\set ON_ERROR_STOP on
begin;

create temp table diagnosis_fixture as
select gen_random_uuid() owner_id, gen_random_uuid() technician_id,
  gen_random_uuid() org_id, gen_random_uuid() owner_role_id, gen_random_uuid() technician_role_id;
insert into auth.users (id, aud, role, email)
select owner_id, 'authenticated', 'authenticated', 'diagnosis-owner@example.test' from diagnosis_fixture
union all select technician_id, 'authenticated', 'authenticated', 'diagnosis-technician@example.test' from diagnosis_fixture;
insert into public.organizations (id, name, created_by)
select org_id, 'Diagnosis test', owner_id from diagnosis_fixture;
insert into public.roles (id, org_id, name, is_system)
select owner_role_id, org_id, 'Diagnosis owner', false from diagnosis_fixture
union all select technician_role_id, org_id, 'Diagnosis technician', false from diagnosis_fixture;
insert into public.org_members (org_id, user_id, role_id)
select org_id, owner_id, owner_role_id from diagnosis_fixture
union all select org_id, technician_id, technician_role_id from diagnosis_fixture;
insert into public.role_permissions (role_id, permission_key)
select owner_role_id, key from diagnosis_fixture cross join public.permissions
where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
  or key in ('repair.plan.record', 'repair.complete', 'repair.customer_approval.record', 'repair.replacement.approve', 'replacement.stock.receive', 'replacement.stock.allocate', 'repair.return.authorize', 'repair.return_qc.record', 'repair.quality.release', 'repair.delivery.receive', 'repair.delivery.dispatch', 'repair.delivery.confirm_receipt', 'delivery.incident.record', 'delivery.incident.followup', 'delivery.incident.resolve', 'repair.delivery.return_receive', 'case.close', 'custody.baseline.record', 'custody.transfer.release', 'custody.transfer.accept', 'custody.transfer.return', 'custody.transfer.discrepancy.record', 'custody.transfer.discrepancy.resolve')
union all select technician_role_id, key from diagnosis_fixture cross join public.permissions
where key in ('repair.case.view', 'repair.diagnosis.record', 'custody.transfer.accept',
  'custody.transfer.release', 'custody.transfer.discrepancy.record');
grant select on diagnosis_fixture to authenticated;

set local role authenticated;
do $$
declare
  f record;
  v_case jsonb;
  v_diagnosis jsonb;
  v_plan jsonb;
  v_other jsonb;
  v_return jsonb;
  v_auth jsonb;
  v_key uuid;
  v_count integer;
