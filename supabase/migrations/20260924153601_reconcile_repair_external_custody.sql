-- A delivery receipt is a physical custody change; staff custody must not linger after handover.
alter table public.repair_device_custody_positions
  alter column custodian_user_id drop not null,
  add column holder_kind text not null default 'staff',
  add column external_reference text;
alter table public.repair_device_custody_positions
  add constraint repair_device_custody_holder_check check (
    (holder_kind='staff' and custodian_user_id is not null and external_reference is null)
    or (holder_kind in ('carrier','recipient') and custodian_user_id is null
      and length(btrim(external_reference)) between 1 and 160));

create function private.reconcile_repair_dispatch_custody()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_position public.repair_device_custody_positions;
begin
 select * into v_position from public.repair_device_custody_positions
  where org_id=new.org_id and device_id=new.device_id for update;
 if v_position.device_id is null or v_position.case_id<>new.case_id
 or v_position.holder_kind<>'staff' or v_position.custodian_user_id<>new.dispatched_by then
  raise exception 'DELIVERY_CUSTODIAN_REQUIRED' using errcode='23514'; end if;
 update public.repair_device_custody_positions set
  holder_kind='carrier',custodian_user_id=null,custodian_label=new.carrier,
  location='نزد حامل: '||new.carrier,external_reference=new.dispatch_reference,
  confirmed_at=new.dispatched_at,confirmed_by=new.dispatched_by
  where org_id=new.org_id and device_id=new.device_id;
 update public.repair_cases set device_location='نزد حامل: '||new.carrier,
  device_custodian=new.carrier where org_id=new.org_id and id=new.case_id;
 return new;
end; $$;
revoke all on function private.reconcile_repair_dispatch_custody() from public,anon,authenticated;
create trigger repair_dispatch_custody_reconcile after insert on public.repair_delivery_dispatches
for each row execute function private.reconcile_repair_dispatch_custody();

create function private.reconcile_repair_receipt_custody()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_position public.repair_device_custody_positions; v_dispatch public.repair_delivery_dispatches;
begin
 select * into v_position from public.repair_device_custody_positions
  where org_id=new.org_id and device_id=new.device_id for update;
 if v_position.device_id is null or v_position.case_id<>new.case_id then
  raise exception 'DELIVERY_CUSTODY_MISMATCH' using errcode='23514'; end if;
 if new.method='in_person' then
  if v_position.holder_kind<>'staff' or v_position.custodian_user_id<>new.handed_over_by
   or new.dispatch_id is not null then
   raise exception 'DELIVERY_CUSTODY_MISMATCH' using errcode='23514'; end if;
 else
  select * into v_dispatch from public.repair_delivery_dispatches
   where org_id=new.org_id and case_id=new.case_id and id=new.dispatch_id;
  if v_dispatch.id is null or v_dispatch.device_id<>new.device_id
   or v_position.holder_kind<>'carrier'
   or v_position.external_reference<>v_dispatch.dispatch_reference then
   raise exception 'DELIVERY_CUSTODY_MISMATCH' using errcode='23514'; end if;
 end if;
 update public.repair_device_custody_positions set holder_kind='recipient',
  custodian_user_id=null,custodian_label=new.recipient_name,
  location='نزد گیرنده: '||new.recipient_name,external_reference=new.receipt_reference,
  confirmed_at=new.received_at,confirmed_by=coalesce(new.confirmed_by,new.handed_over_by)
  where org_id=new.org_id and device_id=new.device_id;
 update public.repair_cases set device_location='نزد گیرنده: '||new.recipient_name,
  device_custodian=new.recipient_name where org_id=new.org_id and id=new.case_id;
 return new;
end; $$;
revoke all on function private.reconcile_repair_receipt_custody() from public,anon,authenticated;
create trigger repair_receipt_custody_reconcile after insert on public.repair_delivery_receipts
for each row execute function private.reconcile_repair_receipt_custody();

