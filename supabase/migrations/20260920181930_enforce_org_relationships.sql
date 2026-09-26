-- Each composite FK checks both identity and organization. NOT VALID plus
-- VALIDATE rejects inconsistent historical data without changing that data.
alter table public.roles add constraint roles_org_id_id_key unique (org_id, id);
alter table public.org_members add constraint org_members_org_id_id_key unique (org_id, id);
alter table public.form_templates add constraint form_templates_org_id_id_key unique (org_id, id);
alter table public.shift_templates add constraint shift_templates_org_id_id_key unique (org_id, id);
alter table public.leave_types add constraint leave_types_org_id_id_key unique (org_id, id);
alter table public.attendance_event_types add constraint attendance_event_types_org_id_id_key unique (org_id, id);

alter table public.org_members add constraint org_members_role_same_org
  foreign key (org_id, role_id) references public.roles(org_id, id) not valid;
alter table public.org_members add constraint org_members_manager_same_org
  foreign key (org_id, manager_id) references public.org_members(org_id, id) not valid;
alter table public.tickets add constraint tickets_form_same_org
  foreign key (org_id, form_template_id) references public.form_templates(org_id, id) not valid;
alter table public.shift_assignments add constraint shifts_member_same_org
  foreign key (org_id, member_id) references public.org_members(org_id, id) not valid;
alter table public.shift_assignments add constraint shifts_template_same_org
  foreign key (org_id, shift_template_id) references public.shift_templates(org_id, id) not valid;
alter table public.leave_requests add constraint leave_member_same_org
  foreign key (org_id, member_id) references public.org_members(org_id, id) not valid;
alter table public.leave_requests add constraint leave_type_same_org
  foreign key (org_id, leave_type_id) references public.leave_types(org_id, id) not valid;
alter table public.attendance_logs add constraint attendance_member_same_org
  foreign key (org_id, member_id) references public.org_members(org_id, id) not valid;
alter table public.attendance_logs add constraint attendance_type_same_org
  foreign key (org_id, event_type_id) references public.attendance_event_types(org_id, id) not valid;

alter table public.org_members validate constraint org_members_role_same_org;
alter table public.org_members validate constraint org_members_manager_same_org;
alter table public.tickets validate constraint tickets_form_same_org;
alter table public.shift_assignments validate constraint shifts_member_same_org;
alter table public.shift_assignments validate constraint shifts_template_same_org;
alter table public.leave_requests validate constraint leave_member_same_org;
alter table public.leave_requests validate constraint leave_type_same_org;
alter table public.attendance_logs validate constraint attendance_member_same_org;
alter table public.attendance_logs validate constraint attendance_type_same_org;

-- Keep one FK path per relation for PostgREST embeddings. The validated
-- composite constraints replace these weaker single-column references.
alter table public.org_members drop constraint org_members_role_id_fkey;
alter table public.org_members drop constraint org_members_manager_id_fkey;
alter table public.tickets drop constraint tickets_form_template_id_fkey;
alter table public.shift_assignments drop constraint shift_assignments_member_id_fkey;
alter table public.shift_assignments drop constraint shift_assignments_shift_template_id_fkey;
alter table public.leave_requests drop constraint leave_requests_member_id_fkey;
alter table public.leave_requests drop constraint leave_requests_leave_type_id_fkey;
alter table public.attendance_logs drop constraint attendance_logs_member_id_fkey;
alter table public.attendance_logs drop constraint attendance_logs_event_type_id_fkey;

-- The field's form must match the ticket's form on both insert and update.
-- Reparenting an existing field or ticket could otherwise invalidate values.
create or replace function private.guard_ticket_field_form()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and (old.ticket_id is distinct from new.ticket_id
      or old.form_field_id is distinct from new.form_field_id) then
    raise exception 'Ticket field association cannot be moved'
      using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.tickets t
    join public.form_fields f on f.form_template_id = t.form_template_id
    where t.id = new.ticket_id and f.id = new.form_field_id
  ) then
    raise exception 'Ticket field does not belong to the ticket form'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

-- Validate historical field values before installing the new invariant.
do $$
begin
  if exists (
    select 1 from public.ticket_field_values v
    join public.tickets t on t.id = v.ticket_id
    join public.form_fields f on f.id = v.form_field_id
    where f.form_template_id <> t.form_template_id
  ) then
    raise exception 'Historical ticket fields reference another form; inspect data before migration'
      using errcode = '23514';
  end if;
end;
$$;

create trigger trg_ticket_field_form
  before insert or update of ticket_id, form_field_id on public.ticket_field_values
  for each row execute function private.guard_ticket_field_form();

create or replace function private.guard_form_reparent()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.form_template_id is distinct from new.form_template_id then
    raise exception 'Form association cannot be changed; create a new field or ticket'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger trg_form_field_no_reparent
  before update of form_template_id on public.form_fields
  for each row execute function private.guard_form_reparent();
create trigger trg_ticket_no_reparent
  before update of form_template_id on public.tickets
  for each row execute function private.guard_form_reparent();