begin
  select * into f from diagnosis_fixture;
  perform set_config('request.jwt.claim.sub', f.owner_id::text, true);
  v_case := public.create_repair_case(f.org_id, 'GPS model', 'temporary-label-42',
    'Customer', 'No power', 'normal', 'walk_in', gen_random_uuid());
  perform public.receive_repair_device(f.org_id, (v_case->>'caseId')::uuid, 1, gen_random_uuid(),
    'walk_in', 'Workshop', 'Agent', 'charger');
  perform public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 2, 'T01', gen_random_uuid());
  begin
    perform public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 3, 'T02', gen_random_uuid());
    raise exception 'T02 accepted without diagnosis';
  exception when check_violation then
    if sqlerrm <> 'FINAL_DIAGNOSIS_REQUIRED' then raise; end if;
  end;
  v_diagnosis := public.save_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid, 3, gen_random_uuid(),
    'No power at input', 'unknown', 'repair', 'pending');
  begin
    perform public.finalize_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid,
      (v_diagnosis->>'diagnosisId')::uuid, 4, gen_random_uuid());
    raise exception 'Unknown technical condition was finalized';
  exception when check_violation then
    if sqlerrm <> 'DIAGNOSIS_CONDITION_UNRESOLVED' then raise; end if;
  end;
  v_key := gen_random_uuid();
  v_diagnosis := public.save_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid, 4, v_key,
    'Power circuit is damaged', 'needs_repair', 'repair', 'pending');
  if public.save_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid, 4, v_key,
    'Power circuit is damaged', 'needs_repair', 'repair', 'pending') <> v_diagnosis then
    raise exception 'Diagnosis save retry was not idempotent';
  end if;
  if v_diagnosis->>'revision' <> '2' then raise exception 'Diagnosis revision did not advance'; end if;
  perform set_config('request.jwt.claim.sub', f.technician_id::text, true);
  begin
    perform public.finalize_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid,
      (v_diagnosis->>'diagnosisId')::uuid, 5, gen_random_uuid());
    raise exception 'Unprivileged user finalized diagnosis';
  exception when insufficient_privilege then
    if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', f.owner_id::text, true);
  v_key := gen_random_uuid();
  perform public.finalize_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid,
    (v_diagnosis->>'diagnosisId')::uuid, 5, v_key);
  if (public.finalize_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid,
    (v_diagnosis->>'diagnosisId')::uuid, 5, v_key))->>'version' <> '6' then
    raise exception 'Finalization retry failed';
  end if;
  perform public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 6, 'T10', gen_random_uuid());
  perform public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 7, 'T01', gen_random_uuid());
  begin
    perform public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 8, 'T02', gen_random_uuid());
    raise exception 'Old diagnosis reused after re-entry';
  exception when check_violation then
    if sqlerrm <> 'FINAL_DIAGNOSIS_REQUIRED' then raise; end if;
  end;
  v_diagnosis := public.save_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid, 8, gen_random_uuid(),
    'Second review confirms damaged circuit', 'needs_repair', 'repair', 'not_covered');
  begin
    perform public.finalize_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid,
      (v_diagnosis->>'diagnosisId')::uuid, 8, gen_random_uuid());
    raise exception 'Stale case version finalized';
  exception when raise_exception then
    if sqlerrm <> 'CASE_VERSION_CONFLICT' then raise; end if;
  end;
  perform public.finalize_repair_diagnosis(f.org_id, (v_case->>'caseId')::uuid,
    (v_diagnosis->>'diagnosisId')::uuid, 9, gen_random_uuid());
  v_case := public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 10, 'T02', gen_random_uuid());
  if v_case->>'stage' <> 'decision' or v_case->>'version' <> '11' then
    raise exception 'T02 failed: %', v_case;
  end if;
  select count(*) into v_count from public.repair_case_events
    where case_id = (v_case->>'caseId')::uuid and event_type = 'diagnosis_finalized';
  if v_count <> 2 then raise exception 'Diagnosis finalization audit missing'; end if;
  begin
    perform public.save_repair_action_plan(f.org_id, (v_case->>'caseId')::uuid, 11, gen_random_uuid(),
      'replacement', 'Replace device', 'customer_paid', 1000000, null, 'Model B',
      'irreparable', 'return_to_customer');
    raise exception 'Plan route diverged from diagnosis';
  exception when check_violation then
    if sqlerrm <> 'PLAN_DIAGNOSIS_MISMATCH' then raise; end if;
  end;
  v_key := gen_random_uuid();
  v_plan := public.save_repair_action_plan(f.org_id, (v_case->>'caseId')::uuid, 11, v_key,
    'repair', 'Repair power circuit', 'customer_paid', 1000000, 'no_parts');
  if public.save_repair_action_plan(f.org_id, (v_case->>'caseId')::uuid, 11, v_key,
    'repair', 'Repair power circuit', 'customer_paid', 1000000, 'no_parts') <> v_plan then
    raise exception 'Plan save retry was not idempotent';
  end if;
  begin
    perform public.record_repair_plan_approval(f.org_id, (v_case->>'caseId')::uuid,
      (v_plan->>'planId')::uuid, 12, gen_random_uuid(), 'customer', 'approved',
      'agency', 'Agent', 'authorized_representative', 'chat-1', null, pg_catalog.clock_timestamp());
    raise exception 'Representative without authority was accepted';
  exception when check_violation then
    if sqlerrm <> 'INVALID_APPROVAL_INPUT' then raise; end if;
  end;
  perform public.record_repair_plan_approval(f.org_id, (v_case->>'caseId')::uuid,
    (v_plan->>'planId')::uuid, 12, gen_random_uuid(), 'customer', 'approved',
    'phone', 'Customer', 'owner', 'call-1', null, pg_catalog.clock_timestamp());
  begin
    perform public.record_repair_plan_approval(f.org_id, (v_case->>'caseId')::uuid,
      (v_plan->>'planId')::uuid, 13, gen_random_uuid(), 'replacement', 'approved');
    raise exception 'Replacement approval accepted for repair route';
  exception when check_violation then
    if sqlerrm <> 'REPLACEMENT_PLAN_REQUIRED' then raise; end if;
  end;
  v_other := public.save_repair_action_plan(f.org_id, (v_case->>'caseId')::uuid, 13, gen_random_uuid(),
    'repair', 'Revised repair scope', 'customer_paid', 1200000, 'no_parts');
  if v_other->>'revision' <> '2' then raise exception 'Plan revision did not advance'; end if;
  begin
    perform public.record_repair_plan_approval(f.org_id, (v_case->>'caseId')::uuid,
      (v_plan->>'planId')::uuid, 14, gen_random_uuid(), 'customer', 'approved',
      'phone', 'Customer', 'owner', 'call-2', null, pg_catalog.clock_timestamp());
    raise exception 'Old plan was approved after a revision';
  exception when check_violation then
    if sqlerrm <> 'PLAN_REVISION_CONFLICT' then raise; end if;
  end;
  begin
    perform public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 14, 'T03', gen_random_uuid());
    raise exception 'T03 reused consent from an older plan';
  exception when check_violation then
    if sqlerrm <> 'CUSTOMER_APPROVAL_REQUIRED' then raise; end if;
  end;
  v_other := public.save_repair_action_plan(f.org_id, (v_case->>'caseId')::uuid, 14, gen_random_uuid(),
    'repair', 'Repair requires a new board', 'customer_paid', 1200000, 'requires_parts');
  perform public.record_repair_plan_approval(f.org_id, (v_case->>'caseId')::uuid,
    (v_other->>'planId')::uuid, 15, gen_random_uuid(), 'customer', 'approved',
    'phone', 'Customer', 'owner', 'call-3', null, pg_catalog.clock_timestamp());
  begin
    perform public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 16, 'T03', gen_random_uuid());
    raise exception 'T03 accepted a parts-dependent plan without stock readiness';
  exception when check_violation then
    if sqlerrm <> 'PARTS_READINESS_REQUIRED' then raise; end if;
  end;
  v_other := public.save_repair_action_plan(f.org_id, (v_case->>'caseId')::uuid, 16, gen_random_uuid(),
    'repair', 'Revised work needs no new parts', 'customer_paid', 1200000, 'no_parts');
  perform public.record_repair_plan_approval(f.org_id, (v_case->>'caseId')::uuid,
    (v_other->>'planId')::uuid, 17, gen_random_uuid(), 'customer', 'approved',
    'phone', 'Customer', 'owner', 'call-4', null, pg_catalog.clock_timestamp());
  v_key := gen_random_uuid();
  v_case := public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 18, 'T03', v_key);
  if v_case->>'stage' <> 'repair' or v_case->>'version' <> '19' then raise exception 'T03 failed'; end if;
  if public.transition_repair_case(f.org_id, (v_case->>'caseId')::uuid, 18, 'T03', v_key) <> v_case then
    raise exception 'T03 retry was not idempotent';
  end if;

  v_other := public.create_repair_case(f.org_id, 'GPS model', 'temporary-label-43',
    'Customer', 'Unrepairable', 'normal', 'walk_in', gen_random_uuid());
  perform public.receive_repair_device(f.org_id, (v_other->>'caseId')::uuid, 1, gen_random_uuid(),
    'walk_in', 'Workshop', 'Agent', 'device');
  perform public.transition_repair_case(f.org_id, (v_other->>'caseId')::uuid, 2, 'T01', gen_random_uuid());
  v_diagnosis := public.save_repair_diagnosis(f.org_id, (v_other->>'caseId')::uuid, 3, gen_random_uuid(),
    'Board irreparable', 'irreparable', 'replacement', 'covered');
  perform public.finalize_repair_diagnosis(f.org_id, (v_other->>'caseId')::uuid,
    (v_diagnosis->>'diagnosisId')::uuid, 4, gen_random_uuid());
  perform public.transition_repair_case(f.org_id, (v_other->>'caseId')::uuid, 5, 'T02', gen_random_uuid());
  v_plan := public.save_repair_action_plan(f.org_id, (v_other->>'caseId')::uuid, 6, gen_random_uuid(),
    'replacement', 'Replace with equivalent model', 'warranty', 0, null, 'Model B',
    'irreparable', 'return_to_customer');
  perform set_config('request.jwt.claim.sub', f.technician_id::text, true);
  begin
    perform public.record_repair_plan_approval(f.org_id, (v_other->>'caseId')::uuid,
      (v_plan->>'planId')::uuid, 7, gen_random_uuid(), 'replacement', 'approved');
    raise exception 'Replacement approval without independent permission was accepted';
  exception when insufficient_privilege then
    if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', f.owner_id::text, true);
  perform public.record_repair_plan_approval(f.org_id, (v_other->>'caseId')::uuid,
    (v_plan->>'planId')::uuid, 7, gen_random_uuid(), 'replacement', 'approved');
  select count(*) into v_count from public.repair_plan_approvals
    where plan_id = (v_plan->>'planId')::uuid and kind = 'replacement' and recorded_by = f.owner_id;
  if v_count <> 1 then raise exception 'Same creator replacement approval missing'; end if;
  begin
    perform public.transition_repair_case(f.org_id, (v_other->>'caseId')::uuid, 8, 'T04', gen_random_uuid());
    raise exception 'T04 accepted without free-replacement customer consent';
  exception when check_violation then
    if sqlerrm <> 'CUSTOMER_APPROVAL_REQUIRED' then raise; end if;
  end;
  perform public.record_repair_plan_approval(f.org_id, (v_other->>'caseId')::uuid,
    (v_plan->>'planId')::uuid, 8, gen_random_uuid(), 'customer', 'approved',
    'phone', 'Customer', 'owner', 'call-4', null, pg_catalog.clock_timestamp());
  v_other := public.transition_repair_case(f.org_id, (v_other->>'caseId')::uuid, 9, 'T04', gen_random_uuid());
  if v_other->>'stage' <> 'replacement' or v_other->>'version' <> '10' then raise exception 'T04 failed'; end if;

  v_return := public.create_repair_case(f.org_id, 'GPS model', 'temporary-label-44',
    'Customer', 'Intermittent complaint', 'normal', 'walk_in', gen_random_uuid());
  perform public.receive_repair_device(f.org_id, (v_return->>'caseId')::uuid, 1, gen_random_uuid(),
    'walk_in', 'Workshop', 'Agent', 'device');
  perform public.transition_repair_case(f.org_id, (v_return->>'caseId')::uuid, 2, 'T01', gen_random_uuid());
  v_diagnosis := public.save_repair_diagnosis(f.org_id, (v_return->>'caseId')::uuid, 3, gen_random_uuid(),
    'No fault observed during diagnosis', 'healthy', 'return', 'pending');
  perform public.finalize_repair_diagnosis(f.org_id, (v_return->>'caseId')::uuid,
    (v_diagnosis->>'diagnosisId')::uuid, 4, gen_random_uuid());
  perform public.transition_repair_case(f.org_id, (v_return->>'caseId')::uuid, 5, 'T02', gen_random_uuid());
  v_plan := public.save_repair_action_plan(f.org_id, (v_return->>'caseId')::uuid, 6, gen_random_uuid(),
    'return', 'Return without repair; no fault observed', 'none', 0);
  begin
    perform public.transition_repair_case(f.org_id, (v_return->>'caseId')::uuid, 7, 'T05', gen_random_uuid());
    raise exception 'T05 accepted without return authorization';
  exception when check_violation then
    if sqlerrm <> 'RETURN_AUTHORIZATION_REQUIRED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', f.technician_id::text, true);
  begin
    perform public.record_repair_return_authorization(f.org_id, (v_return->>'caseId')::uuid,
      (v_plan->>'planId')::uuid, 7, gen_random_uuid(), 'phone', 'Customer', 'call-return-1', pg_catalog.clock_timestamp());
    raise exception 'Unprivileged user authorized return';
  exception when insufficient_privilege then
    if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', f.owner_id::text, true);
  v_auth := public.record_repair_return_authorization(f.org_id, (v_return->>'caseId')::uuid,
    (v_plan->>'planId')::uuid, 7, gen_random_uuid(), 'phone', 'Customer', 'call-return-1', pg_catalog.clock_timestamp());
  if v_auth->>'version' <> '8' then raise exception 'Return authorization failed'; end if;
  v_plan := public.save_repair_action_plan(f.org_id, (v_return->>'caseId')::uuid, 8, gen_random_uuid(),
    'return', 'Revised return instructions', 'none', 0);
  begin
    perform public.transition_repair_case(f.org_id, (v_return->>'caseId')::uuid, 9, 'T05', gen_random_uuid());
    raise exception 'T05 reused an old plan authorization';
  exception when check_violation then
    if sqlerrm <> 'RETURN_AUTHORIZATION_REQUIRED' then raise; end if;
  end;
  perform public.record_repair_return_authorization(f.org_id, (v_return->>'caseId')::uuid,
    (v_plan->>'planId')::uuid, 9, gen_random_uuid(), 'phone', 'Customer', 'call-return-2', pg_catalog.clock_timestamp());
  v_key := gen_random_uuid();
  v_return := public.transition_repair_case(f.org_id, (v_return->>'caseId')::uuid, 10, 'T05', v_key);
  if v_return->>'stage' <> 'test' or v_return->>'version' <> '11' then raise exception 'T05 failed'; end if;
  if public.transition_repair_case(f.org_id, (v_return->>'caseId')::uuid, 10, 'T05', v_key) <> v_return then
    raise exception 'T05 retry was not idempotent';
  end if;
  begin
    perform public.transition_repair_case(f.org_id, (v_return->>'caseId')::uuid, 11, 'T08', gen_random_uuid());
    raise exception 'T08 accepted without outgoing QC';
  exception when check_violation then
    if sqlerrm <> 'RETURN_QC_REQUIRED' then raise; end if;
  end;
  raise notice 'repair diagnosis, decision, T03-T05 transition checks passed';
