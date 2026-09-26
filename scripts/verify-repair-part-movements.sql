\set ON_ERROR_STOP on
begin;
create temp table movement_fixture as select gen_random_uuid() org_id,gen_random_uuid() actor_id,
 gen_random_uuid() role_id,gen_random_uuid() reviewer_id,gen_random_uuid() reviewer_role_id,
 gen_random_uuid() case_id,gen_random_uuid() diagnosis_id,gen_random_uuid() plan_id;
insert into auth.users(id,aud,role,email)
select actor_id,'authenticated','authenticated','part-movement@example.test' from movement_fixture
union all select reviewer_id,'authenticated','authenticated','part-reviewer@example.test' from movement_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Part movement test',actor_id from movement_fixture;
insert into public.roles(id,org_id,name,is_system)
select role_id,org_id,'Movement operator',false from movement_fixture
union all select reviewer_role_id,org_id,'Reject reviewer',false from movement_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,actor_id,role_id from movement_fixture
union all select org_id,reviewer_id,reviewer_role_id from movement_fixture;
insert into public.role_permissions(role_id,permission_key)
select role_id,key from movement_fixture cross join public.permissions where key in
 ('repair.case.view','repair.part.receive','repair.part.require','repair.part.reserve',
  'repair.part.consume','repair.part.release','repair.part.return',
  'repair.part.quarantine.restock','repair.part.quarantine.reject','case.transition.T03');
insert into public.role_permissions(role_id,permission_key)
select reviewer_role_id,key from movement_fixture cross join public.permissions
where key in ('repair.case.view','repair.part.quarantine.reject');
insert into public.repair_cases(id,org_id,created_by,customer_name,device_model,issue,priority,source,stage,stage_entered_at)
select case_id,org_id,actor_id,'Customer','Model','Issue','normal','walk_in','decision',clock_timestamp()-interval '1 hour' from movement_fixture;
insert into public.repair_diagnoses(id,org_id,case_id,revision,status,findings,technical_condition,
 recommended_action,warranty_coverage,created_by,finalized_by,finalized_at)
