insert into storage.buckets (id, name, public)
values ('ticket-attachments', 'ticket-attachments', false)
on conflict (id) do nothing;

-- Objects are stored under `{org_id}/{ticket_id}/{form_field_id}/{filename}`
-- so access can be checked against org membership from the path alone.
create policy "ticket_attachments_select_member" on storage.objects for select
  using (
    bucket_id = 'ticket-attachments'
    and private.is_org_member(((storage.foldername(name))[1])::uuid)
  );

create policy "ticket_attachments_insert_member" on storage.objects for insert
  with check (
    bucket_id = 'ticket-attachments'
    and private.is_org_member(((storage.foldername(name))[1])::uuid)
  );