end;
$$;

reset role;
insert into public.repair_devices(org_id,imei,first_verified_by,first_evidence)
select org_id,'900000000000001',owner_id,'fixture-original-label' from diagnosis_fixture;
update public.repair_cases c set verified_device_id=d.id,imei_evidence=d.first_evidence,
 imei_verified_by=d.first_verified_by,imei_verified_at=clock_timestamp()
from public.repair_devices d,diagnosis_fixture f
where c.org_id=f.org_id and c.stage='replacement' and d.org_id=f.org_id and d.imei='900000000000001';
set local role authenticated;
do $$
declare f record; v_case public.repair_cases; v_plan public.repair_action_plans;
 v_stock jsonb; v_allocation jsonb; v_key uuid; v_device uuid;
begin
 select * into f from diagnosis_fixture;
 select * into v_case from public.repair_cases where org_id=f.org_id and stage='replacement' limit 1;
 select * into v_plan from public.repair_action_plans where org_id=f.org_id and case_id=v_case.id order by revision desc limit 1;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 begin
  perform public.receive_repair_replacement_stock(f.org_id,'900000000000002','Model B','Stock shelf',f.owner_id,
   'stock-label-photo','stock-entry-1',gen_random_uuid());
  raise exception 'Unprivileged stock receipt succeeded';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_key:=gen_random_uuid();
 v_stock:=public.receive_repair_replacement_stock(f.org_id,'900000000000002','Model B','Stock shelf',f.owner_id,
  'stock-label-photo','stock-entry-1',v_key);
 if public.receive_repair_replacement_stock(f.org_id,'900000000000002','Model B','Stock shelf',f.owner_id,
  'stock-label-photo','stock-entry-1',v_key)<>v_stock then raise exception 'Stock receipt retry failed'; end if;
 begin
  perform public.receive_repair_replacement_stock(f.org_id,'900000000000002','Model B','Stock shelf',f.owner_id,
   'stock-label-photo-2','stock-entry-2',gen_random_uuid());
  raise exception 'Duplicate stock IMEI accepted';
 exception when unique_violation then
  if sqlerrm<>'REPLACEMENT_IMEI_EXISTS' then raise; end if;
 end;
 v_device:=(v_stock->>'deviceId')::uuid;
 v_key:=gen_random_uuid();
 v_allocation:=public.allocate_repair_replacement_device(f.org_id,v_case.id,v_device,v_plan.id,
  'allocation-1',v_case.version,v_key);
 if public.allocate_repair_replacement_device(f.org_id,v_case.id,v_device,v_plan.id,
  'allocation-1',v_case.version,v_key)<>v_allocation then raise exception 'Allocation retry failed'; end if;
 if not exists(select 1 from public.repair_device_custody_positions p
  where p.org_id=f.org_id and p.device_id=v_device and p.case_id=v_case.id
   and p.location='Stock shelf' and p.custodian_user_id=f.owner_id)
 then raise exception 'Replacement physical baseline missing'; end if;
 begin
  perform public.allocate_repair_replacement_device(f.org_id,v_case.id,v_device,v_plan.id,
   'allocation-2',v_case.version+1,gen_random_uuid());
  raise exception 'Allocated stock reused';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_STOCK_UNAVAILABLE' then raise; end if;
 end;
 raise notice 'replacement serial stock, allocation, custody baseline and idempotency checks passed';
end $$;
reset role;
do $$
declare v_org uuid; v_case uuid; v_device uuid;
begin
 select org_id into v_org from diagnosis_fixture;
 select id into v_case from public.repair_cases where org_id=v_org and stage='replacement' limit 1;
 select device_id into v_device from public.repair_replacement_stock where org_id=v_org and status='allocated';
 begin
  update public.repair_cases set verified_device_id=v_device where id=v_case;
  raise exception 'Replacement stock was accepted as original repair device';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_STOCK_NOT_ORIGINAL' then raise; end if;
 end;
end $$;
set local role authenticated;
do $$
declare f record; v_case public.repair_cases; v_stock public.repair_replacement_stock;
 v_original jsonb; v_replacement jsonb; v_receipt jsonb; v_key uuid; v_original_location text;
