-- Per-org manual override of a day's status (workday / official holiday /
-- unofficial holiday). This sits *on top of* the global, read-only
-- calendar_events.is_holiday dataset + the "every Friday is a holiday" rule
-- computed in src/lib/holidays.ts -- it does not replace them. Absence of a
-- row for a given (org_id, date) means "use the computed default"; a row
-- here always wins. unofficial_holiday only ever comes from this table --
-- there is no automatic source for it.
create table public.calendar_day_status (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  gregorian_date date not null,
  status text not null check (status in ('official_holiday', 'unofficial_holiday', 'workday')),
  note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, gregorian_date)
);

create trigger trg_calendar_day_status_updated_at
  before update on public.calendar_day_status
  for each row execute function public.bump_updated_at();

alter table public.calendar_day_status enable row level security;

-- Every org member can see the override (it drives day coloring for
-- everyone), but only calendar.manage_days can change it.
create policy "calendar_day_status_select_member" on public.calendar_day_status for select
  using (private.is_org_member(org_id));

create policy "calendar_day_status_manage" on public.calendar_day_status for all
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'calendar.manage_days'))
  with check (private.is_org_member(org_id) and private.has_permission(org_id, 'calendar.manage_days'));

grant select, insert, update, delete on public.calendar_day_status to authenticated, service_role;

-- scope_options omitted -- defaults to '{}' (unscoped), same as
-- leave.request/shift.manage-before-scoping: this is an org-wide action,
-- not a per-member/team scope.
insert into public.permissions (key, label_fa, description_fa) values
  ('calendar.manage_days', 'مدیریت وضعیت روزها', 'تغییر یک روز به تعطیل رسمی، تعطیل غیررسمی یا روز کاری');

-- Existing organizations' "مالک" role doesn't automatically pick up
-- permissions added by later migrations (see create_organization() in
-- 20260818100003) -- backfill onto every existing owner role, same logic
-- create_organization() uses (scope = 'all' only if scope_options is
-- non-empty; null otherwise).
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, case when array_length(p.scope_options, 1) > 0 then 'all' else null end
from public.roles r
cross join public.permissions p
where r.is_system = true
  and p.key = 'calendar.manage_days'
on conflict (role_id, permission_key) do nothing;
