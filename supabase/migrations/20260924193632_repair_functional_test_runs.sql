-- The functional test is separate from repair completion and return outgoing QC.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.test.record','ثبت آزمون عملکرد تعمیر','ثبت نتیجه و شواهد هر کنترل آزمون تعمیر','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,'repair.test.record',null from public.roles r
where r.is_system and r.name='مالک' and r.deleted_at is null
on conflict(role_id,permission_key) do nothing;

create table public.repair_functional_tests (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, plan_id uuid not null,
 completion_id uuid not null, device_id uuid not null,
 revision integer not null check(revision>0),
 protocol_code text not null default 'repair_functional_v1' check(protocol_code='repair_functional_v1'),
 custody_damage_epoch integer not null check(custody_damage_epoch>=0),
 identity_status text not null check(identity_status in ('pass','fail')),
 identity_evidence text not null check(length(pg_catalog.btrim(identity_evidence)) between 1 and 500),
 power_status text not null check(power_status in ('pass','fail')),
 power_evidence text not null check(length(pg_catalog.btrim(power_evidence)) between 1 and 500),
 position_status text not null check(position_status in ('pass','fail','not_applicable')),
 position_evidence text not null check(length(pg_catalog.btrim(position_evidence)) between 1 and 500),
 configuration_status text not null check(configuration_status in ('pass','fail','not_applicable')),
 configuration_evidence text not null check(length(pg_catalog.btrim(configuration_evidence)) between 1 and 500),
 passed boolean generated always as (identity_status='pass' and power_status='pass'
   and position_status<>'fail' and configuration_status<>'fail') stored,
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,case_id,revision), unique(org_id,case_id,id),
 foreign key(org_id,case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,case_id,plan_id) references public.repair_action_plans(org_id,case_id,id),
 foreign key(org_id,case_id,completion_id) references public.repair_completions(org_id,case_id,id),
 foreign key(org_id,device_id) references public.repair_devices(org_id,id)
);
create index repair_functional_tests_latest_idx on public.repair_functional_tests(org_id,case_id,revision desc);
create table public.repair_functional_test_releases (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, test_id uuid not null,
 released_by uuid not null references auth.users(id),
 released_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,case_id,test_id),
 foreign key(org_id,case_id,test_id) references public.repair_functional_tests(org_id,case_id,id)
);
alter table public.repair_functional_tests enable row level security;
alter table public.repair_functional_test_releases enable row level security;
create policy repair_functional_tests_select_authorized on public.repair_functional_tests
 for select to authenticated using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
create policy repair_functional_test_releases_select_authorized on public.repair_functional_test_releases
 for select to authenticated using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_functional_tests,public.repair_functional_test_releases from public,anon,authenticated;
grant select on public.repair_functional_tests,public.repair_functional_test_releases to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
check(event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved',
'custody_baseline_recorded','custody_released','custody_accepted','custody_returned',
'custody_discrepancy_recorded','custody_discrepancy_resolved','delivery_received','delivery_dispatched',
'delivery_incident_recorded','delivery_incident_followed_up','delivery_incident_resolved',
'delivery_damage_returned','replacement_allocated','functional_test_recorded','functional_test_released'));

create function public.record_repair_functional_test(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_identity_status text,p_identity_evidence text,p_power_status text,p_power_evidence text,
 p_position_status text,p_position_evidence text,p_configuration_status text,p_configuration_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_completion public.repair_completions;
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
  'repair.functional.test:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
   and operation='repair.test.record' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'test' then raise exception 'TEST_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_completion from public.repair_completions where org_id=p_org_id and case_id=p_case_id
   order by completed_at desc limit 1;
 if v_plan.id is null or v_plan.route<>'repair' or v_completion.id is null
   or v_completion.plan_id<>v_plan.id or v_completion.device_id is distinct from v_case.verified_device_id
   or v_completion.protocol_code<>'repair_functional_v1'
   or v_completion.completed_at>v_case.stage_entered_at then
  raise exception 'REPAIR_COMPLETION_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_discrepancies d
   where d.org_id=p_org_id and d.device_id=v_completion.device_id and d.status='open')
   or exists(select 1 from public.repair_device_custody_transfers t
   where t.org_id=p_org_id and t.device_id=v_completion.device_id and t.status='in_transit') then
  raise exception 'DEVICE_CUSTODY_UNRESOLVED' using errcode='23514'; end if;
 select coalesce(max(revision),0)+1 into v_revision from public.repair_functional_tests
   where org_id=p_org_id and case_id=p_case_id;
 insert into public.repair_functional_tests(org_id,case_id,plan_id,completion_id,device_id,revision,
  custody_damage_epoch,identity_status,identity_evidence,power_status,power_evidence,
  position_status,position_evidence,configuration_status,configuration_evidence,recorded_by)
 values(p_org_id,p_case_id,v_plan.id,v_completion.id,v_completion.device_id,v_revision,
  v_case.custody_damage_epoch,p_identity_status,pg_catalog.btrim(p_identity_evidence),
  p_power_status,pg_catalog.btrim(p_power_evidence),p_position_status,pg_catalog.btrim(p_position_evidence),
  p_configuration_status,pg_catalog.btrim(p_configuration_evidence),v_actor) returning * into v_test;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'functional_test_recorded',v_actor,
  pg_catalog.jsonb_build_object('testId',v_test.id,'revision',v_revision,'passed',v_test.passed,
    'deviceId',v_test.device_id,'completionId',v_completion.id));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'testId',v_test.id,
  'revision',v_revision,'passed',v_test.passed,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'repair.test.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_repair_functional_test(uuid,uuid,integer,uuid,text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.record_repair_functional_test(uuid,uuid,integer,uuid,text,text,text,text,text,text,text,text) to authenticated;

create function public.release_repair_functional_test(
 p_org_id uuid,p_case_id uuid,p_test_id uuid,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_test public.repair_functional_tests;
 v_release public.repair_functional_test_releases; v_response jsonb;
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
 if v_test.id is null or v_test.id<>p_test_id or not v_test.passed or v_plan.id is null
   or v_plan.route<>'repair' or v_test.plan_id<>v_plan.id
   or v_test.device_id is distinct from v_case.verified_device_id
   or v_test.custody_damage_epoch<>v_case.custody_damage_epoch
   or v_test.recorded_at<v_case.stage_entered_at then
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
revoke all on function public.release_repair_functional_test(uuid,uuid,uuid,integer,uuid) from public,anon;
grant execute on function public.release_repair_functional_test(uuid,uuid,uuid,integer,uuid) to authenticated;
