-- An unresolved return discrepancy keeps the device out of further transfers.
create function private.guard_repair_custody_release() returns trigger language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.repair_device_custody_discrepancies d
 where d.org_id=new.org_id and d.device_id=new.device_id and d.status='open')
 then raise exception 'CUSTODY_DISCREPANCY_OPEN' using errcode='23514'; end if;
 return new;
end; $$;
create trigger repair_custody_release_guard before insert on public.repair_device_custody_transfers
for each row execute function private.guard_repair_custody_release();
