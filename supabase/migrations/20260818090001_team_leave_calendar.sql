-- Lets any org member see WHO is on approved leave and WHEN, without
-- exposing the requester's private note or the approver's review_note --
-- leave_requests itself stays scoped to "my own" vs "leave.approve"
-- (see 0004_leave.sql), this is a deliberately narrow, privacy-safe
-- read path for the shared team calendar.
create or replace function public.team_leave_calendar(p_org_id uuid, p_from date, p_to date)
returns table (
  member_id uuid,
  member_name text,
  leave_type_name text,
  starts_at timestamptz,
  ends_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    lr.member_id,
    coalesce(p.full_name, p.email),
    lt.name,
    lr.starts_at,
    lr.ends_at
  from public.leave_requests lr
  join public.org_members om on om.id = lr.member_id
  join public.profiles p on p.id = om.user_id
  join public.leave_types lt on lt.id = lr.leave_type_id
  where lr.org_id = p_org_id
    and lr.status = 'approved'
    and lr.deleted_at is null
    and private.is_org_member(p_org_id)
    and lr.starts_at < (p_to + 1)::timestamptz
    and lr.ends_at >= p_from::timestamptz;
$$;

grant execute on function public.team_leave_calendar(uuid, date, date) to authenticated;
