\set ON_ERROR_STOP on
begin;
create temp table refund_fixture as select gen_random_uuid() owner_id,gen_random_uuid() approver_id,
 gen_random_uuid() org_id,gen_random_uuid() owner_role_id,gen_random_uuid() approver_role_id;
insert into auth.users(id,aud,role,email)
select owner_id,'authenticated','authenticated','refund-owner@example.test' from refund_fixture
union all select approver_id,'authenticated','authenticated','refund-approver@example.test' from refund_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Refund test',owner_id from refund_fixture;
insert into public.roles(id,org_id,name,is_system)
select owner_role_id,org_id,'Refund owner',false from refund_fixture
union all select approver_role_id,org_id,'Refund approver',false from refund_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,owner_id,owner_role_id from refund_fixture
union all select org_id,approver_id,approver_role_id from refund_fixture;
insert into public.role_permissions(role_id,permission_key)
select owner_role_id,key from refund_fixture cross join public.permissions
where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
 or key in ('repair.plan.record','repair.payment.record','repair.payment.verify','repair.payment.correct',
  'repair.payment.credit.request','repair.payment.credit.approve',
  'repair.payment.refund.request','repair.payment.refund.approve');
insert into public.role_permissions(role_id,permission_key)
select approver_role_id,key from refund_fixture cross join public.permissions
where key in ('repair.payment.refund.approve','repair.payment.credit.approve');
grant select on refund_fixture to authenticated;
create function pg_temp.add_refund_imei_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.add_refund_imei_evidence(text,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; d jsonb; p jsonb; source jsonb; request jsonb; approved jsonb;
 transfer jsonb; current_receipt jsonb; second_receipt jsonb; v jsonb; case_id uuid; path text; key uuid;
begin
 select * into f from refund_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','refund-test','Customer','No signal',
  'normal','walk_in',gen_random_uuid());
 case_id:=(c->>'caseId')::uuid;
 path:=f.org_id::text||'/'||case_id::text||'/'||gen_random_uuid()::text||'.png';
 perform pg_temp.add_refund_imei_evidence(path,f.owner_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567892',path);
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 d:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Signal fault','needs_repair','repair','not_covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(d->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 p:=public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'repair','First repair plan','customer_paid',100000,'no_parts');
 source:=public.record_repair_payment_evidence(f.org_id,case_id,7,gen_random_uuid(),
  100000,'card','refund-old-transaction','bank statement');
 perform public.verify_repair_payment_evidence(f.org_id,case_id,(source->>'paymentId')::uuid,
  8,gen_random_uuid(),'refund-old-bank-match');
 key:=gen_random_uuid();
 request:=public.request_repair_payment_refund(f.org_id,case_id,(source->>'paymentId')::uuid,
  9,key,30000,'Reduced repair estimate','refund-request-1');
 if request->>'version'<>'10' then raise exception 'Refund request version mismatch'; end if;
 if public.request_repair_payment_refund(f.org_id,case_id,(source->>'paymentId')::uuid,
  9,key,30000,'Reduced repair estimate','refund-request-1')<>request then
  raise exception 'Refund request retry was not idempotent'; end if;
 begin
  perform public.approve_repair_payment_refund(f.org_id,case_id,(request->>'refundId')::uuid,
   10,gen_random_uuid(),'bank_transfer','refund-out-self','bank receipt','refund-approve-self');
  raise exception 'Self-approval accepted';
 exception when check_violation then
  if sqlerrm<>'REFUND_APPROVAL_NOT_ALLOWED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.approver_id::text,true);
 begin
  perform public.approve_repair_payment_refund(f.org_id,case_id,(request->>'refundId')::uuid,
   10,gen_random_uuid(),'bank_transfer','','','');
  raise exception 'Missing outbound receipt accepted';
 exception when check_violation then
  if sqlerrm<>'INVALID_REFUND_APPROVAL' then raise; end if;
 end;
 key:=gen_random_uuid();
 approved:=public.approve_repair_payment_refund(f.org_id,case_id,(request->>'refundId')::uuid,
  10,key,'bank_transfer','refund-out-1','bank receipt 1','refund-approve-1');
 if approved->>'version'<>'11' then raise exception 'Refund approval version mismatch'; end if;
 if public.approve_repair_payment_refund(f.org_id,case_id,(request->>'refundId')::uuid,
  10,key,'bank_transfer','refund-out-1','bank receipt 1','refund-approve-1')<>approved then
  raise exception 'Refund approval retry was not idempotent'; end if;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  perform public.correct_repair_payment_evidence(f.org_id,case_id,(source->>'paymentId')::uuid,
   11,gen_random_uuid(),'duplicate','Attempt to erase paid refund','refund-correction','finance evidence');
  raise exception 'Refund source corrected';
 exception when check_violation then
  if sqlerrm<>'PAYMENT_HAS_REFUND' then raise; end if;
 end;
 p:=public.save_repair_action_plan(f.org_id,case_id,11,gen_random_uuid(),
  'repair','Revised repair plan','customer_paid',100000,'no_parts');
 begin
  perform public.request_repair_payment_credit_transfer(f.org_id,case_id,(source->>'paymentId')::uuid,
   12,gen_random_uuid(),80000,'refund-credit-too-large','finance review');
  raise exception 'Refunded amount transferred';
 exception when check_violation then
  if sqlerrm<>'CREDIT_AMOUNT_EXCEEDS_AVAILABLE' then raise; end if;
 end;
 transfer:=public.request_repair_payment_credit_transfer(f.org_id,case_id,(source->>'paymentId')::uuid,
  12,gen_random_uuid(),70000,'refund-credit-request','finance review');
 perform set_config('request.jwt.claim.sub',f.approver_id::text,true);
 perform public.approve_repair_payment_credit_transfer(f.org_id,case_id,(transfer->>'transferId')::uuid,
  13,gen_random_uuid(),'refund-credit-approval');
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 current_receipt:=public.record_repair_payment_evidence(f.org_id,case_id,14,gen_random_uuid(),
  30000,'card','refund-current-transaction','bank statement');
 v:=public.verify_repair_payment_evidence(f.org_id,case_id,(current_receipt->>'paymentId')::uuid,
  15,gen_random_uuid(),'refund-current-bank-match');
 if v->>'confirmedAmountIrr'<>'100000' then raise exception 'Transferred credit did not settle plan'; end if;
 request:=public.request_repair_payment_refund(f.org_id,case_id,(current_receipt->>'paymentId')::uuid,
  16,gen_random_uuid(),10000,'Customer adjustment','refund-request-2');
 perform set_config('request.jwt.claim.sub',f.approver_id::text,true);
 perform public.approve_repair_payment_refund(f.org_id,case_id,(request->>'refundId')::uuid,
  17,gen_random_uuid(),'card_reversal','refund-out-2','card reversal receipt','refund-approve-2');
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 second_receipt:=public.record_repair_payment_evidence(f.org_id,case_id,18,gen_random_uuid(),
  10000,'bank_transfer','refund-replacement-payment','bank statement');
 v:=public.verify_repair_payment_evidence(f.org_id,case_id,(second_receipt->>'paymentId')::uuid,
  19,gen_random_uuid(),'refund-final-bank-match');
 if v->>'confirmedAmountIrr'<>'100000' then raise exception 'Refund was not removed from plan balance'; end if;
 begin
  perform public.request_repair_payment_refund(f.org_id,case_id,(source->>'paymentId')::uuid,
   20,gen_random_uuid(),1,'Overdraw source','refund-request-overdraw');
  raise exception 'Exhausted source refunded again';
 exception when check_violation then
  if sqlerrm<>'REFUND_EXCEEDS_AVAILABLE' then raise; end if;
 end;
 request:=public.request_repair_payment_refund(f.org_id,case_id,(current_receipt->>'paymentId')::uuid,
  20,gen_random_uuid(),1,'Second adjustment','refund-request-duplicate-outbound');
 perform set_config('request.jwt.claim.sub',f.approver_id::text,true);
 begin
  perform public.approve_repair_payment_refund(f.org_id,case_id,(request->>'refundId')::uuid,
   21,gen_random_uuid(),'bank_transfer','refund-out-2','another receipt','refund-approve-duplicate');
  raise exception 'Outbound transaction reference reused';
 exception when unique_violation then null;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  insert into public.repair_payment_refunds(org_id,case_id,source_payment_id,amount_irr,
   reason,request_reference,requested_by)
  values(f.org_id,case_id,(source->>'paymentId')::uuid,1,'Direct write','refund-direct',f.owner_id);
  raise exception 'Direct refund write accepted';
 exception when insufficient_privilege then null;
 end;
 raise notice 'Refund request, second-person outbound approval, credit limits and net settlement passed';
end $$;
rollback;
