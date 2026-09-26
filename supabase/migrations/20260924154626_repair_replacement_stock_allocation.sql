-- A replacement is a serial-numbered physical device, not a model name in a plan.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('replacement.stock.receive','دریافت دستگاه جایگزین','ثبت دستگاه سریال‌دار و مبنای محل انبار با مدرک','{}'),
 ('replacement.stock.allocate','تخصیص دستگاه جایگزین','رزرو انحصاری دستگاه مشخص برای برنامهٔ تأییدشده','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
 and p.key in ('replacement.stock.receive','replacement.stock.allocate')
on conflict(role_id,permission_key) do nothing;

create table public.repair_replacement_stock (
 org_id uuid not null,
 device_id uuid not null,
 model text not null check(length(btrim(model)) between 1 and 160),
 receipt_reference text not null check(length(btrim(receipt_reference)) between 1 and 160),
 location text not null check(length(btrim(location)) between 1 and 200),
 custodian_user_id uuid not null references auth.users(id),
 custodian_label text not null check(length(btrim(custodian_label)) between 1 and 160),
 evidence text not null check(length(btrim(evidence)) between 1 and 240),
 received_by uuid not null references auth.users(id),
 received_at timestamptz not null default clock_timestamp(),
 status text not null default 'available' check(status in ('available','allocated')),
 allocated_case_id uuid,
 allocated_plan_id uuid,
 allocated_at timestamptz,
 primary key(org_id,device_id),
 unique(org_id,receipt_reference),
 foreign key(org_id,device_id) references public.repair_devices(org_id,id),
 foreign key(org_id,allocated_case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,allocated_case_id,allocated_plan_id)
  references public.repair_action_plans(org_id,case_id,id),
 check((status='available' and allocated_case_id is null and allocated_plan_id is null and allocated_at is null)
  or (status='allocated' and allocated_case_id is not null and allocated_plan_id is not null and allocated_at is not null))
);
create index repair_replacement_available_model_idx on public.repair_replacement_stock(org_id,model,received_at)
 where status='available';
create unique index repair_replacement_one_allocated_per_case on public.repair_replacement_stock(org_id,allocated_case_id)
 where status='allocated';
create table public.repair_replacement_allocations (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null,
 case_id uuid not null,
 plan_id uuid not null,
 device_id uuid not null,
 allocation_reference text not null check(length(btrim(allocation_reference)) between 1 and 160),
 allocated_by uuid not null references auth.users(id),
 allocated_at timestamptz not null default clock_timestamp(),
 unique(org_id,allocation_reference),
 foreign key(org_id,case_id,plan_id) references public.repair_action_plans(org_id,case_id,id),
 foreign key(org_id,device_id) references public.repair_replacement_stock(org_id,device_id)
);
create index repair_replacement_allocations_case_idx on public.repair_replacement_allocations(org_id,case_id,allocated_at desc);
alter table public.repair_replacement_stock enable row level security;
alter table public.repair_replacement_allocations enable row level security;
create policy repair_replacement_stock_view on public.repair_replacement_stock for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
create policy repair_replacement_allocations_view on public.repair_replacement_allocations for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_replacement_stock,public.repair_replacement_allocations from public,anon,authenticated;
grant select on public.repair_replacement_stock,public.repair_replacement_allocations to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
check(event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released',
'part_consumed','part_returned_quarantine','part_unused_released','part_quarantine_resolved',
'custody_baseline_recorded','custody_released','custody_accepted','custody_returned',
'custody_discrepancy_recorded','custody_discrepancy_resolved','delivery_received','delivery_dispatched',
'delivery_incident_recorded','delivery_incident_followed_up','delivery_incident_resolved',
'delivery_damage_returned','replacement_allocated'));

