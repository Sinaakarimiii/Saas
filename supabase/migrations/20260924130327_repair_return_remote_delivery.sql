-- A shipment is not a receipt. Remote receipt is tied to one immutable dispatch.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.delivery.dispatch','ثبت خروج پستی یا پیک','ثبت خروج دستگاه عودتی به حامل با مدرک و کد رهگیری','{}'),
 ('repair.delivery.confirm_receipt','تأیید دریافت در مقصد','ثبت مدرک مستقل دریافت گیرندهٔ همان ارسال','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
and p.key in ('repair.delivery.dispatch','repair.delivery.confirm_receipt')
on conflict(role_id,permission_key) do nothing;

create table public.repair_delivery_dispatches(
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null,
 case_id uuid not null,
 device_id uuid not null,
 outgoing_check_id uuid not null,
 method text not null check(method in ('post','courier')),
 carrier text not null check(length(btrim(carrier)) between 1 and 160),
 destination_name text not null check(length(btrim(destination_name)) between 1 and 160),
 destination_role text not null check(destination_role in ('owner','authorized_representative','colleague')),
 authority_reference text,
 destination_address text not null check(length(btrim(destination_address)) between 1 and 300),
 tracking_code text not null check(length(btrim(tracking_code)) between 1 and 240),
 dispatch_reference text not null check(length(btrim(dispatch_reference)) between 1 and 160),
 dispatch_evidence text not null check(length(btrim(dispatch_evidence)) between 1 and 240),
 dispatched_by uuid not null references auth.users(id),
 dispatched_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,case_id),
 unique(org_id,dispatch_reference),
 unique(org_id,method,tracking_code),
 unique(org_id,case_id,id),
 foreign key(org_id,case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,device_id) references public.repair_devices(org_id,id),
 foreign key(org_id,case_id,outgoing_check_id) references public.repair_return_outgoing_checks(org_id,case_id,id),
 check((destination_role='owner' and authority_reference is null)
   or (destination_role<>'owner' and length(btrim(authority_reference)) between 1 and 240))
);
create index repair_delivery_dispatches_tracking_idx on public.repair_delivery_dispatches(org_id,tracking_code);
alter table public.repair_delivery_dispatches enable row level security;
create policy repair_delivery_dispatches_select on public.repair_delivery_dispatches for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_delivery_dispatches from public,anon,authenticated;
grant select on public.repair_delivery_dispatches to authenticated;

alter table public.repair_delivery_receipts drop constraint repair_delivery_receipts_method_check;
alter table public.repair_delivery_receipts add constraint repair_delivery_receipts_method_check
 check(method in ('in_person','post','courier'));
alter table public.repair_delivery_receipts add column dispatch_id uuid,
 add column confirmed_by uuid references auth.users(id);
alter table public.repair_delivery_receipts add constraint repair_delivery_receipts_dispatch_fkey
 foreign key(org_id,case_id,dispatch_id) references public.repair_delivery_dispatches(org_id,case_id,id);
alter table public.repair_delivery_receipts add constraint repair_delivery_receipts_method_dispatch_check
 check((method='in_person' and dispatch_id is null and confirmed_by is null)
   or (method in ('post','courier') and dispatch_id is not null and confirmed_by is not null));
create unique index repair_delivery_receipts_dispatch_unique on public.repair_delivery_receipts(org_id,dispatch_id)
 where dispatch_id is not null;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
check(event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved',
'custody_baseline_recorded','custody_released','custody_accepted','custody_returned',
'custody_discrepancy_recorded','custody_discrepancy_resolved','delivery_received','delivery_dispatched'));

-- These constraints protect the mutually exclusive paths even from a later command writer.
create function private.guard_repair_delivery_receipt_path() returns trigger
language plpgsql set search_path='' as $$
declare v_dispatch public.repair_delivery_dispatches;
begin
 if new.method='in_person' then
  if exists(select 1 from public.repair_delivery_dispatches d where d.org_id=new.org_id and d.case_id=new.case_id) then
   raise exception 'DELIVERY_ALREADY_DISPATCHED' using errcode='23514'; end if;
 else
  select * into v_dispatch from public.repair_delivery_dispatches where org_id=new.org_id and case_id=new.case_id and id=new.dispatch_id;
  if v_dispatch.id is null or v_dispatch.method<>new.method or v_dispatch.device_id<>new.device_id
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
create trigger repair_delivery_receipt_path_guard before insert on public.repair_delivery_receipts
for each row execute function private.guard_repair_delivery_receipt_path();

create function private.guard_repair_dispatch_path() returns trigger
language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.repair_delivery_receipts r where r.org_id=new.org_id and r.case_id=new.case_id) then
  raise exception 'DELIVERY_ALREADY_RECEIVED' using errcode='23514'; end if;
 return new;
end;
$$;
create trigger repair_dispatch_path_guard before insert on public.repair_delivery_dispatches
for each row execute function private.guard_repair_dispatch_path();

create function private.guard_repair_transfer_after_delivery() returns trigger
language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.repair_delivery_dispatches d where d.org_id=new.org_id and d.case_id=new.case_id and d.device_id=new.device_id)
 or exists(select 1 from public.repair_delivery_receipts r where r.org_id=new.org_id and r.case_id=new.case_id and r.device_id=new.device_id) then
  raise exception 'DELIVERY_DEVICE_ALREADY_RELEASED' using errcode='23514'; end if;
 return new;
end;
$$;
create trigger repair_transfer_after_delivery_guard before insert on public.repair_device_custody_transfers
for each row execute function private.guard_repair_transfer_after_delivery();

create function public.record_repair_delivery_dispatch(
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
 if exists(select 1 from public.repair_delivery_dispatches where org_id=p_org_id and case_id=p_case_id) then
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
revoke all on function public.record_repair_delivery_dispatch(uuid,uuid,integer,uuid,text,text,text,text,text,text) from public,anon;
grant execute on function public.record_repair_delivery_dispatch(uuid,uuid,integer,uuid,text,text,text,text,text,text) to authenticated;

create function public.confirm_repair_delivery_receipt(
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
 if v_dispatch.id is null or v_dispatch.device_id<>v_case.verified_device_id or v_dispatch.outgoing_check_id<>v_check_id
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
revoke all on function public.confirm_repair_delivery_receipt(uuid,uuid,uuid,integer,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.confirm_repair_delivery_receipt(uuid,uuid,uuid,integer,uuid,text,text,text,text,text) to authenticated;
