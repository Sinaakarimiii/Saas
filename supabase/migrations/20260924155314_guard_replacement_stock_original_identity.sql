-- A stock unit must never be admitted as a customer's original repair device.
create function private.guard_replacement_stock_as_original() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.verified_device_id is not null and exists(
  select 1 from public.repair_replacement_stock s
  where s.org_id=new.org_id and s.device_id=new.verified_device_id
 ) then raise exception 'REPLACEMENT_STOCK_NOT_ORIGINAL' using errcode='23514'; end if;
 return new;
end; $$;
revoke all on function private.guard_replacement_stock_as_original() from public,anon,authenticated;
create trigger repair_stock_not_original before insert or update of verified_device_id on public.repair_cases
for each row execute function private.guard_replacement_stock_as_original();
