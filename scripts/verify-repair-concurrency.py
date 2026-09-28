#!/usr/bin/env python3
"""Committed synthetic fixtures + overlapping RPC transactions on local port 55422.

Run with PGPASSWORD for the local postgres database/user. Fixtures are retained
for inspection in the isolated local DB; no production connection is accepted.
The existing scrap regression prepares each case; this runner checks lock waits,
competing keys/actors, identical-key retries and exactly-once persisted effects.
"""
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
ENV = dict(os.environ)
if ENV.get('PGHOST', '127.0.0.1') != '127.0.0.1' or ENV.get('PGPORT', '55422') != '55422':
    raise SystemExit('Only the isolated local database at 127.0.0.1:55422 is supported')
ENV.update(PGHOST='127.0.0.1', PGPORT='55422')
ENV.setdefault('PGUSER', 'postgres')
ENV.setdefault('PGDATABASE', 'postgres')
# Prevent libpq service/hostaddr settings from redirecting the local fixture run.
for name in ('PGHOSTADDR', 'PGSERVICE', 'PGSERVICEFILE'):
    ENV.pop(name, None)
CMD = ['psql', '-h', '127.0.0.1', '-p', '55422', '-U', 'postgres', '-d', 'postgres',
       '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1']


def query(sql):
    result = subprocess.run(CMD, input=sql, text=True, capture_output=True, env=ENV, timeout=30)
    if result.returncode:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def setup(label):
    source = (ROOT / 'scripts/verify-repair-replacement-scrap.sql').read_text()
    marker = "\n perform pg_temp.original_disposition(f.org_id,case_id,'scrap_proposed');"
    boundary = marker + "\n perform set_config('request.jwt.claim.sub',f.clerk_id::text,true);"
    assert source.count(boundary) == 1, 'Scrap fixture boundary changed; review setup'
    prefix = source[:source.index(boundary) + len(marker)]
    suffix = uuid.uuid4().hex
    other_approver = str(uuid.uuid4())
    prefix = prefix.replace('replacement-execution-owner@example.test', f'concurrency-owner-{suffix}@example.test')
    prefix = prefix.replace('replacement-execution-clerk@example.test', f'concurrency-clerk-{suffix}@example.test')
    prefix = prefix.replace('Replacement execution test', f'Repair concurrency {label} {suffix}')
    prefix = prefix.replace('set local role authenticated;', '''create temp table concurrency_result(value jsonb);
grant insert,select on concurrency_result to authenticated;
set local role authenticated;''', 1)
    sql = prefix + '''
 perform pg_temp.clerk_scrap_permissions(f.clerk_role_id);
 perform set_config('request.jwt.claim.sub',f.owner_id::text,true);
 a:=public.record_replacement_scrap(f.org_id,case_id,21,gen_random_uuid(),
  'synthetic-concurrency-scrap','synthetic execution evidence','synthetic destroyed device');
 insert into concurrency_result values(jsonb_build_object('org',f.org_id,'case',case_id,
  'recorder',f.owner_id,'approver',f.clerk_id,'scrap',a->>'scrapId'));
end $$;
reset role;
insert into public.role_permissions(role_id,permission_key)
 select clerk_role_id,'case.close' from replacement_fixture;
''' + f"""
insert into auth.users(id,aud,role,email) values('{other_approver}','authenticated','authenticated',
 'concurrency-other-{suffix}@example.test');
insert into public.org_members(org_id,user_id,role_id)
 select org_id,'{other_approver}'::uuid,clerk_role_id from replacement_fixture;
update concurrency_result set value=value||jsonb_build_object('otherApprover','{other_approver}');
select 'FIXTURE='||value::text from concurrency_result;
commit;
"""
    out = query(sql)
    return json.loads(next(line[8:] for line in out.splitlines() if line.startswith('FIXTURE=')))


def rpc(fixture, operation, key):
    org, case = fixture['org'], fixture['case']
    if operation == 'approve':
        return f"public.approve_replacement_scrap('{org}','{case}',22,'{key}','{fixture['scrap']}')"
    return f"public.close_replacement_case('{org}','{case}',23,'{key}')"


