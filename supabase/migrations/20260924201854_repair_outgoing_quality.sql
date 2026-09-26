-- Outgoing control for repaired devices is separate from the functional test
-- and the zero-cost return protocol. T08 is intentionally unchanged here.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.outgoing_qc.record','ثبت کنترل خروج تعمیر','ثبت کنترل خروج و گیرنده دستگاه تعمیرشده','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,'repair.outgoing_qc.record',null from public.roles r
where r.is_system and r.name='مالک' and r.deleted_at is null
on conflict(role_id,permission_key) do nothing;

create table public.repair_outgoing_checks (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, plan_id uuid not null,
 functional_test_id uuid not null, device_id uuid not null,
 revision integer not null check(revision>0),
 protocol_code text not null default 'repair_outgoing_v1' check(protocol_code='repair_outgoing_v1'),
 custody_damage_epoch integer not null check(custody_damage_epoch>=0),
 identity_pass boolean not null,
 identity_evidence text not null check(length(pg_catalog.btrim(identity_evidence)) between 1 and 500),
 items_pass boolean not null,
 items_evidence text not null check(length(pg_catalog.btrim(items_evidence)) between 1 and 500),
 condition_pass boolean not null,
 condition_evidence text not null check(length(pg_catalog.btrim(condition_evidence)) between 1 and 500),
 transport_pass boolean not null,
 transport_evidence text not null check(length(pg_catalog.btrim(transport_evidence)) between 1 and 500),
 intended_recipient text not null check(length(pg_catalog.btrim(intended_recipient)) between 1 and 160),
 recipient_role text not null check(recipient_role in ('owner','authorized_representative','colleague')),
 authority_reference text,
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,case_id,revision), unique(org_id,case_id,id),
 foreign key(org_id,case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,case_id,plan_id) references public.repair_action_plans(org_id,case_id,id),
 foreign key(org_id,case_id,functional_test_id) references public.repair_functional_tests(org_id,case_id,id),
 foreign key(org_id,device_id) references public.repair_devices(org_id,id),
 check((recipient_role='owner' and authority_reference is null)
   or (recipient_role<>'owner' and length(pg_catalog.btrim(authority_reference)) between 1 and 240))
);
create index repair_outgoing_checks_latest_idx on public.repair_outgoing_checks(org_id,case_id,revision desc);
create table public.repair_outgoing_releases (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, check_id uuid not null,
 released_by uuid not null references auth.users(id),
 released_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,case_id,check_id),
 foreign key(org_id,case_id,check_id) references public.repair_outgoing_checks(org_id,case_id,id)
);
alter table public.repair_outgoing_checks enable row level security;
alter table public.repair_outgoing_releases enable row level security;
create policy repair_outgoing_checks_select on public.repair_outgoing_checks for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
create policy repair_outgoing_releases_select on public.repair_outgoing_releases for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_outgoing_checks,public.repair_outgoing_releases from public,anon,authenticated;
grant select on public.repair_outgoing_checks,public.repair_outgoing_releases to authenticated;

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
'delivery_damage_returned','replacement_allocated','functional_test_recorded','functional_test_released',
'payment_recorded','payment_verified','repair_outgoing_checked','repair_outgoing_released'));

create function public.record_repair_outgoing_check(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_identity_pass boolean,p_identity_evidence text,p_items_pass boolean,p_items_evidence text,
 p_condition_pass boolean,p_condition_evidence text,p_transport_pass boolean,p_transport_evidence text,
 p_intended_recipient text,p_recipient_role text,p_authority_reference text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_test public.repair_functional_tests;
 v_check public.repair_outgoing_checks; v_revision integer; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.outgoing_qc.record') then
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
  'repair.outgoing.record:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='repair.outgoing.record' and idempotency_key=p_idempotency_key;
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
 if v_plan.id is null or v_plan.route<>'repair' or v_test.id is null or not v_test.passed
  or v_test.plan_id<>v_plan.id or v_test.device_id is distinct from v_case.verified_device_id
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
 insert into public.repair_outgoing_checks(org_id,case_id,plan_id,functional_test_id,device_id,revision,
  custody_damage_epoch,identity_pass,identity_evidence,items_pass,items_evidence,
  condition_pass,condition_evidence,transport_pass,transport_evidence,
  intended_recipient,recipient_role,authority_reference,recorded_by)
 values(p_org_id,p_case_id,v_plan.id,v_test.id,v_test.device_id,v_revision,v_case.custody_damage_epoch,
  p_identity_pass,pg_catalog.btrim(p_identity_evidence),p_items_pass,pg_catalog.btrim(p_items_evidence),
  p_condition_pass,pg_catalog.btrim(p_condition_evidence),p_transport_pass,pg_catalog.btrim(p_transport_evidence),
  pg_catalog.btrim(p_intended_recipient),p_recipient_role,
  nullif(pg_catalog.btrim(p_authority_reference),''),v_actor)
 returning * into v_check;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'repair_outgoing_checked',v_actor,
  pg_catalog.jsonb_build_object('checkId',v_check.id,'revision',v_revision,'testId',v_test.id,
   'passed',p_identity_pass and p_items_pass and p_condition_pass and p_transport_pass));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'checkId',v_check.id,
  'revision',v_revision,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'repair.outgoing.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_repair_outgoing_check(uuid,uuid,integer,uuid,boolean,text,boolean,text,boolean,text,boolean,text,text,text,text) from public,anon;
grant execute on function public.record_repair_outgoing_check(uuid,uuid,integer,uuid,boolean,text,boolean,text,boolean,text,boolean,text,text,text,text) to authenticated;

create function public.release_repair_outgoing_check(
 p_org_id uuid,p_case_id uuid,p_check_id uuid,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_test public.repair_functional_tests;
 v_check public.repair_outgoing_checks; v_release public.repair_outgoing_releases; v_response jsonb;
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
 if v_plan.id is null or v_plan.route<>'repair' or v_test.id is null or not v_test.passed
  or v_check.id is null or v_check.id<>p_check_id or v_check.plan_id<>v_plan.id
  or v_check.functional_test_id<>v_test.id or v_check.device_id is distinct from v_case.verified_device_id
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
revoke all on function public.release_repair_outgoing_check(uuid,uuid,uuid,integer,uuid) from public,anon;
grant execute on function public.release_repair_outgoing_check(uuid,uuid,uuid,integer,uuid) to authenticated;
