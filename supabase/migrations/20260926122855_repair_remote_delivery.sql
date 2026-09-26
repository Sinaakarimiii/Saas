-- A repaired device can be dispatched only against its released repair QC.
alter table public.repair_delivery_dispatches alter column outgoing_check_id drop not null;
alter table public.repair_delivery_dispatches add column repair_outgoing_check_id uuid;
alter table public.repair_delivery_dispatches add constraint repair_dispatch_one_quality_path
 check ((outgoing_check_id is not null and repair_outgoing_check_id is null)
     or (outgoing_check_id is null and repair_outgoing_check_id is not null));
alter table public.repair_delivery_dispatches add constraint repair_dispatch_repair_check_fkey
 foreign key(org_id,case_id,repair_outgoing_check_id)
 references public.repair_outgoing_checks(org_id,case_id,id);

alter table public.repair_delivery_receipts drop constraint repair_delivery_one_quality_path;
alter table public.repair_delivery_receipts add constraint repair_delivery_one_quality_path
 check ((outgoing_check_id is not null and repair_outgoing_check_id is null)
     or (outgoing_check_id is null and repair_outgoing_check_id is not null));

create or replace function private.guard_repair_delivery_receipt_path() returns trigger
language plpgsql set search_path='' as $$
declare v_dispatch public.repair_delivery_dispatches;
begin
 if new.method='in_person' then
  if exists(select 1 from public.repair_delivery_dispatches d where d.org_id=new.org_id and d.case_id=new.case_id and d.status='in_transit') then
   raise exception 'DELIVERY_ALREADY_DISPATCHED' using errcode='23514'; end if;
 else
  select * into v_dispatch from public.repair_delivery_dispatches
   where org_id=new.org_id and case_id=new.case_id and id=new.dispatch_id;
  if v_dispatch.id is null or v_dispatch.status<>'in_transit' or v_dispatch.method<>new.method
   or v_dispatch.device_id<>new.device_id
   or v_dispatch.outgoing_check_id is distinct from new.outgoing_check_id
   or v_dispatch.repair_outgoing_check_id is distinct from new.repair_outgoing_check_id
   or v_dispatch.destination_name<>new.recipient_name or v_dispatch.destination_role<>new.recipient_role
   or v_dispatch.authority_reference is distinct from new.authority_reference
   or new.received_at<v_dispatch.dispatched_at
   or new.receipt_reference=v_dispatch.dispatch_reference
   or new.receipt_evidence=v_dispatch.dispatch_evidence then
   raise exception 'DELIVERY_DISPATCH_MISMATCH' using errcode='23514'; end if;
 end if;
 return new;
end; $$;

-- The same released check remains current while the device is with a carrier.
create or replace function private.assert_repair_handover_ready(p_org_id uuid,p_case_id uuid,p_stage text)
returns uuid language plpgsql set search_path='' as $$
declare v_case public.repair_cases; v_plan public.repair_action_plans;
 v_test public.repair_functional_tests; v_check public.repair_outgoing_checks;
 v_position public.repair_device_custody_positions; v_paid bigint;
