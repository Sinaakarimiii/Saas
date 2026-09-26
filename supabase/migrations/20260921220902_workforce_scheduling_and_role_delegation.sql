-- Role delegation is permission-based, but bounded by a role hierarchy so a
-- role administrator cannot promote themselves or edit a peer/owner role.
alter table public.roles
  add column system_key text,
  add column management_rank smallint not null default 10
    check (management_rank between 0 and 100);

update public.roles
set system_key = 'owner', management_rank = 100
where is_system and name = 'مالک';

create unique index roles_system_key_per_org_idx
  on public.roles (org_id, system_key)
  where system_key is not null and deleted_at is null;

create or replace function private.is_org_owner(p_org_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.org_members m
    join public.roles r on r.id = m.role_id and r.org_id = m.org_id
    where m.org_id = p_org_id and m.user_id = auth.uid()
      and m.deleted_at is null and m.invitation_status = 'active'
      and r.deleted_at is null and r.system_key = 'owner'
  );
$$;

create or replace function private.current_role_rank(p_org_id uuid)
returns smallint language sql stable security definer set search_path = '' as $$
  select r.management_rank
  from public.org_members m
  join public.roles r on r.id = m.role_id and r.org_id = m.org_id
  where m.org_id = p_org_id and m.user_id = auth.uid()
    and m.deleted_at is null and m.invitation_status = 'active'
    and r.deleted_at is null
  limit 1;
$$;

create or replace function private.can_manage_role(p_org_id uuid, p_role_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_permission(p_org_id, 'org.manage_roles') and exists (
    select 1 from public.roles target
    where target.id = p_role_id and target.org_id = p_org_id
      and target.deleted_at is null and target.system_key is null
      and target.management_rank < coalesce(private.current_role_rank(p_org_id), -1)
  );
$$;

create or replace function private.can_delegate_permission(p_org_id uuid, p_permission_key text, p_scope text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.org_members m
    join public.role_permissions rp on rp.role_id = m.role_id
    where m.org_id = p_org_id and m.user_id = auth.uid()
      and m.deleted_at is null and m.invitation_status = 'active'
      and rp.permission_key = p_permission_key
      and (p_scope is null or rp.scope = 'all' or rp.scope = p_scope)
  );
$$;

create or replace function private.has_permission(p_org_id uuid, p_permission_key text, p_scope text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.role_permissions rp
    where rp.role_id = private.current_role_id(p_org_id)
      and rp.permission_key = p_permission_key
      and (rp.scope = 'all' or rp.scope = p_scope)
  );
$$;

revoke all on function private.current_role_rank(uuid), private.can_manage_role(uuid, uuid),
  private.can_delegate_permission(uuid, text, text)
  from public, anon;
grant execute on function private.current_role_rank(uuid), private.can_manage_role(uuid, uuid)
  to authenticated;
revoke all on function private.has_permission(uuid, text, text) from public, anon;
grant execute on function private.has_permission(uuid, text, text) to authenticated;

create or replace function private.guard_role_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and new.is_system and new.name = 'مالک'
     and new.system_key is null
     and exists (select 1 from public.organizations o where o.id = new.org_id and o.created_by = auth.uid())
     and not exists (select 1 from public.roles r where r.org_id = new.org_id) then
    -- create_organization() is the sole bootstrap path for the owner role.
    new.system_key := 'owner';
    new.management_rank := 100;
    return new;
  end if;
  if new.is_system or new.system_key is not null then
    raise exception 'System roles are not mutable through the API' using errcode = '42501';
  end if;
  if new.manager_invitable and not private.is_org_owner(new.org_id) then
    raise exception 'Only an owner can approve a role for invitations' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_role_write() from public, anon, authenticated;
create trigger trg_guard_role_write before insert or update on public.roles
  for each row execute function private.guard_role_write();

drop policy if exists "roles_insert_owner" on public.roles;
drop policy if exists "roles_update_owner" on public.roles;
create policy "roles_insert_role_manager" on public.roles for insert to authenticated
  with check (
    not is_system and system_key is null
    and private.has_permission(org_id, 'org.manage_roles')
    and management_rank < coalesce(private.current_role_rank(org_id), -1)
  );
create policy "roles_update_role_manager" on public.roles for update to authenticated
  using (private.can_manage_role(org_id, id))
  with check (
    not is_system and system_key is null
    and management_rank < coalesce(private.current_role_rank(org_id), -1)
  );

drop policy if exists "role_permissions_owner" on public.role_permissions;
drop policy if exists "role_permissions_role_manager" on public.role_permissions;
revoke insert, update, delete on public.role_permissions from authenticated;

create or replace function public.set_role_permissions(p_role_id uuid, p_permissions jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_perm jsonb; v_org_id uuid; v_manager_invitable boolean;
  v_old_permissions text; v_new_permissions text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_permissions) <> 'array' then
    raise exception 'Permissions must be an array' using errcode = '22023';
  end if;
  select org_id, manager_invitable into v_org_id, v_manager_invitable
  from public.roles where id = p_role_id and deleted_at is null;
  if v_org_id is null or not private.can_manage_role(v_org_id, p_role_id) then
    raise exception 'Role cannot be managed by the current user' using errcode = '42501';
  end if;
  if v_manager_invitable and not private.is_org_owner(v_org_id) then
    raise exception 'Only an owner can change an invitation-approved role' using errcode = '42501';
  end if;
  for v_perm in select value from jsonb_array_elements(p_permissions) loop
    if not exists (
      select 1 from public.permissions p
      where p.key = v_perm->>'key'
        and (
          (coalesce(array_length(p.scope_options, 1), 0) = 0 and nullif(v_perm->>'scope', '') is null)
          or nullif(v_perm->>'scope', '') = any(p.scope_options)
        )
    ) then
      raise exception 'Invalid permission or scope' using errcode = '22023';
    end if;
    if not private.can_delegate_permission(v_org_id, v_perm->>'key', nullif(v_perm->>'scope', '')) then
      raise exception 'Permission exceeds the current user''s authority' using errcode = '42501';
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('key', permission_key, 'scope', scope)
    order by permission_key, scope), '[]'::jsonb)::text into v_old_permissions
  from public.role_permissions where role_id = p_role_id;
  delete from public.role_permissions where role_id = p_role_id;
  insert into public.role_permissions (role_id, permission_key, scope)
  select p_role_id, value->>'key', nullif(value->>'scope', '')
  from jsonb_array_elements(p_permissions);
  select coalesce(jsonb_agg(jsonb_build_object('key', permission_key, 'scope', scope)
    order by permission_key, scope), '[]'::jsonb)::text into v_new_permissions
  from public.role_permissions where role_id = p_role_id;
  if v_old_permissions is distinct from v_new_permissions then
    insert into public.audit_log (org_id, actor_id, table_name, record_id, field_name, old_value, new_value)
    values (v_org_id, auth.uid(), 'roles', p_role_id, 'permissions', v_old_permissions, v_new_permissions);
  end if;
