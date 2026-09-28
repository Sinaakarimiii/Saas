\set ON_ERROR_STOP on
begin;
create temp table shipment_policy as select :'shipment_method'::text method, :'damage_loop'::boolean damage_loop;
grant select on shipment_policy to authenticated;
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
  'replacement.stock.receive','replacement.stock.allocate','custody.baseline.record','repair.replacement.execute','repair.test.record','repair.quality.release','repair.replacement.outgoing_qc.record','repair.delivery.receive','case.close','repair.replacement.original_return','repair.delivery.dispatch','repair.delivery.confirm_receipt','delivery.incident.record','delivery.incident.resolve','repair.delivery.return_receive');
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
create function pg_temp.allow_clerk_remote(p_role_id uuid) returns void language sql security definer set search_path='' as $$
 insert into public.role_permissions(role_id,permission_key) values(p_role_id,'repair.delivery.confirm_receipt');
$$;
grant execute on function pg_temp.allow_clerk_remote(uuid) to authenticated;
create function pg_temp.allow_clerk_dispatch(p_role_id uuid) returns void language sql security definer set search_path='' as $$
 insert into public.role_permissions(role_id,permission_key) values(p_role_id,'repair.delivery.dispatch');
$$;
grant execute on function pg_temp.allow_clerk_dispatch(uuid) to authenticated;
create function pg_temp.wrong_replacement_dispatch(p_org uuid,p_case uuid,p_device uuid,p_check uuid,p_actor uuid)
returns void language sql security definer set search_path='' as $$
 insert into public.repair_delivery_dispatches(org_id,case_id,device_id,repair_outgoing_check_id,method,
  carrier,destination_name,destination_role,authority_reference,destination_address,tracking_code,
  dispatch_reference,dispatch_evidence,dispatched_by)
 values(p_org,p_case,p_device,p_check,'post','Carrier','Colleague','colleague','signed authorization',
  'Customer address','bad-tracking','bad-dispatch','bad-evidence',p_actor);
