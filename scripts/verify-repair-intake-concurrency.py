#!/usr/bin/env python3
"""Overlapping IMEI intake RPCs on the isolated local DB; fixtures are retained."""
import json
import subprocess
import sys
import uuid
# Hyphenated regression filename is loaded without executing its main runner.
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('repair_concurrency', ROOT / 'scripts/verify-repair-concurrency.py')
shared = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(shared)
query, contend = shared.query, shared.contend
IMEI = '359881234567896'


def setup(label, existing_device=False):
    source = (ROOT / 'scripts/verify-repair-intake.sql').read_text()
    boundary = 'set local role authenticated;\ndo $$'
    assert source.count(boundary) == 1, 'Intake fixture boundary changed; review setup'
    prefix = source[:source.index(boundary)]
    suffix = uuid.uuid4().hex
    for name in ('owner-a', 'receiver-a', 'owner-b'):
        prefix = prefix.replace(f'repair-{name}@example.test', f'intake-race-{name}-{suffix}@example.test')
    prefix = prefix.replace("'Repair A'", f"'Intake concurrency {label} {suffix}'")
    sql = prefix + f"""
create temp table intake_concurrency_result(value jsonb);
grant insert,select on intake_concurrency_result to authenticated;
set local role authenticated;
do $$
declare f record; a jsonb; b jsonb; path_a text; path_b text;
begin
 select * into f from repair_fixture;
 perform set_config('request.jwt.claim.sub',f.owner_a::text,true);
 a:=public.create_repair_case(f.org_a,'Synthetic GPS A','{IMEI}','Synthetic customer',
  'Synthetic concurrency intake','normal','walk_in',gen_random_uuid());
 b:=public.create_repair_case(f.org_a,'Synthetic GPS B','{IMEI}','Synthetic customer',
  'Synthetic concurrency intake','normal','walk_in',gen_random_uuid());
 path_a:=f.org_a||'/'||(a->>'caseId')||'/'||gen_random_uuid()||'.png';
 path_b:=f.org_a||'/'||(b->>'caseId')||'/'||gen_random_uuid()||'.png';
 perform pg_temp.add_repair_evidence(path_a,f.owner_a);
 perform pg_temp.add_repair_evidence(path_b,f.receiver_a);
 insert into intake_concurrency_result values(jsonb_build_object('org',f.org_a,
  'caseA',a->>'caseId','caseB',b->>'caseId','actorA',f.owner_a,'actorB',f.receiver_a,
  'pathA',path_a,'pathB',path_b));
end $$;
reset role;
"""
    if existing_device:
        sql += f"""insert into public.repair_devices(org_id,imei,first_verified_by,first_evidence)
select (value->>'org')::uuid,'{IMEI}',(value->>'actorA')::uuid,value->>'pathA'
from intake_concurrency_result;"""
    sql += "select 'FIXTURE='||value::text from intake_concurrency_result; commit;"
    return json.loads(next(line[8:] for line in query(sql).splitlines() if line.startswith('FIXTURE=')))


def receipt(f, side, key, override=False):
    extra = ",'synthetic override reason','SYNTHETIC-OVERRIDE-1'" if override else ''
    return (f"public.receive_repair_device('{f['org']}','{f['case' + side]}',1,'{key}',"
            f"'walk_in','Synthetic branch {side}','Synthetic receiver {side}','charger',"
            f"'{IMEI}','{f['path' + side]}'{extra})")


def assert_effects(f, expected_key):
    state = json.loads(query(f"""select jsonb_build_object(
      'versionA',a.version,'versionB',b.version,
      'receivedA',a.received_at is not null,'receivedB',b.received_at is not null,
      'verifiedA',a.verified_device_id is not null,'verifiedB',b.verified_device_id is not null,
      'exceptions',(select count(*) from public.repair_cases where org_id=a.org_id
        and duplicate_exception_reference is not null),
      'devices',(select count(*) from public.repair_devices where org_id=a.org_id and imei='{IMEI}'),
      'openVerified',(select count(*) from public.repair_cases where org_id=a.org_id
        and verified_device_id=a.verified_device_id and closed_at is null),
      'receiptEvents',(select count(*) from public.repair_case_events where org_id=a.org_id and event_type='received'),
      'imeiEvents',(select count(*) from public.repair_case_events where org_id=a.org_id and event_type='imei_verified'),
      'commandReceipts',(select count(*) from private.repair_command_receipts where org_id=a.org_id and operation='receive'),
      'winnerKey',(select idempotency_key from private.repair_command_receipts where org_id=a.org_id and operation='receive'))
      from public.repair_cases a cross join public.repair_cases b
      where a.id='{f['caseA']}' and b.id='{f['caseB']}';"""))
    assert state['versionA'] == 2 and state['receivedA'] and state['verifiedA'], state
    assert state['versionB'] == 1 and not state['receivedB'] and not state['verifiedB'], state
    assert state['exceptions'] == 0 and state['winnerKey'] == expected_key, state
    assert all(state[k] == 1 for k in ('devices','openVerified','receiptEvents','imeiEvents','commandReceipts')), state
    print('PASS persisted effects: one verified open case/device/receipt; other case unchanged; no exception')


def unauthorized_override(f):
    # This receiver has intake permission but no independent duplicate override.
    key = str(uuid.uuid4())
    result = subprocess.run(shared.CMD,
      input=shared.transaction(f['actorB'],receipt(f,'B',key,override=True),False),
      text=True,capture_output=True,env=shared.ENV,timeout=20)
    assert result.returncode != 0 and 'ACTIVE_REPAIR_CASE_EXISTS' in result.stderr, result.stderr
    print('PASS receiver cannot bypass duplicate rejection by supplying reason/reference')


if __name__ == '__main__':
    for existing, label in ((False,'new-device'),(True,'known-device')):
        fixture=setup(label,existing)
        key_a,key_b=str(uuid.uuid4()),str(uuid.uuid4())
        contend(fixture['actorA'],receipt(fixture,'A',key_a),
                fixture['actorB'],receipt(fixture,'B',key_b),'ACTIVE_REPAIR_CASE_EXISTS')
        print(f'PASS {label}: observed concurrent lock wait; cross-location duplicate intake rejected')
        unauthorized_override(fixture)
        assert_effects(fixture,key_a)
        print('FIXTURE='+json.dumps(fixture,sort_keys=True))
    fixture=setup('identical-retry')
    key=str(uuid.uuid4())
    contend(fixture['actorA'],receipt(fixture,'A',key),fixture['actorA'],receipt(fixture,'A',key))
    print('PASS intake retry: observed lock wait; exact same response without duplicate receipt')
    assert_effects(fixture,key)
    print('FIXTURE='+json.dumps(fixture,sort_keys=True))

