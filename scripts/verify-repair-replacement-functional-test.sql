\set ON_ERROR_STOP on
begin;
create temp table replacement_fixture as select gen_random_uuid() owner_id,gen_random_uuid() clerk_id,
 gen_random_uuid() org_id,gen_random_uuid() owner_role_id,gen_random_uuid() clerk_role_id;
insert into auth.users(id,aud,role,email)
select owner_id,'authenticated','authenticated','replacement-execution-owner@example.test' from replacement_fixture
union all select clerk_id,'authenticated','authenticated','replacement-execution-clerk@example.test' from replacement_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Replacement execution test',owner_id from replacement_fixture;
insert into public.roles(id,org_id,name,is_system)
select owner_role_id,org_id,'Replacement execution owner',false from replacement_fixture
union all select clerk_role_id,org_id,'Replacement execution clerk',false from replacement_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,owner_id,owner_role_id from replacement_fixture
union all select org_id,clerk_id,clerk_role_id from replacement_fixture;
insert into public.role_permissions(role_id,permission_key)
select owner_role_id,key from replacement_fixture cross join public.permissions
where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
 or key in ('repair.plan.record','repair.customer_approval.record','repair.replacement.approve',
  'replacement.stock.receive','replacement.stock.allocate','custody.baseline.record','repair.replacement.execute','repair.test.record','repair.quality.release');
grant select on replacement_fixture to authenticated;
create function pg_temp.replacement_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.replacement_evidence(text,uuid) to authenticated;
create function pg_temp.force_replacement_test(p_org_id uuid,p_case_id uuid)
returns void language sql security definer set search_path='' as $$
 update public.repair_cases set stage='test',stage_entered_at=pg_catalog.clock_timestamp()
 where org_id=p_org_id and id=p_case_id;
