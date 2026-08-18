"use client";

import { useMemo } from "react";
import DatePicker from "react-multi-date-picker";
import DateObject from "react-date-object";
import persian from "react-date-object/calendars/persian";
import persian_fa from "react-date-object/locales/persian_fa";

import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { isRedDay, redDayClassName } from "@/lib/holidays";
import { uploadTicketFile } from "@/lib/upload-ticket-file";
import {
  textFormatPattern,
  type FieldOptions,
} from "@/lib/form-fields";
import type { Json } from "@/lib/supabase/types";

export type FormFieldDef = {
  id: string;
  key: string;
  label: string;
  field_type: string;
  is_required: boolean;
  options: unknown;
};

// A single field's in-progress value: something JSON-safe ready to send to
// the server, a File the user just picked but hasn't uploaded yet (upload
// happens at submit time, see resolveFieldValueForSubmit), or -- for
// repeatable fields -- an array of either.
export type SingleValue = Json | File | null | undefined;
export type FieldValue = SingleValue | SingleValue[];

const dateInputClass =
  "flex h-8 w-full rounded-lg border border-input bg-transparent px-2.5 py-1 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30";

function getOptions(field: FormFieldDef): FieldOptions {
  return (field.options as FieldOptions | null) ?? {};
}

// Split out so useMemo stays an unconditional top-level hook call, instead
// of living inside one branch of a switch.
function JalaliFormDateField({
  value,
  onChange,
  holidays,
  dateConstraint,
}: {
  value: SingleValue;
  onChange: (value: SingleValue) => void;
  holidays: string[];
  dateConstraint?: "none" | "past_only" | "future_only";
}) {
  const holidaySet = useMemo(() => new Set(holidays), [holidays]);
  const today = useMemo(() => new DateObject({ calendar: persian, locale: persian_fa }), []);

  return (
    <DatePicker
      calendar={persian}
      locale={persian_fa}
      value={typeof value === "string" ? value : ""}
      onChange={(date) => onChange(date ? date.toString() : null)}
      mapDays={({ date }) =>
        isRedDay(date, holidaySet) ? { className: redDayClassName } : undefined
      }
      minDate={dateConstraint === "future_only" ? today : undefined}
      maxDate={dateConstraint === "past_only" ? today : undefined}
      inputClass={dateInputClass}
      containerClassName="w-full"
    />
  );
}

// Renders exactly one instance of a field's input (no repeatability), given
// a single scalar value. Used directly for non-repeatable fields, and N
// times over by RepeatableField for repeatable ones.
function SingleFieldInput({
  field,
  value,
  onChange,
  holidays,
}: {
  field: FormFieldDef;
  value: SingleValue;
  onChange: (value: SingleValue) => void;
  holidays: string[];
}) {
  const options = getOptions(field);

  switch (field.field_type) {
    case "textarea":
      return (
        <Textarea
          value={typeof value === "string" ? value : ""}
          onChange={(e) => onChange(e.target.value)}
          placeholder={options.placeholder}
          maxLength={options.maxLength}
          required={field.is_required}
          rows={3}
        />
      );
    case "number": {
      const format = options.numberFormat ?? "free";
      const pattern =
        format === "mobile"
          ? "^(0|\\+98|0098)?9\\d{9}$"
          : format === "fixed_digits" && options.digitCount
            ? `^\\d{${options.digitCount}}$`
            : undefined;
      return (
        <Input
          type={format === "mobile" || format === "fixed_digits" ? "text" : "number"}
          inputMode={format === "mobile" || format === "fixed_digits" ? "numeric" : undefined}
          dir="ltr"
          value={typeof value === "number" || typeof value === "string" ? value : ""}
          onChange={(e) => onChange(e.target.value === "" ? null : e.target.value)}
          onBlur={(e) => {
            if (format !== "mobile" && format !== "fixed_digits" && e.target.value !== "") {
              onChange(Number(e.target.value));
            }
          }}
          pattern={pattern}
          step={format === "integer" ? 1 : undefined}
          min={options.min}
          max={options.max}
          maxLength={format === "fixed_digits" ? options.digitCount : undefined}
          required={field.is_required}
        />
      );
    }
    case "date_jalali":
      return (
        <JalaliFormDateField
          value={value}
          onChange={onChange}
          holidays={holidays}
          dateConstraint={options.dateConstraint}
        />
      );
    case "boolean":
      return (
        <Checkbox
          checked={value === true}
          onCheckedChange={(c) => onChange(c === true)}
        />
      );
    case "file":
      return (
        <Input
          type="file"
          onChange={(e) => onChange(e.target.files?.[0] ?? null)}
        />
      );
    default: {
      const pattern = textFormatPattern(options.textFormat)?.source;
      return (
        <Input
          type={options.textFormat === "email" ? "email" : options.textFormat === "mobile" ? "tel" : "text"}
          dir={options.textFormat === "mobile" ? "ltr" : undefined}
          value={typeof value === "string" ? value : ""}
          onChange={(e) => onChange(e.target.value)}
          placeholder={options.placeholder}
          pattern={pattern}
          minLength={options.minLength}
          maxLength={options.maxLength}
          required={field.is_required}
        />
      );
    }
  }
}

