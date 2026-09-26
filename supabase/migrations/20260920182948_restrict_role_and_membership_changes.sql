-- Owner explicitly approves non-system roles that member managers may use
-- for invitations. Existing roles start unapproved; no automatic escalation.
alter table public.roles add column manager_invitable boolean not null default false;

drop policy if exists "roles_insert_manager" on public.roles;
drop policy if exists "roles_update_manager" on public.roles;
create policy "roles_insert_owner" on public.roles for insert to authenticated
  with check (private.is_org_owner(org_id) and not is_system);
create policy "roles_update_owner" on public.roles for update to authenticated
  using (private.is_org_owner(org_id) and not is_system)
  with check (private.is_org_owner(org_id) and not is_system);

drop policy if exists "role_permissions_manage" on public.role_permissions;
create policy "role_permissions_owner" on public.role_permissions for all
  to authenticated using (
    exists (select 1 from public.roles r
      where r.id = role_id and not r.is_system and private.is_org_owner(r.org_id))
  ) with check (
    exists (select 1 from public.roles r
      where r.id = role_id and not r.is_system and private.is_org_owner(r.org_id))
  );

create or replace function public.set_role_permissions(p_role_id uuid, p_permissions jsonb)
returns void language plpgsql set search_path = '' as $$
declare
  v_perm jsonb;
begin
  if not exists (
    select 1 from public.roles r
    where r.id = p_role_id and not r.is_system
      and r.deleted_at is null and private.is_org_owner(r.org_id)
  ) then
    raise exception 'Only an active owner can edit this role' using errcode = '42501';
  end if;
  if jsonb_typeof(p_permissions) <> 'array' then
    raise exception 'Permissions must be an array' using errcode = '22023';
  end if;
  delete from public.role_permissions where role_id = p_role_id;
  for v_perm in select value from jsonb_array_elements(p_permissions) loop
    insert into public.role_permissions (role_id, permission_key, scope)
    values (p_role_id, v_perm->>'key', nullif(v_perm->>'scope', ''));
  end loop;
end;
$$;

create or replace function private.guard_member_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_is_owner boolean;
  v_old_owner boolean;
  v_target_owner boolean;
  v_allowed_for_manager boolean;
begin
  if auth.role() <> 'authenticated' then return new; end if;
  v_is_owner := private.is_org_owner(new.org_id);
  select r.is_system and r.name = 'مالک', r.manager_invitable
    into v_target_owner, v_allowed_for_manager
    from public.roles r
    where r.id = new.role_id and r.org_id = new.org_id and r.deleted_at is null;
  if not found then
    raise exception 'Role must be active in this organization' using errcode = '23514';
  end if;
  if new.manager_id is not null and not exists (
    select 1 from public.org_members m
    where m.id = new.manager_id and m.org_id = new.org_id and m.deleted_at is null
  ) then
    raise exception 'Supervisor must be active in this organization' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' then
    if new.invited_by is distinct from auth.uid() or new.deleted_at is not null then
      raise exception 'Invalid membership actor or initial state' using errcode = '42501';
    end if;
    if not v_is_owner and not (
      -- Organization bootstrap inserts its first owner in create_organization.
      (v_target_owner and new.user_id = auth.uid()
       and exists (select 1 from public.organizations o
         where o.id = new.org_id and o.created_by = auth.uid())
       and not exists (select 1 from public.org_members m where m.org_id = new.org_id))
      or (coalesce(private.has_permission(new.org_id, 'org.manage_members'), false)
          and not v_target_owner and v_allowed_for_manager)
    ) then
      raise exception 'Role is not approved for a member-manager invitation'
        using errcode = '42501';
    end if;
  else
    if (to_jsonb(new) - 'role_id' - 'manager_id')
       is distinct from (to_jsonb(old) - 'role_id' - 'manager_id') then
      raise exception 'Membership identity and history cannot be changed'
        using errcode = '42501';
    end if;
    select r.is_system and r.name = 'مالک' into v_old_owner
    from public.roles r where r.id = old.role_id;
    if not v_is_owner and (
      new.role_id is distinct from old.role_id or coalesce(v_old_owner, false)
    ) then
      raise exception 'Only an owner may change roles or the owner record'
        using errcode = '42501';
    end if;
    if coalesce(v_old_owner, false) and not v_target_owner then
      -- Serialize concurrent demotions through one stable org row.
      perform 1 from public.organizations where id = new.org_id for update;
      if not exists (
        select 1 from public.org_members m join public.roles r on r.id = m.role_id
        where m.org_id = new.org_id and m.id <> old.id and m.deleted_at is null
          and r.is_system and r.name = 'مالک'
      ) then
        raise exception 'Cannot remove the last organization owner'
          using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_member_change() from public, anon, authenticated;
create trigger trg_guard_member_change
  before insert or update on public.org_members
  for each row execute function private.guard_member_change();

drop policy if exists "org_members_insert_manager" on public.org_members;
drop policy if exists "org_members_update_manager" on public.org_members;
create policy "org_members_insert_authorized" on public.org_members for insert
  to authenticated with check (
    private.is_org_owner(org_id)
    or (private.has_permission(org_id, 'org.manage_members') and exists (
      select 1 from public.roles r
      where r.id = role_id and r.org_id = org_members.org_id
        and not r.is_system and r.deleted_at is null and r.manager_invitable
    ))
  );
create policy "org_members_update_authorized" on public.org_members for update
  to authenticated using (
    private.is_org_owner(org_id) or private.has_permission(org_id, 'org.manage_members')
  ) with check (
    private.is_org_owner(org_id) or private.has_permission(org_id, 'org.manage_members')
  );
