-- Replacement shipments preserve original identity and only issue stock on the destination receipt.
update public.permissions set description_fa='ثبت خروج دستگاه عودتی، تعمیرشده یا جایگزین به حامل با مدرک و کد رهگیری' where key='repair.delivery.dispatch';

create or replace function private.assert_replacement_handover_ready(p_org_id uuid,p_case_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_case public.repair_cases; v_plan public.repair_action_plans;
 v_execution public.repair_replacement_executions; v_stock public.repair_replacement_stock;
 v_test public.repair_functional_tests; v_check public.repair_outgoing_checks;
 v_position public.repair_device_custody_positions; v_original public.repair_device_custody_positions;
 v_paid bigint;
begin
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id;
 if v_case.id is null or v_case.stage not in ('test','delivery') or v_case.verified_device_id is null then
  raise exception 'REPLACEMENT_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 if v_plan.id is null or v_plan.route<>'replacement' or v_execution.id is null
  or v_execution.plan_id<>v_plan.id or v_execution.original_device_id<>v_case.verified_device_id
  or v_execution.original_disposition_pending<>v_plan.original_disposition
  or v_execution.executed_at>v_case.stage_entered_at then
  raise exception 'REPLACEMENT_EXECUTION_REQUIRED' using errcode='23514'; end if;
 select * into v_stock from public.repair_replacement_stock where org_id=p_org_id and device_id=v_execution.replacement_device_id;
 if v_stock.device_id is null or v_stock.status<>'allocated' or v_stock.allocated_case_id<>p_case_id
  or v_stock.allocated_plan_id<>v_plan.id then
  raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 if v_plan.financial_basis='customer_paid' then
  select coalesce(sum(p.amount_irr),0) into v_paid from public.repair_payment_evidence p
   join public.repair_payment_verifications v on v.org_id=p.org_id and v.case_id=p.case_id and v.payment_id=p.id
   where p.org_id=p_org_id and p.case_id=p_case_id and p.plan_id=v_plan.id
    and not exists(select 1 from public.repair_payment_corrections c
      where c.org_id=p.org_id and c.case_id=p.case_id and c.payment_id=p.id);
  select v_paid-coalesce(sum(r.amount_irr),0) into v_paid
   from public.repair_payment_refunds r join public.repair_payment_evidence p
    on p.org_id=r.org_id and p.case_id=r.case_id and p.id=r.source_payment_id
   where r.org_id=p_org_id and r.case_id=p_case_id and p.plan_id=v_plan.id and r.approved_at is not null;
  select v_paid+coalesce(sum(amount_irr),0) into v_paid from public.repair_payment_credit_transfers
   where org_id=p_org_id and case_id=p_case_id and target_plan_id=v_plan.id and approved_at is not null;
  if v_paid<>v_plan.amount_irr then raise exception 'REPLACEMENT_PAYMENT_UNSETTLED' using errcode='23514'; end if;
 elsif v_plan.financial_basis<>'warranty' or v_plan.amount_irr<>0 then
  raise exception 'REPLACEMENT_FINANCIAL_BASIS_UNRESOLVED' using errcode='23514'; end if;
 select * into v_test from public.repair_functional_tests where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_check from public.repair_outgoing_checks where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_test.id is null or not v_test.passed or v_test.protocol_code<>'replacement_functional_v1'
  or v_test.plan_id<>v_plan.id or v_test.execution_id<>v_execution.id
  or v_test.device_id<>v_execution.replacement_device_id
  or v_test.custody_damage_epoch<>v_case.custody_damage_epoch
  or (v_case.stage='test' and v_test.recorded_at<v_case.stage_entered_at)
  or v_check.id is null or v_check.protocol_code<>'replacement_outgoing_v1'
  or v_check.plan_id<>v_plan.id or v_check.functional_test_id<>v_test.id
  or v_check.device_id<>v_execution.replacement_device_id
  or v_check.custody_damage_epoch<>v_case.custody_damage_epoch
  or (v_case.stage='test' and v_check.recorded_at<v_case.stage_entered_at)
  or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass)
  or not exists(select 1 from public.repair_functional_test_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.test_id=v_test.id)
  or not exists(select 1 from public.repair_outgoing_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.check_id=v_check.id) then
  raise exception 'REPLACEMENT_OUTGOING_RELEASE_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_case_assignment_requests a where a.org_id=p_org_id and a.case_id=p_case_id and a.status='pending')
  or exists(select 1 from public.repair_device_custody_transfers t where t.org_id=p_org_id
   and t.device_id in (v_case.verified_device_id,v_execution.replacement_device_id) and t.status='in_transit')
  or exists(select 1 from public.repair_device_custody_discrepancies d where d.org_id=p_org_id
   and d.device_id in (v_case.verified_device_id,v_execution.replacement_device_id) and d.status='open') then
  raise exception 'DELIVERY_BLOCKERS_OPEN' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and case_id=p_case_id and device_id=v_execution.replacement_device_id;
 select * into v_original from public.repair_device_custody_positions
  where org_id=p_org_id and case_id=p_case_id and device_id=v_case.verified_device_id;
 if v_position.device_id is null or not (
  (v_position.holder_kind='staff' and v_position.custodian_user_id is not null
   and v_stock.location=v_position.location and v_stock.custodian_user_id=v_position.custodian_user_id)
  or (v_case.stage='delivery' and v_position.holder_kind='carrier' and exists(
   select 1 from public.repair_delivery_dispatches d where d.org_id=p_org_id and d.case_id=p_case_id
    and d.device_id=v_execution.replacement_device_id and d.repair_outgoing_check_id=v_check.id
    and d.status='in_transit' and d.dispatch_reference=v_position.external_reference
    and d.dispatched_at>=v_case.stage_entered_at)))
  or v_original.device_id is null or v_original.holder_kind<>'staff' or v_original.custodian_user_id is null then
  raise exception 'DELIVERY_CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 if v_case.stage='delivery' and not exists(select 1 from public.repair_case_events e
  where e.org_id=p_org_id and e.case_id=p_case_id and e.event_type='stage_transition'
   and e.details->>'transitionCode'='T08'
   and e.details->>'replacementOutgoingCheckId'=v_check.id::text
   and e.occurred_at=v_case.stage_entered_at) then
  raise exception 'REPLACEMENT_DELIVERY_TRANSITION_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_incidents i where i.org_id=p_org_id
  and i.case_id=p_case_id and i.status='open') then
  raise exception 'DELIVERY_INCIDENT_OPEN' using errcode='23514'; end if;
 return v_check.id;
