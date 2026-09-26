"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";

type ActionResult = { error?: string; success?: boolean };

async function assertCanManageShifts(orgId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { supabase, user: null, ok: false as const, error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.SHIFT_MANAGE,
  });
  if (!allowed) {
    return { supabase, user, ok: false as const, error: "شما دسترسی مدیریت شیفت را ندارید" };
  }
  return { supabase, user, ok: true as const };
}

export async function createShiftTemplate(
  orgId: string,
  input: { name: string; startTime: string; endTime: string; colorHex: string },
): Promise<ActionResult> {
  const check = await assertCanManageShifts(orgId);
  if (!check.ok) return { error: check.error };
  const { supabase } = check;

  const name = input.name.trim();
  if (!name) return { error: "نام قالب نمی‌تواند خالی باشد" };
  if (!/^#[0-9A-Fa-f]{6}$/.test(input.colorHex)) return { error: "رنگ شیفت معتبر نیست" };

  const { error } = await supabase.from("shift_templates").insert({
    org_id: orgId,
    name,
    start_time: input.startTime,
    end_time: input.endTime,
    color_hex: input.colorHex,
  });

  if (error) return { error: "ساخت قالب انجام نشد" };

  revalidatePath(`/${orgId}/shifts`);
  return { success: true };
}

export async function removeShiftTemplate(orgId: string, templateId: string): Promise<ActionResult> {
  const check = await assertCanManageShifts(orgId);
  if (!check.ok) return { error: check.error };
  const { supabase } = check;

  const { data, error } = await supabase
    .from("shift_templates")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", templateId)
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .select("id")
    .maybeSingle();

  if (error || !data) return { error: "حذف قالب انجام نشد" };

  revalidatePath(`/${orgId}/shifts`);
  return { success: true };
}

export async function createShiftAssignment(
  orgId: string,
  input: {
    memberId: string;
    shiftTemplateId: string | null;
    title: string;
    workDate: string;
    startTime: string;
    endTime: string;
    note: string;
    colorHex: string;
  },
): Promise<ActionResult> {
  const check = await assertCanManageShifts(orgId);
  if (!check.ok) return { error: check.error };
  const { supabase, user } = check;

  const title = input.title.trim();
  if (!title) return { error: "عنوان شیفت نمی‌تواند خالی باشد" };
  if (!/^#[0-9A-Fa-f]{6}$/.test(input.colorHex)) return { error: "رنگ شیفت معتبر نیست" };

  const { error } = await supabase.from("shift_assignments").insert({
    org_id: orgId,
    member_id: input.memberId,
    shift_template_id: input.shiftTemplateId,
    title,
    work_date: input.workDate,
    start_time: input.startTime,
    end_time: input.endTime,
    note: input.note || null,
    color_hex: input.colorHex,
    created_by: user!.id,
  });

  if (error) return { error: "ثبت شیفت انجام نشد" };

  revalidatePath(`/${orgId}/shifts`);
  revalidatePath(`/${orgId}/calendar`);
  return { success: true };
}

export async function removeShiftAssignment(orgId: string, assignmentId: string): Promise<ActionResult> {
  const check = await assertCanManageShifts(orgId);
  if (!check.ok) return { error: check.error };
  const { supabase } = check;

  const { data, error } = await supabase
    .from("shift_assignments")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", assignmentId)
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .select("id")
    .maybeSingle();

  if (error || !data) return { error: "حذف شیفت انجام نشد" };

  revalidatePath(`/${orgId}/shifts`);
  return { success: true };
}
