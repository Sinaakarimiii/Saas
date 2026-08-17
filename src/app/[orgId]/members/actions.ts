"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { PERMISSIONS } from "@/lib/permissions";

type ActionResult = { error?: string; success?: boolean };

export async function inviteMember(
  orgId: string,
  formData: FormData,
): Promise<ActionResult> {
  const email = String(formData.get("email") ?? "")
    .trim()
    .toLowerCase();
  const roleId = String(formData.get("roleId") ?? "");

  if (!email || !roleId) {
    return { error: "ایمیل و نقش را وارد کنید" };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { error: "ابتدا وارد شوید" };
  }

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.MANAGE_MEMBERS,
  });
  if (!allowed) {
    return { error: "شما دسترسی دعوت عضو را ندارید" };
  }

  const { data: role } = await supabase
    .from("roles")
    .select("id")
    .eq("id", roleId)
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .maybeSingle();
  if (!role) {
    return { error: "نقش انتخاب‌شده نامعتبر است" };
  }

  const admin = createAdminClient();

  const { data: existingProfile } = await admin
    .from("profiles")
    .select("id")
    .eq("email", email)
    .maybeSingle();

  let targetUserId = existingProfile?.id;

  if (!targetUserId) {
    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://127.0.0.1:3000";
    // Supabase's default invite email points at GoTrue's own /verify
    // endpoint, which verifies the token and redirects here with the
    // session in the URL *hash fragment* (#access_token=...) -- not a
    // query param, and never sent to the server. set-password/page.tsx
    // reads it client-side.
    const { data: invited, error: inviteError } =
      await admin.auth.admin.inviteUserByEmail(email, {
        redirectTo: `${siteUrl}/auth/set-password`,
      });
    if (inviteError || !invited.user) {
      return { error: "دعوت ارسال نشد. دوباره تلاش کنید." };
    }
    targetUserId = invited.user.id;
  }

  const { error: memberError } = await admin.from("org_members").insert({
    org_id: orgId,
    user_id: targetUserId,
    role_id: roleId,
    invited_by: user.id,
  });

  if (memberError) {
    return {
      error:
        memberError.code === "23505"
          ? "این فرد قبلاً عضو این سازمان است"
          : "افزودن عضو انجام نشد",
    };
  }

  revalidatePath(`/${orgId}/members`);
  return { success: true };
}
