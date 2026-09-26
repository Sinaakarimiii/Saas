-- Transfers are explicit, append-only allocations of verified receipts from an
-- older plan to the currently active paid plan. Request and approval are distinct.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.payment.credit.request','درخواست انتقال اعتبار تعمیر','ثبت انتقال اعتبار پرداخت تأییدشده به برنامه جدید','{}'),
 ('repair.payment.credit.approve','تأیید انتقال اعتبار تعمیر','تأیید مستقل انتقال اعتبار بین نسخه‌های برنامه','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
 and p.key in ('repair.payment.credit.request','repair.payment.credit.approve')
on conflict(role_id,permission_key) do nothing;

create table public.repair_payment_credit_transfers (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null,
 source_payment_id uuid not null, target_plan_id uuid not null,
 amount_irr bigint not null check(amount_irr>0),
 request_reference text not null check(length(pg_catalog.btrim(request_reference)) between 1 and 160),
 request_evidence text not null check(length(pg_catalog.btrim(request_evidence)) between 1 and 500),
 requested_by uuid not null references auth.users(id),
 requested_at timestamptz not null default pg_catalog.clock_timestamp(),
 approval_reference text check(approval_reference is null or length(pg_catalog.btrim(approval_reference)) between 1 and 160),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 check ((approval_reference is null and approved_by is null and approved_at is null)
  or (approval_reference is not null and approved_by is not null and approved_at is not null)),
 check (approved_by is null or approved_by<>requested_by),
 unique(org_id,request_reference), unique(org_id,approval_reference), unique(org_id,case_id,id),
 foreign key(org_id,case_id,source_payment_id) references public.repair_payment_evidence(org_id,case_id,id),
 foreign key(org_id,case_id,target_plan_id) references public.repair_action_plans(org_id,case_id,id)
);
create index repair_payment_credit_transfers_target_idx on public.repair_payment_credit_transfers(org_id,case_id,target_plan_id) where approved_at is not null;
create index repair_payment_credit_transfers_source_idx on public.repair_payment_credit_transfers(org_id,case_id,source_payment_id) where approved_at is not null;
alter table public.repair_payment_credit_transfers enable row level security;
create policy repair_payment_credit_transfers_select on public.repair_payment_credit_transfers for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_payment_credit_transfers from public,anon,authenticated;
grant select on public.repair_payment_credit_transfers to authenticated;

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
'payment_recorded','payment_verified','payment_corrected','payment_credit_requested','payment_credit_approved',
'repair_outgoing_checked','repair_outgoing_released','replacement_executed'));

-- A verified source receipt cannot later be declared erroneous after its value
-- has been allocated to another plan. Refunds will use a different ledger act.
create function private.guard_repair_payment_correction_after_transfer()
returns trigger language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.repair_payment_credit_transfers t
  where t.org_id=new.org_id and t.case_id=new.case_id and t.source_payment_id=new.payment_id
   and t.approved_at is not null) then
  raise exception 'PAYMENT_HAS_CREDIT_TRANSFER' using errcode='23514';
 end if;
 return new;
end; $$;
create trigger guard_repair_payment_correction_after_transfer before insert on public.repair_payment_corrections
for each row execute function private.guard_repair_payment_correction_after_transfer();

