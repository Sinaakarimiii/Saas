-- Decision proposals are immutable revisions. Approval records target one revision,
-- so replacing a proposal cannot carry an old approval forward.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('repair.plan.record', 'ثبت برنامه اقدام تعمیر', 'ثبت پیشنهاد نسخه‌دار تعمیر، تعویض یا عودت', '{}'),
  ('repair.customer_approval.record', 'ثبت پاسخ مشتری تعمیر', 'ثبت پاسخ مشتری با شخص، روش و مرجع', '{}'),
  ('repair.replacement.approve', 'تأیید تعویض دستگاه', 'مصوبه مستقل تعویض برای نسخه مشخص پیشنهاد', '{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
  and p.key in ('repair.plan.record', 'repair.customer_approval.record', 'repair.replacement.approve')
on conflict (role_id, permission_key) do nothing;

alter table public.repair_diagnoses add constraint repair_diagnoses_org_case_id_unique unique (org_id, case_id, id);

create table public.repair_action_plans (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  diagnosis_id uuid not null,
  revision integer not null check (revision > 0),
  route text not null check (route in ('repair', 'replacement', 'return')),
  scope text not null check (length(btrim(scope)) between 1 and 3000),
  financial_basis text not null check (financial_basis in ('warranty', 'customer_paid', 'none')),
  amount_irr bigint not null check (amount_irr >= 0),
  parts_strategy text check (parts_strategy in ('no_parts', 'requires_parts')),
  replacement_model text,
  replacement_reason text check (replacement_reason in ('irreparable', 'uneconomical', 'policy', 'other')),
  original_disposition text check (original_disposition in ('return_to_customer', 'scrap_proposed', 'refurbish_proposed', 'parts_proposed')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  unique (org_id, case_id, revision),
  unique (org_id, case_id, id),
  foreign key (org_id, case_id) references public.repair_cases(org_id, id),
  foreign key (org_id, case_id, diagnosis_id) references public.repair_diagnoses(org_id, case_id, id),
  check ((financial_basis = 'warranty' and amount_irr = 0)
    or (financial_basis = 'customer_paid' and amount_irr > 0)
    or (financial_basis = 'none' and amount_irr = 0 and route = 'return')),
  check ((route = 'repair' and parts_strategy is not null and replacement_model is null
      and replacement_reason is null and original_disposition is null and financial_basis <> 'none')
    or (route = 'replacement' and parts_strategy is null and replacement_model is not null and length(btrim(replacement_model)) between 1 and 160
      and replacement_reason is not null and original_disposition is not null and financial_basis <> 'none')
    or (route = 'return' and parts_strategy is null and replacement_model is null
      and replacement_reason is null and original_disposition is null and financial_basis = 'none'))
);
create index repair_action_plans_latest_idx on public.repair_action_plans (org_id, case_id, revision desc);
alter table public.repair_action_plans enable row level security;
create policy repair_action_plans_select_authorized on public.repair_action_plans for select to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
revoke all on public.repair_action_plans from public, anon, authenticated;
grant select on public.repair_action_plans to authenticated;

create table public.repair_plan_approvals (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  plan_id uuid not null,
  kind text not null check (kind in ('customer', 'replacement')),
  decision text not null check (decision in ('approved', 'rejected')),
  channel text check (channel in ('phone', 'message', 'chat', 'in_person', 'agency', 'other')),
  subject_name text,
  subject_role text check (subject_role in ('owner', 'authorized_representative')),
  evidence_reference text,
  authority_reference text,
  stated_at timestamptz,
  recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default pg_catalog.clock_timestamp(),
  foreign key (org_id, case_id, plan_id) references public.repair_action_plans(org_id, case_id, id),
  check ((kind = 'customer' and channel is not null and subject_name is not null and length(btrim(subject_name)) between 1 and 160
    and subject_role is not null and evidence_reference is not null and length(btrim(evidence_reference)) between 1 and 240
    and (subject_role = 'owner' or (authority_reference is not null and length(btrim(authority_reference)) between 1 and 240))
    and stated_at is not null)
    or (kind = 'replacement' and channel is null and subject_name is null and subject_role is null
      and evidence_reference is null and authority_reference is null and stated_at is null))
);
create index repair_plan_approvals_latest_idx on public.repair_plan_approvals (org_id, case_id, plan_id, kind, recorded_at desc);
alter table public.repair_plan_approvals enable row level security;
create policy repair_plan_approvals_select_authorized on public.repair_plan_approvals for select to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
revoke all on public.repair_plan_approvals from public, anon, authenticated;
grant select on public.repair_plan_approvals to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
  check (event_type in ('created', 'received', 'imei_verified', 'duplicate_override',
    'stage_transition', 'diagnosis_saved', 'diagnosis_finalized', 'plan_saved', 'plan_approval_recorded'));

create function public.save_repair_action_plan(
  p_org_id uuid, p_case_id uuid, p_expected_version integer, p_idempotency_key uuid,
  p_route text, p_scope text, p_financial_basis text, p_amount_irr bigint,
  p_parts_strategy text default null, p_replacement_model text default null,
  p_replacement_reason text default null, p_original_disposition text default null
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
  v_revision integer;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'repair.plan.record') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or p_route is null or p_route not in ('repair', 'replacement', 'return')
     or length(btrim(coalesce(p_scope, ''))) not between 1 and 3000
     or p_financial_basis is null or p_financial_basis not in ('warranty', 'customer_paid', 'none')
     or p_amount_irr is null or p_amount_irr < 0
     or not ((p_financial_basis = 'warranty' and p_amount_irr = 0)
       or (p_financial_basis = 'customer_paid' and p_amount_irr > 0)
       or (p_financial_basis = 'none' and p_amount_irr = 0 and p_route = 'return'))
     or (p_route = 'repair' and (p_parts_strategy is null or p_parts_strategy not in ('no_parts', 'requires_parts')
       or p_replacement_model is not null or p_replacement_reason is not null or p_original_disposition is not null
       or p_financial_basis = 'none'))
     or (p_route = 'replacement' and (p_parts_strategy is not null
       or length(btrim(coalesce(p_replacement_model, ''))) not between 1 and 160
       or p_replacement_reason is null or p_replacement_reason not in ('irreparable', 'uneconomical', 'policy', 'other')
       or p_original_disposition is null or p_original_disposition not in ('return_to_customer', 'scrap_proposed', 'refurbish_proposed', 'parts_proposed')
       or p_financial_basis = 'none'))
     or (p_route = 'return' and (p_parts_strategy is not null or p_replacement_model is not null
       or p_replacement_reason is not null or p_original_disposition is not null or p_financial_basis <> 'none')) then
    raise exception 'INVALID_PLAN_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id, 'expectedVersion', p_expected_version,
    'route', p_route, 'scope', btrim(p_scope), 'basis', p_financial_basis, 'amount', p_amount_irr,
    'parts', p_parts_strategy, 'replacementModel', p_replacement_model,
    'replacementReason', p_replacement_reason, 'disposition', p_original_disposition)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.plan.save:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'plan.save' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'decision' then raise exception 'DECISION_STAGE_REQUIRED' using errcode = '23514'; end if;
  select * into v_diagnosis from public.repair_diagnoses
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  if not found or v_diagnosis.status <> 'final' or v_diagnosis.recommended_action <> p_route then
    raise exception 'PLAN_DIAGNOSIS_MISMATCH' using errcode = '23514';
  end if;
  select coalesce(max(revision), 0) + 1 into v_revision from public.repair_action_plans
    where org_id = p_org_id and case_id = p_case_id;
  insert into public.repair_action_plans (org_id, case_id, diagnosis_id, revision, route, scope,
    financial_basis, amount_irr, parts_strategy, replacement_model, replacement_reason,
    original_disposition, created_by)
    values (p_org_id, p_case_id, v_diagnosis.id, v_revision, p_route, btrim(p_scope),
      p_financial_basis, p_amount_irr, p_parts_strategy, nullif(btrim(coalesce(p_replacement_model, '')), ''),
      p_replacement_reason, p_original_disposition, v_actor) returning * into v_plan;
  update public.repair_cases set version = version + 1 where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'plan_saved', v_actor,
      pg_catalog.jsonb_build_object('planId', v_plan.id, 'revision', v_revision, 'route', p_route));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'planId', v_plan.id,
    'revision', v_revision, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'plan.save', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;

