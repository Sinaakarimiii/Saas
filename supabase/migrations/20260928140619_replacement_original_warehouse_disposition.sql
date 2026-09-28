-- User policy: accepted warehouse custody completes the repair case disposition.
-- Refurbishing/parts processing remains a separate warehouse operation, never implied done.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.replacement.warehouse_receive','تعیین تکلیف دستگاه اولیه در انبار','ثبت دریافت دستگاه اولیه برای بازسازی یا قطعات توسط مسئول مقصد','{}') on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select id,'repair.replacement.warehouse_receive',null from public.roles
 where is_system and name='مالک' and deleted_at is null on conflict(role_id,permission_key) do nothing;
create table public.repair_replacement_warehouse_receipts (
 id uuid primary key default gen_random_uuid(), org_id uuid not null, case_id uuid not null,
 execution_id uuid not null, original_device_id uuid not null, transfer_id uuid not null,
 disposition text not null check(disposition in ('refurbish_received','parts_received')),
 location text not null, received_by uuid not null references auth.users(id),
 receipt_reference text not null, receipt_evidence text not null,
 condition_note text not null check(length(btrim(condition_note)) between 1 and 500),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(org_id,case_id), unique(org_id,transfer_id), unique(org_id,case_id,id),
 foreign key(org_id,case_id,execution_id) references public.repair_replacement_executions(org_id,case_id,id),
 foreign key(org_id,original_device_id) references public.repair_devices(org_id,id),
 foreign key(org_id,transfer_id) references public.repair_device_custody_transfers(org_id,id)
);
alter table public.repair_replacement_warehouse_receipts enable row level security;
create policy replacement_warehouse_view on public.repair_replacement_warehouse_receipts for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_replacement_warehouse_receipts from public,anon,authenticated;
grant select on public.repair_replacement_warehouse_receipts to authenticated;

create function public.record_replacement_warehouse_receipt(
 p_org_id uuid,p_case_id uuid,p_transfer_id uuid,p_expected_version integer,p_idempotency_key uuid,p_condition_note text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_execution public.repair_replacement_executions;
 v_transfer public.repair_device_custody_transfers; v_position public.repair_device_custody_positions;
 v_saved private.repair_command_receipts; v_hash text; v_response jsonb; v_id uuid; v_disposition text; v_previous jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.replacement.warehouse_receive') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or p_idempotency_key is null or p_transfer_id is null
  or length(btrim(coalesce(p_condition_note,''))) not between 1 and 500 then
  raise exception 'INVALID_WAREHOUSE_RECEIPT' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'transfer',p_transfer_id,'version',p_expected_version,'condition',btrim(p_condition_note))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.warehouse.receive:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='replacement.warehouse.receive' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 perform private.assert_replacement_issued_ready(p_org_id,p_case_id);
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 v_disposition:=case v_execution.original_disposition_pending when 'refurbish_proposed' then 'refurbish_received'
  when 'parts_proposed' then 'parts_received' else null end;
 if v_disposition is null then raise exception 'WAREHOUSE_PLAN_REQUIRED' using errcode='23514'; end if;
 select * into v_transfer from public.repair_device_custody_transfers where org_id=p_org_id and case_id=p_case_id and id=p_transfer_id for update;
 select * into v_position from public.repair_device_custody_positions where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.device_id is null or v_transfer.id is null or v_transfer.device_id<>v_case.verified_device_id or v_transfer.status<>'accepted'
  or v_transfer.resolved_at<v_execution.executed_at or v_transfer.destination_user_id<>v_actor
  or v_transfer.resolved_by<>v_actor or v_position.holder_kind<>'staff' or v_position.case_id<>p_case_id
  or v_position.custodian_user_id is distinct from v_actor or v_position.location<>v_transfer.destination_location
  or v_position.confirmed_at<>v_transfer.resolved_at then
  raise exception 'WAREHOUSE_ACCEPTED_TRANSFER_REQUIRED' using errcode='23514'; end if;
 select to_jsonb(w) into v_previous from public.repair_replacement_warehouse_receipts w
  where org_id=p_org_id and case_id=p_case_id;
 insert into public.repair_replacement_warehouse_receipts(org_id,case_id,execution_id,original_device_id,transfer_id,
  disposition,location,received_by,receipt_reference,receipt_evidence,condition_note)
 values(p_org_id,p_case_id,v_execution.id,v_case.verified_device_id,p_transfer_id,v_disposition,v_position.location,v_actor,
  v_transfer.resolution_reference,v_transfer.resolution_evidence,btrim(p_condition_note))
 on conflict(org_id,case_id) do update set execution_id=excluded.execution_id,
  transfer_id=excluded.transfer_id, disposition=excluded.disposition, location=excluded.location,
  received_by=excluded.received_by,receipt_reference=excluded.receipt_reference,receipt_evidence=excluded.receipt_evidence,
  condition_note=excluded.condition_note,recorded_at=clock_timestamp()
 where repair_replacement_warehouse_receipts.transfer_id<>excluded.transfer_id
 returning id into v_id;
 if v_id is null then raise exception 'WAREHOUSE_RECEIPT_ALREADY_CURRENT' using errcode='23514'; end if;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'custody_accepted',v_actor,jsonb_build_object('deviceRole','original','warehouseReceiptId',v_id,
  'disposition',v_disposition,'transferId',p_transfer_id,'deviceId',v_case.verified_device_id,'reference',v_transfer.resolution_reference,'previousReceipt',v_previous,'currentReceipt',
  (select to_jsonb(w) from public.repair_replacement_warehouse_receipts w where w.id=v_id)));
 v_response:=jsonb_build_object('caseId',p_case_id,'warehouseReceiptId',v_id,'version',v_case.version+1);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.warehouse.receive',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_replacement_warehouse_receipt(uuid,uuid,uuid,integer,uuid,text) from public,anon;
