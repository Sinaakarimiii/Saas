-- Normalize a concurrent duplicate IMEI to the same domain error as an existing IMEI.
create or replace function public.receive_repair_replacement_stock(
 p_org_id uuid,p_imei text,p_model text,p_location text,p_custodian_user_id uuid,
 p_evidence text,p_receipt_reference text,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_label text; v_device public.repair_devices; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_custodian_user_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'replacement.stock.receive')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if coalesce(p_imei,'') !~ '^[0-9]{15}$'
 or length(btrim(coalesce(p_model,''))) not between 1 and 160
 or length(btrim(coalesce(p_location,''))) not between 1 and 200
 or length(btrim(coalesce(p_evidence,''))) not between 1 and 240
 or length(btrim(coalesce(p_receipt_reference,''))) not between 1 and 160
 then raise exception 'INVALID_REPLACEMENT_STOCK' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('imei',p_imei,'model',btrim(p_model),'location',btrim(p_location),
 'custodian',p_custodian_user_id,'evidence',btrim(p_evidence),'reference',btrim(p_receipt_reference))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.replacement.receive:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='replacement.stock.receive' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(p.email),''),p_custodian_user_id::text) into v_label
 from public.org_members m join public.profiles p on p.id=m.user_id
 where m.org_id=p_org_id and m.user_id=p_custodian_user_id and m.deleted_at is null and m.invitation_status='active';
 if v_label is null then raise exception 'CUSTODY_MEMBER_INACTIVE' using errcode='23514'; end if;
 if exists(select 1 from public.repair_devices where org_id=p_org_id and imei=p_imei)
 then raise exception 'REPLACEMENT_IMEI_EXISTS' using errcode='23505'; end if;
 insert into public.repair_devices(org_id,imei,first_verified_by,first_evidence)
 values(p_org_id,p_imei,v_actor,btrim(p_evidence))
 on conflict (org_id,imei) do nothing returning * into v_device;
 if not found then raise exception 'REPLACEMENT_IMEI_EXISTS' using errcode='23505'; end if;
 insert into public.repair_replacement_stock(org_id,device_id,model,receipt_reference,location,
 custodian_user_id,custodian_label,evidence,received_by)
 values(p_org_id,v_device.id,btrim(p_model),btrim(p_receipt_reference),btrim(p_location),
 p_custodian_user_id,v_label,btrim(p_evidence),v_actor);
 v_response:=jsonb_build_object('deviceId',v_device.id,'imei',p_imei);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.stock.receive',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