end; $$;

create or replace function private.assert_replacement_issued_ready(p_org_id uuid,p_case_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_case public.repair_cases; v_plan public.repair_action_plans;
 v_execution public.repair_replacement_executions; v_stock public.repair_replacement_stock;
 v_test public.repair_functional_tests; v_check public.repair_outgoing_checks;
 v_position public.repair_device_custody_positions; v_original public.repair_device_custody_positions;
 v_paid bigint;
begin
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id;
 if v_case.id is null or v_case.stage<>'delivery' or v_case.verified_device_id is null then
  raise exception 'REPLACEMENT_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 if v_plan.id is null or v_plan.route<>'replacement' or v_execution.id is null
  or v_execution.plan_id<>v_plan.id or v_execution.original_device_id<>v_case.verified_device_id
  or v_execution.original_disposition_pending<>v_plan.original_disposition
  or v_execution.executed_at>v_case.stage_entered_at then
  raise exception 'REPLACEMENT_EXECUTION_REQUIRED' using errcode='23514'; end if;
 select * into v_stock from public.repair_replacement_stock where org_id=p_org_id and device_id=v_execution.replacement_device_id;
 if v_stock.device_id is null or v_stock.status<>'issued' or v_stock.allocated_case_id<>p_case_id
  or v_stock.allocated_plan_id<>v_plan.id then
  raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 if v_plan.financial_basis='customer_paid' then
  select coalesce(sum(p.amount_irr),0) into v_paid from public.repair_payment_evidence p
   join public.repair_payment_verifications v on v.org_id=p.org_id and v.case_id=p.case_id and v.payment_id=p.id
   where p.org_id=p_org_id and p.case_id=p_case_id and p.plan_id=v_plan.id
    and not exists(select 1 from public.repair_payment_corrections c
      where c.org_id=p.org_id and c.case_id=p.case_id and c.payment_id=p.id);
  select v_paid-coalesce(sum(r.amount_irr),0) into v_paid
   from public.repair_payment_refunds r join public.repair_payment_evidence p
    on p.org_id=r.org_id and p.case_id=r.case_id and p.id=r.source_payment_id
   where r.org_id=p_org_id and r.case_id=p_case_id and p.plan_id=v_plan.id and r.approved_at is not null;
  select v_paid+coalesce(sum(amount_irr),0) into v_paid from public.repair_payment_credit_transfers
   where org_id=p_org_id and case_id=p_case_id and target_plan_id=v_plan.id and approved_at is not null;
  if v_paid<>v_plan.amount_irr then raise exception 'REPLACEMENT_PAYMENT_UNSETTLED' using errcode='23514'; end if;
 elsif v_plan.financial_basis<>'warranty' or v_plan.amount_irr<>0 then
  raise exception 'REPLACEMENT_FINANCIAL_BASIS_UNRESOLVED' using errcode='23514'; end if;
 select * into v_test from public.repair_functional_tests where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_check from public.repair_outgoing_checks where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_test.id is null or not v_test.passed or v_test.protocol_code<>'replacement_functional_v1'
  or v_test.plan_id<>v_plan.id or v_test.execution_id<>v_execution.id
  or v_test.device_id<>v_execution.replacement_device_id
  or v_test.custody_damage_epoch<>v_case.custody_damage_epoch
  or (v_case.stage='test' and v_test.recorded_at<v_case.stage_entered_at)
  or v_check.id is null or v_check.protocol_code<>'replacement_outgoing_v1'
  or v_check.plan_id<>v_plan.id or v_check.functional_test_id<>v_test.id
  or v_check.device_id<>v_execution.replacement_device_id
  or v_check.custody_damage_epoch<>v_case.custody_damage_epoch
  or (v_case.stage='test' and v_check.recorded_at<v_case.stage_entered_at)
  or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass)
  or not exists(select 1 from public.repair_functional_test_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.test_id=v_test.id)
  or not exists(select 1 from public.repair_outgoing_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.check_id=v_check.id) then
  raise exception 'REPLACEMENT_OUTGOING_RELEASE_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_case_assignment_requests a where a.org_id=p_org_id and a.case_id=p_case_id and a.status='pending')
  or exists(select 1 from public.repair_device_custody_transfers t where t.org_id=p_org_id
   and t.device_id in (v_case.verified_device_id,v_execution.replacement_device_id) and t.status='in_transit')
  or exists(select 1 from public.repair_device_custody_discrepancies d where d.org_id=p_org_id
   and d.device_id in (v_case.verified_device_id,v_execution.replacement_device_id) and d.status='open') then
  raise exception 'DELIVERY_BLOCKERS_OPEN' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and case_id=p_case_id and device_id=v_execution.replacement_device_id;
 select * into v_original from public.repair_device_custody_positions
  where org_id=p_org_id and case_id=p_case_id and device_id=v_case.verified_device_id;
 if v_position.device_id is null or v_position.holder_kind<>'recipient'
  or v_original.device_id is null or v_original.holder_kind not in ('staff','recipient')
  or not exists(select 1 from public.repair_delivery_receipts r where r.org_id=p_org_id and r.case_id=p_case_id
   and r.id=v_stock.issued_receipt_id and r.device_id=v_execution.replacement_device_id
   and r.repair_outgoing_check_id=v_check.id
   and (r.method='in_person' or exists(select 1 from public.repair_delivery_dispatches d
     where d.org_id=r.org_id and d.case_id=r.case_id and d.id=r.dispatch_id and d.status='in_transit'
      and d.device_id=r.device_id and d.repair_outgoing_check_id=r.repair_outgoing_check_id
      and d.method=r.method and d.destination_name=r.recipient_name and d.destination_role=r.recipient_role
      and d.authority_reference is not distinct from r.authority_reference
      and d.dispatched_by=r.handed_over_by and r.received_at>=d.dispatched_at
      and r.receipt_reference<>d.dispatch_reference and r.receipt_evidence<>d.dispatch_evidence))
   and r.received_at>=v_case.stage_entered_at and r.received_at=v_stock.issued_at
   and r.receipt_reference=v_position.external_reference) then
  raise exception 'REPLACEMENT_DELIVERY_RECEIPT_REQUIRED' using errcode='23514'; end if;
 if v_case.stage='delivery' and not exists(select 1 from public.repair_case_events e
  where e.org_id=p_org_id and e.case_id=p_case_id and e.event_type='stage_transition'
   and e.details->>'transitionCode'='T08'
   and e.details->>'replacementOutgoingCheckId'=v_check.id::text
   and e.occurred_at=v_case.stage_entered_at) then
  raise exception 'REPLACEMENT_DELIVERY_TRANSITION_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_incidents i where i.org_id=p_org_id
  and i.case_id=p_case_id and i.status='open') then
  raise exception 'DELIVERY_INCIDENT_OPEN' using errcode='23514'; end if;
 return v_check.id;
