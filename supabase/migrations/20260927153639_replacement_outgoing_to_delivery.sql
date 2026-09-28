-- Outgoing QC is shared with repair but bound to the executed replacement serial and protocol.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.replacement.outgoing_qc.record','ثبت کنترل خروج تعویض','ثبت کنترل خروج دستگاه جایگزین و گیرندهٔ موردنظر','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,'repair.replacement.outgoing_qc.record',null from public.roles r
where r.is_system and r.name='مالک' and r.deleted_at is null
on conflict(role_id,permission_key) do nothing;
alter table public.repair_outgoing_checks drop constraint repair_outgoing_checks_protocol_code_check;
alter table public.repair_outgoing_checks add constraint repair_outgoing_checks_protocol_code_check
 check(protocol_code in ('repair_outgoing_v1','replacement_outgoing_v1'));

create function public.record_replacement_outgoing_check(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_identity_pass boolean,p_identity_evidence text,p_items_pass boolean,p_items_evidence text,
 p_condition_pass boolean,p_condition_evidence text,p_transport_pass boolean,p_transport_evidence text,
 p_intended_recipient text,p_recipient_role text,p_authority_reference text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_test public.repair_functional_tests;
 v_execution public.repair_replacement_executions; v_check public.repair_outgoing_checks; v_revision integer; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.replacement.outgoing_qc.record') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_expected_version is null or p_expected_version<1
  or p_identity_pass is null or p_items_pass is null or p_condition_pass is null or p_transport_pass is null
  or length(pg_catalog.btrim(coalesce(p_identity_evidence,''))) not between 1 and 500
  or length(pg_catalog.btrim(coalesce(p_items_evidence,''))) not between 1 and 500
  or length(pg_catalog.btrim(coalesce(p_condition_evidence,''))) not between 1 and 500
  or length(pg_catalog.btrim(coalesce(p_transport_evidence,''))) not between 1 and 500
  or length(pg_catalog.btrim(coalesce(p_intended_recipient,''))) not between 1 and 160
  or p_recipient_role is null or p_recipient_role not in ('owner','authorized_representative','colleague')
  or (p_recipient_role='owner' and p_authority_reference is not null)
  or (p_recipient_role<>'owner' and length(pg_catalog.btrim(coalesce(p_authority_reference,''))) not between 1 and 240) then
  raise exception 'INVALID_REPAIR_OUTGOING_CHECK' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,
  'identity',p_identity_pass,'identityEvidence',pg_catalog.btrim(p_identity_evidence),
  'items',p_items_pass,'itemsEvidence',pg_catalog.btrim(p_items_evidence),
  'condition',p_condition_pass,'conditionEvidence',pg_catalog.btrim(p_condition_evidence),
  'transport',p_transport_pass,'transportEvidence',pg_catalog.btrim(p_transport_evidence),
  'recipient',pg_catalog.btrim(p_intended_recipient),'role',p_recipient_role,
  'authority',p_authority_reference)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'replacement.outgoing.record:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='replacement.outgoing.record' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'test' then raise exception 'TEST_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_test from public.repair_functional_tests where org_id=p_org_id and case_id=p_case_id
  order by revision desc limit 1;
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id
  order by executed_at desc limit 1;
 if v_plan.id is null or v_plan.route<>'replacement' or v_test.id is null or not v_test.passed
  or v_test.plan_id<>v_plan.id or v_test.protocol_code<>'replacement_functional_v1'
  or v_execution.id is null or v_execution.plan_id<>v_plan.id
  or v_execution.original_device_id is distinct from v_case.verified_device_id
  or v_test.execution_id<>v_execution.id or v_test.device_id<>v_execution.replacement_device_id
  or v_test.custody_damage_epoch<>v_case.custody_damage_epoch
  or v_test.recorded_at<v_case.stage_entered_at
  or not exists(select 1 from public.repair_functional_test_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.test_id=v_test.id) then
  raise exception 'FUNCTIONAL_RELEASE_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_discrepancies d
   where d.org_id=p_org_id and d.device_id=v_test.device_id and d.status='open')
  or exists(select 1 from public.repair_device_custody_transfers t
   where t.org_id=p_org_id and t.device_id=v_test.device_id and t.status='in_transit') then
  raise exception 'DEVICE_CUSTODY_UNRESOLVED' using errcode='23514'; end if;
 select coalesce(max(revision),0)+1 into v_revision from public.repair_outgoing_checks
  where org_id=p_org_id and case_id=p_case_id;
 insert into public.repair_outgoing_checks(org_id,case_id,plan_id,functional_test_id,device_id,revision,protocol_code,
  custody_damage_epoch,identity_pass,identity_evidence,items_pass,items_evidence,
  condition_pass,condition_evidence,transport_pass,transport_evidence,
  intended_recipient,recipient_role,authority_reference,recorded_by)
 values(p_org_id,p_case_id,v_plan.id,v_test.id,v_test.device_id,v_revision,'replacement_outgoing_v1',v_case.custody_damage_epoch,
  p_identity_pass,pg_catalog.btrim(p_identity_evidence),p_items_pass,pg_catalog.btrim(p_items_evidence),
  p_condition_pass,pg_catalog.btrim(p_condition_evidence),p_transport_pass,pg_catalog.btrim(p_transport_evidence),
  pg_catalog.btrim(p_intended_recipient),p_recipient_role,
  nullif(pg_catalog.btrim(p_authority_reference),''),v_actor)
 returning * into v_check;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'repair_outgoing_checked',v_actor,
  pg_catalog.jsonb_build_object('checkId',v_check.id,'revision',v_revision,'testId',v_test.id,
   'route','replacement','passed',p_identity_pass and p_items_pass and p_condition_pass and p_transport_pass));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'checkId',v_check.id,
  'revision',v_revision,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.outgoing.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

