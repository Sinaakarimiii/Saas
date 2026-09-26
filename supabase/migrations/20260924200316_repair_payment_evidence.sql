-- Payment evidence is tied to one immutable paid plan revision. Verification is
-- a separate act; a recorded receipt alone never counts toward settlement.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.payment.record','ثبت سند دریافت وجه تعمیر','ثبت مبلغ و مرجع تراکنش برای برنامه پرداختی','{}'),
 ('repair.payment.verify','تطبیق دریافت وجه تعمیر','تأیید مستقل سند پرداخت و مبلغ در برنامه جاری','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
 and p.key in ('repair.payment.record','repair.payment.verify')
on conflict(role_id,permission_key) do nothing;

create table public.repair_payment_evidence (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, plan_id uuid not null,
 amount_irr bigint not null check(amount_irr>0),
 method text not null check(method in ('card','bank_transfer','cash')),
 external_reference text not null check(length(pg_catalog.btrim(external_reference)) between 1 and 160),
 evidence_reference text not null check(length(pg_catalog.btrim(evidence_reference)) between 1 and 500),
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,external_reference), unique(org_id,case_id,id),
 foreign key(org_id,case_id,plan_id) references public.repair_action_plans(org_id,case_id,id)
);
create index repair_payment_evidence_plan_idx on public.repair_payment_evidence(org_id,case_id,plan_id,recorded_at desc);
create table public.repair_payment_verifications (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, payment_id uuid not null,
 verification_reference text not null check(length(pg_catalog.btrim(verification_reference)) between 1 and 160),
 verified_by uuid not null references auth.users(id),
 verified_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,case_id,payment_id), unique(org_id,verification_reference),
 foreign key(org_id,case_id,payment_id) references public.repair_payment_evidence(org_id,case_id,id)
);
create index repair_payment_verifications_case_idx on public.repair_payment_verifications(org_id,case_id,verified_at desc);
alter table public.repair_payment_evidence enable row level security;
alter table public.repair_payment_verifications enable row level security;
create policy repair_payment_evidence_select on public.repair_payment_evidence for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
create policy repair_payment_verifications_select on public.repair_payment_verifications for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_payment_evidence,public.repair_payment_verifications from public,anon,authenticated;
grant select on public.repair_payment_evidence,public.repair_payment_verifications to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
check(event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved',
'custody_baseline_recorded','custody_released','custody_accepted','custody_returned',
'custody_discrepancy_recorded','custody_discrepancy_resolved','delivery_received','delivery_dispatched',
'delivery_incident_recorded','delivery_incident_followed_up','delivery_incident_resolved',
'delivery_damage_returned','replacement_allocated','functional_test_recorded','functional_test_released',
'payment_recorded','payment_verified'));

create function public.record_repair_payment_evidence(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_amount_irr bigint,p_method text,p_external_reference text,p_evidence_reference text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_payment public.repair_payment_evidence; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.payment.record') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_expected_version is null or p_expected_version<1
  or p_amount_irr is null or p_amount_irr<=0
  or p_method is null or p_method not in ('card','bank_transfer','cash')
  or length(pg_catalog.btrim(coalesce(p_external_reference,''))) not between 1 and 160
  or length(pg_catalog.btrim(coalesce(p_evidence_reference,''))) not between 1 and 500 then
  raise exception 'INVALID_PAYMENT_EVIDENCE' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,
  'amount',p_amount_irr,'method',p_method,'reference',pg_catalog.btrim(p_external_reference),
  'evidence',pg_catalog.btrim(p_evidence_reference))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.payment.record:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='repair.payment.record' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_case.stage not in ('decision','repair','test') or v_plan.id is null
  or v_plan.financial_basis<>'customer_paid' or v_plan.route not in ('repair','replacement')
  or p_amount_irr>v_plan.amount_irr then
  raise exception 'CURRENT_PAID_PLAN_REQUIRED' using errcode='23514'; end if;
 insert into public.repair_payment_evidence(org_id,case_id,plan_id,amount_irr,method,
  external_reference,evidence_reference,recorded_by)
 values(p_org_id,p_case_id,v_plan.id,p_amount_irr,p_method,
  pg_catalog.btrim(p_external_reference),pg_catalog.btrim(p_evidence_reference),v_actor)
 returning * into v_payment;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'payment_recorded',v_actor,
  pg_catalog.jsonb_build_object('planId',v_plan.id,'paymentId',v_payment.id,'amountIrr',p_amount_irr));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'paymentId',v_payment.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'repair.payment.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_repair_payment_evidence(uuid,uuid,integer,uuid,bigint,text,text,text) from public,anon;
grant execute on function public.record_repair_payment_evidence(uuid,uuid,integer,uuid,bigint,text,text,text) to authenticated;

create function public.verify_repair_payment_evidence(
 p_org_id uuid,p_case_id uuid,p_payment_id uuid,p_expected_version integer,
 p_idempotency_key uuid,p_verification_reference text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_payment public.repair_payment_evidence; v_verification public.repair_payment_verifications;
 v_confirmed bigint; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.payment.verify') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_payment_id is null or p_expected_version is null or p_expected_version<1
  or length(pg_catalog.btrim(coalesce(p_verification_reference,''))) not between 1 and 160 then
  raise exception 'INVALID_PAYMENT_VERIFICATION' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'paymentId',p_payment_id,
  'version',p_expected_version,'reference',pg_catalog.btrim(p_verification_reference))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.payment.verify:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='repair.payment.verify' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_payment from public.repair_payment_evidence
  where org_id=p_org_id and case_id=p_case_id and id=p_payment_id;
 if v_case.stage not in ('decision','repair','test') or v_plan.id is null
  or v_plan.financial_basis<>'customer_paid' or v_payment.id is null
  or v_payment.plan_id<>v_plan.id then
  raise exception 'CURRENT_PAYMENT_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_payment_verifications
   where org_id=p_org_id and case_id=p_case_id and payment_id=p_payment_id) then
  raise exception 'PAYMENT_ALREADY_VERIFIED' using errcode='23505'; end if;
 select coalesce(sum(p.amount_irr),0) into v_confirmed
 from public.repair_payment_evidence p join public.repair_payment_verifications v
  on v.org_id=p.org_id and v.case_id=p.case_id and v.payment_id=p.id
 where p.org_id=p_org_id and p.case_id=p_case_id and p.plan_id=v_plan.id;
 if v_confirmed>v_plan.amount_irr-v_payment.amount_irr then
  raise exception 'PAYMENT_EXCEEDS_PLAN' using errcode='23514'; end if;
 insert into public.repair_payment_verifications(org_id,case_id,payment_id,verification_reference,verified_by)
 values(p_org_id,p_case_id,p_payment_id,pg_catalog.btrim(p_verification_reference),v_actor)
 returning * into v_verification;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'payment_verified',v_actor,
  pg_catalog.jsonb_build_object('planId',v_plan.id,'paymentId',p_payment_id,
   'verificationId',v_verification.id,'amountIrr',v_payment.amount_irr));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'verificationId',v_verification.id,
  'confirmedAmountIrr',v_confirmed+v_payment.amount_irr,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'repair.payment.verify',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.verify_repair_payment_evidence(uuid,uuid,uuid,integer,uuid,text) from public,anon;
grant execute on function public.verify_repair_payment_evidence(uuid,uuid,uuid,integer,uuid,text) to authenticated;