-- Historical receipts and in-transit dispatches in this isolated slice get the same current-position semantics.
with latest as (
 select distinct on (r.org_id,r.device_id) r.org_id,r.device_id,r.case_id,r.recipient_name,
  r.receipt_reference,r.received_at,coalesce(r.confirmed_by,r.handed_over_by) as actor
 from public.repair_delivery_receipts r
 order by r.org_id,r.device_id,r.received_at desc
)
update public.repair_device_custody_positions p set holder_kind='recipient',custodian_user_id=null,
 custodian_label=l.recipient_name,location='نزد گیرنده: '||l.recipient_name,
 external_reference=l.receipt_reference,confirmed_at=l.received_at,confirmed_by=l.actor
from latest l where p.org_id=l.org_id and p.device_id=l.device_id and p.case_id=l.case_id
 and p.confirmed_at<=l.received_at;
with latest as (
 select distinct on (d.org_id,d.device_id) d.org_id,d.device_id,d.case_id,d.carrier,
  d.dispatch_reference,d.dispatched_at,d.dispatched_by
 from public.repair_delivery_dispatches d where d.status='in_transit'
 order by d.org_id,d.device_id,d.dispatched_at desc
)
update public.repair_device_custody_positions p set holder_kind='carrier',custodian_user_id=null,
 custodian_label=l.carrier,location='نزد حامل: '||l.carrier,
 external_reference=l.dispatch_reference,confirmed_at=l.dispatched_at,confirmed_by=l.dispatched_by
from latest l where p.org_id=l.org_id and p.device_id=l.device_id and p.case_id=l.case_id
 and p.confirmed_at<=l.dispatched_at;
update public.repair_cases c set device_location=p.location,device_custodian=p.custodian_label
from public.repair_device_custody_positions p where c.org_id=p.org_id and c.id=p.case_id
 and p.holder_kind<>'staff';

-- A later physical intake can establish staff custody only after the prior recipient receipt and closed case.
create or replace function public.record_repair_device_custody_baseline(
 p_org_id uuid,p_case_id uuid,p_location text,p_custodian_user_id uuid,p_evidence text,
 p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_position public.repair_device_custody_positions; v_label text; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_custodian_user_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'custody.baseline.record')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or length(btrim(coalesce(p_location,''))) not between 1 and 200
 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_CUSTODY_BASELINE' using errcode='23514'; end if;
 v_hash:=md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'location',btrim(p_location),
 'custodianId',p_custodian_user_id,'evidence',btrim(p_evidence),'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.custody.baseline:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='custody.baseline' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage='closed' or v_case.received_at is null or v_case.verified_device_id is null
 then raise exception 'VERIFIED_DEVICE_REQUIRED' using errcode='23514'; end if;
 if v_case.device_location is not null and btrim(v_case.device_location)<>btrim(p_location)
 then raise exception 'CUSTODY_BASELINE_LOCATION_MISMATCH' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
  where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if v_position.device_id is not null and not (
  v_position.holder_kind='recipient' and v_position.case_id<>p_case_id
  and exists(select 1 from public.repair_cases old_case
   join public.repair_delivery_receipts receipt on receipt.org_id=old_case.org_id
    and receipt.case_id=old_case.id and receipt.device_id=v_case.verified_device_id
   where old_case.org_id=p_org_id and old_case.id=v_position.case_id
    and old_case.closed_at is not null and receipt.receipt_reference=v_position.external_reference
    and v_case.received_at>=receipt.received_at)) then
  raise exception 'CUSTODY_BASELINE_EXISTS' using errcode='23505'; end if;
 select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),''),p_custodian_user_id::text) into v_label
 from public.org_members m join public.profiles p on p.id=m.user_id
 where m.org_id=p_org_id and m.user_id=p_custodian_user_id and m.deleted_at is null and m.invitation_status='active';
 if v_label is null then raise exception 'CUSTODY_MEMBER_INACTIVE' using errcode='23514'; end if;
 if v_position.device_id is null then
  insert into public.repair_device_custody_positions(org_id,device_id,case_id,location,custodian_user_id,custodian_label,baseline_evidence,confirmed_by)
  values(p_org_id,v_case.verified_device_id,p_case_id,btrim(p_location),p_custodian_user_id,v_label,btrim(p_evidence),v_actor);
 else
  update public.repair_device_custody_positions set case_id=p_case_id,location=btrim(p_location),
   holder_kind='staff',custodian_user_id=p_custodian_user_id,custodian_label=v_label,
   external_reference=null,baseline_evidence=btrim(p_evidence),confirmed_by=v_actor,
   confirmed_at=pg_catalog.clock_timestamp()
   where org_id=p_org_id and device_id=v_case.verified_device_id;
 end if;
 update public.repair_cases set device_location=btrim(p_location),device_custodian=v_label,version=version+1
 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'custody_baseline_recorded',v_actor,
 pg_catalog.jsonb_build_object('deviceId',v_case.verified_device_id,'location',btrim(p_location),'custodianId',p_custodian_user_id,'evidence',btrim(p_evidence),'reentry',v_position.device_id is not null));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'deviceId',v_case.verified_device_id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.baseline',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

