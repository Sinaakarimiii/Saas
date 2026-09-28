-- Final issue preserves allocation provenance; issued devices cannot be allocated again.
alter table public.repair_replacement_stock drop constraint repair_replacement_stock_status_check;
alter table public.repair_replacement_stock drop constraint repair_replacement_stock_check;
alter table public.repair_replacement_stock add column issued_receipt_id uuid;
alter table public.repair_replacement_stock add column issued_at timestamptz;
alter table public.repair_replacement_stock add constraint replacement_stock_issue_receipt_fk
 foreign key(org_id,allocated_case_id,issued_receipt_id) references public.repair_delivery_receipts(org_id,case_id,id);
alter table public.repair_replacement_stock add constraint repair_replacement_stock_status_check
 check(status in ('available','allocated','issued'));
alter table public.repair_replacement_stock add constraint repair_replacement_stock_check check(
 (status='available' and allocated_case_id is null and allocated_plan_id is null and allocated_at is null and issued_receipt_id is null and issued_at is null)
 or (status in ('allocated','issued') and allocated_case_id is not null and allocated_plan_id is not null and allocated_at is not null
  and ((status='allocated' and issued_receipt_id is null and issued_at is null)
   or (status='issued' and issued_receipt_id is not null and issued_at is not null))));

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
 if v_position.device_id is null or v_position.holder_kind<>'staff' or v_position.custodian_user_id is null
  or v_stock.location<>v_position.location or v_stock.custodian_user_id<>v_position.custodian_user_id
  or v_original.device_id is null or v_original.holder_kind<>'staff' or v_original.custodian_user_id is null then
  raise exception 'DELIVERY_CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 if v_case.stage='delivery' and not exists(select 1 from public.repair_case_events e
  where e.org_id=p_org_id and e.case_id=p_case_id and e.event_type='stage_transition'
   and e.details->>'transitionCode'='T08'
   and e.details->>'replacementOutgoingCheckId'=v_check.id::text
   and e.occurred_at=v_case.stage_entered_at) then
  raise exception 'REPLACEMENT_DELIVERY_TRANSITION_REQUIRED' using errcode='23514'; end if;
 return v_check.id;
end; $$;
revoke all on function private.assert_replacement_handover_ready(uuid,uuid) from public,anon,authenticated;

create or replace function private.reconcile_repair_receipt_custody()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_position public.repair_device_custody_positions; v_dispatch public.repair_delivery_dispatches;
begin
 select * into v_position from public.repair_device_custody_positions
  where org_id=new.org_id and device_id=new.device_id for update;
 if v_position.device_id is null or v_position.case_id<>new.case_id then
  raise exception 'DELIVERY_CUSTODY_MISMATCH' using errcode='23514'; end if;
 if new.method='in_person' then
  if v_position.holder_kind<>'staff' or v_position.custodian_user_id<>new.handed_over_by
   or new.dispatch_id is not null then
   raise exception 'DELIVERY_CUSTODY_MISMATCH' using errcode='23514'; end if;
 else
  select * into v_dispatch from public.repair_delivery_dispatches
   where org_id=new.org_id and case_id=new.case_id and id=new.dispatch_id;
  if v_dispatch.id is null or v_dispatch.device_id<>new.device_id
   or v_position.holder_kind<>'carrier'
   or v_position.external_reference<>v_dispatch.dispatch_reference then
   raise exception 'DELIVERY_CUSTODY_MISMATCH' using errcode='23514'; end if;
 end if;
 update public.repair_device_custody_positions set holder_kind='recipient',
  custodian_user_id=null,custodian_label=new.recipient_name,
  location='نزد گیرنده: '||new.recipient_name,external_reference=new.receipt_reference,
  confirmed_at=new.received_at,confirmed_by=coalesce(new.confirmed_by,new.handed_over_by)
  where org_id=new.org_id and device_id=new.device_id;
 update public.repair_cases set device_location='نزد گیرنده: '||new.recipient_name,
  device_custodian=new.recipient_name where org_id=new.org_id and id=new.case_id and verified_device_id=new.device_id;
 return new;
