create table public.attendance_event_types (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  name text not null,
  kind text not null default 'other' check (kind in ('clock_in', 'clock_out', 'other')),
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (org_id, name)
);

alter table public.attendance_event_types enable row level security;

create policy "attendance_event_types_select_member" on public.attendance_event_types for select
  using (private.is_org_member(org_id));

-- The two system types ("شروع کار"/"پایان کار", is_system=true, seeded by
-- create_organization()) can't be renamed/removed through the API, same
-- pattern as the "مالک" role in 0009 -- they're what makes an open shift
-- computable at all.
create policy "attendance_event_types_manage" on public.attendance_event_types for all
  using (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'shift.manage')
    and is_system = false
  )
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'shift.manage')
    and is_system = false
  );

grant select, insert, update, delete on public.attendance_event_types to authenticated, service_role;

-- Append-only log of every attendance click. A mistaken entry is voided
-- (voided_at set), never edited/deleted -- same "nothing is deleted"
-- principle as audit_log, just scoped to this one table instead of a
-- platform-wide guarantee, since attendance corrections are a normal HR
-- workflow (unlike the audit log itself, which stays truly immutable).
create table public.attendance_logs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  member_id uuid not null references public.org_members(id),
  event_type_id uuid not null references public.attendance_event_types(id),
  occurred_at timestamptz not null default now(),
  note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references auth.users(id)
);

create index attendance_logs_member_occurred_idx
  on public.attendance_logs (member_id, occurred_at);

alter table public.attendance_logs enable row level security;

-- Seeing your OWN log is always allowed (you need it just to know whether
-- you're currently clocked in) -- attendance.view is only about seeing
-- *other* members' logs.
create policy "attendance_logs_select_scoped" on public.attendance_logs for select
  using (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'attendance.view') = 'all'
      or exists (
        select 1 from public.org_members m
        where m.id = attendance_logs.member_id and m.user_id = (select auth.uid())
      )
    )
  );

create policy "attendance_logs_insert_own" on public.attendance_logs for insert
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'attendance.record')
    and exists (
      select 1 from public.org_members m
      where m.id = attendance_logs.member_id and m.user_id = (select auth.uid())
    )
  );

-- Voiding a mistaken entry: same permission as recording it, own entries
-- only (nobody edits someone else's attendance history this way).
create policy "attendance_logs_void_own" on public.attendance_logs for update
  using (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'attendance.record')
    and exists (
      select 1 from public.org_members m
      where m.id = attendance_logs.member_id and m.user_id = (select auth.uid())
    )
  )
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'attendance.record')
    and exists (
      select 1 from public.org_members m
      where m.id = attendance_logs.member_id and m.user_id = (select auth.uid())
    )
  );

grant select, insert, update on public.attendance_logs to authenticated, service_role;

-- Extend create_organization() to also seed the two system attendance
-- event types every org needs -- same create-or-replace pattern used
-- whenever a later migration needs to add to what org bootstrap does.
create or replace function public.create_organization(p_name text)
returns public.organizations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org public.organizations;
  v_role_id uuid;
  v_permission record;
begin
  if coalesce(trim(p_name), '') = '' then
    raise exception 'نام سازمان نمی‌تواند خالی باشد';
  end if;

  insert into public.organizations (name, created_by)
  values (trim(p_name), auth.uid())
  returning * into v_org;

  insert into public.roles (org_id, name, is_system)
  values (v_org.id, 'مالک', true)
  returning id into v_role_id;

  for v_permission in select key, is_scopable from public.permissions loop
    insert into public.role_permissions (role_id, permission_key, scope)
    values (
      v_role_id,
      v_permission.key,
      case when v_permission.is_scopable then 'all' else null end
    );
  end loop;

  insert into public.org_members (org_id, user_id, role_id, invited_by)
  values (v_org.id, auth.uid(), v_role_id, auth.uid());

  insert into public.attendance_event_types (org_id, name, kind, is_system) values
    (v_org.id, 'شروع کار', 'clock_in', true),
    (v_org.id, 'پایان کار', 'clock_out', true);

  return v_org;
end;
$$;

-- Existing organizations (created before this migration) never got the two
-- system event types -- backfill them the same way 0002 backfilled
-- permissions onto existing owner roles.
insert into public.attendance_event_types (org_id, name, kind, is_system)
select o.id, v.name, v.kind, true
from public.organizations o
cross join (values ('شروع کار', 'clock_in'), ('پایان کار', 'clock_out')) as v(name, kind)
where not exists (
  select 1 from public.attendance_event_types aet
  where aet.org_id = o.id and aet.is_system = true and aet.kind = v.kind
);
