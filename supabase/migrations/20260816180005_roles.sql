create table public.roles (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  name text not null,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (org_id, name)
);

alter table public.roles enable row level security;
-- Policies added in 0009, once access-helper functions exist.
