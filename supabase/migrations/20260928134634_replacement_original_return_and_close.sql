-- Original-device return is a separate physical receipt; proposal states stay pending.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.replacement.original_return','عودت دستگاه اولیهٔ تعویض','ثبت رسید مستقل عودت دستگاه اولیه توسط متصدی فعلی','{}') on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select id,'repair.replacement.original_return',null from public.roles
 where is_system and name='مالک' and deleted_at is null on conflict(role_id,permission_key) do nothing;
create table public.repair_replacement_original_returns (
 id uuid primary key default gen_random_uuid(), org_id uuid not null, case_id uuid not null,
 execution_id uuid not null, original_device_id uuid not null,
 recipient_name text not null, recipient_role text not null check(recipient_role in ('owner','authorized_representative','colleague')),
 authority_reference text,
 receipt_reference text not null check(length(btrim(receipt_reference)) between 1 and 160),
 receipt_evidence text not null check(length(btrim(receipt_evidence)) between 1 and 240),
 condition_note text not null check(length(btrim(condition_note)) between 1 and 500),
 returned_by uuid not null references auth.users(id), returned_at timestamptz not null default clock_timestamp(),
 unique(org_id,case_id), unique(org_id,receipt_reference), unique(org_id,case_id,id),
 foreign key(org_id,case_id,execution_id) references public.repair_replacement_executions(org_id,case_id,id),
 foreign key(org_id,original_device_id) references public.repair_devices(org_id,id),
 check((recipient_role='owner' and authority_reference is null)
  or (recipient_role<>'owner' and length(btrim(authority_reference)) between 1 and 240))
);
alter table public.repair_replacement_original_returns enable row level security;
create policy replacement_original_return_view on public.repair_replacement_original_returns for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_replacement_original_returns from public,anon,authenticated;
grant select on public.repair_replacement_original_returns to authenticated;
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
   and r.repair_outgoing_check_id=v_check.id and r.method='in_person'
   and r.received_at>=v_case.stage_entered_at and r.received_at=v_stock.issued_at
   and r.receipt_reference=v_position.external_reference) then
  raise exception 'REPLACEMENT_DELIVERY_RECEIPT_REQUIRED' using errcode='23514'; end if;
 if v_case.stage='delivery' and not exists(select 1 from public.repair_case_events e
  where e.org_id=p_org_id and e.case_id=p_case_id and e.event_type='stage_transition'
   and e.details->>'transitionCode'='T08'
   and e.details->>'replacementOutgoingCheckId'=v_check.id::text
   and e.occurred_at=v_case.stage_entered_at) then
  raise exception 'REPLACEMENT_DELIVERY_TRANSITION_REQUIRED' using errcode='23514'; end if;
 return v_check.id;
end; $$;
revoke all on function private.assert_replacement_issued_ready(uuid,uuid) from public,anon,authenticated;


create function public.record_replacement_original_return(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_receipt_reference text,p_receipt_evidence text,p_condition_note text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_execution public.repair_replacement_executions;
 v_receipt public.repair_delivery_receipts; v_position public.repair_device_custody_positions;
 v_return public.repair_replacement_original_returns; v_saved private.repair_command_receipts;
 v_hash text; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.replacement.original_return') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or p_idempotency_key is null
  or length(btrim(coalesce(p_receipt_reference,''))) not between 1 and 160
  or length(btrim(coalesce(p_receipt_evidence,''))) not between 1 and 240
  or length(btrim(coalesce(p_condition_note,''))) not between 1 and 500 then
  raise exception 'INVALID_ORIGINAL_RETURN' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'version',p_expected_version,
  'reference',btrim(p_receipt_reference),'evidence',btrim(p_receipt_evidence),'condition',btrim(p_condition_note))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.original.return:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='replacement.original.return' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 perform private.assert_replacement_issued_ready(p_org_id,p_case_id);
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 if v_execution.original_disposition_pending<>'return_to_customer' then
  raise exception 'ORIGINAL_RETURN_PLAN_REQUIRED' using errcode='23514'; end if;
 select * into v_receipt from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id;
 if btrim(p_receipt_reference)=v_receipt.receipt_reference or btrim(p_receipt_evidence)=v_receipt.receipt_evidence then
  raise exception 'ORIGINAL_RETURN_SEPARATE_EVIDENCE_REQUIRED' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.holder_kind<>'staff' or v_position.custodian_user_id is distinct from v_actor then
  raise exception 'DELIVERY_CUSTODIAN_REQUIRED' using errcode='23514'; end if;
 insert into public.repair_replacement_original_returns(org_id,case_id,execution_id,original_device_id,
  recipient_name,recipient_role,authority_reference,receipt_reference,receipt_evidence,condition_note,returned_by)
 values(p_org_id,p_case_id,v_execution.id,v_case.verified_device_id,v_receipt.recipient_name,v_receipt.recipient_role,
  v_receipt.authority_reference,btrim(p_receipt_reference),btrim(p_receipt_evidence),btrim(p_condition_note),v_actor)
 returning * into v_return;
 update public.repair_device_custody_positions set holder_kind='recipient',custodian_user_id=null,
  custodian_label=v_return.recipient_name,location='نزد گیرنده: '||v_return.recipient_name,
  external_reference=v_return.receipt_reference,confirmed_at=v_return.returned_at,confirmed_by=v_actor
  where org_id=p_org_id and device_id=v_case.verified_device_id;
 update public.repair_cases set version=version+1,device_location='نزد گیرنده: '||v_return.recipient_name,
  device_custodian=v_return.recipient_name where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_received',v_actor,jsonb_build_object('deviceRole','original',
  'originalReturnId',v_return.id,'deviceId',v_return.original_device_id,'reference',v_return.receipt_reference));
 v_response:=jsonb_build_object('caseId',p_case_id,'originalReturnId',v_return.id,'version',v_case.version+1);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.original.return',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_replacement_original_return(uuid,uuid,integer,uuid,text,text,text) from public,anon;