end;
$$;
revoke all on function public.set_role_permissions(uuid, jsonb) from public, anon;
grant execute on function public.set_role_permissions(uuid, jsonb) to authenticated;

create or replace function public.save_role(
  p_org_id uuid,
  p_role_id uuid,
  p_name text,
  p_management_rank smallint,
  p_permissions jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_role_id uuid; v_actor_rank smallint; v_invitable boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;
  if nullif(btrim(p_name), '') is null or p_management_rank not between 0 and 99 then
    raise exception 'Invalid role data' using errcode = '22023';
  end if;
  v_actor_rank := private.current_role_rank(p_org_id);
  if not private.has_permission(p_org_id, 'org.manage_roles')
     or p_management_rank >= coalesce(v_actor_rank, -1) then
    raise exception 'Role exceeds the current user''s authority' using errcode = '42501';
  end if;
  if p_role_id is null then
    insert into public.roles (org_id, name, management_rank)
    values (p_org_id, btrim(p_name), p_management_rank)
    returning id into v_role_id;
  else
    select manager_invitable into v_invitable
    from public.roles where id = p_role_id and org_id = p_org_id and deleted_at is null;
    if not found or not private.can_manage_role(p_org_id, p_role_id) then
      raise exception 'Role cannot be managed by the current user' using errcode = '42501';
    end if;
    if v_invitable and not private.is_org_owner(p_org_id) then
      raise exception 'Only an owner can change an invitation-approved role' using errcode = '42501';
    end if;
    update public.roles set name = btrim(p_name), management_rank = p_management_rank
    where id = p_role_id and org_id = p_org_id;
    v_role_id := p_role_id;
  end if;
  perform public.set_role_permissions(v_role_id, p_permissions);
  return v_role_id;
end;
$$;
revoke all on function public.save_role(uuid, uuid, text, smallint, jsonb) from public, anon;
grant execute on function public.save_role(uuid, uuid, text, smallint, jsonb) to authenticated;

create trigger trg_roles_audit after insert or update on public.roles
  for each row execute function public.log_field_changes();

-- Workforce scheduling: templates describe a reusable shift; a pattern turns
-- it into dated assignments. Existing ad-hoc assignments remain valid.
alter table public.shift_templates
  add column color_hex text not null default '#2563EB'
    check (color_hex ~ '^#[0-9A-Fa-f]{6}$');

alter table public.shift_assignments
  add column color_hex text not null default '#2563EB'
    check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  add column source text not null default 'manual'
    check (source in ('manual', 'pattern'));

update public.shift_assignments a
set color_hex = t.color_hex
from public.shift_templates t
where a.shift_template_id = t.id;

create table public.shift_patterns (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  shift_template_id uuid not null,
  valid_from date not null,
  valid_to date,
  weekdays smallint[] not null,
  exclude_fridays boolean not null default true,
  exclude_official_holidays boolean not null default true,
  exclude_unofficial_holidays boolean not null default false,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (valid_to is null or valid_to >= valid_from),
  check (cardinality(weekdays) between 1 and 7),
  check (weekdays <@ array[0,1,2,3,4,5,6]::smallint[]),
  foreign key (org_id, shift_template_id)
    references public.shift_templates(org_id, id)
);
alter table public.shift_patterns add unique (org_id, id);
create index shift_patterns_org_dates_idx
  on public.shift_patterns (org_id, valid_from, valid_to)
  where deleted_at is null;

create table public.shift_pattern_members (
  org_id uuid not null references public.organizations(id),
  pattern_id uuid not null,
  member_id uuid not null,
  foreign key (org_id, pattern_id) references public.shift_patterns(org_id, id) on delete cascade,
  foreign key (org_id, member_id) references public.org_members(org_id, id),
  primary key (pattern_id, member_id)
);

alter table public.shift_assignments
  add column shift_pattern_id uuid,
  add constraint shift_assignment_pattern_org_fk
    foreign key (org_id, shift_pattern_id) references public.shift_patterns(org_id, id),
  add constraint shift_assignment_pattern_source_check
    check ((source = 'pattern') = (shift_pattern_id is not null));
create unique index shift_assignment_pattern_occurrence_idx
  on public.shift_assignments (shift_pattern_id, member_id, work_date)
  where deleted_at is null and source = 'pattern';

alter table public.org_members
  add column work_mode text not null default 'unspecified'
    check (work_mode in ('unspecified', 'shift', 'fixed'));

create table public.fixed_work_schedules (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  member_id uuid not null,
  weekday smallint not null check (weekday between 0 and 6),
  start_time time not null,
  end_time time not null,
  valid_from date not null default current_date,
  valid_to date,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (valid_to is null or valid_to >= valid_from),
  foreign key (org_id, member_id) references public.org_members(org_id, id)
);

alter table public.shift_patterns enable row level security;
alter table public.shift_pattern_members enable row level security;
alter table public.fixed_work_schedules enable row level security;

create policy "shift_patterns_select_member" on public.shift_patterns for select to authenticated
  using (private.is_org_member(org_id));
create policy "shift_patterns_manage" on public.shift_patterns for all to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'shift.manage', 'all'))
  with check (private.is_org_member(org_id) and private.has_permission(org_id, 'shift.manage', 'all'));
