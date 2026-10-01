#!/usr/bin/env python3
"""Bounded 12-client burst against the isolated local replacement-stock RPC.

An advisory-lock gate releases all authenticated database clients together.
This is a correctness check, not a throughput benchmark or a multi-server test.
"""
import importlib.util
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    'stock_receipt', ROOT / 'scripts/verify-repair-stock-receipt-concurrency.py')
stock = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(stock)
shared = stock.shared
CLIENTS = 12


def wait_for_gate(tag):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        waiting = int(shared.query(f"""select count(*) from pg_stat_activity
            where application_name like 'stock-burst-{tag}-%'
              and wait_event_type = 'Lock' and wait_event = 'advisory';"""))
        if waiting == CLIENTS:
            return
        time.sleep(0.1)
    raise AssertionError(f'Only {waiting}/{CLIENTS} clients reached advisory gate')


def run(same_key):
    fixture = stock.setup('burst-retry' if same_key else 'burst-competing')
    tag = uuid.uuid4().hex[:12]
    gate_key = int(uuid.uuid4().int & ((1 << 62) - 1))
    first_key = str(uuid.uuid4())
    processes = []
    gate = None
    try:
        gate = subprocess.Popen(shared.CMD, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, env=dict(shared.ENV, PGAPPNAME=f'stock-gate-{tag}'))
        gate.stdin.write(f'begin; select pg_advisory_xact_lock({gate_key});\n')
        gate.stdin.flush()
        # The lock must be acquired before clients are launched.
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if shared.query(f"""select count(*) from pg_locks l
                join pg_stat_activity a on a.pid=l.pid
                where a.application_name='stock-gate-{tag}'
                  and l.locktype='advisory' and l.granted
                  and l.objid={gate_key & 0xffffffff};""") == '1':
                break
            time.sleep(0.05)
        else:
            raise AssertionError('Advisory gate was not acquired')

        for index in range(CLIENTS):
            actor = fixture['owner'] if same_key or index % 2 == 0 else fixture['clerk']
            key = first_key if same_key else str(uuid.uuid4())
            reference = 'burst-' + tag if same_key else f'burst-{tag}-{index}'
            sql = ("begin; set local statement_timeout='20s'; set local role authenticated; "
                   f"select set_config('request.jwt.claim.sub','{actor}',true); "
                   f"select pg_advisory_xact_lock_shared({gate_key}); "
                   f"select 'RESULT='||{stock.rpc(fixture, actor, reference, key)}::text; commit;\n")
            process = subprocess.Popen(shared.CMD, stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       text=True, env=dict(shared.ENV, PGAPPNAME=f'stock-burst-{tag}-{index}'))
            processes.append(process)
            process.stdin.write(sql)
            process.stdin.close()
            process.stdin = None

        wait_for_gate(tag)
        started = time.monotonic()
        gate.stdin.write('commit;\n')
        gate.stdin.close()
        gate.stdin = None
        gate.communicate(timeout=10)
        assert gate.returncode == 0, 'Advisory gate release failed'
        results = [process.communicate(timeout=30) for process in processes]
        elapsed = time.monotonic() - started
        successes = []
        errors = []
        for process, (stdout, stderr) in zip(processes, results):
            if process.returncode == 0:
                successes.append(json.loads(next(line[7:] for line in stdout.splitlines()
                                               if line.startswith('RESULT='))))
            else:
                errors.append(stderr)
        if same_key:
            assert len(successes) == CLIENTS and not errors, (len(successes), errors)
            assert all(response == successes[0] for response in successes), 'Retry responses differ'
        else:
            assert len(successes) == 1 and len(errors) == CLIENTS - 1, (len(successes), errors)
            assert all('REPLACEMENT_IMEI_EXISTS' in error for error in errors), errors
        assert successes[0]['imei'] == fixture['imei'], successes[0]
        state = json.loads(shared.query(f"""select jsonb_build_object(
          'devices',(select count(*) from public.repair_devices where org_id='{fixture['org']}' and imei='{fixture['imei']}'),
          'stock',(select count(*) from public.repair_replacement_stock where org_id='{fixture['org']}'),
          'commands',(select count(*) from private.repair_command_receipts
            where org_id='{fixture['org']}' and operation='replacement.stock.receive'));"""))
        assert state == {'devices': 1, 'stock': 1, 'commands': 1}, state
        print(f"PASS {'same-key retry' if same_key else 'competing keys'}: "
              f'{CLIENTS} authenticated clients released together; '
              f'{len(successes)} success, {len(errors)} domain errors; '
              f'one device/stock/receipt; {elapsed:.3f}s local completion')
        print('FIXTURE=' + json.dumps(fixture, sort_keys=True))
    finally:
        for process in [*processes, gate]:
            if process and process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


if __name__ == '__main__':
    run(False)
    run(True)