create function public.record_repair_plan_approval(
  p_org_id uuid, p_case_id uuid, p_plan_id uuid, p_expected_version integer,
  p_idempotency_key uuid, p_kind text, p_decision text,
  p_channel text default null, p_subject_name text default null,
  p_subject_role text default null, p_evidence_reference text default null,
  p_authority_reference text default null, p_stated_at timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_plan public.repair_action_plans;
  v_approval public.repair_plan_approvals;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_plan_id is null or p_idempotency_key is null
     or p_kind is null or p_kind not in ('customer', 'replacement')
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id,
       case when p_kind = 'customer' then 'repair.customer_approval.record' else 'repair.replacement.approve' end) then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or p_decision is null or p_decision not in ('approved', 'rejected')
     or (p_kind = 'customer' and (p_channel is null or p_channel not in ('phone', 'message', 'chat', 'in_person', 'agency', 'other')
       or length(btrim(coalesce(p_subject_name, ''))) not between 1 and 160
       or p_subject_role is null or p_subject_role not in ('owner', 'authorized_representative')
       or length(btrim(coalesce(p_evidence_reference, ''))) not between 1 and 240
       or (p_subject_role = 'authorized_representative' and length(btrim(coalesce(p_authority_reference, ''))) not between 1 and 240)
       or p_stated_at is null or p_stated_at > pg_catalog.clock_timestamp() + interval '5 minutes'))
     or (p_kind = 'replacement' and (p_channel is not null or p_subject_name is not null
       or p_subject_role is not null or p_evidence_reference is not null
       or p_authority_reference is not null or p_stated_at is not null)) then
    raise exception 'INVALID_APPROVAL_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id, 'planId', p_plan_id,
    'expectedVersion', p_expected_version, 'kind', p_kind, 'decision', p_decision,
    'channel', p_channel, 'subject', p_subject_name, 'role', p_subject_role,
    'evidence', p_evidence_reference, 'authority', p_authority_reference, 'statedAt', p_stated_at)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.plan.approval:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'plan.approval' and idempotency_key = p_idempotency_key;
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
  if not found or v_plan.id <> p_plan_id or v_plan.created_at < v_case.stage_entered_at then
    raise exception 'PLAN_REVISION_CONFLICT' using errcode = '23514';
  end if;
  if p_kind = 'replacement' and v_plan.route <> 'replacement' then
    raise exception 'REPLACEMENT_PLAN_REQUIRED' using errcode = '23514';
  end if;
  insert into public.repair_plan_approvals (org_id, case_id, plan_id, kind, decision,
    channel, subject_name, subject_role, evidence_reference, authority_reference, stated_at, recorded_by)
    values (p_org_id, p_case_id, p_plan_id, p_kind, p_decision,
      p_channel, nullif(btrim(coalesce(p_subject_name, '')), ''), p_subject_role,
      nullif(btrim(coalesce(p_evidence_reference, '')), ''),
      nullif(btrim(coalesce(p_authority_reference, '')), ''), p_stated_at, v_actor)
    returning * into v_approval;
  update public.repair_cases set version = version + 1 where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'plan_approval_recorded', v_actor,
      pg_catalog.jsonb_build_object('planId', p_plan_id, 'approvalId', v_approval.id,
        'kind', p_kind, 'decision', p_decision));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'approvalId', v_approval.id,
    'planId', p_plan_id, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'plan.approval', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;

revoke all on function public.save_repair_action_plan(uuid, uuid, integer, uuid, text, text, text, bigint, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.record_repair_plan_approval(uuid, uuid, uuid, integer, uuid, text, text, text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.save_repair_action_plan(uuid, uuid, integer, uuid, text, text, text, bigint, text, text, text, text) to authenticated;
grant execute on function public.record_repair_plan_approval(uuid, uuid, uuid, integer, uuid, text, text, text, text, text, text, text, timestamptz) to authenticated;
