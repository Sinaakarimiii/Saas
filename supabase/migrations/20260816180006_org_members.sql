create table public.org_members (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  -- References profiles (not auth.users) even though profiles.id IS
  -- auth.users.id 1:1 -- PostgREST can only auto-embed a join
  -- (org_members -> profiles) when there's a direct FK between the two
  -- tables being queried, not a transitive one through auth.users.
  user_id uuid not null references public.profiles(id),
  role_id uuid not null references public.roles(id),
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (org_id, user_id)
);

alter table public.org_members enable row level security;
-- Policies added in 0009, once access-helper functions exist.
