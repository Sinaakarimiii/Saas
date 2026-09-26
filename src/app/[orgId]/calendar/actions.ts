"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import type { DayStatus } from "@/lib/holidays";

type ActionResult = { error?: string; success?: boolean };

const VALID_STATUSES: DayStatus[] = ["official_holiday", "unofficial_holiday", "workday"];
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export async function setDayStatus(
  orgId: string,
  date: string,
  status: DayStatus,
  note?: string,
): Promise<ActionResult> {
  if (!ISO_DATE_RE.test(date)) return { error: "تاریخ نامعتبر است" };
  if (!VALID_STATUSES.includes(status)) return { error: "وضعیت نامعتبر است" };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.CALENDAR_MANAGE_DAYS,
  });
  if (!allowed) {
    return { error: "شما دسترسی تغییر وضعیت روزها را ندارید" };
  }

  const trimmedNote = note?.trim();
  const { error } = await supabase.from("calendar_day_status").upsert(
    {
      org_id: orgId,
      gregorian_date: date,
      status,
      note: trimmedNote || null,
      created_by: user.id,
    },
    { onConflict: "org_id,gregorian_date" },
  );

  if (error) return { error: "ثبت وضعیت روز انجام نشد" };

  revalidatePath(`/${orgId}/calendar`);
  return { success: true };
}
