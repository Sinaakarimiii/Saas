#!/usr/bin/env python3
"""Prove one serial-numbered replacement cannot be allocated to two open cases."""
import importlib.util
import json
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('repair_concurrency', ROOT / 'scripts/verify-repair-concurrency.py')
shared = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(shared)
query, contend = shared.query, shared.contend


def setup(label):
    suffix = uuid.uuid4().hex
    sql = f"""\set ON_ERROR_STOP on
begin;
create temp table allocation_fixture as select gen_random_uuid() owner_id,gen_random_uuid() clerk_id,
 gen_random_uuid() org_id,gen_random_uuid() owner_role_id,gen_random_uuid() clerk_role_id;
insert into auth.users(id,aud,role,email)
 select owner_id,'authenticated','authenticated','allocation-owner-{suffix}@example.test' from allocation_fixture
 union all select clerk_id,'authenticated','authenticated','allocation-clerk-{suffix}@example.test' from allocation_fixture;
insert into public.organizations(id,name,created_by)
 select org_id,'Allocation concurrency {label} {suffix}',owner_id from allocation_fixture;
insert into public.roles(id,org_id,name,is_system)
 select owner_role_id,org_id,'Allocation owner',false from allocation_fixture
 union all select clerk_role_id,org_id,'Allocation clerk',false from allocation_fixture;
insert into public.org_members(org_id,user_id,role_id)
 select org_id,owner_id,owner_role_id from allocation_fixture
 union all select org_id,clerk_id,clerk_role_id from allocation_fixture;
insert into public.role_permissions(role_id,permission_key)
 select owner_role_id,key from allocation_fixture cross join public.permissions
 where key like 'repair.case.%' or key like 'repair.diagnosis.%' or key like 'case.transition.%'
 or key in ('repair.plan.record','repair.customer_approval.record','repair.replacement.approve',
  'replacement.stock.receive','replacement.stock.allocate')
 union all select clerk_role_id,'replacement.stock.allocate' from allocation_fixture;
grant select on allocation_fixture to authenticated;
create function pg_temp.allocation_evidence(p_path text,p_owner uuid)
returns void language sql security definer set search_path='' as $$
 insert into storage.objects(bucket_id,name,owner_id,metadata)
 values('repair-imei-evidence',p_path,p_owner::text,'{{"mimetype":"image/png","size":128}}'::jsonb);
$$;
grant execute on function pg_temp.allocation_evidence(text,uuid) to authenticated;
create temp table allocation_result(value jsonb);
grant insert,select on allocation_result to authenticated;
set local role authenticated;
do $$
declare f record; c jsonb; d jsonb; p jsonb; s jsonb; case_id uuid; path text;
 case_a uuid; case_b uuid; plan_a uuid; plan_b uuid;
begin
 select * into f from allocation_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 for i in 1..2 loop
  c:=public.create_repair_case(f.org_id,'GPS','allocation-original-'||i,
   'Synthetic customer','Irreparable','normal','walk_in',gen_random_uuid());
  case_id:=(c->>'caseId')::uuid;
  path:=f.org_id||'/'||case_id||'/'||gen_random_uuid()||'.png';
  perform pg_temp.allocation_evidence(path,f.owner_id);
  perform public.receive_repair_device(f.org_id,case_id,1,gen_random_uuid(),
   'walk_in','Synthetic branch '||i,'Owner','charger',
   case when i=1 then '900000000000101' else '900000000000102' end,path);
  perform public.transition_repair_case(f.org_id,case_id,2,'T01',gen_random_uuid());
  d:=public.save_repair_diagnosis(f.org_id,case_id,3,gen_random_uuid(),
   'Main board irreparable','irreparable','replacement','covered');
  perform public.finalize_repair_diagnosis(f.org_id,case_id,(d->>'diagnosisId')::uuid,4,gen_random_uuid());
  perform public.transition_repair_case(f.org_id,case_id,5,'T02',gen_random_uuid());
  p:=public.save_repair_action_plan(f.org_id,case_id,6,gen_random_uuid(),
   'replacement','Equivalent replacement','warranty',0,null,'GPS new','irreparable','return_to_customer');
  perform public.record_repair_plan_approval(f.org_id,case_id,(p->>'planId')::uuid,7,gen_random_uuid(),
   'replacement','approved');
  perform public.record_repair_plan_approval(f.org_id,case_id,(p->>'planId')::uuid,8,gen_random_uuid(),
   'customer','approved','phone','Customer','owner','call-allocation-'||i,
   null,pg_catalog.clock_timestamp());
  perform public.transition_repair_case(f.org_id,case_id,9,'T04',gen_random_uuid());
  if i=1 then case_a:=case_id; plan_a:=(p->>'planId')::uuid;
  else case_b:=case_id; plan_b:=(p->>'planId')::uuid; end if;
 end loop;
 s:=public.receive_repair_replacement_stock(f.org_id,'900000000000103','GPS new','Stock shelf',
  f.owner_id,'synthetic-stock-photo','allocation-stock-{suffix}',gen_random_uuid());
 insert into allocation_result values(jsonb_build_object('org',f.org_id,'caseA',case_a,
  'caseB',case_b,'planA',plan_a,'planB',plan_b,'device',s->>'deviceId',
  'owner',f.owner_id,'clerk',f.clerk_id));
end $$;
reset role;
select 'FIXTURE='||value::text from allocation_result;
commit;
"""
    return json.loads(next(line[8:] for line in query(sql).splitlines() if line.startswith('FIXTURE=')))


