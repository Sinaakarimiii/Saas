create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  tracking_code text unique,
  form_template_id uuid not null references public.form_templates(id),
  title text,
  status text not null default 'open' check (status in ('open', 'closed')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.tickets enable row level security;

create policy "tickets_select_scoped" on public.tickets for select
  using (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'ticket.view') = 'all'
      or (private.permission_scope(org_id, 'ticket.view') = 'own' and created_by = (select auth.uid()))
    )
  );

create policy "tickets_insert_creator" on public.tickets for insert
  with check (
    private.is_org_member(org_id)
    and private.has_permission(org_id, 'ticket.create')
    and created_by = (select auth.uid())
  );

create policy "tickets_update_scoped" on public.tickets for update
  using (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'ticket.edit') = 'all'
      or (private.permission_scope(org_id, 'ticket.edit') = 'own' and created_by = (select auth.uid()))
    )
  )
  with check (
    private.is_org_member(org_id)
    and (
      private.permission_scope(org_id, 'ticket.edit') = 'all'
      or (private.permission_scope(org_id, 'ticket.edit') = 'own' and created_by = (select auth.uid()))
    )
  );

grant select, insert, update on public.tickets to authenticated;

create or replace function public.bump_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_tickets_tracking_code
  before insert on public.tickets
  for each row execute function public.assign_tracking_code('ticket');

create trigger trg_tickets_updated_at
  before update on public.tickets
  for each row execute function public.bump_updated_at();

create trigger trg_tickets_audit
  after insert or update on public.tickets
  for each row execute function public.log_field_changes();