begin
 select * into f from diagnosis_fixture;
 select * into v_case from public.repair_cases where org_id=f.org_id and stage='replacement' limit 1;
 select * into v_stock from public.repair_replacement_stock where org_id=f.org_id and allocated_case_id=v_case.id;
 v_original_location:=v_case.device_location;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 perform public.record_repair_device_custody_baseline(f.org_id,v_case.id,v_original_location,
  f.owner_id,'original-baseline-proof',v_case.version,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 v_original:=public.release_repair_device_custody(f.org_id,v_case.id,'Original desk',f.technician_id,
  'Staff','original-transfer-1','original-release-proof',v_case.version,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 v_key:=gen_random_uuid();
 v_replacement:=public.release_repair_replacement_custody(f.org_id,v_case.id,v_stock.device_id,
  'Replacement desk',f.technician_id,'Staff','replacement-transfer-1','replacement-release-proof',
  v_case.version,v_key);
 if public.release_repair_replacement_custody(f.org_id,v_case.id,v_stock.device_id,
  'Replacement desk',f.technician_id,'Staff','replacement-transfer-1','replacement-release-proof',
  v_case.version,v_key)<>v_replacement then raise exception 'Replacement release retry failed'; end if;
 if (select count(*) from public.repair_device_custody_transfers where org_id=f.org_id and case_id=v_case.id and status='in_transit')<>2
 then raise exception 'Independent transfers could not coexist'; end if;
 select * into v_case from public.repair_cases where id=v_case.id;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 v_key:=gen_random_uuid();
 v_receipt:=public.resolve_repair_replacement_custody(f.org_id,v_case.id,(v_replacement->>'transferId')::uuid,
  'accepted','replacement-receipt-1','replacement-receipt-proof',v_case.version,v_key);
 if public.resolve_repair_replacement_custody(f.org_id,v_case.id,(v_replacement->>'transferId')::uuid,
  'accepted','replacement-receipt-1','replacement-receipt-proof',v_case.version,v_key)<>v_receipt
 then raise exception 'Replacement receipt retry failed'; end if;
 if not exists(select 1 from public.repair_replacement_stock s
  join public.repair_device_custody_positions p on p.org_id=s.org_id and p.device_id=s.device_id
  where s.org_id=f.org_id and s.device_id=v_stock.device_id and s.location='Replacement desk'
   and s.custodian_user_id=f.technician_id and p.location=s.location and p.custodian_user_id=s.custodian_user_id)
 then raise exception 'Replacement stock and custody diverged'; end if;
 if not exists(select 1 from public.repair_device_custody_transfers where id=(v_original->>'transferId')::uuid and status='in_transit')
 or not exists(select 1 from public.repair_cases where id=v_case.id and device_location=v_original_location)
 then raise exception 'Replacement receipt changed original device'; end if;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 select * into v_case from public.repair_cases where id=v_case.id;
 perform public.resolve_repair_device_custody(f.org_id,v_case.id,(v_original->>'transferId')::uuid,
  'returned','original-return-1','original-return-proof',v_case.version,gen_random_uuid());
 if not exists(select 1 from public.repair_replacement_stock where org_id=f.org_id
  and device_id=v_stock.device_id and location='Replacement desk' and custodian_user_id=f.technician_id)
 then raise exception 'Original return changed replacement stock'; end if;
 raise notice 'independent original/replacement transfers and stock reconciliation passed';
end $$;
do $$
declare f record; v_case public.repair_cases; v_stock public.repair_replacement_stock;
 v_transfer jsonb; v_discrepancy jsonb; v_key uuid; v_epoch integer;
begin
 select * into f from diagnosis_fixture;
 select * into v_case from public.repair_cases where org_id=f.org_id and stage='replacement' limit 1;
 select * into v_stock from public.repair_replacement_stock where org_id=f.org_id and allocated_case_id=v_case.id;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 v_transfer:=public.release_repair_replacement_custody(f.org_id,v_case.id,v_stock.device_id,
  'Owner desk',f.owner_id,'Staff','replacement-discrepancy-transfer-1','release-proof-1',
  v_case.version,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_key:=gen_random_uuid();
 v_discrepancy:=public.record_repair_custody_discrepancy(f.org_id,v_case.id,
  (v_transfer->>'transferId')::uuid,'identity_mismatch','replacement-identity-mismatch-1',
  'label-mismatch-proof',f.owner_id,clock_timestamp()+interval '1 day',v_case.version,1,v_key);
 if not exists(select 1 from public.repair_device_custody_discrepancies d
  where d.id=(v_discrepancy->>'discrepancyId')::uuid and d.device_id=v_stock.device_id and d.status='open')
 then raise exception 'Replacement discrepancy not tied to device'; end if;
 select * into v_case from public.repair_cases where id=v_case.id;
 begin
  perform public.resolve_repair_replacement_custody(f.org_id,v_case.id,(v_transfer->>'transferId')::uuid,
   'accepted','replacement-premature-receipt','proof',v_case.version,gen_random_uuid());
  raise exception 'Replacement accepted with open discrepancy';
 exception when check_violation then
  if sqlerrm<>'CUSTODY_DISCREPANCY_OPEN' then raise; end if;
 end;
 perform public.resolve_repair_custody_discrepancy(f.org_id,v_case.id,
  (v_discrepancy->>'discrepancyId')::uuid,'replacement-identity-resolved-1',
  'verified-label-proof',v_case.version,2,1,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 perform public.resolve_repair_replacement_custody(f.org_id,v_case.id,(v_transfer->>'transferId')::uuid,
  'accepted','replacement-corrected-receipt-1','independent-receipt-proof',v_case.version,gen_random_uuid());
 if not exists(select 1 from public.repair_replacement_stock where org_id=f.org_id
  and device_id=v_stock.device_id and location='Owner desk' and custodian_user_id=f.owner_id)
 then raise exception 'Corrected receipt did not reconcile replacement stock'; end if;
 select * into v_case from public.repair_cases where id=v_case.id;
 v_epoch:=v_case.custody_damage_epoch;
 v_transfer:=public.release_repair_replacement_custody(f.org_id,v_case.id,v_stock.device_id,
  'Technician desk',f.technician_id,'Staff','replacement-damage-transfer-1','release-proof-2',
  v_case.version,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 v_discrepancy:=public.record_repair_custody_discrepancy(f.org_id,v_case.id,
  (v_transfer->>'transferId')::uuid,'damage','replacement-damage-1',
  'damage-photo-ref',f.owner_id,clock_timestamp()+interval '1 day',v_case.version,1,gen_random_uuid());
 if not exists(select 1 from public.repair_cases where id=v_case.id and custody_damage_epoch=v_epoch+1)
 then raise exception 'Replacement damage did not invalidate quality epoch'; end if;
 select * into v_case from public.repair_cases where id=v_case.id;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  perform public.resolve_repair_custody_discrepancy(f.org_id,v_case.id,
   (v_discrepancy->>'discrepancyId')::uuid,'replacement-damage-premature-resolution',
   'proof',v_case.version,2,1,gen_random_uuid());
  raise exception 'Replacement damage resolved before physical return';
 exception when check_violation then
  if sqlerrm<>'CUSTODY_DISCREPANCY_RETURN_REQUIRED' then raise; end if;
 end;
 perform public.resolve_repair_replacement_custody(f.org_id,v_case.id,(v_transfer->>'transferId')::uuid,
  'returned','replacement-damage-return-1','return-proof',v_case.version,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 perform public.resolve_repair_custody_discrepancy(f.org_id,v_case.id,
  (v_discrepancy->>'discrepancyId')::uuid,'replacement-damage-resolved-1',
  'inspection-proof',v_case.version,3,1,gen_random_uuid());
 if not exists(select 1 from public.repair_replacement_stock where org_id=f.org_id
  and device_id=v_stock.device_id and location='Owner desk' and custodian_user_id=f.owner_id)
 then raise exception 'Damage return changed confirmed replacement stock'; end if;
 select * into v_case from public.repair_cases where id=v_case.id;
 v_transfer:=public.release_repair_replacement_custody(f.org_id,v_case.id,v_stock.device_id,
  'Second technician desk',f.technician_id,'Staff','replacement-returned-mismatch-transfer',
  'release-proof-3',v_case.version,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 v_discrepancy:=public.record_repair_custody_discrepancy(f.org_id,v_case.id,
  (v_transfer->>'transferId')::uuid,'destination_mismatch','replacement-returned-mismatch-1',
  'destination-proof',f.owner_id,clock_timestamp()+interval '1 day',v_case.version,1,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 perform public.resolve_repair_replacement_custody(f.org_id,v_case.id,(v_transfer->>'transferId')::uuid,
  'returned','replacement-mismatch-return-1','return-proof-2',v_case.version,gen_random_uuid());
 select * into v_case from public.repair_cases where id=v_case.id;
 perform public.resolve_repair_custody_discrepancy(f.org_id,v_case.id,
  (v_discrepancy->>'discrepancyId')::uuid,'replacement-returned-mismatch-resolved-1',
  'inspection-proof-2',v_case.version,3,1,gen_random_uuid());
 if exists(select 1 from public.repair_device_custody_discrepancies
  where org_id=f.org_id and device_id=v_stock.device_id and status='open')
 then raise exception 'Returned replacement discrepancy remained open'; end if;
 raise notice 'replacement discrepancy, acceptance blocker, damage return and quality epoch passed';
end $$;
reset role;
insert into public.repair_devices (org_id, imei, first_verified_by, first_evidence)
select f.org_id, '123456789012345', f.owner_id, 'test-label-evidence' from diagnosis_fixture f;
update public.repair_cases c
set verified_device_id = d.id, imei_evidence = 'test-label-evidence',
    imei_verified_at = pg_catalog.clock_timestamp(), imei_verified_by = d.first_verified_by
from public.repair_devices d, diagnosis_fixture f
where c.org_id = f.org_id and c.stage = 'test' and d.org_id = c.org_id
  and d.imei = '123456789012345';
set local role authenticated;
do $$
declare
  f record;
  v_case public.repair_cases;
  v_check jsonb;
  v_key uuid;
begin
  select * into f from diagnosis_fixture;
  select * into v_case from public.repair_cases where org_id = f.org_id and stage = 'test';
  perform set_config('request.jwt.claim.sub', f.owner_id::text, true);
  begin
    perform public.record_repair_return_outgoing_check(f.org_id, v_case.id, 11, gen_random_uuid(),
      true, '', true, 'items', true, 'condition', true, 'transport', 'Customer', 'owner', null);
    raise exception 'QC accepted empty evidence';
  exception when check_violation then
    if sqlerrm <> 'INVALID_RETURN_QC' then raise; end if;
  end;
  v_check := public.record_repair_return_outgoing_check(f.org_id, v_case.id, 11, gen_random_uuid(),
    true, 'label', true, 'receipt', false, 'not disclosed', true, 'pack', 'Customer', 'owner', null);
  begin
    perform public.release_repair_return_outgoing_check(f.org_id, v_case.id,
      (v_check->>'checkId')::uuid, 12, gen_random_uuid());
    raise exception 'Failed QC was released';
  exception when check_violation then
    if sqlerrm <> 'RETURN_QC_REQUIRED' then raise; end if;
  end;
  v_check := public.record_repair_return_outgoing_check(f.org_id, v_case.id, 12, gen_random_uuid(),
    true, 'label', true, 'receipt', true, 'return condition disclosed', true, 'pack', 'Customer', 'owner', null);
  perform set_config('request.jwt.claim.sub', f.technician_id::text, true);
  begin
    perform public.release_repair_return_outgoing_check(f.org_id, v_case.id,
      (v_check->>'checkId')::uuid, 13, gen_random_uuid());
    raise exception 'Unprivileged user released QC';
  exception when insufficient_privilege then
    if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', f.owner_id::text, true);
  begin
    perform public.transition_repair_case(f.org_id, v_case.id, 13, 'T08', gen_random_uuid());
    raise exception 'T08 accepted unreleased QC';
  exception when check_violation then
    if sqlerrm <> 'QUALITY_RELEASE_REQUIRED' then raise; end if;
  end;
  perform public.release_repair_return_outgoing_check(f.org_id, v_case.id,
    (v_check->>'checkId')::uuid, 13, gen_random_uuid());
  v_check := public.record_repair_return_outgoing_check(f.org_id, v_case.id, 14, gen_random_uuid(),
    true, 'label', true, 'receipt', false, 'new discrepancy', true, 'pack', 'Customer', 'owner', null);
  begin
    perform public.transition_repair_case(f.org_id, v_case.id, 15, 'T08', gen_random_uuid());
    raise exception 'T08 reused release from older QC';
  exception when check_violation then
    if sqlerrm <> 'RETURN_QC_REQUIRED' then raise; end if;
  end;
  v_check := public.record_repair_return_outgoing_check(f.org_id, v_case.id, 15, gen_random_uuid(),
    true, 'label', true, 'receipt', true, 'return condition disclosed', true, 'pack', 'Customer', 'owner', null);
  perform public.release_repair_return_outgoing_check(f.org_id, v_case.id,
    (v_check->>'checkId')::uuid, 16, gen_random_uuid());
  v_key := gen_random_uuid();
  if public.transition_repair_case(f.org_id, v_case.id, 17, 'T08', v_key)->>'stage' <> 'delivery' then
    raise exception 'T08 failed after quality release';
  end if;
  if public.transition_repair_case(f.org_id, v_case.id, 17, 'T08', v_key)->>'stage' <> 'delivery' then
    raise exception 'T08 retry was not idempotent';
  end if;
  raise notice 'return outgoing QC and T08 checks passed';
end;
$$;

do $$
declare f record; v_case public.repair_cases; v_transfer uuid; v_discrepancy uuid;
  v_check jsonb; v_key uuid; v_result jsonb;
begin
  select * into f from diagnosis_fixture;
  select * into v_case from public.repair_cases where org_id=f.org_id and stage='delivery';
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  begin
    perform public.return_repair_case_to_test_after_damage(f.org_id,v_case.id,18,gen_random_uuid());
    raise exception 'T11 allowed without new damage';
  exception when check_violation then
    if sqlerrm<>'CUSTODY_DAMAGE_RETURN_REQUIRED' then raise; end if;
  end;
  perform public.record_repair_device_custody_baseline(f.org_id,v_case.id,'Workshop',f.owner_id,'baseline-proof',18,gen_random_uuid());
  v_transfer := (public.release_repair_device_custody(f.org_id,v_case.id,'Delivery desk',f.technician_id,
    'Internal courier','damage-test-release','release-proof',19,gen_random_uuid())->>'transferId')::uuid;
  perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
  v_discrepancy := (public.record_repair_custody_discrepancy(f.org_id,v_case.id,v_transfer,'damage',
    'damage-after-T08','damage-photo',f.owner_id,clock_timestamp()+interval '1 day',20,1,gen_random_uuid())->>'discrepancyId')::uuid;
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  begin
    perform public.return_repair_case_to_test_after_damage(f.org_id,v_case.id,21,gen_random_uuid());
    raise exception 'T11 allowed before physical return';
  exception when check_violation then
    if sqlerrm<>'CUSTODY_DAMAGE_RETURN_REQUIRED' then raise; end if;
  end;
  perform public.resolve_repair_device_custody(f.org_id,v_case.id,v_transfer,'returned','physical-return','return-proof',21,gen_random_uuid());
  v_key:=gen_random_uuid();
  v_result:=public.return_repair_case_to_test_after_damage(f.org_id,v_case.id,22,v_key);
  if v_result->>'stage'<>'test' or v_result->>'version'<>'23' then raise exception 'T11 failed'; end if;
  if public.return_repair_case_to_test_after_damage(f.org_id,v_case.id,22,v_key)<>v_result then
    raise exception 'T11 retry not idempotent';
  end if;
  begin
    perform public.record_repair_return_outgoing_check(f.org_id,v_case.id,23,gen_random_uuid(),
      true,'label',true,'items',true,'condition',true,'transport','Customer','owner',null);
    raise exception 'QC allowed with open damage';
  exception when check_violation then
    if sqlerrm<>'CUSTODY_DAMAGE_REVIEW_REQUIRED' then raise; end if;
  end;
  perform public.resolve_repair_custody_discrepancy(f.org_id,v_case.id,v_discrepancy,
    'review-complete','inspection-proof',23,3,1,gen_random_uuid());
  begin
    perform public.transition_repair_case(f.org_id,v_case.id,24,'T08',gen_random_uuid());
    raise exception 'T08 reused QC after damage';
  exception when check_violation then
    if sqlerrm<>'RETURN_QC_REQUIRED' and sqlerrm<>'CUSTODY_DAMAGE_REVIEW_REQUIRED' then raise; end if;
  end;
  v_check:=public.record_repair_return_outgoing_check(f.org_id,v_case.id,24,gen_random_uuid(),
    true,'label',true,'items',true,'condition',true,'transport','Customer','owner',null);
  perform public.release_repair_return_outgoing_check(f.org_id,v_case.id,(v_check->>'checkId')::uuid,25,gen_random_uuid());
  if public.transition_repair_case(f.org_id,v_case.id,26,'T08',gen_random_uuid())->>'stage'<>'delivery' then
    raise exception 'T08 failed after retest';
  end if;
  raise notice 'damage in delivery, T11, and fresh outgoing QC checks passed';
end;
$$;

do $$
declare f record; v_case public.repair_cases; v_dispatch jsonb; v_receipt jsonb; v_key uuid;
begin
 begin
  select * into f from diagnosis_fixture;
  select * into v_case from public.repair_cases where org_id=f.org_id and stage='delivery';
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  v_key:=gen_random_uuid();
  v_dispatch:=public.record_repair_delivery_dispatch(f.org_id,v_case.id,27,v_key,
   'post','National post','Tehran, destination','post-track-1','post-dispatch-1','dispatch-proof');
  if v_dispatch->>'deliveryStatus'<>'in_transit' or v_dispatch->>'version'<>'28' then
   raise exception 'Dispatch did not enter transit'; end if;
  if not exists(select 1 from public.repair_device_custody_positions p
   where p.org_id=f.org_id and p.device_id=v_case.verified_device_id and p.holder_kind='carrier'
    and p.custodian_user_id is null and p.custodian_label='National post'
    and p.external_reference='post-dispatch-1') then
   raise exception 'Dispatch left staff as confirmed custodian'; end if;
  if public.record_repair_delivery_dispatch(f.org_id,v_case.id,27,v_key,
   'post','National post','Tehran, destination','post-track-1','post-dispatch-1','dispatch-proof')<>v_dispatch then
   raise exception 'Dispatch retry not idempotent'; end if;
  begin
   perform public.close_repair_return_case(f.org_id,v_case.id,28,gen_random_uuid());
   raise exception 'T09 accepted dispatch without destination receipt';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_RECEIPT_REQUIRED' then raise; end if;
  end;
  begin
   perform public.record_repair_delivery_receipt(f.org_id,v_case.id,28,gen_random_uuid(),
    'Customer','owner',null,'walk-in-after-post','independent-proof');
   raise exception 'In-person receipt accepted after dispatch';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_ALREADY_DISPATCHED' then raise; end if;
  end;
  begin
   perform public.confirm_repair_delivery_receipt(f.org_id,v_case.id,gen_random_uuid(),28,gen_random_uuid(),
    'Customer','owner',null,'post-receipt-wrong','destination-proof');
   raise exception 'Receipt accepted a different dispatch';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_DISPATCH_MISMATCH' then raise; end if;
  end;
  begin
   perform public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,28,gen_random_uuid(),
    'Customer','owner',null,'post-receipt-duplicate-proof','dispatch-proof');
   raise exception 'Receipt reused dispatch proof';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_INDEPENDENT_RECEIPT_REQUIRED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
  begin
   perform public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,28,gen_random_uuid(),
    'Customer','owner',null,'post-receipt-denied','destination-proof');
   raise exception 'Unprivileged destination receipt accepted';
  exception when insufficient_privilege then
   if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  v_key:=gen_random_uuid();
  v_receipt:=public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,28,v_key,
   'Customer','owner',null,'post-receipt-1','signed-destination-receipt');
  if v_receipt->>'deliveryStatus'<>'received' or v_receipt->>'version'<>'29' then
   raise exception 'Remote receipt not recorded'; end if;
  if not exists(select 1 from public.repair_device_custody_positions p
   where p.org_id=f.org_id and p.device_id=v_case.verified_device_id and p.holder_kind='recipient'
    and p.custodian_user_id is null and p.custodian_label='Customer'
    and p.external_reference='post-receipt-1') then
   raise exception 'Destination receipt did not confirm recipient custody'; end if;
  if public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,28,v_key,
   'Customer','owner',null,'post-receipt-1','signed-destination-receipt')<>v_receipt then
   raise exception 'Remote receipt retry not idempotent'; end if;
  if public.close_repair_return_case(f.org_id,v_case.id,29,gen_random_uuid())->>'stage'<>'closed' then
   raise exception 'T09 rejected valid remote receipt'; end if;
  raise notice 'postal dispatch, independent destination receipt, and T09 checks passed';
  raise exception 'TEST_REMOTE_ROLLBACK';
 exception when raise_exception then
  if sqlerrm<>'TEST_REMOTE_ROLLBACK' then raise; end if;
 end;
end;
$$;

do $$
declare f record; v_case public.repair_cases; v_dispatch jsonb;
begin
 begin
  select * into f from diagnosis_fixture;
  select * into v_case from public.repair_cases where org_id=f.org_id and stage='delivery';
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  v_dispatch:=public.record_repair_delivery_dispatch(f.org_id,v_case.id,27,gen_random_uuid(),
   'courier','City courier','Tehran, courier destination','courier-track-1','courier-dispatch-1','courier-proof');
  perform public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,28,gen_random_uuid(),
   'Customer','owner',null,'courier-receipt-1','courier-destination-proof');
  if public.close_repair_return_case(f.org_id,v_case.id,29,gen_random_uuid())->>'stage'<>'closed' then
   raise exception 'Courier T09 failed'; end if;
  raise notice 'courier dispatch and destination receipt checks passed';
  raise exception 'TEST_COURIER_ROLLBACK';
 exception when raise_exception then
  if sqlerrm<>'TEST_COURIER_ROLLBACK' then raise; end if;
 end;
end;
$$;


do $$
declare f record; v_case public.repair_cases; v_dispatch jsonb; v_incident jsonb;
 v_followup jsonb; v_resolved jsonb; v_receipt jsonb; v_key uuid;
begin
 begin
  select * into f from diagnosis_fixture;
  select * into v_case from public.repair_cases where org_id=f.org_id and stage='delivery';
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  v_dispatch:=public.record_repair_delivery_dispatch(f.org_id,v_case.id,27,gen_random_uuid(),
   'post','National post','Tehran, destination','incident-track-1','incident-dispatch-1','incident-dispatch-proof');
  v_key:=gen_random_uuid();
  v_incident:=public.record_repair_delivery_incident(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,
   'lost','incident-lost-1','carrier-search-report',f.owner_id,clock_timestamp()+interval '2 days',28,v_key);
  if v_incident->>'version'<>'29' or v_incident->>'incidentVersion'<>'1' then
   raise exception 'Incident version incorrect'; end if;
  perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
  begin
   perform public.followup_repair_delivery_incident(f.org_id,v_case.id,(v_incident->>'incidentId')::uuid,
    29,1,'unprivileged-followup','Unauthorized update',f.owner_id,clock_timestamp()+interval '3 days',gen_random_uuid());
   raise exception 'Unprivileged incident followup accepted';
  exception when insufficient_privilege then
   if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  begin
   perform public.record_repair_delivery_incident(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,
    'delivery_discrepancy','incident-other-1','carrier-report',f.owner_id,clock_timestamp()+interval '2 days',29,gen_random_uuid());
   raise exception 'Second open incident accepted on one dispatch';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_INCIDENT_OPEN' then raise; end if;
  end;
  begin
   perform public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,29,
    gen_random_uuid(),'Customer','owner',null,'blocked-receipt-1','destination-proof');
   raise exception 'Receipt accepted open incident';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_INCIDENT_OPEN' then raise; end if;
  end;
  begin
   perform public.close_repair_return_case(f.org_id,v_case.id,29,gen_random_uuid());
   raise exception 'T09 accepted open incident';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_INCIDENT_OPEN' then raise; end if;
  end;
  v_key:=gen_random_uuid();
  v_followup:=public.followup_repair_delivery_incident(f.org_id,v_case.id,(v_incident->>'incidentId')::uuid,
   29,1,'followup-1','Carrier search in progress',f.owner_id,clock_timestamp()+interval '3 days',v_key);
  if v_followup->>'status'<>'open' or v_followup->>'incidentVersion'<>'2' then
   raise exception 'Followup changed incident status or version incorrectly'; end if;
  begin
   perform public.followup_repair_delivery_incident(f.org_id,v_case.id,(v_incident->>'incidentId')::uuid,
    30,1,'followup-stale','Another update',f.owner_id,clock_timestamp()+interval '4 days',gen_random_uuid());
   raise exception 'Stale incident version accepted';
  exception when raise_exception then
   if sqlerrm<>'DELIVERY_INCIDENT_VERSION_CONFLICT' then raise; end if;
  end;
  begin
   perform public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,30,
    gen_random_uuid(),'Customer','owner',null,'blocked-receipt-2','destination-proof');
   raise exception 'Followup released receipt';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_INCIDENT_OPEN' then raise; end if;
  end;
  v_resolved:=public.resolve_repair_delivery_incident(f.org_id,v_case.id,(v_incident->>'incidentId')::uuid,
   30,2,'lost-resolved-1','carrier-found-device',gen_random_uuid());
  if v_resolved->>'status'<>'resolved' or v_resolved->>'version'<>'31' then
   raise exception 'Lost incident not resolved'; end if;
  v_receipt:=public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,31,
   gen_random_uuid(),'Customer','owner',null,'after-incident-receipt','signed-destination-receipt');
  if v_receipt->>'version'<>'32' then raise exception 'Independent receipt after resolution failed'; end if;
  if public.close_repair_return_case(f.org_id,v_case.id,32,gen_random_uuid())->>'stage'<>'closed' then
   raise exception 'T09 after resolved incident failed'; end if;
  raise notice 'lost incident, followup blocker, resolution, independent receipt and T09 passed';
  raise exception 'TEST_INCIDENT_ROLLBACK';
 exception when raise_exception then
  if sqlerrm<>'TEST_INCIDENT_ROLLBACK' then raise; end if;
 end;
