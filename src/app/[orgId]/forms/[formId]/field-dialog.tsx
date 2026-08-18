"use client";

import { useState, useTransition } from "react";
import { addField } from "../actions";
import {
  FIELD_TYPES,
  FIELD_TYPE_LABELS,
  TEXT_FORMAT_LABELS,
  NUMBER_FORMAT_LABELS,
  DATE_CONSTRAINT_LABELS,
  type FieldType,
  type FieldOptions,
  type TextFormat,
  type NumberFormat,
  type DateConstraint,
  type SelectionMode,
} from "@/lib/form-fields";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

const REPEATABLE_ELIGIBLE: FieldType[] = ["text", "textarea", "number", "date_jalali", "file"];

function emptyOptions(): FieldOptions {
  return {};
}

export function AddFieldDialog({
  orgId,
  formTemplateId,
}: {
  orgId: string;
  formTemplateId: string;
}) {
  const [open, setOpen] = useState(false);
  const [label, setLabel] = useState("");
  const [fieldType, setFieldType] = useState<FieldType>("text");
  const [isRequired, setIsRequired] = useState(false);
  const [options, setOptions] = useState<FieldOptions>(emptyOptions());
  const [choicesText, setChoicesText] = useState("");
  const [extensionsText, setExtensionsText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function reset() {
    setLabel("");
    setFieldType("text");
    setIsRequired(false);
    setOptions(emptyOptions());
    setChoicesText("");
    setExtensionsText("");
  }

  function patchOptions(patch: Partial<FieldOptions>) {
    setOptions((prev) => ({ ...prev, ...patch }));
  }

  function onSubmit() {
    setError(null);

    const finalOptions: FieldOptions = { ...options };
    if (fieldType === "select") {
      finalOptions.choices = choicesText
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);
      if (finalOptions.choices.length === 0) {
        setError("حداقل یک گزینه برای فیلد انتخابی وارد کنید");
        return;
      }
    }
    if (fieldType === "file") {
      const exts = extensionsText
        .split(",")
        .map((s) => s.trim().replace(/^\./, "").toLowerCase())
        .filter(Boolean);
      if (exts.length > 0) finalOptions.allowedExtensions = exts;
    }
    if (fieldType === "number" && finalOptions.numberFormat === "fixed_digits" && !finalOptions.digitCount) {
      setError("تعداد رقم را مشخص کنید");
      return;
    }

    startTransition(async () => {
      const result = await addField(orgId, formTemplateId, {
        label,
        fieldType,
        isRequired,
        options: finalOptions,
      });
      if (result.error) {
        setError(result.error);
        return;
      }
      reset();
      setOpen(false);
    });
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) reset();
        setOpen(next);
      }}
    >
      <DialogTrigger asChild>
        <Button>+ فیلد جدید</Button>
      </DialogTrigger>
      <DialogContent className="max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>افزودن فیلد</DialogTitle>
          <DialogDescription>
            این فیلد در فرم ثبت تیکت نمایش داده می‌شود.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="field-label">برچسب فیلد</Label>
            <Input
              id="field-label"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="مثلاً توضیحات"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="field-type">نوع فیلد</Label>
            <Select
              value={fieldType}
              onValueChange={(v) => {
                setFieldType(v as FieldType);
                setOptions(emptyOptions());
                setChoicesText("");
                setExtensionsText("");
              }}
            >
              <SelectTrigger id="field-type" className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {FIELD_TYPES.map((t) => (
                  <SelectItem key={t} value={t}>
                    {FIELD_TYPE_LABELS[t]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* --- per-type conditional options --- */}

          {(fieldType === "text" || fieldType === "textarea") && (
            <div className="grid gap-2">
              <Label htmlFor="field-placeholder">متن راهنما (اختیاری)</Label>
              <Input
                id="field-placeholder"
                value={options.placeholder ?? ""}
                onChange={(e) => patchOptions({ placeholder: e.target.value })}
              />
            </div>
          )}

          {fieldType === "text" && (
            <div className="grid gap-2">
              <Label>فرمت متن</Label>
              <Select
                value={options.textFormat ?? "free"}
                onValueChange={(v) => patchOptions({ textFormat: v as TextFormat })}
              >
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(TEXT_FORMAT_LABELS).map(([v, l]) => (
                    <SelectItem key={v} value={v}>
                      {l}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          {(fieldType === "text" || fieldType === "textarea") && (
            <div className="grid grid-cols-2 gap-4">
              <div className="grid gap-2">
                <Label htmlFor="field-minlen">حداقل طول (اختیاری)</Label>
                <Input
                  id="field-minlen"
                  type="number"
                  dir="ltr"
                  value={options.minLength ?? ""}
                  onChange={(e) =>
                    patchOptions({ minLength: e.target.value ? Number(e.target.value) : undefined })
                  }
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="field-maxlen">حداکثر طول (اختیاری)</Label>
                <Input
                  id="field-maxlen"
                  type="number"
                  dir="ltr"
                  value={options.maxLength ?? ""}
                  onChange={(e) =>
                    patchOptions({ maxLength: e.target.value ? Number(e.target.value) : undefined })
                  }
                />
              </div>
            </div>
          )}

          {fieldType === "number" && (
            <>
              <div className="grid gap-2">
                <Label>فرمت عدد</Label>
                <Select
                  value={options.numberFormat ?? "free"}
                  onValueChange={(v) => patchOptions({ numberFormat: v as NumberFormat })}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {Object.entries(NUMBER_FORMAT_LABELS).map(([v, l]) => (
                      <SelectItem key={v} value={v}>
                        {l}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              {options.numberFormat === "fixed_digits" && (
                <div className="grid gap-2">
                  <Label htmlFor="field-digits">چند رقم؟</Label>
                  <Input
                    id="field-digits"
                    type="number"
                    dir="ltr"
                    value={options.digitCount ?? ""}
                    onChange={(e) =>
                      patchOptions({ digitCount: e.target.value ? Number(e.target.value) : undefined })
                    }
                  />
                </div>
              )}
              {(options.numberFormat ?? "free") !== "mobile" &&
                (options.numberFormat ?? "free") !== "fixed_digits" && (
                  <div className="grid grid-cols-2 gap-4">
                    <div className="grid gap-2">
                      <Label htmlFor="field-min">حداقل مقدار (اختیاری)</Label>
                      <Input
                        id="field-min"
                        type="number"
                        dir="ltr"
                        value={options.min ?? ""}
                        onChange={(e) =>
                          patchOptions({ min: e.target.value ? Number(e.target.value) : undefined })
                        }
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label htmlFor="field-max">حداکثر مقدار (اختیاری)</Label>
                      <Input
                        id="field-max"
                        type="number"
                        dir="ltr"
                        value={options.max ?? ""}
                        onChange={(e) =>
                          patchOptions({ max: e.target.value ? Number(e.target.value) : undefined })
                        }
                      />
                    </div>
                  </div>
                )}
            </>
          )}

          {fieldType === "date_jalali" && (
            <div className="grid gap-2">
              <Label>محدودیت تاریخ</Label>
              <Select
                value={options.dateConstraint ?? "none"}
                onValueChange={(v) => patchOptions({ dateConstraint: v as DateConstraint })}
              >
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(DATE_CONSTRAINT_LABELS).map(([v, l]) => (
                    <SelectItem key={v} value={v}>
                      {l}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          {fieldType === "select" && (
            <>
              <div className="grid gap-2">
                <Label htmlFor="field-options">گزینه‌ها (هر خط یک گزینه)</Label>
                <Textarea
                  id="field-options"
                  value={choicesText}
                  onChange={(e) => setChoicesText(e.target.value)}
                  placeholder={"گزینه یک\nگزینه دو"}
                  rows={4}
                />
              </div>
              <div className="grid gap-2">
                <Label>حالت انتخاب</Label>
                <Select
                  value={options.selectionMode ?? "single"}
                  onValueChange={(v) => patchOptions({ selectionMode: v as SelectionMode })}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="single">تک‌گزینه‌ای</SelectItem>
                    <SelectItem value="multiple">چندگزینه‌ای</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </>
          )}

          {fieldType === "file" && (
            <>
              <div className="grid gap-2">
                <Label htmlFor="field-extensions">پسوندهای مجاز (اختیاری، با کاما جدا کنید)</Label>
                <Input
                  id="field-extensions"
                  dir="ltr"
                  value={extensionsText}
                  onChange={(e) => setExtensionsText(e.target.value)}
                  placeholder="pdf, jpg, png"
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="field-maxsize">حداکثر حجم به مگابایت (اختیاری)</Label>
                <Input
                  id="field-maxsize"
                  type="number"
                  dir="ltr"
                  value={options.maxSizeMB ?? ""}
                  onChange={(e) =>
                    patchOptions({ maxSizeMB: e.target.value ? Number(e.target.value) : undefined })
                  }
                />
              </div>
            </>
          )}

          {REPEATABLE_ELIGIBLE.includes(fieldType) && (
            <div className="flex items-center gap-2">
              <Checkbox
                id="field-repeatable"
                checked={options.repeatable ?? false}
                onCheckedChange={(c) => patchOptions({ repeatable: c === true })}
              />
              <Label htmlFor="field-repeatable" className="font-normal">
                این فیلد تکرارپذیر باشد (امکان افزودن چند مورد)
              </Label>
            </div>
          )}

          <div className="flex items-center gap-2">
            <Checkbox
              id="field-required"
              checked={isRequired}
              onCheckedChange={(c) => setIsRequired(c === true)}
            />
            <Label htmlFor="field-required" className="font-normal">
              اجباری باشد
            </Label>
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button onClick={onSubmit} disabled={isPending || !label.trim()}>
            افزودن
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
