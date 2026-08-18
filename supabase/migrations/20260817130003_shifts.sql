create table public.shift_templates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  name text not null,
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.shift_templates enable row level security;

create policy "shift_templates_select_member" on public.shift_templates for select
  using (private.is_org_member(org_id));

create policy "shift_templates_manage" on public.shift_templates for all
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'shift.manage'))
  with check (private.is_org_member(org_id) and private.has_permission(org_id, 'shift.manage'));

grant select, insert, update, delete on public.shift_templates to authenticated, service_role;

-- The actual roster: which member works which hours on which day. When
-- created from a template, start_time/end_time/title are copied from it so
-- the assignment can be tweaked afterwards without touching the template
-- (shift_template_id is kept only for traceability -- "this slot came from
-- قالب صبح"). shift_template_id is nullable: a fully ad-hoc shift with no
-- template at all is equally valid, per the org's request.
create table public.shift_assignments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  member_id uuid not null references public.org_members(id),
  shift_template_id uuid references public.shift_templates(id),
  title text not null,
  work_date date not null,
  start_time time not null,
  end_time time not null,
  note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index shift_assignments_member_date_idx
  on public.shift_assignments (member_id, work_date)
  where deleted_at is null;

alter table public.shift_assignments enable row level security;

-- Every org member can see the roster (it's not sensitive -- everyone
-- needs to know who's working when), but only shift.manage can change it.
create policy "shift_assignments_select_member" on public.shift_assignments for select
  using (private.is_org_member(org_id));

create policy "shift_assignments_manage" on public.shift_assignments for all
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'shift.manage'))
  with check (private.is_org_member(org_id) and private.has_permission(org_id, 'shift.manage'));

grant select, insert, update, delete on public.shift_assignments to authenticated, service_role;
