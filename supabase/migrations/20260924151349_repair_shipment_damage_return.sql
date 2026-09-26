-- One returned shipment is an immutable attempt; a fresh quality cycle may create a new attempt.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.delivery.return_receive','ثبت بازگشت فیزیکی از حمل','ثبت دریافت واقعی دستگاه آسیب‌دیده از حامل و محل و مسئول تازه','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,'repair.delivery.return_receive',null from public.roles r
where r.is_system and r.name='مالک' and r.deleted_at is null
on conflict(role_id,permission_key) do nothing;

alter table public.repair_delivery_dispatches drop constraint repair_delivery_dispatches_org_id_case_id_key;
alter table public.repair_delivery_dispatches add column status text not null default 'in_transit'
 check(status in ('in_transit','returned'));
create unique index repair_delivery_one_in_transit on public.repair_delivery_dispatches(org_id,case_id)
 where status='in_transit';
create index repair_delivery_dispatch_history on public.repair_delivery_dispatches(org_id,case_id,dispatched_at desc);

create table public.repair_delivery_dispatch_returns(
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, device_id uuid not null,
 dispatch_id uuid not null, incident_id uuid not null,
 location text not null check(length(btrim(location)) between 1 and 200),
 condition_note text not null check(length(btrim(condition_note)) between 1 and 1000),
 return_reference text not null check(length(btrim(return_reference)) between 1 and 160),
 return_evidence text not null check(length(btrim(return_evidence)) between 1 and 240),
 received_by uuid not null references auth.users(id),
 received_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,dispatch_id), unique(org_id,incident_id), unique(org_id,return_reference),
 foreign key(org_id,case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,device_id) references public.repair_devices(org_id,id),
 foreign key(org_id,case_id,dispatch_id) references public.repair_delivery_dispatches(org_id,case_id,id),
 foreign key(org_id,case_id,incident_id) references public.repair_delivery_incidents(org_id,case_id,id)
);
create index repair_delivery_returns_case on public.repair_delivery_dispatch_returns(org_id,case_id,received_at desc);
alter table public.repair_delivery_dispatch_returns enable row level security;
create policy repair_delivery_dispatch_returns_select on public.repair_delivery_dispatch_returns for select to authenticated
using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_delivery_dispatch_returns from public,anon,authenticated;
grant select on public.repair_delivery_dispatch_returns to authenticated;

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
'delivery_damage_returned'));


create or replace function private.guard_repair_delivery_receipt_path() returns trigger
language plpgsql set search_path='' as $$
declare v_dispatch public.repair_delivery_dispatches;
begin
 if new.method='in_person' then
  if exists(select 1 from public.repair_delivery_dispatches d where d.org_id=new.org_id and d.case_id=new.case_id and d.status='in_transit') then
   raise exception 'DELIVERY_ALREADY_DISPATCHED' using errcode='23514'; end if;
 else
  select * into v_dispatch from public.repair_delivery_dispatches where org_id=new.org_id and case_id=new.case_id and id=new.dispatch_id;
  if v_dispatch.id is null or v_dispatch.status<>'in_transit' or v_dispatch.method<>new.method or v_dispatch.device_id<>new.device_id
   or v_dispatch.outgoing_check_id<>new.outgoing_check_id
   or v_dispatch.destination_name<>new.recipient_name or v_dispatch.destination_role<>new.recipient_role
   or v_dispatch.authority_reference is distinct from new.authority_reference
   or new.received_at<v_dispatch.dispatched_at
   or new.receipt_reference=v_dispatch.dispatch_reference
   or new.receipt_evidence=v_dispatch.dispatch_evidence then
   raise exception 'DELIVERY_DISPATCH_MISMATCH' using errcode='23514'; end if;
 end if;
 return new;
end;
$$;

create or replace function private.guard_repair_transfer_after_delivery() returns trigger
language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.repair_delivery_dispatches d where d.org_id=new.org_id and d.case_id=new.case_id and d.device_id=new.device_id and d.status='in_transit')
 or exists(select 1 from public.repair_delivery_receipts r where r.org_id=new.org_id and r.case_id=new.case_id and r.device_id=new.device_id) then
  raise exception 'DELIVERY_DEVICE_ALREADY_RELEASED' using errcode='23514'; end if;
 return new;
