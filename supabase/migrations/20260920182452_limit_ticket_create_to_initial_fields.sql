-- A create-only caller may write fields only when creating a new ticket.
-- The narrowly scoped RPC always creates its own ticket and validates fields;
-- direct Data API inserts into another ticket require ticket.edit.
drop policy if exists "ticket_field_values_insert_scoped" on public.ticket_field_values;
create policy "ticket_field_values_insert_scoped" on public.ticket_field_values for insert
  to authenticated with check (
    exists (
      select 1 from public.tickets t
      where t.id = ticket_field_values.ticket_id
        and private.is_org_member(t.org_id)
        and (
          private.permission_scope(t.org_id, 'ticket.edit') = 'all'
          or (private.permission_scope(t.org_id, 'ticket.edit') = 'own'
              and t.created_by = auth.uid())
        )
    )
  );

create or replace function public.create_ticket(
  p_org_id uuid, p_form_template_id uuid, p_title text, p_field_values jsonb
)
returns public.tickets language plpgsql security definer set search_path = '' as $$
declare
  v_ticket public.tickets;
  v_item jsonb;
  v_field_id uuid;
begin
  if auth.uid() is null or not coalesce(private.is_org_member(p_org_id), false)
     or not coalesce(private.has_permission(p_org_id, 'ticket.create'), false) then
    raise exception 'Ticket creation is not allowed' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.form_templates f
    where f.id = p_form_template_id and f.org_id = p_org_id
  ) then
    raise exception 'Form does not belong to the organization' using errcode = '23514';
  end if;
  if p_field_values is not null and jsonb_typeof(p_field_values) <> 'array' then
    raise exception 'Ticket fields must be an array' using errcode = '22023';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_field_values, '[]'::jsonb)) loop
    v_field_id := (v_item->>'form_field_id')::uuid;
    if not exists (
      select 1 from public.form_fields f
      where f.id = v_field_id and f.form_template_id = p_form_template_id
    ) then
      raise exception 'Field does not belong to the selected form' using errcode = '23514';
    end if;
  end loop;
  insert into public.tickets (org_id, form_template_id, title, created_by)
  values (p_org_id, p_form_template_id, nullif(trim(p_title), ''), auth.uid())
  returning * into v_ticket;
  for v_item in select value from jsonb_array_elements(coalesce(p_field_values, '[]'::jsonb)) loop
    insert into public.ticket_field_values (ticket_id, form_field_id, value)
    values (v_ticket.id, (v_item->>'form_field_id')::uuid, v_item->'value');
  end loop;
  return v_ticket;
end;
$$;
revoke execute on function public.create_ticket(uuid, uuid, text, jsonb) from public, anon;
grant execute on function public.create_ticket(uuid, uuid, text, jsonb) to authenticated;

-- A filtered update of a nonexistent/inaccessible ticket must not report
-- success through the void-returning RPC.
create or replace function public.update_ticket_status(
  p_ticket_id uuid,
  p_status text,
  p_note text default null
)
returns void language plpgsql set search_path = '' as $$
begin
  perform set_config('app.audit_note', coalesce(p_note, ''), true);
  update public.tickets set status = p_status where id = p_ticket_id;
  if not found then
    raise exception 'Ticket missing or not editable' using errcode = 'P0002';
  end if;
end;
$$;
