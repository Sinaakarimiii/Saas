"use client";

import { useState, useTransition } from "react";
import { createLeaveForMember } from "./actions";
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
type Member = { id: string; label: string };

export function CreateLeaveForMemberDialog({
  orgId,
  leaveTypes,
  members,
  holidays,
}: {
  orgId: string;
  leaveTypes: LeaveType[];
  members: Member[];
  holidays: string[];
}) {
  const [open, setOpen] = useState(false);
  const [memberId, setMemberId] = useState(members[0]?.id ?? "");
  const [leaveTypeId, setLeaveTypeId] = useState(leaveTypes[0]?.id ?? "");
  const [startDate, setStartDate] = useState("");
  const [startTime, setStartTime] = useState("09:00");
  const [endDate, setEndDate] = useState("");
  const [endTime, setEndTime] = useState("18:00");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function handleOpenChange(next: boolean) {
    if (next) {
      if (!memberId || !members.some((m) => m.id === memberId)) {
        setMemberId(members[0]?.id ?? "");
      }
      if (!leaveTypeId || !leaveTypes.some((lt) => lt.id === leaveTypeId)) {
        setLeaveTypeId(leaveTypes[0]?.id ?? "");
      }
    }
    setOpen(next);
  }

  function onSubmit() {
    setError(null);
    if (!memberId) {
      setError("عضو را انتخاب کنید");
      return;
    }
    if (!leaveTypeId) {
      setError("نوع مرخصی را انتخاب کنید");
      return;
    }
    if (!startDate || !endDate) {
      setError("بازه‌ی زمانی مرخصی را وارد کنید");
      return;
    }
    startTransition(async () => {
      const result = await createLeaveForMember(orgId, {
        memberId,
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
        <Button variant="outline">+ ثبت مرخصی برای عضو</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>ثبت مرخصی برای عضو</DialogTitle>
          <DialogDescription>
            این مرخصی مستقیماً به‌عنوان تاییدشده ثبت می‌شود؛ فقط برای اعضای
            زیرمجموعه‌ی سرپرستی شما (یا کل سازمان، اگر دسترسی «همه» دارید)
            امکان‌پذیر است.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label>عضو</Label>
            <Select value={memberId} onValueChange={setMemberId}>
              <SelectTrigger className="w-full">
                <SelectValue placeholder="یک عضو انتخاب کنید" />
              </SelectTrigger>
              <SelectContent>
                {members.map((m) => (
                  <SelectItem key={m.id} value={m.id}>
                    {m.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
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
              <Label htmlFor="assign-leave-start-date">تاریخ شروع</Label>
              <JalaliDateField
                id="assign-leave-start-date"
                value={startDate}
                onChange={setStartDate}
                holidays={holidays}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="assign-leave-start-time">ساعت شروع</Label>
              <Input
                id="assign-leave-start-time"
                type="time"
                dir="ltr"
                value={startTime}
                onChange={(e) => setStartTime(e.target.value)}
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <Label htmlFor="assign-leave-end-date">تاریخ پایان</Label>
              <JalaliDateField
                id="assign-leave-end-date"
                value={endDate}
                onChange={setEndDate}
                holidays={holidays}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="assign-leave-end-time">ساعت پایان</Label>
              <Input
                id="assign-leave-end-time"
                type="time"
                dir="ltr"
                value={endTime}
                onChange={(e) => setEndTime(e.target.value)}
              />
            </div>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="assign-leave-note">توضیح (اختیاری)</Label>
            <Textarea
              id="assign-leave-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
            />
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button onClick={onSubmit} disabled={isPending}>
            ثبت مرخصی تاییدشده
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
