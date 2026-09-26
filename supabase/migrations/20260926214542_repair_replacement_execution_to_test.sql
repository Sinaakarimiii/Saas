-- Execution records the actual serial-numbered swap. Allocation alone is not execution.
insert into public.permissions(key,label_fa,description_fa,scope_options) values
 ('repair.replacement.execute','ثبت اجرای تعویض','ثبت عمل تعویض دستگاه مشخص با شاهد','{}'),
 ('case.transition.T07','ارجاع تعویض به آزمون','انتقال تعویض اجراشده به کنترل عملکرد','{}')
on conflict(key) do nothing;
insert into public.role_permissions(role_id,permission_key,scope)
select r.id,p.key,null from public.roles r cross join public.permissions p
where r.is_system and r.name='مالک' and r.deleted_at is null
 and p.key in ('repair.replacement.execute','case.transition.T07')
on conflict(role_id,permission_key) do nothing;

alter table public.repair_replacement_allocations
 add constraint repair_replacement_allocations_execution_key unique(org_id,case_id,plan_id,device_id,id);

create table public.repair_replacement_executions (
 id uuid primary key default gen_random_uuid(),
 org_id uuid not null, case_id uuid not null, plan_id uuid not null,
 original_device_id uuid not null, replacement_device_id uuid not null,
 allocation_id uuid not null,
 replacement_stage_entered_at timestamptz not null,
 execution_reference text not null check(length(pg_catalog.btrim(execution_reference)) between 1 and 160),
 evidence_reference text not null check(length(pg_catalog.btrim(evidence_reference)) between 1 and 500),
 original_disposition_pending text not null check(original_disposition_pending in ('return_to_customer','scrap_proposed','refurbish_proposed','parts_proposed')),
 executed_by uuid not null references auth.users(id),
 executed_at timestamptz not null default pg_catalog.clock_timestamp(),
 unique(org_id,execution_reference), unique(org_id,case_id,replacement_stage_entered_at),
 unique(org_id,case_id,id),
 foreign key(org_id,case_id,plan_id) references public.repair_action_plans(org_id,case_id,id),
 foreign key(org_id,case_id) references public.repair_cases(org_id,id),
 foreign key(org_id,original_device_id) references public.repair_devices(org_id,id),
 foreign key(org_id,replacement_device_id) references public.repair_replacement_stock(org_id,device_id),
 foreign key(org_id,case_id,plan_id,replacement_device_id,allocation_id)
  references public.repair_replacement_allocations(org_id,case_id,plan_id,device_id,id),
 check(original_device_id<>replacement_device_id)
);
create index repair_replacement_executions_case_idx on public.repair_replacement_executions(org_id,case_id,executed_at desc);
alter table public.repair_replacement_executions enable row level security;
create policy repair_replacement_executions_select on public.repair_replacement_executions for select to authenticated
 using(private.is_org_member(org_id) and private.has_permission(org_id,'repair.case.view'));
revoke all on public.repair_replacement_executions from public,anon,authenticated;
grant select on public.repair_replacement_executions to authenticated;

