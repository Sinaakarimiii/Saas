\set ON_ERROR_STOP on
begin;
create temp table assignment_fixture as
select gen_random_uuid() owner_id, gen_random_uuid() target_id, gen_random_uuid() other_id,
  gen_random_uuid() org_id, gen_random_uuid() owner_role_id, gen_random_uuid() target_role_id,
  gen_random_uuid() other_role_id;
insert into auth.users (id, aud, role, email)
select owner_id, 'authenticated', 'authenticated', 'assign-owner@example.test' from assignment_fixture
union all select target_id, 'authenticated', 'authenticated', 'assign-target@example.test' from assignment_fixture
union all select other_id, 'authenticated', 'authenticated', 'assign-other@example.test' from assignment_fixture;
insert into public.organizations (id, name, created_by)
select org_id, 'Assignment test', owner_id from assignment_fixture;
insert into public.roles (id, org_id, name, is_system)
select owner_role_id, org_id, 'Assignment owner', false from assignment_fixture
union all select target_role_id, org_id, 'Assignment target', false from assignment_fixture
union all select other_role_id, org_id, 'Assignment other', false from assignment_fixture;
insert into public.org_members (org_id, user_id, role_id)
select org_id, owner_id, owner_role_id from assignment_fixture
union all select org_id, target_id, target_role_id from assignment_fixture
union all select org_id, other_id, other_role_id from assignment_fixture;
insert into public.role_permissions (role_id, permission_key)
select owner_role_id, key from assignment_fixture cross join public.permissions
where key in ('repair.case.create', 'repair.case.view', 'case.assign', 'case.assignment.withdraw')
union all select target_role_id, key from assignment_fixture cross join public.permissions
where key in ('repair.case.view', 'case.assignment.accept', 'case.assignment.reject')
union all select other_role_id, key from assignment_fixture cross join public.permissions
where key in ('repair.case.view', 'case.assignment.accept', 'case.assignment.reject');
grant select on assignment_fixture to authenticated;
set local role authenticated;
do $$
declare
  f record;
  v_case jsonb;
  v_request jsonb;
  v_key uuid;
  v_id uuid;
  v_custodian text;
begin
  select * into f from assignment_fixture;
  perform set_config('request.jwt.claim.sub', f.owner_id::text, true);
  v_case := public.create_repair_case(f.org_id, 'Model', '123456789012345', 'Customer',
    'Issue', 'normal', 'walk_in', gen_random_uuid());
  v_id := (v_case->>'caseId')::uuid;
  select device_custodian into v_custodian from public.repair_cases where id = v_id;
  if (select assigned_to from public.repair_cases where id = v_id) <> f.owner_id then
    raise exception 'Initial assignee is not creator';
  end if;
  begin
    perform public.request_repair_case_assignment(f.org_id, v_id, f.target_id, 'stale', 2, gen_random_uuid());
    raise exception 'Stale assignment request accepted';
  exception when raise_exception then
    if sqlerrm <> 'CASE_VERSION_CONFLICT' then raise; end if;
  end;
  v_key := gen_random_uuid();
  v_request := public.request_repair_case_assignment(f.org_id, v_id, f.target_id, 'assign-1', 1, v_key);
  if public.request_repair_case_assignment(f.org_id, v_id, f.target_id, 'assign-1', 1, v_key) <> v_request then
    raise exception 'Assignment request retry failed';
  end if;
  if (select assigned_to from public.repair_cases where id = v_id) <> f.owner_id then
    raise exception 'Request changed current assignee';
  end if;
  begin
    perform public.request_repair_case_assignment(f.org_id, v_id, f.other_id, 'assign-2', 2, gen_random_uuid());
    raise exception 'Second pending request accepted';
  exception when unique_violation then
    if sqlerrm <> 'ASSIGNMENT_PENDING' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', f.other_id::text, true);
  begin
    perform public.resolve_repair_case_assignment(f.org_id, v_id, (v_request->>'requestId')::uuid,
      'accepted', null, null, 2, gen_random_uuid());
    raise exception 'Wrong target accepted';
  exception when insufficient_privilege then
    if sqlerrm <> 'ASSIGNMENT_ACTOR_MISMATCH' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', f.target_id::text, true);
  begin
    perform public.resolve_repair_case_assignment(f.org_id, v_id, (v_request->>'requestId')::uuid,
      'rejected', null, null, 2, gen_random_uuid());
    raise exception 'Unexplained rejection accepted';
  exception when check_violation then
    if sqlerrm <> 'INVALID_ASSIGNMENT_RESOLUTION' then raise; end if;
  end;
  perform public.resolve_repair_case_assignment(f.org_id, v_id, (v_request->>'requestId')::uuid,
    'rejected', 'Capacity', 'reject-1', 2, gen_random_uuid());
  perform set_config('request.jwt.claim.sub', f.owner_id::text, true);
  v_request := public.request_repair_case_assignment(f.org_id, v_id, f.target_id, 'assign-2', 3, gen_random_uuid());
  perform public.resolve_repair_case_assignment(f.org_id, v_id, (v_request->>'requestId')::uuid,
    'withdrawn', 'Sent in error', 'withdraw-1', 4, gen_random_uuid());
  v_request := public.request_repair_case_assignment(f.org_id, v_id, f.target_id, 'assign-3', 5, gen_random_uuid());
  perform set_config('request.jwt.claim.sub', f.target_id::text, true);
  v_key := gen_random_uuid();
  if public.resolve_repair_case_assignment(f.org_id, v_id, (v_request->>'requestId')::uuid,
    'accepted', null, null, 6, v_key)->>'status' <> 'accepted' then
    raise exception 'Acceptance failed';
  end if;
  if public.resolve_repair_case_assignment(f.org_id, v_id, (v_request->>'requestId')::uuid,
    'accepted', null, null, 6, v_key)->>'status' <> 'accepted' then
    raise exception 'Acceptance retry failed';
  end if;
  if (select assigned_to from public.repair_cases where id = v_id) <> f.target_id then
    raise exception 'Accepted target did not become assignee';
  end if;
  if (select device_custodian from public.repair_cases where id = v_id) is distinct from v_custodian then
    raise exception 'Assignment changed physical custody';
  end if;
  if (select count(*) from public.repair_case_assignment_periods where case_id = v_id) <> 2
     or (select count(*) from public.repair_case_assignment_periods where case_id = v_id and ended_at is null) <> 1 then
    raise exception 'Responsibility periods incorrect';
  end if;
  raise notice 'assignment request, reject, withdraw, accept, idempotency and custody checks passed';
end;
$$;
do $$ begin
  begin
    update public.repair_case_assignment_requests set status = 'accepted';
    raise exception 'Direct assignment update was accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
