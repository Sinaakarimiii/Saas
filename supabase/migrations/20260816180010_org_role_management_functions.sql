-- Creates a new organization, its automatic "مالک" (Owner) role with every
-- current permission, and makes the calling user its first member. This is
-- SECURITY DEFINER because, before this runs, the caller is not yet a
-- member of any org (has_permission()/is_org_member() would fail on the
-- direct table policies) -- this function is the one deliberate bootstrap
-- exception.
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

  return v_org;
end;
$$;

grant execute on function public.create_organization(text) to authenticated;

-- Replaces a role's whole permission set in one atomic call (used by the
-- role editor "save" button). Runs as the caller (not definer) so the
-- normal role_permissions RLS policy (org.manage_roles + not is_system)
-- still applies.
create or replace function public.set_role_permissions(p_role_id uuid, p_permissions jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_perm jsonb;
begin
  delete from public.role_permissions where role_id = p_role_id;

  for v_perm in select * from jsonb_array_elements(p_permissions) loop
    insert into public.role_permissions (role_id, permission_key, scope)
    values (p_role_id, v_perm ->> 'key', nullif(v_perm ->> 'scope', ''));
  end loop;
end;
$$;

grant execute on function public.set_role_permissions(uuid, jsonb) to authenticated;
