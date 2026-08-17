-- Data model for "جانشینی" (delegation) only. Nothing reads this table yet
-- to change what a user can see/do -- that logic + its UI are built in the
-- step that actually needs delegation. See ROADMAP step scoping.
create table public.delegations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  delegator_member_id uuid not null references public.org_members(id),
  delegate_member_id uuid not null references public.org_members(id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  deleted_at timestamptz,
  check (ends_at > starts_at),
  check (delegator_member_id <> delegate_member_id)
);

alter table public.delegations enable row level security;

create policy "delegations_select_member" on public.delegations for select
  using (private.is_org_member(org_id));

grant select on public.delegations to authenticated;
