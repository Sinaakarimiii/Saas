-- Available/allocated stock is not a customer's original device. An issued unit
-- can return for a new repair after its documented replacement case has closed.
-- Keep the stock issue and the old case unchanged; custody re-entry is validated
-- separately by record_repair_device_custody_baseline against the old receipt.
create or replace function private.guard_replacement_stock_as_original() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_stock public.repair_replacement_stock;
begin
 if new.verified_device_id is null then return new; end if;
 select * into v_stock from public.repair_replacement_stock
  where org_id=new.org_id and device_id=new.verified_device_id;
 if not found then return new; end if;
 if v_stock.status<>'issued' or v_stock.allocated_case_id=new.id
  or not exists(
   select 1 from public.repair_cases previous_case
   join public.repair_delivery_receipts receipt
    on receipt.org_id=previous_case.org_id and receipt.case_id=previous_case.id
   join public.repair_replacement_executions execution
    on execution.org_id=previous_case.org_id and execution.case_id=previous_case.id
   where previous_case.org_id=new.org_id and previous_case.id=v_stock.allocated_case_id
    and previous_case.stage='closed' and previous_case.closed_at is not null
    and receipt.id=v_stock.issued_receipt_id and receipt.device_id=new.verified_device_id
    and receipt.received_at=v_stock.issued_at
    and execution.plan_id=v_stock.allocated_plan_id
    and execution.replacement_device_id=new.verified_device_id
  ) then
  raise exception 'REPLACEMENT_STOCK_NOT_ORIGINAL' using errcode='23514';
 end if;
 return new;
end; $$;
revoke all on function private.guard_replacement_stock_as_original() from public,anon,authenticated;
