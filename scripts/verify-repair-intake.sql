\set ON_ERROR_STOP on
begin;

create temp table repair_fixture as
select gen_random_uuid() owner_a, gen_random_uuid() receiver_a,
       gen_random_uuid() owner_b, gen_random_uuid() org_a,
       gen_random_uuid() org_b, gen_random_uuid() owner_role_a,
       gen_random_uuid() receiver_role_a, gen_random_uuid() owner_role_b;

insert into auth.users (id, aud, role, email)
select owner_a, 'authenticated', 'authenticated', 'repair-owner-a@example.test' from repair_fixture
union all select receiver_a, 'authenticated', 'authenticated', 'repair-receiver-a@example.test' from repair_fixture
union all select owner_b, 'authenticated', 'authenticated', 'repair-owner-b@example.test' from repair_fixture;

insert into public.organizations (id, name, created_by)
select org_a, 'Repair A', owner_a from repair_fixture
union all select org_b, 'Repair B', owner_b from repair_fixture;
insert into public.roles (id, org_id, name, is_system)
select owner_role_a, org_a, 'Repair owner A', false from repair_fixture
union all select receiver_role_a, org_a, 'دریافت‌کننده', false from repair_fixture
union all select owner_role_b, org_b, 'Repair owner B', false from repair_fixture;
insert into public.org_members (org_id, user_id, role_id)
select org_a, owner_a, owner_role_a from repair_fixture
union all select org_a, receiver_a, receiver_role_a from repair_fixture
union all select org_b, owner_b, owner_role_b from repair_fixture;
insert into public.role_permissions (role_id, permission_key)
select owner_role_a, key from repair_fixture cross join public.permissions
where key like 'repair.case.%' or key in ('case.transition.T01', 'case.transition.T10')
union all select owner_role_b, key from repair_fixture cross join public.permissions
where key like 'repair.case.%' or key in ('case.transition.T01', 'case.transition.T10')
union all select receiver_role_a, key from repair_fixture cross join public.permissions
where key in ('repair.case.view', 'repair.case.receive');

grant select on repair_fixture to authenticated;