-- A documented shipment return restores the device to the actual receiving staff member.
create or replace function public.receive_repair_delivery_damage_return(
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
 if v_position.device_id is null or v_position.case_id<>p_case_id
 or v_position.holder_kind<>'carrier' or v_position.external_reference<>v_dispatch.dispatch_reference then
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
 update public.repair_device_custody_positions set location=btrim(p_location),holder_kind='staff',
  external_reference=null,custodian_user_id=v_actor,
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

-- Internal movement is valid only while the confirmed holder is an organization member.
create or replace function public.release_repair_device_custody(
 p_org_id uuid,p_case_id uuid,p_destination_location text,p_destination_user_id uuid,p_carrier text,
 p_release_reference text,p_release_evidence text,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_position public.repair_device_custody_positions;
 v_transfer public.repair_device_custody_transfers; v_label text; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_destination_user_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'custody.transfer.release')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1
 or length(btrim(coalesce(p_destination_location,''))) not between 1 and 200
 or length(btrim(coalesce(p_carrier,''))) not between 1 and 160
 or length(btrim(coalesce(p_release_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_release_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_CUSTODY_TRANSFER' using errcode='23514'; end if;
 v_hash:=md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'destination',btrim(p_destination_location),
 'destinationId',p_destination_user_id,'carrier',btrim(p_carrier),'reference',btrim(p_release_reference),
 'evidence',btrim(p_release_evidence),'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.custody.release:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='custody.release' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage='closed' or v_case.received_at is null or v_case.verified_device_id is null
 then raise exception 'VERIFIED_DEVICE_REQUIRED' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
 where org_id=p_org_id and device_id=v_case.verified_device_id for update;
 if not found then raise exception 'CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 if v_position.case_id<>p_case_id or v_position.holder_kind<>'staff'
 or v_position.custodian_user_id is distinct from v_actor then
  raise exception 'CUSTODY_SOURCE_MISMATCH' using errcode='42501'; end if;
 if v_position.location=btrim(p_destination_location) and v_position.custodian_user_id=p_destination_user_id
 then raise exception 'CUSTODY_SAME_DESTINATION' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_transfers where org_id=p_org_id
 and device_id=v_case.verified_device_id and status='in_transit')
 then raise exception 'CUSTODY_TRANSFER_OPEN' using errcode='23505'; end if;
 select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),''),p_destination_user_id::text) into v_label
 from public.org_members m join public.profiles p on p.id=m.user_id
 where m.org_id=p_org_id and m.user_id=p_destination_user_id and m.deleted_at is null and m.invitation_status='active';
 if v_label is null then raise exception 'CUSTODY_MEMBER_INACTIVE' using errcode='23514'; end if;
 insert into public.repair_device_custody_transfers(org_id,case_id,device_id,source_location,source_custodian_user_id,
 source_custodian_label,destination_location,destination_user_id,destination_label,carrier,release_reference,
 release_evidence,released_by) values(p_org_id,p_case_id,v_case.verified_device_id,v_position.location,
 v_position.custodian_user_id,v_position.custodian_label,btrim(p_destination_location),p_destination_user_id,
 v_label,btrim(p_carrier),btrim(p_release_reference),btrim(p_release_evidence),v_actor) returning * into v_transfer;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'custody_released',v_actor,pg_catalog.jsonb_build_object('transferId',v_transfer.id,
 'deviceId',v_transfer.device_id,'source',v_transfer.source_location,'destination',v_transfer.destination_location,
 'destinationUserId',p_destination_user_id,'carrier',v_transfer.carrier,'reference',v_transfer.release_reference,
 'evidence',v_transfer.release_evidence));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'transferId',v_transfer.id,'status','in_transit','version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.release',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

