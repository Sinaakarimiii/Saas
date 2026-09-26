-- A carrier incident blocks destination receipt and T09 until separately resolved.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('delivery.incident.record','ثبت مسئله حمل','ثبت مفقودی، آسیب یا اختلاف تحویل برای همان ارسال','{}'),
 ('delivery.incident.followup','پیگیری مسئله حمل','ثبت پیگیری و تغییر مسئول یا موعد مسئله حمل','{}'),
 ('delivery.incident.resolve','رفع مسئله حمل','رفع مستند مفقودی یا اختلاف تحویل بدون ساخت رسید مقصد','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
and p.key in ('delivery.incident.record','delivery.incident.followup','delivery.incident.resolve')
on conflict(role_id,permission_key) do nothing;

create table public.repair_delivery_incidents(
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null,
 case_id uuid not null,
 device_id uuid not null,
 dispatch_id uuid not null,
 kind text not null check(kind in ('lost','damage','delivery_discrepancy')),
 reference text not null check(length(btrim(reference)) between 1 and 160),
 evidence text not null check(length(btrim(evidence)) between 1 and 240),
 responsible_user_id uuid not null references auth.users(id),
 due_at timestamptz not null,
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default pg_catalog.clock_timestamp(),
 status text not null default 'open' check(status in ('open','resolved')),
 resolution_reference text,
 resolution_evidence text,
 resolved_by uuid references auth.users(id),
 resolved_at timestamptz,
 version integer not null default 1 check(version>0),
 unique(org_id,reference),
 unique(org_id,case_id,id),
 foreign key(org_id,case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,device_id) references public.repair_devices(org_id,id),
 foreign key(org_id,case_id,dispatch_id) references public.repair_delivery_dispatches(org_id,case_id,id),
 check((status='open' and resolution_reference is null and resolution_evidence is null and resolved_by is null and resolved_at is null)
 or (status='resolved' and length(btrim(resolution_reference)) between 1 and 160
 and length(btrim(resolution_evidence)) between 1 and 240 and resolved_by is not null and resolved_at is not null))
);
create unique index repair_delivery_one_open_incident on public.repair_delivery_incidents(org_id,dispatch_id) where status='open';
create unique index repair_delivery_incident_resolution_ref on public.repair_delivery_incidents(org_id,resolution_reference) where resolution_reference is not null;
create index repair_delivery_incident_queue on public.repair_delivery_incidents(org_id,due_at,responsible_user_id) where status='open';
alter table public.repair_delivery_incidents enable row level security;
create policy repair_delivery_incidents_select on public.repair_delivery_incidents for select to authenticated
using(private.is_org_member(org_id) and (private.has_permission(org_id,'repair.case.view') or responsible_user_id=(select auth.uid())));
revoke all on public.repair_delivery_incidents from public,anon,authenticated;
grant select on public.repair_delivery_incidents to authenticated;

create table public.repair_delivery_incident_followups(
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null,
 case_id uuid not null,
 incident_id uuid not null,
 reference text not null check(length(btrim(reference)) between 1 and 160),
 outcome text not null check(length(btrim(outcome)) between 1 and 1000),
 next_responsible_user_id uuid not null references auth.users(id),
 next_due_at timestamptz not null,
 incident_version integer not null check(incident_version>0),
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,reference),
 unique(org_id,incident_id,incident_version),
 foreign key(org_id,case_id,incident_id) references public.repair_delivery_incidents(org_id,case_id,id)
);
create index repair_delivery_followups_incident_idx on public.repair_delivery_incident_followups(org_id,incident_id,recorded_at desc);
alter table public.repair_delivery_incident_followups enable row level security;
create policy repair_delivery_incident_followups_select on public.repair_delivery_incident_followups for select to authenticated
using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_delivery_incident_followups from public,anon,authenticated;
grant select on public.repair_delivery_incident_followups to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
check(event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved',
'custody_baseline_recorded','custody_released','custody_accepted','custody_returned',
'custody_discrepancy_recorded','custody_discrepancy_resolved','delivery_received','delivery_dispatched',
'delivery_incident_recorded','delivery_incident_followed_up','delivery_incident_resolved'));

create or replace function private.assert_return_handover_ready(p_org_id uuid,p_case_id uuid)
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
 if exists(select 1 from public.repair_delivery_incidents i
   where i.org_id=p_org_id and i.case_id=p_case_id and i.status='open') then
   raise exception 'DELIVERY_INCIDENT_OPEN' using errcode='23514'; end if;
 return v_check.id;
end;
$$;

