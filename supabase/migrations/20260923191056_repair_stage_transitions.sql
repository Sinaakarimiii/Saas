-- Only the first forward transition and its direct return are executable here.
-- Later transitions remain blocked until their domain evidence and approvals exist.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('case.transition.T01', 'ارجاع تعمیر به کارشناسی', 'انتقال پروندهٔ دریافت‌شده از پذیرش به کارشناسی', '{}'),
  ('case.transition.T10', 'بازگشت تعمیر به پذیرش', 'بازگشت مستقیم پرونده از کارشناسی به پذیرش', '{}')
on conflict (key) do nothing;

insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null
from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
  and p.key in ('case.transition.T01', 'case.transition.T10')
on conflict (role_id, permission_key) do nothing;

alter table public.repair_cases add column stage_entered_at timestamptz not null default now();
-- Before this migration all existing cases are still in intake.
update public.repair_cases set stage_entered_at = created_at where stage = 'intake';

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
  check (event_type in ('created', 'received', 'imei_verified', 'duplicate_override', 'stage_transition'));

create function public.transition_repair_case(
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
  v_from text;
  v_to text;
  v_at timestamptz;
  v_previous_entered_at timestamptz;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or p_transition_code not in ('T01', 'T10')
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'case.transition.' || p_transition_code) then
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
        'to', v_to, 'previousStageEnteredAt', v_previous_entered_at));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'stage', v_to,
    'version', v_case.version, 'transitionCode', p_transition_code);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'transition', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;

revoke all on function public.transition_repair_case(uuid, uuid, integer, text, uuid)
  from public, anon, authenticated;
grant execute on function public.transition_repair_case(uuid, uuid, integer, text, uuid) to authenticated;