create function public.request_repair_payment_credit_transfer(
 p_org_id uuid,p_case_id uuid,p_source_payment_id uuid,p_expected_version integer,
 p_idempotency_key uuid,p_amount_irr bigint,p_request_reference text,p_request_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_source public.repair_payment_evidence; v_source_plan public.repair_action_plans;
 v_transfer public.repair_payment_credit_transfers; v_used bigint; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.payment.credit.request') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_source_payment_id is null or p_expected_version is null or p_expected_version<1
  or p_idempotency_key is null or p_amount_irr is null or p_amount_irr<=0
  or length(pg_catalog.btrim(coalesce(p_request_reference,''))) not between 1 and 160
  or length(pg_catalog.btrim(coalesce(p_request_evidence,''))) not between 1 and 500 then
  raise exception 'INVALID_CREDIT_TRANSFER' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'source',p_source_payment_id,
  'version',p_expected_version,'amount',p_amount_irr,'reference',pg_catalog.btrim(p_request_reference),
  'evidence',pg_catalog.btrim(p_request_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.payment.credit.request:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='repair.payment.credit.request' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_source from public.repair_payment_evidence
  where org_id=p_org_id and case_id=p_case_id and id=p_source_payment_id;
 select * into v_source_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id and id=v_source.plan_id;
 if v_case.stage not in ('decision','repair','replacement','test') or v_plan.id is null
  or v_plan.financial_basis<>'customer_paid' or v_plan.route not in ('repair','replacement')
  or v_source.id is null or v_source_plan.revision>=v_plan.revision
  or not exists(select 1 from public.repair_payment_verifications x where x.org_id=p_org_id and x.case_id=p_case_id and x.payment_id=v_source.id)
  or exists(select 1 from public.repair_payment_corrections x where x.org_id=p_org_id and x.case_id=p_case_id and x.payment_id=v_source.id) then
  raise exception 'ELIGIBLE_OLD_PAYMENT_REQUIRED' using errcode='23514'; end if;
 select coalesce(sum(amount_irr),0) into v_used from public.repair_payment_credit_transfers
  where org_id=p_org_id and case_id=p_case_id and source_payment_id=v_source.id and approved_at is not null;
 if p_amount_irr>v_source.amount_irr-v_used or p_amount_irr>v_plan.amount_irr then
  raise exception 'CREDIT_AMOUNT_EXCEEDS_AVAILABLE' using errcode='23514'; end if;
 insert into public.repair_payment_credit_transfers(org_id,case_id,source_payment_id,target_plan_id,
  amount_irr,request_reference,request_evidence,requested_by)
 values(p_org_id,p_case_id,v_source.id,v_plan.id,p_amount_irr,
  pg_catalog.btrim(p_request_reference),pg_catalog.btrim(p_request_evidence),v_actor)
 returning * into v_transfer;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'payment_credit_requested',v_actor,
  pg_catalog.jsonb_build_object('transferId',v_transfer.id,'sourcePaymentId',v_source.id,
   'targetPlanId',v_plan.id,'amountIrr',p_amount_irr));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'transferId',v_transfer.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'repair.payment.credit.request',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.request_repair_payment_credit_transfer(uuid,uuid,uuid,integer,uuid,bigint,text,text) from public,anon;
grant execute on function public.request_repair_payment_credit_transfer(uuid,uuid,uuid,integer,uuid,bigint,text,text) to authenticated;

create function public.approve_repair_payment_credit_transfer(
 p_org_id uuid,p_case_id uuid,p_transfer_id uuid,p_expected_version integer,
 p_idempotency_key uuid,p_approval_reference text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_source public.repair_payment_evidence; v_transfer public.repair_payment_credit_transfers;
 v_used bigint; v_confirmed bigint; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.payment.credit.approve') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_transfer_id is null or p_expected_version is null or p_expected_version<1
  or p_idempotency_key is null
  or length(pg_catalog.btrim(coalesce(p_approval_reference,''))) not between 1 and 160 then
  raise exception 'INVALID_CREDIT_APPROVAL' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'transferId',p_transfer_id,
  'version',p_expected_version,'reference',pg_catalog.btrim(p_approval_reference))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.payment.credit.approve:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='repair.payment.credit.approve' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_transfer from public.repair_payment_credit_transfers
  where org_id=p_org_id and case_id=p_case_id and id=p_transfer_id;
 if v_transfer.id is null or v_transfer.approved_at is not null then
  raise exception 'PENDING_CREDIT_TRANSFER_REQUIRED' using errcode='23514'; end if;
 select * into v_source from public.repair_payment_evidence
  where org_id=p_org_id and case_id=p_case_id and id=v_transfer.source_payment_id;
 if v_case.stage not in ('decision','repair','replacement','test') or v_plan.id<>v_transfer.target_plan_id
  or v_plan.financial_basis<>'customer_paid' or v_transfer.requested_by=v_actor
  or not exists(select 1 from public.repair_payment_verifications x where x.org_id=p_org_id and x.case_id=p_case_id and x.payment_id=v_source.id)
  or exists(select 1 from public.repair_payment_corrections x where x.org_id=p_org_id and x.case_id=p_case_id and x.payment_id=v_source.id) then
  raise exception 'CREDIT_APPROVAL_NOT_ALLOWED' using errcode='23514'; end if;
 select coalesce(sum(amount_irr),0) into v_used from public.repair_payment_credit_transfers
  where org_id=p_org_id and case_id=p_case_id and source_payment_id=v_source.id and approved_at is not null;
 if v_transfer.amount_irr>v_source.amount_irr-v_used then
  raise exception 'CREDIT_SOURCE_EXHAUSTED' using errcode='23514'; end if;
 select coalesce(sum(p.amount_irr),0) into v_confirmed from public.repair_payment_evidence p
  join public.repair_payment_verifications x on x.org_id=p.org_id and x.case_id=p.case_id and x.payment_id=p.id
  where p.org_id=p_org_id and p.case_id=p_case_id and p.plan_id=v_plan.id
   and not exists(select 1 from public.repair_payment_corrections c where c.org_id=p.org_id and c.case_id=p.case_id and c.payment_id=p.id);
 select v_confirmed+coalesce(sum(amount_irr),0) into v_confirmed from public.repair_payment_credit_transfers
  where org_id=p_org_id and case_id=p_case_id and target_plan_id=v_plan.id and approved_at is not null;
 if v_transfer.amount_irr>v_plan.amount_irr-v_confirmed then
  raise exception 'CREDIT_EXCEEDS_PLAN' using errcode='23514'; end if;
 update public.repair_payment_credit_transfers set approval_reference=pg_catalog.btrim(p_approval_reference),
  approved_by=v_actor,approved_at=pg_catalog.clock_timestamp()
 where id=v_transfer.id returning * into v_transfer;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'payment_credit_approved',v_actor,
  pg_catalog.jsonb_build_object('transferId',v_transfer.id,'sourcePaymentId',v_source.id,
   'targetPlanId',v_plan.id,'amountIrr',v_transfer.amount_irr));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'transferId',v_transfer.id,
  'confirmedAmountIrr',v_confirmed+v_transfer.amount_irr,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'repair.payment.credit.approve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.approve_repair_payment_credit_transfer(uuid,uuid,uuid,integer,uuid,text) from public,anon;
