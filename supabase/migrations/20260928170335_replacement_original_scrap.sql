-- Actual scrap is terminal physical disposition; approval is a separate second-person decision.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.replacement.scrap.record','ثبت اجرای اسقاط دستگاه اولیه','ثبت مدرک اجرای واقعی اسقاط توسط نگهدارنده فعلی','{}'),
 ('repair.replacement.scrap.approve','تأیید اجرای اسقاط دستگاه اولیه','تأیید مستقل توسط فردی متفاوت از ثبت‌کننده','{}') on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null and p.key in
 ('repair.replacement.scrap.record','repair.replacement.scrap.approve') on conflict(role_id,permission_key) do nothing;
create table public.repair_replacement_scraps (
 id uuid primary key default gen_random_uuid(),org_id uuid not null,case_id uuid not null,
 execution_id uuid not null,original_device_id uuid not null,location text not null,
 reference text not null check(length(btrim(reference)) between 1 and 160),
 evidence text not null check(length(btrim(evidence)) between 1 and 240),
 note text not null check(length(btrim(note)) between 1 and 500),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 approved_by uuid references auth.users(id),approved_at timestamptz,
 unique(org_id,case_id),unique(org_id,original_device_id),unique(org_id,reference),
 foreign key(org_id,case_id,execution_id) references public.repair_replacement_executions(org_id,case_id,id),
 foreign key(org_id,original_device_id) references public.repair_devices(org_id,id),
 check((approved_by is null and approved_at is null) or
  (approved_by is not null and approved_at is not null and approved_by<>recorded_by and approved_at>=recorded_at))
);
alter table public.repair_replacement_scraps enable row level security;
create policy replacement_scrap_view on public.repair_replacement_scraps for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_replacement_scraps from public,anon,authenticated;
grant select on public.repair_replacement_scraps to authenticated;
alter table public.repair_device_custody_positions drop constraint repair_device_custody_holder_check;
alter table public.repair_device_custody_positions add constraint repair_device_custody_holder_check check (
 (holder_kind='staff' and custodian_user_id is not null and external_reference is null)
 or (holder_kind in ('carrier','recipient','scrapped') and custodian_user_id is null
  and external_reference is not null and length(btrim(external_reference)) between 1 and 160));

create function private.guard_scrapped_device_custody() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
  if old.holder_kind='scrapped' then raise exception 'DEVICE_SCRAPPED' using errcode='23514'; end if;
  return old;
 end if;
 if tg_op='UPDATE' and old.holder_kind='scrapped' then
  raise exception 'DEVICE_SCRAPPED' using errcode='23514'; end if;
 if new.holder_kind='scrapped' and not exists(select 1 from public.repair_replacement_scraps s
  where s.org_id=new.org_id and s.case_id=new.case_id and s.original_device_id=new.device_id
   and s.reference=new.external_reference and s.recorded_at=new.confirmed_at and s.location=new.location) then
  raise exception 'SCRAP_EXECUTION_REQUIRED' using errcode='23514'; end if;
 return new;
end; $$;
create trigger guard_scrapped_device_custody before insert or update or delete on public.repair_device_custody_positions
 for each row execute function private.guard_scrapped_device_custody();
create function private.guard_scrapped_device_intake() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.verified_device_id is not null and (tg_op='INSERT' or new.verified_device_id is distinct from old.verified_device_id)
  and exists(select 1 from public.repair_replacement_scraps s where s.org_id=new.org_id and s.original_device_id=new.verified_device_id) then
  raise exception 'DEVICE_SCRAPPED' using errcode='23514'; end if;
 return new;
end; $$;
create trigger guard_scrapped_device_intake before insert or update of verified_device_id on public.repair_cases
 for each row execute function private.guard_scrapped_device_intake();