create function public.record_repair_delivery_incident(
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
revoke all on function public.record_repair_delivery_incident(uuid,uuid,uuid,text,text,text,uuid,timestamptz,integer,uuid) from public,anon,authenticated;
grant execute on function public.record_repair_delivery_incident(uuid,uuid,uuid,text,text,text,uuid,timestamptz,integer,uuid) to authenticated;

create function public.followup_repair_delivery_incident(
 p_org_id uuid,p_case_id uuid,p_incident_id uuid,p_expected_version integer,p_expected_incident_version integer,
 p_reference text,p_outcome text,p_responsible_user_id uuid,p_due_at timestamptz,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_item public.repair_delivery_incidents;
 v_saved private.repair_command_receipts; v_hash text; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_incident_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'delivery.incident.followup')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_incident_version is null or p_responsible_user_id is null
 or p_due_at is null or p_due_at<=pg_catalog.clock_timestamp()
 or length(btrim(coalesce(p_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_outcome,''))) not between 1 and 1000
 then raise exception 'INVALID_DELIVERY_FOLLOWUP' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('case',p_case_id,'incident',p_incident_id,
 'caseVersion',p_expected_version,'incidentVersion',p_expected_incident_version,'reference',btrim(p_reference),
 'outcome',btrim(p_outcome),'responsible',p_responsible_user_id,'due',p_due_at)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.delivery.incident.followup:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='delivery.incident.followup' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_item from public.repair_delivery_incidents where org_id=p_org_id and case_id=p_case_id and id=p_incident_id for update;
 if v_item.id is null or v_item.status<>'open' or v_case.stage<>'delivery'
 then raise exception 'DELIVERY_INCIDENT_NOT_OPEN' using errcode='23514'; end if;
 if v_item.version<>p_expected_incident_version then raise exception 'DELIVERY_INCIDENT_VERSION_CONFLICT' using errcode='P0001'; end if;
 if not exists(select 1 from public.org_members where org_id=p_org_id and user_id=p_responsible_user_id
 and deleted_at is null and invitation_status='active') then raise exception 'DELIVERY_MEMBER_INACTIVE' using errcode='23514'; end if;
 insert into public.repair_delivery_incident_followups(org_id,case_id,incident_id,reference,outcome,
 next_responsible_user_id,next_due_at,incident_version,recorded_by)
 values(p_org_id,p_case_id,p_incident_id,btrim(p_reference),btrim(p_outcome),p_responsible_user_id,
 p_due_at,v_item.version+1,v_actor);
 update public.repair_delivery_incidents set responsible_user_id=p_responsible_user_id,due_at=p_due_at,version=version+1
 where id=p_incident_id returning * into v_item;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_incident_followed_up',v_actor,pg_catalog.jsonb_build_object(
 'incidentId',p_incident_id,'reference',btrim(p_reference),'outcome',btrim(p_outcome),
 'responsibleUserId',p_responsible_user_id,'dueAt',p_due_at,'incidentVersion',v_item.version));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'incidentId',p_incident_id,
 'version',v_case.version,'incidentVersion',v_item.version,'status',v_item.status);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.incident.followup',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.followup_repair_delivery_incident(uuid,uuid,uuid,integer,integer,text,text,uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.followup_repair_delivery_incident(uuid,uuid,uuid,integer,integer,text,text,uuid,timestamptz,uuid) to authenticated;

create function public.resolve_repair_delivery_incident(
 p_org_id uuid,p_case_id uuid,p_incident_id uuid,p_expected_version integer,p_expected_incident_version integer,
 p_resolution_reference text,p_resolution_evidence text,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_case public.repair_cases; v_item public.repair_delivery_incidents;
 v_saved private.repair_command_receipts; v_hash text; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_incident_id is null or p_idempotency_key is null
 or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'delivery.incident.resolve')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_incident_version is null
 or length(btrim(coalesce(p_resolution_reference,''))) not between 1 and 160
 or length(btrim(coalesce(p_resolution_evidence,''))) not between 1 and 240
 then raise exception 'INVALID_DELIVERY_INCIDENT_RESOLUTION' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('case',p_case_id,'incident',p_incident_id,
 'caseVersion',p_expected_version,'incidentVersion',p_expected_incident_version,
 'reference',btrim(p_resolution_reference),'evidence',btrim(p_resolution_evidence))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.delivery.incident.resolve:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='delivery.incident.resolve' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 select * into v_item from public.repair_delivery_incidents where org_id=p_org_id and case_id=p_case_id and id=p_incident_id for update;
 if v_item.id is null or v_item.status<>'open' or v_case.stage<>'delivery'
 then raise exception 'DELIVERY_INCIDENT_NOT_OPEN' using errcode='23514'; end if;
 if v_item.version<>p_expected_incident_version then raise exception 'DELIVERY_INCIDENT_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_item.kind='damage' then raise exception 'DELIVERY_DAMAGE_RETURN_REQUIRED' using errcode='23514'; end if;
 update public.repair_delivery_incidents set status='resolved',resolution_reference=btrim(p_resolution_reference),
 resolution_evidence=btrim(p_resolution_evidence),resolved_by=v_actor,resolved_at=pg_catalog.clock_timestamp(),version=version+1
 where id=p_incident_id returning * into v_item;
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'delivery_incident_resolved',v_actor,pg_catalog.jsonb_build_object(
 'incidentId',p_incident_id,'kind',v_item.kind,'reference',v_item.resolution_reference,
 'incidentVersion',v_item.version));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'incidentId',p_incident_id,
 'version',v_case.version,'incidentVersion',v_item.version,'status',v_item.status);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'delivery.incident.resolve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.resolve_repair_delivery_incident(uuid,uuid,uuid,integer,integer,text,text,uuid) from public,anon,authenticated;
grant execute on function public.resolve_repair_delivery_incident(uuid,uuid,uuid,integer,integer,text,text,uuid) to authenticated;
