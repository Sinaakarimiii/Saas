"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { PERMISSIONS } from "@/lib/permissions";
import { sendInvitationEmail } from "@/lib/resend";

type ActionResult = { error?: string; success?: boolean };

export async function inviteMember(
  orgId: string,
  formData: FormData,
): Promise<ActionResult> {
  const email = String(formData.get("email") ?? "")
    .trim()
    .toLowerCase();
  const roleId = String(formData.get("roleId") ?? "");
  const managerId = String(formData.get("managerId") ?? "") || null;

  if (!email || !roleId) {
    return { error: "ایمیل و نقش را وارد کنید" };
  }
  if (!z.string().email().safeParse(email).success) {
    return { error: "نشانی ایمیل معتبر نیست" };
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
    .select("id, is_system, manager_invitable")
    .eq("id", roleId)
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .maybeSingle();
  if (!role) {
    return { error: "نقش انتخاب‌شده نامعتبر است" };
  }
  if (role.is_system) {
    return { error: "نقش مالک فقط از مسیر انتقال مالکیت قابل واگذاری است" };
  }

  const { data: actor } = await supabase
    .from("org_members")
    .select("roles(system_key)")
    .eq("org_id", orgId)
    .eq("user_id", user.id)
    .is("deleted_at", null)
    .maybeSingle();
  const isOwner = actor?.roles?.system_key === "owner";
  if (!isOwner && !role.manager_invitable) {
    return { error: "این نقش برای دعوت مدیر اعضا تأیید نشده است" };
  }
  if (managerId) {
    const { data: manager } = await supabase
      .from("org_members")
      .select("id")
      .eq("id", managerId)
      .eq("org_id", orgId)
      .eq("invitation_status", "active")
      .is("deleted_at", null)
      .maybeSingle();
    if (!manager) return { error: "سرپرست انتخاب‌شده معتبر نیست" };
  }

  const admin = createAdminClient();

  const { data: existingProfile } = await admin
    .from("profiles")
    .select("id")
    .eq("email", email)
    .maybeSingle();

  let targetUserId = existingProfile?.id;
  let existingMemberId: string | null = null;
  let confirmed = false;
  let actionLink: string | undefined;

  if (targetUserId) {
    const { data: existingMember, error: existingMemberError } = await admin
      .from("org_members")
      .select("id, role_id, manager_id, invitation_status")
      .eq("org_id", orgId)
      .eq("user_id", targetUserId)
      .is("deleted_at", null)
      .maybeSingle();
    if (existingMemberError) return { error: "وضعیت دعوت بررسی نشد" };
    if (existingMember) {
      if (existingMember.invitation_status !== "delivery_failed") {
        return { error: "این فرد قبلاً عضو این سازمان است یا دعوتش در انتظار تأیید است" };
      }
      if (existingMember.role_id !== roleId || existingMember.manager_id !== managerId) {
        return { error: "برای تلاش دوباره، نقش و سرپرست دعوت قبلی را انتخاب کنید" };
      }
      existingMemberId = existingMember.id;
    }

    const { data: existingUser, error: existingUserError } =
      await admin.auth.admin.getUserById(targetUserId);
    if (existingUserError || !existingUser.user) {
      return { error: "وضعیت حساب دعوت‌شده بررسی نشد" };
    }
    confirmed = Boolean(existingUser.user.email_confirmed_at);
  }

  if (!confirmed) {
    if (!process.env.INVITATION_MAILPIT_URL &&
      (!process.env.RESEND_API_KEY || !process.env.RESEND_FROM_EMAIL)) {
      return { error: "ارسال دعوت هنوز پیکربندی نشده است" };
    }
    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://127.0.0.1:3000";
    const { data: invited, error: inviteError } = await admin.auth.admin.generateLink({
      type: "invite",
      email,
      options: { redirectTo: `${siteUrl}/auth/set-password` },
    });
    if (inviteError || !invited.user || !invited.properties.action_link) {
      return { error: "دعوت ارسال نشد. دوباره تلاش کنید." };
    }
    targetUserId = invited.user.id;
    actionLink = invited.properties.action_link;
  }
  if (!targetUserId) return { error: "حساب دعوت‌شده ساخته نشد" };

  let memberId = existingMemberId;
  if (memberId) {
    const { data: reactivated, error: reactivateError } = await admin
      .from("org_members")
      .update({ invitation_status: confirmed ? "active" : "pending" })
      .eq("id", memberId)
      .eq("invitation_status", "delivery_failed")
      .select("id")
      .maybeSingle();
    if (reactivateError || !reactivated) {
      return { error: "تلاش دوباره برای دعوت انجام نشد" };
    }
  } else {
    const { data: member, error: memberError } = await supabase.from("org_members").insert({
      org_id: orgId,
      user_id: targetUserId,
      role_id: roleId,
      manager_id: managerId,
      invited_by: user.id,
      invitation_status: confirmed ? "active" : "pending",
    }).select("id").single();

    if (memberError) {
      return {
        error:
          memberError.code === "23505"
            ? "این فرد قبلاً عضو این سازمان است"
            : "افزودن عضو انجام نشد",
      };
    }
    memberId = member.id;
  }

  if (actionLink) {
    const delivery = await sendInvitationEmail({ to: email, actionLink });
    if (!delivery.ok) {
      await admin
        .from("org_members")
        .update({ invitation_status: "delivery_failed" })
        .eq("id", memberId)
        .eq("invitation_status", "pending");
      revalidatePath(`/${orgId}/members`);
      return { error: `عضویت ثبت شد، اما ارسال دعوت انجام نشد${delivery.status ? ` (HTTP ${delivery.status})` : ""}` };
    }
  }

  revalidatePath(`/${orgId}/members`);
  return { success: true };
}

export async function updateMember(
  orgId: string,
  memberId: string,
  input: { roleId: string; managerId: string | null; workMode: "unspecified" | "shift" | "fixed" },
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.MANAGE_MEMBERS,
  });
  if (!allowed) return { error: "شما دسترسی مدیریت اعضا را ندارید" };

  if (input.managerId === memberId) {
    return { error: "عضو نمی‌تواند سرپرست خودش باشد" };
  }

  const { data, error } = await supabase
    .from("org_members")
    .update({ role_id: input.roleId, manager_id: input.managerId, work_mode: input.workMode })
    .eq("id", memberId)
    .eq("org_id", orgId)
    .select("id")
    .maybeSingle();

  if (error || !data) {
    return {
      error: error?.message.includes("حلقه")
        ? "این تغییر باعث حلقه در زنجیره‌ی سرپرستی می‌شود"
        : "ویرایش عضو انجام نشد",
    };
  }

  revalidatePath(`/${orgId}/members`);
  return { success: true };
}

export async function transferOwnership(
  orgId: string,
  successorMemberId: string,
  formerOwnerRoleId: string,
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: member } = await supabase
    .from("org_members")
    .select("roles(system_key)")
    .eq("org_id", orgId)
    .eq("user_id", user.id)
    .is("deleted_at", null)
    .maybeSingle();
  if (member?.roles?.system_key !== "owner") {
    return { error: "فقط مالک فعلی می‌تواند مالکیت را منتقل کند" };
  }

  const { error } = await supabase.rpc("transfer_org_ownership", {
    p_org_id: orgId,
    p_successor_member_id: successorMemberId,
    p_former_owner_role_id: formerOwnerRoleId,
  });
  if (error) return { error: "انتقال مالکیت انجام نشد؛ عضو و نقش مقصد را بررسی کنید" };

  revalidatePath(`/${orgId}/members`);
  revalidatePath(`/${orgId}/dashboard`);
  return { success: true };
}
