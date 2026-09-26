-- A newly invited account must not gain organization access until its email
-- link has been verified.  Existing memberships retain their active state.
alter table public.org_members
  add column invitation_status text not null default 'active'
  check (invitation_status in ('active', 'pending', 'delivery_failed'));

create or replace function private.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.org_members
    where org_id = p_org_id
      and user_id = auth.uid()
      and deleted_at is null
      and invitation_status = 'active'
  );
$$;

create or replace function private.current_role_id(p_org_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select role_id
  from public.org_members
  where org_id = p_org_id
    and user_id = auth.uid()
    and deleted_at is null
    and invitation_status = 'active'
  limit 1;
$$;

create or replace function private.is_org_owner(p_org_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_members m
    join public.roles r on r.id = m.role_id and r.org_id = m.org_id
    where m.org_id = p_org_id and m.user_id = auth.uid()
      and m.deleted_at is null and m.invitation_status = 'active'
      and r.deleted_at is null and r.is_system and r.name = 'مالک'
  );
$$;

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
  perform 1 from public.organizations where id = p_org_id for update;
  if not found then
    raise exception 'Organization not found' using errcode = 'P0002';
  end if;
  select m.id, m.role_id into v_from_member_id, v_owner_role_id
  from public.org_members m
  join public.roles r on r.id = m.role_id and r.org_id = m.org_id
  where m.org_id = p_org_id and m.user_id = v_actor_id
    and m.deleted_at is null and m.invitation_status = 'active'
    and r.deleted_at is null and r.is_system and r.name = 'مالک';
  if not found then
    raise exception 'Only an active owner can transfer ownership' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.org_members m
    where m.id = p_successor_member_id and m.org_id = p_org_id
      and m.deleted_at is null and m.invitation_status = 'active'
      and m.id <> v_from_member_id and m.role_id <> v_owner_role_id
  ) then
    raise exception 'Successor must be another active non-owner member' using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.roles r
    where r.id = p_former_owner_role_id and r.org_id = p_org_id
      and r.deleted_at is null and not r.is_system
  ) then
    raise exception 'Former owner needs an active non-owner role' using errcode = '23514';
  end if;
  insert into private.owner_transfer_authorizations (
    transaction_id, org_id, actor_id, from_member_id, to_member_id,
    owner_role_id, replacement_role_id
  ) values (
    txid_current(), p_org_id, v_actor_id, v_from_member_id,
    p_successor_member_id, v_owner_role_id, p_former_owner_role_id
  );
  update public.org_members set role_id = v_owner_role_id
  where id = p_successor_member_id and org_id = p_org_id
    and deleted_at is null and invitation_status = 'active';
  if not found then raise exception 'Successor update had no effect' using errcode = 'P0002'; end if;
  update public.org_members set role_id = p_former_owner_role_id
  where id = v_from_member_id and org_id = p_org_id
    and deleted_at is null and invitation_status = 'active';
  if not found then raise exception 'Former owner update had no effect' using errcode = 'P0002'; end if;
  delete from private.owner_transfer_authorizations
  where transaction_id = txid_current() and org_id = p_org_id;
end;
$$;

-- A pending invite must not use the co-member profile policy to discover
-- names or email addresses before it has accepted the invitation.
drop policy if exists "profiles_select_org_comembers" on public.profiles;
create policy "profiles_select_org_comembers" on public.profiles for select
  using (
    exists (
      select 1
      from public.org_members me
      join public.org_members them on them.org_id = me.org_id
      where me.user_id = (select auth.uid())
        and me.deleted_at is null
        and me.invitation_status = 'active'
        and them.user_id = public.profiles.id
        and them.deleted_at is null
        and them.invitation_status = 'active'
    )
  );

-- Auth owns email confirmation.  This trigger only activates memberships
-- created by an authorized invitation after Auth has confirmed that email.
create or replace function private.activate_confirmed_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    update public.org_members
    set invitation_status = 'active'
    where user_id = new.id
      and invitation_status = 'pending'
      and deleted_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_confirmed on auth.users;
create trigger on_auth_user_email_confirmed
  after update of email_confirmed_at on auth.users
  for each row execute function private.activate_confirmed_invitation();
