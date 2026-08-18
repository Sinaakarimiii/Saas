-- create_organization() referenced permissions.is_scopable, which
-- 20260818100002 replaced with scope_options -- update it to match, same
-- create-or-replace pattern used every other time org bootstrap needed to
-- track a schema change (see 20260817130005 for the attendance version).
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

  for v_permission in select key, scope_options from public.permissions loop
    insert into public.role_permissions (role_id, permission_key, scope)
    values (
      v_role_id,
      v_permission.key,
      case when array_length(v_permission.scope_options, 1) > 0 then 'all' else null end
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