create policy "shift_pattern_members_select_member" on public.shift_pattern_members for select to authenticated
  using (private.is_org_member(org_id));
create policy "shift_pattern_members_manage" on public.shift_pattern_members for all to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'shift.manage', 'all'))
  with check (private.is_org_member(org_id) and private.has_permission(org_id, 'shift.manage', 'all'));
create policy "fixed_work_schedules_select_member" on public.fixed_work_schedules for select to authenticated
  using (private.is_org_member(org_id));
create policy "fixed_work_schedules_manage" on public.fixed_work_schedules for all to authenticated
  using (private.is_org_member(org_id) and (
    private.has_permission(org_id, 'shift.manage', 'all')
    or (private.has_permission(org_id, 'shift.manage', 'team') and private.is_manager_of(org_id, member_id))
  ))
  with check (private.is_org_member(org_id) and (
    private.has_permission(org_id, 'shift.manage', 'all')
    or (private.has_permission(org_id, 'shift.manage', 'team') and private.is_manager_of(org_id, member_id))
  ));

grant select, insert, update, delete on public.shift_patterns, public.shift_pattern_members,
  public.fixed_work_schedules to authenticated;

-- Existing ownership and membership triggers predate system_key and work_mode.
-- Replace their name-based checks so the authorization model has one stable key.
create or replace function private.guard_ownership_transfer()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_old_owner boolean := false; v_new_owner boolean := false;
begin
  if auth.role() is distinct from 'authenticated' then return new; end if;
  select r.system_key = 'owner' into v_new_owner
  from public.roles r where r.id = new.role_id and r.org_id = new.org_id;
  if tg_op = 'INSERT' then
    if not coalesce(v_new_owner, false) then return new; end if;
    if new.user_id = auth.uid() and exists (
      select 1 from public.organizations o where o.id = new.org_id and o.created_by = auth.uid()
    ) and not exists (select 1 from public.org_members m where m.org_id = new.org_id) then return new; end if;
    raise exception 'Owner membership requires an atomic transfer' using errcode = '42501';
  end if;
  if old.role_id is not distinct from new.role_id then return new; end if;
  select r.system_key = 'owner' into v_old_owner
  from public.roles r where r.id = old.role_id and r.org_id = old.org_id;
  if not coalesce(v_old_owner, false) and not coalesce(v_new_owner, false) then return new; end if;
  if not exists (
    select 1 from private.owner_transfer_authorizations a
    where a.transaction_id = txid_current() and a.org_id = new.org_id and a.actor_id = auth.uid()
      and ((new.id = a.to_member_id and old.role_id <> a.owner_role_id and new.role_id = a.owner_role_id
            and not coalesce(v_old_owner, false))
        or (new.id = a.from_member_id and old.role_id = a.owner_role_id
            and new.role_id = a.replacement_role_id and coalesce(v_old_owner, false)))
  ) then
    raise exception 'Owner role may change only within the transfer RPC' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function private.guard_member_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_is_owner boolean; v_old_owner boolean; v_target_owner boolean;
  v_allowed_for_manager boolean; v_can_manage_members boolean; v_can_manage_work_mode boolean;
