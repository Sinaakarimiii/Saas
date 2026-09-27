-- A replacement test is bound to the executed serial, while repaired-device tests retain their completion binding.
alter table public.repair_functional_tests alter column completion_id drop not null;
alter table public.repair_functional_tests add column execution_id uuid;
alter table public.repair_functional_tests add constraint repair_functional_tests_execution_fkey
 foreign key(org_id,case_id,execution_id) references public.repair_replacement_executions(org_id,case_id,id);
alter table public.repair_functional_tests add constraint repair_functional_tests_source_check
 check((completion_id is not null and execution_id is null and protocol_code='repair_functional_v1')
    or (completion_id is null and execution_id is not null and protocol_code='replacement_functional_v1'));
alter table public.repair_functional_tests drop constraint repair_functional_tests_protocol_code_check;
alter table public.repair_functional_tests add constraint repair_functional_tests_protocol_code_check
 check(protocol_code in ('repair_functional_v1','replacement_functional_v1'));

create function public.record_repair_replacement_functional_test(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_identity_status text,p_identity_evidence text,p_power_status text,p_power_evidence text,
 p_position_status text,p_position_evidence text,p_configuration_status text,p_configuration_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_execution public.repair_replacement_executions;
 v_test public.repair_functional_tests; v_revision integer; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
   or not private.has_permission(p_org_id,'repair.test.record') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_expected_version is null or p_expected_version<1
   or p_identity_status is null or p_identity_status not in ('pass','fail')
   or p_power_status is null or p_power_status not in ('pass','fail')
   or p_position_status is null or p_position_status not in ('pass','fail','not_applicable')
   or p_configuration_status is null or p_configuration_status not in ('pass','fail','not_applicable')
   or length(pg_catalog.btrim(coalesce(p_identity_evidence,''))) not between 1 and 500
   or length(pg_catalog.btrim(coalesce(p_power_evidence,''))) not between 1 and 500
   or length(pg_catalog.btrim(coalesce(p_position_evidence,''))) not between 1 and 500
   or length(pg_catalog.btrim(coalesce(p_configuration_evidence,''))) not between 1 and 500 then
  raise exception 'INVALID_FUNCTIONAL_TEST' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,
  'identity',p_identity_status,'identityEvidence',pg_catalog.btrim(p_identity_evidence),
  'power',p_power_status,'powerEvidence',pg_catalog.btrim(p_power_evidence),
  'position',p_position_status,'positionEvidence',pg_catalog.btrim(p_position_evidence),
  'configuration',p_configuration_status,'configurationEvidence',pg_catalog.btrim(p_configuration_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'replacement.functional.test:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
   and operation='replacement.test.record' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'test' then raise exception 'TEST_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id
   order by executed_at desc limit 1;
 if v_plan.id is null or v_plan.route<>'replacement' or v_execution.id is null
   or v_execution.plan_id<>v_plan.id
   or v_execution.original_device_id is distinct from v_case.verified_device_id
   or v_execution.executed_at>v_case.stage_entered_at then
  raise exception 'REPLACEMENT_EXECUTION_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_discrepancies d
   where d.org_id=p_org_id and d.device_id=v_execution.replacement_device_id and d.status='open')
   or exists(select 1 from public.repair_device_custody_transfers t
   where t.org_id=p_org_id and t.device_id=v_execution.replacement_device_id and t.status='in_transit') then
  raise exception 'DEVICE_CUSTODY_UNRESOLVED' using errcode='23514'; end if;
 select coalesce(max(revision),0)+1 into v_revision from public.repair_functional_tests
   where org_id=p_org_id and case_id=p_case_id;
 insert into public.repair_functional_tests(org_id,case_id,plan_id,execution_id,device_id,revision,protocol_code,
  custody_damage_epoch,identity_status,identity_evidence,power_status,power_evidence,
  position_status,position_evidence,configuration_status,configuration_evidence,recorded_by)
 values(p_org_id,p_case_id,v_plan.id,v_execution.id,v_execution.replacement_device_id,v_revision,'replacement_functional_v1',
  v_case.custody_damage_epoch,p_identity_status,pg_catalog.btrim(p_identity_evidence),
  p_power_status,pg_catalog.btrim(p_power_evidence),p_position_status,pg_catalog.btrim(p_position_evidence),
  p_configuration_status,pg_catalog.btrim(p_configuration_evidence),v_actor) returning * into v_test;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'functional_test_recorded',v_actor,
  pg_catalog.jsonb_build_object('testId',v_test.id,'revision',v_revision,'passed',v_test.passed,
    'deviceId',v_test.device_id,'executionId',v_execution.id,'route','replacement'));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'testId',v_test.id,
  'revision',v_revision,'passed',v_test.passed,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.test.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

revoke all on function public.record_repair_replacement_functional_test(uuid,uuid,integer,uuid,text,text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.record_repair_replacement_functional_test(uuid,uuid,integer,uuid,text,text,text,text,text,text,text,text) to authenticated;

create or replace function public.release_repair_functional_test(
 p_org_id uuid,p_case_id uuid,p_test_id uuid,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_test public.repair_functional_tests;
 v_release public.repair_functional_test_releases; v_execution public.repair_replacement_executions; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
   or not private.has_permission(p_org_id,'repair.quality.release') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_test_id is null or p_expected_version is null or p_expected_version<1 then
  raise exception 'INVALID_FUNCTIONAL_TEST' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'testId',p_test_id,
   'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.functional.release:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
   and operation='repair.test.release' and idempotency_key=p_idempotency_key;
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
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 if v_test.id is null or v_test.id<>p_test_id or not v_test.passed or v_plan.id is null
   or v_plan.route not in ('repair','replacement') or v_test.plan_id<>v_plan.id
   or v_test.custody_damage_epoch<>v_case.custody_damage_epoch
   or v_test.recorded_at<v_case.stage_entered_at
   or (v_plan.route='repair' and (v_test.protocol_code<>'repair_functional_v1'
      or v_test.device_id is distinct from v_case.verified_device_id or v_test.completion_id is null or v_test.execution_id is not null))
   or (v_plan.route='replacement' and (v_test.protocol_code<>'replacement_functional_v1'
      or v_execution.id is null or v_execution.plan_id<>v_plan.id
      or v_execution.original_device_id is distinct from v_case.verified_device_id
      or v_test.execution_id<>v_execution.id or v_test.completion_id is not null
      or v_test.device_id<>v_execution.replacement_device_id)) then
  raise exception 'FUNCTIONAL_TEST_NOT_RELEASABLE' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_discrepancies d
   where d.org_id=p_org_id and d.device_id=v_test.device_id and d.status='open')
   or exists(select 1 from public.repair_device_custody_transfers t
   where t.org_id=p_org_id and t.device_id=v_test.device_id and t.status='in_transit') then
  raise exception 'DEVICE_CUSTODY_UNRESOLVED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_functional_test_releases
   where org_id=p_org_id and case_id=p_case_id and test_id=p_test_id) then
  raise exception 'QUALITY_ALREADY_RELEASED' using errcode='23505'; end if;
 insert into public.repair_functional_test_releases(org_id,case_id,test_id,released_by)
 values(p_org_id,p_case_id,p_test_id,v_actor) returning * into v_release;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'functional_test_released',v_actor,
  pg_catalog.jsonb_build_object('testId',p_test_id,'releaseId',v_release.id));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'testId',p_test_id,
  'releaseId',v_release.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'repair.test.release',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
