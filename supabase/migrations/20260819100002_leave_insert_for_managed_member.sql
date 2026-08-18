-- Someone who can approve leave (all or team scope) can now also create and
-- immediately finalize a leave request on a subordinate's behalf -- e.g. a
-- supervisor logging a leave they agreed to over the phone, without forcing
-- a pointless self-approval loop. Self-service (leave.request, own row
-- only) keeps working exactly as before; this only adds a second way in.
drop policy if exists "leave_requests_insert_own" on public.leave_requests;

create policy "leave_requests_insert_own_or_managed" on public.leave_requests for insert
  with check (
    private.is_org_member(org_id)
    and (
      (
        private.has_permission(org_id, 'leave.request')
        and exists (
          select 1 from public.org_members m
          where m.id = leave_requests.member_id and m.user_id = (select auth.uid())
        )
      )
      or private.permission_scope(org_id, 'leave.approve') = 'all'
      or (
        private.permission_scope(org_id, 'leave.approve') = 'team'
        and private.is_manager_of(org_id, leave_requests.member_id)
      )
    )
  );
