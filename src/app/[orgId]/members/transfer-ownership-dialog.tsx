"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { transferOwnership } from "./actions";
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
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

export function TransferOwnershipDialog({
  orgId,
  successors,
  replacementRoles,
}: {
  orgId: string;
  successors: { id: string; label: string }[];
  replacementRoles: { id: string; name: string }[];
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [successorId, setSuccessorId] = useState("");
  const [replacementRoleId, setReplacementRoleId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function submit() {
    setError(null);
    startTransition(async () => {
      const result = await transferOwnership(orgId, successorId, replacementRoleId);
      if (result.error) {
        setError(result.error);
        return;
      }
      setOpen(false);
      router.push(`/${orgId}/dashboard`);
      router.refresh();
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline">انتقال مالکیت</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>انتقال مالکیت سازمان</DialogTitle>
          <DialogDescription>
            عضو انتخاب‌شده مالک می‌شود و نقش شما هم‌زمان به نقش غیرمالکِ انتخاب‌شده تغییر می‌کند.
            پس از انتقال، فقط مالک جدید می‌تواند نقش‌ها را مدیریت کند.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label>مالک جدید</Label>
            <Select value={successorId} onValueChange={setSuccessorId}>
              <SelectTrigger className="w-full"><SelectValue placeholder="عضو را انتخاب کنید" /></SelectTrigger>
              <SelectContent>
                {successors.map((member) => (
                  <SelectItem key={member.id} value={member.id}>{member.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid gap-2">
            <Label>نقش شما پس از انتقال</Label>
            <Select value={replacementRoleId} onValueChange={setReplacementRoleId}>
              <SelectTrigger className="w-full"><SelectValue placeholder="نقش غیرمالک را انتخاب کنید" /></SelectTrigger>
              <SelectContent>
                {replacementRoles.map((role) => (
                  <SelectItem key={role.id} value={role.id}>{role.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button
            onClick={submit}
            disabled={pending || !successorId || !replacementRoleId}
          >
            تأیید انتقال
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
