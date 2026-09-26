-- Case work ownership is independent of physical device custody.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('case.assign', 'درخواست واگذاری پرونده', 'ارسال درخواست مسئولیت رسیدگی به عضو فعال سازمان', '{}'),
  ('case.assignment.accept', 'پذیرش واگذاری پرونده', 'پذیرش درخواست خطاب به خود', '{}'),
  ('case.assignment.reject', 'رد واگذاری پرونده', 'رد مستند درخواست خطاب به خود', '{}'),
  ('case.assignment.withdraw', 'پس‌گرفتن واگذاری پرونده', 'پس‌گرفتن مستند درخواست ارسال‌شده', '{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
  and p.key in ('case.assign', 'case.assignment.accept', 'case.assignment.reject', 'case.assignment.withdraw')
on conflict (role_id, permission_key) do nothing;

alter table public.repair_cases add column assigned_to uuid references auth.users(id);
update public.repair_cases set assigned_to = created_by;
alter table public.repair_cases alter column assigned_to set not null;
create index repair_cases_assigned_to_idx on public.repair_cases (org_id, assigned_to, stage);
create function private.repair_case_initial_assignment() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.assigned_to := new.created_by;
  return new;
end; $$;
create trigger repair_case_initial_assignment before insert on public.repair_cases
for each row execute function private.repair_case_initial_assignment();

create table public.repair_case_assignment_periods (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  assignee_id uuid not null references auth.users(id),
  started_at timestamptz not null default pg_catalog.clock_timestamp(),
  ended_at timestamptz,
  request_id uuid,
  foreign key (org_id, case_id) references public.repair_cases(org_id, id),
  check (ended_at is null or ended_at >= started_at)
);
create unique index repair_case_assignment_one_open_period
  on public.repair_case_assignment_periods (org_id, case_id) where ended_at is null;
create index repair_case_assignment_periods_case_idx
  on public.repair_case_assignment_periods (org_id, case_id, started_at desc);
insert into public.repair_case_assignment_periods (org_id, case_id, assignee_id, started_at)
select org_id, id, created_by, created_at from public.repair_cases;
create function private.repair_case_initial_assignment_period() returns trigger
language plpgsql set search_path = '' as $$
begin
  insert into public.repair_case_assignment_periods (org_id, case_id, assignee_id, started_at)
    values (new.org_id, new.id, new.assigned_to, new.created_at);
  return new;
end; $$;
create trigger repair_case_initial_assignment_period after insert on public.repair_cases
for each row execute function private.repair_case_initial_assignment_period();

create table public.repair_case_assignment_requests (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  case_id uuid not null,
  from_user_id uuid not null references auth.users(id),
  target_user_id uuid not null references auth.users(id),
  requested_by uuid not null references auth.users(id),
  request_reference text not null check (length(btrim(request_reference)) between 1 and 160),
  requested_at timestamptz not null default pg_catalog.clock_timestamp(),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'withdrawn')),
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  resolution_reason text,
  resolution_reference text,
  unique (org_id, request_reference),
  unique (org_id, case_id, id),
  foreign key (org_id, case_id) references public.repair_cases(org_id, id),
  check (from_user_id <> target_user_id),
  check ((status = 'pending' and resolved_by is null and resolved_at is null
    and resolution_reason is null and resolution_reference is null)
    or (status = 'accepted' and resolved_by is not null and resolved_at is not null
      and resolution_reason is null and resolution_reference is null)
    or (status in ('rejected', 'withdrawn') and resolved_by is not null and resolved_at is not null
      and length(btrim(resolution_reason)) between 1 and 500
      and length(btrim(resolution_reference)) between 1 and 160))
);
create unique index repair_case_assignment_one_pending
  on public.repair_case_assignment_requests (org_id, case_id) where status = 'pending';
create unique index repair_case_assignment_resolution_ref_unique
  on public.repair_case_assignment_requests (org_id, resolution_reference)
  where resolution_reference is not null;
