\set ON_ERROR_STOP on
begin;
create temp table warehouse_policy as select :'warehouse_proposal'::text proposal, :'warehouse_outcome'::text outcome;
grant select on warehouse_policy to authenticated;
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
  'replacement.stock.receive','replacement.stock.allocate','custody.baseline.record','repair.replacement.execute','repair.test.record','repair.quality.release','repair.replacement.outgoing_qc.record','repair.delivery.receive','repair.replacement.original_return','case.close','custody.transfer.release','custody.transfer.accept','repair.replacement.warehouse_receive');
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
create function pg_temp.force_replacement_delivery(p_org_id uuid,p_case_id uuid)
returns void language sql security definer set search_path='' as $$
 update public.repair_cases set stage='delivery',stage_entered_at=pg_catalog.clock_timestamp()
 where org_id=p_org_id and id=p_case_id;
$$;
grant execute on function pg_temp.force_replacement_delivery(uuid,uuid) to authenticated;
create function pg_temp.set_replacement_plan_amount(p_org_id uuid,p_plan_id uuid,p_basis text,p_amount bigint)
returns void language sql security definer set search_path='' as $$
 update public.repair_action_plans set financial_basis=p_basis,amount_irr=p_amount
 where org_id=p_org_id and id=p_plan_id;
$$;
grant execute on function pg_temp.set_replacement_plan_amount(uuid,uuid,text,bigint) to authenticated;
create function pg_temp.close_replacement(p_org_id uuid,p_case_id uuid)
returns void language sql security definer set search_path='' as $$
 update public.repair_cases set stage='closed',closed_at=pg_catalog.clock_timestamp() where org_id=p_org_id and id=p_case_id;
$$;
grant execute on function pg_temp.close_replacement(uuid,uuid) to authenticated;
create function pg_temp.reallocate_issued(p_org_id uuid,p_device_id uuid)
returns void language sql security definer set search_path='' as $$
 update public.repair_replacement_stock set status='allocated',issued_receipt_id=null,issued_at=null where org_id=p_org_id and device_id=p_device_id;
$$;
grant execute on function pg_temp.reallocate_issued(uuid,uuid) to authenticated;
create function pg_temp.allow_clerk_delivery(p_role_id uuid)
returns void language sql security definer set search_path='' as $$
 insert into public.role_permissions(role_id,permission_key) values(p_role_id,'repair.delivery.receive');
$$;
grant execute on function pg_temp.allow_clerk_delivery(uuid) to authenticated;
-- Intake uses transaction time; advance the fixture timestamp to model a later request.
create function pg_temp.later_intake_time(p_case_id uuid)
returns void language sql security definer set search_path='' as $$
 update public.repair_cases set received_at=clock_timestamp() where id=p_case_id;
$$;
grant execute on function pg_temp.later_intake_time(uuid) to authenticated;
create function pg_temp.original_disposition(p_org_id uuid,p_case_id uuid,p_disposition text)
returns void language plpgsql security definer set search_path='' as $$
begin
 update public.repair_action_plans set original_disposition=p_disposition where org_id=p_org_id and case_id=p_case_id;
 update public.repair_replacement_executions set original_disposition_pending=p_disposition where org_id=p_org_id and case_id=p_case_id;
end; $$;
grant execute on function pg_temp.original_disposition(uuid,uuid,text) to authenticated;
create function pg_temp.allow_clerk_original_return(p_role_id uuid)
returns void language sql security definer set search_path='' as $$
 insert into public.role_permissions(role_id,permission_key) values(p_role_id,'repair.replacement.original_return');
$$;
grant execute on function pg_temp.allow_clerk_original_return(uuid) to authenticated;
create function pg_temp.clerk_warehouse_permissions(p_role_id uuid)
returns void language sql security definer set search_path='' as $$
 insert into public.role_permissions(role_id,permission_key) values(p_role_id,'custody.transfer.accept'),(p_role_id,'repair.replacement.warehouse_receive'),(p_role_id,'repair.case.view'),(p_role_id,'custody.transfer.release');
$$;
grant execute on function pg_temp.clerk_warehouse_permissions(uuid) to authenticated;
create function pg_temp.move_original(p_org_id uuid,p_device_id uuid,p_location text)
returns void language sql security definer set search_path='' as $$
 update public.repair_device_custody_positions set location=p_location where org_id=p_org_id and device_id=p_device_id;
