create table public.leave_types (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  name text not null,
  unit text not null default 'day' check (unit in ('day', 'hour')),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.leave_types enable row level security;

create policy "leave_types_select_member" on public.leave_types for select
  using (private.is_org_member(org_id));

-- Managing the leave-type catalog is folded into leave.approve rather than
-- a separate permission key -- keeps the permission list from growing for
-- something this small; whoever can approve leave can also define what
-- kinds of leave exist.
create policy "leave_types_manage" on public.leave_types for all
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'leave.approve'))
  with check (private.is_org_member(org_id) and private.has_permission(org_id, 'leave.approve'));

grant select, insert, update, delete on public.leave_types to authenticated, service_role;

create table public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  tracking_code text unique,
  member_id uuid not null references public.org_members(id),
  leave_type_id uuid not null references public.leave_types(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ends_at > starts_at)
);

alter table public.leave_requests enable row level security;

-- Same own/all scoping shape as tickets: leave.approve sees every request
-- in the org, leave.request alone only sees requests for the member row
-- that belongs to the calling user.
create policy "leave_requests_select_scoped" on public.leave_requests for select
  using (
    private.is_org_member(org_id)
    and (
      private.has_permission(org_id, 'leave.approve')
      or exists (
        select 1 from public.org_members m
        where m.id = leave_requests.member_id and m.user_id = (select auth.uid())
      )
    )
  );

create policy "leave_requests_insert_own" on public.leave_requests for insert
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'leave.request')
    and exists (
      select 1 from public.org_members m
      where m.id = leave_requests.member_id and m.user_id = (select auth.uid())
    )
  );

-- Approve/reject (and correcting an earlier decision) requires leave.approve.
create policy "leave_requests_review" on public.leave_requests for update
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'leave.approve'))
  with check (private.is_org_member(org_id) and private.has_permission(org_id, 'leave.approve'));

grant select, insert, update on public.leave_requests to authenticated, service_role;

create trigger trg_leave_requests_tracking_code
  before insert on public.leave_requests
  for each row execute function public.assign_tracking_code('leave_request');

create trigger trg_leave_requests_updated_at
  before update on public.leave_requests
  for each row execute function public.bump_updated_at();

create trigger trg_leave_requests_audit
  after insert or update on public.leave_requests
  for each row execute function public.log_field_changes();
