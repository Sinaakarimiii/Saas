"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { getOrgContext } from "@/lib/org-context";
import { PERMISSIONS } from "@/lib/permissions";

export type PermissionInput = {
  key: string;
  granted: boolean;
  scope: "own" | "all" | "team" | null;
};

type ActionResult = { error?: string; success?: boolean };

export async function saveRole(
  orgId: string,
  roleId: string | null,
  name: string,
  managementRank: number,
  permissions: PermissionInput[],
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { error: "ابتدا وارد شوید" };
  }

  const ctx = await getOrgContext(orgId);
  if (!ctx.can(PERMISSIONS.MANAGE_ROLES)) {
    return { error: "شما دسترسی مدیریت نقش‌ها را ندارید" };
  }

  const trimmedName = name.trim();
  if (!trimmedName) {
    return { error: "نام نقش نمی‌تواند خالی باشد" };
  }
  if (!Number.isInteger(managementRank) || managementRank < 0 || managementRank >= ctx.roleRank) {
    return { error: "سطح مدیریتی نقش باید کمتر از سطح نقش شما باشد" };
  }

  const payload = permissions
    .filter((p) => p.granted)
    .map((p) => ({ key: p.key, scope: p.scope }));

  const { error } = await supabase.rpc("save_role", {
    p_org_id: orgId,
    p_role_id: roleId,
    p_name: trimmedName,
    p_management_rank: managementRank,
    p_permissions: payload,
  });
  if (error) {
    return {
      error: error.code === "23505" ? "نقشی با این نام از قبل وجود دارد" : "ذخیره‌ی نقش انجام نشد",
    };
  }

  revalidatePath(`/${orgId}/roles`);
  return { success: true };
}

export async function setRoleInvitationApproval(
  orgId: string,
  roleId: string,
  approved: boolean,
): Promise<ActionResult> {
  const ctx = await getOrgContext(orgId);
  if (!ctx.isOwner) return { error: "فقط مالک می‌تواند نقش دعوت را تأیید کند" };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("roles")
    .update({ manager_invitable: approved })
    .eq("org_id", orgId)
    .eq("id", roleId)
    .eq("is_system", false)
    .is("deleted_at", null)
    .select("id")
    .maybeSingle();
  if (error || !data) return { error: "تغییر تأیید نقش انجام نشد" };

  revalidatePath(`/${orgId}/roles`);
  revalidatePath(`/${orgId}/members`);
  return { success: true };
}
