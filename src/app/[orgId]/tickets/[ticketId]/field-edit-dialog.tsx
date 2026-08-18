"use client";

import { useState, useTransition } from "react";
import { updateTicketFieldValueAction } from "../actions";
import {
  DynamicFieldInput,
  resolveFieldValueForSubmit,
  type FormFieldDef,
  type FieldValue,
} from "../field-input";
import type { Json } from "@/lib/supabase/types";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

export function FieldEditDialog({
  orgId,
  ticketId,
  field,
  currentValue,
  holidays,
}: {
  orgId: string;
  ticketId: string;
  field: FormFieldDef;
  currentValue: Json;
  holidays: string[];
}) {
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState<FieldValue>(currentValue);
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function onSubmit() {
    setError(null);
    startTransition(async () => {
      try {
        const finalValue = await resolveFieldValueForSubmit(orgId, field, value);
        const result = await updateTicketFieldValueAction(
          orgId,
          ticketId,
          field.id,
          finalValue,
          note,
        );
        if (result.error) {
          setError(result.error);
          return;
        }
        setOpen(false);
        setNote("");
      } catch {
        setError("ذخیره‌ی تغییر انجام نشد");
      }
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="ghost" size="sm">
          ویرایش
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>ویرایش «{field.label}»</DialogTitle>
          <DialogDescription>
            در صورت نیاز می‌توانید توضیح کوتاهی برای این تغییر بنویسید.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <DynamicFieldInput field={field} value={value} onChange={setValue} holidays={holidays} />
          <div className="grid gap-2">
            <Label htmlFor="note">توضیح (اختیاری)</Label>
            <Textarea
              id="note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="چرا این تغییر انجام شد؟"
              rows={2}
            />
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button onClick={onSubmit} disabled={isPending}>
            ذخیره
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