end;
$$;

do $$
declare f record; v_case public.repair_cases; v_dispatch jsonb; v_incident jsonb;
begin
 begin
  select * into f from diagnosis_fixture;
  select * into v_case from public.repair_cases where org_id=f.org_id and stage='delivery';
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  v_dispatch:=public.record_repair_delivery_dispatch(f.org_id,v_case.id,27,gen_random_uuid(),
   'courier','City courier','Tehran','damage-track-1','damage-dispatch-1','damage-dispatch-proof');
  v_incident:=public.record_repair_delivery_incident(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,
   'damage','incident-damage-1','photo-of-damage',f.owner_id,clock_timestamp()+interval '2 days',28,gen_random_uuid());
  begin
   perform public.resolve_repair_delivery_incident(f.org_id,v_case.id,(v_incident->>'incidentId')::uuid,
    29,1,'damage-resolved-1','carrier-claim',gen_random_uuid());
   raise exception 'Damage resolved without physical return';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_DAMAGE_RETURN_REQUIRED' then raise; end if;
  end;
  raise notice 'shipment damage remains blocked until physical return';
  raise exception 'TEST_DAMAGE_ROLLBACK';
 exception when raise_exception then
  if sqlerrm<>'TEST_DAMAGE_ROLLBACK' then raise; end if;
 end;