create function public.execute_repair_replacement_for_test(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid,
 p_execution_reference text,p_evidence_reference text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_stock public.repair_replacement_stock; v_allocation public.repair_replacement_allocations;
 v_original public.repair_device_custody_positions; v_replacement public.repair_device_custody_positions;
 v_execution public.repair_replacement_executions; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or not private.is_org_member(p_org_id)
  or not private.has_permission(p_org_id,'repair.replacement.execute')
  or not private.has_permission(p_org_id,'case.transition.T07') then
  raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 or p_idempotency_key is null
  or length(pg_catalog.btrim(coalesce(p_execution_reference,''))) not between 1 and 160
  or length(pg_catalog.btrim(coalesce(p_evidence_reference,''))) not between 1 and 500 then
  raise exception 'INVALID_REPLACEMENT_EXECUTION' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('case',p_case_id,'version',p_expected_version,
  'reference',pg_catalog.btrim(p_execution_reference),'evidence',pg_catalog.btrim(p_evidence_reference))::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.replacement.execute:'||p_org_id::text||':'||v_actor::text||':'||p_idempotency_key::text,0));
 select * into v_saved from private.repair_command_receipts where org_id=p_org_id and actor_id=v_actor
  and operation='replacement.execute' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if not found then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'replacement' or v_case.verified_device_id is null then
  raise exception 'REPLACEMENT_STAGE_REQUIRED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans where org_id=p_org_id and case_id=p_case_id
  order by revision desc limit 1;
 if v_plan.id is null or v_plan.route<>'replacement' then
  raise exception 'CURRENT_PLAN_REQUIRED' using errcode='23514'; end if;
 if (select decision from public.repair_plan_approvals where org_id=p_org_id and case_id=p_case_id
   and plan_id=v_plan.id and kind='replacement' order by recorded_at desc,id desc limit 1) is distinct from 'approved'
  or (select decision from public.repair_plan_approvals where org_id=p_org_id and case_id=p_case_id
   and plan_id=v_plan.id and kind='customer' order by recorded_at desc,id desc limit 1) is distinct from 'approved' then
  raise exception 'REPLACEMENT_APPROVAL_REQUIRED' using errcode='23514'; end if;
 select * into v_stock from public.repair_replacement_stock where org_id=p_org_id
  and allocated_case_id=p_case_id and status='allocated' for update;
 if v_stock.device_id is null or v_stock.allocated_plan_id<>v_plan.id or v_stock.model<>v_plan.replacement_model
  or v_stock.device_id=v_case.verified_device_id then
  raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 select * into v_allocation from public.repair_replacement_allocations where org_id=p_org_id
  and case_id=p_case_id and plan_id=v_plan.id and device_id=v_stock.device_id
  order by allocated_at desc limit 1;
 if v_allocation.id is null then raise exception 'REPLACEMENT_STOCK_UNAVAILABLE' using errcode='23514'; end if;
 select * into v_original from public.repair_device_custody_positions where org_id=p_org_id
  and case_id=p_case_id and device_id=v_case.verified_device_id;
 select * into v_replacement from public.repair_device_custody_positions where org_id=p_org_id
  and case_id=p_case_id and device_id=v_stock.device_id;
 if v_original.device_id is null or v_replacement.device_id is null
  or v_original.holder_kind<>'staff' or v_original.custodian_user_id is null
  or v_replacement.holder_kind<>'staff' or v_replacement.custodian_user_id is null
  or v_stock.custodian_user_id<>v_replacement.custodian_user_id
  or v_stock.location<>v_replacement.location
  or exists(select 1 from public.repair_device_custody_transfers t where t.org_id=p_org_id
   and t.device_id in (v_case.verified_device_id,v_stock.device_id) and t.status='in_transit')
  or exists(select 1 from public.repair_device_custody_discrepancies d where d.org_id=p_org_id
   and d.device_id in (v_case.verified_device_id,v_stock.device_id) and d.status='open') then
  raise exception 'DEVICE_CUSTODY_UNRESOLVED' using errcode='23514'; end if;
 v_at:=pg_catalog.clock_timestamp();
 insert into public.repair_replacement_executions(org_id,case_id,plan_id,original_device_id,
  replacement_device_id,allocation_id,replacement_stage_entered_at,execution_reference,
  evidence_reference,original_disposition_pending,executed_by,executed_at)
 values(p_org_id,p_case_id,v_plan.id,v_case.verified_device_id,v_stock.device_id,v_allocation.id,
  v_case.stage_entered_at,pg_catalog.btrim(p_execution_reference),pg_catalog.btrim(p_evidence_reference),
  v_plan.original_disposition,v_actor,v_at) returning * into v_execution;
 update public.repair_cases set stage='test',stage_entered_at=v_at,version=version+1
  where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,
  pg_catalog.jsonb_build_object('transitionCode','T07','from','replacement','to','test',
   'planId',v_plan.id,'executionId',v_execution.id,'originalDeviceId',v_execution.original_device_id,
   'replacementDeviceId',v_execution.replacement_device_id,'reference',v_execution.execution_reference));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','test','version',v_case.version,
  'transitionCode','T07','executionId',v_execution.id);
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'replacement.execute',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
revoke all on function public.execute_repair_replacement_for_test(uuid,uuid,integer,uuid,text,text) from public,anon,authenticated;
grant execute on function public.execute_repair_replacement_for_test(uuid,uuid,integer,uuid,text,text) to authenticated;

-- A privileged stage update must not bypass the actual serial execution record.
create function private.guard_replacement_test_stage() returns trigger language plpgsql set search_path='' as $$
begin
 if old.stage='replacement' and new.stage='test' and not exists(
  select 1 from public.repair_replacement_executions e
  where e.org_id=new.org_id and e.case_id=new.id
   and e.original_device_id=new.verified_device_id
   and e.replacement_stage_entered_at=old.stage_entered_at
   and e.executed_at<=new.stage_entered_at
 ) then raise exception 'REPLACEMENT_EXECUTION_REQUIRED' using errcode='23514'; end if;
 return new;
end; $$;
revoke all on function private.guard_replacement_test_stage() from public,anon,authenticated;
create trigger replacement_test_stage_guard before update of stage on public.repair_cases
for each row execute function private.guard_replacement_test_stage();