end;
$$;

create or replace function public.record_repair_delivery_dispatch(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_method text,p_carrier text,p_destination_address text,p_tracking_code text,
 p_dispatch_reference text,p_dispatch_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_check public.repair_return_outgoing_checks;
 v_position public.repair_device_custody_positions; v_saved private.repair_command_receipts;
 v_hash text; v_check_id uuid; v_dispatch public.repair_delivery_dispatches; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.delivery.dispatch') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or p_method not in ('post','courier')
 or length(btrim(coalesce(p_carrier,''))) not between 1 and 160
 or length(btrim(coalesce(p_destination_address,''))) not between 1 and 300
 or length(btrim(coalesce(p_tracking_code,''))) not between 1 and 240
 or length(btrim(coalesce(p_dispatch_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_dispatch_evidence,''))) not between 1 and 240 then
  raise exception 'INVALID_DELIVERY_DISPATCH' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'version',p_expected_version,
  'method',p_method,'carrier',btrim(p_carrier),'address',btrim(p_destination_address),
  'tracking',btrim(p_tracking_code),'reference',btrim(p_dispatch_reference),
  'evidence',btrim(p_dispatch_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.dispatch:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='delivery.dispatch' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_return_handover_ready(p_org_id,p_case_id);
 select * into v_check from public.repair_return_outgoing_checks where id=v_check_id;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.device_id is null or v_position.case_id<>p_case_id or v_position.custodian_user_id<>v_actor then
  raise exception 'DELIVERY_CUSTODIAN_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_dispatches where org_id=p_org_id and case_id=p_case_id and status='in_transit') then
  raise exception 'DELIVERY_ALREADY_DISPATCHED' using errcode='23505'; end if;
 if exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'DELIVERY_ALREADY_RECEIVED' using errcode='23505'; end if;
 insert into public.repair_delivery_dispatches(org_id,case_id,device_id,outgoing_check_id,method,
  carrier,destination_name,destination_role,authority_reference,destination_address,
  tracking_code,dispatch_reference,dispatch_evidence,dispatched_by)
 values(p_org_id,p_case_id,v_case.verified_device_id,v_check_id,p_method,btrim(p_carrier),
  v_check.intended_recipient,v_check.recipient_role,v_check.authority_reference,btrim(p_destination_address),
  btrim(p_tracking_code),btrim(p_dispatch_reference),btrim(p_dispatch_evidence),v_actor)
 returning * into v_dispatch;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_dispatched',v_actor,pg_catalog.jsonb_build_object(
  'dispatchId',v_dispatch.id,'outgoingCheckId',v_check_id,'method',p_method,
  'carrier',v_dispatch.carrier,'trackingCode',v_dispatch.tracking_code,
  'recipient',v_dispatch.destination_name,'reference',v_dispatch.dispatch_reference));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'dispatchId',v_dispatch.id,
  'version',v_case.version+1,'deliveryStatus','in_transit');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.dispatch',p_idempotency_key,v_hash,v_response);
 return v_response;
end;
$$;

