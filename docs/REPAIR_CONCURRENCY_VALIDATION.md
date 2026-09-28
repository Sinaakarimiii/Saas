# Repair concurrency validation — 2026-09-28

Stage 4: overlapping database transactions and exactly-once effects.

## Scope

`scripts/verify-repair-concurrency.py` creates two synthetic organizations/cases using the existing scrap SQL regression up to delivery, records synthetic scrap execution, and commits the fixtures into the isolated local database at `127.0.0.1:55422`. Three generated Auth identities have organization-specific fixture roles; no passwords/login sessions, real people, production records or payments are used. The approval identity differs from the scrap recorder.

The runner holds transaction A open after its RPC succeeds. It observes `PgSleep` for A, starts connection B, and observes B's `wait_event_type = Lock` before A commits. Thus these are overlapping database transactions with measured contention, not sequential commands or two stale browser views. Both RPCs execute as `authenticated` with explicit per-transaction identity claims; administrative access is used only for fixture setup, lock observation and persisted-effect assertions.

## Verified scenarios

| Scenario | Result |
| --- | --- |
| Different approval identities and request keys, same expected version 22 | First approval succeeds. Other authorized approver waits on the case lock, then gets `CASE_VERSION_CONFLICT`. Version becomes 23 once. |
| Different close identities and request keys, same expected version 23 | First T09 succeeds. Other authorized user waits, then gets `CASE_VERSION_CONFLICT`. Case closes at version 24 once. |
| Same approval identity/key/payload in two connections | Second connection waits on the idempotency lock and returns the exact first response. Approval/version/event are not repeated. |
| Same close identity/key/payload in two connections | Second connection waits and returns the exact first closure response. Closure/version/event are not repeated. |

After each approval/closure pair, assertions verify closed version 24, the correct independent approver, exactly one approval event, one T09 event and one persisted command receipt per operation. All four scenarios pass. No application/schema changes were required.

## Re-running

Requires Python 3, `psql`, the migrated isolated local database, and its password supplied through `PGPASSWORD` (or an existing local libpq password file). Run from the repository:

```sh
python3 scripts/verify-repair-concurrency.py
```

The script fixes the connection to local port 55422/database and user `postgres`; alternate host/port settings are rejected. It needs permission to inspect `pg_stat_activity`. Generated fixtures remain for inspection and their IDs are printed; the setup is committed because independent connections must see it. It is not a rollback-only test. Fixture setup reuses a checked boundary in `verify-repair-replacement-scrap.sql`; a boundary change fails explicitly and requires review.

## Limits and next checks

This verifies database RPC concurrency for the scrap approval and replacement closure paths. It does not verify simultaneous browser logins, session expiry, multi-server deployment, deadlock/load behavior across unrelated workflows, or concurrent receipt of the same IMEI into different cases. Earlier browser checks cover stale diagnosis save/finalization/T02 and sequential independent scrap identities. Concurrent IMEI intake is the next scenario; full operational acceptance remains pending.
