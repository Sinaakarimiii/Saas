-- Damage returned from either outgoing route requires a fresh test/QC cycle.
update public.permissions set description_fa='ثبت خروج دستگاه عودتی یا تعمیرشده به حامل با مدرک و کد رهگیری'
where key='repair.delivery.dispatch';

create or replace function public.return_repair_case_to_test_after_damage(
 p_org_id uuid,p_case_id uuid,p_expected_version integer,p_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_hash text; v_saved private.repair_command_receipts;
 v_case public.repair_cases; v_plan public.repair_action_plans;
 v_check_id uuid; v_check_epoch integer; v_at timestamptz; v_response jsonb;
begin
 if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
  or not private.is_org_member(p_org_id) or not private.has_permission(p_org_id,'case.transition.T11')
 then raise exception 'PERMISSION_DENIED' using errcode='42501'; end if;
 if p_expected_version is null or p_expected_version<1 then
  raise exception 'INVALID_TRANSITION_INPUT' using errcode='23514'; end if;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_object('caseId',p_case_id,
  'expectedVersion',p_expected_version,'transitionCode','T11')::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'repair.transition:'||p_org_id||':'||v_actor||':'||p_idempotency_key,0));
 select * into v_saved from private.repair_command_receipts
  where org_id=p_org_id and actor_id=v_actor and operation='transition' and idempotency_key=p_idempotency_key;
 if found then
  if v_saved.request_hash<>v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode='23505'; end if;
  return v_saved.response; end if;
 select * into v_case from public.repair_cases where org_id=p_org_id and id=p_case_id for update;
 if v_case.id is null then raise exception 'CASE_NOT_FOUND' using errcode='P0002'; end if;
 if v_case.version<>p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode='P0001'; end if;
 if v_case.stage<>'delivery' or v_case.verified_device_id is null then
  raise exception 'TRANSITION_NOT_ALLOWED' using errcode='23514'; end if;
 select * into v_plan from public.repair_action_plans
  where org_id=p_org_id and case_id=p_case_id order by revision desc limit 1;
 if v_plan.id is null or v_plan.route not in ('return','repair') then
  raise exception 'TRANSITION_NOT_ALLOWED' using errcode='23514'; end if;
 if v_plan.route='return' then
  select c.id,c.custody_damage_epoch into v_check_id,v_check_epoch
   from public.repair_return_outgoing_checks c
   where c.org_id=p_org_id and c.case_id=p_case_id order by c.revision desc limit 1;
 else
  select c.id,c.custody_damage_epoch into v_check_id,v_check_epoch
   from public.repair_outgoing_checks c
   where c.org_id=p_org_id and c.case_id=p_case_id order by c.revision desc limit 1;
 end if;
 if v_check_id is null or v_check_epoch>=v_case.custody_damage_epoch
  or not exists(select 1 from public.repair_delivery_dispatch_returns dr
   join public.repair_delivery_dispatches dd on dd.org_id=dr.org_id and dd.case_id=dr.case_id and dd.id=dr.dispatch_id
   where dr.org_id=p_org_id and dr.case_id=p_case_id and dr.device_id=v_case.verified_device_id
    and dr.received_at>=v_case.stage_entered_at and dd.status='returned'
    and (v_plan.route='return' and dd.outgoing_check_id=v_check_id
      or v_plan.route='repair' and dd.repair_outgoing_check_id=v_check_id))
  and not exists(select 1 from public.repair_device_custody_discrepancies d
   join public.repair_device_custody_transfers t on t.org_id=d.org_id and t.id=d.transfer_id
   where d.org_id=p_org_id and d.case_id=p_case_id and d.device_id=v_case.verified_device_id
    and d.kind='damage' and d.recorded_at>=v_case.stage_entered_at and t.status='returned') then
  raise exception 'CUSTODY_DAMAGE_RETURN_REQUIRED' using errcode='23514'; end if;
 if exists(select 1 from public.repair_delivery_receipts r where r.org_id=p_org_id and r.case_id=p_case_id)
  or exists(select 1 from public.repair_delivery_dispatches d
   where d.org_id=p_org_id and d.case_id=p_case_id and d.status='in_transit') then
  raise exception 'DELIVERY_ALREADY_RELEASED' using errcode='23514'; end if;
 v_at:=pg_catalog.clock_timestamp();
 update public.repair_cases set stage='test',stage_entered_at=v_at,version=version+1
  where org_id=p_org_id and id=p_case_id returning * into v_case;
 insert into public.repair_case_events(org_id,case_id,event_type,actor_id,occurred_at,details)
 values(p_org_id,p_case_id,'stage_transition',v_actor,v_at,pg_catalog.jsonb_build_object(
  'transitionCode','T11','from','delivery','to','test','reason','physical_damage_return',
  'previousCheckId',v_check_id,'damageEpoch',v_case.custody_damage_epoch));
 v_response:=pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','test','version',v_case.version,'transitionCode','T11');
 insert into private.repair_command_receipts(org_id,actor_id,operation,idempotency_key,request_hash,response)
 values(p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
 return v_response;
end; $$;
