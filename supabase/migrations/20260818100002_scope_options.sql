-- Replaces the binary is_scopable flag with an explicit list of valid
-- scope values per permission. Some permissions genuinely have no "own"
-- option (approving your own leave request isn't a thing), and future
-- scope kinds (e.g. a department-based scope) can be introduced without
-- another structural change -- Configuration over Code applied to the
-- scope system itself.
alter table public.permissions add column scope_options text[] not null default '{}';

update public.permissions set scope_options = case
  when key in ('ticket.view', 'ticket.edit') then array['own', 'all']
  when key = 'attendance.view' then array['own', 'all', 'team']
  when key in ('leave.approve', 'shift.manage') then array['all', 'team']
  else '{}'
end;

alter table public.permissions drop column is_scopable;

alter table public.role_permissions drop constraint if exists role_permissions_scope_check;
alter table public.role_permissions add constraint role_permissions_scope_check
  check (scope in ('own', 'all', 'team'));

-- leave.approve and shift.manage used to be flat (unscoped) permissions,
-- so every existing grant has scope = null. Backfill those to 'all' so
-- nobody who already had unrestricted access silently loses it now that
-- the same permission key requires a scope.
update public.role_permissions
set scope = 'all'
where permission_key in ('leave.approve', 'shift.manage') and scope is null;
