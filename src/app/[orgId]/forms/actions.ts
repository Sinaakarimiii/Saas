"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";

type ActionResult = { error?: string; success?: boolean };

async function assertCanManageForms(orgId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { supabase, ok: false as const, error: "ابتدا وارد شوید" };

  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: PERMISSIONS.MANAGE_FORMS,
  });
  if (!allowed) {
    return { supabase, ok: false as const, error: "شما دسترسی مدیریت فرم‌ها را ندارید" };
  }
  return { supabase, ok: true as const };
}

export async function createFormTemplate(orgId: string, formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return { error: "نام فرم نمی‌تواند خالی باشد" };

  const check = await assertCanManageForms(orgId);
  if (!check.ok) return { error: check.error };
  const { supabase } = check;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: template, error } = await supabase
    .from("form_templates")
    .insert({ org_id: orgId, name, created_by: user!.id })
    .select("id")
    .single();

  if (error || !template) {
    return { error: "ساخت فرم انجام نشد" };
  }

  redirect(`/${orgId}/forms/${template.id}`);
}

const FIELD_TYPES = ["text", "number", "date_jalali", "select", "file"] as const;

export async function addField(
  orgId: string,
  formTemplateId: string,
  input: {
    label: string;
    fieldType: (typeof FIELD_TYPES)[number];
    isRequired: boolean;
    options: string[];
  },
): Promise<ActionResult> {
  const check = await assertCanManageForms(orgId);
  if (!check.ok) return { error: check.error };
  const { supabase } = check;

  const label = input.label.trim();
  if (!label) return { error: "برچسب فیلد نمی‌تواند خالی باشد" };
  if (!FIELD_TYPES.includes(input.fieldType)) {
    return { error: "نوع فیلد نامعتبر است" };
  }

  const key = label
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "_")
    .replace(/^_+|_+$/g, "");

  const { count } = await supabase
    .from("form_fields")
    .select("id", { count: "exact", head: true })
    .eq("form_template_id", formTemplateId)
    .is("deleted_at", null);

  const { error } = await supabase.from("form_fields").insert({
    form_template_id: formTemplateId,
    key: key || `field_${Date.now()}`,
    label,
    field_type: input.fieldType,
    is_required: input.isRequired,
    sort_order: count ?? 0,
    options: input.fieldType === "select" ? input.options : null,
  });

  if (error) {
    return {
      error:
        error.code === "23505"
          ? "فیلدی با این برچسب از قبل وجود دارد"
          : "افزودن فیلد انجام نشد",
    };
  }

  revalidatePath(`/${orgId}/forms/${formTemplateId}`);
  return { success: true };
}

export async function removeField(
  orgId: string,
  formTemplateId: string,
  fieldId: string,
): Promise<ActionResult> {
  const check = await assertCanManageForms(orgId);
  if (!check.ok) return { error: check.error };
  const { supabase } = check;

  const { error } = await supabase
    .from("form_fields")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", fieldId);

  if (error) return { error: "حذف فیلد انجام نشد" };

  revalidatePath(`/${orgId}/forms/${formTemplateId}`);
  return { success: true };
}
