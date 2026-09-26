"""Two-session race check against the isolated local repair test database."""

import os
import subprocess
import uuid

PORT = "55422"
if os.environ.get("REPAIR_TEST_DB_PORT", PORT) != PORT:
    raise SystemExit("This check only runs against isolated local port 55422")

env = {**os.environ, "PGPASSWORD": "postgres"}
base = ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1",
        "-p", PORT, "-U", "postgres", "-d", "postgres"]


def sql(statement):
    result = subprocess.run(base, input=statement, text=True, capture_output=True,
                            env=env, timeout=20, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


actor, org, role, case_a, case_b = [str(uuid.uuid4()) for _ in range(5)]
imei = "357862109876543"
evidence_a = f"{org}/{case_a}/{uuid.uuid4()}.png"
evidence_b = f"{org}/{case_b}/{uuid.uuid4()}.png"

sql(f"""
insert into auth.users (id, aud, role, email)
values ('{actor}', 'authenticated', 'authenticated', 'repair-race-{actor}@example.test');
insert into public.organizations (id, name, created_by)
values ('{org}', 'Repair race test', '{actor}');
insert into public.roles (id, org_id, name) values ('{role}', '{org}', 'Race receiver');
insert into public.org_members (org_id, user_id, role_id) values ('{org}', '{actor}', '{role}');
insert into public.role_permissions (role_id, permission_key)
values ('{role}', 'repair.case.receive'), ('{role}', 'repair.case.view');
insert into public.repair_cases
  (id, org_id, created_by, customer_name, device_model, issue, priority, source)
values
  ('{case_a}', '{org}', '{actor}', 'A', 'Model', 'Fault', 'normal', 'walk_in'),
  ('{case_b}', '{org}', '{actor}', 'B', 'Model', 'Fault', 'normal', 'walk_in');
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('repair-imei-evidence', '{evidence_a}', '{actor}', '{{"mimetype":"image/png","size":128}}'::jsonb),
       ('repair-imei-evidence', '{evidence_b}', '{actor}', '{{"mimetype":"image/png","size":128}}'::jsonb);
""")


def receipt(case_id, hold=False):
    key = uuid.uuid4()
    return f"""
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '{actor}', true);
select public.receive_repair_device('{org}', '{case_id}', 1, '{key}',
  'walk_in', 'Branch', 'Receiver', 'box', '{imei}', '{evidence_a if case_id == case_a else evidence_b}');
{'select pg_sleep(2);' if hold else ''}
commit;
"""


try:
    first = subprocess.Popen(base, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, env=env)
    assert first.stdin and first.stdout
    first.stdin.write(receipt(case_a, hold=True))
    first.stdin.close()
    observed = ""
    while "\"caseId\"" not in observed:
        line = first.stdout.readline()
        if not line:
            raise RuntimeError("First receipt did not reach the device lock")
        observed += line
    second = subprocess.run(base, input=receipt(case_b), text=True, capture_output=True,
                            env=env, timeout=15, check=False)
    first.wait(timeout=15)
    first_error = first.stderr.read() if first.stderr else ""
    if first.returncode or second.returncode == 0 or "ACTIVE_REPAIR_CASE_EXISTS" not in second.stderr:
        raise RuntimeError(f"Race failed: first={first.returncode} {first_error}; "
                           f"second={second.returncode} {second.stderr}")
    counts = sql(f"select count(*), count(*) filter (where verified_device_id is not null) "
                 f"from public.repair_cases where org_id = '{org}';")
    if counts != "2|1":
        raise RuntimeError(f"Unexpected case counts: {counts}")
    print("Two-session IMEI race check passed: one receipt committed, second rejected")
finally:
    sql(f"""
    begin;
    -- These two rows are metadata-only test fixtures; no object bytes exist.
    set local storage.allow_delete_query = 'true';
    delete from storage.objects where bucket_id = 'repair-imei-evidence' and name in ('{evidence_a}', '{evidence_b}');
    delete from private.repair_command_receipts where org_id = '{org}';
    delete from public.repair_case_events where org_id = '{org}';
    delete from public.tracking_codes where org_id = '{org}';
    delete from public.repair_cases where org_id = '{org}';
    delete from public.repair_devices where org_id = '{org}';
    delete from public.org_members where org_id = '{org}';
    delete from public.role_permissions where role_id = '{role}';
    delete from public.roles where org_id = '{org}';
    delete from public.audit_log where org_id = '{org}';
    delete from public.organizations where id = '{org}';
    delete from auth.users where id = '{actor}';
    commit;
    """)
