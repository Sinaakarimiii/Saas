import { notFound, redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { AddFieldDialog } from "./field-dialog";
import { RemoveFieldButton } from "./remove-field-button";

const FIELD_TYPE_LABELS: Record<string, string> = {
  text: "متن",
  number: "عدد",
  date_jalali: "تاریخ شمسی",
  select: "انتخابی",
  file: "آپلود فایل",
};

export default async function FormEditorPage({
  params,
}: PageProps<"/[orgId]/forms/[formId]">) {
  const { orgId, formId } = await params;
  const ctx = await getOrgContext(orgId);

  if (!ctx.can(PERMISSIONS.MANAGE_FORMS)) {
    redirect(`/${orgId}/dashboard`);
  }

  const supabase = await createClient();

  const { data: template } = await supabase
    .from("form_templates")
    .select("id, name")
    .eq("id", formId)
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .maybeSingle();

  if (!template) {
    notFound();
  }

  const { data: fields } = await supabase
    .from("form_fields")
    .select("id, label, field_type, is_required, options")
    .eq("form_template_id", formId)
    .is("deleted_at", null)
    .order("sort_order", { ascending: true });

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">{template.name}</h1>
        <AddFieldDialog orgId={orgId} formTemplateId={formId} />
      </div>

      {(fields ?? []).length === 0 && (
        <p className="text-muted-foreground">
          هنوز فیلدی به این فرم اضافه نشده.
        </p>
      )}

      <div className="grid gap-2">
        {(fields ?? []).map((field) => (
          <Card key={field.id}>
            <CardHeader className="flex-row items-center justify-between">
              <CardTitle className="flex items-center gap-2 text-base">
                {field.label}
                <Badge variant="outline">
                  {FIELD_TYPE_LABELS[field.field_type] ?? field.field_type}
                </Badge>
                {field.is_required && (
                  <Badge variant="secondary">اجباری</Badge>
                )}
              </CardTitle>
              <RemoveFieldButton
                orgId={orgId}
                formTemplateId={formId}
                fieldId={field.id}
              />
            </CardHeader>
            {field.field_type === "select" &&
              Array.isArray(field.options) &&
              field.options.length > 0 && (
                <CardContent className="text-muted-foreground text-sm">
                  گزینه‌ها: {(field.options as string[]).join("، ")}
                </CardContent>
              )}
          </Card>
        ))}
      </div>
    </div>
  );
}