revoke all on function private.guard_scrapped_device_custody(),private.guard_scrapped_device_intake() from public,anon,authenticated;
create or replace function private.assert_replacement_issued_ready(p_org_id uuid,p_case_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_case public.repair_cases; v_plan public.repair_action_plans;
 v_execution public.repair_replacement_executions; v_stock public.repair_replacement_stock;
 v_test public.repair_functional_tests; v_check public.repair_outgoing_checks;
 v_position public.repair_device_custody_positions; v_original public.repair_device_custody_positions;
 v_paid bigint;
begin
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id;
 if v_case.id is null or v_case.stage<>'delivery' or v_case.verified_device_id is null then
  raise exception 'REPLACEMENT_DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 if v_plan.id is null or v_plan.route<>'replacement' or v_execution.id is null
  or v_execution.plan_id<>v_plan.id or v_execution.original_device_id<>v_case.verified_device_id
  or v_execution.original_disposition_pending<>v_plan.original_disposition
  or v_execution.executed_at>v_case.stage_entered_at then
  raise exception 'REPLACEMENT_EXECUTION_REQUIRED' using errcode='23514'; end if;
 select * into v_stock from public.repair_replacement_stock where org_id=p_org_id and device_id=v_execution.replacement_device_id;
 if v_stock.device_id is null or v_stock.status<>'issued' or v_stock.allocated_case_id<>p_case_id
  or v_stock.allocated_plan_id<>v_plan.id then
  raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 if v_plan.financial_basis='customer_paid' then
  select coalesce(sum(p.amount_irr),0) into v_paid from public.repair_payment_evidence p
   join public.repair_payment_verifications v on v.org_id=p.org_id and v.case_id=p.case_id and v.payment_id=p.id
   where p.org_id=p_org_id and p.case_id=p_case_id and p.plan_id=v_plan.id
    and not exists(select 1 from public.repair_payment_corrections c
      where c.org_id=p.org_id and c.case_id=p.case_id and c.payment_id=p.id);
  select v_paid-coalesce(sum(r.amount_irr),0) into v_paid
   from public.repair_payment_refunds r join public.repair_payment_evidence p
    on p.org_id=r.org_id and p.case_id=r.case_id and p.id=r.source_payment_id
   where r.org_id=p_org_id and r.case_id=p_case_id and p.plan_id=v_plan.id and r.approved_at is not null;
  select v_paid+coalesce(sum(amount_irr),0) into v_paid from public.repair_payment_credit_transfers
   where org_id=p_org_id and case_id=p_case_id and target_plan_id=v_plan.id and approved_at is not null;
  if v_paid<>v_plan.amount_irr then raise exception 'REPLACEMENT_PAYMENT_UNSETTLED' using errcode='23514'; end if;
 elsif v_plan.financial_basis<>'warranty' or v_plan.amount_irr<>0 then
  raise exception 'REPLACEMENT_FINANCIAL_BASIS_UNRESOLVED' using errcode='23514'; end if;
 select * into v_test from public.repair_functional_tests where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 select * into v_check from public.repair_outgoing_checks where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_test.id is null or not v_test.passed or v_test.protocol_code<>'replacement_functional_v1'
  or v_test.plan_id<>v_plan.id or v_test.execution_id<>v_execution.id
  or v_test.device_id<>v_execution.replacement_device_id
  or v_test.custody_damage_epoch<>v_case.custody_damage_epoch
  or (v_case.stage='test' and v_test.recorded_at<v_case.stage_entered_at)
  or v_check.id is null or v_check.protocol_code<>'replacement_outgoing_v1'
  or v_check.plan_id<>v_plan.id or v_check.functional_test_id<>v_test.id
  or v_check.device_id<>v_execution.replacement_device_id
  or v_check.custody_damage_epoch<>v_case.custody_damage_epoch
  or (v_case.stage='test' and v_check.recorded_at<v_case.stage_entered_at)
  or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass)
  or not exists(select 1 from public.repair_functional_test_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.test_id=v_test.id)
  or not exists(select 1 from public.repair_outgoing_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.check_id=v_check.id) then
  raise exception 'REPLACEMENT_OUTGOING_RELEASE_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_case_assignment_requests a where a.org_id=p_org_id and a.case_id=p_case_id and a.status='pending')
  or exists(select 1 from public.repair_device_custody_transfers t where t.org_id=p_org_id
   and t.device_id in (v_case.verified_device_id,v_execution.replacement_device_id) and t.status='in_transit')
  or exists(select 1 from public.repair_device_custody_discrepancies d where d.org_id=p_org_id
   and d.device_id in (v_case.verified_device_id,v_execution.replacement_device_id) and d.status='open') then
  raise exception 'DELIVERY_BLOCKERS_OPEN' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and case_id=p_case_id and device_id=v_execution.replacement_device_id;
 select * into v_original from public.repair_device_custody_positions
  where org_id=p_org_id and case_id=p_case_id and device_id=v_case.verified_device_id;
 if v_position.device_id is null or v_position.holder_kind<>'recipient'
  or v_original.device_id is null or (v_original.holder_kind not in ('staff','recipient') and not (v_original.holder_kind='scrapped' and exists(
   select 1 from public.repair_replacement_scraps s where s.org_id=p_org_id and s.case_id=p_case_id
    and s.execution_id=v_execution.id and s.original_device_id=v_case.verified_device_id
    and s.reference=v_original.external_reference and s.recorded_at=v_original.confirmed_at and s.location=v_original.location)))
  or not exists(select 1 from public.repair_delivery_receipts r where r.org_id=p_org_id and r.case_id=p_case_id
   and r.id=v_stock.issued_receipt_id and r.device_id=v_execution.replacement_device_id
   and r.repair_outgoing_check_id=v_check.id
   and (r.method='in_person' or exists(select 1 from public.repair_delivery_dispatches d
     where d.org_id=r.org_id and d.case_id=r.case_id and d.id=r.dispatch_id and d.status='in_transit'
      and d.device_id=r.device_id and d.repair_outgoing_check_id=r.repair_outgoing_check_id
      and d.method=r.method and d.destination_name=r.recipient_name and d.destination_role=r.recipient_role
      and d.authority_reference is not distinct from r.authority_reference
      and d.dispatched_by=r.handed_over_by and r.received_at>=d.dispatched_at
      and r.receipt_reference<>d.dispatch_reference and r.receipt_evidence<>d.dispatch_evidence))
   and r.received_at>=v_case.stage_entered_at and r.received_at=v_stock.issued_at
   and r.receipt_reference=v_position.external_reference) then
  raise exception 'REPLACEMENT_DELIVERY_RECEIPT_REQUIRED' using errcode='23514'; end if;
 if v_case.stage='delivery' and not exists(select 1 from public.repair_case_events e
  where e.org_id=p_org_id and e.case_id=p_case_id and e.event_type='stage_transition'
   and e.details->>'transitionCode'='T08'
   and e.details->>'replacementOutgoingCheckId'=v_check.id::text
   and e.occurred_at=v_case.stage_entered_at) then
  raise exception 'REPLACEMENT_DELIVERY_TRANSITION_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_incidents i where i.org_id=p_org_id
  and i.case_id=p_case_id and i.status='open') then
  raise exception 'DELIVERY_INCIDENT_OPEN' using errcode='23514'; end if;
 return v_check.id;
