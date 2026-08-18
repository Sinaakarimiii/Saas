import { notFound, redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import {
  FIELD_TYPE_LABELS,
  NUMBER_FORMAT_LABELS,
  TEXT_FORMAT_LABELS,
  DATE_CONSTRAINT_LABELS,
  type FieldOptions,
} from "@/lib/form-fields";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { AddFieldDialog } from "./field-dialog";
import { RemoveFieldButton } from "./remove-field-button";

function optionBadges(fieldType: string, options: FieldOptions | null): string[] {
  if (!options) return [];
  const badges: string[] = [];
  if (fieldType === "select" && options.selectionMode === "multiple") badges.push("چندگزینه‌ای");
  if (fieldType === "text" && options.textFormat && options.textFormat !== "free") {
    badges.push(TEXT_FORMAT_LABELS[options.textFormat]);
  }
  if (fieldType === "number" && options.numberFormat && options.numberFormat !== "free") {
    badges.push(
      options.numberFormat === "fixed_digits"
        ? `${options.digitCount ?? "?"} رقمی`
        : NUMBER_FORMAT_LABELS[options.numberFormat],
    );
  }
  if (fieldType === "date_jalali" && options.dateConstraint && options.dateConstraint !== "none") {
    badges.push(DATE_CONSTRAINT_LABELS[options.dateConstraint]);
  }
  if (options.repeatable) badges.push("تکرارپذیر");
  return badges;
}

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
        {(fields ?? []).map((field) => {
          const options = (field.options as FieldOptions | null) ?? null;
          const badges = optionBadges(field.field_type, options);
          return (
            <Card key={field.id}>
              <CardHeader className="flex-row items-center justify-between">
                <CardTitle className="flex flex-wrap items-center gap-2 text-base">
                  {field.label}
                  <Badge variant="outline">
                    {FIELD_TYPE_LABELS[field.field_type as keyof typeof FIELD_TYPE_LABELS] ??
                      field.field_type}
                  </Badge>
                  {field.is_required && <Badge variant="secondary">اجباری</Badge>}
                  {badges.map((b) => (
                    <Badge key={b} variant="secondary">
                      {b}
                    </Badge>
                  ))}
                </CardTitle>
                <RemoveFieldButton
                  orgId={orgId}
                  formTemplateId={formId}
                  fieldId={field.id}
                />
              </CardHeader>
              {field.field_type === "select" && (options?.choices?.length ?? 0) > 0 && (
                <CardContent className="text-muted-foreground text-sm">
                  گزینه‌ها: {options!.choices!.join("، ")}
                </CardContent>
              )}
            </Card>
          );
        })}
      </div>
    </div>
  );
}