select diagnosis_id,org_id,case_id,1,'final','Needs part','needs_repair','repair','covered',actor_id,actor_id,clock_timestamp() from movement_fixture;
insert into public.repair_action_plans(id,org_id,case_id,diagnosis_id,revision,route,scope,financial_basis,amount_irr,parts_strategy,created_by)
select plan_id,org_id,case_id,diagnosis_id,1,'repair','Replace board','warranty',0,'requires_parts',actor_id from movement_fixture;
grant select on movement_fixture to authenticated;
set local role authenticated;
do $$
declare f record; v_part uuid; v_consumption uuid; v_return uuid; v_response jsonb; v_key uuid;
begin
 select * into f from movement_fixture;
 perform set_config('request.jwt.claim.sub',f.actor_id::text,true);
 v_part:=(public.receive_repair_part(f.org_id,'BOARD-M','Board',3,'movement-receipt',gen_random_uuid())->>'partId')::uuid;
 perform public.require_repair_part(f.org_id,f.case_id,f.plan_id,v_part,3,1,gen_random_uuid());
 perform public.reserve_repair_part(f.org_id,f.case_id,f.plan_id,v_part,2,gen_random_uuid());
 perform public.transition_repair_case(f.org_id,f.case_id,3,'T03',gen_random_uuid());
 v_key:=gen_random_uuid();
 v_response:=public.consume_repair_part(f.org_id,f.case_id,f.plan_id,v_part,2,'Board fitted','issue-1',4,v_key);
 if public.consume_repair_part(f.org_id,f.case_id,f.plan_id,v_part,2,'Board fitted','issue-1',4,v_key)<>v_response
 then raise exception 'Consumption retry was not idempotent'; end if;
 v_consumption:=(v_response->>'movementId')::uuid;
 if (select on_hand from public.repair_parts where id=v_part)<>1
 or (select consumed_quantity from public.repair_part_reservations where case_id=f.case_id)<>2
 then raise exception 'Stock and reservation after consumption incorrect'; end if;
 begin
  perform public.consume_repair_part(f.org_id,f.case_id,f.plan_id,v_part,2,'Overuse','issue-over',5,gen_random_uuid());
  raise exception 'Over-consumption accepted';
 exception when check_violation then
  if sqlerrm<>'PART_RESERVATION_INSUFFICIENT' then raise; end if;
 end;
 v_response:=public.return_consumed_repair_part(f.org_id,f.case_id,v_consumption,2,'Faulty board','return-1',5,gen_random_uuid());
 v_return:=(v_response->>'movementId')::uuid;
 if (select on_hand from public.repair_parts where id=v_part)<>1
 then raise exception 'Quarantined return increased usable stock'; end if;
 begin
  perform public.return_consumed_repair_part(f.org_id,f.case_id,v_consumption,1,'Overreturn','return-over',6,gen_random_uuid());
  raise exception 'Over-return accepted';
 exception when check_violation then
  if sqlerrm<>'PART_RETURN_EXCEEDS_CONSUMPTION' then raise; end if;
 end;
 v_key:=gen_random_uuid();
 v_response:=public.resolve_repair_part_quarantine(f.org_id,f.case_id,v_return,'released_to_stock',1,
   'Passed inspection','inspection-1','quarantine-1',6,v_key);
 if public.resolve_repair_part_quarantine(f.org_id,f.case_id,v_return,'released_to_stock',1,
   'Passed inspection','inspection-1','quarantine-1',6,v_key)<>v_response
 then raise exception 'Quarantine retry was not idempotent'; end if;
 if (select on_hand from public.repair_parts where id=v_part)<>2 then
  raise exception 'Inspected item did not enter usable stock exactly once'; end if;
 perform set_config('request.jwt.claim.sub',f.reviewer_id::text,true);
 begin
  perform public.resolve_repair_part_quarantine(f.org_id,f.case_id,v_return,'released_to_stock',1,
    'Unauthorized restock','inspection-no','quarantine-no',7,gen_random_uuid());
  raise exception 'Reject-only reviewer restocked the item';
 exception when insufficient_privilege then
  if sqlerrm<>'PERMISSION_DENIED' then raise; end if;
 end;
 perform public.resolve_repair_part_quarantine(f.org_id,f.case_id,v_return,'rejected_hold',1,
   'Failed inspection','inspection-2','quarantine-2',7,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',f.actor_id::text,true);
 if (select on_hand from public.repair_parts where id=v_part)<>2 then
  raise exception 'Rejected item entered usable stock'; end if;
 begin
  perform public.resolve_repair_part_quarantine(f.org_id,f.case_id,v_return,'released_to_stock',1,
    'Over-resolution','inspection-3','quarantine-over',8,gen_random_uuid());
  raise exception 'Over-resolution accepted';
 exception when check_violation then
  if sqlerrm<>'QUARANTINE_QUANTITY_EXCEEDED' then raise; end if;
 end;
 perform public.release_unused_repair_part(f.org_id,f.case_id,f.plan_id,v_part,'Unused spare','release-1',8,gen_random_uuid());
 if (select status from public.repair_part_reservations where case_id=f.case_id)<>'released'
 or (select quantity from public.repair_part_reservation_releases where case_id=f.case_id)<>1
 or (select on_hand from public.repair_parts where id=v_part)<>2
 then raise exception 'Unused reservation release incorrect'; end if;
 begin
  perform public.consume_repair_part(f.org_id,f.case_id,f.plan_id,v_part,1,'After release','issue-after',9,gen_random_uuid());
  raise exception 'Consumption after release accepted';
 exception when check_violation then
  if sqlerrm<>'PART_RESERVATION_INSUFFICIENT' then raise; end if;
 end;
 if (select coalesce(sum(quantity),0) from public.repair_part_movements where kind='return_quarantine' and case_id=f.case_id)<>2
 then raise exception 'Return ledger mismatch'; end if;
 raise notice 'consumption, return, quarantine inspection, overage and unused release passed';
end $$;
do $$ begin
 begin
  insert into public.repair_part_movements(org_id,case_id,plan_id,part_id,reservation_id,kind,quantity,reference,action_description,recorded_by)
  values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'consumption',1,'direct','direct',gen_random_uuid());
  raise exception 'Direct ledger write accepted';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.repair_part_quarantine_resolutions(org_id,case_id,plan_id,part_id,
    return_movement_id,outcome,quantity,inspection_note,evidence_reference,decision_reference,decided_by)
  values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
    'released_to_stock',1,'direct','direct','direct',gen_random_uuid());
  raise exception 'Direct quarantine decision write accepted';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
