-- Return outgoing QC records physical release readiness, never a claim of repair or health.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('repair.return_qc.record', 'ثبت کنترل خروج عودت', 'ثبت نتایج و شواهد کنترل خروج دستگاه عودتی', '{}'),
  ('repair.quality.release', 'آزادسازی کنترل کیفیت عودت', 'تأیید مستقل آخرین کنترل خروج عودت', '{}'),
  ('case.transition.T08', 'ارجاع از کنترل خروج به تحویل', 'انتقال عودت آزادشده از تست به تحویل', '{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
  and p.key in ('repair.return_qc.record', 'repair.quality.release', 'case.transition.T08')
on conflict (role_id, permission_key) do nothing;

alter table public.repair_return_authorizations
  add constraint repair_return_authorizations_org_case_id_unique unique (org_id, case_id, id);

create table public.repair_return_outgoing_checks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  plan_id uuid not null,
  authorization_id uuid not null,
  device_id uuid not null,
  revision integer not null check (revision > 0),
  protocol_code text not null default 'return_outgoing_v1' check (protocol_code = 'return_outgoing_v1'),
  identity_pass boolean not null,
  identity_evidence text not null check (length(btrim(identity_evidence)) between 1 and 500),
  items_pass boolean not null,
  items_evidence text not null check (length(btrim(items_evidence)) between 1 and 500),
  condition_pass boolean not null,
  condition_evidence text not null check (length(btrim(condition_evidence)) between 1 and 500),
  transport_pass boolean not null,
  transport_evidence text not null check (length(btrim(transport_evidence)) between 1 and 500),
  intended_recipient text not null check (length(btrim(intended_recipient)) between 1 and 160),
  recipient_role text not null check (recipient_role in ('owner', 'authorized_representative', 'colleague')),
  authority_reference text,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  unique (org_id, case_id, revision),
  unique (org_id, case_id, id),
  foreign key (org_id, case_id) references public.repair_cases(org_id, id),
  foreign key (org_id, case_id, plan_id) references public.repair_action_plans(org_id, case_id, id),
  foreign key (org_id, case_id, authorization_id) references public.repair_return_authorizations(org_id, case_id, id),
  foreign key (org_id, device_id) references public.repair_devices(org_id, id),
  check ((recipient_role = 'owner' and authority_reference is null)
      or (recipient_role <> 'owner' and length(btrim(authority_reference)) between 1 and 240))
);
create index repair_return_outgoing_checks_latest_idx
  on public.repair_return_outgoing_checks (org_id, case_id, revision desc);
create table public.repair_return_outgoing_releases (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  check_id uuid not null,
  released_by uuid not null references auth.users(id),
  released_at timestamptz not null default pg_catalog.clock_timestamp(),
  unique (org_id, case_id, check_id),
  foreign key (org_id, case_id, check_id) references public.repair_return_outgoing_checks(org_id, case_id, id)
);
alter table public.repair_return_outgoing_checks enable row level security;
alter table public.repair_return_outgoing_releases enable row level security;
create policy repair_return_outgoing_checks_select_authorized on public.repair_return_outgoing_checks
  for select to authenticated using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
create policy repair_return_outgoing_releases_select_authorized on public.repair_return_outgoing_releases
  for select to authenticated using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
revoke all on public.repair_return_outgoing_checks, public.repair_return_outgoing_releases from public, anon, authenticated;
grant select on public.repair_return_outgoing_checks, public.repair_return_outgoing_releases to authenticated;
alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
  check (event_type in ('created', 'received', 'imei_verified', 'duplicate_override',
    'stage_transition', 'diagnosis_saved', 'diagnosis_finalized', 'plan_saved',
    'plan_approval_recorded', 'return_authorized', 'return_outgoing_checked', 'return_outgoing_released'));