end; $$;

create or replace function private.reconcile_repair_dispatch_custody()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_position public.repair_device_custody_positions;
begin
 select * into v_position from public.repair_device_custody_positions
  where org_id=new.org_id and device_id=new.device_id for update;
 if v_position.device_id is null or v_position.case_id<>new.case_id
 or v_position.holder_kind<>'staff' or v_position.custodian_user_id<>new.dispatched_by then
  raise exception 'DELIVERY_CUSTODIAN_REQUIRED' using errcode='23514'; end if;
 update public.repair_device_custody_positions set
  holder_kind='carrier',custodian_user_id=null,custodian_label=new.carrier,
  location='نزد حامل: '||new.carrier,external_reference=new.dispatch_reference,
  confirmed_at=new.dispatched_at,confirmed_by=new.dispatched_by
  where org_id=new.org_id and device_id=new.device_id;
 update public.repair_cases set device_location='نزد حامل: '||new.carrier,
  device_custodian=new.carrier where org_id=new.org_id and id=new.case_id and verified_device_id=new.device_id;
 return new;
end; $$;

create or replace function private.guard_replacement_receipt() returns trigger
language plpgsql set search_path='' as $$
declare v_route text; v_check public.repair_outgoing_checks; v_check_id uuid;
begin
 perform 1 from public.repair_cases where org_id=new.org_id and id=new.case_id for update;
 select route into v_route from public.repair_action_plans where org_id=new.org_id and case_id=new.case_id order by revision desc limit 1;
 if v_route='replacement' then
  v_check_id:=private.assert_replacement_handover_ready(new.org_id,new.case_id);
  select * into v_check from public.repair_outgoing_checks where id=v_check_id;
  if new.device_id<>v_check.device_id or new.repair_outgoing_check_id is distinct from v_check.id
   or new.recipient_name<>v_check.intended_recipient or new.recipient_role<>v_check.recipient_role
   or new.authority_reference is distinct from v_check.authority_reference
   or (new.method='in_person' and new.dispatch_id is not null)
   or (new.method<>'in_person' and not exists(select 1 from public.repair_delivery_dispatches d
     where d.org_id=new.org_id and d.case_id=new.case_id and d.id=new.dispatch_id
      and d.dispatched_by=new.handed_over_by and d.repair_outgoing_check_id=v_check.id))
   or not exists(select 1 from public.repair_cases c where c.org_id=new.org_id and c.id=new.case_id
    and c.stage='delivery' and new.received_at>=c.stage_entered_at) then
   raise exception 'REPLACEMENT_RECEIPT_MISMATCH' using errcode='23514'; end if;
 end if;
 return new;
