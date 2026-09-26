-- In-person handover of a zero-cost return, followed by a separate close command.
insert into public.permissions (key,label_fa,description_fa,scope_options) values
 ('repair.delivery.receive','ثبت رسید تحویل حضوری','ثبت دریافت واقعی دستگاه عودتی توسط گیرنده','{}'),
 ('case.close','بستن پرونده تعمیر','بستن پرونده فقط پس از رسید معتبر و رفع مانع‌ها','{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
and p.key in ('repair.delivery.receive','case.close')
on conflict (role_id,permission_key) do nothing;

create table public.repair_delivery_receipts (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null,
 case_id uuid not null,
 device_id uuid not null,
 outgoing_check_id uuid not null,
 method text not null check (method='in_person'),
 recipient_name text not null check (length(btrim(recipient_name)) between 1 and 160),
 recipient_role text not null check (recipient_role in ('owner','authorized_representative','colleague')),
 authority_reference text,
 receipt_reference text not null check (length(btrim(receipt_reference)) between 1 and 160),
 receipt_evidence text not null check (length(btrim(receipt_evidence)) between 1 and 240),
 handed_over_by uuid not null references auth.users(id),
 received_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique (org_id,case_id),
 unique (org_id,receipt_reference),
 unique (org_id,case_id,id),
 foreign key (org_id,case_id) references public.repair_cases(org_id,id),
 foreign key (org_id,device_id) references public.repair_devices(org_id,id),
 foreign key (org_id,case_id,outgoing_check_id) references public.repair_return_outgoing_checks(org_id,case_id,id),
 check ((recipient_role='owner' and authority_reference is null)
   or (recipient_role<>'owner' and length(btrim(authority_reference)) between 1 and 240))
);
create index repair_delivery_receipts_case_idx on public.repair_delivery_receipts(org_id,case_id,received_at desc);
alter table public.repair_delivery_receipts enable row level security;
create policy repair_delivery_receipts_select on public.repair_delivery_receipts for select to authenticated
 using (private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_delivery_receipts from public,anon,authenticated;
grant select on public.repair_delivery_receipts to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
check (event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved',
'custody_baseline_recorded','custody_released','custody_accepted','custody_returned',
'custody_discrepancy_recorded','custody_discrepancy_resolved','delivery_received'));

create function private.assert_return_handover_ready(p_org_id uuid,p_case_id uuid)
returns uuid language plpgsql set search_path='' as $$
declare v_case public.repair_cases; v_plan public.repair_action_plans;
 v_check public.repair_return_outgoing_checks;
begin
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id;
 if v_case.id is null or v_case.stage<>'delivery' or v_case.verified_device_id is null then
   raise exception 'DELIVERY_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_plan.id is null or v_plan.route<>'return' or v_plan.financial_basis<>'none' or v_plan.amount_irr<>0 then
   raise exception 'RETURN_ZERO_COST_REQUIRED' using errcode='23514'; end if;
 select * into v_check from public.repair_return_outgoing_checks where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_check.id is null or v_check.plan_id<>v_plan.id or v_check.device_id<>v_case.verified_device_id
  or v_check.custody_damage_epoch<>v_case.custody_damage_epoch
  or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass)
  or not exists (select 1 from public.repair_return_outgoing_releases r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.check_id=v_check.id)
  or not exists (select 1 from public.repair_case_events e where e.org_id=p_org_id and e.case_id=p_case_id
    and e.event_type='stage_transition' and e.details->>'transitionCode'='T08'
    and e.details->>'outgoingCheckId'=v_check.id::text and e.occurred_at>=v_check.created_at) then
   raise exception 'DELIVERY_QC_REQUIRED' using errcode='23514'; end if;
 if exists (select 1 from public.repair_case_assignment_requests a
   where a.org_id=p_org_id and a.case_id=p_case_id and a.status='pending')
 or exists (select 1 from public.repair_device_custody_transfers t
   where t.org_id=p_org_id and t.device_id=v_case.verified_device_id and t.status='in_transit')
 or exists (select 1 from public.repair_device_custody_discrepancies d
   where d.org_id=p_org_id and d.device_id=v_case.verified_device_id and d.status='open') then
   raise exception 'DELIVERY_BLOCKERS_OPEN' using errcode='23514'; end if;
 return v_check.id;
end;
$$;
revoke all on function private.assert_return_handover_ready(uuid,uuid) from public,anon,authenticated;

