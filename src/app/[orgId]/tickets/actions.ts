"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import type { Json } from "@/lib/supabase/types";

type ActionResult = { error?: string; success?: boolean };

export async function createTicketAction(
  orgId: string,
  formTemplateId: string,
  title: string,
  fieldValues: { form_field_id: string; value: Json }[],
) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.TICKET_CREATE,
  });
  if (!allowed) return { error: "شما دسترسی ساخت تیکت را ندارید" };

  // create_ticket returns a single row (not a set) -- no .single() here,
  // see the comment in src/app/orgs/new/actions.ts for why.
  const { data: ticket, error } = await supabase.rpc("create_ticket", {
    p_org_id: orgId,
    p_form_template_id: formTemplateId,
    p_title: title,
    p_field_values: fieldValues as Json,
  });

  if (error || !ticket) {
    return { error: "ثبت تیکت انجام نشد. دوباره تلاش کنید." };
  }

  redirect(`/${orgId}/tickets/${ticket.id}`);
}

export async function updateTicketFieldValueAction(
  orgId: string,
  ticketId: string,
  formFieldId: string,
  value: Json,
  note: string,
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("update_ticket_field_value", {
    p_ticket_id: ticketId,
    p_form_field_id: formFieldId,
    p_value: value,
    p_note: note || undefined,
  });

  if (error) return { error: "ذخیره‌ی تغییر انجام نشد" };

  revalidatePath(`/${orgId}/tickets/${ticketId}`);
  return { success: true };
}

export async function updateTicketStatusAction(
  orgId: string,
  ticketId: string,
  status: "open" | "closed",
  note: string,
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("update_ticket_status", {
    p_ticket_id: ticketId,
    p_status: status,
    p_note: note || undefined,
  });

  if (error) return { error: "تغییر وضعیت انجام نشد" };

  revalidatePath(`/${orgId}/tickets/${ticketId}`);
  return { success: true };
}
