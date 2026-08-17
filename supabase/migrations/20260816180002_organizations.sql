create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.organizations enable row level security;
-- Policies are added later in 0009, once the org-membership helper
-- functions exist. Until then this table is fully locked down (deny-all).
