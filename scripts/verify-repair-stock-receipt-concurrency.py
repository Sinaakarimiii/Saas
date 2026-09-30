#!/usr/bin/env python3
"""Check competing replacement-stock receipts on the isolated local database."""
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


def setup(label):
    suffix = uuid.uuid4().hex
    org, owner, clerk, role = (str(uuid.uuid4()) for _ in range(4))
    imei = '901' + str(int(suffix[:8], 16)).zfill(12)
    shared.query(f"""begin;
insert into auth.users(id,aud,role,email) values
 ('{owner}','authenticated','authenticated','stock-owner-{suffix}@example.test'),
 ('{clerk}','authenticated','authenticated','stock-clerk-{suffix}@example.test');
insert into public.organizations(id,name,created_by)
 values('{org}','Stock receipt concurrency {label} {suffix}','{owner}');
insert into public.roles(id,org_id,name,is_system)
 values('{role}','{org}','Stock receiver',false);
insert into public.org_members(org_id,user_id,role_id)
 values('{org}','{owner}','{role}'),('{org}','{clerk}','{role}');
insert into public.role_permissions(role_id,permission_key)
 values('{role}','replacement.stock.receive');
commit;""")
    return {'org': org, 'owner': owner, 'clerk': clerk, 'imei': imei, 'suffix': suffix}


def rpc(fixture, actor, reference, key):
    return ("public.receive_repair_replacement_stock("
            f"'{fixture['org']}','{fixture['imei']}','Test model','Test shelf',"
            f"'{actor}','synthetic evidence','{reference}','{key}')")


def assert_effects(fixture, expected_actor, expected_key):
    state = json.loads(shared.query(f"""select jsonb_build_object(
      'devices',(select count(*) from public.repair_devices where org_id='{fixture['org']}' and imei='{fixture['imei']}'),
      'stock',(select count(*) from public.repair_replacement_stock s join public.repair_devices d
        on d.org_id=s.org_id and d.id=s.device_id where s.org_id='{fixture['org']}' and d.imei='{fixture['imei']}'),
      'commands',(select count(*) from private.repair_command_receipts
        where org_id='{fixture['org']}' and operation='replacement.stock.receive'),
      'actor',(select actor_id from private.repair_command_receipts
        where org_id='{fixture['org']}' and operation='replacement.stock.receive'),
      'key',(select idempotency_key from private.repair_command_receipts
        where org_id='{fixture['org']}' and operation='replacement.stock.receive'));"""))
    assert state['devices'] == state['stock'] == state['commands'] == 1, state
    assert state['actor'] == expected_actor and state['key'] == expected_key, state


def race(same_key):
    fixture = setup('same-key' if same_key else 'different-actors')
    first_key = str(uuid.uuid4())
    second_key = first_key if same_key else str(uuid.uuid4())
    second_actor = fixture['owner'] if same_key else fixture['clerk']
    first_ref = 'stock-first-' + fixture['suffix']
    second_ref = first_ref if same_key else 'stock-second-' + fixture['suffix']
    response = shared.contend(
        fixture['owner'], rpc(fixture, fixture['owner'], first_ref, first_key),
        second_actor, rpc(fixture, second_actor, second_ref, second_key),
        None if same_key else 'REPLACEMENT_IMEI_EXISTS')
    assert response['imei'] == fixture['imei'], response
    assert_effects(fixture, fixture['owner'], first_key)
    print('PASS same-key retry returns identical response with one receipt' if same_key
          else 'PASS second receiver waits and gets REPLACEMENT_IMEI_EXISTS; one device and receipt')


if __name__ == '__main__':
    race(False)
    race(True)
