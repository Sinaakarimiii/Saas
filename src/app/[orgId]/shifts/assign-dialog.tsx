"use client";

import { useState, useTransition } from "react";
import { createShiftAssignment } from "./actions";
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

const NO_TEMPLATE = "__none__";

type Member = { id: string; label: string };
type Template = { id: string; name: string; start_time: string; end_time: string; color_hex: string };

export function AssignShiftDialog({
  orgId,
  members,
  templates,
  defaultDate,
  holidays,
}: {
  orgId: string;
  members: Member[];
  templates: Template[];
  defaultDate?: string;
  holidays: string[];
}) {
  const [open, setOpen] = useState(false);
  const [memberId, setMemberId] = useState(members[0]?.id ?? "");
  const [templateId, setTemplateId] = useState(NO_TEMPLATE);
  const [title, setTitle] = useState("");
  const [workDate, setWorkDate] = useState(defaultDate ?? "");
  const [startTime, setStartTime] = useState("08:00");
  const [endTime, setEndTime] = useState("16:00");
  const [note, setNote] = useState("");
  const [colorHex, setColorHex] = useState("#2563EB");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  // Same reasoning as request-dialog.tsx: useState's default only runs on
  // mount, so a dialog that mounted before `members` was populated (or
  // before the org had any members yet) would otherwise keep an empty
  // selection forever. Re-pick a valid default each time it's opened.
  function handleOpenChange(next: boolean) {
    if (next && (!memberId || !members.some((m) => m.id === memberId))) {
      setMemberId(members[0]?.id ?? "");
    }
    setOpen(next);
  }

  function onTemplateChange(value: string) {
    setTemplateId(value);
    if (value === NO_TEMPLATE) return;
    const tpl = templates.find((t) => t.id === value);
    if (tpl) {
      setTitle(tpl.name);
      setStartTime(tpl.start_time.slice(0, 5));
      setEndTime(tpl.end_time.slice(0, 5));
      setColorHex(tpl.color_hex);
    }
  }

  function onSubmit() {
    setError(null);
    if (!memberId) {
      setError("یک عضو انتخاب کنید");
      return;
    }
    if (!workDate) {
      setError("تاریخ را وارد کنید");
      return;
    }
    startTransition(async () => {
      const result = await createShiftAssignment(orgId, {
        memberId,
        shiftTemplateId: templateId === NO_TEMPLATE ? null : templateId,
        title: title || "شیفت",
        workDate,
        startTime,
        endTime,
        note,
        colorHex,
      });
      if (result.error) {
        setError(result.error);
        return;
      }
      setTitle("");
      setNote("");
      setTemplateId(NO_TEMPLATE);
      setOpen(false);
    });
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button>+ برنامه‌ریزی شیفت</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>برنامه‌ریزی شیفت</DialogTitle>
          <DialogDescription>
            یا یک قالب انتخاب کنید، یا مستقیم ساعت شروع/پایان دلخواه وارد کنید.
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
            <Label htmlFor="shift-color">رنگ نمایش</Label>
            <Input id="shift-color" type="color" value={colorHex} onChange={(e) => setColorHex(e.target.value)} />
          </div>

          <div className="grid gap-2">
            <Label>قالب شیفت (اختیاری)</Label>
            <Select value={templateId} onValueChange={onTemplateChange}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NO_TEMPLATE}>بدون قالب / سفارشی</SelectItem>
                {templates.map((t) => (
                  <SelectItem key={t.id} value={t.id}>
                    {t.name} ({t.start_time.slice(0, 5)}–{t.end_time.slice(0, 5)})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="grid gap-2">
            <Label htmlFor="shift-title">عنوان</Label>
            <Input
              id="shift-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="مثلاً شیفت صبح"
            />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="shift-date">تاریخ</Label>
            <JalaliDateField
              id="shift-date"
              value={workDate}
              onChange={setWorkDate}
              holidays={holidays}
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="grid gap-2">
              <Label htmlFor="shift-start">ساعت شروع</Label>
              <Input
                id="shift-start"
                type="time"
                dir="ltr"
                value={startTime}
                onChange={(e) => setStartTime(e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="shift-end">ساعت پایان</Label>
              <Input
                id="shift-end"
                type="time"
                dir="ltr"
                value={endTime}
                onChange={(e) => setEndTime(e.target.value)}
              />
            </div>
          </div>

          <div className="grid gap-2">
            <Label htmlFor="shift-note">توضیح (اختیاری)</Label>
            <Textarea
              id="shift-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
            />
          </div>

          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button onClick={onSubmit} disabled={isPending}>
            ثبت شیفت
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
