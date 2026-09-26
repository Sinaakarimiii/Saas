-- First repair vertical slice: case creation and physical receipt/IMEI verification.
-- Mutations are available only through the two checked, atomic commands below.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('repair.case.create', 'ایجاد پرونده تعمیر', 'ثبت درخواست اولیه تعمیر', '{}'),
  ('repair.case.view', 'مشاهده پرونده تعمیر', 'مشاهده پرونده‌های تعمیر سازمان', '{}'),
  ('repair.case.receive', 'دریافت دستگاه تعمیر', 'ثبت دریافت فیزیکی و تطبیق شناسه', '{}'),
  ('repair.case.duplicate.override', 'استثنای پرونده تکراری', 'تأیید پرونده دوم با علت و مرجع', '{}')
on conflict (key) do nothing;

-- Match the existing owner bootstrap, which grants every catalog permission.
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null
from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
  and p.key in ('repair.case.create', 'repair.case.view', 'repair.case.receive', 'repair.case.duplicate.override')
on conflict (role_id, permission_key) do nothing;

create table public.repair_devices (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  imei text not null check (imei ~ '^[0-9]{15}$'),
  first_verified_at timestamptz not null default now(),
  first_verified_by uuid not null references auth.users(id),
  first_evidence text not null check (length(btrim(first_evidence)) > 0),
  unique (org_id, id),
  unique (org_id, imei)
);

create table public.repair_cases (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id),
  tracking_code text unique,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  stage text not null default 'intake' check (stage in ('intake', 'diagnosis', 'decision', 'repair', 'replacement', 'test', 'delivery', 'closed')),
  closed_at timestamptz,
  customer_name text not null check (length(btrim(customer_name)) > 0),
  device_model text not null check (length(btrim(device_model)) > 0),
  raw_identifier text,
  issue text not null check (length(btrim(issue)) > 0),
  priority text not null check (priority in ('normal', 'high', 'urgent')),
  source text not null check (source in ('phone', 'chat', 'walk_in', 'agency', 'post', 'internal', 'other')),
  received_at timestamptz,
  receipt_method text check (receipt_method in ('walk_in', 'post', 'courier', 'agency', 'internal')),
  receipt_items text,
  device_location text,
  device_custodian text,
  verified_device_id uuid,
  imei_evidence text,
  imei_verified_by uuid references auth.users(id),
  imei_verified_at timestamptz,
  duplicate_exception_reason text,
  duplicate_exception_reference text,
  unique (org_id, id),
  foreign key (org_id, verified_device_id) references public.repair_devices(org_id, id),
  check ((verified_device_id is null and imei_verified_at is null and imei_verified_by is null and imei_evidence is null)
      or (verified_device_id is not null and imei_verified_at is not null and imei_verified_by is not null and length(btrim(imei_evidence)) > 0)),
  check ((duplicate_exception_reason is null and duplicate_exception_reference is null)
      or (length(btrim(duplicate_exception_reason)) > 0 and length(btrim(duplicate_exception_reference)) > 0))
);

create unique index repair_one_normal_open_case_per_device
  on public.repair_cases (org_id, verified_device_id)
  where closed_at is null and verified_device_id is not null and duplicate_exception_reference is null;
create unique index repair_duplicate_exception_reference_unique
  on public.repair_cases (org_id, duplicate_exception_reference)
  where duplicate_exception_reference is not null;
create index repair_cases_org_stage_created_idx on public.repair_cases (org_id, stage, created_at desc);

create table public.repair_case_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  event_type text not null check (event_type in ('created', 'received', 'imei_verified', 'duplicate_override')),
  actor_id uuid not null references auth.users(id),
  occurred_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb,
  foreign key (org_id, case_id) references public.repair_cases(org_id, id)
);
create index repair_case_events_case_time_idx on public.repair_case_events (case_id, occurred_at);

create table private.repair_command_receipts (
  org_id uuid not null,
  actor_id uuid not null,
  operation text not null,
  idempotency_key uuid not null,
  request_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (org_id, actor_id, operation, idempotency_key)
);

alter table public.repair_devices enable row level security;
alter table public.repair_cases enable row level security;
alter table public.repair_case_events enable row level security;

create policy repair_devices_select_authorized on public.repair_devices for select to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
create policy repair_cases_select_authorized on public.repair_cases for select to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
create policy repair_case_events_select_authorized on public.repair_case_events for select to authenticated
  using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));

revoke all on public.repair_devices, public.repair_cases, public.repair_case_events from public, anon, authenticated;
grant select on public.repair_devices, public.repair_cases, public.repair_case_events to authenticated;
revoke all on private.repair_command_receipts from public, anon, authenticated;

create trigger trg_repair_cases_tracking_code before insert on public.repair_cases
  for each row execute function public.assign_tracking_code('repair_case');