end; $$;

create function private.guard_replacement_dispatch() returns trigger
language plpgsql set search_path='' as $$
declare v_route text; v_check_id uuid; v_check public.repair_outgoing_checks;
begin
 perform 1 from public.repair_cases where org_id=new.org_id and id=new.case_id for update;
 select route into v_route from public.repair_action_plans where org_id=new.org_id and case_id=new.case_id order by revision desc limit 1;
 if v_route='replacement' then
  v_check_id:=private.assert_replacement_handover_ready(new.org_id,new.case_id);
  select * into v_check from public.repair_outgoing_checks where id=v_check_id;
  if new.device_id<>v_check.device_id or new.repair_outgoing_check_id is distinct from v_check_id
   or new.destination_name<>v_check.intended_recipient or new.destination_role<>v_check.recipient_role
   or new.authority_reference is distinct from v_check.authority_reference
   or not exists(select 1 from public.repair_cases c where c.org_id=new.org_id and c.id=new.case_id
    and c.stage='delivery' and new.dispatched_at>=c.stage_entered_at) then
   raise exception 'REPLACEMENT_DISPATCH_MISMATCH' using errcode='23514'; end if;
 end if;
 return new;
end; $$;
revoke all on function private.guard_replacement_dispatch() from public,anon,authenticated;
create trigger replacement_dispatch_guard before insert on public.repair_delivery_dispatches
for each row execute function private.guard_replacement_dispatch();

