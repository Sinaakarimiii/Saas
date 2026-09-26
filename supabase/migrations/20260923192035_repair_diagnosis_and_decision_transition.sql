insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('repair.diagnosis.record', 'ثبت تشخیص تعمیر', 'ثبت نسخه تازه تشخیص فنی پرونده', '{}'),
  ('repair.diagnosis.finalize', 'نهایی‌سازی تشخیص تعمیر', 'تأیید نسخه جاری تشخیص فنی', '{}'),
  ('case.transition.T02', 'ارجاع تعمیر به تصمیم', 'انتقال پرونده دارای تشخیص نهایی از کارشناسی به تصمیم', '{}')
on conflict (key) do nothing;

insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
  and p.key in ('repair.diagnosis.record', 'repair.diagnosis.finalize', 'case.transition.T02')
on conflict (role_id, permission_key) do nothing;

create table public.repair_diagnoses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  revision integer not null check (revision > 0),
  status text not null default 'draft' check (status in ('draft', 'final')),
  findings text not null check (length(btrim(findings)) between 1 and 3000),
  technical_condition text not null check (technical_condition in ('unknown', 'needs_repair', 'healthy', 'irreparable')),
  recommended_action text not null check (recommended_action in ('repair', 'replacement', 'return')),
  warranty_coverage text not null check (warranty_coverage in ('covered', 'not_covered', 'pending')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  finalized_by uuid references auth.users(id),
  finalized_at timestamptz,
  unique (org_id, case_id, revision),
  foreign key (org_id, case_id) references public.repair_cases(org_id, id),
  check ((status = 'draft' and finalized_by is null and finalized_at is null)
      or (status = 'final' and finalized_by is not null and finalized_at is not null))
);
create index repair_diagnoses_latest_idx on public.repair_diagnoses (org_id, case_id, revision desc);
alter table public.repair_diagnoses enable row level security;
create policy repair_diagnoses_select_authorized on public.repair_diagnoses for select to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
revoke all on public.repair_diagnoses from public, anon, authenticated;
grant select on public.repair_diagnoses to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
  check (event_type in ('created', 'received', 'imei_verified', 'duplicate_override',
    'stage_transition', 'diagnosis_saved', 'diagnosis_finalized'));

create function public.save_repair_diagnosis(
  p_org_id uuid, p_case_id uuid, p_expected_version integer, p_idempotency_key uuid,
  p_findings text, p_technical_condition text, p_recommended_action text, p_warranty_coverage text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_diagnosis public.repair_diagnoses;
  v_revision integer;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'repair.diagnosis.record') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or length(btrim(coalesce(p_findings, ''))) not between 1 and 3000
     or p_technical_condition is null or p_technical_condition not in ('unknown', 'needs_repair', 'healthy', 'irreparable')
     or p_recommended_action is null or p_recommended_action not in ('repair', 'replacement', 'return')
     or p_warranty_coverage is null or p_warranty_coverage not in ('covered', 'not_covered', 'pending') then
    raise exception 'INVALID_DIAGNOSIS_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id, 'expectedVersion', p_expected_version,
    'findings', btrim(p_findings), 'condition', p_technical_condition,
    'action', p_recommended_action, 'coverage', p_warranty_coverage)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.diagnosis.save:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'diagnosis.save' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'diagnosis' then raise exception 'DIAGNOSIS_STAGE_REQUIRED' using errcode = '23514'; end if;
  select coalesce(max(revision), 0) + 1 into v_revision from public.repair_diagnoses
    where org_id = p_org_id and case_id = p_case_id;
  insert into public.repair_diagnoses (org_id, case_id, revision, findings, technical_condition,
    recommended_action, warranty_coverage, created_by)
    values (p_org_id, p_case_id, v_revision, btrim(p_findings), p_technical_condition,
      p_recommended_action, p_warranty_coverage, v_actor) returning * into v_diagnosis;
  update public.repair_cases set version = version + 1 where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'diagnosis_saved', v_actor,
      pg_catalog.jsonb_build_object('diagnosisId', v_diagnosis.id, 'revision', v_revision));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'diagnosisId', v_diagnosis.id,
    'revision', v_revision, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'diagnosis.save', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;

create function public.finalize_repair_diagnosis(
  p_org_id uuid, p_case_id uuid, p_diagnosis_id uuid,
  p_expected_version integer, p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_diagnosis public.repair_diagnoses;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_diagnosis_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'repair.diagnosis.finalize') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'INVALID_DIAGNOSIS_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id,
    'diagnosisId', p_diagnosis_id, 'expectedVersion', p_expected_version)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.diagnosis.finalize:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'diagnosis.finalize' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'diagnosis' then raise exception 'DIAGNOSIS_STAGE_REQUIRED' using errcode = '23514'; end if;
  select * into v_diagnosis from public.repair_diagnoses
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1 for update;
  if not found or v_diagnosis.id <> p_diagnosis_id or v_diagnosis.status <> 'draft'
     or v_diagnosis.created_at < v_case.stage_entered_at then
    raise exception 'DIAGNOSIS_REVISION_CONFLICT' using errcode = '23514';
  end if;
  if v_diagnosis.technical_condition = 'unknown' then
    raise exception 'DIAGNOSIS_CONDITION_UNRESOLVED' using errcode = '23514';
  end if;
  update public.repair_diagnoses set status = 'final', finalized_by = v_actor, finalized_at = pg_catalog.clock_timestamp()
    where id = v_diagnosis.id returning * into v_diagnosis;
  update public.repair_cases set version = version + 1 where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'diagnosis_finalized', v_actor,
      pg_catalog.jsonb_build_object('diagnosisId', v_diagnosis.id, 'revision', v_diagnosis.revision));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'diagnosisId', v_diagnosis.id,
    'revision', v_diagnosis.revision, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'diagnosis.finalize', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;

revoke all on function public.save_repair_diagnosis(uuid, uuid, integer, uuid, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.finalize_repair_diagnosis(uuid, uuid, uuid, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.save_repair_diagnosis(uuid, uuid, integer, uuid, text, text, text, text) to authenticated;
grant execute on function public.finalize_repair_diagnosis(uuid, uuid, uuid, integer, uuid) to authenticated;

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
  v_from text;
  v_to text;
  v_at timestamptz;
  v_previous_entered_at timestamptz;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or p_transition_code is null or p_transition_code not in ('T01', 'T02', 'T10')
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
          else '{}'::jsonb end);
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'stage', v_to,
    'version', v_case.version, 'transitionCode', p_transition_code);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'transition', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