end; $$;


create function public.record_replacement_scrap(p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,p_reference text,p_evidence text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_case public.repair_cases;v_execution public.repair_replacement_executions;
 v_position public.repair_device_custody_positions;v_scrap public.repair_replacement_scraps;
 v_saved private.repair_command_receipts;v_hash text;v_response jsonb;v_at timestamptz;
begin
 if v_actor is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.replacement.scrap.record') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or p_idempotency_key is null or length(btrim(coalesce(p_reference,''))) not between 1 and 160 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240 or length(btrim(coalesce(p_note,''))) not between 1 and 500 then
  raise exception 'INVALID_SCRAP_INPUT' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'version',p_expected_version,'reference',btrim(p_reference),'evidence',btrim(p_evidence),'note',btrim(p_note))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('replacement.scrap.record:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='replacement.scrap.record' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 perform private.assert_replacement_issued_ready(p_org_id,p_case_id);
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 if v_execution.original_disposition_pending<>'scrap_proposed' then raise exception 'SCRAP_PLAN_REQUIRED' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 v_at:=clock_timestamp();
 if v_position.device_id is null or v_position.case_id<>p_case_id or v_position.holder_kind<>'staff'
  or v_position.custodian_user_id is distinct from v_actor then raise exception 'SCRAP_CUSTODIAN_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_replacement_scraps where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'SCRAP_ALREADY_RECORDED' using errcode='23514'; end if;
 insert into public.repair_replacement_scraps(org_id,case_id,execution_id,original_device_id,location,reference,evidence,note,recorded_by,recorded_at)
 values(p_org_id,p_case_id,v_execution.id,v_case.verified_device_id,v_position.location,btrim(p_reference),btrim(p_evidence),btrim(p_note),v_actor,v_at)
 returning * into v_scrap;
 update public.repair_device_custody_positions set holder_kind='scrapped',custodian_user_id=null,
  custodian_label='اسقاط‌شده',external_reference=v_scrap.reference,confirmed_at=v_at,confirmed_by=v_actor
  where org_id=p_org_id and device_id=v_case.verified_device_id;
 update public.repair_cases set device_custodian='اسقاط‌شده' where org_id=p_org_id and id=p_case_id;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'custody_accepted',v_actor,v_at,
  jsonb_build_object('operation','replacement.scrap.record','scrapId',v_scrap.id,'deviceRole','original','deviceId',v_case.verified_device_id,
   'scrap',(select to_jsonb(s) from public.repair_replacement_scraps s where s.id=v_scrap.id)));
 v_response:=jsonb_build_object('caseId',p_case_id,'scrapId',v_scrap.id,'version',v_case.version+1);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.scrap.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_replacement_scrap(uuid,uuid,integer,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.record_replacement_scrap(uuid,uuid,integer,uuid,text,text,text) to authenticated;

create function public.approve_replacement_scrap(p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,p_scrap_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v_case public.repair_cases;v_execution public.repair_replacement_executions;
 v_position public.repair_device_custody_positions;v_scrap public.repair_replacement_scraps;
 v_saved private.repair_command_receipts;v_hash text;v_response jsonb;v_at timestamptz;
begin
 if v_actor is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.replacement.scrap.approve') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or p_idempotency_key is null or p_scrap_id is null then
  raise exception 'INVALID_SCRAP_INPUT' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'version',p_expected_version,'scrap',p_scrap_id)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('replacement.scrap.approve:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='replacement.scrap.approve' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 perform private.assert_replacement_issued_ready(p_org_id,p_case_id);
 select * into v_execution from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1;
 if v_execution.original_disposition_pending<>'scrap_proposed' then raise exception 'SCRAP_PLAN_REQUIRED' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 v_at:=clock_timestamp();
 select * into v_scrap from public.repair_replacement_scraps where org_id=p_org_id and case_id=p_case_id and id=p_scrap_id for update;
 if v_scrap.id is null or v_scrap.execution_id<>v_execution.id or v_scrap.original_device_id<>v_case.verified_device_id
  or v_position.holder_kind<>'scrapped' or v_position.external_reference<>v_scrap.reference
  or v_position.confirmed_at<>v_scrap.recorded_at or v_position.location<>v_scrap.location then
  raise exception 'SCRAP_EXECUTION_REQUIRED' using errcode='23514'; end if;
 if v_scrap.recorded_by=v_actor then raise exception 'SCRAP_SECOND_PERSON_REQUIRED' using errcode='42501'; end if;
 if v_scrap.approved_at is not null then raise exception 'SCRAP_ALREADY_APPROVED' using errcode='23514'; end if;
 update public.repair_replacement_scraps set approved_by=v_actor,approved_at=v_at where id=v_scrap.id;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'plan_approval_recorded',v_actor,v_at,
  jsonb_build_object('operation','replacement.scrap.approve','scrapId',v_scrap.id,'deviceRole','original','deviceId',v_case.verified_device_id,
   'scrap',(select to_jsonb(s) from public.repair_replacement_scraps s where s.id=v_scrap.id)));
 v_response:=jsonb_build_object('caseId',p_case_id,'scrapId',v_scrap.id,'version',v_case.version+1);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.scrap.approve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.approve_replacement_scrap(uuid,uuid,integer,uuid,uuid) from public,anon,authenticated;
grant execute on function public.approve_replacement_scrap(uuid,uuid,integer,uuid,uuid) to authenticated;
create or replace function private.assert_replacement_close_ready(p_org_id uuid,p_case_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_check uuid; v_return public.repair_replacement_original_returns; v_warehouse public.repair_replacement_warehouse_receipts; v_scrap public.repair_replacement_scraps;
begin
 v_check:=private.assert_replacement_issued_ready(p_org_id,p_case_id);
 select * into v_scrap from public.repair_replacement_scraps where org_id=p_org_id and case_id=p_case_id;
 if v_scrap.id is not null then
  if v_scrap.approved_at is null or v_scrap.approved_by is null or v_scrap.approved_by=v_scrap.recorded_by
   or not exists(select 1 from public.repair_replacement_executions x
    join public.repair_device_custody_positions pos on pos.org_id=x.org_id and pos.device_id=x.original_device_id
    where x.org_id=p_org_id and x.case_id=p_case_id and x.id=v_scrap.execution_id
     and x.original_disposition_pending='scrap_proposed' and x.original_device_id=v_scrap.original_device_id
     and x.id=(select id from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1)
     and pos.case_id=p_case_id and pos.holder_kind='scrapped' and pos.external_reference=v_scrap.reference
     and pos.confirmed_at=v_scrap.recorded_at and pos.location=v_scrap.location) then
   raise exception 'SCRAP_APPROVAL_REQUIRED' using errcode='23514'; end if;
  return v_scrap.id;
 end if;
 select * into v_warehouse from public.repair_replacement_warehouse_receipts where org_id=p_org_id and case_id=p_case_id;
 if v_warehouse.id is not null then
  if not exists(select 1 from public.repair_replacement_executions x
   join public.repair_cases c on c.org_id=x.org_id and c.id=x.case_id
   join public.repair_device_custody_positions pos on pos.org_id=x.org_id and pos.device_id=x.original_device_id
   join public.repair_device_custody_transfers t on t.org_id=x.org_id and t.id=v_warehouse.transfer_id
   where x.org_id=p_org_id and x.case_id=p_case_id and x.id=v_warehouse.execution_id
    and x.id=(select id from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1)
    and x.original_device_id=v_warehouse.original_device_id and c.verified_device_id=v_warehouse.original_device_id
    and v_warehouse.disposition=case x.original_disposition_pending when 'parts_proposed' then 'parts_received' when 'refurbish_proposed' then 'refurbish_received' end
    and pos.case_id=p_case_id and pos.holder_kind='staff' and pos.location=v_warehouse.location
    and pos.custodian_user_id=v_warehouse.received_by and pos.confirmed_at=t.resolved_at
    and t.case_id=p_case_id and t.device_id=v_warehouse.original_device_id and t.status='accepted'
    and t.destination_user_id=v_warehouse.received_by and t.resolved_by=v_warehouse.received_by
    and t.destination_location=v_warehouse.location and t.resolution_reference=v_warehouse.receipt_reference
    and t.resolution_evidence=v_warehouse.receipt_evidence and t.resolved_at>=x.executed_at) then
   raise exception 'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' using errcode='23514'; end if;
  return v_warehouse.id;
 end if;
 select * into v_return from public.repair_replacement_original_returns where org_id=p_org_id and case_id=p_case_id;
 if v_return.id is null or not exists(select 1 from public.repair_replacement_executions x
  join public.repair_device_custody_positions pos on pos.org_id=x.org_id and pos.device_id=x.original_device_id
  join public.repair_cases c on c.org_id=x.org_id and c.id=x.case_id
  join public.repair_delivery_receipts r on r.org_id=x.org_id and r.case_id=x.case_id
  where x.org_id=p_org_id and x.case_id=p_case_id and x.id=v_return.execution_id
   and x.original_disposition_pending='return_to_customer' and x.original_device_id=v_return.original_device_id
   and x.id=(select id from public.repair_replacement_executions where org_id=p_org_id and case_id=p_case_id order by executed_at desc limit 1)
   and c.verified_device_id=v_return.original_device_id and pos.case_id=p_case_id
   and pos.holder_kind='recipient' and pos.external_reference=v_return.receipt_reference
   and v_return.returned_at>=r.received_at and v_return.recipient_name=r.recipient_name
   and v_return.recipient_role=r.recipient_role and v_return.authority_reference is not distinct from r.authority_reference) then
  raise exception 'REPLACEMENT_ORIGINAL_DISPOSITION_REQUIRED' using errcode='23514'; end if;
 return v_return.id;
end; $$;
revoke all on function private.assert_replacement_close_ready(uuid,uuid) from public,anon,authenticated;
create or replace function public.close_replacement_case(p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_receipt public.repair_delivery_receipts;
 v_saved private.repair_command_receipts; v_hash text; v_check_id uuid; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_idempotency_key is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'case.close') then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 then raise exception 'INVALID_TRANSITION_INPUT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,'transitionCode','T09')::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.close:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='transition' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_replacement_close_ready(p_org_id,p_case_id);
 select * into v_receipt from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id;
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_cases set stage='closed',stage_entered_at=v_at,closed_at=v_at,version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,pg_catalog.jsonb_build_object('transitionCode','T09','from','delivery','to','closed',
  'scrapId',(select id from public.repair_replacement_scraps where org_id=p_org_id and case_id=p_case_id),
  'outcome',coalesce((select 'replaced_original_scrapped' from public.repair_replacement_scraps where org_id=p_org_id and case_id=p_case_id),(select 'replaced_original_'||disposition from public.repair_replacement_warehouse_receipts where org_id=p_org_id and case_id=p_case_id),'replaced_original_returned'),'deliveryReceiptId',v_receipt.id,
  'originalReturnId',(select id from public.repair_replacement_original_returns where org_id=p_org_id and case_id=p_case_id),
  'warehouseReceiptId',(select id from public.repair_replacement_warehouse_receipts where org_id=p_org_id and case_id=p_case_id)));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','closed','version',v_case.version+1,'transitionCode','T09');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.close_replacement_case(uuid,uuid,integer,uuid) from public,anon;
grant execute on function public.close_replacement_case(uuid,uuid,integer,uuid) to authenticated;