end; $$;
revoke all on function private.reconcile_repair_receipt_custody() from public,anon,authenticated;
create function public.record_replacement_delivery_receipt(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_recipient_name text,p_recipient_role text,p_authority_reference text,p_receipt_reference text,p_receipt_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_check public.repair_outgoing_checks;
 v_position public.repair_device_custody_positions; v_receipt public.repair_delivery_receipts;
 v_saved private.repair_command_receipts; v_stock public.repair_replacement_stock; v_hash text; v_check_id uuid; v_response jsonb;
begin
 if v_actor is null or p_idempotency_key is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.delivery.receive') then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1
  or length(pg_catalog.btrim(coalesce(p_recipient_name,''))) not between 1 and 160
  or p_recipient_role not in ('owner','authorized_representative','colleague')
  or length(pg_catalog.btrim(coalesce(p_receipt_reference,''))) not between 1 and 160
  or length(pg_catalog.btrim(coalesce(p_receipt_evidence,''))) not between 1 and 240
  or (p_recipient_role='owner' and p_authority_reference is not null)
  or (p_recipient_role<>'owner' and length(pg_catalog.btrim(coalesce(p_authority_reference,''))) not between 1 and 240)
 then raise exception 'INVALID_DELIVERY_RECEIPT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,'recipient',pg_catalog.btrim(p_recipient_name),
  'role',p_recipient_role,'authority',p_authority_reference,'reference',pg_catalog.btrim(p_receipt_reference),'evidence',pg_catalog.btrim(p_receipt_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.delivery:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='replacement.delivery.receive' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'delivery' then raise exception 'REPLACEMENT_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 v_check_id:=private.assert_replacement_handover_ready(p_org_id,p_case_id);
 select * into v_check from public.repair_outgoing_checks where id=v_check_id;
 if v_check.intended_recipient<>pg_catalog.btrim(p_recipient_name) or v_check.recipient_role<>p_recipient_role
  or v_check.authority_reference is distinct from p_authority_reference then
  raise exception 'DELIVERY_RECIPIENT_MISMATCH' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions where org_id=p_org_id and device_id=v_check.device_id for update;
 if v_position.device_id is null or v_position.case_id<>p_case_id or v_position.holder_kind<>'staff'
  or v_position.custodian_user_id<>v_actor then raise exception 'DELIVERY_CUSTODIAN_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'DELIVERY_ALREADY_RECEIVED' using errcode='23505'; end if;
 select * into v_stock from public.repair_replacement_stock
  where org_id=p_org_id and device_id=v_check.device_id for update;
 insert into public.repair_delivery_receipts(org_id,case_id,device_id,repair_outgoing_check_id,method,
  recipient_name,recipient_role,authority_reference,receipt_reference,receipt_evidence,handed_over_by)
 values(p_org_id,p_case_id,v_check.device_id,v_check_id,'in_person',pg_catalog.btrim(p_recipient_name),
  p_recipient_role,p_authority_reference,pg_catalog.btrim(p_receipt_reference),pg_catalog.btrim(p_receipt_evidence),v_actor)
 returning * into v_receipt;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_received',v_actor,pg_catalog.jsonb_build_object('receiptId',v_receipt.id,'repairOutgoingCheckId',v_check_id,
  'recipient',v_receipt.recipient_name,'role',v_receipt.recipient_role,'reference',v_receipt.receipt_reference));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'receiptId',v_receipt.id,'version',v_case.version+1);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.delivery.receive',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_replacement_delivery_receipt(uuid,uuid,integer,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.record_replacement_delivery_receipt(uuid,uuid,integer,uuid,text,text,text,text,text) to authenticated;


create function private.guard_replacement_stock_issue() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.status='issued' and new is distinct from old then
  raise exception 'REPLACEMENT_STOCK_ALREADY_ISSUED' using errcode='23514'; end if;
 if new.status='issued' and old.status<>'issued' then
  if old.status<>'allocated' or new.allocated_case_id is distinct from old.allocated_case_id
   or new.allocated_plan_id is distinct from old.allocated_plan_id
   or not exists(select 1 from public.repair_delivery_receipts r join public.repair_outgoing_checks q
    on q.org_id=r.org_id and q.case_id=r.case_id and q.id=r.repair_outgoing_check_id
    where r.org_id=new.org_id and r.case_id=new.allocated_case_id and r.id=new.issued_receipt_id
     and r.device_id=new.device_id and q.plan_id=new.allocated_plan_id
     and q.protocol_code='replacement_outgoing_v1' and r.received_at=new.issued_at) then
   raise exception 'REPLACEMENT_ISSUE_RECEIPT_REQUIRED' using errcode='23514'; end if;
 end if;
 return new;
