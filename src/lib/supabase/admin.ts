import "server-only";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";

// Uses the service-role key. Only import this from server actions/route
// handlers that first verify the caller's permission themselves (e.g. via
// the `has_permission` RPC) — this client bypasses RLS entirely and is
// needed only for the handful of operations that require Supabase Auth
// admin privileges, like inviting a user by email.
export function createAdminClient() {
  return createSupabaseClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}