create or replace function public.create_repair_case(
  p_org_id uuid, p_device_model text, p_raw_identifier text,
  p_customer_name text, p_issue text, p_priority text, p_source text,
  p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'repair.case.create') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_device_model, ''))) = 0
     or length(btrim(coalesce(p_customer_name, ''))) = 0
     or length(btrim(coalesce(p_issue, ''))) = 0
     or p_priority not in ('normal', 'high', 'urgent')
     or p_source not in ('phone', 'chat', 'walk_in', 'agency', 'post', 'internal', 'other') then
    raise exception 'INVALID_CASE_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(jsonb_build_object('model', btrim(p_device_model), 'identifier', nullif(btrim(coalesce(p_raw_identifier, '')), ''),
    'customer', btrim(p_customer_name), 'issue', btrim(p_issue), 'priority', p_priority, 'source', p_source)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.create:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'create' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  insert into public.repair_cases (org_id, created_by, customer_name, device_model, raw_identifier, issue, priority, source)
    values (p_org_id, v_actor, btrim(p_customer_name), btrim(p_device_model),
      nullif(btrim(coalesce(p_raw_identifier, '')), ''), btrim(p_issue), p_priority, p_source)
    returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id)
    values (p_org_id, v_case.id, 'created', v_actor);
  v_response := jsonb_build_object('caseId', v_case.id, 'trackingCode', v_case.tracking_code, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'create', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;

create or replace function public.receive_repair_device(
  p_org_id uuid, p_case_id uuid, p_expected_version integer, p_idempotency_key uuid,
  p_method text, p_location text, p_custodian text, p_items text,
  p_verified_imei text default null, p_imei_evidence text default null,
  p_duplicate_reason text default null, p_duplicate_reference text default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_device_id uuid;
  v_duplicate_id uuid;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'repair.case.receive') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or p_method is null or p_method not in ('walk_in', 'post', 'courier', 'agency', 'internal')
     or length(btrim(coalesce(p_location, ''))) = 0
     or length(btrim(coalesce(p_custodian, ''))) = 0
     or (p_verified_imei is not null and (p_verified_imei !~ '^[0-9]{15}$' or length(btrim(coalesce(p_imei_evidence, ''))) = 0))
     or (p_verified_imei is null and p_imei_evidence is not null) then
    raise exception 'INVALID_RECEIPT_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(jsonb_build_object('caseId', p_case_id, 'expectedVersion', p_expected_version,
    'method', p_method, 'location', btrim(p_location), 'custodian', btrim(p_custodian), 'items', p_items,
    'imei', p_verified_imei, 'evidence', p_imei_evidence, 'duplicateReason', p_duplicate_reason,
    'duplicateReference', p_duplicate_reference)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.receive:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'receive' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases
    where id = p_case_id and org_id = p_org_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'intake' or v_case.received_at is not null then
    raise exception 'RECEIPT_ALREADY_RECORDED' using errcode = '23514';
  end if;
  if p_verified_imei is not null then
    if v_case.raw_identifier ~ '^[0-9]{15}$' and v_case.raw_identifier <> p_verified_imei then
      raise exception 'IDENTITY_CORRECTION_REQUIRED' using errcode = '23514';
    end if;
    insert into public.repair_devices (org_id, imei, first_verified_by, first_evidence)
      values (p_org_id, p_verified_imei, v_actor, btrim(p_imei_evidence))
      on conflict (org_id, imei) do nothing;
    select id into v_device_id from public.repair_devices
      where org_id = p_org_id and imei = p_verified_imei for update;
    select id into v_duplicate_id from public.repair_cases
      where org_id = p_org_id and verified_device_id = v_device_id
        and closed_at is null and id <> p_case_id
      order by created_at limit 1;
    if v_duplicate_id is not null then
      if not private.has_permission(p_org_id, 'repair.case.duplicate.override')
         or length(btrim(coalesce(p_duplicate_reason, ''))) = 0
         or length(btrim(coalesce(p_duplicate_reference, ''))) = 0 then
        raise exception 'ACTIVE_REPAIR_CASE_EXISTS' using errcode = '23505';
      end if;
    elsif p_duplicate_reason is not null or p_duplicate_reference is not null then
      raise exception 'DUPLICATE_OVERRIDE_NOT_APPLICABLE' using errcode = '23514';
    end if;
  elsif p_duplicate_reason is not null or p_duplicate_reference is not null then
    raise exception 'DUPLICATE_OVERRIDE_NOT_APPLICABLE' using errcode = '23514';
  end if;
  update public.repair_cases set
    received_at = now(), receipt_method = p_method, receipt_items = coalesce(p_items, ''),
    device_location = btrim(p_location), device_custodian = btrim(p_custodian),
    verified_device_id = v_device_id,
    imei_evidence = case when v_device_id is null then null else btrim(p_imei_evidence) end,
    imei_verified_by = case when v_device_id is null then null else v_actor end,
    imei_verified_at = case when v_device_id is null then null else now() end,
    duplicate_exception_reason = case when v_duplicate_id is null then null else btrim(p_duplicate_reason) end,
    duplicate_exception_reference = case when v_duplicate_id is null then null else btrim(p_duplicate_reference) end,
    raw_identifier = coalesce(raw_identifier, p_verified_imei), version = version + 1
    where id = p_case_id and org_id = p_org_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'received', v_actor, jsonb_build_object('method', p_method, 'location', btrim(p_location)));
  if v_device_id is not null then
    insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
      values (p_org_id, p_case_id, 'imei_verified', v_actor, jsonb_build_object('deviceId', v_device_id, 'evidence', btrim(p_imei_evidence)));
  end if;
  if v_duplicate_id is not null then
    insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
      values (p_org_id, p_case_id, 'duplicate_override', v_actor,
        jsonb_build_object('existingCaseId', v_duplicate_id, 'reason', btrim(p_duplicate_reason), 'reference', btrim(p_duplicate_reference)));
  end if;
  v_response := jsonb_build_object('caseId', v_case.id, 'version', v_case.version,
    'verifiedDeviceId', v_device_id, 'duplicateException', v_duplicate_id is not null);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'receive', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;

revoke all on function public.create_repair_case(uuid, text, text, text, text, text, text, uuid)
  from public, anon, authenticated;
revoke all on function public.receive_repair_device(uuid, uuid, integer, uuid, text, text, text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.create_repair_case(uuid, text, text, text, text, text, text, uuid) to authenticated;
grant execute on function public.receive_repair_device(uuid, uuid, integer, uuid, text, text, text, text, text, text, text, text) to authenticated;
