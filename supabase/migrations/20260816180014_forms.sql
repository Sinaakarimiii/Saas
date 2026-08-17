create table public.form_templates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  name text not null,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.form_templates enable row level security;

create policy "form_templates_select_member" on public.form_templates for select
  using (private.is_org_member(org_id));

create policy "form_templates_manage" on public.form_templates for all
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'form.manage'))
  with check (private.is_org_member(org_id) and private.has_permission(org_id, 'form.manage'));

grant select, insert, update, delete on public.form_templates to authenticated;

create table public.form_fields (
  id uuid primary key default gen_random_uuid(),
  form_template_id uuid not null references public.form_templates(id),
  key text not null,
  label text not null,
  field_type text not null check (field_type in ('text', 'number', 'date_jalali', 'select', 'file')),
  options jsonb,
  is_required boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Partial (not a plain table UNIQUE) so a soft-deleted field's key can be
-- reused by a new field -- otherwise "deleting" a field and re-adding one
-- with the same label would wrongly fail as a duplicate.
create unique index form_fields_template_key_active_idx
  on public.form_fields (form_template_id, key)
  where deleted_at is null;

alter table public.form_fields enable row level security;

create policy "form_fields_select_member" on public.form_fields for select
  using (
    exists (
      select 1 from public.form_templates ft
      where ft.id = form_fields.form_template_id
        and private.is_org_member(ft.org_id)
    )
  );

create policy "form_fields_manage" on public.form_fields for all
  using (
    exists (
      select 1 from public.form_templates ft
      where ft.id = form_fields.form_template_id
        and private.is_org_member(ft.org_id)
        and private.has_permission(ft.org_id, 'form.manage')
    )
  )
  with check (
    exists (
      select 1 from public.form_templates ft
      where ft.id = form_fields.form_template_id
        and private.is_org_member(ft.org_id)
        and private.has_permission(ft.org_id, 'form.manage')
    )
  );

grant select, insert, update, delete on public.form_fields to authenticated;
