"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
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
  permissions: PermissionInput[],
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { error: "ابتدا وارد شوید" };
  }

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.MANAGE_ROLES,
  });
  if (!allowed) {
    return { error: "شما دسترسی مدیریت نقش‌ها را ندارید" };
  }

  const trimmedName = name.trim();
  if (!trimmedName) {
    return { error: "نام نقش نمی‌تواند خالی باشد" };
  }

  let finalRoleId = roleId;

  if (!finalRoleId) {
    const { data: newRole, error: insertError } = await supabase
      .from("roles")
      .insert({ org_id: orgId, name: trimmedName })
      .select("id")
      .single();
    if (insertError || !newRole) {
      return {
        error:
          insertError?.code === "23505"
            ? "نقشی با این نام از قبل وجود دارد"
            : "ساخت نقش انجام نشد",
      };
    }
    finalRoleId = newRole.id;
  } else {
    const { error: updateError } = await supabase
      .from("roles")
      .update({ name: trimmedName })
      .eq("id", finalRoleId)
      .eq("org_id", orgId);
    if (updateError) {
      return {
        error: "ویرایش نقش انجام نشد (نقش‌های سیستمی قابل ویرایش نیستند)",
      };
    }
  }

  const payload = permissions
    .filter((p) => p.granted)
    .map((p) => ({ key: p.key, scope: p.scope }));

  const { error: permError } = await supabase.rpc("set_role_permissions", {
    p_role_id: finalRoleId,
    p_permissions: payload,
  });
  if (permError) {
    return { error: "ذخیره‌ی دسترسی‌ها انجام نشد" };
  }

  revalidatePath(`/${orgId}/roles`);
  return { success: true };
}
