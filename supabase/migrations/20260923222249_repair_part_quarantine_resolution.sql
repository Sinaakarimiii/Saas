-- Explicit inspection of returned repair parts. Rejected items remain held; only inspected reusable stock is released.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.part.quarantine.restock','آزادسازی قطعه قرنطینه','تأیید بررسی و بازگرداندن قطعه به موجودی قابل استفاده','{}'),
 ('repair.part.quarantine.reject','رد قطعه قرنطینه','ثبت قطعه مردود در نگهداری جداگانه بدون ورود به موجودی آزاد','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
and p.key in ('repair.part.quarantine.restock','repair.part.quarantine.reject')
on conflict(role_id,permission_key) do nothing;

create table public.repair_part_quarantine_resolutions (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, plan_id uuid not null, part_id uuid not null,
 return_movement_id uuid not null,
 outcome text not null check(outcome in ('released_to_stock','rejected_hold')),
 quantity integer not null check(quantity>0),
 inspection_note text not null check(length(btrim(inspection_note)) between 1 and 1000),
 evidence_reference text not null check(length(btrim(evidence_reference)) between 1 and 240),
 decision_reference text not null check(length(btrim(decision_reference)) between 1 and 240),
 decided_by uuid not null references auth.users(id),
 decided_at timestamptz not null default clock_timestamp(),
 unique(org_id,decision_reference),
 foreign key(org_id,case_id,plan_id,part_id,return_movement_id)
  references public.repair_part_movements(org_id,case_id,plan_id,part_id,id)
);
create index repair_part_quarantine_resolutions_return_idx
 on public.repair_part_quarantine_resolutions(org_id,return_movement_id);
create index repair_part_quarantine_resolutions_case_idx
 on public.repair_part_quarantine_resolutions(org_id,case_id,decided_at desc);
alter table public.repair_part_quarantine_resolutions enable row level security;
create policy repair_part_quarantine_resolutions_read on public.repair_part_quarantine_resolutions
 for select to authenticated using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_part_quarantine_resolutions from public,anon,authenticated;
grant select on public.repair_part_quarantine_resolutions to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
 check(event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
 'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
 'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
 'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
 'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved'));

create function public.resolve_repair_part_quarantine(
 p_org_id uuid,p_case_id uuid,p_return_movement_id uuid,p_outcome text,p_quantity integer,
 p_inspection_note text,p_evidence_reference text,p_decision_reference text,
 p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_return public.repair_part_movements; v_part public.repair_parts;
 v_resolved bigint; v_resolution public.repair_part_quarantine_resolutions; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_return_movement_id is null
 or p_outcome not in ('released_to_stock','rejected_hold')
 or not private.is_org_member(p_org_id)
 or not private.has_permission(p_org_id,case when p_outcome='released_to_stock'
   then 'repair.part.quarantine.restock' else 'repair.part.quarantine.reject' end)
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or p_idempotency_key is null
 or p_quantity is null or p_quantity<=0
 or length(btrim(coalesce(p_inspection_note,''))) not between 1 and 1000
 or length(btrim(coalesce(p_evidence_reference,''))) not between 1 and 240
 or length(btrim(coalesce(p_decision_reference,''))) not between 1 and 240
 then raise exception 'INVALID_QUARANTINE_RESOLUTION' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'return',p_return_movement_id,
 'outcome',p_outcome,'quantity',p_quantity,'note',btrim(p_inspection_note),
 'evidence',btrim(p_evidence_reference),'reference',btrim(p_decision_reference),
 'version',p_expected_version)::text);
 perform pg_advisory_xact_lock(hashtextextended(
  'part.quarantine.resolve:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts
 where org_id=p_org_id and actor_id=v_actor and operation='part.quarantine.resolve'
 and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage not in ('repair','test','delivery') then
  raise exception 'QUARANTINE_STAGE_REQUIRED' using errcode='23514'; end if;
 -- Lock order: case, stock item, then return record. Concurrent decisions recheck the remainder.
 select * into v_return from public.repair_part_movements
 where org_id=p_org_id and case_id=p_case_id and id=p_return_movement_id
 and kind='return_quarantine';
 if not found then raise exception 'PART_QUARANTINE_RETURN_REQUIRED' using errcode='23514'; end if;
 select * into v_part from public.repair_parts where org_id=p_org_id and id=v_return.part_id for update;
 if not found or (p_outcome='released_to_stock' and not v_part.active) then
  raise exception 'PART_CATALOG_CONFLICT' using errcode='23514'; end if;
 select * into v_return from public.repair_part_movements
 where org_id=p_org_id and case_id=p_case_id and id=p_return_movement_id
 and kind='return_quarantine' for update;
 select coalesce(sum(quantity),0) into v_resolved from public.repair_part_quarantine_resolutions
 where org_id=p_org_id and return_movement_id=p_return_movement_id;
 if v_resolved+p_quantity>v_return.quantity then
  raise exception 'QUARANTINE_QUANTITY_EXCEEDED' using errcode='23514'; end if;
 insert into public.repair_part_quarantine_resolutions(
 org_id,case_id,plan_id,part_id,return_movement_id,outcome,quantity,
 inspection_note,evidence_reference,decision_reference,decided_by)
 values(p_org_id,p_case_id,v_return.plan_id,v_return.part_id,p_return_movement_id,p_outcome,
 p_quantity,btrim(p_inspection_note),btrim(p_evidence_reference),btrim(p_decision_reference),v_actor)
 returning * into v_resolution;
 if p_outcome='released_to_stock' then
  update public.repair_parts set on_hand=on_hand+p_quantity where id=v_part.id;
 end if;
 update public.repair_cases set version=version+1 where id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'part_quarantine_resolved',v_actor,
  jsonb_build_object('resolutionId',v_resolution.id,'returnMovementId',p_return_movement_id,
   'outcome',p_outcome,'quantity',p_quantity,'reference',btrim(p_decision_reference)));
 v_response:=jsonb_build_object('caseId',p_case_id,'resolutionId',v_resolution.id,
  'outcome',p_outcome,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'part.quarantine.resolve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.resolve_repair_part_quarantine(uuid,uuid,uuid,text,integer,text,text,text,integer,uuid)
 from public,anon,authenticated;
grant execute on function public.resolve_repair_part_quarantine(uuid,uuid,uuid,text,integer,text,text,text,integer,uuid)
 to authenticated;