create function public.record_replacement_delivery_dispatch(
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
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.replacement.dispatch:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='replacement.delivery.dispatch' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'delivery' then raise exception 'REPLACEMENT_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 v_check_id:=private.assert_replacement_handover_ready(p_org_id,p_case_id);
 select * into v_check from public.repair_outgoing_checks where id=v_check_id;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_check.device_id for update;
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
 values(p_org_id,p_case_id,v_check.device_id,v_check_id,p_method,pg_catalog.btrim(p_carrier),
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
 values(p_org_id,v_actor,'replacement.delivery.dispatch',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create function public.confirm_replacement_delivery_receipt(
 p_org_id uuid,p_case_id uuid,p_dispatch_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_recipient_name text,p_recipient_role text,p_authority_reference text,
 p_receipt_reference text,p_receipt_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_dispatch public.repair_delivery_dispatches;
 v_saved private.repair_command_receipts; v_hash text; v_check_id uuid;
 v_check public.repair_outgoing_checks; v_position public.repair_device_custody_positions; v_receipt public.repair_delivery_receipts; v_response jsonb;
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
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.replacement.delivery.confirm:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='replacement.delivery.confirm' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'delivery' then raise exception 'REPLACEMENT_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 v_check_id:=private.assert_replacement_handover_ready(p_org_id,p_case_id);
 select * into v_check from public.repair_outgoing_checks where id=v_check_id;
 select * into v_dispatch from public.repair_delivery_dispatches
  where org_id=p_org_id and case_id=p_case_id and id=p_dispatch_id for update;
 if v_dispatch.id is null or v_dispatch.status<>'in_transit' or v_dispatch.device_id<>v_check.device_id
  or v_dispatch.repair_outgoing_check_id<>v_check_id
  or v_dispatch.destination_name<>pg_catalog.btrim(p_recipient_name) or v_dispatch.destination_role<>p_recipient_role
  or v_dispatch.authority_reference is distinct from p_authority_reference then
  raise exception 'DELIVERY_DISPATCH_MISMATCH' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_check.device_id for update;
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
 values(p_org_id,p_case_id,v_check.device_id,v_check_id,v_dispatch.method,
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
 values(p_org_id,v_actor,'replacement.delivery.confirm',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create or replace function public.record_repair_delivery_incident(
 p_org_id uuid,p_case_id uuid,p_dispatch_id uuid,p_kind text,p_reference text,p_evidence text,
 p_responsible_user_id uuid,p_due_at timestamptz,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_dispatch public.repair_delivery_dispatches;
 v_item public.repair_delivery_incidents; v_hash text; v_saved private.repair_command_receipts; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_dispatch_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'delivery.incident.record')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_kind not in ('lost','damage','delivery_discrepancy') or p_responsible_user_id is null
 or p_due_at is null or p_due_at<=pg_catalog.clock_timestamp() or p_expected_version is null
 or length(btrim(coalesce(p_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_DELIVERY_INCIDENT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('case',p_case_id,'dispatch',p_dispatch_id,'kind',p_kind,
 'reference',btrim(p_reference),'evidence',btrim(p_evidence),'responsible',p_responsible_user_id,
 'due',p_due_at,'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.delivery.incident.record:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='delivery.incident.record' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_dispatch from public.repair_delivery_dispatches where org_id=p_org_id and case_id=p_case_id and id=p_dispatch_id;
 if v_case.stage<>'delivery' or v_dispatch.id is null or (v_dispatch.device_id<>v_case.verified_device_id and not exists(
   select 1 from public.repair_replacement_executions x
   join public.repair_action_plans p on p.org_id=x.org_id and p.case_id=x.case_id and p.id=x.plan_id
   join public.repair_outgoing_checks q on q.org_id=p.org_id and q.case_id=p.case_id and q.plan_id=p.id
   where x.org_id=p_org_id and x.case_id=p_case_id and x.original_device_id=v_case.verified_device_id
    and x.replacement_device_id=v_dispatch.device_id and p.route='replacement'
    and p.revision=(select max(revision) from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id)
    and q.id=v_dispatch.repair_outgoing_check_id and q.protocol_code='replacement_outgoing_v1'))
 or v_dispatch.status<>'in_transit'
 or exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id)
 then raise exception 'DELIVERY_DISPATCH_NOT_OPEN' using errcode='23514'; end if;
 if not exists(select 1 from public.org_members where org_id=p_org_id and user_id=p_responsible_user_id
 and deleted_at is null and invitation_status='active') then raise exception 'DELIVERY_MEMBER_INACTIVE' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_incidents where org_id=p_org_id and dispatch_id=p_dispatch_id and status='open')
 then raise exception 'DELIVERY_INCIDENT_OPEN' using errcode='23514'; end if;
 insert into public.repair_delivery_incidents(org_id,case_id,device_id,dispatch_id,kind,reference,evidence,responsible_user_id,due_at,recorded_by)
 values(p_org_id,p_case_id,v_dispatch.device_id,p_dispatch_id,p_kind,btrim(p_reference),btrim(p_evidence),p_responsible_user_id,p_due_at,v_actor)
 returning * into v_item;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_incident_recorded',v_actor,pg_catalog.jsonb_build_object(
 'incidentId',v_item.id,'dispatchId',p_dispatch_id,'kind',p_kind,'reference',v_item.reference,
 'responsibleUserId',p_responsible_user_id,'dueAt',p_due_at));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'incidentId',v_item.id,'version',v_case.version,'incidentVersion',v_item.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.incident.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create or replace function public.receive_repair_delivery_damage_return(
 p_org_id uuid,p_case_id uuid,p_dispatch_id uuid,p_incident_id uuid,
 p_expected_version integer,p_expected_incident_version integer,p_idempotency_key uuid,
 p_location text,p_condition_note text,p_return_reference text,p_return_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_dispatch public.repair_delivery_dispatches;
 v_incident public.repair_delivery_incidents; v_position public.repair_device_custody_positions;
 v_return public.repair_delivery_dispatch_returns; v_saved private.repair_command_receipts;
 v_plan public.repair_action_plans; v_execution public.repair_replacement_executions; v_device_id uuid;
 v_hash text; v_label text; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_dispatch_id is null or p_incident_id is null
 or p_idempotency_key is null or not private.is_org_member(p_org_id)
 or not private.has_permission(p_org_id,'repair.delivery.return_receive') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_incident_version is null
 or length(btrim(coalesce(p_location,''))) not between 1 and 200
 or length(btrim(coalesce(p_condition_note,''))) not between 1 and 1000
 or length(btrim(coalesce(p_return_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_return_evidence,''))) not between 1 and 240 then
  raise exception 'INVALID_DELIVERY_DAMAGE_RETURN' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('case',p_case_id,'dispatch',p_dispatch_id,
  'incident',p_incident_id,'caseVersion',p_expected_version,'incidentVersion',p_expected_incident_version,
  'location',btrim(p_location),'condition',btrim(p_condition_note),
  'reference',btrim(p_return_reference),'evidence',btrim(p_return_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.delivery.damage.return:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='delivery.damage.return' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 v_device_id:=v_case.verified_device_id;
 if v_plan.route='replacement' then
  select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
  if v_execution.id is null or v_execution.plan_id<>v_plan.id or v_execution.original_device_id<>v_case.verified_device_id then
   raise exception 'REPLACEMENT_EXECUTION_REQUIRED' using errcode='23514'; end if;
  v_device_id:=v_execution.replacement_device_id;
 end if;
 select * into v_dispatch from public.repair_delivery_dispatches
  where org_id=p_org_id and case_id=p_case_id and id=p_dispatch_id for update;
 select * into v_incident from public.repair_delivery_incidents
  where org_id=p_org_id and case_id=p_case_id and id=p_incident_id for update;
 if v_case.stage<>'delivery' or v_device_id is null
 or v_dispatch.id is null or v_dispatch.status<>'in_transit' or v_dispatch.device_id<>v_device_id
 or v_incident.id is null or v_incident.dispatch_id<>p_dispatch_id or v_incident.kind<>'damage'
 or v_incident.status<>'open'
 or exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'DELIVERY_DAMAGE_RETURN_NOT_ALLOWED' using errcode='23514'; end if;
 if v_incident.version<>p_expected_incident_version then
  raise exception 'DELIVERY_INCIDENT_VERSION_CONFLICT' using errcode='P0001'; end if;
 if btrim(p_return_reference) in (v_dispatch.dispatch_reference,v_incident.reference)
 or btrim(p_return_evidence) in (v_dispatch.dispatch_evidence,v_incident.evidence)
 or exists(select 1 from public.repair_delivery_incidents where org_id=p_org_id and resolution_reference=btrim(p_return_reference)) then
  raise exception 'DELIVERY_INDEPENDENT_RETURN_REQUIRED' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_device_id for update;
 if v_position.device_id is null or v_position.case_id<>p_case_id
 or v_position.holder_kind<>'carrier' or v_position.external_reference<>v_dispatch.dispatch_reference then
  raise exception 'DELIVERY_CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),''),v_actor::text) into v_label from public.org_members m
 join public.profiles p on p.id=m.user_id where m.org_id=p_org_id and m.user_id=v_actor
 and m.deleted_at is null and m.invitation_status='active';
 if v_label is null then raise exception 'DELIVERY_MEMBER_INACTIVE' using errcode='23514'; end if;
 v_at:=pg_catalog.clock_timestamp();
 insert into public.repair_delivery_dispatch_returns(org_id,case_id,device_id,dispatch_id,incident_id,
  location,condition_note,return_reference,return_evidence,received_by,received_at)
 values(p_org_id,p_case_id,v_device_id,p_dispatch_id,p_incident_id,
  btrim(p_location),btrim(p_condition_note),btrim(p_return_reference),btrim(p_return_evidence),v_actor,v_at)
 returning * into v_return;
 update public.repair_delivery_dispatches set status='returned' where id=p_dispatch_id;
 update public.repair_delivery_incidents set status='resolved',resolution_reference=btrim(p_return_reference),
  resolution_evidence=btrim(p_return_evidence),resolved_by=v_actor,resolved_at=v_at,version=version+1
  where id=p_incident_id;
 update public.repair_device_custody_positions set location=btrim(p_location),holder_kind='staff',
  external_reference=null,custodian_user_id=v_actor,
  custodian_label=v_label,confirmed_at=v_at,confirmed_by=v_actor,baseline_evidence=btrim(p_return_evidence)
  where org_id=p_org_id and device_id=v_device_id;
 if v_plan.route='replacement' then
  update public.repair_replacement_stock set location=btrim(p_location),custodian_user_id=v_actor
   where org_id=p_org_id and device_id=v_device_id and status='allocated'
    and allocated_case_id=p_case_id and allocated_plan_id=v_plan.id;
  if not found then raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 end if;
 update public.repair_cases set
  device_location=case when verified_device_id=v_device_id then btrim(p_location) else device_location end,
  device_custodian=case when verified_device_id=v_device_id then v_label else device_custodian end,
  custody_damage_epoch=custody_damage_epoch+1,version=version+1
  where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'delivery_damage_returned',v_actor,v_at,pg_catalog.jsonb_build_object(
  'deviceId',v_device_id,'dispatchId',p_dispatch_id,'incidentId',p_incident_id,'returnId',v_return.id,
  'reference',v_return.return_reference,'location',v_return.location,
  'condition',v_return.condition_note,'damageEpoch',v_case.custody_damage_epoch));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'returnId',v_return.id,
  'version',v_case.version,'incidentVersion',v_incident.version+1,'damageEpoch',v_case.custody_damage_epoch);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.damage.return',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create or replace function public.return_repair_case_to_test_after_damage(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_execution public.repair_replacement_executions; v_device_id uuid; v_check_id uuid; v_check_epoch integer; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
  or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'case.transition.T11')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 then
  raise exception 'INVALID_TRANSITION_INPUT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,
  'expectedVersion',p_expected_version,'transitionCode','T11')::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.transition:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts
  where org_id=p_org_id and actor_id=v_actor and operation='transition' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'delivery' or v_case.verified_device_id is null then
  raise exception 'TRANSITION_NOT_ALLOWED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans
  where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_plan.id is null or v_plan.route not in ('return','repair','replacement') then
  raise exception 'TRANSITION_NOT_ALLOWED' using errcode='23514'; end if;
 v_device_id:=v_case.verified_device_id;
 if v_plan.route='replacement' then
  select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
  if v_execution.id is null or v_execution.plan_id<>v_plan.id or v_execution.original_device_id<>v_case.verified_device_id then
   raise exception 'REPLACEMENT_EXECUTION_REQUIRED' using errcode='23514'; end if;
  v_device_id:=v_execution.replacement_device_id;
 end if;
 if v_plan.route='return' then
  select c.id,c.custody_damage_epoch into v_check_id,v_check_epoch
   from public.repair_return_outgoing_checks c
   where c.org_id=p_org_id and c.case_id=p_case_id order by c.revision desc limit 1;
 else
  select c.id,c.custody_damage_epoch into v_check_id,v_check_epoch
   from public.repair_outgoing_checks c
   where c.org_id=p_org_id and c.case_id=p_case_id order by c.revision desc limit 1;
 end if;
 if v_check_id is null or v_check_epoch>=v_case.custody_damage_epoch
  or not exists(select 1 from public.repair_delivery_dispatch_returns dr
   join public.repair_delivery_dispatches dd on dd.org_id=dr.org_id and dd.case_id=dr.case_id and dd.id=dr.dispatch_id
   where dr.org_id=p_org_id and dr.case_id=p_case_id and dr.device_id=v_device_id
    and dr.received_at>=v_case.stage_entered_at and dd.status='returned'
    and (v_plan.route='return' and dd.outgoing_check_id=v_check_id
      or v_plan.route in ('repair','replacement') and dd.repair_outgoing_check_id=v_check_id))
  and not exists(select 1 from public.repair_device_custody_discrepancies d
   join public.repair_device_custody_transfers t on t.org_id=d.org_id and t.id=d.transfer_id
   where d.org_id=p_org_id and d.case_id=p_case_id and d.device_id=v_device_id
    and d.kind='damage' and d.recorded_at>=v_case.stage_entered_at and t.status='returned') then
  raise exception 'CUSTODY_DAMAGE_RETURN_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_receipts r where r.org_id=p_org_id and r.case_id=p_case_id)
  or exists(select 1 from public.repair_delivery_dispatches d
   where d.org_id=p_org_id and d.case_id=p_case_id and d.status='in_transit') then
  raise exception 'DELIVERY_ALREADY_RELEASED' using errcode='23514'; end if;
 if not exists(select 1 from public.repair_device_custody_positions pos where pos.org_id=p_org_id
  and pos.device_id=v_device_id and pos.case_id=p_case_id and pos.holder_kind='staff') then
  raise exception 'DELIVERY_CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_cases set stage='test',stage_entered_at=v_at,version=version+1
  where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,pg_catalog.jsonb_build_object(
  'transitionCode','T11','from','delivery','to','test','reason','physical_damage_return',
  'previousCheckId',v_check_id,'damageEpoch',v_case.custody_damage_epoch));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','test','version',v_case.version,'transitionCode','T11');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

revoke all on function public.record_replacement_delivery_dispatch(uuid,uuid,integer,uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.record_replacement_delivery_dispatch(uuid,uuid,integer,uuid,text,text,text,text,text,text) to authenticated;

revoke all on function public.confirm_replacement_delivery_receipt(uuid,uuid,uuid,integer,uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.confirm_replacement_delivery_receipt(uuid,uuid,uuid,integer,uuid,text,text,text,text,text) to authenticated;
