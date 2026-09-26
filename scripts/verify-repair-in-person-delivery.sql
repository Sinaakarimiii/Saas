\set ON_ERROR_STOP on
begin;
create temp table delivery_fixture as select gen_random_uuid() owner_id,gen_random_uuid() org_id,gen_random_uuid() role_id;
insert into auth.users(id,aud,role,email) select owner_id,'authenticated','authenticated','repair-delivery@example.test' from delivery_fixture;
insert into public.organizations(id,name,created_by) select org_id,'Repair delivery test',owner_id from delivery_fixture;
insert into public.roles(id,org_id,name,is_system) select role_id,org_id,'Delivery tester',false from delivery_fixture;
insert into public.org_members(org_id,user_id,role_id) select org_id,owner_id,role_id from delivery_fixture;
insert into public.role_permissions(role_id,permission_key)
select role_id,key from delivery_fixture cross join public.permissions
where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
 or key in ('repair.plan.record','repair.complete','repair.test.record','repair.quality.release',
  'repair.outgoing_qc.record','custody.baseline.record','repair.delivery.receive','case.close',
  'repair.customer_approval.record','repair.payment.record','repair.payment.verify',
  'repair.payment.correct','custody.transfer.release');
grant select on delivery_fixture to authenticated;
create function pg_temp.delivery_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.delivery_evidence(text,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; d jsonb; t jsonb; q jsonb; step jsonb; receipt jsonb;
 case_id uuid; path text; test_device_id uuid; holder text; retry uuid;
begin
 select * into f from delivery_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','delivery-test','Customer','No power',
  'normal','walk_in',gen_random_uuid()); case_id:=(c->>'caseId')::uuid;
 path:=f.org_id||'/'||case_id||'/'||gen_random_uuid()||'.png';
 perform pg_temp.delivery_evidence(path,f.owner_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567894',path);
 select verified_device_id into test_device_id from public.repair_cases where id=case_id;
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 d:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Power contact fault','needs_repair','repair','covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(d->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 perform public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'repair','Reseat contact','warranty',0,'no_parts');
 perform public.transition_repair_case(f.org_id,case_id,7,'T03',gen_random_uuid());
 perform public.complete_repair_for_test(f.org_id,case_id,8,gen_random_uuid(),
  'repair_functional_v1','Reseated contact','work-delivery');
 t:=public.record_repair_functional_test(f.org_id,case_id,9,gen_random_uuid(),
  'pass','label','pass','stable','not_applicable','no positioning','pass','settings');
 perform public.release_repair_functional_test(f.org_id,case_id,(t->>'testId')::uuid,10,gen_random_uuid());
 q:=public.record_repair_outgoing_check(f.org_id,case_id,11,gen_random_uuid(),
  true,'label',true,'charger',true,'repaired',true,'packed','Colleague','colleague','written authority');
 perform public.release_repair_outgoing_check(f.org_id,case_id,(q->>'checkId')::uuid,12,gen_random_uuid());
 begin
  perform public.record_repaired_delivery_receipt(f.org_id,case_id,13,gen_random_uuid(),
   'Colleague','colleague','written authority','premature-receipt','signed note');
  raise exception 'Receipt before delivery was accepted';
 exception when check_violation then
  if sqlerrm<>'REPAIR_DELIVERY_STAGE_REQUIRED' then raise; end if;
 end;
 perform public.record_repair_device_custody_baseline(f.org_id,case_id,'Workshop',f.owner_id,'shelf record',13,gen_random_uuid());
 retry:=gen_random_uuid();
 step:=public.advance_repaired_case_to_delivery(f.org_id,case_id,14,retry);
 if public.advance_repaired_case_to_delivery(f.org_id,case_id,14,retry)<>step then raise exception 'T08 retry changed result'; end if;
 begin
  perform public.release_repair_device_custody(f.org_id,case_id,'Front desk',f.owner_id,'internal',
   'late-transfer','handover log',15,gen_random_uuid());
  raise exception 'Internal movement after repair T08 accepted';
 exception when check_violation then
  if sqlerrm<>'REPAIR_DELIVERY_TRANSFER_BLOCKED' then raise; end if;
 end;
 begin
  perform public.close_repaired_case(f.org_id,case_id,15,gen_random_uuid());
  raise exception 'Closure without receipt accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_RECEIPT_REQUIRED' then raise; end if;
 end;
 begin
  perform public.record_repaired_delivery_receipt(f.org_id,case_id,15,gen_random_uuid(),
   'Different person','colleague','written authority','wrong-person','signed note');
  raise exception 'Recipient mismatch accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_RECIPIENT_MISMATCH' then raise; end if;
 end;
 retry:=gen_random_uuid();
 receipt:=public.record_repaired_delivery_receipt(f.org_id,case_id,15,retry,
  'Colleague','colleague','written authority','actual-receipt','signed note');
 if public.record_repaired_delivery_receipt(f.org_id,case_id,15,retry,
  'Colleague','colleague','written authority','actual-receipt','signed note')<>receipt then raise exception 'Receipt retry changed result'; end if;
 select holder_kind into holder from public.repair_device_custody_positions where org_id=f.org_id and device_id=test_device_id;
 if holder<>'recipient' then raise exception 'Custody not transferred to recipient'; end if;
 perform public.close_repaired_case(f.org_id,case_id,16,gen_random_uuid());
 if not exists(select 1 from public.repair_cases where id=case_id and stage='closed') then raise exception 'Case did not close'; end if;
 raise notice 'Repair in-person delivery, receipt and close passed';
end $$;
do $$
declare f record; c jsonb; d jsonb; p jsonb; t jsonb; q jsonb; paid jsonb;
 case_id uuid; path text;
begin
 select * into f from delivery_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','paid-delivery-test','Customer','No signal',
  'normal','walk_in',gen_random_uuid()); case_id:=(c->>'caseId')::uuid;
 path:=f.org_id||'/'||case_id||'/'||gen_random_uuid()||'.png';
 perform pg_temp.delivery_evidence(path,f.owner_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567895',path);
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 d:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Signal fault','needs_repair','repair','not_covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(d->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 p:=public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'repair','Repair signal','customer_paid',100000,'no_parts');
 perform public.record_repair_plan_approval(f.org_id,case_id,(p->>'planId')::uuid,7,gen_random_uuid(),
  'customer','approved','phone','Customer','owner','call-paid',null,pg_catalog.clock_timestamp());
 perform public.transition_repair_case(f.org_id,case_id,8,'T03',gen_random_uuid());
 perform public.complete_repair_for_test(f.org_id,case_id,9,gen_random_uuid(),
  'repair_functional_v1','Fixed signal','work-paid');
 t:=public.record_repair_functional_test(f.org_id,case_id,10,gen_random_uuid(),
  'pass','label','pass','stable','pass','fix','pass','settings');
 perform public.release_repair_functional_test(f.org_id,case_id,(t->>'testId')::uuid,11,gen_random_uuid());
 q:=public.record_repair_outgoing_check(f.org_id,case_id,12,gen_random_uuid(),
  true,'label',true,'charger',true,'repaired',true,'packed','Customer','owner',null);
 perform public.release_repair_outgoing_check(f.org_id,case_id,(q->>'checkId')::uuid,13,gen_random_uuid());
 perform public.record_repair_device_custody_baseline(f.org_id,case_id,'Workshop',f.owner_id,'shelf record',14,gen_random_uuid());
 begin
  perform public.advance_repaired_case_to_delivery(f.org_id,case_id,15,gen_random_uuid());
  raise exception 'Unpaid repair advanced';
 exception when check_violation then
  if sqlerrm<>'REPAIR_PAYMENT_UNSETTLED' then raise; end if;
 end;
 paid:=public.record_repair_payment_evidence(f.org_id,case_id,15,gen_random_uuid(),
  40000,'card','paid-part-1','bank-1');
 perform public.verify_repair_payment_evidence(f.org_id,case_id,(paid->>'paymentId')::uuid,16,gen_random_uuid(),'match-1');
 begin
  perform public.advance_repaired_case_to_delivery(f.org_id,case_id,17,gen_random_uuid());
  raise exception 'Partially paid repair advanced';
 exception when check_violation then
  if sqlerrm<>'REPAIR_PAYMENT_UNSETTLED' then raise; end if;
 end;
 paid:=public.record_repair_payment_evidence(f.org_id,case_id,17,gen_random_uuid(),
  60000,'bank_transfer','paid-part-2','bank-2');
 perform public.verify_repair_payment_evidence(f.org_id,case_id,(paid->>'paymentId')::uuid,18,gen_random_uuid(),'match-2');
 perform public.correct_repair_payment_evidence(f.org_id,case_id,(paid->>'paymentId')::uuid,
  19,gen_random_uuid(),'not_received','Bank did not settle','paid-correction-2','bank-rejection');
 begin
  perform public.advance_repaired_case_to_delivery(f.org_id,case_id,20,gen_random_uuid());
  raise exception 'Corrected payment still released delivery';
 exception when check_violation then
  if sqlerrm<>'REPAIR_PAYMENT_UNSETTLED' then raise; end if;
 end;
 paid:=public.record_repair_payment_evidence(f.org_id,case_id,20,gen_random_uuid(),
  60000,'bank_transfer','paid-part-3','bank-3');
 perform public.verify_repair_payment_evidence(f.org_id,case_id,(paid->>'paymentId')::uuid,21,gen_random_uuid(),'match-3');
 perform public.advance_repaired_case_to_delivery(f.org_id,case_id,22,gen_random_uuid());
 raise notice 'Paid repair stayed blocked after correction until new verified settlement';
end $$;
rollback;
