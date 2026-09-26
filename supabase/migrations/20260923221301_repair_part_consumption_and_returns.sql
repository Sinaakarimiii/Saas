-- Repair execution movements: consumption, unused-reservation release, and quarantined returns.
insert into public.permissions (key,label_fa,description_fa,scope_options) values
 ('repair.part.consume','مصرف قطعه','ثبت اقدام تعمیر و حواله مصرف از رزرو','{}'),
 ('repair.part.release','آزادسازی قطعه','آزادسازی مانده رزرو مصرف‌نشده با علت و مرجع','{}'),
 ('repair.part.return','بازگشت قطعه','ثبت بازگشت قطعه مصرف‌شده به قرنطینه','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
and p.key in ('repair.part.consume','repair.part.release','repair.part.return')
on conflict(role_id,permission_key) do nothing;

alter table public.repair_part_reservations add column consumed_quantity integer not null default 0;
alter table public.repair_part_reservations add constraint repair_part_reservations_consumed_quantity_check
 check(consumed_quantity between 0 and quantity);
alter table public.repair_part_reservations drop constraint repair_part_reservations_status_check;
alter table public.repair_part_reservations add constraint repair_part_reservations_status_check
 check(status in ('active','released','consumed'));
alter table public.repair_part_reservations drop constraint repair_part_reservations_check;
alter table public.repair_part_reservations add constraint repair_part_reservations_lifecycle_check
 check((status='active' and released_at is null and consumed_quantity<quantity)
 or (status='released' and released_at is not null and consumed_quantity<quantity)
 or (status='consumed' and released_at is null and consumed_quantity=quantity));
alter table public.repair_part_reservations add constraint repair_part_reservations_movement_fk_unique
 unique(org_id,case_id,plan_id,part_id,id);

create table public.repair_part_movements (
 id uuid primary key default gen_random_uuid(), org_id uuid not null, case_id uuid not null,
 plan_id uuid not null, part_id uuid not null, reservation_id uuid not null,
 kind text not null check(kind in ('consumption','return_quarantine')),
 quantity integer not null check(quantity>0),
 reference text not null check(length(btrim(reference)) between 1 and 240),
 action_description text,
 reason text,
 source_consumption_id uuid,
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(org_id,reference), unique(org_id,case_id,plan_id,part_id,id),
 foreign key(org_id,case_id,plan_id,part_id,reservation_id)
  references public.repair_part_reservations(org_id,case_id,plan_id,part_id,id),
 foreign key(org_id,case_id,plan_id,part_id,source_consumption_id)
  references public.repair_part_movements(org_id,case_id,plan_id,part_id,id),
 check((kind='consumption' and length(btrim(action_description)) between 1 and 2000
    and reason is null and source_consumption_id is null)
    or (kind='return_quarantine' and action_description is null
    and length(btrim(reason)) between 1 and 500 and source_consumption_id is not null))
);
create index repair_part_movements_case_idx on public.repair_part_movements(org_id,case_id,recorded_at desc);
create index repair_part_movements_source_idx on public.repair_part_movements(org_id,source_consumption_id)
 where source_consumption_id is not null;
alter table public.repair_part_movements enable row level security;
create policy repair_part_movements_read on public.repair_part_movements for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_part_movements from public,anon,authenticated;
grant select on public.repair_part_movements to authenticated;

create table public.repair_part_reservation_releases (
 id uuid primary key default gen_random_uuid(), org_id uuid not null, case_id uuid not null,
 plan_id uuid not null, part_id uuid not null, reservation_id uuid not null,
 quantity integer not null check(quantity>0),
 reason text not null check(length(btrim(reason)) between 1 and 500),
 reference text not null check(length(btrim(reference)) between 1 and 240),
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(org_id,reference), unique(org_id,reservation_id),
 foreign key(org_id,case_id,plan_id,part_id,reservation_id)
  references public.repair_part_reservations(org_id,case_id,plan_id,part_id,id)
);
alter table public.repair_part_reservation_releases enable row level security;
create policy repair_part_reservation_releases_read on public.repair_part_reservation_releases for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_part_reservation_releases from public,anon,authenticated;
grant select on public.repair_part_reservation_releases to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
 check(event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
 'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
 'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
 'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
 'part_consumed','part_returned_quarantine','part_unused_released'));

