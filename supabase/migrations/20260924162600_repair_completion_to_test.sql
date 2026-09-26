-- A physical repair completion is distinct from a successful functional test.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.complete','تکمیل عملیات تعمیر','ثبت اقدامات انجام‌شده و انتخاب پروتکل آزمون','{}'),
 ('case.transition.T06','ارجاع تعمیر به آزمون','تکمیل تعمیر و انتقال پرونده به مرحله آزمون','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
 and p.key in ('repair.complete','case.transition.T06')
on conflict(role_id,permission_key) do nothing;

create table public.repair_completions (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, plan_id uuid not null, device_id uuid not null,
 repair_stage_entered_at timestamptz not null,
 protocol_code text not null check(protocol_code='repair_functional_v1'),
 work_description text,
 work_reference text,
 completed_by uuid not null references auth.users(id),
 completed_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,case_id,repair_stage_entered_at),
 unique(org_id,case_id,id),
 foreign key(org_id,case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,case_id,plan_id) references public.repair_action_plans(org_id,case_id,id),
 foreign key(org_id,device_id) references public.repair_devices(org_id,id),
 check ((work_description is null and work_reference is null) or
   (length(pg_catalog.btrim(work_description)) between 1 and 2000
    and length(pg_catalog.btrim(work_reference)) between 1 and 240))
);
create index repair_completions_case_latest_idx on public.repair_completions(org_id,case_id,completed_at desc);
alter table public.repair_completions enable row level security;
create policy repair_completions_select_authorized on public.repair_completions
 for select to authenticated using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_completions from public,anon,authenticated;
grant select on public.repair_completions to authenticated;

create function public.complete_repair_for_test(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_protocol_code text,p_work_description text,p_work_reference text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_completion public.repair_completions; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or not private.is_org_member(p_org_id)
   or not private.has_permission(p_org_id,'repair.complete')
   or not private.has_permission(p_org_id,'case.transition.T06') then
  raise exception 'PERMISSION_DENIED' using errcode='42501';
 end if;
 if p_expected_version is null or p_expected_version<1 or p_idempotency_key is null
   or p_protocol_code is distinct from 'repair_functional_v1'
   or ((nullif(pg_catalog.btrim(coalesce(p_work_description,'')),'') is null)
       <> (nullif(pg_catalog.btrim(coalesce(p_work_reference,'')),'') is null))
   or length(pg_catalog.btrim(coalesce(p_work_description,'')))>2000
   or length(pg_catalog.btrim(coalesce(p_work_reference,'')))>240 then
  raise exception 'INVALID_REPAIR_COMPLETION' using errcode='23514';
 end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,
  'expectedVersion',p_expected_version,'transitionCode','T06','protocol',p_protocol_code,
  'work',pg_catalog.btrim(coalesce(p_work_description,'')),
  'reference',pg_catalog.btrim(coalesce(p_work_reference,'')))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.transition:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
   and operation='transition' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response;
 end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'repair' then raise exception 'TRANSITION_NOT_ALLOWED' using errcode='23514'; end if;
 if v_case.verified_device_id is null then raise exception 'VERIFIED_DEVICE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id
   order by revision desc limit 1;
 if v_plan.id is null or v_plan.route<>'repair' or v_plan.parts_strategy not in ('no_parts','requires_parts')
   then raise exception 'CURRENT_PLAN_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_device_custody_discrepancies d
   where d.org_id=p_org_id and d.device_id=v_case.verified_device_id and d.status='open')
   or exists(select 1 from public.repair_device_custody_transfers t
   where t.org_id=p_org_id and t.device_id=v_case.verified_device_id and t.status='in_transit') then
  raise exception 'DEVICE_CUSTODY_UNRESOLVED' using errcode='23514';
 end if;
 if v_plan.parts_strategy='no_parts' then
  if nullif(pg_catalog.btrim(coalesce(p_work_description,'')),'') is null then
   raise exception 'REPAIR_WORK_REQUIRED' using errcode='23514';
  end if;
 else
  if not exists(select 1 from public.repair_plan_part_requirements r
    where r.org_id=p_org_id and r.case_id=p_case_id and r.plan_id=v_plan.id)
   or exists(select 1 from public.repair_plan_part_requirements r
     where r.org_id=p_org_id and r.case_id=p_case_id and r.plan_id=v_plan.id
      and not exists(select 1 from public.repair_part_reservations s
        where s.org_id=r.org_id and s.case_id=r.case_id and s.plan_id=r.plan_id
          and s.part_id=r.part_id and s.quantity=r.quantity and s.consumed_quantity=r.quantity
          and s.status='consumed'))
   or exists(select 1 from public.repair_part_reservations s
     where s.org_id=p_org_id and s.case_id=p_case_id and s.plan_id=v_plan.id and s.status='active') then
   raise exception 'PART_WORK_INCOMPLETE' using errcode='23514';
  end if;
 end if;
 v_at:=pg_catalog.clock_timestamp();
 insert into public.repair_completions(org_id,case_id,plan_id,device_id,repair_stage_entered_at,
  protocol_code,work_description,work_reference,completed_by,completed_at)
 values(p_org_id,p_case_id,v_plan.id,v_case.verified_device_id,v_case.stage_entered_at,
  p_protocol_code,nullif(pg_catalog.btrim(coalesce(p_work_description,'')),''),
  nullif(pg_catalog.btrim(coalesce(p_work_reference,'')),''),v_actor,v_at)
 returning * into v_completion;
 update public.repair_cases set stage='test',stage_entered_at=v_at,version=version+1
   where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,
  pg_catalog.jsonb_build_object('transitionCode','T06','from','repair','to','test',
   'planId',v_plan.id,'completionId',v_completion.id,'deviceId',v_completion.device_id,
   'protocolCode',p_protocol_code));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','test','version',v_case.version,
  'transitionCode','T06','completionId',v_completion.id);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.complete_repair_for_test(uuid,uuid,integer,uuid,text,text,text) from public,anon;
grant execute on function public.complete_repair_for_test(uuid,uuid,integer,uuid,text,text,text) to authenticated;
