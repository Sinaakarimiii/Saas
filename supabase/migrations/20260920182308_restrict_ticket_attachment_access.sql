-- Upload still precedes ticket creation; a file becomes readable only after
-- a valid field value associates it with a ticket visible to the caller.
drop policy if exists "ticket_attachments_select_member" on storage.objects;
create policy "ticket_attachments_select_ticket_view" on storage.objects for select
  to authenticated using (
    bucket_id = 'ticket-attachments'
    and exists (
      select 1 from public.ticket_field_values v
      join public.tickets t on t.id = v.ticket_id
      where (v.value @> jsonb_build_object('storage_path', name)
         or v.value @> jsonb_build_array(jsonb_build_object('storage_path', name)))
        and t.org_id::text = (storage.foldername(name))[1]
        and (
          private.permission_scope(t.org_id, 'ticket.view') = 'all'
          or (private.permission_scope(t.org_id, 'ticket.view') = 'own'
              and t.created_by = auth.uid())
        )
    )
  );

-- Do not let a user attach someone else's known path to a ticket that they
-- can edit: every newly associated path must belong to the caller's upload.
create or replace function private.guard_new_ticket_attachment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_entry jsonb;
  v_path text;
  v_org_id uuid;
  v_old_paths text[] := array[]::text[];
begin
  if auth.role() <> 'authenticated' then return new; end if;

  select org_id into v_org_id from public.tickets where id = new.ticket_id;
  if tg_op = 'UPDATE' and old.ticket_id = new.ticket_id
     and old.form_field_id = new.form_field_id then
    select coalesce(array_agg(x->>'storage_path'), array[]::text[])
      into v_old_paths
    from jsonb_array_elements(case
      when jsonb_typeof(old.value) = 'array' then old.value
      when jsonb_typeof(old.value) = 'object' then jsonb_build_array(old.value)
      else '[]'::jsonb end) x
    where x ? 'storage_path';
  end if;

  for v_entry in select x from jsonb_array_elements(case
      when jsonb_typeof(new.value) = 'array' then new.value
      when jsonb_typeof(new.value) = 'object' then jsonb_build_array(new.value)
      else '[]'::jsonb end) x loop
    v_path := v_entry->>'storage_path';
    if v_path is null or v_path = any(v_old_paths) then continue; end if;
    if v_path not like v_org_id::text || '/' || new.form_field_id::text || '/%'
       or not exists (
         select 1 from storage.objects o
         where o.bucket_id = 'ticket-attachments'
           and o.name = v_path and o.owner_id = auth.uid()::text
       ) then
      raise exception 'Attachment must be uploaded by the acting user for this form field'
        using errcode = '42501';
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function private.guard_new_ticket_attachment() from public, anon, authenticated;

create trigger trg_guard_new_ticket_attachment
  before insert or update of value, ticket_id, form_field_id on public.ticket_field_values
  for each row execute function private.guard_new_ticket_attachment();