grant execute on function public.record_replacement_original_return(uuid,uuid,integer,uuid,text,text,text) to authenticated;

create function private.assert_replacement_close_ready(p_org_id uuid,p_case_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_check uuid; v_return public.repair_replacement_original_returns;
begin
 v_check:=private.assert_replacement_issued_ready(p_org_id,p_case_id);
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
create function public.close_replacement_case(p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid)
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
  'outcome','replaced_original_returned','deliveryReceiptId',v_receipt.id,'originalReturnId',v_check_id));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','closed','version',v_case.version+1,'transitionCode','T09');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.close_replacement_case(uuid,uuid,integer,uuid) from public,anon;
grant execute on function public.close_replacement_case(uuid,uuid,integer,uuid) to authenticated;

create or replace function private.guard_replacement_delivery_stage() returns trigger
language plpgsql set search_path='' as $$
declare v_route text;
begin
 select route into v_route from public.repair_action_plans where org_id=new.org_id and case_id=new.id order by revision desc limit 1;
 if v_route='replacement' then
  if new.stage='closed' and old.stage<>'closed' then perform private.assert_replacement_close_ready(new.org_id,new.id); end if;
  if old.stage='test' and new.stage='delivery' then perform private.assert_replacement_handover_ready(new.org_id,new.id); end if;
 end if;
 return new;
end; $$;
create or replace function public.record_repair_device_custody_baseline(
 p_org_id uuid,p_case_id uuid,p_location text,p_custodian_user_id uuid,p_evidence text,
 p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_position public.repair_device_custody_positions; v_label text; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_custodian_user_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'custody.baseline.record')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or length(btrim(coalesce(p_location,''))) not between 1 and 200
 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_CUSTODY_BASELINE' using errcode='23514'; end if;
 v_hash:=md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'location',btrim(p_location),
 'custodianId',p_custodian_user_id,'evidence',btrim(p_evidence),'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.custody.baseline:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='custody.baseline' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage='closed' or v_case.received_at is null or v_case.verified_device_id is null
 then raise exception 'VERIFIED_DEVICE_REQUIRED' using errcode='23514'; end if;
 if v_case.device_location is not null and btrim(v_case.device_location)<>btrim(p_location)
 then raise exception 'CUSTODY_BASELINE_LOCATION_MISMATCH' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.device_id is not null and not (
  v_position.holder_kind='recipient' and v_position.case_id<>p_case_id
  and exists(select 1 from public.repair_cases old_case
   join (select org_id,case_id,device_id,receipt_reference,received_at from public.repair_delivery_receipts
    union all select org_id,case_id,original_device_id,receipt_reference,returned_at from public.repair_replacement_original_returns) receipt
    on receipt.org_id=old_case.org_id
    and receipt.case_id=old_case.id and receipt.device_id=v_case.verified_device_id
   where old_case.org_id=p_org_id and old_case.id=v_position.case_id
    and old_case.closed_at is not null and receipt.receipt_reference=v_position.external_reference
    and v_case.received_at>=receipt.received_at)) then
  raise exception 'CUSTODY_BASELINE_EXISTS' using errcode='23505'; end if;
 select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),''),p_custodian_user_id::text) into v_label
 from public.org_members m join public.profiles p on p.id=m.user_id
 where m.org_id=p_org_id and m.user_id=p_custodian_user_id and m.deleted_at is null and m.invitation_status='active';
 if v_label is null then raise exception 'CUSTODY_MEMBER_INACTIVE' using errcode='23514'; end if;
 if v_position.device_id is null then
  insert into public.repair_device_custody_positions(org_id,device_id,case_id,location,custodian_user_id,custodian_label,baseline_evidence,confirmed_by)
  values(p_org_id,v_case.verified_device_id,p_case_id,btrim(p_location),p_custodian_user_id,v_label,btrim(p_evidence),v_actor);
 else
  update public.repair_device_custody_positions set case_id=p_case_id,location=btrim(p_location),
   holder_kind='staff',custodian_user_id=p_custodian_user_id,custodian_label=v_label,
   external_reference=null,baseline_evidence=btrim(p_evidence),confirmed_by=v_actor,
   confirmed_at=pg_catalog.clock_timestamp()
   where org_id=p_org_id and device_id=v_case.verified_device_id;
 end if;
 update public.repair_cases set device_location=btrim(p_location),device_custodian=v_label,version=version+1
 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'custody_baseline_recorded',v_actor,
 pg_catalog.jsonb_build_object('deviceId',v_case.verified_device_id,'location',btrim(p_location),'custodianId',p_custodian_user_id,'evidence',btrim(p_evidence),'reentry',v_position.device_id is not null));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'deviceId',v_case.verified_device_id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.baseline',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

-- A documented shipment return restores the device to the actual receiving staff member.
