\set ON_ERROR_STOP on
begin;
create temp table outgoing_fixture as select gen_random_uuid() owner_id,gen_random_uuid() other_id,
 gen_random_uuid() org_id,gen_random_uuid() owner_role_id,gen_random_uuid() other_role_id;
insert into auth.users(id,aud,role,email)
select owner_id,'authenticated','authenticated','outgoing-owner@example.test' from outgoing_fixture
union all select other_id,'authenticated','authenticated','outgoing-other@example.test' from outgoing_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Outgoing test',owner_id from outgoing_fixture;
insert into public.roles(id,org_id,name,is_system)
select owner_role_id,org_id,'Outgoing owner',false from outgoing_fixture
union all select other_role_id,org_id,'Outgoing other',false from outgoing_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,owner_id,owner_role_id from outgoing_fixture
union all select org_id,other_id,other_role_id from outgoing_fixture;
insert into public.role_permissions(role_id,permission_key)
select owner_role_id,key from outgoing_fixture cross join public.permissions
where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
 or key in ('repair.plan.record','repair.complete','repair.test.record',
  'repair.quality.release','repair.outgoing_qc.record');
grant select on outgoing_fixture to authenticated;
create function pg_temp.add_outgoing_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.add_outgoing_evidence(text,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; d jsonb; p jsonb; t jsonb; bad jsonb; good jsonb; release_result jsonb;
 case_id uuid; evidence_path text; retry_key uuid;
begin
 select * into f from outgoing_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','outgoing-test','Customer','No power',
  'normal','walk_in',gen_random_uuid());
 case_id:=(c->>'caseId')::uuid;
 evidence_path:=f.org_id::text||'/'||case_id::text||'/'||gen_random_uuid()::text||'.png';
 perform pg_temp.add_outgoing_evidence(evidence_path,f.owner_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567893',evidence_path);
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 d:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Power contact fault','needs_repair','repair','covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(d->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 p:=public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'repair','Reseat contact','warranty',0,'no_parts');
 perform public.transition_repair_case(f.org_id,case_id,7,'T03',gen_random_uuid());
 perform public.complete_repair_for_test(f.org_id,case_id,8,gen_random_uuid(),
  'repair_functional_v1','Reseated contact','work-outgoing');
 begin
  perform public.record_repair_outgoing_check(f.org_id,case_id,9,gen_random_uuid(),
   true,'label',true,'charger',true,'working',true,'packed','Customer','owner',null);
  raise exception 'Outgoing accepted before functional release';
 exception when check_violation then
  if sqlerrm<>'FUNCTIONAL_RELEASE_REQUIRED' then raise; end if;
 end;
 t:=public.record_repair_functional_test(f.org_id,case_id,9,gen_random_uuid(),
  'pass','label','pass','stable','not_applicable','no positioning','pass','settings');
 perform public.release_repair_functional_test(f.org_id,case_id,(t->>'testId')::uuid,10,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',f.other_id::text,true);
 begin
  perform public.record_repair_outgoing_check(f.org_id,case_id,11,gen_random_uuid(),
   true,'label',true,'charger',true,'working',true,'packed','Customer','owner',null);
  raise exception 'User without outgoing permission recorded check';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 bad:=public.record_repair_outgoing_check(f.org_id,case_id,11,gen_random_uuid(),
  true,'label',true,'charger',false,'screen crack',true,'packed','Customer','owner',null);
 begin
  perform public.release_repair_outgoing_check(f.org_id,case_id,(bad->>'checkId')::uuid,12,gen_random_uuid());
  raise exception 'Failed outgoing check released';
 exception when check_violation then
  if sqlerrm<>'REPAIR_OUTGOING_NOT_RELEASABLE' then raise; end if;
 end;
 retry_key:=gen_random_uuid();
 good:=public.record_repair_outgoing_check(f.org_id,case_id,12,retry_key,
  true,'label',true,'charger',true,'repaired condition',true,'packed','Colleague','colleague','written authority');
 if public.record_repair_outgoing_check(f.org_id,case_id,12,retry_key,
  true,'label',true,'charger',true,'repaired condition',true,'packed','Colleague','colleague','written authority')<>good
  then raise exception 'Outgoing record retry not idempotent'; end if;
 retry_key:=gen_random_uuid();
 release_result:=public.release_repair_outgoing_check(f.org_id,case_id,(good->>'checkId')::uuid,13,retry_key);
 if public.release_repair_outgoing_check(f.org_id,case_id,(good->>'checkId')::uuid,13,retry_key)<>release_result
  then raise exception 'Outgoing release retry not idempotent'; end if;
 begin
  perform public.transition_repair_case(f.org_id,case_id,14,'T08',gen_random_uuid());
  raise exception 'Repair T08 opened before delivery guards';
 exception when check_violation then
  if sqlerrm<>'RETURN_QC_REQUIRED' then raise; end if;
 end;
 perform public.record_repair_outgoing_check(f.org_id,case_id,14,gen_random_uuid(),
  false,'identity mismatch',true,'charger',true,'working',true,'packed','Customer','owner',null);
 begin
  perform public.release_repair_outgoing_check(f.org_id,case_id,(good->>'checkId')::uuid,15,gen_random_uuid());
  raise exception 'Older outgoing check released after new failed check';
 exception when check_violation then
  if sqlerrm<>'REPAIR_OUTGOING_NOT_RELEASABLE' then raise; end if;
 end;
 raise notice 'Repair outgoing control, independent release, revisions, permissions and T08 guard passed';
end $$;
do $$ begin
 begin
  insert into public.repair_outgoing_releases(org_id,case_id,check_id,released_by)
  values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
  raise exception 'Direct write accepted';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