create index repair_case_assignment_target_queue_idx
  on public.repair_case_assignment_requests (org_id, target_user_id, requested_at desc)
  where status = 'pending';
alter table public.repair_case_assignment_periods
  add constraint repair_case_assignment_period_request_fk
  foreign key (org_id, case_id, request_id)
  references public.repair_case_assignment_requests(org_id, case_id, id);

alter table public.repair_case_assignment_requests enable row level security;
alter table public.repair_case_assignment_periods enable row level security;
create policy repair_case_assignment_requests_select on public.repair_case_assignment_requests
  for select to authenticated using (private.is_org_member(org_id)
    and (private.has_permission(org_id, 'repair.case.view') or target_user_id = (select auth.uid())));
create policy repair_case_assignment_periods_select on public.repair_case_assignment_periods
  for select to authenticated using (private.is_org_member(org_id) and private.has_permission(org_id, 'repair.case.view'));
revoke all on public.repair_case_assignment_requests, public.repair_case_assignment_periods from public, anon, authenticated;
grant select on public.repair_case_assignment_requests, public.repair_case_assignment_periods to authenticated;
alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
  check (event_type in ('created', 'received', 'imei_verified', 'duplicate_override',
    'stage_transition', 'diagnosis_saved', 'diagnosis_finalized', 'plan_saved',
    'plan_approval_recorded', 'return_authorized', 'return_outgoing_checked', 'return_outgoing_released',
    'assignment_requested', 'assignment_accepted', 'assignment_rejected', 'assignment_withdrawn'));

create function public.request_repair_case_assignment(
  p_org_id uuid, p_case_id uuid, p_target_user_id uuid, p_request_reference text,
  p_expected_version integer, p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_request public.repair_case_assignment_requests;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_target_user_id is null
     or p_idempotency_key is null or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'case.assign') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or length(btrim(coalesce(p_request_reference, ''))) not between 1 and 160 then
    raise exception 'INVALID_ASSIGNMENT' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id, 'targetId', p_target_user_id,
    'reference', btrim(p_request_reference), 'version', p_expected_version)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.assign.request:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'assignment.request' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage = 'closed' or v_case.assigned_to = p_target_user_id then
    raise exception 'INVALID_ASSIGNMENT' using errcode = '23514';
  end if;
  if not exists (select 1 from public.org_members m where m.org_id = p_org_id
    and m.user_id = p_target_user_id and m.deleted_at is null and m.invitation_status = 'active') then
    raise exception 'ASSIGNMENT_TARGET_INACTIVE' using errcode = '23514';
  end if;
  if exists (select 1 from public.repair_case_assignment_requests
    where org_id = p_org_id and case_id = p_case_id and status = 'pending') then
    raise exception 'ASSIGNMENT_PENDING' using errcode = '23505';
  end if;
  insert into public.repair_case_assignment_requests (org_id, case_id, from_user_id, target_user_id,
    requested_by, request_reference)
  values (p_org_id, p_case_id, v_case.assigned_to, p_target_user_id, v_actor, btrim(p_request_reference))
  returning * into v_request;
  update public.repair_cases set version = version + 1
    where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'assignment_requested', v_actor,
      pg_catalog.jsonb_build_object('requestId', v_request.id, 'fromUserId', v_request.from_user_id,
        'targetUserId', p_target_user_id, 'reference', v_request.request_reference));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'requestId', v_request.id,
    'status', 'pending', 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'assignment.request', p_idempotency_key, v_hash, v_response);
  return v_response;