function RepeatableField({
  field,
  value,
  onChange,
  holidays,
}: {
  field: FormFieldDef;
  value: FieldValue;
  onChange: (value: FieldValue) => void;
  holidays: string[];
}) {
  const items: SingleValue[] = Array.isArray(value) ? value : value != null ? [value] : [""];

  function updateAt(index: number, next: SingleValue) {
    const copy = [...items];
    copy[index] = next;
    onChange(copy);
  }

  function removeAt(index: number) {
    const copy = items.filter((_, i) => i !== index);
    onChange(copy.length > 0 ? copy : [""]);
  }

  return (
    <div className="grid gap-2">
      {items.map((item, i) => (
        <div key={i} className="flex items-center gap-2">
          <div className="flex-1">
            <SingleFieldInput
              field={field}
              value={item}
              onChange={(v) => updateAt(i, v)}
              holidays={holidays}
            />
          </div>
          {items.length > 1 && (
            <Button type="button" variant="ghost" size="sm" onClick={() => removeAt(i)}>
              حذف
            </Button>
          )}
        </div>
      ))}
      <Button type="button" variant="outline" size="sm" onClick={() => onChange([...items, ""])}>
        + افزودن یک مورد دیگر
      </Button>
    </div>
  );
}

// null/undefined/"" (or an array made up only of those) counts as unset;
// `false` is a real answer for a boolean field, not an empty one.
export function isFieldValueEmpty(value: FieldValue): boolean {
  const isEmptyScalar = (v: SingleValue) => v === null || v === undefined || v === "";
  if (Array.isArray(value)) return value.every(isEmptyScalar);
  return isEmptyScalar(value as SingleValue);
}

// Uploads any File values (single or, for a repeatable field, every File in
// the array) to Storage and swaps them for the uploaded metadata, so the
// server action always receives plain JSON -- used by both the new-ticket
// form and the single-field edit dialog.
export async function resolveFieldValueForSubmit(
  orgId: string,
  field: FormFieldDef,
  value: FieldValue,
): Promise<Json> {
  async function resolveOne(v: SingleValue): Promise<Json> {
    if (field.field_type === "file" && v instanceof File) {
      return await uploadTicketFile(orgId, field.id, v);
    }
    return (v ?? null) as Json;
  }

  if (Array.isArray(value)) {
    return (await Promise.all(value.map(resolveOne))) as Json;
  }
  return resolveOne(value as SingleValue);
}

export function DynamicFieldInput({
  field,
  value,
  onChange,
  holidays = [],
}: {
  field: FormFieldDef;
  value: FieldValue;
  onChange: (value: FieldValue) => void;
  holidays?: string[];
}) {
  const options = getOptions(field);

  if (field.field_type === "select") {
    const choices = options.choices ?? [];
    if (options.selectionMode === "multiple") {
      const selected: string[] = Array.isArray(value) ? (value as string[]) : [];
      return (
        <div className="grid gap-2">
          {choices.map((opt) => (
            <div key={opt} className="flex items-center gap-2">
              <Checkbox
                id={`${field.id}-${opt}`}
                checked={selected.includes(opt)}
                onCheckedChange={(c) =>
                  onChange(c === true ? [...selected, opt] : selected.filter((s) => s !== opt))
                }
              />
              <Label htmlFor={`${field.id}-${opt}`} className="font-normal">
                {opt}
              </Label>
            </div>
          ))}
        </div>
      );
    }
    return (
      <Select
        value={typeof value === "string" ? value : undefined}
        onValueChange={(v) => onChange(v)}
      >
        <SelectTrigger className="w-full">
          <SelectValue placeholder="انتخاب کنید" />
        </SelectTrigger>
        <SelectContent>
          {choices.map((opt) => (
            <SelectItem key={opt} value={opt}>
              {opt}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    );
  }

  if (options.repeatable) {
    return (
      <RepeatableField field={field} value={value} onChange={onChange} holidays={holidays} />
    );
  }

  return (
    <SingleFieldInput
      field={field}
      value={value as SingleValue}
      onChange={onChange}
      holidays={holidays}
    />
  );
}
