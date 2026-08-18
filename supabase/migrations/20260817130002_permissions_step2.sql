insert into public.permissions (key, label_fa, description_fa, is_scopable) values
  ('shift.manage', 'مدیریت شیفت‌ها', 'تعریف قالب شیفت و برنامه‌ریزی شیفت افراد', false),
  ('leave.request', 'ثبت درخواست مرخصی', 'ثبت درخواست مرخصی برای خودم', false),
  ('leave.approve', 'تایید مرخصی', 'تایید یا رد درخواست مرخصی و مدیریت انواع مرخصی', false),
  ('attendance.record', 'ثبت حضور', 'ثبت رویدادهای حضور برای خودم', false),
  ('attendance.view', 'دیدن حضور و غیاب', 'مشاهده‌ی لاگ حضور', true);

-- Existing organizations' "مالک" role was populated at org-creation time from
-- whatever the permissions catalog looked like back then (see
-- create_organization() in 0010) -- it doesn't automatically pick up
-- permissions added by later migrations. Backfill the 5 new ones onto
-- every existing owner role, same as create_organization() would.
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, case when p.is_scopable then 'all' else null end
from public.roles r
cross join public.permissions p
where r.is_system = true
  and p.key in ('shift.manage', 'leave.request', 'leave.approve', 'attendance.record', 'attendance.view')
on conflict (role_id, permission_key) do nothing;
