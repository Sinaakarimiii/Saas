-- service_role (used by createAdminClient() for privileged server-only
-- operations, e.g. the invite flow reading profiles / inserting
-- org_members before the invited user has a session of their own) has
-- BYPASSRLS, but that only skips row-level policies -- it does NOT grant
-- table-level privileges. This Supabase version's default is to expose
-- NOTHING to any API role (anon, authenticated, service_role) without an
-- explicit GRANT, so without this migration every admin-client table
-- call 403s with "permission denied", regardless of RLS.
--
-- Every table gets full access EXCEPT audit_log, which stays
-- insert/select-only for every role, including this one -- that
-- restriction (nobody can edit or delete a log entry, not even an admin)
-- is the entire point of 0013_audit_log.sql and must hold regardless of
-- which role is asking.
do $$
declare
  t text;
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public' and tablename <> 'audit_log'
  loop
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;

grant select, insert on public.audit_log to service_role;
revoke update, delete on public.audit_log from service_role;

grant usage on schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Cover tables/functions created by future migrations automatically too.
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;
