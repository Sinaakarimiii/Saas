# Repair concurrency validation — 2026-09-28–30

Stage 4: overlapping database transactions and exactly-once effects.

## Scope

`scripts/verify-repair-concurrency.py` creates two synthetic organizations/cases using the existing scrap SQL regression up to delivery, records synthetic scrap execution, and commits the fixtures into the isolated local database at `127.0.0.1:55422`. Three generated Auth identities have organization-specific fixture roles; no passwords/login sessions, real people, production records or payments are used. The approval identity differs from the scrap recorder.

The runner holds transaction A open after its RPC succeeds. It observes A `idle in transaction`, starts connection B, verifies B's `wait_event_type = Lock` and that A is its blocking PID, then explicitly commits A. A fixed sleep is not used. Thus these are overlapping database transactions with measured contention, not sequential commands or two stale browser views. Both RPCs execute as `authenticated` with explicit per-transaction identity claims; administrative access is used only for fixture setup, lock observation and persisted-effect assertions.

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

This verifies database RPC concurrency for the scrap approval and replacement closure paths. It does not verify simultaneous browser logins, session expiry, multi-server deployment, or deadlock/load behavior across unrelated workflows. Earlier browser checks cover stale diagnosis save/finalization/T02 and sequential independent scrap identities. Concurrent IMEI intake and competing replacement-stock allocation are verified below; full operational acceptance remains pending.


## Concurrent IMEI intake — 2026-09-29

`scripts/verify-repair-intake-concurrency.py` reuses the same measured-lock orchestration and the existing intake regression fixture setup. Two distinct raw requests share one organization and IMEI. Permitted receivers use different identities, evidence paths, request keys and physical-location labels (`Synthetic branch A/B`). This tests the organization-wide invariant across locations; it does not establish a separate branch data model or simultaneous browser login coverage.

| Scenario | Result |
| --- | --- |
| IMEI absent from device registry | First intake holds its uncommitted device insertion. Second intake demonstrably waits on its transaction. After explicit commit, the second RPC rejects with `ACTIVE_REPAIR_CASE_EXISTS`. |
| IMEI already in device registry, no open case | First intake holds the existing device lock. Second intake waits on the first transaction, then rejects with the same open-case error. |
| Same intake identity/key/payload in two connections | Second RPC waits and returns the exact first response; no second receipt or version increment. |
| Reason/reference without override permission | Losing receiver supplies synthetic exception reason/reference; RPC still rejects with `ACTIVE_REPAIR_CASE_EXISTS`. No exception is recorded. |

After each race, assertions verify: one device row, one open verified case, one receive event, one IMEI verification event and one receive command receipt with the winning key. The accepted case is intake version 2 with physical receipt and verified identity; the other raw case stays version 1 without either. Exception count is zero.

Run with the same local database/password setup:

```sh
python3 scripts/verify-repair-intake-concurrency.py
```

Fixtures and synthetic Storage metadata are committed for independent connections and retained for inspection; actual image bytes are not uploaded by these database tests. The earlier re-entry browser scenario separately covers real synthetic PNG upload. The helper's timed-hold prototype produced intake statement timeouts; the final runner uses an explicit transaction barrier and verifies the actual blocking PID. All three intake races and all four approval/closure regressions pass with this method. No application/schema change or confirmed product fix is claimed for the prototype timeout.

Concurrent rollback/recovery, authorized duplicate exceptions under contention, independent browser sessions and production acceptance remain outside this run. Replacement-stock allocation is verified below.

## Competing replacement allocation — 2026-09-30

`scripts/verify-repair-allocation-concurrency.py` prepares two separate synthetic cases in the replacement stage with approved plans for the same model, and two serial-numbered devices in available stock. The cases, plans, and original IMEIs are distinct. Two authorized identities issue allocations on separate database connections. The runner verifies an actual lock wait and blocking PID before committing or rolling back the first allocation.

| Scenario | Result |
| --- | --- |
| Two cases, two actors and two keys allocate the same serial | First allocation succeeds; second waits for its stock-row lock, then receives `REPLACEMENT_STOCK_UNAVAILABLE`. The losing case remains at version 10. |
| Exact same allocation command retried concurrently | Retry waits on the idempotency lock and returns the exact first response. |
| One case, two actors and two distinct stock devices | First allocation succeeds; second waits on the case-row lock, then receives `CASE_VERSION_CONFLICT`. The other stock device remains available. |
| First transaction rolls back while another case waits for the same serial | Waiting request succeeds after rollback. The first case stays at version 10 and leaves no allocation, custody baseline, event or idempotency receipt. Retrying its original key after the second case wins returns `REPLACEMENT_STOCK_UNAVAILABLE`. |

Persisted assertions show exactly one allocation row, replacement custody baseline, `replacement_allocated` event and command receipt; the winning case advances to version 11, and its stock row names only that case and plan. All four scenarios passed against the isolated local database. No schema or application-code change was needed.

```sh
python3 scripts/verify-repair-allocation-concurrency.py
```

The script requires the same local `PGPASSWORD` and retains synthetic fixtures for inspection. This proves the database RPC invariant under measured overlap, including rollback of the first allocation. Stock receipt races are checked below; browser sessions and multi-server load remain outside this run.

## Competing replacement-stock receipts — 2026-10-01

`scripts/verify-repair-stock-receipt-concurrency.py` uses two authenticated identities and separate PostgreSQL connections in the isolated local database. It confirms the second connection actually waits on the first transaction. Before the fix, two distinct receipt commands for the same organization/IMEI surfaced the raw `repair_devices_org_id_imei_key` unique-constraint error. Migration `20260930215823_repair_replacement_stock_concurrent_imei.sql` makes the insert conflict-safe and returns the existing `REPLACEMENT_IMEI_EXISTS` domain error after the wait. The UI already translates that error into a Persian message.

The two-actor, two-key race now returns `REPLACEMENT_IMEI_EXISTS` for the loser. An identical concurrent retry returns the first response. Each scenario persists exactly one device, one stock row, and one command receipt, with the correct actor and key. Both pass after applying the migration locally; the four allocation races above also pass. The local Supabase security advisor reports no error-level issues. Run with `PGPASSWORD` configured for the isolated local database:

```sh
python3 scripts/verify-repair-stock-receipt-concurrency.py
```

The broad legacy `verify-repair-diagnosis.sql` script passed its stock receipt/allocation block, then stopped at an unrelated final direct-close guard: it selects any delivery case from a database now containing many retained fixtures and encountered `REPLACEMENT_OUTGOING_RELEASE_REQUIRED`. This run does not establish that the entire broad script passes. A fresh isolated database or fixture-scoped selection is needed for a full rerun. Simultaneous independent browser sessions and production load remain pending.
