"use client";

import { useState, useTransition } from "react";
import { addField } from "../actions";
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

const FIELD_TYPE_LABELS: Record<string, string> = {
  text: "متن",
  number: "عدد",
  date_jalali: "تاریخ شمسی",
  select: "انتخابی",
  file: "آپلود فایل",
};

export function AddFieldDialog({
  orgId,
  formTemplateId,
}: {
  orgId: string;
  formTemplateId: string;
}) {
  const [open, setOpen] = useState(false);
  const [label, setLabel] = useState("");
  const [fieldType, setFieldType] = useState("text");
  const [isRequired, setIsRequired] = useState(false);
  const [optionsText, setOptionsText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function onSubmit() {
    setError(null);
    const options = optionsText
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);

    if (fieldType === "select" && options.length === 0) {
      setError("حداقل یک گزینه برای فیلد انتخابی وارد کنید");
      return;
    }

    startTransition(async () => {
      const result = await addField(orgId, formTemplateId, {
        label,
        fieldType: fieldType as "text" | "number" | "date_jalali" | "select" | "file",
        isRequired,
        options,
      });
      if (result.error) {
        setError(result.error);
        return;
      }
      setLabel("");
      setFieldType("text");
      setIsRequired(false);
      setOptionsText("");
      setOpen(false);
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>+ فیلد جدید</Button>
      </DialogTrigger>
      <DialogContent>
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
            <Select value={fieldType} onValueChange={setFieldType}>
              <SelectTrigger id="field-type" className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(FIELD_TYPE_LABELS).map(([value, text]) => (
                  <SelectItem key={value} value={value}>
                    {text}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {fieldType === "select" && (
            <div className="grid gap-2">
              <Label htmlFor="field-options">گزینه‌ها (هر خط یک گزینه)</Label>
              <Textarea
                id="field-options"
                value={optionsText}
                onChange={(e) => setOptionsText(e.target.value)}
                placeholder={"گزینه یک\nگزینه دو"}
                rows={4}
              />
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
