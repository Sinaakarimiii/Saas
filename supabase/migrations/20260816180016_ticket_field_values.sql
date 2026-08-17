create table public.ticket_field_values (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.tickets(id),
  form_field_id uuid not null references public.form_fields(id),
  value jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ticket_id, form_field_id)
);

alter table public.ticket_field_values enable row level security;

create policy "ticket_field_values_select_scoped" on public.ticket_field_values for select
  using (
    exists (
      select 1 from public.tickets t
      where t.id = ticket_field_values.ticket_id
        and private.is_org_member(t.org_id)
        and (
          private.permission_scope(t.org_id, 'ticket.view') = 'all'
          or (private.permission_scope(t.org_id, 'ticket.view') = 'own' and t.created_by = (select auth.uid()))
        )
    )
  );

-- Insert is allowed either while creating the ticket (ticket.create) or
-- while editing an existing one (ticket.edit, scoped).
create policy "ticket_field_values_insert_scoped" on public.ticket_field_values for insert
  with check (
    exists (
      select 1 from public.tickets t
      where t.id = ticket_field_values.ticket_id
        and private.is_org_member(t.org_id)
        and (
          private.has_permission(t.org_id, 'ticket.create')
          or private.permission_scope(t.org_id, 'ticket.edit') = 'all'
          or (private.permission_scope(t.org_id, 'ticket.edit') = 'own' and t.created_by = (select auth.uid()))
        )
    )
  );

create policy "ticket_field_values_update_scoped" on public.ticket_field_values for update
  using (
    exists (
      select 1 from public.tickets t
      where t.id = ticket_field_values.ticket_id
        and private.is_org_member(t.org_id)
        and (
          private.permission_scope(t.org_id, 'ticket.edit') = 'all'
          or (private.permission_scope(t.org_id, 'ticket.edit') = 'own' and t.created_by = (select auth.uid()))
        )
    )
  )
  with check (
    exists (
      select 1 from public.tickets t
      where t.id = ticket_field_values.ticket_id
        and private.is_org_member(t.org_id)
        and (
          private.permission_scope(t.org_id, 'ticket.edit') = 'all'
          or (private.permission_scope(t.org_id, 'ticket.edit') = 'own' and t.created_by = (select auth.uid()))
        )
    )
  );

grant select, insert, update on public.ticket_field_values to authenticated;

create trigger trg_ticket_field_values_updated_at
  before update on public.ticket_field_values
  for each row execute function public.bump_updated_at();

-- Logs into audit_log using table_name='tickets' and record_id=ticket_id,
-- so field-value changes show up in the same per-ticket history timeline
-- as ticket status changes -- and with the field's actual Persian label,
-- not the generic "value" column name.
create or replace function public.log_ticket_field_value_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_field_label text;
  v_org_id uuid;
  v_note text;
begin
  if TG_OP = 'UPDATE' and old.value is not distinct from new.value then
    return new;
  end if;

  select ff.label, t.org_id into v_field_label, v_org_id
  from public.form_fields ff
  join public.tickets t on t.id = new.ticket_id
  where ff.id = new.form_field_id;

  v_note := nullif(current_setting('app.audit_note', true), '');

  insert into public.audit_log (org_id, actor_id, table_name, record_id, field_name, old_value, new_value, note, action)
  values (
    v_org_id,
    auth.uid(),
    'tickets',
    new.ticket_id,
    v_field_label,
    case when TG_OP = 'UPDATE' then old.value::text else null end,
    new.value::text,
    v_note,
    case when TG_OP = 'INSERT' then 'insert' else 'update' end
  );

  return new;
end;
$$;

create trigger trg_ticket_field_values_audit
  after insert or update on public.ticket_field_values
  for each row execute function public.log_ticket_field_value_changes();