end;
$$;

do $$
declare f record; v_case public.repair_cases; v_dispatch jsonb; v_incident jsonb;
 v_return jsonb; v_check jsonb; v_new_dispatch jsonb; v_receipt jsonb; v_key uuid;
begin
 begin
  select * into f from diagnosis_fixture;
  select * into v_case from public.repair_cases where org_id=f.org_id and stage='delivery';
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  v_dispatch:=public.record_repair_delivery_dispatch(f.org_id,v_case.id,27,gen_random_uuid(),
   'courier','City courier','Tehran','damage-retry-track-1','damage-retry-dispatch-1','damage-retry-dispatch-proof');
  v_incident:=public.record_repair_delivery_incident(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,
   'damage','damage-retry-incident-1','damage-retry-photo',f.owner_id,clock_timestamp()+interval '2 days',28,gen_random_uuid());
  perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
  begin
   perform public.receive_repair_delivery_damage_return(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,
    (v_incident->>'incidentId')::uuid,29,1,gen_random_uuid(),
    'Workshop','Screen crack','damage-return-denied','return-photo');
   raise exception 'Unprivileged physical return accepted';
  exception when insufficient_privilege then
   if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  begin
   perform public.receive_repair_delivery_damage_return(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,
    (v_incident->>'incidentId')::uuid,29,1,gen_random_uuid(),
    'Workshop','Screen crack','damage-retry-dispatch-1','return-photo');
   raise exception 'Dispatch reference reused for return';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_INDEPENDENT_RETURN_REQUIRED' then raise; end if;
  end;
  v_key:=gen_random_uuid();
  v_return:=public.receive_repair_delivery_damage_return(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,
   (v_incident->>'incidentId')::uuid,29,1,v_key,
   'Workshop','Screen crack visible','damage-retry-return-1','independent-return-photo');
  if v_return->>'version'<>'30' or v_return->>'damageEpoch' is null then
   raise exception 'Damage return did not invalidate outgoing check'; end if;
  if not exists(select 1 from public.repair_device_custody_positions p
   where p.org_id=f.org_id and p.device_id=v_case.verified_device_id and p.holder_kind='staff'
    and p.custodian_user_id=f.owner_id and p.external_reference is null and p.location='Workshop') then
   raise exception 'Physical damage return did not restore staff custody'; end if;
  if public.receive_repair_delivery_damage_return(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,
   (v_incident->>'incidentId')::uuid,29,1,v_key,
   'Workshop','Screen crack visible','damage-retry-return-1','independent-return-photo')<>v_return then
   raise exception 'Damage return retry not idempotent'; end if;
  begin
   perform public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,30,
    gen_random_uuid(),'Customer','owner',null,'stale-destination-receipt','destination-proof');
   raise exception 'Old dispatch accepted destination receipt';
  exception when check_violation then
   if sqlerrm not in ('DELIVERY_QC_REQUIRED','DELIVERY_DISPATCH_MISMATCH') then raise; end if;
  end;
  begin
   perform public.record_repair_delivery_dispatch(f.org_id,v_case.id,30,gen_random_uuid(),
    'courier','City courier','Tehran','premature-track','premature-dispatch','premature-proof');
   raise exception 'New dispatch accepted before retest';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_QC_REQUIRED' then raise; end if;
  end;
  if public.return_repair_case_to_test_after_damage(f.org_id,v_case.id,30,gen_random_uuid())->>'stage'<>'test' then
   raise exception 'T11 failed after physical shipment return'; end if;
  v_check:=public.record_repair_return_outgoing_check(f.org_id,v_case.id,31,gen_random_uuid(),
   true,'retest-label',true,'retest-items',true,'damage disclosed',true,'repacked',
   'Customer','owner',null);
  perform public.release_repair_return_outgoing_check(f.org_id,v_case.id,(v_check->>'checkId')::uuid,32,gen_random_uuid());
  if public.transition_repair_case(f.org_id,v_case.id,33,'T08',gen_random_uuid())->>'stage'<>'delivery' then
   raise exception 'Fresh T08 failed'; end if;
  v_new_dispatch:=public.record_repair_delivery_dispatch(f.org_id,v_case.id,34,gen_random_uuid(),
   'post','National post','Tehran','damage-retry-track-2','damage-retry-dispatch-2','new-dispatch-proof');
  if v_new_dispatch->>'version'<>'35' or (v_new_dispatch->>'dispatchId')::uuid=(v_dispatch->>'dispatchId')::uuid then
   raise exception 'Corrective dispatch was not a new attempt'; end if;
  if not exists(select 1 from public.repair_device_custody_positions p
   where p.org_id=f.org_id and p.device_id=v_case.verified_device_id and p.holder_kind='carrier'
    and p.custodian_user_id is null and p.external_reference='damage-retry-dispatch-2') then
   raise exception 'Corrective dispatch did not confirm new carrier custody'; end if;
  if (select count(*) from public.repair_delivery_dispatches where org_id=f.org_id and case_id=v_case.id)<>2
   or (select count(*) from public.repair_delivery_dispatches where org_id=f.org_id and case_id=v_case.id and status='in_transit')<>1 then
   raise exception 'Shipment history or active uniqueness incorrect'; end if;
  begin
   perform public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_dispatch->>'dispatchId')::uuid,35,
    gen_random_uuid(),'Customer','owner',null,'stale-after-retest-receipt','stale-receipt-proof');
   raise exception 'Returned dispatch accepted a receipt after fresh QC';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_DISPATCH_MISMATCH' then raise; end if;
  end;
  v_receipt:=public.confirm_repair_delivery_receipt(f.org_id,v_case.id,(v_new_dispatch->>'dispatchId')::uuid,35,
   gen_random_uuid(),'Customer','owner',null,'damage-retry-receipt','signed-receipt-after-retest');
  if v_receipt->>'version'<>'36' or public.close_repair_return_case(f.org_id,v_case.id,36,gen_random_uuid())->>'stage'<>'closed' then
   raise exception 'Corrective delivery and T09 failed'; end if;
  raise notice 'damage return, T11, fresh QC, corrective dispatch, receipt and T09 passed';
  raise exception 'TEST_DAMAGE_RETRY_ROLLBACK';
 exception when raise_exception then
  if sqlerrm<>'TEST_DAMAGE_RETRY_ROLLBACK' then raise; end if;
 end;
