-- Only trusted trigger functions may create audit rows. Existing records stay intact.
drop policy if exists "audit_log_insert_member" on public.audit_log;
revoke insert on public.audit_log from authenticated;

create or replace function private.is_org_owner(p_org_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_members m
    join public.roles r on r.id = m.role_id and r.org_id = m.org_id
    where m.org_id = p_org_id and m.user_id = auth.uid()
      and m.deleted_at is null and r.deleted_at is null
      and r.is_system and r.name = 'مالک'
  );
$$;
revoke all on function private.is_org_owner(uuid) from public, anon;
grant execute on function private.is_org_owner(uuid) to authenticated;

drop policy if exists "audit_log_select_member" on public.audit_log;
create policy "audit_log_select_authorized" on public.audit_log for select
  using (
    private.is_org_member(org_id)
    and (
      (table_name = 'tickets' and exists (
        select 1 from public.tickets t
        where t.id = audit_log.record_id and t.org_id = audit_log.org_id
          and (
            private.permission_scope(audit_log.org_id, 'ticket.view') = 'all'
            or (
              private.permission_scope(audit_log.org_id, 'ticket.view') = 'own'
              and t.created_by = auth.uid()
            )
          )
      ))
      or (table_name <> 'tickets' and private.is_org_owner(org_id))
    )
  );

-- Authenticated users may void their own entry once; its historical fields
-- and the actor/timestamp of the void cannot be supplied by the client.
create or replace function private.guard_attendance_history()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.role() <> 'authenticated' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.created_by is distinct from auth.uid()
       or new.voided_at is not null or new.voided_by is not null then
      raise exception 'Invalid attendance actor or void state' using errcode = '42501';
    end if;
  else
    if old.voided_at is not null
       or (to_jsonb(new) - 'voided_at' - 'voided_by')
          is distinct from (to_jsonb(old) - 'voided_at' - 'voided_by')
       or new.voided_at is null then
      raise exception 'Attendance history is immutable; only first void is allowed'
        using errcode = '42501';
    end if;
    new.voided_at := statement_timestamp();
    new.voided_by := auth.uid();
  end if;
  return new;
end;
$$;

create trigger trg_guard_attendance_history
  before insert or update on public.attendance_logs
  for each row execute function private.guard_attendance_history();