create function public.record_repair_return_outgoing_check(
  p_org_id uuid, p_case_id uuid, p_expected_version integer, p_idempotency_key uuid,
  p_identity_pass boolean, p_identity_evidence text, p_items_pass boolean, p_items_evidence text,
  p_condition_pass boolean, p_condition_evidence text, p_transport_pass boolean, p_transport_evidence text,
  p_intended_recipient text, p_recipient_role text, p_authority_reference text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_plan public.repair_action_plans;
  v_authorization public.repair_return_authorizations;
  v_check public.repair_return_outgoing_checks;
  v_revision integer;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'repair.return_qc.record') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or p_identity_pass is null or length(btrim(coalesce(p_identity_evidence, ''))) not between 1 and 500
     or p_items_pass is null or length(btrim(coalesce(p_items_evidence, ''))) not between 1 and 500
     or p_condition_pass is null or length(btrim(coalesce(p_condition_evidence, ''))) not between 1 and 500
     or p_transport_pass is null or length(btrim(coalesce(p_transport_evidence, ''))) not between 1 and 500
     or length(btrim(coalesce(p_intended_recipient, ''))) not between 1 and 160
     or p_recipient_role is null or p_recipient_role not in ('owner', 'authorized_representative', 'colleague')
     or (p_recipient_role = 'owner' and p_authority_reference is not null)
     or (p_recipient_role <> 'owner' and length(btrim(coalesce(p_authority_reference, ''))) not between 1 and 240) then
    raise exception 'INVALID_RETURN_QC' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id, 'version', p_expected_version,
    'identityPass', p_identity_pass, 'identityEvidence', btrim(p_identity_evidence),
    'itemsPass', p_items_pass, 'itemsEvidence', btrim(p_items_evidence),
    'conditionPass', p_condition_pass, 'conditionEvidence', btrim(p_condition_evidence),
    'transportPass', p_transport_pass, 'transportEvidence', btrim(p_transport_evidence),
    'recipient', btrim(p_intended_recipient), 'role', p_recipient_role,
    'authority', p_authority_reference)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.return.qc:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'return.qc.record' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'test' then raise exception 'TEST_STAGE_REQUIRED' using errcode = '23514'; end if;
  if v_case.verified_device_id is null then raise exception 'VERIFIED_DEVICE_REQUIRED' using errcode = '23514'; end if;
  select * into v_plan from public.repair_action_plans
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  if v_plan.id is null or v_plan.route <> 'return' then
    raise exception 'RETURN_QC_REQUIRED' using errcode = '23514';
  end if;
  select * into v_authorization from public.repair_return_authorizations
    where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id;
  if v_authorization.id is null or v_authorization.protocol_code <> 'return_outgoing_v1' then
    raise exception 'RETURN_AUTHORIZATION_REQUIRED' using errcode = '23514';
  end if;
  select coalesce(max(revision), 0) + 1 into v_revision from public.repair_return_outgoing_checks
    where org_id = p_org_id and case_id = p_case_id;
  insert into public.repair_return_outgoing_checks (org_id, case_id, plan_id, authorization_id, device_id,
    revision, identity_pass, identity_evidence, items_pass, items_evidence,
    condition_pass, condition_evidence, transport_pass, transport_evidence,
    intended_recipient, recipient_role, authority_reference, recorded_by)
  values (p_org_id, p_case_id, v_plan.id, v_authorization.id, v_case.verified_device_id,
    v_revision, p_identity_pass, btrim(p_identity_evidence), p_items_pass, btrim(p_items_evidence),
    p_condition_pass, btrim(p_condition_evidence), p_transport_pass, btrim(p_transport_evidence),
    btrim(p_intended_recipient), p_recipient_role, nullif(btrim(p_authority_reference), ''), v_actor)
  returning * into v_check;
  update public.repair_cases set version = version + 1 where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'return_outgoing_checked', v_actor,
      pg_catalog.jsonb_build_object('checkId', v_check.id, 'revision', v_revision,
        'passed', p_identity_pass and p_items_pass and p_condition_pass and p_transport_pass));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'checkId', v_check.id,
    'revision', v_revision, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'return.qc.record', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
revoke all on function public.record_repair_return_outgoing_check(uuid, uuid, integer, uuid,
  boolean, text, boolean, text, boolean, text, boolean, text, text, text, text) from public, anon, authenticated;
grant execute on function public.record_repair_return_outgoing_check(uuid, uuid, integer, uuid,
  boolean, text, boolean, text, boolean, text, boolean, text, text, text, text) to authenticated;

