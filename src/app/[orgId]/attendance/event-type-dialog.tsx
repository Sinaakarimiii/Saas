"use client";

import { useState, useTransition } from "react";
import { createAttendanceEventType } from "./actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

export function NewAttendanceEventTypeDialog({ orgId }: { orgId: string }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [toggle, setToggle] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function onSubmit() {
    setError(null);
    startTransition(async () => {
      const result = await createAttendanceEventType(orgId, { name, toggle });
      if (result.error) {
        setError(result.error);
        return;
      }
      setName("");
      setOpen(false);
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          + نوع رویداد جدید
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>نوع رویداد حضور جدید</DialogTitle>
          <DialogDescription>
            مثلاً «جلسه» یا «استراحت / ناهار». اگر دوحالته باشد، دکمه‌ی آن بین
            «شروع …» و «پایان …» جابه‌جا می‌شود؛ در غیر این صورت هر کلیک یک
            رویداد یک‌باره ثبت می‌کند.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="et-name">نام</Label>
            <Input
              id="et-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="مثلاً جلسه"
            />
          </div>
          <div className="flex items-center gap-2">
            <Checkbox
              id="et-toggle"
              checked={toggle}
              onCheckedChange={(c) => setToggle(c === true)}
            />
            <Label htmlFor="et-toggle" className="font-normal">
              دوحالته (شروع/پایان) است
            </Label>
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button onClick={onSubmit} disabled={isPending || !name.trim()}>
            ذخیره
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
