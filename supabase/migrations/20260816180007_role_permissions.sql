-- Which permissions a role has, and with what scope ('own' vs 'all') for
-- permissions that support scoping. This is the table product admins edit
-- when they build a custom role in the UI.
create table public.role_permissions (
  role_id uuid not null references public.roles(id),
  permission_key text not null references public.permissions(key),
  scope text check (scope in ('own', 'all')),
  primary key (role_id, permission_key)
);

alter table public.role_permissions enable row level security;
-- Policies added in 0009, once access-helper functions exist.
