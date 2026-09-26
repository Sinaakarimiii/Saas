-- Confirmed physical custody of the original verified device is separate from case assignment.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
 ('custody.baseline.record', 'ثبت مبنای نگهداری دستگاه', 'تأیید محل و نگهدارنده اولیه دستگاه با مدرک', '{}'),
 ('custody.transfer.release', 'خروج داخلی دستگاه', 'ثبت حواله خروج فیزیکی به عضو مقصد', '{}'),
 ('custody.transfer.accept', 'پذیرش داخلی دستگاه', 'ثبت رسید واقعی عضو مقصد', '{}'),
 ('custody.transfer.return', 'بازگشت داخلی دستگاه', 'ثبت بازگشت واقعی به نگهدارنده مبدأ', '{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
and p.key in ('custody.baseline.record','custody.transfer.release','custody.transfer.accept','custody.transfer.return')
on conflict (role_id, permission_key) do nothing;

create table public.repair_device_custody_positions (
 org_id uuid not null,
 device_id uuid not null,
 case_id uuid not null,
 location text not null check (length(btrim(location)) between 1 and 200),
 custodian_user_id uuid not null references auth.users(id),
 custodian_label text not null check (length(btrim(custodian_label)) between 1 and 160),
 baseline_evidence text not null check (length(btrim(baseline_evidence)) between 1 and 240),
 confirmed_at timestamptz not null default clock_timestamp(),
 confirmed_by uuid not null references auth.users(id),
 primary key (org_id, device_id),
 foreign key (org_id, device_id) references public.repair_devices(org_id, id),
 foreign key (org_id, case_id) references public.repair_cases(org_id, id)
);
create index repair_device_custody_positions_case_idx on public.repair_device_custody_positions(org_id,case_id);
create table public.repair_device_custody_transfers (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null,
 case_id uuid not null,
 device_id uuid not null,
 source_location text not null,
 source_custodian_user_id uuid not null references auth.users(id),
 source_custodian_label text not null,
 destination_location text not null check (length(btrim(destination_location)) between 1 and 200),
 destination_user_id uuid not null references auth.users(id),
 destination_label text not null,
 carrier text not null check (length(btrim(carrier)) between 1 and 160),
 release_reference text not null check (length(btrim(release_reference)) between 1 and 160),
 release_evidence text not null check (length(btrim(release_evidence)) between 1 and 240),
 released_by uuid not null references auth.users(id),
 released_at timestamptz not null default clock_timestamp(),
 status text not null default 'in_transit' check (status in ('in_transit','accepted','returned')),
 resolved_by uuid references auth.users(id),
 resolved_at timestamptz,
 resolution_reference text,
 resolution_evidence text,
 unique (org_id, release_reference),
 unique (org_id, id),
 foreign key (org_id, device_id) references public.repair_devices(org_id, id),
 foreign key (org_id, case_id) references public.repair_cases(org_id, id),
 check ((status='in_transit' and resolved_by is null and resolved_at is null and resolution_reference is null and resolution_evidence is null)
   or (status in ('accepted','returned') and resolved_by is not null and resolved_at is not null
      and length(btrim(resolution_reference)) between 1 and 160
      and length(btrim(resolution_evidence)) between 1 and 240))
);
create unique index repair_device_custody_one_open_transfer on public.repair_device_custody_transfers(org_id,device_id) where status='in_transit';
create unique index repair_device_custody_resolution_ref_unique on public.repair_device_custody_transfers(org_id,resolution_reference) where resolution_reference is not null;
create index repair_device_custody_case_history_idx on public.repair_device_custody_transfers(org_id,case_id,released_at desc);
create index repair_device_custody_target_queue_idx on public.repair_device_custody_transfers(org_id,destination_user_id,released_at desc) where status='in_transit';
alter table public.repair_device_custody_positions enable row level security;
alter table public.repair_device_custody_transfers enable row level security;
create policy repair_device_custody_positions_select on public.repair_device_custody_positions for select to authenticated
using (private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
create policy repair_device_custody_transfers_select on public.repair_device_custody_transfers for select to authenticated
using (private.is_org_member(org_id) and (private.has_permission(org_id,'repair.case.view') or destination_user_id=(select auth.uid())));
revoke all on public.repair_device_custody_positions,public.repair_device_custody_transfers from public,anon,authenticated;
grant select on public.repair_device_custody_positions,public.repair_device_custody_transfers to authenticated;
alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
check (event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved',
'custody_baseline_recorded','custody_released','custody_accepted','custody_returned'));

create function public.record_repair_device_custody_baseline(
 p_org_id uuid,p_case_id uuid,p_location text,p_custodian_user_id uuid,p_evidence text,
 p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_label text; v_response jsonb;
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
 if exists(select 1 from public.repair_device_custody_positions where org_id=p_org_id and device_id=v_case.verified_device_id)
 then raise exception 'CUSTODY_BASELINE_EXISTS' using errcode='23505'; end if;
 select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),''),p_custodian_user_id::text) into v_label
 from public.org_members m join public.profiles p on p.id=m.user_id
 where m.org_id=p_org_id and m.user_id=p_custodian_user_id and m.deleted_at is null and m.invitation_status='active';
 if v_label is null then raise exception 'CUSTODY_MEMBER_INACTIVE' using errcode='23514'; end if;
 insert into public.repair_device_custody_positions(org_id,device_id,case_id,location,custodian_user_id,custodian_label,baseline_evidence,confirmed_by)
 values(p_org_id,v_case.verified_device_id,p_case_id,btrim(p_location),p_custodian_user_id,v_label,btrim(p_evidence),v_actor);
 update public.repair_cases set device_location=btrim(p_location),device_custodian=v_label,version=version+1
 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'custody_baseline_recorded',v_actor,
 pg_catalog.jsonb_build_object('deviceId',v_case.verified_device_id,'location',btrim(p_location),'custodianId',p_custodian_user_id,'evidence',btrim(p_evidence)));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'deviceId',v_case.verified_device_id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.baseline',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_repair_device_custody_baseline(uuid,uuid,text,uuid,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.record_repair_device_custody_baseline(uuid,uuid,text,uuid,text,integer,uuid) to authenticated;

create function public.release_repair_device_custody(
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
 if v_position.custodian_user_id<>v_actor then raise exception 'CUSTODY_SOURCE_MISMATCH' using errcode='42501'; end if;
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
revoke all on function public.release_repair_device_custody(uuid,uuid,text,uuid,text,text,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.release_repair_device_custody(uuid,uuid,text,uuid,text,text,text,integer,uuid) to authenticated;

create function public.resolve_repair_device_custody(
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
 if not found or v_position.location<>v_transfer.source_location
 or v_position.custodian_user_id<>v_transfer.source_custodian_user_id
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
revoke all on function public.resolve_repair_device_custody(uuid,uuid,uuid,text,text,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.resolve_repair_device_custody(uuid,uuid,uuid,text,text,text,integer,uuid) to authenticated;