$$;
grant execute on function pg_temp.wrong_replacement_dispatch(uuid,uuid,uuid,uuid,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; d jsonb; p jsonb; s jsonb; a jsonb; e jsonb;
 policy record; v_version integer:=20; shipped jsonb; incident jsonb; returned jsonb; receipt jsonb;
 case_id uuid; path text; retry uuid; original_id uuid; failed jsonb; v_passed jsonb; released jsonb; bad_check jsonb; good_check jsonb; moved jsonb; test_key uuid;
begin
 select * into f from replacement_fixture;
 select * into policy from shipment_policy;
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
  perform public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version,gen_random_uuid(),
   policy.method,'Carrier','Customer address','tracking-1','dispatch-1','carrier-signature');
  raise exception 'Unauthorized dispatch accepted';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform pg_temp.allow_clerk_dispatch(f.clerk_role_id);
 begin
  perform public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version,gen_random_uuid(),
   policy.method,'Carrier','Customer address','tracking-1','dispatch-1','carrier-signature');
  raise exception 'Authorized non-custodian dispatched replacement';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_CUSTODIAN_REQUIRED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  perform public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version-1,gen_random_uuid(),
   policy.method,'Carrier','Customer address','tracking-1','dispatch-1','carrier-signature');
  raise exception 'Stale dispatch accepted';
 exception when raise_exception then
  if sqlerrm<>'CASE_VERSION_CONFLICT' then raise; end if;
 end;
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'customer_paid',100);
 begin
  perform public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version,gen_random_uuid(),
   policy.method,'Carrier','Customer address','tracking-1','dispatch-1','carrier-signature');
  raise exception 'Unsettled dispatch accepted';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_PAYMENT_UNSETTLED' then raise; end if;
 end;
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'warranty',0);
 begin
  perform pg_temp.wrong_replacement_dispatch(f.org_id,case_id,original_id,(good_check->>'checkId')::uuid,f.owner_id);
  raise exception 'Administrative insert shipped original as replacement';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_DISPATCH_MISMATCH' then raise; end if;
 end;
 retry:=gen_random_uuid();
 shipped:=public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version,retry,
  policy.method,'Carrier','Customer address','tracking-1','dispatch-1','carrier-signature');
 if public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version,retry,
  policy.method,'Carrier','Customer address','tracking-1','dispatch-1','carrier-signature')<>shipped then
  raise exception 'Dispatch replay changed result'; end if;
 begin
  perform public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version,retry,
   policy.method,'Other carrier','Customer address','tracking-1','dispatch-1','carrier-signature');
  raise exception 'Changed dispatch replay accepted';
 exception when unique_violation then
  if sqlerrm<>'IDEMPOTENCY_KEY_REUSED' then raise; end if;
 end;
 v_version:=(shipped->>'version')::integer;
 if not exists(select 1 from public.repair_device_custody_positions pos where org_id=f.org_id
  and device_id=(s->>'deviceId')::uuid and pos.case_id=(c->>'caseId')::uuid
  and holder_kind='carrier' and custodian_user_id is null and external_reference='dispatch-1')
  or not exists(select 1 from public.repair_replacement_stock stock where org_id=f.org_id
   and device_id=(s->>'deviceId')::uuid and status='allocated' and issued_receipt_id is null)
  or not exists(select 1 from public.repair_cases rc where id=(c->>'caseId')::uuid
   and verified_device_id=original_id and device_location='Workshop') then
  raise exception 'Shipment changed original identity or prematurely issued stock'; end if;
 begin
  perform public.record_replacement_delivery_receipt(f.org_id,case_id,v_version,gen_random_uuid(),
   'Colleague','colleague','signed authorization','in-person','signature');
  raise exception 'In-person receipt while carrier holds device accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_CUSTODIAN_REQUIRED' then raise; end if;
 end;
 begin
  perform public.confirm_replacement_delivery_receipt(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
   v_version,gen_random_uuid(),'Wrong person','colleague','signed authorization','destination','signature');
  raise exception 'Wrong recipient accepted';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_DISPATCH_MISMATCH' then raise; end if;
 end;
 begin
  perform public.confirm_replacement_delivery_receipt(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
   v_version,gen_random_uuid(),'Colleague','colleague','signed authorization','dispatch-1','carrier-signature');
  raise exception 'Dispatch evidence reused as receipt';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_INDEPENDENT_RECEIPT_REQUIRED' then raise; end if;
 end;
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'customer_paid',100);
 begin
  perform public.confirm_replacement_delivery_receipt(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
   v_version,gen_random_uuid(),'Colleague','colleague','signed authorization','destination','signature');
  raise exception 'Unsettled remote receipt accepted';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_PAYMENT_UNSETTLED' then raise; end if;
 end;
 perform pg_temp.set_replacement_plan_amount(f.org_id,(p->>'planId')::uuid,'warranty',0);
 incident:=public.record_repair_delivery_incident(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
  case when policy.damage_loop then 'damage' else 'lost' end,'incident-1','carrier report',
  f.owner_id,clock_timestamp()+interval '1 day',v_version,gen_random_uuid());
 v_version:=(incident->>'version')::integer;
 if not exists(select 1 from public.repair_delivery_incidents i where id=(incident->>'incidentId')::uuid
  and device_id=(s->>'deviceId')::uuid and device_id<>original_id) then
  raise exception 'Shipment incident attached to original'; end if;
 begin
  perform public.confirm_replacement_delivery_receipt(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
   v_version,gen_random_uuid(),'Colleague','colleague','signed authorization','destination','signature');
  raise exception 'Open incident allowed receipt';
 exception when check_violation then
  if sqlerrm<>'DELIVERY_INCIDENT_OPEN' then raise; end if;
 end;
 if policy.damage_loop then
  begin
   perform public.return_repair_case_to_test_after_damage(f.org_id,case_id,v_version,gen_random_uuid());
   raise exception 'Retest without physical return accepted';
  exception when check_violation then
   if sqlerrm<>'CUSTODY_DAMAGE_RETURN_REQUIRED' then raise; end if;
  end;
  begin
   perform public.resolve_repair_delivery_incident(f.org_id,case_id,(incident->>'incidentId')::uuid,
    v_version,1,'damage-resolved','no return',gen_random_uuid());
   raise exception 'Damage resolved without return';
  exception when check_violation then
   if sqlerrm<>'DELIVERY_DAMAGE_RETURN_REQUIRED' then raise; end if;
  end;
  retry:=gen_random_uuid();
  returned:=public.receive_repair_delivery_damage_return(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
   (incident->>'incidentId')::uuid,v_version,1,retry,'Replacement quarantine','Damaged box',
   'physical-return','signed-return');
  if public.receive_repair_delivery_damage_return(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
   (incident->>'incidentId')::uuid,v_version,1,retry,'Replacement quarantine','Damaged box',
   'physical-return','signed-return')<>returned then raise exception 'Damage return replay invalid'; end if;
  v_version:=(returned->>'version')::integer;
  if not exists(select 1 from public.repair_replacement_stock stock where org_id=f.org_id
   and device_id=(s->>'deviceId')::uuid and status='allocated' and location='Replacement quarantine'
   and custodian_user_id=f.owner_id)
   or not exists(select 1 from public.repair_cases rc where id=(c->>'caseId')::uuid
    and verified_device_id=original_id and device_location='Workshop' and custody_damage_epoch=1) then
   raise exception 'Damage return corrupted original or replacement stock custody'; end if;
  begin
   perform public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version,gen_random_uuid(),
    policy.method,'Carrier','Customer address','tracking-2','dispatch-2','fresh-carrier-signature');
   raise exception 'Damaged replacement sent with stale QC';
  exception when check_violation then
   if sqlerrm<>'REPLACEMENT_OUTGOING_RELEASE_REQUIRED' then raise; end if;
  end;
  moved:=public.return_repair_case_to_test_after_damage(f.org_id,case_id,v_version,gen_random_uuid());
  v_version:=(moved->>'version')::integer;
  v_passed:=public.record_repair_replacement_functional_test(f.org_id,case_id,v_version,gen_random_uuid(),
   'pass','fresh label','pass','fresh boot','pass','fresh position','pass','fresh config');
  v_version:=(v_passed->>'version')::integer;
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  released:=public.release_repair_functional_test(f.org_id,case_id,(v_passed->>'testId')::uuid,v_version,gen_random_uuid());
  v_version:=(released->>'version')::integer;
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  good_check:=public.record_replacement_outgoing_check(f.org_id,case_id,v_version,gen_random_uuid(),
   true,'fresh identity',true,'charger',true,'condition passed',true,'repacked',
   'Colleague','colleague','signed authorization');
  v_version:=(good_check->>'version')::integer;
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  released:=public.release_repair_outgoing_check(f.org_id,case_id,(good_check->>'checkId')::uuid,v_version,gen_random_uuid());
  v_version:=(released->>'version')::integer;
  perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
  moved:=public.advance_replacement_case_to_delivery(f.org_id,case_id,v_version,gen_random_uuid());
  v_version:=(moved->>'version')::integer;
  shipped:=public.record_replacement_delivery_dispatch(f.org_id,case_id,v_version,gen_random_uuid(),
   policy.method,'Carrier','Customer address','tracking-2','dispatch-2','fresh-carrier-signature');
  v_version:=(shipped->>'version')::integer;
 else
  moved:=public.resolve_repair_delivery_incident(f.org_id,case_id,(incident->>'incidentId')::uuid,
   v_version,1,'found','carrier found parcel',gen_random_uuid());
  v_version:=(moved->>'version')::integer;
 end if;
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.confirm_replacement_delivery_receipt(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
   v_version,gen_random_uuid(),'Colleague','colleague','signed authorization','destination','signature');
  raise exception 'Unauthorized destination confirmation accepted';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform pg_temp.allow_clerk_remote(f.clerk_role_id);
 retry:=gen_random_uuid();
 receipt:=public.confirm_replacement_delivery_receipt(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
  v_version,retry,'Colleague','colleague','signed authorization','destination','signature');
 if public.confirm_replacement_delivery_receipt(f.org_id,case_id,(shipped->>'dispatchId')::uuid,
  v_version,retry,'Colleague','colleague','signed authorization','destination','signature')<>receipt then
  raise exception 'Remote receipt replay invalid'; end if;
 v_version:=(receipt->>'version')::integer;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 if not exists(select 1 from public.repair_delivery_receipts r join public.repair_replacement_stock stock
  on stock.org_id=r.org_id and stock.device_id=r.device_id and stock.issued_receipt_id=r.id
  where r.id=(receipt->>'receiptId')::uuid and r.device_id=(s->>'deviceId')::uuid and r.method=policy.method
   and r.dispatch_id=(shipped->>'dispatchId')::uuid and stock.status='issued' and stock.issued_at=r.received_at)
  or not exists(select 1 from public.repair_device_custody_positions pos where org_id=f.org_id
   and device_id=(s->>'deviceId')::uuid and holder_kind='recipient' and external_reference='destination') then
  raise exception 'Remote receipt did not atomically issue stock/custody'; end if;
 begin
  perform public.close_replacement_case(f.org_id,case_id,v_version,gen_random_uuid());
  raise exception 'Remote replacement closed without original disposition';
 exception when check_violation then
  if sqlerrm<>'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' then raise; end if;
 end;
 moved:=public.record_replacement_original_return(f.org_id,case_id,v_version,gen_random_uuid(),
  'original-receipt','original-signature','broken original and charger');
 v_version:=(moved->>'version')::integer;
 moved:=public.close_replacement_case(f.org_id,case_id,v_version,gen_random_uuid());
 if moved->>'stage'<>'closed' then raise exception 'Remote replacement failed closure'; end if;
 raise notice '% replacement dispatch, incident, damage_loop=%, destination receipt, stock issue and original disposition passed',policy.method,policy.damage_loop;
end $$;
reset role;
rollback;
