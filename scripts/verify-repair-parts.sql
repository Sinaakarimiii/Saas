\set ON_ERROR_STOP on
begin;
create temp table part_fixture as select gen_random_uuid() org_id, gen_random_uuid() actor_id,
 gen_random_uuid() role_id, gen_random_uuid() case_a, gen_random_uuid() case_b,
 gen_random_uuid() diagnosis_a, gen_random_uuid() diagnosis_b,
 gen_random_uuid() plan_a, gen_random_uuid() plan_b;
insert into auth.users(id,aud,role,email)
select actor_id,'authenticated','authenticated','parts-owner@example.test' from part_fixture;
insert into public.organizations(id,name,created_by)
select org_id,'Parts verification',actor_id from part_fixture;
insert into public.roles(id,org_id,name,is_system)
select role_id,org_id,'Parts operator',false from part_fixture;
insert into public.org_members(org_id,user_id,role_id)
select org_id,actor_id,role_id from part_fixture;
insert into public.role_permissions(role_id,permission_key)
select role_id,key from part_fixture cross join public.permissions
where key in ('repair.case.view','repair.part.receive','repair.part.require','repair.part.reserve','case.transition.T03','repair.plan.record');
insert into public.repair_cases(id,org_id,created_by,customer_name,device_model,issue,priority,source,stage,stage_entered_at)
select case_a,org_id,actor_id,'Customer A','Model','Issue','normal','walk_in','decision',clock_timestamp()-interval '1 hour' from part_fixture
union all select case_b,org_id,actor_id,'Customer B','Model','Issue','normal','walk_in','decision',clock_timestamp()-interval '1 hour' from part_fixture;
insert into public.repair_diagnoses(id,org_id,case_id,revision,status,findings,technical_condition,recommended_action,warranty_coverage,created_by,finalized_by,finalized_at)
select diagnosis_a,org_id,case_a,1,'final','Needs part','needs_repair','repair','covered',actor_id,actor_id,clock_timestamp() from part_fixture
union all select diagnosis_b,org_id,case_b,1,'final','Needs part','needs_repair','repair','covered',actor_id,actor_id,clock_timestamp() from part_fixture;
insert into public.repair_action_plans(id,org_id,case_id,diagnosis_id,revision,route,scope,financial_basis,amount_irr,parts_strategy,created_by)
select plan_a,org_id,case_a,diagnosis_a,1,'repair','Replace board','warranty',0,'requires_parts',actor_id from part_fixture
union all select plan_b,org_id,case_b,diagnosis_b,1,'repair','Replace board','warranty',0,'requires_parts',actor_id from part_fixture;
grant select on part_fixture to authenticated;
set local role authenticated;
do $$
declare f record; v_part uuid; v_response jsonb; v_new_plan uuid:=gen_random_uuid();
begin
 select * into f from part_fixture;
 perform set_config('request.jwt.claim.sub',f.actor_id::text,true);
 begin
  perform public.transition_repair_case(f.org_id,f.case_a,1,'T03',gen_random_uuid());
  raise exception 'T03 without requirements accepted';
 exception when check_violation then
  if sqlerrm<>'PARTS_READINESS_REQUIRED' then raise; end if;
 end;
 v_response:=public.receive_repair_part(f.org_id,'BOARD-1','Main board',1,'receipt-1',gen_random_uuid());
 v_part:=(v_response->>'partId')::uuid;
 perform public.require_repair_part(f.org_id,f.case_a,f.plan_a,v_part,1,1,gen_random_uuid());
 perform public.require_repair_part(f.org_id,f.case_b,f.plan_b,v_part,1,1,gen_random_uuid());
 begin
  perform public.transition_repair_case(f.org_id,f.case_a,2,'T03',gen_random_uuid());
  raise exception 'T03 before reservation accepted';
 exception when check_violation then
  if sqlerrm<>'PARTS_READINESS_REQUIRED' then raise; end if;
 end;
 perform public.reserve_repair_part(f.org_id,f.case_a,f.plan_a,v_part,2,gen_random_uuid());
 begin
  perform public.reserve_repair_part(f.org_id,f.case_b,f.plan_b,v_part,2,gen_random_uuid());
  raise exception 'Last part reserved twice';
 exception when check_violation then
  if sqlerrm<>'PART_STOCK_INSUFFICIENT' then raise; end if;
 end;
 -- A revised plan releases the old reservation. This makes stock available to case B.
 v_response:=public.save_repair_action_plan(f.org_id,f.case_a,3,gen_random_uuid(),
   'repair','Revised','warranty',0,'requires_parts',null,null,null);
 v_new_plan:=(v_response->>'planId')::uuid;
 if (select status from public.repair_part_reservations where plan_id=f.plan_a)<>'released' then
  raise exception 'Old reservation not released';
 end if;
 perform public.reserve_repair_part(f.org_id,f.case_b,f.plan_b,v_part,2,gen_random_uuid());
 if (public.transition_repair_case(f.org_id,f.case_b,3,'T03',gen_random_uuid())->>'stage')<>'repair' then
  raise exception 'Ready repair did not advance';
 end if;
 begin
  perform public.transition_repair_case(f.org_id,f.case_a,4,'T03',gen_random_uuid());
  raise exception 'Revised unready plan advanced';
 exception when check_violation then
  if sqlerrm<>'PARTS_READINESS_REQUIRED' then raise; end if;
 end;
 raise notice 'stock receipt, readiness gate, shortage, revision release and T03 passed';
end $$;
rollback;
