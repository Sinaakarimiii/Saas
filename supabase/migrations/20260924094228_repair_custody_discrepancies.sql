-- A discrepancy belongs to one physical transfer and never substitutes for a receipt.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
('custody.transfer.discrepancy.record','ثبت مغایرت پذیرش داخلی','ثبت مغایرت حواله توسط گیرنده مقصد','{}'),
('custody.transfer.discrepancy.resolve','رفع مغایرت پذیرش داخلی','رفع مستند مغایرت پس از بررسی','{}')
on conflict (key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
and p.key in ('custody.transfer.discrepancy.record','custody.transfer.discrepancy.resolve')
on conflict (role_id,permission_key) do nothing;

alter table public.repair_device_custody_transfers add column version integer not null default 1 check(version>0);
create table public.repair_device_custody_discrepancies (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null,
 case_id uuid not null,
 device_id uuid not null,
 transfer_id uuid not null,
 kind text not null check(kind in ('identity_mismatch','destination_mismatch','damage')),
 reference text not null check(length(btrim(reference)) between 1 and 160),
 evidence text not null check(length(btrim(evidence)) between 1 and 240),
 responsible_user_id uuid not null references auth.users(id),
 due_at timestamptz not null,
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 status text not null default 'open' check(status in ('open','resolved')),
 resolution_reference text,
 resolution_evidence text,
 resolved_by uuid references auth.users(id),
 resolved_at timestamptz,
 version integer not null default 1 check(version>0),
 unique(org_id,reference),
 foreign key(org_id,transfer_id) references public.repair_device_custody_transfers(org_id,id),
 foreign key(org_id,case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,device_id) references public.repair_devices(org_id,id),
 check((status='open' and resolution_reference is null and resolution_evidence is null and resolved_by is null and resolved_at is null)
 or (status='resolved' and length(btrim(resolution_reference)) between 1 and 160
 and length(btrim(resolution_evidence)) between 1 and 240 and resolved_by is not null and resolved_at is not null))
);
create unique index repair_custody_one_open_discrepancy on public.repair_device_custody_discrepancies(org_id,transfer_id) where status='open';
create unique index repair_custody_discrepancy_resolution_ref on public.repair_device_custody_discrepancies(org_id,resolution_reference) where resolution_reference is not null;
create index repair_custody_discrepancy_queue on public.repair_device_custody_discrepancies(org_id,responsible_user_id,due_at) where status='open';
alter table public.repair_device_custody_discrepancies enable row level security;
create policy repair_custody_discrepancies_select on public.repair_device_custody_discrepancies for select to authenticated
using(private.is_org_member(org_id) and (private.has_permission(org_id,'repair.case.view') or responsible_user_id=(select auth.uid())));
revoke all on public.repair_device_custody_discrepancies from public,anon,authenticated;
grant select on public.repair_device_custody_discrepancies to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
check (event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved',
'custody_baseline_recorded','custody_released','custody_accepted','custody_returned',
'custody_discrepancy_recorded','custody_discrepancy_resolved'));

create function public.record_repair_custody_discrepancy(
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
 if not found or v_transfer.status<>'in_transit' or v_transfer.device_id is distinct from v_case.verified_device_id
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
 values(p_org_id,p_case_id,'custody_discrepancy_recorded',v_actor,pg_catalog.jsonb_build_object('discrepancyId',v_item.id,'transferId',p_transfer_id,'deviceId',v_transfer.device_id,'kind',p_kind,'reference',btrim(p_reference),'responsibleUserId',p_responsible_user_id,'dueAt',p_due_at));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'discrepancyId',v_item.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.discrepancy.record',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.record_repair_custody_discrepancy(uuid,uuid,uuid,text,text,text,uuid,timestamptz,integer,integer,uuid) from public,anon,authenticated;
grant execute on function public.record_repair_custody_discrepancy(uuid,uuid,uuid,text,text,text,uuid,timestamptz,integer,integer,uuid) to authenticated;

create function public.resolve_repair_custody_discrepancy(
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
 if not found or v_item.status<>'open' or v_item.device_id is distinct from v_case.verified_device_id
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
 values(p_org_id,p_case_id,'custody_discrepancy_resolved',v_actor,pg_catalog.jsonb_build_object('discrepancyId',p_discrepancy_id,'transferId',v_transfer.id,'kind',v_item.kind,'reference',btrim(p_reference),'evidence',btrim(p_evidence),'requiresTestReview',v_item.kind='damage'));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'discrepancyId',p_discrepancy_id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'custody.discrepancy.resolve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.resolve_repair_custody_discrepancy(uuid,uuid,uuid,text,text,integer,integer,integer,uuid) from public,anon,authenticated;
grant execute on function public.resolve_repair_custody_discrepancy(uuid,uuid,uuid,text,text,integer,integer,integer,uuid) to authenticated;

create function private.guard_repair_custody_receipt() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status='accepted' and old.status='in_transit' and exists(
  select 1 from public.repair_device_custody_discrepancies d
  where d.org_id=old.org_id and d.transfer_id=old.id and d.status='open'
 ) then raise exception 'CUSTODY_DISCREPANCY_OPEN' using errcode='23514'; end if;
 if new.status is distinct from old.status then new.version:=old.version+1; end if;
 return new;
end; $$;
create trigger repair_custody_receipt_guard before update of status on public.repair_device_custody_transfers
for each row execute function private.guard_repair_custody_receipt();
