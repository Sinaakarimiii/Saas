-- Fixed catalog of every permission the platform code actually checks
-- somewhere. This list is defined by code (new features add new rows via
-- migration), but WHICH ROLE HAS WHICH PERMISSION is fully configurable
-- per organization via role_permissions (see 0007).
create table public.permissions (
  key text primary key,
  label_fa text not null,
  description_fa text,
  is_scopable boolean not null default false
);

alter table public.permissions enable row level security;

create policy "permissions_select_all" on public.permissions for select
  using (true);

grant select on public.permissions to authenticated;

insert into public.permissions (key, label_fa, description_fa, is_scopable) values
  ('org.manage_members', 'مدیریت اعضا', 'دعوت و حذف اعضای سازمان', false),
  ('org.manage_roles', 'مدیریت نقش‌ها', 'ساخت، ویرایش و تعیین دسترسی نقش‌ها', false),
  ('form.manage', 'مدیریت فرم‌ها', 'ساخت و ویرایش فرم‌های تیکت', false),
  ('ticket.create', 'ساخت تیکت', 'ثبت تیکت جدید', false),
  ('ticket.view', 'دیدن تیکت‌ها', 'مشاهده‌ی فهرست و جزییات تیکت‌ها', true),
  ('ticket.edit', 'ویرایش تیکت‌ها', 'تغییر وضعیت و مقادیر فیلدهای تیکت', true);
