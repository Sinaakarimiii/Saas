import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { PermissionKey, PermissionScope } from "@/lib/permissions";

// Central place every org-scoped server component/action uses to: confirm
// the user is actually a member of this org (redirecting to /orgs if not,
// rather than silently rendering an empty page), and to know what they're
// allowed to do so the UI can hide actions they don't have.
export async function getOrgContext(orgId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: org, error: orgError } = await supabase
    .from("organizations")
    .select("id, name")
    .eq("id", orgId)
    .maybeSingle();

  if (orgError) {
    throw new Error("Could not load organization", { cause: orgError });
  }

  if (!org) {
    redirect("/orgs");
  }

  const { data: member, error: memberError } = await supabase
    .from("org_members")
    .select("id, role_id, invitation_status, roles(name, is_system, system_key, management_rank)")
    .eq("org_id", orgId)
    .eq("user_id", user.id)
    .is("deleted_at", null)
    .maybeSingle();

  if (memberError) {
    throw new Error("Could not load organization membership", { cause: memberError });
  }

  if (!member || member.invitation_status !== "active") {
    redirect("/orgs");
  }

  const { data: rolePermissions } = await supabase
    .from("role_permissions")
    .select("permission_key, scope")
    .eq("role_id", member.role_id);

  const scopes = new Map<string, PermissionScope | null>(
    (rolePermissions ?? []).map((rp) => [
      rp.permission_key,
      rp.scope as PermissionScope | null,
    ]),
  );

  return {
    user,
    org,
    memberId: member.id,
    roleName: member.roles?.name ?? "",
    isOwner: member.roles?.system_key === "owner",
    roleRank: member.roles?.management_rank ?? 0,
    can(key: PermissionKey) {
      return scopes.has(key);
    },
    scopeOf(key: PermissionKey) {
      return scopes.get(key) ?? null;
    },
  };
}

export type OrgContext = Awaited<ReturnType<typeof getOrgContext>>;