end; $$;
revoke all on function private.guard_replacement_stock_issue() from public,anon,authenticated;
create trigger replacement_stock_issue_guard before update on public.repair_replacement_stock
for each row execute function private.guard_replacement_stock_issue();

-- Original-device disposition is still pending: even privileged writes cannot close this slice.
create or replace function private.guard_replacement_delivery_stage() returns trigger
language plpgsql set search_path='' as $$
declare v_route text;
begin
 select route into v_route from public.repair_action_plans where org_id=new.org_id and case_id=new.id order by revision desc limit 1;
 if v_route='replacement' then
  if new.stage='closed' and old.stage<>'closed' then
   raise exception 'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' using errcode='23514'; end if;
  if old.stage='test' and new.stage='delivery' then
   perform private.assert_replacement_handover_ready(new.org_id,new.id);
  end if;
 end if;
 return new;
end; $$;

-- Keep receipt and issue atomic even for administrative inserts.
create function private.guard_replacement_receipt() returns trigger
language plpgsql set search_path='' as $$
declare v_route text; v_check public.repair_outgoing_checks; v_check_id uuid;
begin
 perform 1 from public.repair_cases where org_id=new.org_id and id=new.case_id for update;
 select route into v_route from public.repair_action_plans where org_id=new.org_id and case_id=new.case_id order by revision desc limit 1;
 if v_route='replacement' then
  v_check_id:=private.assert_replacement_handover_ready(new.org_id,new.case_id);
  select * into v_check from public.repair_outgoing_checks where id=v_check_id;
  if new.method<>'in_person' or new.dispatch_id is not null
   or new.device_id<>v_check.device_id or new.repair_outgoing_check_id is distinct from v_check.id
   or new.recipient_name<>v_check.intended_recipient or new.recipient_role<>v_check.recipient_role
   or new.authority_reference is distinct from v_check.authority_reference
   or not exists(select 1 from public.repair_cases c where c.org_id=new.org_id and c.id=new.case_id
    and c.stage='delivery' and new.received_at>=c.stage_entered_at) then
   raise exception 'REPLACEMENT_RECEIPT_MISMATCH' using errcode='23514'; end if;
 end if;
 return new;
end; $$;
revoke all on function private.guard_replacement_receipt() from public,anon,authenticated;
create trigger replacement_receipt_guard before insert on public.repair_delivery_receipts
for each row execute function private.guard_replacement_receipt();

create function private.issue_replacement_on_receipt() returns trigger
language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.repair_outgoing_checks q where q.org_id=new.org_id
  and q.case_id=new.case_id and q.id=new.repair_outgoing_check_id and q.protocol_code='replacement_outgoing_v1') then
  update public.repair_replacement_stock set status='issued',issued_receipt_id=new.id,issued_at=new.received_at
   where org_id=new.org_id and device_id=new.device_id and allocated_case_id=new.case_id and status='allocated';
  if not found then raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 end if;
 return new;
end; $$;
revoke all on function private.issue_replacement_on_receipt() from public,anon,authenticated;
create trigger replacement_receipt_issue after insert on public.repair_delivery_receipts
for each row execute function private.issue_replacement_on_receipt();

-- T08 must still start at test after extending the shared handover validator.
create or replace function public.advance_replacement_case_to_delivery(p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_saved private.repair_command_receipts;
 v_hash text; v_check_id uuid; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_idempotency_key is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'case.transition.T08') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 then raise exception 'INVALID_TRANSITION_INPUT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'expectedVersion',p_expected_version,'transitionCode','T08')::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.transition:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='transition' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'test' then raise exception 'REPLACEMENT_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 v_check_id:=private.assert_replacement_handover_ready(p_org_id,p_case_id);
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_cases set stage='delivery',stage_entered_at=v_at,version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,
  pg_catalog.jsonb_build_object('transitionCode','T08','from','test','to','delivery','replacementOutgoingCheckId',v_check_id));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','delivery','version',v_case.version+1,'transitionCode','T08');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.advance_replacement_case_to_delivery(uuid,uuid,integer,uuid) from public,anon,authenticated;
grant execute on function public.advance_replacement_case_to_delivery(uuid,uuid,integer,uuid) to authenticated;

-- Protect against privileged direct stage writes that skip the transition command.
