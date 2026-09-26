-- One discrepancy ledger serves the original device and the allocated replacement independently.
create or replace function public.record_repair_custody_discrepancy(
 p_org_id uuid,p_case_id uuid,p_transfer_id uuid,p_kind text,p_reference text,p_evidence text,
 p_responsible_user_id uuid,p_due_at timestamptz,p_expected_version integer,p_expected_transfer_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_transfer public.repair_device_custody_transfers;
 v_item public.repair_device_custody_discrepancies; v_hash text; v_saved private.repair_command_receipts; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_transfer_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'custody.transfer.discrepancy.record')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_kind not in ('identity_mismatch','destination_mismatch','damage') or p_responsible_user_id is null
 or p_due_at is null or p_due_at<=clock_timestamp() or p_expected_version is null or p_expected_transfer_version is null
 or length(btrim(coalesce(p_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_CUSTODY_DISCREPANCY' using errcode='23514'; end if;
 v_hash:=md5(pg_catalog.jsonb_build_object('case',p_case_id,'transfer',p_transfer_id,'kind',p_kind,'ref',btrim(p_reference),
 'evidence',btrim(p_evidence),'responsible',p_responsible_user_id,'due',p_due_at,'caseVersion',p_expected_version,
 'transferVersion',p_expected_transfer_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.custody.discrepancy.record:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='custody.discrepancy.record' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_transfer from public.repair_device_custody_transfers where org_id=p_org_id and case_id=p_case_id and id=p_transfer_id for update;
 if not found or v_transfer.status<>'in_transit' or not (v_transfer.device_id=v_case.verified_device_id or
  (v_case.stage='replacement' and exists(select 1 from public.repair_replacement_stock s
   where s.org_id=p_org_id and s.device_id=v_transfer.device_id and s.status='allocated' and s.allocated_case_id=p_case_id)))
 or v_case.stage='closed' then raise exception 'CUSTODY_TRANSFER_NOT_OPEN' using errcode='23514'; end if;
 if v_transfer.version<>p_expected_transfer_version then raise exception 'CUSTODY_TRANSFER_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_actor<>v_transfer.destination_user_id then raise exception 'CUSTODY_ACTOR_MISMATCH' using errcode='42501'; end if;
 if not exists(select 1 from public.org_members where org_id=p_org_id and user_id=p_responsible_user_id
 and deleted_at is null and invitation_status='active') then raise exception 'CUSTODY_MEMBER_INACTIVE' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_discrepancies where org_id=p_org_id and transfer_id=p_transfer_id and status='open')
 then raise exception 'CUSTODY_DISCREPANCY_OPEN' using errcode='23514'; end if;
 insert into public.repair_device_custody_discrepancies(org_id,case_id,device_id,transfer_id,kind,reference,evidence,
 responsible_user_id,due_at,recorded_by)
 values(p_org_id,p_case_id,v_transfer.device_id,p_transfer_id,p_kind,btrim(p_reference),btrim(p_evidence),
 p_responsible_user_id,p_due_at,v_actor) returning * into v_item;
 update public.repair_device_custody_transfers set version=version+1 where id=p_transfer_id;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'custody_discrepancy_recorded',v_actor,pg_catalog.jsonb_build_object('discrepancyId',v_item.id,'transferId',p_transfer_id,'deviceId',v_transfer.device_id,'kind',p_kind,'reference',btrim(p_reference),'responsibleUserId',p_responsible_user_id,'deviceRole',case when v_transfer.device_id=v_case.verified_device_id then 'original' else 'replacement' end,'dueAt',p_due_at));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'discrepancyId',v_item.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.discrepancy.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create or replace function public.resolve_repair_custody_discrepancy(
 p_org_id uuid,p_case_id uuid,p_discrepancy_id uuid,p_reference text,p_evidence text,
 p_expected_version integer,p_expected_transfer_version integer,p_expected_discrepancy_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_transfer public.repair_device_custody_transfers;
 v_item public.repair_device_custody_discrepancies; v_hash text; v_saved private.repair_command_receipts; v_response jsonb; v_at timestamptz;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_discrepancy_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'custody.transfer.discrepancy.resolve')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_transfer_version is null or p_expected_discrepancy_version is null
 or length(btrim(coalesce(p_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_CUSTODY_DISCREPANCY_RESOLUTION' using errcode='23514'; end if;
 v_hash:=md5(pg_catalog.jsonb_build_object('case',p_case_id,'discrepancy',p_discrepancy_id,'ref',btrim(p_reference),
 'evidence',btrim(p_evidence),'caseVersion',p_expected_version,'transferVersion',p_expected_transfer_version,
 'discrepancyVersion',p_expected_discrepancy_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.custody.discrepancy.resolve:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor and operation='custody.discrepancy.resolve' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_item from public.repair_device_custody_discrepancies where org_id=p_org_id and case_id=p_case_id and id=p_discrepancy_id for update;
 if not found or v_item.status<>'open' or not (v_item.device_id=v_case.verified_device_id or
  (v_case.stage='replacement' and exists(select 1 from public.repair_replacement_stock s
   where s.org_id=p_org_id and s.device_id=v_item.device_id and s.status='allocated' and s.allocated_case_id=p_case_id)))
 then raise exception 'CUSTODY_DISCREPANCY_NOT_OPEN' using errcode='23514'; end if;
 if v_item.version<>p_expected_discrepancy_version then raise exception 'CUSTODY_DISCREPANCY_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_transfer from public.repair_device_custody_transfers where org_id=p_org_id and id=v_item.transfer_id for update;
 if not found or v_transfer.device_id<>v_item.device_id or v_transfer.version<>p_expected_transfer_version
 then raise exception 'CUSTODY_TRANSFER_VERSION_CONFLICT' using errcode='P0001'; end if;
 if (v_item.kind='damage' and v_transfer.status<>'returned')
 or (v_item.kind<>'damage' and v_transfer.status<>'in_transit')
 then raise exception 'CUSTODY_DISCREPANCY_RETURN_REQUIRED' using errcode='23514'; end if;
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_device_custody_discrepancies set status='resolved',resolution_reference=btrim(p_reference),
 resolution_evidence=btrim(p_evidence),resolved_by=v_actor,resolved_at=v_at,version=version+1 where id=p_discrepancy_id;
 update public.repair_device_custody_transfers set version=version+1 where id=v_transfer.id;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'custody_discrepancy_resolved',v_actor,pg_catalog.jsonb_build_object('discrepancyId',p_discrepancy_id,'transferId',v_transfer.id,'kind',v_item.kind,'reference',btrim(p_reference),'evidence',btrim(p_evidence),'deviceRole',case when v_item.device_id=v_case.verified_device_id then 'original' else 'replacement' end,'requiresTestReview',v_item.kind='damage'));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'discrepancyId',p_discrepancy_id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.discrepancy.resolve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create or replace function private.mark_repair_custody_damage() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.kind = 'damage' then
    update public.repair_cases
       set custody_damage_epoch = custody_damage_epoch + 1
     where org_id = new.org_id and id = new.case_id
       and (verified_device_id = new.device_id or
         (stage='replacement' and exists(select 1 from public.repair_replacement_stock s
           where s.org_id=new.org_id and s.device_id=new.device_id
             and s.status='allocated' and s.allocated_case_id=new.case_id)));
    if not found then
      raise exception 'VERIFIED_DEVICE_REQUIRED' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
