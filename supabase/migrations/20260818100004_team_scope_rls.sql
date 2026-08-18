-- leave_requests: add the "team" branch (an approver whose scope is
-- 'team' can act on anyone in their reporting subtree, at any depth --
-- see is_manager_of). Org-wide catalog management (leave_types) is
-- deliberately restricted to scope='all' only, since a leave *type* isn't
-- tied to any one member the way a *request* is.
drop policy "leave_requests_select_scoped" on public.leave_requests;
create policy "leave_requests_select_scoped" on public.leave_requests for select
  using (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'leave.approve') = 'all'
      or (
        private.permission_scope(org_id, 'leave.approve') = 'team'
        and private.is_manager_of(org_id, member_id)
      )
      or exists (
        select 1 from public.org_members m
        where m.id = leave_requests.member_id and m.user_id = (select auth.uid())
      )
    )
  );

drop policy "leave_requests_review" on public.leave_requests;
create policy "leave_requests_review" on public.leave_requests for update
  using (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'leave.approve') = 'all'
      or (
        private.permission_scope(org_id, 'leave.approve') = 'team'
        and private.is_manager_of(org_id, member_id)
      )
    )
  )
  with check (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'leave.approve') = 'all'
      or (
        private.permission_scope(org_id, 'leave.approve') = 'team'
        and private.is_manager_of(org_id, member_id)
      )
    )
  );

drop policy "leave_types_manage" on public.leave_types;
create policy "leave_types_manage" on public.leave_types for all
  using (private.is_org_member(org_id) and private.permission_scope(org_id, 'leave.approve') = 'all')
  with check (private.is_org_member(org_id) and private.permission_scope(org_id, 'leave.approve') = 'all');

-- attendance_logs: same team branch, for seeing (not recording -- you can
-- only ever record your own) a subordinate's attendance.
drop policy "attendance_logs_select_scoped" on public.attendance_logs;
create policy "attendance_logs_select_scoped" on public.attendance_logs for select
  using (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'attendance.view') = 'all'
      or (
        private.permission_scope(org_id, 'attendance.view') = 'team'
        and private.is_manager_of(org_id, member_id)
      )
      or exists (
        select 1 from public.org_members m
        where m.id = attendance_logs.member_id and m.user_id = (select auth.uid())
      )
    )
  );

-- shift_templates stay scope='all'-only (a template isn't tied to a
-- member); shift_assignments get the team branch since each row belongs
-- to a specific member.
drop policy "shift_templates_manage" on public.shift_templates;
create policy "shift_templates_manage" on public.shift_templates for all
  using (private.is_org_member(org_id) and private.permission_scope(org_id, 'shift.manage') = 'all')
  with check (private.is_org_member(org_id) and private.permission_scope(org_id, 'shift.manage') = 'all');

drop policy "shift_assignments_manage" on public.shift_assignments;
create policy "shift_assignments_manage" on public.shift_assignments for all
  using (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'shift.manage') = 'all'
      or (
        private.permission_scope(org_id, 'shift.manage') = 'team'
        and private.is_manager_of(org_id, member_id)
      )
    )
  )
  with check (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'shift.manage') = 'all'
      or (
        private.permission_scope(org_id, 'shift.manage') = 'team'
        and private.is_manager_of(org_id, member_id)
      )
    )
  );

drop policy "attendance_event_types_manage" on public.attendance_event_types;
create policy "attendance_event_types_manage" on public.attendance_event_types for all
  using (
    private.is_org_member(org_id)
    and private.permission_scope(org_id, 'shift.manage') = 'all'
    and is_system = false
  )
  with check (
    private.is_org_member(org_id)
    and private.permission_scope(org_id, 'shift.manage') = 'all'
    and is_system = false
  );