begin
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id;
 if v_case.id is null or v_case.stage<>p_stage or v_case.verified_device_id is null
 then raise exception 'REPAIR_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_plan.id is null or v_plan.route<>'repair'
 then raise exception 'CURRENT_REPAIR_PLAN_REQUIRED' using errcode='23514'; end if;
 if v_plan.financial_basis='customer_paid' then
  select coalesce(sum(p.amount_irr),0) into v_paid from public.repair_payment_evidence p
   join public.repair_payment_verifications v on v.org_id=p.org_id and v.case_id=p.case_id and v.payment_id=p.id
   where p.org_id=p_org_id and p.case_id=p_case_id and p.plan_id=v_plan.id;
  if v_paid<>v_plan.amount_irr then raise exception 'REPAIR_PAYMENT_UNSETTLED' using errcode='23514'; end if;
 elsif v_plan.financial_basis<>'warranty' or v_plan.amount_irr<>0 then
  raise exception 'REPAIR_FINANCIAL_BASIS_UNRESOLVED' using errcode='23514'; end if;
 select * into v_test from public.repair_functional_tests where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_check from public.repair_outgoing_checks where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_test.id is null or not v_test.passed or v_check.id is null
  or v_check.plan_id<>v_plan.id or v_check.functional_test_id<>v_test.id
  or v_test.plan_id<>v_plan.id or v_check.device_id<>v_case.verified_device_id
  or v_check.custody_damage_epoch<>v_case.custody_damage_epoch
  or (p_stage='test' and v_check.recorded_at<v_case.stage_entered_at)
  or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass)
  or not exists(select 1 from public.repair_functional_test_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.test_id=v_test.id)
  or not exists(select 1 from public.repair_outgoing_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.check_id=v_check.id) then
  raise exception 'REPAIR_OUTGOING_RELEASE_REQUIRED' using errcode='23514'; end if;
 if p_stage='delivery' and not exists(select 1 from public.repair_case_events e
   where e.org_id=p_org_id and e.case_id=p_case_id and e.event_type='stage_transition'
    and e.details->>'transitionCode'='T08' and e.details->>'repairOutgoingCheckId'=v_check.id::text
    and e.occurred_at<=v_case.stage_entered_at) then
  raise exception 'REPAIR_DELIVERY_TRANSITION_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_case_assignment_requests a where a.org_id=p_org_id and a.case_id=p_case_id and a.status='pending')
 or exists(select 1 from public.repair_device_custody_transfers t where t.org_id=p_org_id and t.device_id=v_case.verified_device_id and t.status='in_transit')
 or exists(select 1 from public.repair_device_custody_discrepancies d where d.org_id=p_org_id and d.device_id=v_case.verified_device_id and d.status='open') then
  raise exception 'DELIVERY_BLOCKERS_OPEN' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id;
 if v_position.device_id is null or v_position.case_id<>p_case_id
  or (p_stage='test' and (v_position.holder_kind<>'staff' or v_position.custodian_user_id is null))
  or (p_stage='delivery' and v_position.holder_kind not in ('staff','carrier','recipient')) then
  raise exception 'DELIVERY_CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 return v_check.id;
end; $$;
revoke all on function private.assert_repair_handover_ready(uuid,uuid,text) from public,anon,authenticated;

