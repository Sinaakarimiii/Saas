"use client";

import { useState, useTransition } from "react";
import { submitLeaveRequest } from "./actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { JalaliDateField } from "@/components/jalali-date-field";
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

type LeaveType = { id: string; name: string; unit: string };

export function NewLeaveRequestDialog({
  orgId,
  leaveTypes,
  holidays,
}: {
  orgId: string;
  leaveTypes: LeaveType[];
  holidays: string[];
}) {
  const [open, setOpen] = useState(false);
  const [leaveTypeId, setLeaveTypeId] = useState(leaveTypes[0]?.id ?? "");
  const [startDate, setStartDate] = useState("");
  const [startTime, setStartTime] = useState("09:00");
  const [endDate, setEndDate] = useState("");
  const [endTime, setEndTime] = useState("18:00");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);

  // leaveTypes only exists as a server-fetched prop; the dialog's own
  // useState default is only evaluated once on mount, so if it mounted
  // before any leave type existed (or a new one was just added), the
  // stale "" default would stick around across re-renders. Re-pick a
  // valid default every time the dialog is (re)opened instead.
  function handleOpenChange(next: boolean) {
    if (next && (!leaveTypeId || !leaveTypes.some((lt) => lt.id === leaveTypeId))) {
      setLeaveTypeId(leaveTypes[0]?.id ?? "");
    }
    setOpen(next);
  }
  const [isPending, startTransition] = useTransition();

  function onSubmit() {
    setError(null);
    if (!leaveTypeId) {
      setError("نوع مرخصی را انتخاب کنید");
      return;
    }
    if (!startDate || !endDate) {
      setError("بازه‌ی زمانی مرخصی را وارد کنید");
      return;
    }
    startTransition(async () => {
      const result = await submitLeaveRequest(orgId, {
        leaveTypeId,
        startsAt: new Date(`${startDate}T${startTime}:00`).toISOString(),
        endsAt: new Date(`${endDate}T${endTime}:00`).toISOString(),
        note,
      });
      if (result.error) {
        setError(result.error);
        return;
      }
      setStartDate("");
      setEndDate("");
      setNote("");
      setOpen(false);
    });
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button>+ درخواست مرخصی</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>درخواست مرخصی جدید</DialogTitle>
          <DialogDescription>
            برای مرخصی یک‌روزه، ساعت شروع و پایان همان روز را وارد کنید؛ برای
            چندروزه، تاریخ پایان را روز دیگری انتخاب کنید.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label>نوع مرخصی</Label>
            <Select value={leaveTypeId} onValueChange={setLeaveTypeId}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="یک نوع انتخاب کنید" />
              </SelectTrigger>
              <SelectContent>
                {leaveTypes.map((lt) => (
                  <SelectItem key={lt.id} value={lt.id}>
                    {lt.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <Label htmlFor="leave-start-date">تاریخ شروع</Label>
              <JalaliDateField
                id="leave-start-date"
                value={startDate}
                onChange={setStartDate}
                holidays={holidays}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="leave-start-time">ساعت شروع</Label>
              <Input
                id="leave-start-time"
                type="time"
                dir="ltr"
                value={startTime}
                onChange={(e) => setStartTime(e.target.value)}
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <Label htmlFor="leave-end-date">تاریخ پایان</Label>
              <JalaliDateField
                id="leave-end-date"
                value={endDate}
                onChange={setEndDate}
                holidays={holidays}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="leave-end-time">ساعت پایان</Label>
              <Input
                id="leave-end-time"
                type="time"
                dir="ltr"
                value={endTime}
                onChange={(e) => setEndTime(e.target.value)}
              />
            </div>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="leave-note">توضیح (اختیاری)</Label>
            <Textarea
              id="leave-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
            />
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button onClick={onSubmit} disabled={isPending}>
            ثبت درخواست
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
