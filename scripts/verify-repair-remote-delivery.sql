\set ON_ERROR_STOP on
begin;
create temp table remote_fixture as select gen_random_uuid() actor_id,gen_random_uuid() org_id,gen_random_uuid() role_id;
insert into auth.users(id,aud,role,email) select actor_id,'authenticated','authenticated','repair-remote@example.test' from remote_fixture;
insert into public.organizations(id,name,created_by) select org_id,'Repair remote test',actor_id from remote_fixture;
insert into public.roles(id,org_id,name,is_system) select role_id,org_id,'Remote tester',false from remote_fixture;
insert into public.org_members(org_id,user_id,role_id) select org_id,actor_id,role_id from remote_fixture;
insert into public.role_permissions(role_id,permission_key)
 select role_id,key from remote_fixture cross join public.permissions
 where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
  or key in ('repair.plan.record','repair.complete','repair.test.record','repair.quality.release',
   'repair.outgoing_qc.record','custody.baseline.record','repair.delivery.receive','repair.delivery.dispatch',
   'repair.delivery.confirm_receipt','repair.delivery.return_receive',
   'delivery.incident.record','case.close');
grant select on remote_fixture to authenticated;
create function pg_temp.remote_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.remote_evidence(text,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; diagnosis jsonb; test_run jsonb; qc jsonb; dispatch jsonb; receipt jsonb;
 case_id uuid; test_device_id uuid; photo_path text; holder text; retry uuid;
begin
 select * into f from remote_fixture;
 perform set_config('request.jwt.claim.sub',f.actor_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','remote-test','Customer','No power',
  'normal','walk_in',gen_random_uuid()); case_id:=(c->>'caseId')::uuid;
 photo_path:=f.org_id||'/'||case_id||'/'||gen_random_uuid()||'.png';
 perform pg_temp.remote_evidence(photo_path,f.actor_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567896',photo_path);
 select verified_device_id into test_device_id from public.repair_cases where id=case_id;
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 diagnosis:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Power contact fault','needs_repair','repair','covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(diagnosis->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 perform public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'repair','Reseat contact','warranty',0,'no_parts');
 perform public.transition_repair_case(f.org_id,case_id,7,'T03',gen_random_uuid());
 perform public.complete_repair_for_test(f.org_id,case_id,8,gen_random_uuid(),
  'repair_functional_v1','Reseated contact','work-remote');
 test_run:=public.record_repair_functional_test(f.org_id,case_id,9,gen_random_uuid(),
  'pass','label','pass','stable','not_applicable','no positioning','pass','settings');
 perform public.release_repair_functional_test(f.org_id,case_id,(test_run->>'testId')::uuid,10,gen_random_uuid());
 qc:=public.record_repair_outgoing_check(f.org_id,case_id,11,gen_random_uuid(),
  true,'label',true,'charger',true,'repaired',true,'packed','Colleague','colleague','written authority');
 perform public.release_repair_outgoing_check(f.org_id,case_id,(qc->>'checkId')::uuid,12,gen_random_uuid());
 perform public.record_repair_device_custody_baseline(f.org_id,case_id,'Workshop',f.actor_id,'shelf record',13,gen_random_uuid());
 perform public.advance_repaired_case_to_delivery(f.org_id,case_id,14,gen_random_uuid());
 begin
  perform public.close_repaired_case(f.org_id,case_id,15,gen_random_uuid());
  raise exception 'Closure before shipment accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_RECEIPT_REQUIRED' then raise; end if;
 end;
 retry:=gen_random_uuid();
 dispatch:=public.record_repaired_delivery_dispatch(f.org_id,case_id,15,retry,
  'courier','Courier','Tehran','tracking-remote','dispatch-remote','carrier signature');
 if public.record_repaired_delivery_dispatch(f.org_id,case_id,15,retry,
  'courier','Courier','Tehran','tracking-remote','dispatch-remote','carrier signature')<>dispatch then
  raise exception 'Dispatch retry changed result'; end if;
 select holder_kind into holder from public.repair_device_custody_positions where org_id=f.org_id and device_id=test_device_id;
 if holder<>'carrier' then raise exception 'Carrier custody not recorded'; end if;
 begin
  perform public.record_repaired_delivery_receipt(f.org_id,case_id,16,gen_random_uuid(),
   'Colleague','colleague','written authority','direct-after-dispatch','signed note');
  raise exception 'Direct handover after dispatch accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_CUSTODIAN_REQUIRED' and sqlerrm<>'DELIVERY_ALREADY_DISPATCHED' then raise; end if;
 end;
 begin
  perform public.close_repaired_case(f.org_id,case_id,16,gen_random_uuid());
  raise exception 'Closure before destination receipt accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_RECEIPT_REQUIRED' then raise; end if;
 end;
 begin
  perform public.confirm_repaired_delivery_receipt(f.org_id,case_id,(dispatch->>'dispatchId')::uuid,16,gen_random_uuid(),
   'Different person','colleague','written authority','wrong-person','signed note');
  raise exception 'Wrong recipient accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_DISPATCH_MISMATCH' then raise; end if;
 end;
 begin
  perform public.confirm_repaired_delivery_receipt(f.org_id,case_id,(dispatch->>'dispatchId')::uuid,16,gen_random_uuid(),
   'Colleague','colleague','written authority','dispatch-remote','signed note');
  raise exception 'Duplicate dispatch reference accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_INDEPENDENT_RECEIPT_REQUIRED' then raise; end if;
 end;
 retry:=gen_random_uuid();
 receipt:=public.confirm_repaired_delivery_receipt(f.org_id,case_id,(dispatch->>'dispatchId')::uuid,16,retry,
  'Colleague','colleague','written authority','receipt-remote','recipient signature');
 if public.confirm_repaired_delivery_receipt(f.org_id,case_id,(dispatch->>'dispatchId')::uuid,16,retry,
  'Colleague','colleague','written authority','receipt-remote','recipient signature')<>receipt then
  raise exception 'Receipt retry changed result'; end if;
 select holder_kind into holder from public.repair_device_custody_positions where org_id=f.org_id and device_id=test_device_id;
 if holder<>'recipient' then raise exception 'Recipient custody not recorded'; end if;
 perform public.close_repaired_case(f.org_id,case_id,17,gen_random_uuid());
 if not exists(select 1 from public.repair_cases where id=case_id and stage='closed') then
  raise exception 'Remote case did not close'; end if;
 raise notice 'Repaired remote delivery, receipt, custody, idempotency and close passed';
end $$;
do $$
#variable_conflict use_variable
declare f record; c jsonb; diagnosis jsonb; test_run jsonb; qc jsonb;
 dispatch jsonb; incident jsonb; damage_return jsonb; new_dispatch jsonb;
 case_id uuid; photo_path text; v integer; epoch integer; holder text;
begin
 select * into f from remote_fixture;
 perform set_config('request.jwt.claim.sub',f.actor_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','damage-loop','Customer','No signal',
  'normal','walk_in',gen_random_uuid()); case_id:=(c->>'caseId')::uuid;
 photo_path:=f.org_id||'/'||case_id||'/'||gen_random_uuid()||'.png';
 perform pg_temp.remote_evidence(photo_path,f.actor_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567897',photo_path);
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 diagnosis:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Signal fault','needs_repair','repair','covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(diagnosis->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 perform public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'repair','Reseat contact','warranty',0,'no_parts');
 perform public.transition_repair_case(f.org_id,case_id,7,'T03',gen_random_uuid());
 perform public.complete_repair_for_test(f.org_id,case_id,8,gen_random_uuid(),
  'repair_functional_v1','Reseated contact','work-damage');
 test_run:=public.record_repair_functional_test(f.org_id,case_id,9,gen_random_uuid(),
  'pass','label','pass','stable','not_applicable','no positioning','pass','settings');
 perform public.release_repair_functional_test(f.org_id,case_id,(test_run->>'testId')::uuid,10,gen_random_uuid());
 qc:=public.record_repair_outgoing_check(f.org_id,case_id,11,gen_random_uuid(),
  true,'label',true,'charger',true,'repaired',true,'packed','Customer','owner',null);
 perform public.release_repair_outgoing_check(f.org_id,case_id,(qc->>'checkId')::uuid,12,gen_random_uuid());
 perform public.record_repair_device_custody_baseline(f.org_id,case_id,'Workshop',f.actor_id,'shelf record',13,gen_random_uuid());
 perform public.advance_repaired_case_to_delivery(f.org_id,case_id,14,gen_random_uuid());
 dispatch:=public.record_repaired_delivery_dispatch(f.org_id,case_id,15,gen_random_uuid(),
  'post','Postal service','Tehran','damage-track-1','damage-dispatch-1','carrier signature');
 incident:=public.record_repair_delivery_incident(f.org_id,case_id,(dispatch->>'dispatchId')::uuid,
  'damage','damage-report-1','carrier report',f.actor_id,pg_catalog.clock_timestamp()+interval '1 day',16,gen_random_uuid());
 begin
  perform public.confirm_repaired_delivery_receipt(f.org_id,case_id,(dispatch->>'dispatchId')::uuid,17,gen_random_uuid(),
   'Customer','owner',null,'damage-receipt','recipient signature');
  raise exception 'Destination receipt while incident open accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_INCIDENT_OPEN' then raise; end if;
 end;
 begin
  perform public.return_repair_case_to_test_after_damage(f.org_id,case_id,17,gen_random_uuid());
  raise exception 'T11 before physical return accepted';
 exception when check_violation then
  if sqlerrm<>'CUSTODY_DAMAGE_RETURN_REQUIRED' then raise; end if;
 end;
 damage_return:=public.receive_repair_delivery_damage_return(f.org_id,case_id,(dispatch->>'dispatchId')::uuid,
  (incident->>'incidentId')::uuid,17,1,gen_random_uuid(),
  'Workshop','Damaged package','damage-return-1','physical return photo');
 select holder_kind into holder from public.repair_device_custody_positions p
  join public.repair_cases c on c.org_id=p.org_id and c.verified_device_id=p.device_id
  where c.id=case_id;
 if holder<>'staff' then raise exception 'Returned device is not with staff'; end if;
 select version,custody_damage_epoch into v,epoch from public.repair_cases where id=case_id;
 if epoch<>1 then raise exception 'Damage epoch was not advanced'; end if;
 perform public.return_repair_case_to_test_after_damage(f.org_id,case_id,v,gen_random_uuid());
 select version into v from public.repair_cases where id=case_id;
 begin
  perform public.advance_repaired_case_to_delivery(f.org_id,case_id,v,gen_random_uuid());
  raise exception 'T08 without fresh test accepted';
 exception when check_violation then
  if sqlerrm<>'REPAIR_OUTGOING_RELEASE_REQUIRED' then raise; end if;
 end;
 test_run:=public.record_repair_functional_test(f.org_id,case_id,v,gen_random_uuid(),
  'pass','label again','pass','stable again','not_applicable','not relevant','pass','settings again');
 select version into v from public.repair_cases where id=case_id;
 perform public.release_repair_functional_test(f.org_id,case_id,(test_run->>'testId')::uuid,v,gen_random_uuid());
 select version into v from public.repair_cases where id=case_id;
 qc:=public.record_repair_outgoing_check(f.org_id,case_id,v,gen_random_uuid(),
  true,'label again',true,'charger again',true,'repaired again',true,'repacked','Customer','owner',null);
 select version into v from public.repair_cases where id=case_id;
 perform public.release_repair_outgoing_check(f.org_id,case_id,(qc->>'checkId')::uuid,v,gen_random_uuid());
 select version into v from public.repair_cases where id=case_id;
 perform public.advance_repaired_case_to_delivery(f.org_id,case_id,v,gen_random_uuid());
 select version into v from public.repair_cases where id=case_id;
 new_dispatch:=public.record_repaired_delivery_dispatch(f.org_id,case_id,v,gen_random_uuid(),
  'post','Postal service','Tehran','damage-track-2','damage-dispatch-2','new carrier signature');
 if new_dispatch->>'dispatchId'=dispatch->>'dispatchId' then raise exception 'New shipment reused old attempt'; end if;
 select version into v from public.repair_cases where id=case_id;
 perform public.confirm_repaired_delivery_receipt(f.org_id,case_id,(new_dispatch->>'dispatchId')::uuid,v,gen_random_uuid(),
  'Customer','owner',null,'damage-receipt-2','new recipient signature');
 select version into v from public.repair_cases where id=case_id;
 perform public.close_repaired_case(f.org_id,case_id,v,gen_random_uuid());
 raise notice 'Damaged repaired shipment, physical return, T11, fresh QC and second shipment passed';
end $$;
rollback;
