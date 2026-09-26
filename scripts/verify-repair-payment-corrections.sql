\set ON_ERROR_STOP on
begin;
create temp table payment_fixture as select gen_random_uuid() owner_id,gen_random_uuid() clerk_id,
 gen_random_uuid() org_id,gen_random_uuid() owner_role_id,gen_random_uuid() clerk_role_id;
insert into auth.users(id,aud,role,email)
select owner_id,'authenticated','authenticated','payment-owner@example.test' from payment_fixture
union all select clerk_id,'authenticated','authenticated','payment-clerk@example.test' from payment_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Payment test',owner_id from payment_fixture;
insert into public.roles(id,org_id,name,is_system)
select owner_role_id,org_id,'Payment owner',false from payment_fixture
union all select clerk_role_id,org_id,'Payment clerk',false from payment_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,owner_id,owner_role_id from payment_fixture
union all select org_id,clerk_id,clerk_role_id from payment_fixture;
insert into public.role_permissions(role_id,permission_key)
select owner_role_id,key from payment_fixture cross join public.permissions
where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
 or key in ('repair.plan.record','repair.payment.record','repair.payment.verify','repair.payment.correct');
grant select on payment_fixture to authenticated;
create function pg_temp.add_payment_imei_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{"mimetype":"image/png","size":128}'::jsonb);
$$;
grant execute on function pg_temp.add_payment_imei_evidence(text,uuid) to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; d jsonb; p jsonb; a jsonb; b jsonb; v jsonb;
 case_id uuid; path text; retry_key uuid;
begin
 select * into f from payment_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 c:=public.create_repair_case(f.org_id,'GPS','payment-test','Customer','No signal',
  'normal','walk_in',gen_random_uuid());
 case_id:=(c->>'caseId')::uuid;
 path:=f.org_id::text||'/'||case_id::text||'/'||gen_random_uuid()::text||'.png';
 perform pg_temp.add_payment_imei_evidence(path,f.owner_id);
 perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
  'walk_in','Workshop','Owner','charger','359881234567892',path);
 perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
 d:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
  'Signal fault','needs_repair','repair','not_covered');
 perform public.finalize_repair_diagnosis(f.org_id,case_id,(d->>'diagnosisId')::uuid,4,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
 p:=public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
  'repair','Repair signal','customer_paid',100000,'no_parts');
 begin
  perform public.record_repair_payment_evidence(f.org_id,case_id,7,gen_random_uuid(),
   0,'card','transaction-0','bank statement');
  raise exception 'Zero payment accepted';
 exception when check_violation then
  if sqlerrm<>'INVALID_PAYMENT_EVIDENCE' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.record_repair_payment_evidence(f.org_id,case_id,7,gen_random_uuid(),
   60000,'card','transaction-1','bank statement');
  raise exception 'User without permission recorded payment';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 retry_key:=gen_random_uuid();
 a:=public.record_repair_payment_evidence(f.org_id,case_id,7,retry_key,
  60000,'card','transaction-1','bank statement');
 if a->>'version'<>'8' then raise exception 'Payment version did not advance'; end if;
 if public.record_repair_payment_evidence(f.org_id,case_id,7,retry_key,
  60000,'card','transaction-1','bank statement')<>a then
  raise exception 'Payment retry was not idempotent'; end if;
 begin
  perform public.verify_repair_payment_evidence(f.org_id,case_id,(a->>'paymentId')::uuid,
   7,gen_random_uuid(),'bank-match-1');
  raise exception 'Stale case version accepted';
 exception when raise_exception then
  if sqlerrm<>'CASE_VERSION_CONFLICT' then raise; end if;
 end;
 retry_key:=gen_random_uuid();
 v:=public.verify_repair_payment_evidence(f.org_id,case_id,(a->>'paymentId')::uuid,
  8,retry_key,'bank-match-1');
 if v->>'confirmedAmountIrr'<>'60000' then raise exception 'Confirmed amount wrong'; end if;
 if public.verify_repair_payment_evidence(f.org_id,case_id,(a->>'paymentId')::uuid,
  8,retry_key,'bank-match-1')<>v then raise exception 'Verification retry was not idempotent'; end if;
 b:=public.record_repair_payment_evidence(f.org_id,case_id,9,gen_random_uuid(),
  50000,'bank_transfer','transaction-2','bank statement');
 -- The second receipt is still unverified; correcting it must prevent later verification.
 perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);
 begin
  perform public.correct_repair_payment_evidence(f.org_id,case_id,(a->>'paymentId')::uuid,
   10,gen_random_uuid(),'duplicate','Duplicate bank record','correction-denied','bank review');
  raise exception 'Unpermitted correction accepted';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 retry_key:=gen_random_uuid();
 v:=public.correct_repair_payment_evidence(f.org_id,case_id,(a->>'paymentId')::uuid,
  10,retry_key,'duplicate','Duplicate bank record','correction-1','bank review');
 if v->>'version'<>'11' then raise exception 'Correction version did not advance'; end if;
 if public.correct_repair_payment_evidence(f.org_id,case_id,(a->>'paymentId')::uuid,
  10,retry_key,'duplicate','Duplicate bank record','correction-1','bank review')<>v then
  raise exception 'Correction retry was not idempotent'; end if;
 if not exists(select 1 from public.repair_payment_corrections
   where payment_id=(a->>'paymentId')::uuid and reason='duplicate') then
  raise exception 'Correction evidence missing'; end if;
 begin
  perform public.correct_repair_payment_evidence(f.org_id,case_id,(a->>'paymentId')::uuid,
   11,gen_random_uuid(),'duplicate','Duplicate bank record','correction-2','bank review');
  raise exception 'Second correction accepted';
 exception when unique_violation then
  if sqlerrm<>'PAYMENT_ALREADY_CORRECTED' then raise; end if;
 end;
 -- The previous 60,000 IRR no longer consumes the plan cap.
 v:=public.verify_repair_payment_evidence(f.org_id,case_id,(b->>'paymentId')::uuid,
  11,gen_random_uuid(),'bank-match-2');
 if v->>'confirmedAmountIrr'<>'50000' then raise exception 'Correction did not reduce active balance'; end if;
 begin
  perform public.verify_repair_payment_evidence(f.org_id,case_id,(a->>'paymentId')::uuid,
   12,gen_random_uuid(),'bank-match-reused');
  raise exception 'Corrected payment reverified';
 exception when unique_violation then
  if sqlerrm<>'PAYMENT_ALREADY_CORRECTED' then raise; end if;
 end;
 -- A correction cannot be silently written around the checked command.
 begin
  insert into public.repair_payment_corrections(org_id,case_id,payment_id,reason,explanation,
   correction_reference,evidence_reference,corrected_by)
  values(f.org_id,case_id,(b->>'paymentId')::uuid,'duplicate','No direct writes','bypass','evidence',f.owner_id);
  raise exception 'Direct correction accepted';
 exception when insufficient_privilege then null;
 end;
 raise notice 'Payment correction permissions, audit, retry, balance and reuse checks passed';
end $$;
rollback;
