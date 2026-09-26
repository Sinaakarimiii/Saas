\set ON_ERROR_STOP on
begin;
create temp table credit_fixture as select gen_random_uuid() owner_id,gen_random_uuid() approver_id,
 gen_random_uuid() org_id,gen_random_uuid() owner_role_id,gen_random_uuid() approver_role_id;
insert into auth.users(id,aud,role,email)
select owner_id,'authenticated','authenticated','credit-owner@example.test' from credit_fixture
union all select approver_id,'authenticated','authenticated','credit-approver@example.test' from credit_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Credit transfer test',owner_id from credit_fixture;
insert into public.roles(id,org_id,name,is_system)
select owner_role_id,org_id,'Credit owner',false from credit_fixture
union all select approver_role_id,org_id,'Credit approver',false from credit_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,owner_id,owner_role_id from credit_fixture
union all select org_id,approver_id,approver_role_id from credit_fixture;
insert into public.role_permissions(role_id,permission_key)
select owner_role_id,key from credit_fixture cross join public.permissions
where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
 or key in ('repair.plan.record','repair.payment.record','repair.payment.verify','repair.payment.correct',
  'repair.payment.credit.request','repair.payment.credit.approve');
insert into public.role_permissions(role_id,permission_key)
select approver_role_id,'repair.payment.credit.approve' from credit_fixture;
grant select on credit_fixture to authenticated;
create function pg_temp.add_credit_imei_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.add_credit_imei_evidence(text,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; d jsonb; p jsonb; source jsonb; v jsonb; request jsonb; approval jsonb;
 second jsonb; case_id uuid; path text; key uuid;
begin
 select * into f from credit_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','credit-test','Customer','No signal',
  'normal','walk_in',gen_random_uuid());
 case_id:=(c->>'caseId')::uuid;
 path:=f.org_id::text||'/'||case_id::text||'/'||gen_random_uuid()::text||'.png';
 perform pg_temp.add_credit_imei_evidence(path,f.owner_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567892',path);
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 d:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Signal fault','needs_repair','repair','not_covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(d->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 p:=public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'repair','First repair plan','customer_paid',80000,'no_parts');
 source:=public.record_repair_payment_evidence(f.org_id,case_id,7,gen_random_uuid(),
  80000,'card','credit-old-transaction','bank statement');
 perform public.verify_repair_payment_evidence(f.org_id,case_id,(source->>'paymentId')::uuid,
  8,gen_random_uuid(),'credit-old-bank-match');
 p:=public.save_repair_action_plan(f.org_id,case_id,9,gen_random_uuid(),
  'repair','Revised repair plan','customer_paid',100000,'no_parts');
 key:=gen_random_uuid();
 request:=public.request_repair_payment_credit_transfer(f.org_id,case_id,(source->>'paymentId')::uuid,
  10,key,60000,'credit-request-1','finance review');
 if request->>'version'<>'11' then raise exception 'Request version mismatch'; end if;
 if public.request_repair_payment_credit_transfer(f.org_id,case_id,(source->>'paymentId')::uuid,
  10,key,60000,'credit-request-1','finance review')<>request then
  raise exception 'Request retry was not idempotent'; end if;
 begin
  perform public.approve_repair_payment_credit_transfer(f.org_id,case_id,(request->>'transferId')::uuid,
   11,gen_random_uuid(),'credit-self-approval');
  raise exception 'Self-approval accepted';
 exception when check_violation then
  if sqlerrm<>'CREDIT_APPROVAL_NOT_ALLOWED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.approver_id::text,true);
 key:=gen_random_uuid();
 approval:=public.approve_repair_payment_credit_transfer(f.org_id,case_id,(request->>'transferId')::uuid,
  11,key,'credit-approval-1');
 if approval->>'confirmedAmountIrr'<>'60000' then raise exception 'Approved credit missing from balance'; end if;
 if public.approve_repair_payment_credit_transfer(f.org_id,case_id,(request->>'transferId')::uuid,
  11,key,'credit-approval-1')<>approval then raise exception 'Approval retry was not idempotent'; end if;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  perform public.correct_repair_payment_evidence(f.org_id,case_id,(source->>'paymentId')::uuid,
   12,gen_random_uuid(),'duplicate','Incorrect source','credit-correction','finance evidence');
  raise exception 'Transferred source corrected';
 exception when check_violation then
  if sqlerrm<>'CURRENT_PAYMENT_REQUIRED' then raise; end if;
 end;
 begin
  perform public.request_repair_payment_credit_transfer(f.org_id,case_id,(source->>'paymentId')::uuid,
   12,gen_random_uuid(),30000,'credit-too-large','finance review');
  raise exception 'Source overspent';
 exception when check_violation then
  if sqlerrm<>'CREDIT_AMOUNT_EXCEEDS_AVAILABLE' then raise; end if;
 end;
 second:=public.record_repair_payment_evidence(f.org_id,case_id,12,gen_random_uuid(),
  40000,'bank_transfer','credit-new-transaction','bank statement');
 v:=public.verify_repair_payment_evidence(f.org_id,case_id,(second->>'paymentId')::uuid,
  13,gen_random_uuid(),'credit-new-bank-match');
 if v->>'confirmedAmountIrr'<>'100000' then raise exception 'New payment and credit did not settle plan'; end if;
 second:=public.record_repair_payment_evidence(f.org_id,case_id,14,gen_random_uuid(),
  1,'card','credit-extra-transaction','bank statement');
 begin
  perform public.verify_repair_payment_evidence(f.org_id,case_id,(second->>'paymentId')::uuid,
   15,gen_random_uuid(),'credit-extra-bank-match');
  raise exception 'Overpayment verified';
 exception when check_violation then
  if sqlerrm<>'PAYMENT_EXCEEDS_PLAN' then raise; end if;
 end;
 -- A request left pending against a superseded target plan cannot be approved.
 p:=public.save_repair_action_plan(f.org_id,case_id,15,gen_random_uuid(),
  'repair','Third repair plan','customer_paid',70000,'no_parts');
 request:=public.request_repair_payment_credit_transfer(f.org_id,case_id,(source->>'paymentId')::uuid,
  16,gen_random_uuid(),20000,'credit-stale-request','finance review');
 p:=public.save_repair_action_plan(f.org_id,case_id,17,gen_random_uuid(),
  'repair','Fourth repair plan','customer_paid',70000,'no_parts');
 perform set_config('request.jwt.claim.sub',f.approver_id::text,true);
 begin
  perform public.approve_repair_payment_credit_transfer(f.org_id,case_id,(request->>'transferId')::uuid,
   18,gen_random_uuid(),'credit-stale-approval');
  raise exception 'Superseded target approved';
 exception when check_violation then
  if sqlerrm<>'CREDIT_APPROVAL_NOT_ALLOWED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 begin
  insert into public.repair_payment_credit_transfers(org_id,case_id,source_payment_id,target_plan_id,
   amount_irr,request_reference,request_evidence,requested_by)
  values(f.org_id,case_id,(source->>'paymentId')::uuid,(p->>'planId')::uuid,
   1,'credit-direct','direct',f.owner_id);
  raise exception 'Direct transfer write accepted';
 exception when insufficient_privilege then null;
 end;
 raise notice 'Credit request, second-person approval, limits, correction guard and settlement passed';
end $$;
reset role;
do $$
declare f record; source record;
begin
 select * into f from credit_fixture;
 select * into source from public.repair_payment_evidence
  where org_id=f.org_id and external_reference='credit-old-transaction';
 begin
  insert into public.repair_payment_corrections(org_id,case_id,payment_id,reason,explanation,
   correction_reference,evidence_reference,corrected_by)
  values(f.org_id,source.case_id,source.id,'duplicate','Direct invalidation attempt',
   'credit-direct-correction','finance evidence',f.owner_id);
  raise exception 'Transferred source directly corrected';
 exception when check_violation then
  if sqlerrm<>'PAYMENT_HAS_CREDIT_TRANSFER' then raise; end if;
 end;
end $$;
rollback;
