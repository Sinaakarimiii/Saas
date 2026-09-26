-- Documented stock receipts and plan-specific reservations. No consumption is recorded here.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
 ('repair.part.receive','ثبت ورود قطعه','ثبت ورود مستند قطعه به موجودی سازمان','{}'),
 ('repair.part.require','تعیین قطعهٔ برنامه','ثبت نیاز قطعه برای نسخهٔ جاری برنامه','{}'),
 ('repair.part.reserve','رزرو قطعه','رزرو قطعهٔ موجود برای نسخهٔ جاری برنامه','{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, p.key, null from public.roles r cross join public.permissions p
where r.is_system and r.name = 'مالک' and r.deleted_at is null
and p.key in ('repair.part.receive','repair.part.require','repair.part.reserve')
on conflict (role_id, permission_key) do nothing;

create table public.repair_parts (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations(id),
 sku text not null check (length(btrim(sku)) between 1 and 64),
 name text not null check (length(btrim(name)) between 1 and 160),
 on_hand integer not null default 0 check (on_hand >= 0),
 active boolean not null default true,
 unique(org_id,id), unique(org_id,sku)
);
create table public.repair_part_receipts (
 id uuid primary key default gen_random_uuid(), org_id uuid not null,
 part_id uuid not null, quantity integer not null check(quantity > 0),
 evidence_reference text not null check(length(btrim(evidence_reference)) between 1 and 240),
 recorded_by uuid not null references auth.users(id), recorded_at timestamptz not null default clock_timestamp(),
 foreign key(org_id,part_id) references public.repair_parts(org_id,id),
 unique(org_id,evidence_reference)
);
create table public.repair_plan_part_requirements (
 id uuid primary key default gen_random_uuid(), org_id uuid not null, case_id uuid not null,
 plan_id uuid not null, part_id uuid not null, quantity integer not null check(quantity > 0),
 recorded_by uuid not null references auth.users(id), recorded_at timestamptz not null default clock_timestamp(),
 foreign key(org_id,case_id,plan_id) references public.repair_action_plans(org_id,case_id,id),
 foreign key(org_id,part_id) references public.repair_parts(org_id,id),
 unique(org_id,plan_id,part_id), unique(org_id,plan_id,part_id,quantity)
);
create table public.repair_part_reservations (
 id uuid primary key default gen_random_uuid(), org_id uuid not null, case_id uuid not null,
 plan_id uuid not null, part_id uuid not null, quantity integer not null check(quantity > 0),
 status text not null default 'active' check(status in ('active','released')),
 reserved_by uuid not null references auth.users(id), reserved_at timestamptz not null default clock_timestamp(),
 released_at timestamptz,
 foreign key(org_id,plan_id,part_id,quantity)
   references public.repair_plan_part_requirements(org_id,plan_id,part_id,quantity),
 foreign key(org_id,case_id,plan_id) references public.repair_action_plans(org_id,case_id,id),
 unique(org_id,plan_id,part_id),
 check((status='active' and released_at is null) or (status='released' and released_at is not null))
);
create index repair_part_reservations_active_idx on public.repair_part_reservations(org_id,part_id) where status='active';

alter table public.repair_parts enable row level security;
alter table public.repair_part_receipts enable row level security;
alter table public.repair_plan_part_requirements enable row level security;
alter table public.repair_part_reservations enable row level security;
create policy repair_parts_read on public.repair_parts for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
create policy repair_part_receipts_read on public.repair_part_receipts for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.part.receive'));
create policy repair_plan_part_requirements_read on public.repair_plan_part_requirements for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
create policy repair_part_reservations_read on public.repair_part_reservations for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_parts, public.repair_part_receipts, public.repair_plan_part_requirements, public.repair_part_reservations from public, anon, authenticated;
grant select on public.repair_parts, public.repair_plan_part_requirements, public.repair_part_reservations to authenticated;
grant select on public.repair_part_receipts to authenticated;

alter table public.repair_case_events drop constraint repair_case_events_event_type_check;
alter table public.repair_case_events add constraint repair_case_events_event_type_check
 check(event_type in ('created','received','imei_verified','duplicate_override','stage_transition',
 'diagnosis_saved','diagnosis_finalized','plan_saved','plan_approval_recorded','return_authorized',
 'return_outgoing_checked','return_outgoing_released','assignment_requested','assignment_accepted',
 'assignment_rejected','assignment_withdrawn','part_required','part_reserved','part_reservation_released'));

-- A new plan revision supersedes its predecessor. The case row is locked by save_repair_action_plan.
create function private.release_superseded_repair_parts() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
 update public.repair_part_reservations set status='released', released_at=clock_timestamp()
 where org_id=new.org_id and case_id=new.case_id and plan_id<>new.id and status='active';
 get diagnostics v_count = row_count;
 if v_count > 0 then
  insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
  values(new.org_id,new.case_id,'part_reservation_released',new.created_by,
    jsonb_build_object('newPlanId',new.id,'releasedCount',v_count));
 end if;
 return new;
end; $$;
create trigger repair_plan_release_old_parts after insert on public.repair_action_plans
for each row execute function private.release_superseded_repair_parts();

create function public.receive_repair_part(
 p_org_id uuid,p_sku text,p_name text,p_quantity integer,p_evidence_reference text,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_part public.repair_parts; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.part.receive')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or length(btrim(coalesce(p_sku,''))) not between 1 and 64
 or length(btrim(coalesce(p_name,''))) not between 1 and 160 or p_quantity is null or p_quantity <= 0
 or length(btrim(coalesce(p_evidence_reference,''))) not between 1 and 240
 then raise exception 'INVALID_PART_INPUT' using errcode='23514'; end if;
 v_hash := md5(jsonb_build_object('sku',upper(btrim(p_sku)),'name',btrim(p_name),
  'quantity',p_quantity,'evidence',btrim(p_evidence_reference))::text);
 perform pg_advisory_xact_lock(hashtextextended('part.receive:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='part.receive' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 insert into public.repair_parts(org_id,sku,name) values(p_org_id,upper(btrim(p_sku)),btrim(p_name))
 on conflict(org_id,sku) do nothing;
 select * into v_part from public.repair_parts where org_id=p_org_id and sku=upper(btrim(p_sku)) for update;
 if not v_part.active or v_part.name<>btrim(p_name) then raise exception 'PART_CATALOG_CONFLICT' using errcode='23514'; end if;
 insert into public.repair_part_receipts(org_id,part_id,quantity,evidence_reference,recorded_by)
 values(p_org_id,v_part.id,p_quantity,btrim(p_evidence_reference),v_actor);
 update public.repair_parts set on_hand=on_hand+p_quantity where id=v_part.id returning * into v_part;
 v_response:=jsonb_build_object('partId',v_part.id,'onHand',v_part.on_hand);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'part.receive',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create function public.require_repair_part(
 p_org_id uuid,p_case_id uuid,p_plan_id uuid,p_part_id uuid,p_quantity integer,
 p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans; v_part public.repair_parts; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'repair.part.require')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_idempotency_key is null or p_quantity is null or p_quantity<=0 or p_expected_version is null
 then raise exception 'INVALID_PART_INPUT' using errcode='23514'; end if;
 v_hash:=md5(jsonb_build_object('case',p_case_id,'plan',p_plan_id,'part',p_part_id,
  'quantity',p_quantity,'version',p_expected_version)::text);
 perform pg_advisory_xact_lock(hashtextextended('part.require:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
 and operation='part.require' and idempotency_key=p_idempotency_key;
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
 select * into v_part from public.repair_parts where org_id=p_org_id and id=p_part_id;
 if not found or not v_part.active then raise exception 'PART_CATALOG_CONFLICT' using errcode='23514'; end if;
 insert into public.repair_plan_part_requirements(org_id,case_id,plan_id,part_id,quantity,recorded_by)
 values(p_org_id,p_case_id,p_plan_id,p_part_id,p_quantity,v_actor);
 update public.repair_cases set version=version+1 where id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,details)
 values(p_org_id,p_case_id,'part_required',v_actor,jsonb_build_object('planId',p_plan_id,'partId',p_part_id,'quantity',p_quantity));
 v_response:=jsonb_build_object('caseId',p_case_id,'version',v_case.version);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'part.require',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;

create function public.reserve_repair_part(
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
 select coalesce(sum(quantity),0) into v_reserved from public.repair_part_reservations
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

revoke all on function public.receive_repair_part(uuid,text,text,integer,text,uuid) from public,anon,authenticated;
revoke all on function public.require_repair_part(uuid,uuid,uuid,uuid,integer,integer,uuid) from public,anon,authenticated;
revoke all on function public.reserve_repair_part(uuid,uuid,uuid,uuid,integer,uuid) from public,anon,authenticated;
grant execute on function public.receive_repair_part(uuid,text,text,integer,text,uuid) to authenticated;
grant execute on function public.require_repair_part(uuid,uuid,uuid,uuid,integer,integer,uuid) to authenticated;
grant execute on function public.reserve_repair_part(uuid,uuid,uuid,uuid,integer,uuid) to authenticated;

create or replace function public.transition_repair_case(
  p_org_id uuid, p_case_id uuid, p_expected_version integer,
  p_transition_code text, p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_diagnosis public.repair_diagnoses;
  v_plan public.repair_action_plans;
  v_return_authorization public.repair_return_authorizations;
  v_check public.repair_return_outgoing_checks;
  v_release public.repair_return_outgoing_releases;
  v_customer_decision text;
  v_replacement_decision text;
  v_from text;
  v_to text;
  v_at timestamptz;
  v_previous_entered_at timestamptz;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or p_transition_code is null or p_transition_code not in ('T01', 'T02', 'T03', 'T04', 'T05', 'T08', 'T10')
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'case.transition.' || p_transition_code)
     or (p_transition_code = 'T02' and not private.has_permission(p_org_id, 'repair.diagnosis.finalize')) then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'INVALID_TRANSITION_INPUT' using errcode = '23514';
  end if;
  v_hash := md5(pg_catalog.jsonb_build_object('caseId', p_case_id,
    'expectedVersion', p_expected_version, 'transitionCode', p_transition_code)::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.transition:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'transition' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases
    where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  v_from := v_case.stage;
  if p_transition_code = 'T01' and v_from = 'intake' then
    v_to := 'diagnosis';
    if v_case.received_at is null or nullif(pg_catalog.btrim(coalesce(v_case.device_location, '')), '') is null
       or nullif(pg_catalog.btrim(coalesce(v_case.device_custodian, '')), '') is null
       or (v_case.verified_device_id is null and nullif(pg_catalog.btrim(coalesce(v_case.raw_identifier, '')), '') is null)
       or nullif(pg_catalog.btrim(v_case.device_model), '') is null
       or nullif(pg_catalog.btrim(v_case.issue), '') is null then
      raise exception 'INTAKE_INCOMPLETE' using errcode = '23514';
    end if;
  elsif p_transition_code = 'T02' and v_from = 'diagnosis' then
    select * into v_diagnosis from public.repair_diagnoses
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if not found or v_diagnosis.status <> 'final'
       or v_diagnosis.created_at < v_case.stage_entered_at
       or v_diagnosis.finalized_at < v_case.stage_entered_at
       or v_diagnosis.technical_condition = 'unknown' then
      raise exception 'FINAL_DIAGNOSIS_REQUIRED' using errcode = '23514';
    end if;
    v_to := 'decision';
  elsif p_transition_code in ('T03', 'T04') and v_from = 'decision' then
    select * into v_plan from public.repair_action_plans
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    select * into v_diagnosis from public.repair_diagnoses
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if v_plan.id is null or v_diagnosis.id is null or v_plan.created_at < v_case.stage_entered_at
       or v_plan.diagnosis_id <> v_diagnosis.id or v_diagnosis.status <> 'final'
       or v_plan.route <> (case when p_transition_code = 'T03' then 'repair' else 'replacement' end) then
      raise exception 'CURRENT_PLAN_REQUIRED' using errcode = '23514';
    end if;
    if v_diagnosis.warranty_coverage = 'pending'
       or (v_plan.financial_basis = 'warranty' and v_diagnosis.warranty_coverage <> 'covered')
       or (v_plan.financial_basis = 'customer_paid' and v_diagnosis.warranty_coverage <> 'not_covered')
       or v_plan.financial_basis = 'none' then
      raise exception 'FINANCIAL_BASIS_UNRESOLVED' using errcode = '23514';
    end if;
    if v_plan.financial_basis = 'customer_paid' or p_transition_code = 'T04' then
      select decision into v_customer_decision from public.repair_plan_approvals
        where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id and kind = 'customer'
        order by recorded_at desc, id desc limit 1;
      if v_customer_decision is distinct from 'approved' then
        raise exception 'CUSTOMER_APPROVAL_REQUIRED' using errcode = '23514';
      end if;
    end if;
    if p_transition_code = 'T03' then
      if v_plan.parts_strategy = 'requires_parts' then
        if not exists (select 1 from public.repair_plan_part_requirements
          where org_id=p_org_id and plan_id=v_plan.id)
          or exists (select 1 from public.repair_plan_part_requirements req
            where req.org_id=p_org_id and req.plan_id=v_plan.id
            and not exists (select 1 from public.repair_part_reservations res
              where res.org_id=req.org_id and res.plan_id=req.plan_id
              and res.part_id=req.part_id and res.quantity=req.quantity and res.status='active'))
        then raise exception 'PARTS_READINESS_REQUIRED' using errcode='23514'; end if;
      elsif v_plan.parts_strategy <> 'no_parts' then
        raise exception 'PARTS_READINESS_REQUIRED' using errcode='23514';
      end if;
      v_to := 'repair';
    else
      select decision into v_replacement_decision from public.repair_plan_approvals
        where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id and kind = 'replacement'
        order by recorded_at desc, id desc limit 1;
      if v_replacement_decision is distinct from 'approved' then
        raise exception 'REPLACEMENT_APPROVAL_REQUIRED' using errcode = '23514';
      end if;
      v_to := 'replacement';
    end if;
  elsif p_transition_code = 'T05' and v_from = 'decision' then
    select * into v_plan from public.repair_action_plans
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    select * into v_diagnosis from public.repair_diagnoses
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if v_plan.id is null or v_diagnosis.id is null or v_plan.created_at < v_case.stage_entered_at
       or v_plan.diagnosis_id <> v_diagnosis.id or v_diagnosis.status <> 'final'
       or v_diagnosis.recommended_action <> 'return' or v_plan.route <> 'return'
       or v_plan.financial_basis <> 'none' or v_plan.amount_irr <> 0 then
      raise exception 'CURRENT_PLAN_REQUIRED' using errcode = '23514';
    end if;
    select * into v_return_authorization from public.repair_return_authorizations
      where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id;
    if not found or v_return_authorization.protocol_code <> 'return_outgoing_v1' then
      raise exception 'RETURN_AUTHORIZATION_REQUIRED' using errcode = '23514';
    end if;
    v_to := 'test';
  elsif p_transition_code = 'T08' and v_from = 'test' then
    select * into v_plan from public.repair_action_plans
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if v_plan.id is null or v_plan.route <> 'return' then
      raise exception 'RETURN_QC_REQUIRED' using errcode = '23514';
    end if;
    select * into v_return_authorization from public.repair_return_authorizations
      where org_id = p_org_id and case_id = p_case_id and plan_id = v_plan.id;
    select * into v_check from public.repair_return_outgoing_checks
      where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
    if v_return_authorization.id is null or v_check.id is null
       or v_check.plan_id <> v_plan.id or v_check.authorization_id <> v_return_authorization.id
       or v_check.device_id is distinct from v_case.verified_device_id
       or v_check.created_at < v_case.stage_entered_at
       or not (v_check.identity_pass and v_check.items_pass and v_check.condition_pass and v_check.transport_pass) then
      raise exception 'RETURN_QC_REQUIRED' using errcode = '23514';
    end if;
    select * into v_release from public.repair_return_outgoing_releases
      where org_id = p_org_id and case_id = p_case_id and check_id = v_check.id;
    if v_release.id is null then
      raise exception 'QUALITY_RELEASE_REQUIRED' using errcode = '23514';
    end if;
    v_to := 'delivery';
  elsif p_transition_code = 'T10' and v_from = 'diagnosis' then
    v_to := 'intake';
  else
    raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '23514';
  end if;
  v_at := pg_catalog.clock_timestamp();
  v_previous_entered_at := v_case.stage_entered_at;
  update public.repair_cases set stage = v_to, stage_entered_at = v_at, version = version + 1
    where org_id = p_org_id and id = p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, occurred_at, details)
    values (p_org_id, p_case_id, 'stage_transition', v_actor, v_at,
      pg_catalog.jsonb_build_object('transitionCode', p_transition_code, 'from', v_from,
        'to', v_to, 'previousStageEnteredAt', v_previous_entered_at) ||
        case when p_transition_code = 'T02' then pg_catalog.jsonb_build_object('diagnosisId', v_diagnosis.id)
          when p_transition_code in ('T03', 'T04') then pg_catalog.jsonb_build_object('diagnosisId', v_diagnosis.id, 'planId', v_plan.id, 'planRevision', v_plan.revision)
          when p_transition_code = 'T05' then pg_catalog.jsonb_build_object('diagnosisId', v_diagnosis.id, 'planId', v_plan.id, 'returnAuthorizationId', v_return_authorization.id)
          when p_transition_code = 'T08' then pg_catalog.jsonb_build_object('planId', v_plan.id, 'outgoingCheckId', v_check.id, 'qualityReleaseId', v_release.id)
          else '{}'::jsonb end);
  v_response := pg_catalog.jsonb_build_object('caseId', p_case_id, 'stage', v_to,
    'version', v_case.version, 'transitionCode', p_transition_code);
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id, v_actor, 'transition', p_idempotency_key, v_hash, v_response);
  return v_response;
end;
$$;