grant execute on function public.approve_repair_payment_credit_transfer(uuid,uuid,uuid,integer,uuid,text) to authenticated;

-- Recheck the total credited amount when verifying another payment or releasing a repaired device.
create or replace function public.verify_repair_payment_evidence(
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
 if v_case.stage not in ('decision','repair','replacement','test') or v_plan.id is null
  or v_plan.financial_basis<>'customer_paid' or v_payment.id is null
  or v_payment.plan_id<>v_plan.id then
  raise exception 'CURRENT_PAYMENT_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_payment_corrections
   where org_id=p_org_id and case_id=p_case_id and payment_id=p_payment_id) then
  raise exception 'PAYMENT_ALREADY_CORRECTED' using errcode='23505'; end if;
 if exists(select 1 from public.repair_payment_verifications
   where org_id=p_org_id and case_id=p_case_id and payment_id=p_payment_id) then
  raise exception 'PAYMENT_ALREADY_VERIFIED' using errcode='23505'; end if;
 select coalesce(sum(p.amount_irr),0) into v_confirmed
 from public.repair_payment_evidence p join public.repair_payment_verifications v
  on v.org_id=p.org_id and v.case_id=p.case_id and v.payment_id=p.id
 where p.org_id=p_org_id and p.case_id=p_case_id and p.plan_id=v_plan.id
  and not exists(select 1 from public.repair_payment_corrections c
   where c.org_id=p.org_id and c.case_id=p.case_id and c.payment_id=p.id);
 select v_confirmed+coalesce(sum(amount_irr),0) into v_confirmed from public.repair_payment_credit_transfers
  where org_id=p_org_id and case_id=p_case_id and target_plan_id=v_plan.id and approved_at is not null;
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


