-- Creates a ticket and all of its initial field values in one call/one
-- transaction, so the tracking code, the "insert" audit_log entries, and
-- the field values all land together. Runs as the caller (not definer),
-- so the tickets/ticket_field_values RLS policies from 0015/0016 still
-- gate this normally.
create or replace function public.create_ticket(
  p_org_id uuid,
  p_form_template_id uuid,
  p_title text,
  p_field_values jsonb -- array of {"form_field_id": uuid, "value": any}
)
returns public.tickets
language plpgsql
set search_path = ''
as $$
declare
  v_ticket public.tickets;
  v_item jsonb;
begin
  insert into public.tickets (org_id, form_template_id, title, created_by)
  values (p_org_id, p_form_template_id, nullif(trim(p_title), ''), auth.uid())
  returning * into v_ticket;

  for v_item in select * from jsonb_array_elements(coalesce(p_field_values, '[]'::jsonb)) loop
    insert into public.ticket_field_values (ticket_id, form_field_id, value)
    values (v_ticket.id, (v_item ->> 'form_field_id')::uuid, v_item -> 'value');
  end loop;

  return v_ticket;
end;
$$;

grant execute on function public.create_ticket(uuid, uuid, text, jsonb) to authenticated;

-- Sets the optional audit note (if any) and the new value in the same
-- transaction, so the trigger in 0016 can attach the note to the log row
-- it writes for this exact change.
create or replace function public.update_ticket_field_value(
  p_ticket_id uuid,
  p_form_field_id uuid,
  p_value jsonb,
  p_note text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('app.audit_note', coalesce(p_note, ''), true);

  insert into public.ticket_field_values (ticket_id, form_field_id, value)
  values (p_ticket_id, p_form_field_id, p_value)
  on conflict (ticket_id, form_field_id) do update set value = excluded.value;
end;
$$;

grant execute on function public.update_ticket_field_value(uuid, uuid, jsonb, text) to authenticated;

create or replace function public.update_ticket_status(
  p_ticket_id uuid,
  p_status text,
  p_note text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('app.audit_note', coalesce(p_note, ''), true);

  update public.tickets set status = p_status where id = p_ticket_id;
end;
$$;

grant execute on function public.update_ticket_status(uuid, text, text) to authenticated;
