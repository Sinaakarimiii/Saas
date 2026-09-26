"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";

type ActionResult = { error?: string; success?: boolean };

export async function recordAttendance(
  orgId: string,
  eventTypeId: string,
  note: string,
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.ATTENDANCE_RECORD,
  });
  if (!allowed) return { error: "شما دسترسی ثبت حضور را ندارید" };

  const { data: member } = await supabase
    .from("org_members")
    .select("id")
    .eq("org_id", orgId)
    .eq("user_id", user.id)
    .is("deleted_at", null)
    .maybeSingle();
  if (!member) return { error: "عضویت شما در این سازمان یافت نشد" };

  const { error } = await supabase.from("attendance_logs").insert({
    org_id: orgId,
    member_id: member.id,
    event_type_id: eventTypeId,
    note: note || null,
    created_by: user.id,
  });

  if (error) return { error: "ثبت حضور انجام نشد" };

  revalidatePath(`/${orgId}/attendance`);
  return { success: true };
}

export async function createAttendanceEventType(
  orgId: string,
  input: { name: string; toggle: boolean },
): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.SHIFT_MANAGE,
  });
  if (!allowed) return { error: "شما دسترسی مدیریت رویدادهای حضور را ندارید" };

  const name = input.name.trim();
  if (!name) return { error: "نام رویداد را وارد کنید" };

  const { error } = await supabase.from("attendance_event_types").insert({
    org_id: orgId,
    name,
    kind: "other",
    toggle: input.toggle,
  });

  if (error) {
    return {
      error:
        error.code === "23505"
          ? "رویدادی با این نام قبلاً ساخته شده"
          : "ساخت نوع رویداد انجام نشد",
    };
  }

  revalidatePath(`/${orgId}/attendance`);
  return { success: true };
}

export async function voidAttendanceLog(orgId: string, logId: string): Promise<ActionResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data, error } = await supabase
    .from("attendance_logs")
    .update({ voided_at: new Date().toISOString(), voided_by: user.id })
    .eq("id", logId)
    .eq("org_id", orgId)
    .is("voided_at", null)
    .select("id")
    .maybeSingle();

  if (error || !data) return { error: "باطل‌کردن ثبت انجام نشد" };

  revalidatePath(`/${orgId}/attendance`);
  return { success: true };
}