create function public.record_repair_delivery_receipt(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_recipient_name text,p_recipient_role text,p_authority_reference text,
 p_receipt_reference text,p_receipt_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_check public.repair_return_outgoing_checks;
 v_position public.repair_device_custody_positions; v_saved private.repair_command_receipts;
 v_hash text; v_check_id uuid; v_receipt public.repair_delivery_receipts; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.delivery.receive') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1
 or length(btrim(coalesce(p_recipient_name,''))) not between 1 and 160
 or p_recipient_role not in ('owner','authorized_representative','colleague')
 or length(btrim(coalesce(p_receipt_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_receipt_evidence,''))) not between 1 and 240
 or (p_recipient_role='owner' and p_authority_reference is not null)
 or (p_recipient_role<>'owner' and length(btrim(coalesce(p_authority_reference,''))) not between 1 and 240) then
  raise exception 'INVALID_DELIVERY_RECEIPT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,
  'recipient',btrim(p_recipient_name),'role',p_recipient_role,'authority',p_authority_reference,
  'reference',btrim(p_receipt_reference),'evidence',btrim(p_receipt_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.delivery:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='delivery.receive' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_return_handover_ready(p_org_id,p_case_id);
 select * into v_check from public.repair_return_outgoing_checks where id=v_check_id;
 if v_check.intended_recipient<>btrim(p_recipient_name) or v_check.recipient_role<>p_recipient_role
 or v_check.authority_reference is distinct from p_authority_reference then
  raise exception 'DELIVERY_RECIPIENT_MISMATCH' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.device_id is null or v_position.case_id<>p_case_id or v_position.custodian_user_id<>v_actor then
  raise exception 'DELIVERY_CUSTODIAN_REQUIRED' using errcode='23514'; end if;
 if exists (select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'DELIVERY_ALREADY_RECEIVED' using errcode='23505'; end if;
 insert into public.repair_delivery_receipts(org_id,case_id,device_id,outgoing_check_id,method,
  recipient_name,recipient_role,authority_reference,receipt_reference,receipt_evidence,handed_over_by)
 values(p_org_id,p_case_id,v_case.verified_device_id,v_check_id,'in_person',btrim(p_recipient_name),
  p_recipient_role,p_authority_reference,btrim(p_receipt_reference),btrim(p_receipt_evidence),v_actor)
 returning * into v_receipt;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_received',v_actor,pg_catalog.jsonb_build_object(
  'receiptId',v_receipt.id,'outgoingCheckId',v_check_id,'recipient',v_receipt.recipient_name,
  'role',v_receipt.recipient_role,'reference',v_receipt.receipt_reference));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'receiptId',v_receipt.id,'version',v_case.version+1);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.receive',p_idempotency_key,v_hash,v_response);
 return v_response;
end;
$$;
revoke all on function public.record_repair_delivery_receipt(uuid,uuid,integer,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.record_repair_delivery_receipt(uuid,uuid,integer,uuid,text,text,text,text,text) to authenticated;

create function public.close_repair_return_case(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_receipt public.repair_delivery_receipts;
 v_saved private.repair_command_receipts; v_hash text; v_check_id uuid; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'case.close') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 then
  raise exception 'INVALID_TRANSITION_INPUT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,'transitionCode','T09')::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.close:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='transition' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_return_handover_ready(p_org_id,p_case_id);
 select * into v_receipt from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id;
 if v_receipt.id is null or v_receipt.outgoing_check_id<>v_check_id
 or v_receipt.device_id<>v_case.verified_device_id or v_receipt.received_at<v_case.stage_entered_at then
  raise exception 'DELIVERY_RECEIPT_REQUIRED' using errcode='23514'; end if;
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_cases set stage='closed',stage_entered_at=v_at,closed_at=v_at,version=version+1
  where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,pg_catalog.jsonb_build_object(
  'transitionCode','T09','from','delivery','to','closed','outcome','returned_unrepaired',
  'deliveryReceiptId',v_receipt.id,'outgoingCheckId',v_check_id));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','closed','version',v_case.version+1,'transitionCode','T09');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end;
$$;
revoke all on function public.close_repair_return_case(uuid,uuid,integer,uuid) from public,anon;
grant execute on function public.close_repair_return_case(uuid,uuid,integer,uuid) to authenticated;

-- Block a privileged direct stage write that omits the receipt or current QC.
create function private.guard_repair_return_closure() returns trigger language plpgsql set search_path='' as $$
declare v_check_id uuid;
begin
 if old.stage='delivery' and new.stage='closed' and exists (
   select 1 from public.repair_action_plans p where p.org_id=new.org_id and p.case_id=new.id
   and p.route='return' and p.revision=(select max(p2.revision) from public.repair_action_plans p2
     where p2.org_id=p.org_id and p2.case_id=p.case_id)) then
  v_check_id:=private.assert_return_handover_ready(new.org_id,new.id);
  if not exists(select 1 from public.repair_delivery_receipts r where r.org_id=new.org_id
    and r.case_id=new.id and r.device_id=new.verified_device_id and r.outgoing_check_id=v_check_id
    and r.received_at>=old.stage_entered_at) then
    raise exception 'DELIVERY_RECEIPT_REQUIRED' using errcode='23514'; end if;
 end if;
 return new;
end;
$$;
create trigger repair_return_closure_guard before update of stage on public.repair_cases
for each row execute function private.guard_repair_return_closure();
