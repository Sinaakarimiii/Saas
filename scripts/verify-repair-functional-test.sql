\set ON_ERROR_STOP on
begin;
create temp table functional_fixture as select gen_random_uuid() owner_id,gen_random_uuid() technician_id,
 gen_random_uuid() org_id,gen_random_uuid() owner_role_id,gen_random_uuid() technician_role_id;
insert into auth.users(id,aud,role,email)
select owner_id,'authenticated','authenticated','functional-owner@example.test' from functional_fixture
union all select technician_id,'authenticated','authenticated','functional-technician@example.test' from functional_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Functional test',owner_id from functional_fixture;
insert into public.roles(id,org_id,name,is_system)
select owner_role_id,org_id,'Functional owner',false from functional_fixture
union all select technician_role_id,org_id,'Functional technician',false from functional_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,owner_id,owner_role_id from functional_fixture
union all select org_id,technician_id,technician_role_id from functional_fixture;
insert into public.role_permissions(role_id,permission_key)
select owner_role_id,key from functional_fixture cross join public.permissions
where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
 or key in ('repair.plan.record','repair.complete','repair.test.record','repair.quality.release');
grant select on functional_fixture to authenticated;
create function pg_temp.add_functional_imei_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.add_functional_imei_evidence(text,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; v_case jsonb; v_diagnosis jsonb; v_plan jsonb; v_done jsonb;
 v_failed jsonb; v_passed jsonb; v_release jsonb; v_key uuid; v_evidence text; v_case_id uuid;
begin
 select * into f from functional_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_case:=public.create_repair_case(f.org_id,'GPS model','repair-test','Customer','No power',
  'normal','walk_in',gen_random_uuid());
 v_case_id:=(v_case->>'caseId')::uuid;
 v_evidence:=f.org_id::text||'/'||v_case_id::text||'/'||gen_random_uuid()::text||'.png';
 perform pg_temp.add_functional_imei_evidence(v_evidence,f.owner_id);
 perform public.receive_repair_device(f.org_id,v_case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567891',v_evidence);
 perform public.transition_repair_case(f.org_id,v_case_id,2,'T01',gen_random_uuid());
 v_diagnosis:=public.save_repair_diagnosis(f.org_id,v_case_id,3,gen_random_uuid(),
  'Power contact restored','needs_repair','repair','covered');
 perform public.finalize_repair_diagnosis(f.org_id,v_case_id,(v_diagnosis->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,v_case_id,5,'T02',gen_random_uuid());
 v_plan:=public.save_repair_action_plan(f.org_id,v_case_id,6,gen_random_uuid(),
  'repair','Restore power contact','warranty',0,'no_parts');
 perform public.transition_repair_case(f.org_id,v_case_id,7,'T03',gen_random_uuid());
 v_done:=public.complete_repair_for_test(f.org_id,v_case_id,8,gen_random_uuid(),
  'repair_functional_v1','Reseated power contact','work-functional');
 if v_done->>'stage'<>'test' then raise exception 'T06 did not enter test'; end if;
 begin
  perform public.record_repair_functional_test(f.org_id,v_case_id,9,gen_random_uuid(),
   'not_applicable','identity unavailable','pass','power on','pass','position lock','pass','settings retained');
  raise exception 'Mandatory identity accepted not-applicable';
 exception when check_violation then
  if sqlerrm<>'INVALID_FUNCTIONAL_TEST' then raise; end if;
 end;
 begin
  perform public.record_repair_functional_test(f.org_id,v_case_id,9,gen_random_uuid(),
   'pass','','pass','power on','pass','position lock','pass','settings retained');
  raise exception 'Missing evidence accepted';
 exception when check_violation then
  if sqlerrm<>'INVALID_FUNCTIONAL_TEST' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 begin
  perform public.record_repair_functional_test(f.org_id,v_case_id,9,gen_random_uuid(),
   'pass','label matched','pass','power on','pass','position lock','pass','settings retained');
  raise exception 'User without test permission recorded test';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_key:=gen_random_uuid();
 v_failed:=public.record_repair_functional_test(f.org_id,v_case_id,9,v_key,
  'pass','label matched','fail','power unstable','not_applicable','model has no positioning',
  'pass','settings retained');
 if v_failed->>'passed'<>'false' or v_failed->>'revision'<>'1' then raise exception 'Failed test not retained'; end if;
 if public.record_repair_functional_test(f.org_id,v_case_id,9,v_key,
  'pass','label matched','fail','power unstable','not_applicable','model has no positioning',
  'pass','settings retained')<>v_failed then raise exception 'Test retry was not idempotent'; end if;
 begin
  perform public.release_repair_functional_test(f.org_id,v_case_id,(v_failed->>'testId')::uuid,10,gen_random_uuid());
  raise exception 'Failed test was released';
 exception when check_violation then
  if sqlerrm<>'FUNCTIONAL_TEST_NOT_RELEASABLE' then raise; end if;
 end;
 v_passed:=public.record_repair_functional_test(f.org_id,v_case_id,10,gen_random_uuid(),
  'pass','label matched','pass','power stable','not_applicable','model has no positioning',
  'pass','settings retained');
 if v_passed->>'passed'<>'true' or v_passed->>'revision'<>'2' then raise exception 'Passing test incorrect'; end if;
 begin
  perform public.release_repair_functional_test(f.org_id,v_case_id,(v_failed->>'testId')::uuid,11,gen_random_uuid());
  raise exception 'Old failed test released';
 exception when check_violation then
  if sqlerrm<>'FUNCTIONAL_TEST_NOT_RELEASABLE' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.technician_id::text,true);
 begin
  perform public.release_repair_functional_test(f.org_id,v_case_id,(v_passed->>'testId')::uuid,11,gen_random_uuid());
  raise exception 'User without quality permission released test';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 v_key:=gen_random_uuid();
 v_release:=public.release_repair_functional_test(f.org_id,v_case_id,(v_passed->>'testId')::uuid,11,v_key);
 if v_release->>'version'<>'12' then raise exception 'Quality release failed'; end if;
 if public.release_repair_functional_test(f.org_id,v_case_id,(v_passed->>'testId')::uuid,11,v_key)<>v_release
  then raise exception 'Quality release retry was not idempotent'; end if;
 v_failed:=public.record_repair_functional_test(f.org_id,v_case_id,12,gen_random_uuid(),
  'pass','label matched','fail','intermittent power failure','not_applicable','model has no positioning',
  'pass','settings retained');
 begin
  perform public.release_repair_functional_test(f.org_id,v_case_id,(v_passed->>'testId')::uuid,13,gen_random_uuid());
  raise exception 'Older released test remained releasable after a newer failed test';
 exception when check_violation then
  if sqlerrm<>'FUNCTIONAL_TEST_NOT_RELEASABLE' then raise; end if;
 end;
 if (select count(*) from public.repair_functional_tests where org_id=f.org_id and case_id=v_case_id)<>3
  or (select count(*) from public.repair_functional_test_releases where org_id=f.org_id and case_id=v_case_id)<>1
  then raise exception 'Test or release history missing'; end if;
 begin
  perform public.transition_repair_case(f.org_id,v_case_id,13,'T08',gen_random_uuid());
  raise exception 'Return-only T08 accepted repair before financial/delivery guards';
 exception when check_violation then
  if sqlerrm<>'RETURN_QC_REQUIRED' then raise; end if;
 end;
 raise notice 'functional test revisions, evidence, permission, release and T08 guard passed';
end $$;
do $$ begin
 begin
  insert into public.repair_functional_tests(org_id,case_id,plan_id,completion_id,device_id,revision,
   custody_damage_epoch,identity_status,identity_evidence,power_status,power_evidence,
   position_status,position_evidence,configuration_status,configuration_evidence,recorded_by)
  values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1,
   0,'pass','x','pass','x','pass','x','pass','x',gen_random_uuid());
  raise exception 'Direct test write accepted';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
