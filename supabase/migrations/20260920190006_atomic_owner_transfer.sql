-- A transaction-local authorization record is written only by the checked
-- transfer RPC. Client writes cannot manufacture either half of a transfer.
create table private.owner_transfer_authorizations (
  transaction_id bigint not null,
  org_id uuid not null,
  actor_id uuid not null,
  from_member_id uuid not null,
  to_member_id uuid not null,
  owner_role_id uuid not null,
  replacement_role_id uuid not null,
  primary key (transaction_id, org_id)
);
alter table private.owner_transfer_authorizations enable row level security;
revoke all on private.owner_transfer_authorizations from public, anon, authenticated;

create or replace function private.guard_ownership_transfer()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_old_owner boolean := false;
  v_new_owner boolean := false;
begin
  if auth.role() <> 'authenticated' then return new; end if;

  select r.is_system and r.name = 'مالک' into v_new_owner
  from public.roles r where r.id = new.role_id and r.org_id = new.org_id;
  if tg_op = 'INSERT' then
    if not coalesce(v_new_owner, false) then return new; end if;
    -- The only direct creation of an owner is organization bootstrap.
    if new.user_id = auth.uid() and exists (
      select 1 from public.organizations o
      where o.id = new.org_id and o.created_by = auth.uid()
    ) and not exists (
      select 1 from public.org_members m where m.org_id = new.org_id
    ) then
      return new;
    end if;
    raise exception 'Owner membership requires an atomic transfer'
      using errcode = '42501';
  end if;

  if old.role_id is not distinct from new.role_id then return new; end if;
  select r.is_system and r.name = 'مالک' into v_old_owner
  from public.roles r where r.id = old.role_id and r.org_id = old.org_id;
  if not coalesce(v_old_owner, false) and not coalesce(v_new_owner, false) then
    return new;
  end if;
  if not exists (
    select 1 from private.owner_transfer_authorizations a
    where a.transaction_id = txid_current() and a.org_id = new.org_id
      and a.actor_id = auth.uid()
      and (
        (new.id = a.to_member_id and old.role_id <> a.owner_role_id
         and new.role_id = a.owner_role_id and not coalesce(v_old_owner, false))
        or
        (new.id = a.from_member_id and old.role_id = a.owner_role_id
         and new.role_id = a.replacement_role_id and coalesce(v_old_owner, false))
      )
  ) then
    raise exception 'Owner role may change only within the transfer RPC'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_ownership_transfer() from public, anon, authenticated;
create trigger trg_guard_ownership_transfer
  before insert or update on public.org_members
  for each row execute function private.guard_ownership_transfer();

create or replace function public.transfer_org_ownership(
  p_org_id uuid,
  p_successor_member_id uuid,
  p_former_owner_role_id uuid
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor_id uuid := auth.uid();
  v_from_member_id uuid;
  v_owner_role_id uuid;
begin
  if v_actor_id is null then
    raise exception 'Sign in before transferring ownership' using errcode = '42501';
  end if;
  -- Serializes concurrent handoffs and makes the owner check fresh after wait.
  perform 1 from public.organizations where id = p_org_id for update;
  if not found then
    raise exception 'Organization not found' using errcode = 'P0002';
  end if;
  select m.id, m.role_id into v_from_member_id, v_owner_role_id
  from public.org_members m
  join public.roles r on r.id = m.role_id and r.org_id = m.org_id
  where m.org_id = p_org_id and m.user_id = v_actor_id
    and m.deleted_at is null and r.deleted_at is null
    and r.is_system and r.name = 'مالک';
  if not found then
    raise exception 'Only an active owner can transfer ownership'
      using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.org_members m
    where m.id = p_successor_member_id and m.org_id = p_org_id
      and m.deleted_at is null and m.id <> v_from_member_id
      and m.role_id <> v_owner_role_id
  ) then
    raise exception 'Successor must be another active non-owner member'
      using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.roles r
    where r.id = p_former_owner_role_id and r.org_id = p_org_id
      and r.deleted_at is null and not r.is_system
  ) then
    raise exception 'Former owner needs an active non-owner role'
      using errcode = '23514';
  end if;

  insert into private.owner_transfer_authorizations (
    transaction_id, org_id, actor_id, from_member_id, to_member_id,
    owner_role_id, replacement_role_id
  ) values (
    txid_current(), p_org_id, v_actor_id, v_from_member_id,
    p_successor_member_id, v_owner_role_id, p_former_owner_role_id
  );
  update public.org_members set role_id = v_owner_role_id
  where id = p_successor_member_id and org_id = p_org_id and deleted_at is null;
  if not found then raise exception 'Successor update had no effect' using errcode = 'P0002'; end if;
  update public.org_members set role_id = p_former_owner_role_id
  where id = v_from_member_id and org_id = p_org_id and deleted_at is null;
  if not found then raise exception 'Former owner update had no effect' using errcode = 'P0002'; end if;
  delete from private.owner_transfer_authorizations
  where transaction_id = txid_current() and org_id = p_org_id;
end;
$$;
revoke execute on function public.transfer_org_ownership(uuid, uuid, uuid)
  from public, anon;
grant execute on function public.transfer_org_ownership(uuid, uuid, uuid)
  to authenticated;

-- Role changes and invitations become part of the trusted audit stream.
create trigger trg_org_members_audit
  after insert or update on public.org_members
  for each row execute function public.log_field_changes();