create function public.consume_repair_part(
 p_org_id uuid,p_case_id uuid,p_plan_id uuid,p_part_id uuid,p_quantity integer,
 p_action_description text,p_reference text,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_part public.repair_parts;
 v_res public.repair_part_reservations; v_movement public.repair_part_movements; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.part.consume')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_expected_version is null or p_quantity is null or p_quantity<=0
 or length(btrim(coalesce(p_action_description,''))) not between 1 and 2000
 or length(btrim(coalesce(p_reference,''))) not between 1 and 240
 then raise exception 'INVALID_PART_MOVEMENT' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'plan',p_plan_id,'part',p_part_id,
 'quantity',p_quantity,'action',btrim(p_action_description),'reference',btrim(p_reference),'version',p_expected_version)::text);
 perform pg_advisory_xact_lock(hashtextextended('part.consume:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='part.consume' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'repair' then raise exception 'REPAIR_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_plan.id is distinct from p_plan_id or v_plan.route<>'repair' or v_plan.parts_strategy<>'requires_parts'
 then raise exception 'PLAN_REVISION_CONFLICT' using errcode='23514'; end if;
 -- All stock-changing commands lock case then item. The quantity is rechecked under the item lock.
 select * into v_part from public.repair_parts where org_id=p_org_id and id=p_part_id for update;
 if not found or not v_part.active then raise exception 'PART_CATALOG_CONFLICT' using errcode='23514'; end if;
 select * into v_res from public.repair_part_reservations
 where org_id=p_org_id and case_id=p_case_id and plan_id=p_plan_id and part_id=p_part_id for update;
 if not found or v_res.status<>'active' or v_res.quantity-v_res.consumed_quantity<p_quantity
 then raise exception 'PART_RESERVATION_INSUFFICIENT' using errcode='23514'; end if;
 if v_part.on_hand<p_quantity then raise exception 'PART_STOCK_INSUFFICIENT' using errcode='23514'; end if;
 update public.repair_parts set on_hand=on_hand-p_quantity where id=v_part.id;
 update public.repair_part_reservations
 set consumed_quantity=consumed_quantity+p_quantity,
 status=case when consumed_quantity+p_quantity=quantity then 'consumed' else 'active' end
 where id=v_res.id;
 insert into public.repair_part_movements(org_id,case_id,plan_id,part_id,reservation_id,kind,
 quantity,reference,action_description,recorded_by)
 values(p_org_id,p_case_id,p_plan_id,p_part_id,v_res.id,'consumption',p_quantity,
 btrim(p_reference),btrim(p_action_description),v_actor) returning * into v_movement;
 update public.repair_cases set version=version+1 where id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'part_consumed',v_actor,jsonb_build_object('movementId',v_movement.id,
 'planId',p_plan_id,'partId',p_part_id,'quantity',p_quantity,'reference',btrim(p_reference)));
 v_response:=jsonb_build_object('caseId',p_case_id,'movementId',v_movement.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'part.consume',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create function public.return_consumed_repair_part(
 p_org_id uuid,p_case_id uuid,p_consumption_id uuid,p_quantity integer,p_reason text,
 p_reference text,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_part public.repair_parts; v_consumption public.repair_part_movements;
 v_returned bigint; v_movement public.repair_part_movements; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.part.return')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_expected_version is null or p_quantity is null or p_quantity<=0
 or length(btrim(coalesce(p_reason,''))) not between 1 and 500
 or length(btrim(coalesce(p_reference,''))) not between 1 and 240
 then raise exception 'INVALID_PART_MOVEMENT' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'consumption',p_consumption_id,
 'quantity',p_quantity,'reason',btrim(p_reason),'reference',btrim(p_reference),'version',p_expected_version)::text);
 perform pg_advisory_xact_lock(hashtextextended('part.return:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='part.return' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'repair' then raise exception 'REPAIR_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_consumption from public.repair_part_movements
 where org_id=p_org_id and case_id=p_case_id and id=p_consumption_id and kind='consumption';
 if not found then raise exception 'PART_CONSUMPTION_REQUIRED' using errcode='23514'; end if;
 select * into v_part from public.repair_parts where org_id=p_org_id and id=v_consumption.part_id for update;
 select * into v_consumption from public.repair_part_movements
 where org_id=p_org_id and case_id=p_case_id and id=p_consumption_id and kind='consumption' for update;
 select coalesce(sum(quantity),0) into v_returned from public.repair_part_movements
 where org_id=p_org_id and source_consumption_id=p_consumption_id and kind='return_quarantine';
 if v_returned+p_quantity>v_consumption.quantity then
  raise exception 'PART_RETURN_EXCEEDS_CONSUMPTION' using errcode='23514'; end if;
 insert into public.repair_part_movements(org_id,case_id,plan_id,part_id,reservation_id,kind,
 quantity,reference,reason,source_consumption_id,recorded_by)
 values(p_org_id,p_case_id,v_consumption.plan_id,v_consumption.part_id,v_consumption.reservation_id,
 'return_quarantine',p_quantity,btrim(p_reference),btrim(p_reason),p_consumption_id,v_actor)
 returning * into v_movement;
 update public.repair_cases set version=version+1 where id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'part_returned_quarantine',v_actor,jsonb_build_object('movementId',v_movement.id,
 'sourceConsumptionId',p_consumption_id,'partId',v_consumption.part_id,'quantity',p_quantity,'reference',btrim(p_reference)));
 v_response:=jsonb_build_object('caseId',p_case_id,'movementId',v_movement.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'part.return',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create function public.release_unused_repair_part(
 p_org_id uuid,p_case_id uuid,p_plan_id uuid,p_part_id uuid,p_reason text,p_reference text,
 p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_part public.repair_parts;
 v_res public.repair_part_reservations; v_released integer; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.part.release')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_expected_version is null
 or length(btrim(coalesce(p_reason,''))) not between 1 and 500
 or length(btrim(coalesce(p_reference,''))) not between 1 and 240
 then raise exception 'INVALID_PART_MOVEMENT' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'plan',p_plan_id,'part',p_part_id,
 'reason',btrim(p_reason),'reference',btrim(p_reference),'version',p_expected_version)::text);
 perform pg_advisory_xact_lock(hashtextextended('part.release:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='part.release' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'repair' then raise exception 'REPAIR_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_plan.id is distinct from p_plan_id or v_plan.route<>'repair'
 then raise exception 'PLAN_REVISION_CONFLICT' using errcode='23514'; end if;
 select * into v_part from public.repair_parts where org_id=p_org_id and id=p_part_id for update;
 if not found then raise exception 'PART_CATALOG_CONFLICT' using errcode='23514'; end if;
 select * into v_res from public.repair_part_reservations
 where org_id=p_org_id and case_id=p_case_id and plan_id=p_plan_id and part_id=p_part_id for update;
 if not found or v_res.status<>'active' then raise exception 'PART_RESERVATION_INSUFFICIENT' using errcode='23514'; end if;
 v_released:=v_res.quantity-v_res.consumed_quantity;
 update public.repair_part_reservations set status='released',released_at=clock_timestamp() where id=v_res.id;
 insert into public.repair_part_reservation_releases(org_id,case_id,plan_id,part_id,reservation_id,
 quantity,reason,reference,recorded_by)
 values(p_org_id,p_case_id,p_plan_id,p_part_id,v_res.id,v_released,btrim(p_reason),btrim(p_reference),v_actor);
 update public.repair_cases set version=version+1 where id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'part_unused_released',v_actor,jsonb_build_object('planId',p_plan_id,
 'partId',p_part_id,'quantity',v_released,'reference',btrim(p_reference)));
 v_response:=jsonb_build_object('caseId',p_case_id,'releasedQuantity',v_released,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'part.release',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

revoke all on function public.consume_repair_part(uuid,uuid,uuid,uuid,integer,text,text,integer,uuid) from public,anon,authenticated;
revoke all on function public.return_consumed_repair_part(uuid,uuid,uuid,integer,text,text,integer,uuid) from public,anon,authenticated;
revoke all on function public.release_unused_repair_part(uuid,uuid,uuid,uuid,text,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.consume_repair_part(uuid,uuid,uuid,uuid,integer,text,text,integer,uuid) to authenticated;
grant execute on function public.return_consumed_repair_part(uuid,uuid,uuid,integer,text,text,integer,uuid) to authenticated;
grant execute on function public.release_unused_repair_part(uuid,uuid,uuid,uuid,text,text,integer,uuid) to authenticated;

create or replace function public.reserve_repair_part(
 p_org_id uuid,p_case_id uuid,p_plan_id uuid,p_part_id uuid,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_part public.repair_parts;
 v_requirement public.repair_plan_part_requirements; v_reserved bigint; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.part.reserve')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_expected_version is null then raise exception 'INVALID_PART_INPUT' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'plan',p_plan_id,'part',p_part_id,'version',p_expected_version)::text);
 perform pg_advisory_xact_lock(hashtextextended('part.reserve:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='part.reserve' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'decision' then raise exception 'DECISION_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_plan.id is distinct from p_plan_id or v_plan.route<>'repair' or v_plan.parts_strategy<>'requires_parts'
 then raise exception 'PLAN_REVISION_CONFLICT' using errcode='23514'; end if;
 select * into v_requirement from public.repair_plan_part_requirements
 where org_id=p_org_id and plan_id=p_plan_id and part_id=p_part_id;
 if not found then raise exception 'PART_REQUIREMENT_REQUIRED' using errcode='23514'; end if;
 -- Lock order is case, then stock row. Every reservation for this part serializes here.
 select * into v_part from public.repair_parts where org_id=p_org_id and id=p_part_id for update;
 if not found or not v_part.active then raise exception 'PART_CATALOG_CONFLICT' using errcode='23514'; end if;
 select coalesce(sum(quantity-consumed_quantity),0) into v_reserved from public.repair_part_reservations
 where org_id=p_org_id and part_id=p_part_id and status='active';
 if v_part.on_hand-v_reserved<v_requirement.quantity then raise exception 'PART_STOCK_INSUFFICIENT' using errcode='23514'; end if;
 insert into public.repair_part_reservations(org_id,case_id,plan_id,part_id,quantity,reserved_by)
 values(p_org_id,p_case_id,p_plan_id,p_part_id,v_requirement.quantity,v_actor);
 update public.repair_cases set version=version+1 where id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'part_reserved',v_actor,jsonb_build_object('planId',p_plan_id,'partId',p_part_id,'quantity',v_requirement.quantity));
 v_response:=jsonb_build_object('caseId',p_case_id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'part.reserve',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