create function public.release_repair_return_outgoing_check(
  p_org_id uuid, p_case_id uuid, p_check_id uuid, p_expected_version integer, p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_plan public.repair_action_plans;
  v_check public.repair_return_outgoing_checks;
  v_release public.repair_return_outgoing_releases;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_check_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id, 'repair.quality.release') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'INVALID_RETURN_QC' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id, 'checkId', p_check_id,
    'version', p_expected_version)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.return.qc.release:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'return.qc.release' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'test' then raise exception 'TEST_STAGE_REQUIRED' using errcode = '23514'; end if;
  select * into v_plan from public.repair_action_plans
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  select * into v_check from public.repair_return_outgoing_checks
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  if v_check.id is null or v_check.id <> p_check_id or v_plan.id is null
     or v_plan.id <> v_check.plan_id or v_plan.route <> 'return'
     or v_check.device_id is distinct from v_case.verified_device_id
     or v_check.created_at < v_case.stage_entered_at
     or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass) then
    raise exception 'RETURN_QC_REQUIRED' using errcode = '23514';
  end if;
  if exists (select 1 from public.repair_return_outgoing_releases
    where org_id = p_org_id and case_id = p_case_id and check_id = v_check.id) then
    raise exception 'QUALITY_ALREADY_RELEASED' using errcode = '23505';
  end if;
  insert into public.repair_return_outgoing_releases (org_id, case_id, check_id, released_by)
    values (p_org_id, p_case_id, p_check_id, v_actor) returning * into v_release;
  update public.repair_cases set version = version + 1 where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'return_outgoing_released', v_actor,
      pg_catalog.jsonb_build_object('checkId', p_check_id, 'releaseId', v_release.id));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'checkId', p_check_id,
    'releaseId', v_release.id, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'return.qc.release', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
