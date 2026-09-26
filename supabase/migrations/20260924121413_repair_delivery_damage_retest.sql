-- Reopen a return case for a fresh outgoing check after physical damage in delivery.
insert into public.permissions (key, label_fa, description_fa, scope_options) values
  ('case.transition.T11', 'بازگشت تحویل به تست پس از آسیب', 'بازگشت عودت آسیب‌دیده پس از رسید بازگشت فیزیکی برای کنترل خروج تازه', '{}')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_key, scope)
select r.id, 'case.transition.T11', null from public.roles r
where r.is_system and r.name = 'مالک' and r.deleted_at is null
on conflict (role_id, permission_key) do nothing;

create function public.return_repair_case_to_test_after_damage(
  p_org_id uuid, p_case_id uuid, p_expected_version integer, p_idempotency_key uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := auth.uid();
  v_hash text;
  v_saved private.repair_command_receipts;
  v_case public.repair_cases;
  v_plan public.repair_action_plans;
  v_check public.repair_return_outgoing_checks;
  v_at timestamptz;
  v_response jsonb;
begin
  if v_actor is null or p_org_id is null or p_case_id is null or p_idempotency_key is null
     or not private.is_org_member(p_org_id)
     or not private.has_permission(p_org_id, 'case.transition.T11') then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'INVALID_TRANSITION_INPUT' using errcode = '23514';
  end if;
  v_hash := pg_catalog.md5(pg_catalog.jsonb_build_object('caseId', p_case_id,
    'expectedVersion', p_expected_version, 'transitionCode', 'T11')::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'repair.transition:' || p_org_id::text || ':' || v_actor::text || ':' || p_idempotency_key::text, 0));
  select * into v_saved from private.repair_command_receipts
    where org_id = p_org_id and actor_id = v_actor and operation = 'transition' and idempotency_key = p_idempotency_key;
  if found then
    if v_saved.request_hash <> v_hash then raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = '23505'; end if;
    return v_saved.response;
  end if;
  select * into v_case from public.repair_cases where org_id = p_org_id and id = p_case_id for update;
  if not found then raise exception 'CASE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_case.version <> p_expected_version then raise exception 'CASE_VERSION_CONFLICT' using errcode = 'P0001'; end if;
  if v_case.stage <> 'delivery' then raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '23514'; end if;
  select * into v_plan from public.repair_action_plans
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  if v_plan.id is null or v_plan.route <> 'return' or v_case.verified_device_id is null then
    raise exception 'TRANSITION_NOT_ALLOWED' using errcode = '23514';
  end if;
  select * into v_check from public.repair_return_outgoing_checks
    where org_id = p_org_id and case_id = p_case_id order by revision desc limit 1;
  if v_check.id is null or v_check.custody_damage_epoch >= v_case.custody_damage_epoch
     or not exists (select 1 from public.repair_device_custody_discrepancies d
       join public.repair_device_custody_transfers t on t.org_id=d.org_id and t.id=d.transfer_id
       where d.org_id=p_org_id and d.case_id=p_case_id and d.device_id=v_case.verified_device_id
         and d.kind='damage' and d.recorded_at >= v_case.stage_entered_at
         and t.status='returned') then
    raise exception 'CUSTODY_DAMAGE_RETURN_REQUIRED' using errcode = '23514';
  end if;
  v_at := pg_catalog.clock_timestamp();
  update public.repair_cases set stage='test', stage_entered_at=v_at, version=version+1
    where org_id=p_org_id and id=p_case_id returning * into v_case;
  insert into public.repair_case_events (org_id, case_id, event_type, actor_id, occurred_at, details)
    values (p_org_id, p_case_id, 'stage_transition', v_actor, v_at,
      pg_catalog.jsonb_build_object('transitionCode','T11','from','delivery','to','test',
        'reason','custody_damage','previousCheckId',v_check.id,'damageEpoch',v_case.custody_damage_epoch));
  v_response := pg_catalog.jsonb_build_object('caseId',p_case_id,'stage','test',
    'version',v_case.version,'transitionCode','T11');
  insert into private.repair_command_receipts (org_id, actor_id, operation, idempotency_key, request_hash, response)
    values (p_org_id,v_actor,'transition',p_idempotency_key,v_hash,v_response);
  return v_response;
end;
$$;
revoke all on function public.return_repair_case_to_test_after_damage(uuid,uuid,integer,uuid) from public, anon;
grant execute on function public.return_repair_case_to_test_after_damage(uuid,uuid,integer,uuid) to authenticated;

-- A stale release can never become a final handover through another stage writer.
create function private.guard_repair_damage_final_handover() returns trigger
language plpgsql set search_path = '' as $$
declare v_check public.repair_return_outgoing_checks;
begin
  if new.stage='closed' and old.stage='delivery' and exists (
    select 1 from public.repair_action_plans p where p.org_id=new.org_id and p.case_id=new.id
      and p.route='return' and p.revision=(select max(p2.revision) from public.repair_action_plans p2
        where p2.org_id=p.org_id and p2.case_id=p.case_id)) then
    if exists (select 1 from public.repair_device_custody_discrepancies d
      where d.org_id=new.org_id and d.device_id=new.verified_device_id
        and d.kind='damage' and d.status='open') then
      raise exception 'CUSTODY_DAMAGE_REVIEW_REQUIRED' using errcode='23514';
    end if;
    select * into v_check from public.repair_return_outgoing_checks
      where org_id=new.org_id and case_id=new.id order by revision desc limit 1;
    if v_check.id is null or v_check.custody_damage_epoch <> new.custody_damage_epoch
       or not exists (select 1 from public.repair_return_outgoing_releases r
         where r.org_id=new.org_id and r.case_id=new.id and r.check_id=v_check.id)
       or not exists (select 1 from public.repair_case_events e
         where e.org_id=new.org_id and e.case_id=new.id and e.event_type='stage_transition'
           and e.details->>'transitionCode'='T08' and e.details->>'outgoingCheckId'=v_check.id::text
           and e.occurred_at >= v_check.created_at) then
      raise exception 'CUSTODY_DAMAGE_REVIEW_REQUIRED' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger repair_damage_final_handover_guard
before update of stage on public.repair_cases
for each row execute function private.guard_repair_damage_final_handover();
