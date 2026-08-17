create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  actor_id uuid references auth.users(id),
  acted_at timestamptz not null default now(),
  table_name text not null,
  record_id uuid not null,
  field_name text,
  old_value text,
  new_value text,
  note text,
  action text not null default 'update' check (action in ('insert', 'update', 'delete'))
);

alter table public.audit_log enable row level security;

create policy "audit_log_select_member" on public.audit_log for select
  using (private.is_org_member(org_id));

-- Only INSERT is allowed via policy, and only INSERT is granted at the
-- privilege level below -- there is deliberately no update/delete policy.
create policy "audit_log_insert_member" on public.audit_log for insert
  with check (private.is_org_member(org_id));

grant select, insert on public.audit_log to authenticated;

-- Belt and suspenders: even service_role (which bypasses RLS) and the
-- table owner acting through a future bug cannot UPDATE/DELETE audit rows,
-- because the privilege itself is revoked at the Postgres level, not just
-- gated by a policy. Nobody -- not even "admin" -- can edit or delete a
-- log entry once written.
revoke update, delete on public.audit_log from authenticated, anon, service_role, public;

-- Generic field-diff logger. Attach as `after insert or update` on any
-- table that has org_id + id columns; it will log one row per changed
-- column (skipping bookkeeping columns), reading an optional note from the
-- `app.audit_note` session setting (see update_ticket_field_value/
-- update_ticket_status in 0017 for how the note gets set in the same
-- transaction as the write).
create or replace function public.log_field_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_key text;
  v_note text;
begin
  v_note := nullif(current_setting('app.audit_note', true), '');

  if TG_OP = 'INSERT' then
    insert into public.audit_log (org_id, actor_id, table_name, record_id, note, action)
    values (new.org_id, auth.uid(), TG_TABLE_NAME, new.id, v_note, 'insert');
    return new;
  end if;

  v_old := to_jsonb(old);
  v_new := to_jsonb(new);

  for v_key in select jsonb_object_keys(v_new) loop
    if v_key in ('id', 'org_id', 'created_at', 'updated_at') then
      continue;
    end if;
    if (v_old -> v_key) is distinct from (v_new -> v_key) then
      insert into public.audit_log (org_id, actor_id, table_name, record_id, field_name, old_value, new_value, note, action)
      values (
        new.org_id, auth.uid(), TG_TABLE_NAME, new.id, v_key,
        v_old ->> v_key, v_new ->> v_key, v_note, 'update'
      );
    end if;
  end loop;

  return new;
end;
$$;