begin
  if auth.role() is distinct from 'authenticated' then return new; end if;
  v_is_owner := private.is_org_owner(new.org_id);
  v_can_manage_members := private.has_permission(new.org_id, 'org.manage_members');
  select r.system_key = 'owner', r.manager_invitable into v_target_owner, v_allowed_for_manager
  from public.roles r where r.id = new.role_id and r.org_id = new.org_id and r.deleted_at is null;
  if not found then raise exception 'Role must be active in this organization' using errcode = '23514'; end if;
  if new.manager_id is not null and not exists (
    select 1 from public.org_members m where m.id = new.manager_id and m.org_id = new.org_id
      and m.deleted_at is null and m.invitation_status = 'active'
  ) then raise exception 'Supervisor must be active in this organization' using errcode = '23514'; end if;
  if tg_op = 'INSERT' then
    if new.invited_by is distinct from auth.uid() or new.deleted_at is not null then
      raise exception 'Invalid membership actor or initial state' using errcode = '42501';
    end if;
    if not v_is_owner and not (
      (v_target_owner and new.user_id = auth.uid() and exists (
        select 1 from public.organizations o where o.id = new.org_id and o.created_by = auth.uid()
      ) and not exists (select 1 from public.org_members m where m.org_id = new.org_id))
      or (v_can_manage_members and not v_target_owner and v_allowed_for_manager)
    ) then raise exception 'Role is not approved for a member-manager invitation' using errcode = '42501'; end if;
  else
    if (to_jsonb(new) - 'role_id' - 'manager_id' - 'work_mode')
       is distinct from (to_jsonb(old) - 'role_id' - 'manager_id' - 'work_mode') then
      raise exception 'Membership identity and history cannot be changed' using errcode = '42501';
    end if;
    select r.system_key = 'owner' into v_old_owner from public.roles r where r.id = old.role_id;
    if not v_is_owner and (new.role_id is distinct from old.role_id or coalesce(v_old_owner, false)) then
      raise exception 'Only an owner may change roles or the owner record' using errcode = '42501';
    end if;
    if not v_is_owner and new.manager_id is distinct from old.manager_id and not v_can_manage_members then
      raise exception 'Only a member manager may change a supervisor' using errcode = '42501';
    end if;
    v_can_manage_work_mode := v_is_owner or v_can_manage_members
      or private.has_permission(new.org_id, 'shift.manage', 'all')
      or (private.has_permission(new.org_id, 'shift.manage', 'team') and private.is_manager_of(new.org_id, new.id));
    if new.work_mode is distinct from old.work_mode and not v_can_manage_work_mode then
      raise exception 'Work mode cannot be changed by the current user' using errcode = '42501';
    end if;
    if coalesce(v_old_owner, false) and not v_target_owner then
      perform 1 from public.organizations where id = new.org_id for update;
      if not exists (
        select 1 from public.org_members m join public.roles r on r.id = m.role_id
        where m.org_id = new.org_id and m.id <> old.id and m.deleted_at is null
          and r.system_key = 'owner'
      ) then raise exception 'Cannot remove the last organization owner' using errcode = '23514'; end if;
    end if;
  end if;
  return new;