end;
$$;

reset role;
do $$
declare v_case_id uuid;
begin
  select c.id into v_case_id from public.repair_cases c
    join diagnosis_fixture f on f.org_id=c.org_id
    where c.stage='delivery' limit 1;
  begin
    update public.repair_cases set custody_damage_epoch=custody_damage_epoch+1 where id=v_case_id;
    update public.repair_cases set stage='closed' where id=v_case_id;
    raise exception 'Final handover accepted stale outgoing QC';
  exception when check_violation then
    if sqlerrm<>'CUSTODY_DAMAGE_REVIEW_REQUIRED' then raise; end if;
  end;
  begin
    update public.repair_cases set stage='closed' where id=v_case_id;
    raise exception 'Direct closure accepted without actual receipt';
  exception when check_violation then
    if sqlerrm<>'DELIVERY_RECEIPT_REQUIRED' then raise; end if;
  end;
end;
$$;
set local role authenticated;

do $$
declare f record; v_case public.repair_cases; v_receipt jsonb; v_key uuid; v_result jsonb;
begin
 select * into f from diagnosis_fixture;
 select * into v_case from public.repair_cases where org_id=f.org_id and stage='delivery';
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  perform public.close_repair_return_case(f.org_id,v_case.id,27,gen_random_uuid());
  raise exception 'T09 accepted without receipt';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_RECEIPT_REQUIRED' then raise; end if;
 end;
 begin
  perform public.record_repair_delivery_receipt(f.org_id,v_case.id,27,gen_random_uuid(),
   'Other customer','owner',null,'delivery-wrong','signed-receipt');
  raise exception 'Receipt accepted mismatched recipient';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_RECIPIENT_MISMATCH' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 begin
  perform public.record_repair_delivery_receipt(f.org_id,v_case.id,27,gen_random_uuid(),
   'Customer','owner',null,'delivery-denied','signed-receipt');
  raise exception 'Unprivileged receipt accepted';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_key:=gen_random_uuid();
 v_receipt:=public.record_repair_delivery_receipt(f.org_id,v_case.id,27,v_key,
  'Customer','owner',null,'delivery-good','signed-receipt');
 if public.record_repair_delivery_receipt(f.org_id,v_case.id,27,v_key,
  'Customer','owner',null,'delivery-good','signed-receipt')<>v_receipt then
  raise exception 'Receipt retry not idempotent'; end if;
 if v_receipt->>'version'<>'28' then raise exception 'Receipt version incorrect'; end if;
 if not exists(select 1 from public.repair_device_custody_positions p
  where p.org_id=f.org_id and p.device_id=v_case.verified_device_id and p.holder_kind='recipient'
   and p.custodian_user_id is null and p.custodian_label='Customer'
   and p.external_reference='delivery-good') then
  raise exception 'In-person handover left staff as confirmed custodian'; end if;
 v_key:=gen_random_uuid();
 v_result:=public.close_repair_return_case(f.org_id,v_case.id,28,v_key);
 if v_result->>'stage'<>'closed' or v_result->>'version'<>'29' then raise exception 'T09 failed'; end if;
 if public.close_repair_return_case(f.org_id,v_case.id,28,v_key)<>v_result then
  raise exception 'T09 retry not idempotent'; end if;
 if not exists(select 1 from public.repair_cases where id=v_case.id and closed_at is not null) then
  raise exception 'Closure timestamp missing'; end if;
 raise notice 'in-person return receipt and T09 checks passed';