revoke all on function public.release_repair_return_outgoing_check(uuid, uuid, uuid, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.release_repair_return_outgoing_check(uuid, uuid, uuid, integer, uuid)
  to authenticated;

create or replace function public.transition_repair_case(
  p_org_id uuid, p_case_id uuid, p_expected_version integer,
  p_transition_code text, p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_diagnosis public.repair_diagnoses;
  v_plan public.repair_action_plans;
  v_return_authorization public.repair_return_authorizations;
  v_check public.repair_return_outgoing_checks;
  v_release public.repair_return_outgoing_releases;
  v_customer_decision text;
  v_replacement_decision text;
  v_from text;
  v_to text;
  v_at timestamptz;
  v_previous_entered_at timestamptz;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or p_transition_code is null or p_transition_code not in ('T01', 'T02', 'T03', 'T04', 'T05', 'T08', 'T10')
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'case.transition.' || p_transition_code)
     or (p_transition_code = 'T02' and not private.has_permission(p_org_id, 'repair.diagnosis.finalize')) then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'INVALID_TRANSITION_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id,
    'expectedVersion', p_expected_version, 'transitionCode', p_transition_code)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.transition:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'transition' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases
    where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  v_from := v_case.stage;
  if p_transition_code = 'T01' and v_from = 'intake' then
    v_to := 'diagnosis';
    if v_case.received_at is null or nullif(pg_catalog.btrim(coalesce(v_case.device_location, '')), '') is null
       or nullif(pg_catalog.btrim(coalesce(v_case.device_custodian, '')), '') is null
       or (v_case.verified_device_id is null and nullif(pg_catalog.btrim(coalesce(v_case.raw_identifier, '')), '') is null)
       or nullif(pg_catalog.btrim(v_case.device_model), '') is null
       or nullif(pg_catalog.btrim(v_case.issue), '') is null then
      raise exception 'INTAKE_INCOMPLETE' using errcode = '23514';
    end if;
  elsif p_transition_code = 'T02' and v_from = 'diagnosis' then
    select * into v_diagnosis from public.repair_diagnoses
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if not found or v_diagnosis.status <> 'final'
       or v_diagnosis.created_at < v_case.stage_entered_at
       or v_diagnosis.finalized_at < v_case.stage_entered_at
       or v_diagnosis.technical_condition = 'unknown' then
      raise exception 'FINAL_DIAGNOSIS_REQUIRED' using errcode = '23514';
    end if;
    v_to := 'decision';
  elsif p_transition_code in ('T03', 'T04') and v_from = 'decision' then
    select * into v_plan from public.repair_action_plans
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    select * into v_diagnosis from public.repair_diagnoses
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if v_plan.id is null or v_diagnosis.id is null or v_plan.created_at < v_case.stage_entered_at
       or v_plan.diagnosis_id <> v_diagnosis.id or v_diagnosis.status <> 'final'
       or v_plan.route <> (case when p_transition_code = 'T03' then 'repair' else 'replacement' end) then
      raise exception 'CURRENT_PLAN_REQUIRED' using errcode = '23514';
    end if;
    if v_diagnosis.warranty_coverage = 'pending'
       or (v_plan.financial_basis = 'warranty' and v_diagnosis.warranty_coverage <> 'covered')
       or (v_plan.financial_basis = 'customer_paid' and v_diagnosis.warranty_coverage <> 'not_covered')
       or v_plan.financial_basis = 'none' then
      raise exception 'FINANCIAL_BASIS_UNRESOLVED' using errcode = '23514';
    end if;
    if v_plan.financial_basis = 'customer_paid' or p_transition_code = 'T04' then
      select decision into v_customer_decision from public.repair_plan_approvals
        where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id and kind = 'customer'
        order by recorded_at desc, id desc limit 1;
      if v_customer_decision is distinct from 'approved' then
        raise exception 'CUSTOMER_APPROVAL_REQUIRED' using errcode = '23514';
      end if;
    end if;
    if p_transition_code = 'T03' then
      if v_plan.parts_strategy <> 'no_parts' then
        raise exception 'PARTS_READINESS_REQUIRED' using errcode = '23514';
      end if;
      v_to := 'repair';
    else
      select decision into v_replacement_decision from public.repair_plan_approvals
        where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id and kind = 'replacement'
        order by recorded_at desc, id desc limit 1;
      if v_replacement_decision is distinct from 'approved' then
        raise exception 'REPLACEMENT_APPROVAL_REQUIRED' using errcode = '23514';
      end if;
      v_to := 'replacement';
    end if;
  elsif p_transition_code = 'T05' and v_from = 'decision' then
    select * into v_plan from public.repair_action_plans
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    select * into v_diagnosis from public.repair_diagnoses
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if v_plan.id is null or v_diagnosis.id is null or v_plan.created_at < v_case.stage_entered_at
       or v_plan.diagnosis_id <> v_diagnosis.id or v_diagnosis.status <> 'final'
       or v_diagnosis.recommended_action <> 'return' or v_plan.route <> 'return'
       or v_plan.financial_basis <> 'none' or v_plan.amount_irr <> 0 then
      raise exception 'CURRENT_PLAN_REQUIRED' using errcode = '23514';
    end if;
    select * into v_return_authorization from public.repair_return_authorizations
      where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id;
    if not found or v_return_authorization.protocol_code <> 'return_outgoing_v1' then
      raise exception 'RETURN_AUTHORIZATION_REQUIRED' using errcode = '23514';
    end if;
    v_to := 'test';
  elsif p_transition_code = 'T08' and v_from = 'test' then
    select * into v_plan from public.repair_action_plans
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if v_plan.id is null or v_plan.route <> 'return' then
      raise exception 'RETURN_QC_REQUIRED' using errcode = '23514';
    end if;
    select * into v_return_authorization from public.repair_return_authorizations
      where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id;
    select * into v_check from public.repair_return_outgoing_checks
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if v_return_authorization.id is null or v_check.id is null
       or v_check.plan_id <> v_plan.id or v_check.authorization_id <> v_return_authorization.id
       or v_check.device_id is distinct from v_case.verified_device_id
       or v_check.created_at < v_case.stage_entered_at
       or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass) then
      raise exception 'RETURN_QC_REQUIRED' using errcode = '23514';
    end if;
    select * into v_release from public.repair_return_outgoing_releases
      where org_id = p_org_id and case_id = p_case_id and check_id = v_check.id;
    if v_release.id is null then
      raise exception 'QUALITY_RELEASE_REQUIRED' using errcode = '23514';
    end if;
    v_to := 'delivery';
  elsif p_transition_code = 'T10' and v_from = 'diagnosis' then
    v_to := 'intake';
  else
    raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '23514';
  end if;
  v_at := pg_catalog.clock_timestamp();
  v_previous_entered_at := v_case.stage_entered_at;
  update public.repair_cases set stage = v_to, stage_entered_at = v_at, version = version + 1
    where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, occurred_at, details)
    values (p_org_id, p_case_id, 'stage_transition', v_actor, v_at,
      pg_catalog.jsonb_build_object('transitionCode', p_transition_code, 'from', v_from,
        'to', v_to, 'previousStageEnteredAt', v_previous_entered_at) ||
        case when p_transition_code = 'T02' then pg_catalog.jsonb_build_object('diagnosisId', v_diagnosis.id)
          when p_transition_code in ('T03', 'T04') then pg_catalog.jsonb_build_object('diagnosisId', v_diagnosis.id, 'planId', v_plan.id, 'planRevision', v_plan.revision)
          when p_transition_code = 'T05' then pg_catalog.jsonb_build_object('diagnosisId', v_diagnosis.id, 'planId', v_plan.id, 'returnAuthorizationId', v_return_authorization.id)
          when p_transition_code = 'T08' then pg_catalog.jsonb_build_object('planId', v_plan.id, 'outgoingCheckId', v_check.id, 'qualityReleaseId', v_release.id)
          else '{}'::jsonb end);
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'stage', v_to,
    'version', v_case.version, 'transitionCode', p_transition_code);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'transition', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