create or replace function public.confirm_repair_delivery_receipt(
 p_org_id uuid,p_case_id uuid,p_dispatch_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_recipient_name text,p_recipient_role text,p_authority_reference text,
 p_receipt_reference text,p_receipt_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_dispatch public.repair_delivery_dispatches;
 v_saved private.repair_command_receipts; v_hash text; v_check_id uuid;
 v_receipt public.repair_delivery_receipts; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_dispatch_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.delivery.confirm_receipt') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1
 or length(btrim(coalesce(p_recipient_name,''))) not between 1 and 160
 or p_recipient_role not in ('owner','authorized_representative','colleague')
 or (p_recipient_role='owner' and p_authority_reference is not null)
 or (p_recipient_role<>'owner' and length(btrim(coalesce(p_authority_reference,''))) not between 1 and 240)
 or length(btrim(coalesce(p_receipt_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_receipt_evidence,''))) not between 1 and 240 then
  raise exception 'INVALID_DELIVERY_RECEIPT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'dispatchId',p_dispatch_id,
  'version',p_expected_version,'recipient',btrim(p_recipient_name),'role',p_recipient_role,
  'authority',p_authority_reference,'reference',btrim(p_receipt_reference),
  'evidence',btrim(p_receipt_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.delivery.confirm:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='delivery.confirm' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 v_check_id:=private.assert_return_handover_ready(p_org_id,p_case_id);
 select * into v_dispatch from public.repair_delivery_dispatches
  where org_id=p_org_id and case_id=p_case_id and id=p_dispatch_id for update;
 if v_dispatch.id is null or v_dispatch.status<>'in_transit' or v_dispatch.device_id<>v_case.verified_device_id or v_dispatch.outgoing_check_id<>v_check_id
 or v_dispatch.destination_name<>btrim(p_recipient_name) or v_dispatch.destination_role<>p_recipient_role
 or v_dispatch.authority_reference is distinct from p_authority_reference then
  raise exception 'DELIVERY_DISPATCH_MISMATCH' using errcode='23514'; end if;
 if btrim(p_receipt_reference)=v_dispatch.dispatch_reference
 or btrim(p_receipt_evidence)=v_dispatch.dispatch_evidence then
  raise exception 'DELIVERY_INDEPENDENT_RECEIPT_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'DELIVERY_ALREADY_RECEIVED' using errcode='23505'; end if;
 insert into public.repair_delivery_receipts(org_id,case_id,device_id,outgoing_check_id,method,
  recipient_name,recipient_role,authority_reference,receipt_reference,receipt_evidence,
  handed_over_by,dispatch_id,confirmed_by)
 values(p_org_id,p_case_id,v_case.verified_device_id,v_check_id,v_dispatch.method,
  btrim(p_recipient_name),p_recipient_role,p_authority_reference,btrim(p_receipt_reference),btrim(p_receipt_evidence),
  v_dispatch.dispatched_by,v_dispatch.id,v_actor)
 returning * into v_receipt;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_received',v_actor,pg_catalog.jsonb_build_object(
  'receiptId',v_receipt.id,'dispatchId',v_dispatch.id,'outgoingCheckId',v_check_id,
  'recipient',v_receipt.recipient_name,'method',v_dispatch.method,'reference',v_receipt.receipt_reference));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'receiptId',v_receipt.id,
  'version',v_case.version+1,'deliveryStatus','received');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.confirm',p_idempotency_key,v_hash,v_response);
 return v_response;
end;
$$;