end;
$$;

-- A subsequent case for the same delivered device needs a new, documented staff baseline.
create temp table reentry_fixture(case_id uuid) on commit drop;
grant select on reentry_fixture to authenticated;
do $$
declare f record; v_created jsonb;
begin
 select * into f from diagnosis_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_created:=public.create_repair_case(f.org_id,'GPS model','123456789012345',
  'Customer','Returned for another issue','normal','walk_in',gen_random_uuid());
 insert into reentry_fixture values((v_created->>'caseId')::uuid);
end;
$$;
reset role;
update public.repair_cases c set received_at=pg_catalog.clock_timestamp(),receipt_method='walk_in',
 device_location='Workshop',device_custodian='Agent',verified_device_id=previous.verified_device_id,
 imei_evidence='reentry-imei-photo',imei_verified_by=f.owner_id,imei_verified_at=pg_catalog.clock_timestamp(),
 version=2
from reentry_fixture n, public.repair_cases previous, diagnosis_fixture f
where c.id=n.case_id and c.org_id=f.org_id and previous.org_id=f.org_id
 and previous.stage='closed' and previous.verified_device_id is not null;
set local role authenticated;
do $$
declare f record; v_case_id uuid; v_device_id uuid;
begin
 select * into f from diagnosis_fixture;
 select case_id into v_case_id from reentry_fixture;
 select verified_device_id into v_device_id from public.repair_cases where id=v_case_id;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  perform public.release_repair_device_custody(f.org_id,v_case_id,'Other desk',f.technician_id,
   'Staff carrier','reentry-premature-release','proof',2,gen_random_uuid());
  raise exception 'External recipient was treated as staff custodian';
 exception when insufficient_privilege then
  if sqlerrm<>'CUSTODY_SOURCE_MISMATCH' then raise; end if;
 end;
 perform public.record_repair_device_custody_baseline(f.org_id,v_case_id,'Workshop',
  f.owner_id,'new-physical-inspection',2,gen_random_uuid());
 if not exists(select 1 from public.repair_device_custody_positions p
  where p.org_id=f.org_id and p.device_id=v_device_id and p.case_id=v_case_id
   and p.holder_kind='staff' and p.custodian_user_id=f.owner_id
   and p.external_reference is null and p.baseline_evidence='new-physical-inspection') then
  raise exception 'New physical intake did not restore staff custody'; end if;
 raise notice 'same-device reentry requires new documented staff baseline';
end;
$$;


do $$ begin
  begin
    insert into public.repair_diagnoses (org_id, case_id, revision, findings, technical_condition,
      recommended_action, warranty_coverage, created_by)
    values (gen_random_uuid(), gen_random_uuid(), 1, 'x', 'healthy', 'return', 'pending', gen_random_uuid());
    raise exception 'Direct diagnosis write was accepted';
  exception when insufficient_privilege then null;
  end;
end $$;

do $$ begin
  begin
    insert into public.repair_return_authorizations (org_id, case_id, plan_id, notification_channel,
      notified_person, notification_reference, notified_at, authorized_by)
    values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'phone',
      'Customer', 'fake-call', pg_catalog.clock_timestamp(), gen_random_uuid());
    raise exception 'Direct return authorization write was accepted';
  exception when insufficient_privilege then null;
  end;
end $$;

do $$ begin
  begin
    insert into public.repair_return_outgoing_checks (org_id, case_id, plan_id, authorization_id, device_id,
      revision, identity_pass, identity_evidence, items_pass, items_evidence, condition_pass,
      condition_evidence, transport_pass, transport_evidence, intended_recipient, recipient_role, recorded_by)
    values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
      1, true, 'x', true, 'x', true, 'x', true, 'x', 'Customer', 'owner', gen_random_uuid());
    raise exception 'Direct outgoing QC write was accepted';
  exception when insufficient_privilege then null;
  end;
end $$;

do $$ begin
  begin
    insert into public.repair_return_outgoing_releases (org_id, case_id, check_id, released_by)
    values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid());
    raise exception 'Direct quality-release write was accepted';
  exception when insufficient_privilege then null;
  end;
end $$;

-- T06: a verified, documented repair may enter test, but is not quality-released.
reset role;
create function pg_temp.add_completion_imei_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.add_completion_imei_evidence(text,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; v_case jsonb; v_diagnosis jsonb; v_plan jsonb; v_done jsonb; v_key uuid; v_evidence text;
begin
 select * into f from diagnosis_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_case:=public.create_repair_case(f.org_id,'GPS model','repair-t06','Customer','No power',
   'normal','walk_in',gen_random_uuid());
 v_evidence:=f.org_id::text||'/'||(v_case->>'caseId')||'/'||gen_random_uuid()::text||'.png';
 perform pg_temp.add_completion_imei_evidence(v_evidence,f.owner_id);
 perform public.receive_repair_device(f.org_id,(v_case->>'caseId')::uuid,1,gen_random_uuid(),
   'walk_in','Workshop','Owner','charger','359881234567890',v_evidence);
 perform public.transition_repair_case(f.org_id,(v_case->>'caseId')::uuid,2,'T01',gen_random_uuid());
 v_diagnosis:=public.save_repair_diagnosis(f.org_id,(v_case->>'caseId')::uuid,3,gen_random_uuid(),
   'Power contact restored','needs_repair','repair','covered');
 perform public.finalize_repair_diagnosis(f.org_id,(v_case->>'caseId')::uuid,
   (v_diagnosis->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,(v_case->>'caseId')::uuid,5,'T02',gen_random_uuid());
 v_plan:=public.save_repair_action_plan(f.org_id,(v_case->>'caseId')::uuid,6,gen_random_uuid(),
   'repair','Restore power contact','warranty',0,'no_parts');
 perform public.transition_repair_case(f.org_id,(v_case->>'caseId')::uuid,7,'T03',gen_random_uuid());
 begin
  perform public.complete_repair_for_test(f.org_id,(v_case->>'caseId')::uuid,8,gen_random_uuid(),
    'repair_functional_v1',null,null);
  raise exception 'T06 accepted no recorded work';
 exception when check_violation then
  if sqlerrm<>'REPAIR_WORK_REQUIRED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 begin
  perform public.complete_repair_for_test(f.org_id,(v_case->>'caseId')::uuid,8,gen_random_uuid(),
    'repair_functional_v1','Cleaned and reseated contact','work-t06');
  raise exception 'T06 accepted technician without completion permission';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_key:=gen_random_uuid();
 v_done:=public.complete_repair_for_test(f.org_id,(v_case->>'caseId')::uuid,8,v_key,
   'repair_functional_v1','Cleaned and reseated contact','work-t06');
 if v_done->>'stage'<>'test' or v_done->>'version'<>'9' then raise exception 'T06 failed'; end if;
 if public.complete_repair_for_test(f.org_id,(v_case->>'caseId')::uuid,8,v_key,
   'repair_functional_v1','Cleaned and reseated contact','work-t06')<>v_done then
  raise exception 'T06 retry not idempotent';
 end if;
 if (select count(*) from public.repair_completions where org_id=f.org_id
   and case_id=(v_case->>'caseId')::uuid)<>1 then raise exception 'Duplicate repair completion'; end if;
 begin
  perform public.transition_repair_case(f.org_id,(v_case->>'caseId')::uuid,9,'T08',gen_random_uuid());
  raise exception 'T08 accepted repair without a separate test';
 exception when check_violation then
  if sqlerrm<>'RETURN_QC_REQUIRED' then raise; end if;
 end;
end $$;

set local role authenticated;
do $$ begin
 begin
  insert into public.repair_completions(org_id,case_id,plan_id,device_id,repair_stage_entered_at,
   protocol_code,completed_by)
  values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),now(),
   'repair_functional_v1',gen_random_uuid());
  raise exception 'Direct repair completion write was accepted';
 exception when insufficient_privilege then null;
 end;
end $$;

rollback;