def allocation(f, side, key):
    return (f"public.allocate_repair_replacement_device('{f['org']}','{f['case' + side]}',"
            f"'{f['device']}','{f['plan' + side]}','race-{side}-{key}',10,'{key}')")


def assert_effects(f, winner_key):
    state = json.loads(query(f"""select jsonb_build_object(
     'caseA',a.version,'caseB',b.version,'status',s.status,
     'allocatedCase',s.allocated_case_id,'allocatedPlan',s.allocated_plan_id,
     'allocations',(select count(*) from public.repair_replacement_allocations x where x.org_id=a.org_id),
     'custody',(select count(*) from public.repair_device_custody_positions x
       where x.org_id=a.org_id and x.device_id=s.device_id),
     'events',(select count(*) from public.repair_case_events x
       where x.org_id=a.org_id and x.event_type='replacement_allocated'),
     'commands',(select count(*) from private.repair_command_receipts x
       where x.org_id=a.org_id and x.operation='replacement.allocate'),
     'winnerKey',(select idempotency_key from private.repair_command_receipts x
       where x.org_id=a.org_id and x.operation='replacement.allocate'))
     from public.repair_cases a cross join public.repair_cases b
     join public.repair_replacement_stock s on s.org_id=a.org_id
     where a.id='{f['caseA']}' and b.id='{f['caseB']}' and s.device_id='{f['device']}';"""))
    assert state['caseA'] == 11 and state['caseB'] == 10, state
    assert state['status'] == 'allocated' and state['allocatedCase'] == f['caseA'], state
    assert state['allocatedPlan'] == f['planA'] and state['winnerKey'] == winner_key, state
    assert all(state[name] == 1 for name in ('allocations', 'custody', 'events', 'commands')), state
    print('PASS persisted effects: one allocation/custody/event/receipt; losing case unchanged')


if __name__ == '__main__':
    for same_key, label in ((False, 'competing-cases'), (True, 'same-command-retry')):
        f = setup(label)
        key_a = str(uuid.uuid4())
        key_b = key_a if same_key else str(uuid.uuid4())
        contender = allocation(f, 'A' if same_key else 'B', key_b)
        contend(f['owner'], allocation(f, 'A', key_a),
                f['owner'] if same_key else f['clerk'], contender,
                None if same_key else 'REPLACEMENT_STOCK_UNAVAILABLE')
        print(f'PASS {label}: verified lock wait and expected concurrent response')
        assert_effects(f, key_a)
        print('FIXTURE=' + json.dumps(f, sort_keys=True))