-- Internal movement is valid only while the confirmed holder is an organization member.
create or replace function public.resolve_repair_device_custody(
 p_org_id uuid,p_case_id uuid,p_transfer_id uuid,p_outcome text,p_reference text,p_evidence text,
 p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_permission text; v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_position public.repair_device_custody_positions;
 v_transfer public.repair_device_custody_transfers; v_response jsonb; v_at timestamptz;
begin
 v_permission:=case p_outcome when 'accepted' then 'custody.transfer.accept'
 when 'returned' then 'custody.transfer.return' else null end;
 if v_actor is null or p_org_id is null or p_case_id is null or p_transfer_id is null or p_idempotency_key is null
 or v_permission is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,v_permission)
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1
 or length(btrim(coalesce(p_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_CUSTODY_RESOLUTION' using errcode='23514'; end if;
 v_hash:=md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'transferId',p_transfer_id,'outcome',p_outcome,
 'reference',btrim(p_reference),'evidence',btrim(p_evidence),'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.custody.resolve:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='custody.resolve' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_transfer from public.repair_device_custody_transfers
 where org_id=p_org_id and case_id=p_case_id and id=p_transfer_id for update;
 if not found or v_transfer.status<>'in_transit' or v_case.stage='closed'
 or v_case.verified_device_id is distinct from v_transfer.device_id
 then raise exception 'CUSTODY_TRANSFER_NOT_OPEN' using errcode='23514'; end if;
 if (p_outcome='accepted' and v_actor<>v_transfer.destination_user_id)
 or (p_outcome='returned' and v_actor<>v_transfer.source_custodian_user_id)
 then raise exception 'CUSTODY_ACTOR_MISMATCH' using errcode='42501'; end if;
 if not exists(select 1 from public.org_members m where m.org_id=p_org_id and m.user_id=v_actor
 and m.deleted_at is null and m.invitation_status='active')
 then raise exception 'CUSTODY_MEMBER_INACTIVE' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
 where org_id=p_org_id and device_id=v_transfer.device_id for update;
 if not found or v_position.holder_kind<>'staff' or v_position.case_id<>p_case_id
 or v_position.location<>v_transfer.source_location
 or v_position.custodian_user_id is distinct from v_transfer.source_custodian_user_id
 then raise exception 'CUSTODY_SOURCE_CHANGED' using errcode='23514'; end if;
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_device_custody_transfers set status=p_outcome,resolved_by=v_actor,resolved_at=v_at,
 resolution_reference=btrim(p_reference),resolution_evidence=btrim(p_evidence) where id=p_transfer_id;
 if p_outcome='accepted' then
  update public.repair_device_custody_positions set location=v_transfer.destination_location,
  custodian_user_id=v_actor,custodian_label=v_transfer.destination_label,case_id=p_case_id,
  confirmed_at=v_at,confirmed_by=v_actor where org_id=p_org_id and device_id=v_transfer.device_id;
  update public.repair_cases set device_location=v_transfer.destination_location,
  device_custodian=v_transfer.destination_label,version=version+1
  where org_id=p_org_id and id=p_case_id returning * into v_case;
 else
  update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 end if;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'custody_'||p_outcome,v_actor,v_at,
 pg_catalog.jsonb_build_object('transferId',p_transfer_id,'deviceId',v_transfer.device_id,
 'reference',btrim(p_reference),'evidence',btrim(p_evidence),'confirmedLocation',
 case when p_outcome='accepted' then v_transfer.destination_location else v_transfer.source_location end));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'transferId',p_transfer_id,'status',p_outcome,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.resolve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