$$;
grant execute on function pg_temp.force_replacement_test(uuid,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; d jsonb; p jsonb; s jsonb; a jsonb; e jsonb;
 case_id uuid; path text; retry uuid; original_id uuid; failed jsonb; v_passed jsonb; released jsonb; test_key uuid;
begin
 select * into f from replacement_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','replacement-test','Customer','Irreparable',
  'normal','walk_in',gen_random_uuid()); case_id:=(c->>'caseId')::uuid;
 path:=f.org_id||'/'||case_id||'/'||gen_random_uuid()||'.png';
 perform pg_temp.replacement_evidence(path,f.owner_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567896',path);
 select verified_device_id into original_id from public.repair_cases where id=case_id;
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 d:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Main board irreparable','irreparable','replacement','covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(d->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 p:=public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'replacement','Equivalent replacement','warranty',0,null,'GPS new','irreparable','return_to_customer');
 perform public.record_repair_plan_approval(f.org_id,case_id,(p->>'planId')::uuid,7,gen_random_uuid(),
  'replacement','approved');
 perform public.record_repair_plan_approval(f.org_id,case_id,(p->>'planId')::uuid,8,gen_random_uuid(),
  'customer','approved','phone','Customer','owner','call-replacement',null,pg_catalog.clock_timestamp());
 perform public.transition_repair_case(f.org_id,case_id,9,'T04',gen_random_uuid());
 begin
  perform pg_temp.force_replacement_test(f.org_id,case_id);
  raise exception 'Direct T07 without execution accepted';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_EXECUTION_REQUIRED' then raise; end if;
 end;
 begin
  perform public.execute_repair_replacement_for_test(f.org_id,case_id,10,gen_random_uuid(),
   'execution-too-early','work-order');
  raise exception 'Execution without stock accepted';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_STOCK_UNAVAILABLE' then raise; end if;
 end;
 s:=public.receive_repair_replacement_stock(f.org_id,'900000000000012','GPS new','Stock shelf',
  f.owner_id,'stock-label-photo','stock-entry-execution',gen_random_uuid());
 a:=public.allocate_repair_replacement_device(f.org_id,case_id,(s->>'deviceId')::uuid,
  (p->>'planId')::uuid,'allocation-execution',10,gen_random_uuid());
 begin
  perform public.execute_repair_replacement_for_test(f.org_id,case_id,11,gen_random_uuid(),
   'execution-no-original-baseline','work-order');
  raise exception 'Execution without original custody accepted';
 exception when check_violation then
  if sqlerrm<>'DEVICE_CUSTODY_UNRESOLVED' then raise; end if;
 end;
 perform public.record_repair_device_custody_baseline(f.org_id,case_id,'Workshop',f.owner_id,
  'original-shelf-record',11,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.execute_repair_replacement_for_test(f.org_id,case_id,12,gen_random_uuid(),
   'execution-denied','work-order');
  raise exception 'Unauthorized execution accepted';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 retry:=gen_random_uuid();
 e:=public.execute_repair_replacement_for_test(f.org_id,case_id,12,retry,
  'execution-approved','signed-swap-order');
 if e->>'stage'<>'test' or e->>'version'<>'13' then raise exception 'T07 failed'; end if;
 if public.execute_repair_replacement_for_test(f.org_id,case_id,12,retry,
  'execution-approved','signed-swap-order')<>e then raise exception 'Execution retry changed result'; end if;
 if not exists(select 1 from public.repair_replacement_executions x where x.org_id=f.org_id
   and x.case_id=(c->>'caseId')::uuid and x.original_device_id=original_id
   and x.replacement_device_id=(s->>'deviceId')::uuid
   and x.original_disposition_pending='return_to_customer') then
  raise exception 'Serial swap record missing'; end if;
 if not exists(select 1 from public.repair_replacement_stock where org_id=f.org_id
   and device_id=(s->>'deviceId')::uuid and status='allocated' and allocated_case_id=(c->>'caseId')::uuid) then
  raise exception 'Stock allocation changed unexpectedly'; end if;
 begin
  perform public.execute_repair_replacement_for_test(f.org_id,case_id,13,gen_random_uuid(),
   'execution-repeat','other-order');
  raise exception 'Second execution accepted';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_STAGE_REQUIRED' then raise; end if;
 end;
 begin
  perform public.record_repair_functional_test(f.org_id,case_id,13,gen_random_uuid(),
   'pass','label','pass','boot','pass','location','pass','config');
  raise exception 'Original-device repair test accepted for replacement';
 exception when check_violation then
  if sqlerrm<>'REPAIR_COMPLETION_REQUIRED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.record_repair_replacement_functional_test(f.org_id,case_id,13,gen_random_uuid(),
   'pass','label','pass','boot','pass','location','pass','config');
  raise exception 'Unauthorized replacement test accepted';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 test_key:=gen_random_uuid();
 failed:=public.record_repair_replacement_functional_test(f.org_id,case_id,13,test_key,
  'pass','replacement IMEI matched','fail','no power','pass','location fix','pass','config loaded');
 if failed->>'passed'<>'false' or public.record_repair_replacement_functional_test(f.org_id,case_id,13,test_key,
  'pass','replacement IMEI matched','fail','no power','pass','location fix','pass','config loaded')<>failed then
  raise exception 'Failed replacement test or replay invalid'; end if;
 begin
  perform public.release_repair_functional_test(f.org_id,case_id,(failed->>'testId')::uuid,14,gen_random_uuid());
  raise exception 'Failed replacement test released';
 exception when check_violation then
  if sqlerrm<>'FUNCTIONAL_TEST_NOT_RELEASABLE' then raise; end if;
 end;
 v_passed:=public.record_repair_replacement_functional_test(f.org_id,case_id,14,gen_random_uuid(),
  'pass','replacement IMEI matched','pass','booted','pass','location fix','pass','config loaded');
 if v_passed->>'passed'<>'true' then raise exception 'Replacement test failed unexpectedly'; end if;
 begin
  perform public.release_repair_functional_test(f.org_id,case_id,(failed->>'testId')::uuid,15,gen_random_uuid());
  raise exception 'Stale replacement test released';
 exception when check_violation then
  if sqlerrm<>'FUNCTIONAL_TEST_NOT_RELEASABLE' then raise; end if;
 end;
 released:=public.release_repair_functional_test(f.org_id,case_id,(v_passed->>'testId')::uuid,15,gen_random_uuid());
 if released->>'version'<>'16' then raise exception 'Replacement quality release missing'; end if;
 if not exists(select 1 from public.repair_functional_tests t join public.repair_replacement_executions x
    on x.org_id=t.org_id and x.case_id=t.case_id and x.id=t.execution_id
    where t.id=(v_passed->>'testId')::uuid and t.device_id=x.replacement_device_id
     and t.completion_id is null and t.protocol_code='replacement_functional_v1') then
  raise exception 'Test not bound to executed replacement serial'; end if;
 if (select stage from public.repair_cases where id=case_id)<>'test' then
  raise exception 'Test release moved stage prematurely'; end if;
 raise notice 'Replacement functional test and independent quality release passed';
end $$;
reset role;
rollback;