create function public.record_repaired_delivery_dispatch(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_method text,p_carrier text,p_destination_address text,p_tracking_code text,
 p_dispatch_reference text,p_dispatch_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_check public.repair_outgoing_checks;
 v_position public.repair_device_custody_positions; v_saved private.repair_command_receipts;
 v_hash text; v_check_id uuid; v_dispatch public.repair_delivery_dispatches; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
  or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.delivery.dispatch')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or p_method not in ('post','courier')
  or length(pg_catalog.btrim(coalesce(p_carrier,''))) not between 1 and 160
  or length(pg_catalog.btrim(coalesce(p_destination_address,''))) not between 1 and 300
  or length(pg_catalog.btrim(coalesce(p_tracking_code,''))) not between 1 and 240
  or length(pg_catalog.btrim(coalesce(p_dispatch_reference,''))) not between 1 and 160
  or length(pg_catalog.btrim(coalesce(p_dispatch_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_DELIVERY_DISPATCH' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,
  'method',p_method,'carrier',pg_catalog.btrim(p_carrier),'address',pg_catalog.btrim(p_destination_address),
  'tracking',pg_catalog.btrim(p_tracking_code),'reference',pg_catalog.btrim(p_dispatch_reference),
  'evidence',pg_catalog.btrim(p_dispatch_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.dispatch:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='delivery.dispatch' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_repair_handover_ready(p_org_id,p_case_id,'delivery');
 select * into v_check from public.repair_outgoing_checks where id=v_check_id;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.device_id is null or v_position.case_id<>p_case_id or v_position.holder_kind<>'staff'
  or v_position.custodian_user_id<>v_actor then
  raise exception 'DELIVERY_CUSTODIAN_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_dispatches where org_id=p_org_id and case_id=p_case_id and status='in_transit') then
  raise exception 'DELIVERY_ALREADY_DISPATCHED' using errcode='23505'; end if;
 if exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'DELIVERY_ALREADY_RECEIVED' using errcode='23505'; end if;
 insert into public.repair_delivery_dispatches(org_id,case_id,device_id,repair_outgoing_check_id,method,
  carrier,destination_name,destination_role,authority_reference,destination_address,
  tracking_code,dispatch_reference,dispatch_evidence,dispatched_by)
 values(p_org_id,p_case_id,v_case.verified_device_id,v_check_id,p_method,pg_catalog.btrim(p_carrier),
  v_check.intended_recipient,v_check.recipient_role,v_check.authority_reference,pg_catalog.btrim(p_destination_address),
  pg_catalog.btrim(p_tracking_code),pg_catalog.btrim(p_dispatch_reference),pg_catalog.btrim(p_dispatch_evidence),v_actor)
 returning * into v_dispatch;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_dispatched',v_actor,pg_catalog.jsonb_build_object(
  'dispatchId',v_dispatch.id,'repairOutgoingCheckId',v_check_id,'method',p_method,
  'carrier',v_dispatch.carrier,'trackingCode',v_dispatch.tracking_code,
  'recipient',v_dispatch.destination_name,'reference',v_dispatch.dispatch_reference));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'dispatchId',v_dispatch.id,
  'version',v_case.version+1,'deliveryStatus','in_transit');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.dispatch',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_repaired_delivery_dispatch(uuid,uuid,integer,uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.record_repaired_delivery_dispatch(uuid,uuid,integer,uuid,text,text,text,text,text,text) to authenticated;

create function public.confirm_repaired_delivery_receipt(
 p_org_id uuid,p_case_id uuid,p_dispatch_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_recipient_name text,p_recipient_role text,p_authority_reference text,
 p_receipt_reference text,p_receipt_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_dispatch public.repair_delivery_dispatches;
 v_saved private.repair_command_receipts; v_hash text; v_check_id uuid;
 v_position public.repair_device_custody_positions; v_receipt public.repair_delivery_receipts; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_dispatch_id is null or p_idempotency_key is null
  or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.delivery.confirm_receipt')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1
  or length(pg_catalog.btrim(coalesce(p_recipient_name,''))) not between 1 and 160
  or p_recipient_role not in ('owner','authorized_representative','colleague')
  or (p_recipient_role='owner' and p_authority_reference is not null)
  or (p_recipient_role<>'owner' and length(pg_catalog.btrim(coalesce(p_authority_reference,''))) not between 1 and 240)
  or length(pg_catalog.btrim(coalesce(p_receipt_reference,''))) not between 1 and 160
  or length(pg_catalog.btrim(coalesce(p_receipt_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_DELIVERY_RECEIPT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'dispatchId',p_dispatch_id,
  'version',p_expected_version,'recipient',pg_catalog.btrim(p_recipient_name),'role',p_recipient_role,
  'authority',p_authority_reference,'reference',pg_catalog.btrim(p_receipt_reference),
  'evidence',pg_catalog.btrim(p_receipt_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.delivery.confirm:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='delivery.confirm' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_repair_handover_ready(p_org_id,p_case_id,'delivery');
 select * into v_dispatch from public.repair_delivery_dispatches
  where org_id=p_org_id and case_id=p_case_id and id=p_dispatch_id for update;
 if v_dispatch.id is null or v_dispatch.status<>'in_transit' or v_dispatch.device_id<>v_case.verified_device_id
  or v_dispatch.repair_outgoing_check_id<>v_check_id
  or v_dispatch.destination_name<>pg_catalog.btrim(p_recipient_name) or v_dispatch.destination_role<>p_recipient_role
  or v_dispatch.authority_reference is distinct from p_authority_reference then
  raise exception 'DELIVERY_DISPATCH_MISMATCH' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.case_id<>p_case_id or v_position.holder_kind<>'carrier'
  or v_position.external_reference<>v_dispatch.dispatch_reference then
  raise exception 'DELIVERY_CUSTODY_MISMATCH' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_incidents
  where org_id=p_org_id and dispatch_id=p_dispatch_id and status='open') then
  raise exception 'DELIVERY_INCIDENT_OPEN' using errcode='23514'; end if;
 if pg_catalog.btrim(p_receipt_reference)=v_dispatch.dispatch_reference
  or pg_catalog.btrim(p_receipt_evidence)=v_dispatch.dispatch_evidence then
  raise exception 'DELIVERY_INDEPENDENT_RECEIPT_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'DELIVERY_ALREADY_RECEIVED' using errcode='23505'; end if;
 insert into public.repair_delivery_receipts(org_id,case_id,device_id,repair_outgoing_check_id,method,
  recipient_name,recipient_role,authority_reference,receipt_reference,receipt_evidence,
  handed_over_by,dispatch_id,confirmed_by)
 values(p_org_id,p_case_id,v_case.verified_device_id,v_check_id,v_dispatch.method,
  pg_catalog.btrim(p_recipient_name),p_recipient_role,p_authority_reference,
  pg_catalog.btrim(p_receipt_reference),pg_catalog.btrim(p_receipt_evidence),
  v_dispatch.dispatched_by,v_dispatch.id,v_actor)
 returning * into v_receipt;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_received',v_actor,pg_catalog.jsonb_build_object(
  'receiptId',v_receipt.id,'dispatchId',v_dispatch.id,'repairOutgoingCheckId',v_check_id,
  'recipient',v_receipt.recipient_name,'method',v_dispatch.method,'reference',v_receipt.receipt_reference));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'receiptId',v_receipt.id,
  'version',v_case.version+1,'deliveryStatus','received');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.confirm',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.confirm_repaired_delivery_receipt(uuid,uuid,uuid,integer,uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.confirm_repaired_delivery_receipt(uuid,uuid,uuid,integer,uuid,text,text,text,text,text) to authenticated;

create or replace function public.close_repaired_case(p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_receipt public.repair_delivery_receipts;
 v_dispatch public.repair_delivery_dispatches; v_saved private.repair_command_receipts;
 v_hash text; v_check_id uuid; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
  or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'case.close')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 then raise exception 'INVALID_TRANSITION_INPUT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,'transitionCode','T09')::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.close:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='transition' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_repair_handover_ready(p_org_id,p_case_id,'delivery');
 select * into v_receipt from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id;
 if v_receipt.id is null or v_receipt.repair_outgoing_check_id<>v_check_id
  or v_receipt.device_id<>v_case.verified_device_id or v_receipt.received_at<v_case.stage_entered_at then
  raise exception 'DELIVERY_RECEIPT_REQUIRED' using errcode='23514'; end if;
 if v_receipt.method<>'in_person' then
  select * into v_dispatch from public.repair_delivery_dispatches
   where org_id=p_org_id and case_id=p_case_id and id=v_receipt.dispatch_id;
  if v_dispatch.id is null or v_dispatch.status<>'in_transit'
   or v_dispatch.repair_outgoing_check_id<>v_check_id
   or exists(select 1 from public.repair_delivery_incidents i
    where i.org_id=p_org_id and i.dispatch_id=v_dispatch.id and i.status='open') then
   raise exception 'DELIVERY_RECEIPT_REQUIRED' using errcode='23514'; end if;
 end if;
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_cases set stage='closed',stage_entered_at=v_at,closed_at=v_at,version=version+1
  where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,pg_catalog.jsonb_build_object('transitionCode','T09',
  'from','delivery','to','closed','outcome','repaired','deliveryReceiptId',v_receipt.id,
  'repairOutgoingCheckId',v_check_id));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','closed','version',v_case.version+1,'transitionCode','T09');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create or replace function private.guard_repaired_stage_path() returns trigger language plpgsql set search_path='' as $$
declare v_plan public.repair_action_plans; v_check_id uuid;
begin
 if (old.stage='test' and new.stage='delivery') or (old.stage='delivery' and new.stage='closed') then
  select * into v_plan from public.repair_action_plans where org_id=new.org_id and case_id=new.id order by revision desc limit 1;
  if v_plan.route='repair' then
   v_check_id:=private.assert_repair_handover_ready(new.org_id,new.id,old.stage);
   if new.stage='closed' and not exists(select 1 from public.repair_delivery_receipts r
     left join public.repair_delivery_dispatches d on d.org_id=r.org_id and d.case_id=r.case_id and d.id=r.dispatch_id
     where r.org_id=new.org_id and r.case_id=new.id and r.device_id=new.verified_device_id
      and r.repair_outgoing_check_id=v_check_id and r.received_at>=old.stage_entered_at
      and (r.method='in_person' and r.dispatch_id is null
        or r.method in ('post','courier') and d.status='in_transit'
         and d.repair_outgoing_check_id=v_check_id and d.method=r.method
         and not exists(select 1 from public.repair_delivery_incidents i
           where i.org_id=new.org_id and i.dispatch_id=d.id and i.status='open'))) then
    raise exception 'DELIVERY_RECEIPT_REQUIRED' using errcode='23514'; end if;
  end if;
 end if;
 return new;
end; $$;