end;
$$;

-- Backfill only after the updated membership guard accepts this new column.
-- Migration execution has no end-user JWT and remains a privileged operation.
update public.org_members m set work_mode = 'shift'
where exists (
  select 1 from public.shift_assignments s
  where s.member_id = m.id and s.deleted_at is null
);

drop policy if exists "org_members_update_authorized" on public.org_members;
create policy "org_members_update_authorized" on public.org_members for update to authenticated
  using (private.is_org_owner(org_id) or private.has_permission(org_id, 'org.manage_members')
    or private.has_permission(org_id, 'shift.manage', 'all')
    or (private.has_permission(org_id, 'shift.manage', 'team') and private.is_manager_of(org_id, id)))
  with check (private.is_org_owner(org_id) or private.has_permission(org_id, 'org.manage_members')
    or private.has_permission(org_id, 'shift.manage', 'all')
    or (private.has_permission(org_id, 'shift.manage', 'team') and private.is_manager_of(org_id, id)));

create or replace function public.transfer_org_ownership(
  p_org_id uuid, p_successor_member_id uuid, p_former_owner_role_id uuid
)
returns void language plpgsql security definer set search_path = '' as $$
declare v_actor_id uuid := auth.uid(); v_from_member_id uuid; v_owner_role_id uuid;
begin
  if v_actor_id is null then raise exception 'Sign in before transferring ownership' using errcode = '42501'; end if;
  perform 1 from public.organizations where id = p_org_id for update;
  if not found then raise exception 'Organization not found' using errcode = 'P0002'; end if;
  select m.id, m.role_id into v_from_member_id, v_owner_role_id from public.org_members m
  join public.roles r on r.id = m.role_id and r.org_id = m.org_id
  where m.org_id = p_org_id and m.user_id = v_actor_id and m.deleted_at is null
    and m.invitation_status = 'active' and r.deleted_at is null and r.system_key = 'owner';
  if not found then raise exception 'Only an active owner can transfer ownership' using errcode = '42501'; end if;
  if not exists (select 1 from public.org_members m where m.id = p_successor_member_id and m.org_id = p_org_id
    and m.deleted_at is null and m.invitation_status = 'active' and m.id <> v_from_member_id and m.role_id <> v_owner_role_id) then
    raise exception 'Successor must be another active non-owner member' using errcode = '23514'; end if;
  if not exists (select 1 from public.roles r where r.id = p_former_owner_role_id and r.org_id = p_org_id
    and r.deleted_at is null and r.system_key is null) then
    raise exception 'Former owner needs an active non-owner role' using errcode = '23514'; end if;
  insert into private.owner_transfer_authorizations (transaction_id, org_id, actor_id, from_member_id, to_member_id, owner_role_id, replacement_role_id)
  values (txid_current(), p_org_id, v_actor_id, v_from_member_id, p_successor_member_id, v_owner_role_id, p_former_owner_role_id);
  update public.org_members set role_id = v_owner_role_id where id = p_successor_member_id and org_id = p_org_id and deleted_at is null and invitation_status = 'active';
  if not found then raise exception 'Successor update had no effect' using errcode = 'P0002'; end if;
  update public.org_members set role_id = p_former_owner_role_id where id = v_from_member_id and org_id = p_org_id and deleted_at is null and invitation_status = 'active';
  if not found then raise exception 'Former owner update had no effect' using errcode = 'P0002'; end if;
  delete from private.owner_transfer_authorizations where transaction_id = txid_current() and org_id = p_org_id;
end;
$$;