create or replace function public.record_repair_delivery_incident(
 p_org_id uuid,p_case_id uuid,p_dispatch_id uuid,p_kind text,p_reference text,p_evidence text,
 p_responsible_user_id uuid,p_due_at timestamptz,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_dispatch public.repair_delivery_dispatches;
 v_item public.repair_delivery_incidents; v_hash text; v_saved private.repair_command_receipts; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_dispatch_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'delivery.incident.record')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_kind not in ('lost','damage','delivery_discrepancy') or p_responsible_user_id is null
 or p_due_at is null or p_due_at<=pg_catalog.clock_timestamp() or p_expected_version is null
 or length(btrim(coalesce(p_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_DELIVERY_INCIDENT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('case',p_case_id,'dispatch',p_dispatch_id,'kind',p_kind,
 'reference',btrim(p_reference),'evidence',btrim(p_evidence),'responsible',p_responsible_user_id,
 'due',p_due_at,'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.delivery.incident.record:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='delivery.incident.record' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_dispatch from public.repair_delivery_dispatches where org_id=p_org_id and case_id=p_case_id and id=p_dispatch_id;
 if v_case.stage<>'delivery' or v_dispatch.id is null or v_dispatch.device_id<>v_case.verified_device_id
 or v_dispatch.status<>'in_transit'
 or exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id)
 then raise exception 'DELIVERY_DISPATCH_NOT_OPEN' using errcode='23514'; end if;
 if not exists(select 1 from public.org_members where org_id=p_org_id and user_id=p_responsible_user_id
 and deleted_at is null and invitation_status='active') then raise exception 'DELIVERY_MEMBER_INACTIVE' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_incidents where org_id=p_org_id and dispatch_id=p_dispatch_id and status='open')
 then raise exception 'DELIVERY_INCIDENT_OPEN' using errcode='23514'; end if;
 insert into public.repair_delivery_incidents(org_id,case_id,device_id,dispatch_id,kind,reference,evidence,responsible_user_id,due_at,recorded_by)
 values(p_org_id,p_case_id,v_dispatch.device_id,p_dispatch_id,p_kind,btrim(p_reference),btrim(p_evidence),p_responsible_user_id,p_due_at,v_actor)
 returning * into v_item;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_incident_recorded',v_actor,pg_catalog.jsonb_build_object(
 'incidentId',v_item.id,'dispatchId',p_dispatch_id,'kind',p_kind,'reference',v_item.reference,
 'responsibleUserId',p_responsible_user_id,'dueAt',p_due_at));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'incidentId',v_item.id,'version',v_case.version,'incidentVersion',v_item.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.incident.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create or replace function public.return_repair_case_to_test_after_damage(
  p_org_id uuid, p_case_id uuid, p_expected_version integer, p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_plan public.repair_action_plans;
  v_check public.repair_return_outgoing_checks;
  v_at timestamptz;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'case.transition.T11') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'INVALID_TRANSITION_INPUT' using errcode = '23514';
  end if;
  v_hash := pg_catalog.md5(pg_catalog.jsonb_build_object('caseId', p_case_id,
    'expectedVersion', p_expected_version, 'transitionCode', 'T11')::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.transition:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'transition' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'delivery' then raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '23514'; end if;
  select * into v_plan from public.repair_action_plans
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  if v_plan.id is null or v_plan.route <> 'return' or v_case.verified_device_id is null then
    raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '23514';
  end if;
  select * into v_check from public.repair_return_outgoing_checks
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  if v_check.id is null or v_check.custody_damage_epoch >= v_case.custody_damage_epoch
     or not exists (select 1 from public.repair_device_custody_discrepancies d
       join public.repair_device_custody_transfers t on t.org_id=d.org_id and t.id=d.transfer_id
       where d.org_id=p_org_id and d.case_id=p_case_id and d.device_id=v_case.verified_device_id
         and d.kind='damage' and d.recorded_at >= v_case.stage_entered_at
         and t.status='returned')
     and not exists(select 1 from public.repair_delivery_dispatch_returns dr
       where dr.org_id=p_org_id and dr.case_id=p_case_id and dr.device_id=v_case.verified_device_id
       and dr.received_at>=v_case.stage_entered_at) then
    raise exception 'CUSTODY_DAMAGE_RETURN_REQUIRED' using errcode = '23514';
  end if;
  v_at := pg_catalog.clock_timestamp();
  update public.repair_cases set stage='test', stage_entered_at=v_at, version=version+1
    where org_id=p_org_id and id=p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, occurred_at, details)
    values (p_org_id, p_case_id, 'stage_transition', v_actor, v_at,
      pg_catalog.jsonb_build_object('transitionCode','T11','from','delivery','to','test',
        'reason','physical_damage_return','previousCheckId',v_check.id,'damageEpoch',v_case.custody_damage_epoch));
  v_response := pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','test',
    'version',v_case.version,'transitionCode','T11');
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
  return v_response;
end;
$$;


