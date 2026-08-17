-- Private schema for internal helper functions (RLS helpers, etc.)
-- Not exposed via the Data API; only callable from inside the database
-- (SQL functions/policies) or via explicit public wrapper RPCs.
create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
