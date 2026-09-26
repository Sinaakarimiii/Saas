"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";

type ActionResult = { error?: string; success?: boolean };

async function getSelfMembership(orgId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { supabase, user: null, memberId: null };

  const { data: member } = await supabase
    .from("org_members")
    .select("id")
    .eq("org_id", orgId)
    .eq("user_id", user.id)
    .is("deleted_at", null)
    .maybeSingle();

  return { supabase, user, memberId: member?.id ?? null };
}

export async function submitLeaveRequest(
  orgId: string,
  input: { leaveTypeId: string; startsAt: string; endsAt: string; note: string },
): Promise<ActionResult> {
  const { supabase, user, memberId } = await getSelfMembership(orgId);
  if (!user || !memberId) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.LEAVE_REQUEST,
  });
  if (!allowed) return { error: "شما دسترسی ثبت درخواست مرخصی را ندارید" };

  if (new Date(input.endsAt) <= new Date(input.startsAt)) {
    return { error: "پایان مرخصی باید بعد از شروع آن باشد" };
  }

  const { error } = await supabase.from("leave_requests").insert({
    org_id: orgId,
    member_id: memberId,
    leave_type_id: input.leaveTypeId,
    starts_at: input.startsAt,
    ends_at: input.endsAt,
    note: input.note || null,
    created_by: user.id,
  });

  if (error) return { error: "ثبت درخواست انجام نشد" };

  revalidatePath(`/${orgId}/leave`);
  return { success: true };
}

// For someone with leave.approve (all/team scope): create a leave request
// for a subordinate and finalize it in the same step, instead of forcing a
// self-approval round-trip. RLS (leave_requests_insert_own_or_managed)
// re-checks the scope/manager-chain server-side regardless of what the UI
// sent, so an out-of-scope memberId just fails here with a Postgres error.
export async function createLeaveForMember(
  orgId: string,
  input: { memberId: string; leaveTypeId: string; startsAt: string; endsAt: string; note: string },
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.LEAVE_APPROVE,
  });
  if (!allowed) return { error: "شما دسترسی ثبت مرخصی برای دیگران را ندارید" };

  if (new Date(input.endsAt) <= new Date(input.startsAt)) {
    return { error: "پایان مرخصی باید بعد از شروع آن باشد" };
  }

  const { error } = await supabase.from("leave_requests").insert({
    org_id: orgId,
    member_id: input.memberId,
    leave_type_id: input.leaveTypeId,
    starts_at: input.startsAt,
    ends_at: input.endsAt,
    note: input.note || null,
    created_by: user.id,
    status: "approved",
    reviewed_by: user.id,
    reviewed_at: new Date().toISOString(),
  });

  if (error) {
    return {
      error:
        error.code === "42501"
          ? "این عضو در زیرمجموعه‌ی سرپرستی شما نیست"
          : "ثبت مرخصی انجام نشد",
    };
  }

  revalidatePath(`/${orgId}/leave`);
  return { success: true };
}

export async function reviewLeaveRequest(
  orgId: string,
  requestId: string,
  status: "approved" | "rejected",
  reviewNote: string,
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.LEAVE_APPROVE,
  });
  if (!allowed) return { error: "شما دسترسی تایید مرخصی را ندارید" };

  const { data, error } = await supabase
    .from("leave_requests")
    .update({
      status,
      reviewed_by: user.id,
      reviewed_at: new Date().toISOString(),
      review_note: reviewNote || null,
    })
    .eq("id", requestId)
    .eq("org_id", orgId)
    .select("id")
    .maybeSingle();

  if (error || !data) return { error: "ثبت تصمیم انجام نشد" };

  revalidatePath(`/${orgId}/leave`);
  return { success: true };
}

export async function createLeaveType(
  orgId: string,
  input: { name: string; unit: "day" | "hour" },
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.LEAVE_APPROVE,
  });
  if (!allowed) return { error: "شما دسترسی مدیریت انواع مرخصی را ندارید" };

  const name = input.name.trim();
  if (!name) return { error: "نام نوع مرخصی نمی‌تواند خالی باشد" };

  const { error } = await supabase.from("leave_types").insert({
    org_id: orgId,
    name,
    unit: input.unit,
  });

  if (error) return { error: "ساخت نوع مرخصی انجام نشد" };

  revalidatePath(`/${orgId}/leave`);
  return { success: true };
}