$$;
grant execute on function pg_temp.move_original(uuid,uuid,text) to authenticated;
set local role authenticated;
do $$
declare f record; policy record; c jsonb; d jsonb; p jsonb; s jsonb; a jsonb; e jsonb;
 case_id uuid; path text; retry uuid; original_id uuid; failed jsonb; v_passed jsonb; released jsonb; bad_check jsonb; good_check jsonb; moved jsonb; test_key uuid;
begin
 select * into f from replacement_fixture;
 select * into policy from warehouse_policy;
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
 begin
  perform pg_temp.force_replacement_delivery(f.org_id,case_id);
  raise exception 'Direct T08 without outgoing QC accepted';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_OUTGOING_RELEASE_REQUIRED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.record_replacement_outgoing_check(f.org_id,case_id,16,gen_random_uuid(),
   true,'IMEI',true,'charger',true,'intact',true,'packed','Customer','owner',null);
  raise exception 'Unauthorized replacement outgoing accepted';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 bad_check:=public.record_replacement_outgoing_check(f.org_id,case_id,16,gen_random_uuid(),
  true,'replacement IMEI',true,'charger',false,'screen damaged',true,'packed','Customer','owner',null);
 begin
  perform public.release_repair_outgoing_check(f.org_id,case_id,(bad_check->>'checkId')::uuid,17,gen_random_uuid());
  raise exception 'Failed replacement QC released';
 exception when check_violation then
  if sqlerrm<>'REPAIR_OUTGOING_NOT_RELEASABLE' then raise; end if;
 end;
 good_check:=public.record_replacement_outgoing_check(f.org_id,case_id,17,gen_random_uuid(),
  true,'replacement IMEI',true,'charger',true,'new device intact',true,'packed',
  'Colleague','colleague','signed authorization');
 perform public.release_repair_outgoing_check(f.org_id,case_id,(good_check->>'checkId')::uuid,18,gen_random_uuid());
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'customer_paid',100);
 begin
  perform public.advance_replacement_case_to_delivery(f.org_id,case_id,19,gen_random_uuid());
  raise exception 'Unsettled replacement advanced to delivery';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_PAYMENT_UNSETTLED' then raise; end if;
 end;
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'warranty',0);
 test_key:=gen_random_uuid();
 moved:=public.advance_replacement_case_to_delivery(f.org_id,case_id,19,test_key);
 if moved->>'stage'<>'delivery' or moved->>'version'<>'20' then raise exception 'Replacement T08 failed'; end if;
 if public.advance_replacement_case_to_delivery(f.org_id,case_id,19,test_key)<>moved then
  raise exception 'Replacement T08 retry changed result'; end if;
 if not exists(select 1 from public.repair_case_events e where e.org_id=f.org_id and e.case_id=(c->>'caseId')::uuid
  and e.details->>'transitionCode'='T08' and e.details->>'replacementOutgoingCheckId'=good_check->>'checkId') then
  raise exception 'Replacement T08 evidence missing'; end if;

 begin
  perform public.advance_replacement_case_to_delivery(f.org_id,case_id,20,gen_random_uuid());
  raise exception 'T08 repeated after delivery';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_DELIVERY_STAGE_REQUIRED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.record_replacement_delivery_receipt(f.org_id,case_id,20,gen_random_uuid(),
   'Colleague','colleague','signed authorization','handover-1','signed receipt');
  raise exception 'Unauthorized replacement handover accepted';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform pg_temp.allow_clerk_delivery(f.clerk_role_id);
 begin
  perform public.record_replacement_delivery_receipt(f.org_id,case_id,20,gen_random_uuid(),
   'Colleague','colleague','signed authorization','handover-1','signed receipt');
  raise exception 'Non-custodian handover accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_CUSTODIAN_REQUIRED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  perform public.record_replacement_delivery_receipt(f.org_id,case_id,19,gen_random_uuid(),
   'Colleague','colleague','signed authorization','handover-1','signed receipt');
  raise exception 'Stale handover accepted';
 exception when raise_exception then
  if sqlerrm<>'CASE_VERSION_CONFLICT' then raise; end if;
 end;
 begin
  perform public.record_replacement_delivery_receipt(f.org_id,case_id,20,gen_random_uuid(),
   'Other person','colleague','signed authorization','handover-1','signed receipt');
  raise exception 'Wrong recipient accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_RECIPIENT_MISMATCH' then raise; end if;
 end;
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'customer_paid',100);
 begin
  perform public.record_replacement_delivery_receipt(f.org_id,case_id,20,gen_random_uuid(),
   'Colleague','colleague','signed authorization','handover-1','signed receipt');
  raise exception 'Unsettled replacement handover accepted';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_PAYMENT_UNSETTLED' then raise; end if;
 end;
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'warranty',0);
 test_key:=gen_random_uuid();
 moved:=public.record_replacement_delivery_receipt(f.org_id,case_id,20,test_key,
   'Colleague','colleague','signed authorization','handover-1','signed receipt');
 if moved->>'version'<>'21' or public.record_replacement_delivery_receipt(f.org_id,case_id,20,test_key,
   'Colleague','colleague','signed authorization','handover-1','signed receipt')<>moved then
  raise exception 'Handover retry invalid'; end if;
 begin
  perform public.record_replacement_delivery_receipt(f.org_id,case_id,20,test_key,
   'Colleague','colleague','signed authorization','changed-receipt','signed receipt');
  raise exception 'Changed retry accepted';
 exception when unique_violation then
  if sqlerrm<>'IDEMPOTENCY_KEY_REUSED' then raise; end if;
 end;
 if not exists(select 1 from public.repair_delivery_receipts r join public.repair_replacement_stock s
  on s.org_id=r.org_id and s.device_id=r.device_id and s.issued_receipt_id=r.id
  where r.id=(moved->>'receiptId')::uuid and r.device_id<>original_id and s.status='issued'
   and s.issued_at=r.received_at and r.repair_outgoing_check_id=(good_check->>'checkId')::uuid) then
  raise exception 'Receipt not atomically bound to issued replacement'; end if;
 if not exists(select 1 from public.repair_device_custody_positions where org_id=f.org_id
  and device_id=(s->>'deviceId')::uuid and holder_kind='recipient' and custodian_user_id is null) then
  raise exception 'Replacement custody not handed over'; end if;
 if not exists(select 1 from public.repair_device_custody_positions pos join public.repair_cases rc
  on rc.org_id=pos.org_id and rc.id=pos.case_id and rc.verified_device_id=pos.device_id
  where rc.id=(c->>'caseId')::uuid and pos.device_id=original_id and pos.holder_kind='staff'
   and rc.device_location=pos.location and rc.device_custodian=pos.custodian_label and rc.stage='delivery') then
  raise exception 'Original identity/custody metadata changed'; end if;
 begin
  perform pg_temp.reallocate_issued(f.org_id,(s->>'deviceId')::uuid);
  raise exception 'Issued device reallocated';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_STOCK_ALREADY_ISSUED' then raise; end if;
 end;
 begin
  perform pg_temp.close_replacement(f.org_id,case_id);
  raise exception 'Replacement closed without original disposition';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' then raise; end if;
 end;

 perform pg_temp.original_disposition(f.org_id,case_id,policy.proposal);
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.record_replacement_warehouse_receipt(f.org_id,case_id,gen_random_uuid(),21,gen_random_uuid(),'broken unit');
  raise exception 'Unauthorized warehouse result accepted';
 exception when insufficient_privilege then if sqlerrm<>'PERMISSION_DENIED' then raise; end if; end;
 perform pg_temp.clerk_warehouse_permissions(f.clerk_role_id);
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 moved:=public.release_repair_device_custody(f.org_id,case_id,'Warehouse',f.clerk_id,'internal carrier','warehouse-release','release evidence',21,gen_random_uuid());
 begin
  perform public.record_replacement_warehouse_receipt(f.org_id,case_id,(moved->>'transferId')::uuid,22,gen_random_uuid(),'broken unit');
  raise exception 'In-transit warehouse result accepted';
 exception when check_violation then if sqlerrm<>'DELIVERY_BLOCKERS_OPEN' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 perform public.resolve_repair_device_custody(f.org_id,case_id,(moved->>'transferId')::uuid,'accepted','warehouse-receipt','signed warehouse receipt',22,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  perform public.record_replacement_warehouse_receipt(f.org_id,case_id,(moved->>'transferId')::uuid,23,gen_random_uuid(),'broken unit');
  raise exception 'Non-recipient warehouse result accepted';
 exception when check_violation then if sqlerrm<>'WAREHOUSE_ACCEPTED_TRANSFER_REQUIRED' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.record_replacement_warehouse_receipt(f.org_id,case_id,gen_random_uuid(),23,gen_random_uuid(),'broken unit');
  raise exception 'Unrelated transfer accepted';
 exception when check_violation then if sqlerrm<>'WAREHOUSE_ACCEPTED_TRANSFER_REQUIRED' then raise; end if; end;
 begin
  perform public.record_replacement_warehouse_receipt(f.org_id,case_id,(moved->>'transferId')::uuid,22,gen_random_uuid(),'broken unit');
  raise exception 'Stale version accepted';
 exception when raise_exception then if sqlerrm<>'CASE_VERSION_CONFLICT' then raise; end if; end;
 test_key:=gen_random_uuid();
 a:=public.record_replacement_warehouse_receipt(f.org_id,case_id,(moved->>'transferId')::uuid,23,test_key,'broken unit with charger');
 if a->>'version'<>'24' or public.record_replacement_warehouse_receipt(f.org_id,case_id,(moved->>'transferId')::uuid,23,test_key,'broken unit with charger')<>a then
  raise exception 'Warehouse receipt replay invalid'; end if;
 begin
  perform public.record_replacement_warehouse_receipt(f.org_id,case_id,(moved->>'transferId')::uuid,23,test_key,'changed condition');
  raise exception 'Changed warehouse replay accepted';
 exception when unique_violation then if sqlerrm<>'IDEMPOTENCY_KEY_REUSED' then raise; end if; end;
 if not exists(select 1 from public.repair_replacement_warehouse_receipts w where w.org_id=f.org_id
  and w.case_id=(c->>'caseId')::uuid and w.original_device_id=original_id and w.received_by=f.clerk_id
  and w.disposition=policy.outcome and w.receipt_reference='warehouse-receipt' and w.transfer_id=(moved->>'transferId')::uuid) then
  raise exception 'Warehouse serial, recipient or evidence mismatch'; end if;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 perform pg_temp.move_original(f.org_id,original_id,'Other location');
 begin
  perform public.close_replacement_case(f.org_id,case_id,24,gen_random_uuid());
  raise exception 'Changed warehouse custody allowed closure';
 exception when check_violation then if sqlerrm<>'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' then raise; end if; end;
 perform pg_temp.move_original(f.org_id,original_id,'Warehouse');
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'customer_paid',100);
 begin
  perform public.close_replacement_case(f.org_id,case_id,24,gen_random_uuid());
  raise exception 'Unsettled warehouse closure accepted';
 exception when check_violation then if sqlerrm<>'REPLACEMENT_PAYMENT_UNSETTLED' then raise; end if; end;
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'warranty',0);
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.record_replacement_warehouse_receipt(f.org_id,case_id,(moved->>'transferId')::uuid,24,gen_random_uuid(),'overwrite');
  raise exception 'Same transfer receipt overwritten';
 exception when check_violation then if sqlerrm<>'WAREHOUSE_RECEIPT_ALREADY_CURRENT' then raise; end if; end;
 moved:=public.release_repair_device_custody(f.org_id,case_id,'Final warehouse',f.owner_id,'internal carrier','second-release','second release evidence',24,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 perform public.resolve_repair_device_custody(f.org_id,case_id,(moved->>'transferId')::uuid,'accepted','second-warehouse-receipt','second receipt evidence',25,gen_random_uuid());
 begin
  perform public.close_replacement_case(f.org_id,case_id,26,gen_random_uuid());
  raise exception 'Old warehouse receipt remained valid after transfer';
 exception when check_violation then if sqlerrm<>'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' then raise; end if; end;
 a:=public.record_replacement_warehouse_receipt(f.org_id,case_id,(moved->>'transferId')::uuid,26,gen_random_uuid(),'broken unit with charger');
 if a->>'version'<>'27' or not exists(select 1 from public.repair_case_events ev where ev.org_id=f.org_id
  and ev.case_id=(c->>'caseId')::uuid and ev.details->'previousReceipt'->>'receipt_reference'='warehouse-receipt'
  and ev.details->'currentReceipt'->>'receipt_reference'='second-warehouse-receipt') then
  raise exception 'New warehouse receipt audit missing'; end if;
 test_key:=gen_random_uuid();
 a:=public.close_replacement_case(f.org_id,case_id,27,test_key);
 if a->>'stage'<>'closed' or a->>'version'<>'28' or public.close_replacement_case(f.org_id,case_id,27,test_key)<>a then
  raise exception 'Warehouse closure replay invalid'; end if;
 if not exists(select 1 from public.repair_case_events ev where ev.org_id=f.org_id and ev.case_id=(c->>'caseId')::uuid
  and ev.details->>'outcome'='replaced_original_'||policy.outcome and ev.details->>'warehouseReceiptId' is not null
  and ev.details->>'originalReturnId' is null) then raise exception 'Warehouse final outcome missing'; end if;
 raise notice '%: accepted warehouse transfer, permission, recipient, replay and guarded closure passed',policy.outcome;
end $$;
reset role;
rollback;