revoke all on function public.record_replacement_outgoing_check(uuid,uuid,integer,uuid,boolean,text,boolean,text,boolean,text,boolean,text,text,text,text) from public,anon,authenticated;
grant execute on function public.record_replacement_outgoing_check(uuid,uuid,integer,uuid,boolean,text,boolean,text,boolean,text,boolean,text,text,text,text) to authenticated;

create or replace function public.release_repair_outgoing_check(
 p_org_id uuid,p_case_id uuid,p_check_id uuid,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_test public.repair_functional_tests;
 v_execution public.repair_replacement_executions; v_check public.repair_outgoing_checks; v_release public.repair_outgoing_releases; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.quality.release') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_check_id is null or p_expected_version is null or p_expected_version<1 then
  raise exception 'INVALID_REPAIR_OUTGOING_CHECK' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'checkId',p_check_id,
  'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.outgoing.release:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='repair.outgoing.release' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'test' then raise exception 'TEST_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_test from public.repair_functional_tests where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_check from public.repair_outgoing_checks where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 if v_plan.id is null or v_plan.route not in ('repair','replacement') or v_test.id is null or not v_test.passed
  or v_test.plan_id<>v_plan.id or v_test.custody_damage_epoch<>v_case.custody_damage_epoch
  or v_test.recorded_at<v_case.stage_entered_at
  or v_check.id is null or v_check.id<>p_check_id or v_check.plan_id<>v_plan.id
  or v_check.functional_test_id<>v_test.id or v_check.device_id<>v_test.device_id
  or (v_plan.route='repair' and (v_check.protocol_code<>'repair_outgoing_v1'
    or v_test.protocol_code<>'repair_functional_v1' or v_check.device_id is distinct from v_case.verified_device_id))
  or (v_plan.route='replacement' and (v_check.protocol_code<>'replacement_outgoing_v1'
    or v_test.protocol_code<>'replacement_functional_v1' or v_execution.id is null
    or v_execution.plan_id<>v_plan.id or v_execution.original_device_id is distinct from v_case.verified_device_id
    or v_test.execution_id<>v_execution.id or v_check.device_id<>v_execution.replacement_device_id))
  or v_check.custody_damage_epoch<>v_case.custody_damage_epoch
  or v_check.recorded_at<v_case.stage_entered_at
  or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass)
  or not exists(select 1 from public.repair_functional_test_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.test_id=v_test.id) then
  raise exception 'REPAIR_OUTGOING_NOT_RELEASABLE' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_discrepancies d
   where d.org_id=p_org_id and d.device_id=v_check.device_id and d.status='open')
  or exists(select 1 from public.repair_device_custody_transfers t
   where t.org_id=p_org_id and t.device_id=v_check.device_id and t.status='in_transit') then
  raise exception 'DEVICE_CUSTODY_UNRESOLVED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_outgoing_releases
   where org_id=p_org_id and case_id=p_case_id and check_id=p_check_id) then
  raise exception 'QUALITY_ALREADY_RELEASED' using errcode='23505'; end if;
 insert into public.repair_outgoing_releases(org_id,case_id,check_id,released_by)
 values(p_org_id,p_case_id,p_check_id,v_actor) returning * into v_release;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'repair_outgoing_released',v_actor,
  pg_catalog.jsonb_build_object('checkId',p_check_id,'releaseId',v_release.id,'testId',v_test.id));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'checkId',p_check_id,
  'releaseId',v_release.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'repair.outgoing.release',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

-- T08 moves the case to delivery; it neither issues stock nor records customer receipt.
create function private.assert_replacement_handover_ready(p_org_id uuid,p_case_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_case public.repair_cases; v_plan public.repair_action_plans;
 v_execution public.repair_replacement_executions; v_stock public.repair_replacement_stock;
 v_test public.repair_functional_tests; v_check public.repair_outgoing_checks;
 v_position public.repair_device_custody_positions; v_original public.repair_device_custody_positions;
 v_paid bigint;
begin
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id;
 if v_case.id is null or v_case.stage<>'test' or v_case.verified_device_id is null then
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
  or v_test.recorded_at<v_case.stage_entered_at
  or v_check.id is null or v_check.protocol_code<>'replacement_outgoing_v1'
  or v_check.plan_id<>v_plan.id or v_check.functional_test_id<>v_test.id
  or v_check.device_id<>v_execution.replacement_device_id
  or v_check.custody_damage_epoch<>v_case.custody_damage_epoch
  or v_check.recorded_at<v_case.stage_entered_at
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
 return v_check.id;
end; $$;
revoke all on function private.assert_replacement_handover_ready(uuid,uuid) from public,anon,authenticated;

create function public.advance_replacement_case_to_delivery(p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid)
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
create function private.guard_replacement_delivery_stage() returns trigger language plpgsql set search_path='' as $$
declare v_route text;
begin
 if old.stage='test' and new.stage='delivery' then
  select route into v_route from public.repair_action_plans where org_id=new.org_id and case_id=new.id order by revision desc limit 1;
  if v_route='replacement' then perform private.assert_replacement_handover_ready(new.org_id,new.id); end if;
 end if;
 return new;
end; $$;
revoke all on function private.guard_replacement_delivery_stage() from public,anon,authenticated;
create trigger replacement_delivery_stage_guard before update of stage on public.repair_cases
for each row execute function private.guard_replacement_delivery_stage();