grant execute on function public.record_replacement_warehouse_receipt(uuid,uuid,uuid,integer,uuid,text) to authenticated;

create or replace function private.assert_replacement_close_ready(p_org_id uuid,p_case_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_check uuid; v_return public.repair_replacement_original_returns; v_warehouse public.repair_replacement_warehouse_receipts;
begin
 v_check:=private.assert_replacement_issued_ready(p_org_id,p_case_id);
 select * into v_warehouse from public.repair_replacement_warehouse_receipts where org_id=p_org_id and case_id=p_case_id;
 if v_warehouse.id is not null then
  if not exists(select 1 from public.repair_replacement_executions x
   join public.repair_cases c on c.org_id=x.org_id and c.id=x.case_id
   join public.repair_device_custody_positions pos on pos.org_id=x.org_id and pos.device_id=x.original_device_id
   join public.repair_device_custody_transfers t on t.org_id=x.org_id and t.id=v_warehouse.transfer_id
   where x.org_id=p_org_id and x.case_id=p_case_id and x.id=v_warehouse.execution_id
    and x.id=(select id from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1)
    and x.original_device_id=v_warehouse.original_device_id and c.verified_device_id=v_warehouse.original_device_id
    and v_warehouse.disposition=case x.original_disposition_pending when 'parts_proposed' then 'parts_received' when 'refurbish_proposed' then 'refurbish_received' end
    and pos.case_id=p_case_id and pos.holder_kind='staff' and pos.location=v_warehouse.location
    and pos.custodian_user_id=v_warehouse.received_by and pos.confirmed_at=t.resolved_at
    and t.case_id=p_case_id and t.device_id=v_warehouse.original_device_id and t.status='accepted'
    and t.destination_user_id=v_warehouse.received_by and t.resolved_by=v_warehouse.received_by
    and t.destination_location=v_warehouse.location and t.resolution_reference=v_warehouse.receipt_reference
    and t.resolution_evidence=v_warehouse.receipt_evidence and t.resolved_at>=x.executed_at) then
   raise exception 'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' using errcode='23514'; end if;
  return v_warehouse.id;
 end if;
 select * into v_return from public.repair_replacement_original_returns where org_id=p_org_id and case_id=p_case_id;
 if v_return.id is null or not exists(select 1 from public.repair_replacement_executions x
  join public.repair_device_custody_positions pos on pos.org_id=x.org_id and pos.device_id=x.original_device_id
  join public.repair_cases c on c.org_id=x.org_id and c.id=x.case_id
  join public.repair_delivery_receipts r on r.org_id=x.org_id and r.case_id=x.case_id
  where x.org_id=p_org_id and x.case_id=p_case_id and x.id=v_return.execution_id
   and x.original_disposition_pending='return_to_customer' and x.original_device_id=v_return.original_device_id
   and x.id=(select id from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1)
   and c.verified_device_id=v_return.original_device_id and pos.case_id=p_case_id
   and pos.holder_kind='recipient' and pos.external_reference=v_return.receipt_reference
   and v_return.returned_at>=r.received_at and v_return.recipient_name=r.recipient_name
   and v_return.recipient_role=r.recipient_role and v_return.authority_reference is not distinct from r.authority_reference) then
  raise exception 'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' using errcode='23514'; end if;
 return v_return.id;
end; $$;
revoke all on function private.assert_replacement_close_ready(uuid,uuid) from public,anon,authenticated;
create or replace function public.close_replacement_case(p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_receipt public.repair_delivery_receipts;
 v_saved private.repair_command_receipts; v_hash text; v_check_id uuid; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_idempotency_key is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'case.close') then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 then raise exception 'INVALID_TRANSITION_INPUT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,'transitionCode','T09')::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.close:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='transition' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_replacement_close_ready(p_org_id,p_case_id);
 select * into v_receipt from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id;
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_cases set stage='closed',stage_entered_at=v_at,closed_at=v_at,version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,pg_catalog.jsonb_build_object('transitionCode','T09','from','delivery','to','closed',
  'outcome',coalesce((select 'replaced_original_'||disposition from public.repair_replacement_warehouse_receipts where org_id=p_org_id and case_id=p_case_id),'replaced_original_returned'),'deliveryReceiptId',v_receipt.id,
  'originalReturnId',(select id from public.repair_replacement_original_returns where org_id=p_org_id and case_id=p_case_id),
  'warehouseReceiptId',(select id from public.repair_replacement_warehouse_receipts where org_id=p_org_id and case_id=p_case_id)));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','closed','version',v_case.version+1,'transitionCode','T09');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.close_replacement_case(uuid,uuid,integer,uuid) from public,anon;
grant execute on function public.close_replacement_case(uuid,uuid,integer,uuid) to authenticated;

