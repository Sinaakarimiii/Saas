"use client";

import DatePicker from "react-multi-date-picker";
import persian from "react-date-object/calendars/persian";
import persian_fa from "react-date-object/locales/persian_fa";

import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { Json } from "@/lib/supabase/types";

export type FormFieldDef = {
  id: string;
  key: string;
  label: string;
  field_type: string;
  is_required: boolean;
  options: unknown;
};

// A field's in-progress value in the browser: either something JSON-safe
// that's ready to send to the server, or a File the user just picked but
// hasn't been uploaded to Storage yet (that upload happens at submit time,
// see uploadTicketFile).
export type FieldValue = Json | File | null | undefined;

const dateInputClass =
  "flex h-8 w-full rounded-lg border border-input bg-transparent px-2.5 py-1 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30";

export function DynamicFieldInput({
  field,
  value,
  onChange,
}: {
  field: FormFieldDef;
  value: FieldValue;
  onChange: (value: FieldValue) => void;
}) {
  switch (field.field_type) {
    case "number":
      return (
        <Input
          type="number"
          value={typeof value === "number" || typeof value === "string" ? value : ""}
          onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
          required={field.is_required}
        />
      );
    case "date_jalali":
      return (
        <DatePicker
          calendar={persian}
          locale={persian_fa}
          value={typeof value === "string" ? value : ""}
          onChange={(date) => onChange(date ? date.toString() : null)}
          inputClass={dateInputClass}
          containerClassName="w-full"
        />
      );
    case "select": {
      const options = Array.isArray(field.options)
        ? (field.options as string[])
        : [];
      return (
        <Select
          value={typeof value === "string" ? value : undefined}
          onValueChange={(v) => onChange(v)}
        >
          <SelectTrigger className="w-full">
            <SelectValue placeholder="انتخاب کنید" />
          </SelectTrigger>
          <SelectContent>
            {options.map((opt) => (
              <SelectItem key={opt} value={opt}>
                {opt}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      );
    }
    case "file":
      return (
        <Input
          type="file"
          onChange={(e) => onChange(e.target.files?.[0] ?? null)}
        />
      );
    default:
      return (
        <Input
          type="text"
          value={typeof value === "string" ? value : ""}
          onChange={(e) => onChange(e.target.value)}
          required={field.is_required}
        />
      );
  }
}