def transaction(actor, expression, hold):
    return f"""begin;
set local statement_timeout='15s';
set local role authenticated;
do $$begin perform set_config('request.jwt.claim.sub','{actor}',true); end$$;
select 'RESULT='||{expression}::text;
{'select pg_sleep(5);' if hold else ''}
commit;"""


def wait_for(app, event_type=None, event=None):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        filters = [f"application_name='{app}'"]
        if event_type:
            filters.append(f"wait_event_type='{event_type}'")
        if event:
            filters.append(f"wait_event='{event}'")
        if query('select count(*) from pg_stat_activity where ' + ' and '.join(filters)) == '1':
            return
        time.sleep(0.1)
    raise AssertionError(f'Expected wait not observed: {event_type or event}')


def race(fixture, operation, same_key):
    first_key = str(uuid.uuid4())
    second_key = first_key if same_key else str(uuid.uuid4())
    actor_a = fixture['approver'] if operation == 'approve' else fixture['recorder']
    # Distinct-key races use different permitted identities. Same-key retries
    # use one identity because idempotency keys are scoped to the caller.
    actor_b = actor_a if same_key else (fixture['otherApprover'] if operation == 'approve' else fixture['approver'])
    tag = uuid.uuid4().hex
    app_a, app_b = 'repair-race-a-' + tag, 'repair-race-b-' + tag
    processes = []
    try:
        a = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, env=dict(ENV, PGAPPNAME=app_a))
        processes.append(a)
        a.stdin.write(transaction(actor_a, rpc(fixture, operation, first_key), True))
        a.stdin.close()
        a.stdin = None
        # PgSleep proves RPC A has completed while its transaction retains locks.
        wait_for(app_a, event='PgSleep')
        b = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, env=dict(ENV, PGAPPNAME=app_b))
        processes.append(b)
        b.stdin.write(transaction(actor_b, rpc(fixture, operation, second_key), False))
        b.stdin.close()
        b.stdin = None
        # Prove overlap/lock contention rather than relying on launch timing.
        wait_for(app_b, event_type='Lock')
        out_a, err_a = a.communicate(timeout=20)
        out_b, err_b = b.communicate(timeout=20)
        assert a.returncode == 0, err_a
        response_a = json.loads(next(line[7:] for line in out_a.splitlines() if line.startswith('RESULT=')))
        if same_key:
            assert b.returncode == 0, err_b
            response_b = json.loads(next(line[7:] for line in out_b.splitlines() if line.startswith('RESULT=')))
            assert response_a == response_b, 'Concurrent retry response differs'
        else:
            assert b.returncode != 0 and 'CASE_VERSION_CONFLICT' in err_b, err_b
        print(f"PASS {operation}: observed lock wait; " +
              ('same-key identical response' if same_key else 'competing key rejected'))
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


def assert_effects(fixture):
    case, org = fixture['case'], fixture['org']
    state = json.loads(query(f"""select jsonb_build_object(
      'stage',c.stage,'version',c.version,
      'approver',s.approved_by,'recorder',s.recorded_by,
      'approvals',(select count(*) from public.repair_case_events where case_id=c.id
        and details->>'operation'='replacement.scrap.approve'),
      'closures',(select count(*) from public.repair_case_events where case_id=c.id
        and details->>'transitionCode'='T09'),
      'approvalCommands',(select count(*) from private.repair_command_receipts
        where org_id='{org}' and operation='replacement.scrap.approve'),
      'closeCommands',(select count(*) from private.repair_command_receipts
        where org_id='{org}' and operation='transition' and response->>'transitionCode'='T09'))
      from public.repair_cases c join public.repair_replacement_scraps s on s.case_id=c.id
      where c.id='{case}';"""))
    assert state['stage'] == 'closed' and state['version'] == 24, state
    assert state['approver'] == fixture['approver'] != state['recorder'], state
    assert all(state[key] == 1 for key in ('approvals', 'closures', 'approvalCommands', 'closeCommands')), state
    print('PASS persisted effects: one approval, one closure, one receipt per command; closed version 24')


if __name__ == '__main__':
    for same_key, label in ((False, 'competing-keys'), (True, 'identical-retry')):
        fixture = setup(label)
        race(fixture, 'approve', same_key)
        race(fixture, 'close', same_key)
        assert_effects(fixture)
        print('FIXTURE=' + json.dumps(fixture, sort_keys=True))
