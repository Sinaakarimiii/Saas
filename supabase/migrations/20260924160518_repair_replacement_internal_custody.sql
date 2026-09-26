-- Replacement custody uses the same transfer ledger and permissions, but never mutates original-device case fields.
create or replace function public.release_repair_replacement_custody(
 p_org_id uuid,p_case_id uuid,p_device_id uuid,p_destination_location text,p_destination_user_id uuid,p_carrier text,
 p_release_reference text,p_release_evidence text,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_position public.repair_device_custody_positions;
 v_transfer public.repair_device_custody_transfers; v_label text; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_device_id is null or p_destination_user_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'custody.transfer.release')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1
 or length(btrim(coalesce(p_destination_location,''))) not between 1 and 200
 or length(btrim(coalesce(p_carrier,''))) not between 1 and 160
 or length(btrim(coalesce(p_release_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_release_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_CUSTODY_TRANSFER' using errcode='23514'; end if;
 v_hash:=md5(pg_catalog.jsonb_build_object('caseId',p_case_id,'deviceId',p_device_id,'destination',btrim(p_destination_location),
 'destinationId',p_destination_user_id,'carrier',btrim(p_carrier),'reference',btrim(p_release_reference),
 'evidence',btrim(p_release_evidence),'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.replacement.custody.release:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='replacement.custody.release' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'replacement' or v_case.verified_device_id is null
 then raise exception 'REPLACEMENT_STAGE_REQUIRED' using errcode='23514'; end if;
 if not exists(select 1 from public.repair_replacement_stock s where s.org_id=p_org_id and s.device_id=p_device_id and s.status='allocated' and s.allocated_case_id=p_case_id)
 then raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 select * into v_position from public.repair_device_custody_positions
 where org_id=p_org_id and device_id=p_device_id for update;
 if not found then raise exception 'CUSTODY_BASELINE_REQUIRED' using errcode='23514'; end if;
 if v_position.case_id<>p_case_id or v_position.holder_kind<>'staff'
 or v_position.custodian_user_id is distinct from v_actor then
  raise exception 'CUSTODY_SOURCE_MISMATCH' using errcode='42501'; end if;
 if v_position.location=btrim(p_destination_location) and v_position.custodian_user_id=p_destination_user_id
 then raise exception 'CUSTODY_SAME_DESTINATION' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_transfers where org_id=p_org_id
 and device_id=p_device_id and status='in_transit')
 then raise exception 'CUSTODY_TRANSFER_OPEN' using errcode='23505'; end if;
 select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),''),p_destination_user_id::text) into v_label
 from public.org_members m join public.profiles p on p.id=m.user_id
 where m.org_id=p_org_id and m.user_id=p_destination_user_id and m.deleted_at is null and m.invitation_status='active';
 if v_label is null then raise exception 'CUSTODY_MEMBER_INACTIVE' using errcode='23514'; end if;
 insert into public.repair_device_custody_transfers(org_id,case_id,device_id,source_location,source_custodian_user_id,
 source_custodian_label,destination_location,destination_user_id,destination_label,carrier,release_reference,
 release_evidence,released_by) values(p_org_id,p_case_id,p_device_id,v_position.location,
 v_position.custodian_user_id,v_position.custodian_label,btrim(p_destination_location),p_destination_user_id,
 v_label,btrim(p_carrier),btrim(p_release_reference),btrim(p_release_evidence),v_actor) returning * into v_transfer;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'custody_released',v_actor,pg_catalog.jsonb_build_object('transferId',v_transfer.id,
 'deviceId',v_transfer.device_id,'source',v_transfer.source_location,'destination',v_transfer.destination_location,
 'destinationUserId',p_destination_user_id,'carrier',v_transfer.carrier,'reference',v_transfer.release_reference,
 'deviceRole','replacement','evidence',v_transfer.release_evidence));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'transferId',v_transfer.id,'status','in_transit','version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.custody.release',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create or replace function public.resolve_repair_replacement_custody(
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
 'deviceRole','replacement','reference',btrim(p_reference),'evidence',btrim(p_evidence),'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.replacement.custody.resolve:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='replacement.custody.resolve' and idempotency_key=p_idempotency_key;
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
 or not exists(select 1 from public.repair_replacement_stock s where s.org_id=p_org_id and s.device_id=v_transfer.device_id and s.status='allocated' and s.allocated_case_id=p_case_id)
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
  update public.repair_replacement_stock set location=v_transfer.destination_location,
  custodian_user_id=v_actor,custodian_label=v_transfer.destination_label
  where org_id=p_org_id and device_id=v_transfer.device_id and allocated_case_id=p_case_id;
  update public.repair_cases set version=version+1
  where org_id=p_org_id and id=p_case_id returning * into v_case;
 else
  update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 end if;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'custody_'||p_outcome,v_actor,v_at,
 pg_catalog.jsonb_build_object('transferId',p_transfer_id,'deviceId',v_transfer.device_id,
 'deviceRole','replacement','reference',btrim(p_reference),'evidence',btrim(p_evidence),'confirmedLocation',
 case when p_outcome='accepted' then v_transfer.destination_location else v_transfer.source_location end));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'transferId',p_transfer_id,'status',p_outcome,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.custody.resolve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

revoke all on function public.release_repair_replacement_custody(uuid,uuid,uuid,text,uuid,text,text,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.release_repair_replacement_custody(uuid,uuid,uuid,text,uuid,text,text,text,integer,uuid) to authenticated;
revoke all on function public.resolve_repair_replacement_custody(uuid,uuid,uuid,text,text,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.resolve_repair_replacement_custody(uuid,uuid,uuid,text,text,text,integer,uuid) to authenticated;
