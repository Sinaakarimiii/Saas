"use client";

import { useState, useTransition } from "react";
import { updateMember } from "./actions";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
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
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

const NO_MANAGER = "__none__";

export function EditMemberDialog({
  orgId,
  memberId,
  currentRoleId,
  currentManagerId,
  currentWorkMode,
  roles,
  members,
  canChangeRole,
}: {
  orgId: string;
  memberId: string;
  currentRoleId: string;
  currentManagerId: string | null;
  currentWorkMode: "unspecified" | "shift" | "fixed";
  roles: { id: string; name: string }[];
  members: { id: string; label: string }[];
  canChangeRole: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [roleId, setRoleId] = useState(currentRoleId);
  const [managerId, setManagerId] = useState(currentManagerId ?? NO_MANAGER);
  const [workMode, setWorkMode] = useState(currentWorkMode);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const otherMembers = members.filter((m) => m.id !== memberId);

  function onSubmit() {
    setError(null);
    startTransition(async () => {
      const result = await updateMember(orgId, memberId, {
        roleId,
        managerId: managerId === NO_MANAGER ? null : managerId,
        workMode,
      });
      if (result.error) {
        setError(result.error);
        return;
      }
      setOpen(false);
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
          <DialogTitle>ویرایش عضو</DialogTitle>
        </DialogHeader>
        <div className="grid gap-4">
          {canChangeRole && <div className="grid gap-2">
            <Label>نقش</Label>
            <Select value={roleId} onValueChange={setRoleId}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {roles.map((r) => (
                  <SelectItem key={r.id} value={r.id}>
                    {r.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>}
          <div className="grid gap-2">
            <Label>سرپرست مستقیم</Label>
            <Select value={managerId} onValueChange={setManagerId}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NO_MANAGER}>بدون سرپرست</SelectItem>
                {otherMembers.map((m) => (
                  <SelectItem key={m.id} value={m.id}>
                    {m.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid gap-2">
            <Label>نوع برنامهٔ کاری</Label>
            <Select value={workMode} onValueChange={(value) => setWorkMode(value as typeof workMode)}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="unspecified">تعیین نشده</SelectItem>
                <SelectItem value="shift">شیفتی</SelectItem>
                <SelectItem value="fixed">ساعات ثابت</SelectItem>
              </SelectContent>
            </Select>
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