create function public.receive_repair_replacement_stock(
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
 values(p_org_id,p_imei,v_actor,btrim(p_evidence)) returning * into v_device;
 insert into public.repair_replacement_stock(org_id,device_id,model,receipt_reference,location,
 custodian_user_id,custodian_label,evidence,received_by)
 values(p_org_id,v_device.id,btrim(p_model),btrim(p_receipt_reference),btrim(p_location),
 p_custodian_user_id,v_label,btrim(p_evidence),v_actor);
 v_response:=jsonb_build_object('deviceId',v_device.id,'imei',p_imei);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.stock.receive',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.receive_repair_replacement_stock(uuid,text,text,text,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.receive_repair_replacement_stock(uuid,text,text,text,uuid,text,text,uuid) to authenticated;

create function public.allocate_repair_replacement_device(
 p_org_id uuid,p_case_id uuid,p_device_id uuid,p_plan_id uuid,p_allocation_reference text,
 p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_stock public.repair_replacement_stock; v_allocation public.repair_replacement_allocations;
 v_approval text; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_device_id is null or p_plan_id is null
 or p_idempotency_key is null or not private.is_org_member(p_org_id)
 or not private.has_permission(p_org_id,'replacement.stock.allocate')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1
 or length(btrim(coalesce(p_allocation_reference,''))) not between 1 and 160
 then raise exception 'INVALID_REPLACEMENT_ALLOCATION' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'device',p_device_id,'plan',p_plan_id,
 'reference',btrim(p_allocation_reference),'version',p_expected_version)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('repair.replacement.allocate:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='replacement.allocate' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'replacement' or v_case.verified_device_id is null
 then raise exception 'REPLACEMENT_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id
 order by revision desc limit 1;
 if v_plan.id is distinct from p_plan_id or v_plan.route<>'replacement'
 then raise exception 'CURRENT_PLAN_REQUIRED' using errcode='23514'; end if;
 select decision into v_approval from public.repair_plan_approvals
 where org_id=p_org_id and case_id=p_case_id and plan_id=p_plan_id and kind='replacement'
 order by recorded_at desc,id desc limit 1;
 if v_approval is distinct from 'approved' then raise exception 'REPLACEMENT_APPROVAL_REQUIRED' using errcode='23514'; end if;
 select * into v_stock from public.repair_replacement_stock
 where org_id=p_org_id and device_id=p_device_id for update;
 if not found or v_stock.status<>'available' or v_stock.model<>v_plan.replacement_model
 or v_stock.device_id=v_case.verified_device_id
 then raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 if exists(select 1 from public.repair_replacement_stock where org_id=p_org_id
 and allocated_case_id=p_case_id and status='allocated')
 then raise exception 'REPLACEMENT_ALREADY_ALLOCATED' using errcode='23505'; end if;
 insert into public.repair_replacement_allocations(org_id,case_id,plan_id,device_id,
 allocation_reference,allocated_by)
 values(p_org_id,p_case_id,p_plan_id,p_device_id,btrim(p_allocation_reference),v_actor)
 returning * into v_allocation;
 update public.repair_replacement_stock set status='allocated',allocated_case_id=p_case_id,
 allocated_plan_id=p_plan_id,allocated_at=v_allocation.allocated_at
 where org_id=p_org_id and device_id=p_device_id;
 insert into public.repair_device_custody_positions(org_id,device_id,case_id,location,
 custodian_user_id,custodian_label,baseline_evidence,confirmed_by)
 values(p_org_id,p_device_id,p_case_id,v_stock.location,v_stock.custodian_user_id,
 v_stock.custodian_label,v_stock.evidence,v_actor);
 update public.repair_cases set version=version+1 where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'replacement_allocated',v_actor,
 jsonb_build_object('deviceId',p_device_id,'planId',p_plan_id,'allocationId',v_allocation.id,
 'reference',btrim(p_allocation_reference),'location',v_stock.location,'custodianId',v_stock.custodian_user_id));
 v_response:=jsonb_build_object('caseId',p_case_id,'deviceId',p_device_id,
 'allocationId',v_allocation.id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.allocate',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.allocate_repair_replacement_device(uuid,uuid,uuid,uuid,text,integer,uuid) from public,anon,authenticated;
grant execute on function public.allocate_repair_replacement_device(uuid,uuid,uuid,uuid,text,integer,uuid) to authenticated;