create function public.receive_repair_delivery_damage_return(
 p_org_id uuid,p_case_id uuid,p_dispatch_id uuid,p_incident_id uuid,
 p_expected_version integer,p_expected_incident_version integer,p_idempotency_key uuid,
 p_location text,p_condition_note text,p_return_reference text,p_return_evidence text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_dispatch public.repair_delivery_dispatches;
 v_incident public.repair_delivery_incidents; v_position public.repair_device_custody_positions;
 v_return public.repair_delivery_dispatch_returns; v_saved private.repair_command_receipts;
 v_hash text; v_label text; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_dispatch_id is null or p_incident_id is null
 or p_idempotency_key is null or not private.is_org_member(p_org_id)
 or not private.has_permission(p_org_id,'repair.delivery.return_receive') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_incident_version is null
 or length(btrim(coalesce(p_location,''))) not between 1 and 200
 or length(btrim(coalesce(p_condition_note,''))) not between 1 and 1000
 or length(btrim(coalesce(p_return_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_return_evidence,''))) not between 1 and 240 then
  raise exception 'INVALID_DELIVERY_DAMAGE_RETURN' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('case',p_case_id,'dispatch',p_dispatch_id,
  'incident',p_incident_id,'caseVersion',p_expected_version,'incidentVersion',p_expected_incident_version,
  'location',btrim(p_location),'condition',btrim(p_condition_note),
  'reference',btrim(p_return_reference),'evidence',btrim(p_return_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.delivery.damage.return:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='delivery.damage.return' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_dispatch from public.repair_delivery_dispatches
  where org_id=p_org_id and case_id=p_case_id and id=p_dispatch_id for update;
 select * into v_incident from public.repair_delivery_incidents
  where org_id=p_org_id and case_id=p_case_id and id=p_incident_id for update;
 if v_case.stage<>'delivery' or v_case.verified_device_id is null
 or v_dispatch.id is null or v_dispatch.status<>'in_transit' or v_dispatch.device_id<>v_case.verified_device_id
 or v_incident.id is null or v_incident.dispatch_id<>p_dispatch_id or v_incident.kind<>'damage'
 or v_incident.status<>'open'
 or exists(select 1 from public.repair_delivery_receipts where org_id=p_org_id and case_id=p_case_id) then
  raise exception 'DELIVERY_DAMAGE_RETURN_NOT_ALLOWED' using errcode='23514'; end if;
 if v_incident.version<>p_expected_incident_version then
  raise exception 'DELIVERY_INCIDENT_VERSION_CONFLICT' using errcode='P0001'; end if;
 if btrim(p_return_reference) in (v_dispatch.dispatch_reference,v_incident.reference)
 or btrim(p_return_evidence) in (v_dispatch.dispatch_evidence,v_incident.evidence)
 or exists(select 1 from public.repair_delivery_incidents where org_id=p_org_id and resolution_reference=btrim(p_return_reference)) then
  raise exception 'DELIVERY_INDEPENDENT_RETURN_REQUIRED' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.device_id is null or v_position.case_id<>p_case_id then
  raise exception 'DELIVERY_CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),''),v_actor::text) into v_label from public.org_members m
 join public.profiles p on p.id=m.user_id where m.org_id=p_org_id and m.user_id=v_actor
 and m.deleted_at is null and m.invitation_status='active';
 if v_label is null then raise exception 'DELIVERY_MEMBER_INACTIVE' using errcode='23514'; end if;
 v_at:=pg_catalog.clock_timestamp();
 insert into public.repair_delivery_dispatch_returns(org_id,case_id,device_id,dispatch_id,incident_id,
  location,condition_note,return_reference,return_evidence,received_by,received_at)
 values(p_org_id,p_case_id,v_case.verified_device_id,p_dispatch_id,p_incident_id,
  btrim(p_location),btrim(p_condition_note),btrim(p_return_reference),btrim(p_return_evidence),v_actor,v_at)
 returning * into v_return;
 update public.repair_delivery_dispatches set status='returned' where id=p_dispatch_id;
 update public.repair_delivery_incidents set status='resolved',resolution_reference=btrim(p_return_reference),
  resolution_evidence=btrim(p_return_evidence),resolved_by=v_actor,resolved_at=v_at,version=version+1
  where id=p_incident_id;
 update public.repair_device_custody_positions set location=btrim(p_location),custodian_user_id=v_actor,
  custodian_label=v_label,confirmed_at=v_at,confirmed_by=v_actor,baseline_evidence=btrim(p_return_evidence)
  where org_id=p_org_id and device_id=v_case.verified_device_id;
 update public.repair_cases set device_location=btrim(p_location),device_custodian=v_label,
  custody_damage_epoch=custody_damage_epoch+1,version=version+1
  where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'delivery_damage_returned',v_actor,v_at,pg_catalog.jsonb_build_object(
  'dispatchId',p_dispatch_id,'incidentId',p_incident_id,'returnId',v_return.id,
  'reference',v_return.return_reference,'location',v_return.location,
  'condition',v_return.condition_note,'damageEpoch',v_case.custody_damage_epoch));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'returnId',v_return.id,
  'version',v_case.version,'incidentVersion',v_incident.version+1,'damageEpoch',v_case.custody_damage_epoch);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.damage.return',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.receive_repair_delivery_damage_return(uuid,uuid,uuid,uuid,integer,integer,uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.receive_repair_delivery_damage_return(uuid,uuid,uuid,uuid,integer,integer,uuid,text,text,text,text) to authenticated;