create or replace function private.assert_repair_handover_ready(p_org_id uuid,p_case_id uuid,p_stage text)
returns uuid language plpgsql set search_path='' as $$
declare v_case public.repair_cases; v_plan public.repair_action_plans;
 v_test public.repair_functional_tests; v_check public.repair_outgoing_checks;
 v_position public.repair_device_custody_positions; v_paid bigint;
begin
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id;
 if v_case.id is null or v_case.stage<>p_stage or v_case.verified_device_id is null
 then raise exception 'REPAIR_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_plan.id is null or v_plan.route<>'repair'
 then raise exception 'CURRENT_REPAIR_PLAN_REQUIRED' using errcode='23514'; end if;
 if v_plan.financial_basis='customer_paid' then
  select coalesce(sum(p.amount_irr),0) into v_paid from public.repair_payment_evidence p
   join public.repair_payment_verifications v on v.org_id=p.org_id and v.case_id=p.case_id and v.payment_id=p.id
   where p.org_id=p_org_id and p.case_id=p_case_id and p.plan_id=v_plan.id
    and not exists(select 1 from public.repair_payment_corrections c
     where c.org_id=p.org_id and c.case_id=p.case_id and c.payment_id=p.id);
  select v_paid+coalesce(sum(amount_irr),0) into v_paid from public.repair_payment_credit_transfers
   where org_id=p_org_id and case_id=p_case_id and target_plan_id=v_plan.id and approved_at is not null;
  if v_paid<>v_plan.amount_irr then raise exception 'REPAIR_PAYMENT_UNSETTLED' using errcode='23514'; end if;
 elsif v_plan.financial_basis<>'warranty' or v_plan.amount_irr<>0 then
  raise exception 'REPAIR_FINANCIAL_BASIS_UNRESOLVED' using errcode='23514'; end if;
 select * into v_test from public.repair_functional_tests where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_check from public.repair_outgoing_checks where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_test.id is null or not v_test.passed or v_check.id is null
  or v_check.plan_id<>v_plan.id or v_check.functional_test_id<>v_test.id
  or v_test.plan_id<>v_plan.id or v_check.device_id<>v_case.verified_device_id
  or v_check.custody_damage_epoch<>v_case.custody_damage_epoch
  or (p_stage='test' and v_check.recorded_at<v_case.stage_entered_at)
  or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass)
  or not exists(select 1 from public.repair_functional_test_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.test_id=v_test.id)
  or not exists(select 1 from public.repair_outgoing_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.check_id=v_check.id) then
  raise exception 'REPAIR_OUTGOING_RELEASE_REQUIRED' using errcode='23514'; end if;
 if p_stage='delivery' and not exists(select 1 from public.repair_case_events e
   where e.org_id=p_org_id and e.case_id=p_case_id and e.event_type='stage_transition'
    and e.details->>'transitionCode'='T08' and e.details->>'repairOutgoingCheckId'=v_check.id::text
    and e.occurred_at<=v_case.stage_entered_at) then
  raise exception 'REPAIR_DELIVERY_TRANSITION_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_case_assignment_requests a where a.org_id=p_org_id and a.case_id=p_case_id and a.status='pending')
 or exists(select 1 from public.repair_device_custody_transfers t where t.org_id=p_org_id and t.device_id=v_case.verified_device_id and t.status='in_transit')
 or exists(select 1 from public.repair_device_custody_discrepancies d where d.org_id=p_org_id and d.device_id=v_case.verified_device_id and d.status='open') then
  raise exception 'DELIVERY_BLOCKERS_OPEN' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id;
 if v_position.device_id is null or v_position.case_id<>p_case_id
  or (p_stage='test' and (v_position.holder_kind<>'staff' or v_position.custodian_user_id is null))
  or (p_stage='delivery' and v_position.holder_kind not in ('staff','carrier','recipient')) then
  raise exception 'DELIVERY_CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 return v_check.id;
end; $$;
