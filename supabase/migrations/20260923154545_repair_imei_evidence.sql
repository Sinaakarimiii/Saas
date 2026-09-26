-- Private receipt evidence. No UPDATE/DELETE policies: attached files cannot
-- be silently replaced, and retention remains a separate policy decision.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('repair-imei-evidence', 'repair-imei-evidence', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = excluded.allowed_mime_types;

create policy repair_imei_evidence_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'repair-imei-evidence'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
    and exists (
      select 1 from public.repair_cases c
      where c.org_id::text = (storage.foldername(name))[1]
        and c.id::text = (storage.foldername(name))[2]
        and c.received_at is null and c.stage = 'intake'
        and private.is_org_member(c.org_id)
        and private.has_permission(c.org_id, 'repair.case.receive')
    )
  );

create policy repair_imei_evidence_select on storage.objects for select to authenticated
  using (
    bucket_id = 'repair-imei-evidence'
    and (owner_id = (select auth.uid())::text or exists (
      select 1 from public.repair_cases c
      where c.org_id::text = (storage.foldername(name))[1]
        and c.id::text = (storage.foldername(name))[2]
        and c.imei_evidence = name
        and private.is_org_member(c.org_id)
        and private.has_permission(c.org_id, 'repair.case.view')
    ))
  );

create or replace function public.receive_repair_device(
  p_org_id uuid, p_case_id uuid, p_expected_version integer, p_idempotency_key uuid,
  p_method text, p_location text, p_custodian text, p_items text,
  p_verified_imei text default null, p_imei_evidence text default null,
  p_duplicate_reason text default null, p_duplicate_reference text default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_device_id uuid;
  v_duplicate_id uuid;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'repair.case.receive') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1
     or p_method is null or p_method not in ('walk_in', 'post', 'courier', 'agency', 'internal')
     or length(btrim(coalesce(p_location, ''))) = 0
     or length(btrim(coalesce(p_custodian, ''))) = 0
     or (p_verified_imei is not null and (p_verified_imei !~ '^[0-9]{15}$' or length(btrim(coalesce(p_imei_evidence, ''))) = 0))
     or (p_verified_imei is null and p_imei_evidence is not null) then
    raise exception 'INVALID_RECEIPT_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(jsonb_build_object('caseId', p_case_id, 'expectedVersion', p_expected_version,
    'method', p_method, 'location', btrim(p_location), 'custodian', btrim(p_custodian), 'items', p_items,
    'imei', p_verified_imei, 'evidence', p_imei_evidence, 'duplicateReason', p_duplicate_reason,
    'duplicateReference', p_duplicate_reference)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.receive:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'receive' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases
    where id = p_case_id and org_id = p_org_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'intake' or v_case.received_at is not null then
    raise exception 'RECEIPT_ALREADY_RECORDED' using errcode = '23514';
  end if;
  if p_verified_imei is not null then
    if v_case.raw_identifier ~ '^[0-9]{15}$' and v_case.raw_identifier <> p_verified_imei then
      raise exception 'IDENTITY_CORRECTION_REQUIRED' using errcode = '23514';
    end if;
    -- The evidence must be a real private Storage object in this case, uploaded
    -- by the acting receiver. A text reference alone can never verify an IMEI.
    if p_imei_evidence !~ ('^' || p_org_id::text || '/' || p_case_id::text || '/[0-9a-f-]{36}\.(jpg|png|webp)$')
       or not exists (
         select 1 from storage.objects o
         where o.bucket_id = 'repair-imei-evidence'
           and o.name = p_imei_evidence
           and o.owner_id = v_actor::text
           and o.metadata->>'mimetype' in ('image/jpeg', 'image/png', 'image/webp')
           and o.metadata->>'size' ~ '^[0-9]+$'
           and (o.metadata->>'size')::bigint between 1 and 5242880
       ) then
      raise exception 'IMEI_EVIDENCE_REQUIRED' using errcode = '23514';
    end if;
    insert into public.repair_devices (org_id, imei, first_verified_by, first_evidence)
      values (p_org_id, p_verified_imei, v_actor, btrim(p_imei_evidence))
      on conflict (org_id, imei) do nothing;
    select id into v_device_id from public.repair_devices
      where org_id = p_org_id and imei = p_verified_imei for update;
    select id into v_duplicate_id from public.repair_cases
      where org_id = p_org_id and verified_device_id = v_device_id
        and closed_at is null and id <> p_case_id
      order by created_at limit 1;
    if v_duplicate_id is not null then
      if not private.has_permission(p_org_id, 'repair.case.duplicate.override')
         or length(btrim(coalesce(p_duplicate_reason, ''))) = 0
         or length(btrim(coalesce(p_duplicate_reference, ''))) = 0 then
        raise exception 'ACTIVE_REPAIR_CASE_EXISTS' using errcode = '23505';
      end if;
    elsif p_duplicate_reason is not null or p_duplicate_reference is not null then
      raise exception 'DUPLICATE_OVERRIDE_NOT_APPLICABLE' using errcode = '23514';
    end if;
  elsif p_duplicate_reason is not null or p_duplicate_reference is not null then
    raise exception 'DUPLICATE_OVERRIDE_NOT_APPLICABLE' using errcode = '23514';
  end if;
  update public.repair_cases set
    received_at = now(), receipt_method = p_method, receipt_items = coalesce(p_items, ''),
    device_location = btrim(p_location), device_custodian = btrim(p_custodian),
    verified_device_id = v_device_id,
    imei_evidence = case when v_device_id is null then null else btrim(p_imei_evidence) end,
    imei_verified_by = case when v_device_id is null then null else v_actor end,
    imei_verified_at = case when v_device_id is null then null else now() end,
    duplicate_exception_reason = case when v_duplicate_id is null then null else btrim(p_duplicate_reason) end,
    duplicate_exception_reference = case when v_duplicate_id is null then null else btrim(p_duplicate_reference) end,
    raw_identifier = coalesce(raw_identifier, p_verified_imei), version = version + 1
    where id = p_case_id and org_id = p_org_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
    values (p_org_id, p_case_id, 'received', v_actor, jsonb_build_object('method', p_method, 'location', btrim(p_location)));
  if v_device_id is not null then
    insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
      values (p_org_id, p_case_id, 'imei_verified', v_actor, jsonb_build_object('deviceId', v_device_id, 'evidence', btrim(p_imei_evidence)));
  end if;
  if v_duplicate_id is not null then
    insert into public.repair_case_events (org_id, case_id, event_type, actor_id, details)
      values (p_org_id, p_case_id, 'duplicate_override', v_actor,
        jsonb_build_object('existingCaseId', v_duplicate_id, 'reason', btrim(p_duplicate_reason), 'reference', btrim(p_duplicate_reference)));
  end if;
  v_response := jsonb_build_object('caseId', v_case.id, 'version', v_case.version,
    'verifiedDeviceId', v_device_id, 'duplicateException', v_duplicate_id is not null);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'receive', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