end; $$;
revoke all on function public.request_repair_case_assignment(uuid, uuid, uuid, text, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.request_repair_case_assignment(uuid, uuid, uuid, text, integer, uuid)
  to authenticated;

create function public.resolve_repair_case_assignment(
  p_org_id uuid, p_case_id uuid, p_request_id uuid, p_decision text,
  p_reason text, p_resolution_reference text, p_expected_version integer, p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_permission text;
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_request public.repair_case_assignment_requests;
  v_at timestamptz;
  v_response jsonb;
begin
  v_permission := case p_decision when 'accepted' then 'case.assignment.accept'
    when 'rejected' then 'case.assignment.reject' when 'withdrawn' then 'case.assignment.withdraw' else null end;
  if v_actor is null or p_org_id is null or p_case_id is null or p_request_id is null
     or p_idempotency_key is null or v_permission is null
     or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id, v_permission) then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or (p_decision = 'accepted' and (p_reason is not null or p_resolution_reference is not null))
     or (p_decision <> 'accepted' and (length(btrim(coalesce(p_reason, ''))) not between 1 and 500
       or length(btrim(coalesce(p_resolution_reference, ''))) not between 1 and 160)) then
    raise exception 'INVALID_ASSIGNMENT_RESOLUTION' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id, 'requestId', p_request_id,
    'decision', p_decision, 'reason', p_reason, 'reference', p_resolution_reference,
    'version', p_expected_version)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.assign.resolve:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'assignment.resolve' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  select * into v_request from public.repair_case_assignment_requests
    where org_id = p_org_id and case_id = p_case_id and id = p_request_id for update;
  if not found or v_request.status <> 'pending' or v_case.assigned_to <> v_request.from_user_id
     or v_case.stage = 'closed' then
    raise exception 'ASSIGNMENT_NOT_PENDING' using errcode = '23514';
  end if;
  if (p_decision in ('accepted', 'rejected') and v_actor <> v_request.target_user_id)
     or (p_decision = 'withdrawn' and v_actor <> v_request.requested_by) then
    raise exception 'ASSIGNMENT_ACTOR_MISMATCH' using errcode = '42501';
  end if;
  if p_decision = 'accepted' and not exists (select 1 from public.org_members m
    where m.org_id = p_org_id and m.user_id = v_actor
      and m.deleted_at is null and m.invitation_status = 'active') then
    raise exception 'ASSIGNMENT_TARGET_INACTIVE' using errcode = '23514';
  end if;
  v_at := pg_catalog.clock_timestamp();
  update public.repair_case_assignment_requests set status = p_decision,
    resolved_by = v_actor, resolved_at = v_at,
    resolution_reason = case when p_decision = 'accepted' then null else btrim(p_reason) end,
    resolution_reference = case when p_decision = 'accepted' then null else btrim(p_resolution_reference) end
    where id = p_request_id;
  if p_decision = 'accepted' then
    update public.repair_case_assignment_periods set ended_at = v_at
      where org_id = p_org_id and case_id = p_case_id and ended_at is null;
    insert into public.repair_case_assignment_periods
      (org_id, case_id, assignee_id, started_at, request_id)
      values (p_org_id, p_case_id, v_actor, v_at, p_request_id);
    update public.repair_cases set assigned_to = v_actor, version = version + 1
      where org_id = p_org_id and id = p_case_id returning * into v_case;
  else
    update public.repair_cases set version = version + 1
      where org_id = p_org_id and id = p_case_id returning * into v_case;
  end if;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, occurred_at, details)
    values (p_org_id, p_case_id, 'assignment_' || p_decision, v_actor, v_at,
      pg_catalog.jsonb_build_object('requestId', p_request_id, 'fromUserId', v_request.from_user_id,
        'targetUserId', v_request.target_user_id, 'reason', p_reason, 'reference', p_resolution_reference));
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'requestId', p_request_id,
    'status', p_decision, 'version', v_case.version);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'assignment.resolve', p_idempotency_key, v_hash, v_response);
  return v_response;
end; $$;
revoke all on function public.resolve_repair_case_assignment(uuid, uuid, uuid, text, text, text, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.resolve_repair_case_assignment(uuid, uuid, uuid, text, text, text, integer, uuid)
  to authenticated;
