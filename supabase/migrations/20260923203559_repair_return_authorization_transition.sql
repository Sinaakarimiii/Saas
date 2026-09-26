-- Return authorization is a business record, separate from the two-button stage confirmation.
-- It records a manual notification reference and selects the outgoing return protocol;
-- it does not claim that QC, shipment or final handover has occurred.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('repair.return.authorize', 'مجوز عودت بدون تعمیر', 'ثبت اطلاع‌رسانی و مجوز عودت برای نسخه جاری برنامه', '{}'),
  ('case.transition.T05', 'ارجاع عودت به کنترل خروج', 'انتقال برنامه عودت مجاز به مرحله کنترل خروج', '{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
  and p.key in ('repair.return.authorize', 'case.transition.T05')
on conflict (role_id, permission_key) do nothing;

create table public.repair_return_authorizations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  plan_id uuid not null,
  notification_channel text not null check (notification_channel in ('phone', 'message', 'chat', 'in_person', 'agency', 'other')),
  notified_person text not null check (length(btrim(notified_person)) between 1 and 160),
  notification_reference text not null check (length(btrim(notification_reference)) between 1 and 240),
  notified_at timestamptz not null,
  protocol_code text not null default 'return_outgoing_v1' check (protocol_code = 'return_outgoing_v1'),
  authorized_by uuid not null references auth.users(id),
  authorized_at timestamptz not null default pg_catalog.clock_timestamp(),
  unique (org_id, case_id, plan_id),
  foreign key (org_id, case_id, plan_id) references public.repair_action_plans(org_id, case_id, id)
);
create index repair_return_authorizations_case_idx on public.repair_return_authorizations (org_id, case_id);
alter table public.repair_return_authorizations enable row level security;
create policy repair_return_authorizations_select_authorized on public.repair_return_authorizations for select to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
revoke all on public.repair_return_authorizations from public, anon, authenticated;
grant select on public.repair_return_authorizations to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
  check (event_type in ('created', 'received', 'imei_verified', 'duplicate_override',
    'stage_transition', 'diagnosis_saved', 'diagnosis_finalized', 'plan_saved',
    'plan_approval_recorded', 'return_authorized'));

create function public.record_repair_return_authorization(
  p_org_id uuid, p_case_id uuid, p_plan_id uuid, p_expected_version integer,
  p_idempotency_key uuid, p_notification_channel text, p_notified_person text,
  p_notification_reference text, p_notified_at timestamptz
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_plan public.repair_action_plans;
  v_diagnosis public.repair_diagnoses;
  v_authorization public.repair_return_authorizations;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_plan_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'repair.return.authorize') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or p_notification_channel is null or p_notification_channel not in ('phone', 'message', 'chat', 'in_person', 'agency', 'other')
     or length(btrim(coalesce(p_notified_person, ''))) not between 1 and 160
     or length(btrim(coalesce(p_notification_reference, ''))) not between 1 and 240
     or p_notified_at is null or p_notified_at > pg_catalog.clock_timestamp() + interval '5 minutes' then
    raise exception 'INVALID_RETURN_AUTHORIZATION' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id, 'planId', p_plan_id,
    'expectedVersion', p_expected_version, 'channel', p_notification_channel,
    'person', btrim(p_notified_person), 'reference', btrim(p_notification_reference),
    'notifiedAt', p_notified_at)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.return.authorize:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'return.authorize' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'decision' then raise exception 'DECISION_STAGE_REQUIRED' using errcode = '23514'; end if;
  select * into v_plan from public.repair_action_plans
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  select * into v_diagnosis from public.repair_diagnoses
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  if v_plan.id is null or v_plan.id <> p_plan_id or v_plan.created_at < v_case.stage_entered_at
     or v_plan.route <> 'return' or v_plan.financial_basis <> 'none' or v_plan.amount_irr <> 0
     or v_diagnosis.id is null or v_diagnosis.id <> v_plan.diagnosis_id
     or v_diagnosis.status <> 'final' or v_diagnosis.recommended_action <> 'return' then
    raise exception 'CURRENT_PLAN_REQUIRED' using errcode = '23514';
  end if;
  if p_notified_at < v_plan.created_at then
    raise exception 'INVALID_RETURN_AUTHORIZATION' using errcode = '23514';
  end if;
  if exists (select 1 from public.repair_return_authorizations
    where org_id = p_org_id and case_id = p_case_id and plan_id = p_plan_id) then
    raise exception 'RETURN_ALREADY_AUTHORIZED' using errcode = '23505';
  end if;
  insert into public.repair_return_authorizations (org_id, case_id, plan_id, notification_channel,
    notified_person, notification_reference, notified_at, authorized_by)
    values (p_org_id, p_case_id, p_plan_id, p_notification_channel, btrim(p_notified_person),
      btrim(p_notification_reference), p_notified_at, v_actor) returning * into v_authorization;
  update public.repair_cases set version = version + 1 where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'return_authorized', v_actor,
      pg_catalog.jsonb_build_object('planId', p_plan_id, 'authorizationId', v_authorization.id,
        'protocolCode', v_authorization.protocol_code));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'authorizationId', v_authorization.id,
    'planId', p_plan_id, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'return.authorize', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
revoke all on function public.record_repair_return_authorization(uuid, uuid, uuid, integer, uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.record_repair_return_authorization(uuid, uuid, uuid, integer, uuid, text, text, text, timestamptz)
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
  v_customer_decision text;
  v_replacement_decision text;
  v_from text;
  v_to text;
  v_at timestamptz;
  v_previous_entered_at timestamptz;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or p_transition_code is null or p_transition_code not in ('T01', 'T02', 'T03', 'T04', 'T05', 'T10')
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
          else '{}'::jsonb end);
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'stage', v_to,
    'version', v_case.version, 'transitionCode', p_transition_code);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'transition', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