-- Transaction-local metadata fixtures exercise the database invariant. The
-- browser test separately verifies that actual bytes are stored and served.
create function pg_temp.add_repair_evidence(p_path text, p_owner uuid)
returns void language sql security definer set search_path = '' as $$
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('repair-imei-evidence', p_path, p_owner::text,
    '{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.add_repair_evidence(text, uuid) to authenticated;
set local role authenticated;
do $$
declare
  f record;
  a jsonb;
  b jsonb;
  c jsonb;
  d jsonb;
  v_key uuid;
  v_count integer;
  v_path_a text;
  v_path_b text;
  v_path_b_receiver text;
begin
  select * into f from repair_fixture;
  perform set_config('request.jwt.claim.sub', f.owner_a::text, true);
  v_key := gen_random_uuid();
  a := public.create_repair_case(f.org_a, 'Model A', '123456789012345', 'Customer', 'No power', 'normal', 'walk_in', v_key);
  if public.create_repair_case(f.org_a, 'Model A', '123456789012345', 'Customer', 'No power', 'normal', 'walk_in', v_key) <> a then
    raise exception 'Create idempotency failed';
  end if;
  begin
    perform public.create_repair_case(f.org_a, 'Different', '123456789012345', 'Customer', 'No power', 'normal', 'walk_in', v_key);
    raise exception 'Changed retry was accepted';
  exception when unique_violation then
    if sqlerrm <> 'IDEMPOTENCY_KEY_REUSED' then raise; end if;
  end;
  b := public.create_repair_case(f.org_a, 'Model B', '123456789012345', 'Customer', 'No power', 'normal', 'walk_in', gen_random_uuid());
  if a->>'caseId' = b->>'caseId' then raise exception 'Distinct intake cases collapsed'; end if;

  v_path_a := f.org_a::text || '/' || (a->>'caseId') || '/' || gen_random_uuid()::text || '.png';
  v_path_b := f.org_a::text || '/' || (b->>'caseId') || '/' || gen_random_uuid()::text || '.png';
  v_path_b_receiver := f.org_a::text || '/' || (b->>'caseId') || '/' || gen_random_uuid()::text || '.png';
  begin
    perform public.receive_repair_device(f.org_a, (a->>'caseId')::uuid, 1, gen_random_uuid(),
      'walk_in', 'Branch 1', 'Agent A', 'charger', '123456789012345', v_path_a);
    raise exception 'Missing file was accepted';
  exception when check_violation then
    if sqlerrm <> 'IMEI_EVIDENCE_REQUIRED' then raise; end if;
  end;
  perform pg_temp.add_repair_evidence(v_path_a, f.owner_a);
  perform pg_temp.add_repair_evidence(v_path_b, f.owner_a);
  perform pg_temp.add_repair_evidence(v_path_b_receiver, f.receiver_a);

  v_key := gen_random_uuid();
  a := public.receive_repair_device(f.org_a, (a->>'caseId')::uuid, 1, v_key,
    'walk_in', 'Branch 1', 'Agent A', 'charger', '123456789012345', v_path_a);
  if a->>'version' <> '2' or a->>'duplicateException' <> 'false' then raise exception 'First receipt failed: %', a; end if;
  if public.receive_repair_device(f.org_a, (a->>'caseId')::uuid, 1, v_key,
    'walk_in', 'Branch 1', 'Agent A', 'charger', '123456789012345', v_path_a) <> a then
    raise exception 'Receipt idempotency failed';
  end if;

  perform set_config('request.jwt.claim.sub', f.receiver_a::text, true);
  begin
    perform public.receive_repair_device(f.org_a, (b->>'caseId')::uuid, 1, gen_random_uuid(),
      'walk_in', 'Branch 2', 'Agent B', 'box', '123456789012345', v_path_b_receiver);
    raise exception 'Duplicate was accepted';
  exception when unique_violation then
    if sqlerrm <> 'ACTIVE_REPAIR_CASE_EXISTS' then raise; end if;
  end;
  begin
    perform public.receive_repair_device(f.org_a, (b->>'caseId')::uuid, 1, gen_random_uuid(),
      'walk_in', 'Branch 2', 'Agent B', 'box', '123456789012345', v_path_b_receiver, 'urgent service', 'APPROVAL-1');
    raise exception 'Unprivileged override was accepted';
  exception when unique_violation then
    if sqlerrm <> 'ACTIVE_REPAIR_CASE_EXISTS' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', f.owner_a::text, true);
  c := public.receive_repair_device(f.org_a, (b->>'caseId')::uuid, 1, gen_random_uuid(),
    'walk_in', 'Branch 2', 'Agent B', 'box', '123456789012345', v_path_b, 'urgent service', 'APPROVAL-1');
  if c->>'duplicateException' <> 'true' then raise exception 'Authorized override failed'; end if;

  d := public.create_repair_case(f.org_a, 'Model C', null, 'Customer', 'Broken', 'high', 'phone', gen_random_uuid());
  begin
    perform public.receive_repair_device(f.org_a, (d->>'caseId')::uuid, 2, gen_random_uuid(),
      'post', 'Warehouse', 'Agent A', 'none', null, null);
    raise exception 'Stale version was accepted';
  exception when raise_exception then
    if sqlerrm <> 'CASE_VERSION_CONFLICT' then raise; end if;
  end;
  c := public.receive_repair_device(f.org_a, (d->>'caseId')::uuid, 1, gen_random_uuid(),
    'post', 'Warehouse', 'Agent A', 'none', null, null);
  if c->>'verifiedDeviceId' is not null then raise exception 'Unverified IMEI was treated as verified'; end if;
  begin
    perform public.transition_repair_case(f.org_a, (d->>'caseId')::uuid, 2, 'T01', gen_random_uuid());
    raise exception 'Case without traceable identity advanced';
  exception when check_violation then
    if sqlerrm <> 'INTAKE_INCOMPLETE' then raise; end if;
  end;

  v_key := gen_random_uuid();
  c := public.transition_repair_case(f.org_a, (a->>'caseId')::uuid, 2, 'T01', v_key);
  if c->>'stage' <> 'diagnosis' or c->>'version' <> '3' then raise exception 'Forward transition failed: %', c; end if;
  if public.transition_repair_case(f.org_a, (a->>'caseId')::uuid, 2, 'T01', v_key) <> c then
    raise exception 'Transition retry was not idempotent';
  end if;
  begin
    perform public.transition_repair_case(f.org_a, (a->>'caseId')::uuid, 2, 'T10', v_key);
    raise exception 'Changed transition retry was accepted';
  exception when unique_violation then
    if sqlerrm <> 'IDEMPOTENCY_KEY_REUSED' then raise; end if;
  end;
  begin
    perform public.transition_repair_case(f.org_a, (a->>'caseId')::uuid, 2, 'T10', gen_random_uuid());
    raise exception 'Stale transition was accepted';
  exception when raise_exception then
    if sqlerrm <> 'CASE_VERSION_CONFLICT' then raise; end if;
  end;
  begin
    perform public.transition_repair_case(f.org_a, (a->>'caseId')::uuid, 3, 'T02', gen_random_uuid());
    raise exception 'Unimplemented transition was accepted';
  exception when insufficient_privilege then
    if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
  end;
  select count(*) into v_count from public.repair_case_events
    where case_id = (a->>'caseId')::uuid and event_type = 'stage_transition'
      and details->>'transitionCode' = 'T01';
  if v_count <> 1 then raise exception 'Forward transition audit missing or duplicated'; end if;
  perform set_config('request.jwt.claim.sub', f.receiver_a::text, true);
  begin
    perform public.transition_repair_case(f.org_a, (a->>'caseId')::uuid, 3, 'T10', gen_random_uuid());
    raise exception 'Unprivileged return was accepted';
  exception when insufficient_privilege then
    if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', f.owner_a::text, true);
  c := public.transition_repair_case(f.org_a, (a->>'caseId')::uuid, 3, 'T10', gen_random_uuid());
  if c->>'stage' <> 'intake' or c->>'version' <> '4' then raise exception 'Return transition failed: %', c; end if;
  select count(*) into v_count from public.repair_case_events
    where case_id = (a->>'caseId')::uuid and event_type = 'stage_transition';
  if v_count <> 2 then raise exception 'Transition history was lost'; end if;

  d := public.create_repair_case(f.org_a, 'Model E', '999999999999999', 'Customer', 'Broken', 'normal', 'phone', gen_random_uuid());
  begin
    perform public.receive_repair_device(f.org_a, (d->>'caseId')::uuid, 1, gen_random_uuid(),
      'walk_in', 'Branch 1', 'Agent A', 'none', '888888888888888', 'physical label photo E');
    raise exception 'IMEI correction was silently accepted';
  exception when check_violation then
    if sqlerrm <> 'IDENTITY_CORRECTION_REQUIRED' then raise; end if;
  end;
  begin
    perform public.receive_repair_device(f.org_a, (d->>'caseId')::uuid, 1, gen_random_uuid(),
      null, 'Branch 1', 'Agent A', 'none');
    raise exception 'Receipt with null method was accepted';
  exception when check_violation then
    if sqlerrm <> 'INVALID_RECEIPT_INPUT' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', f.owner_b::text, true);
  begin
    perform public.transition_repair_case(f.org_a, (a->>'caseId')::uuid, 4, 'T01', gen_random_uuid());
    raise exception 'Cross-org transition was accepted';
  exception when insufficient_privilege then
    if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
  end;
  begin
    perform public.create_repair_case(f.org_a, 'Model D', null, 'Other', 'Broken', 'normal', 'phone', gen_random_uuid());
    raise exception 'Cross-org create was accepted';
  exception when insufficient_privilege then
    if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
  end;
  select count(*) into v_count from public.repair_cases where org_id = f.org_a;
  if v_count <> 0 then raise exception 'Cross-org RLS leaked % cases', v_count; end if;
  raise notice 'repair intake functional checks passed';
end;
$$;

do $$ begin
  begin
    insert into public.repair_cases (org_id, created_by, customer_name, device_model, issue, priority, source)
    values (gen_random_uuid(), gen_random_uuid(), 'x', 'x', 'x', 'normal', 'phone');
    raise exception 'Direct write was accepted';
  exception when insufficient_privilege then null;
  end;
end $$;

rollback;
