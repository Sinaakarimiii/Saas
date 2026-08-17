-- These functions are SECURITY DEFINER, owned by the migration role which
-- owns org_members/role_permissions, so they read those tables directly
-- without going back through RLS (which would otherwise recurse into the
-- very policies that call these functions). This is the standard Supabase
-- pattern for RLS helper functions.

create or replace function private.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.org_members
    where org_id = p_org_id
      and user_id = auth.uid()
      and deleted_at is null
  );
$$;

create or replace function private.current_role_id(p_org_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select role_id from public.org_members
  where org_id = p_org_id
    and user_id = auth.uid()
    and deleted_at is null
  limit 1;
$$;

-- Whether the current user's role in this org has been granted this
-- permission at all (works for both scopable and non-scopable permissions).
create or replace function private.has_permission(p_org_id uuid, p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.role_permissions rp
    where rp.role_id = private.current_role_id(p_org_id)
      and rp.permission_key = p_permission_key
  );
$$;

-- The scope ('own' / 'all') the current user's role has for a scopable
-- permission in this org, or null if not granted / not applicable.
create or replace function private.permission_scope(p_org_id uuid, p_permission_key text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select rp.scope from public.role_permissions rp
  where rp.role_id = private.current_role_id(p_org_id)
    and rp.permission_key = p_permission_key
  limit 1;
$$;

grant usage on schema private to authenticated;
grant execute on function private.is_org_member(uuid) to authenticated;
grant execute on function private.current_role_id(uuid) to authenticated;
grant execute on function private.has_permission(uuid, text) to authenticated;
grant execute on function private.permission_scope(uuid, text) to authenticated;

-- Thin public wrappers so the client SDK (and server actions) can ask
-- "can I do X in org Y" without needing direct access to the private schema.
create or replace function public.has_permission(p_org_id uuid, p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission(p_org_id, p_permission_key);
$$;

create or replace function public.permission_scope(p_org_id uuid, p_permission_key text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select private.permission_scope(p_org_id, p_permission_key);
$$;

grant execute on function public.has_permission(uuid, text) to authenticated;
grant execute on function public.permission_scope(uuid, text) to authenticated;
