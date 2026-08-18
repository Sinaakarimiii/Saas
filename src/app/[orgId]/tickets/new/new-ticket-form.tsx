"use client";

import { useMemo, useState } from "react";
import { createTicketAction } from "../actions";
import {
  DynamicFieldInput,
  isFieldValueEmpty,
  resolveFieldValueForSubmit,
  type FormFieldDef,
  type FieldValue,
} from "../field-input";
import type { Json } from "@/lib/supabase/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

type FormTemplate = {
  id: string;
  name: string;
  fields: FormFieldDef[];
};

export function NewTicketForm({
  orgId,
  templates,
  holidays,
}: {
  orgId: string;
  templates: FormTemplate[];
  holidays: string[];
}) {
  const [formTemplateId, setFormTemplateId] = useState(templates[0]?.id ?? "");
  const [title, setTitle] = useState("");
  const [values, setValues] = useState<Record<string, FieldValue>>({});
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const activeTemplate = useMemo(
    () => templates.find((t) => t.id === formTemplateId),
    [templates, formTemplateId],
  );

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!activeTemplate) {
      setError("یک فرم انتخاب کنید");
      return;
    }

    for (const field of activeTemplate.fields) {
      if (field.is_required && isFieldValueEmpty(values[field.id])) {
        setError(`فیلد «${field.label}» اجباری است`);
        return;
      }
    }

    setIsSubmitting(true);
    try {
      const fieldValues: { form_field_id: string; value: Json }[] = await Promise.all(
        activeTemplate.fields.map(async (field) => ({
          form_field_id: field.id,
          value: await resolveFieldValueForSubmit(orgId, field, values[field.id]),
        })),
      );

      const result = await createTicketAction(
        orgId,
        activeTemplate.id,
        title,
        fieldValues,
      );
      if (result?.error) {
        setError(result.error);
      }
    } catch {
      setError("ثبت تیکت انجام نشد. دوباره تلاش کنید.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="grid max-w-lg gap-4">
      {templates.length > 1 && (
        <div className="grid gap-2">
          <Label>فرم</Label>
          <Select
            value={formTemplateId}
            onValueChange={(v) => {
              setFormTemplateId(v);
              setValues({});
            }}
          >
            <SelectTrigger className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {templates.map((t) => (
                <SelectItem key={t.id} value={t.id}>
                  {t.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      )}

      <div className="grid gap-2">
        <Label htmlFor="ticket-title">عنوان (اختیاری)</Label>
        <Input
          id="ticket-title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="خلاصه‌ی کوتاهی از تیکت"
        />
      </div>

      {activeTemplate?.fields.map((field) => (
        <div key={field.id} className="grid gap-2">
          <Label>
            {field.label}
            {field.is_required && <span className="text-destructive"> *</span>}
          </Label>
          <DynamicFieldInput
            field={field}
            value={values[field.id]}
            onChange={(v) => setValues((prev) => ({ ...prev, [field.id]: v }))}
            holidays={holidays}
          />
        </div>
      ))}

      {error && <p className="text-destructive text-sm">{error}</p>}

      <Button type="submit" disabled={isSubmitting || !activeTemplate}>
        ثبت تیکت
      </Button>
    </form>
  );
}
