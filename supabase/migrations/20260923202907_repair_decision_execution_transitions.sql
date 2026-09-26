-- Enter an execution queue only from the current approved decision revision.
-- T03 is limited to plans with no parts; stock readiness needs a separate ledger.
-- T04 does not allocate stock or physically execute a replacement.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('case.transition.T03', 'ارجاع پرونده به تعمیر', 'ورود از تصمیم به تعمیر با برنامه و شروط معتبر', '{}'),
  ('case.transition.T04', 'ارجاع پرونده به تعویض', 'ورود از تصمیم به صف تعویض با تأییدهای مستقل', '{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
  and p.key in ('case.transition.T03', 'case.transition.T04')
on conflict (role_id, permission_key) do nothing;

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
  v_customer_decision text;
  v_replacement_decision text;
  v_from text;
  v_to text;
  v_at timestamptz;
  v_previous_entered_at timestamptz;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or p_transition_code is null or p_transition_code not in ('T01', 'T02', 'T03', 'T04', 'T10')
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
          else '{}'::jsonb end);
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'stage', v_to,
    'version', v_case.version, 'transitionCode', p_transition_code);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'transition', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
