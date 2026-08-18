"use client";

import { useState, useTransition } from "react";
import { inviteMember } from "./actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
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

export function InviteMemberDialog({
  orgId,
  roles,
  members,
}: {
  orgId: string;
  roles: { id: string; name: string }[];
  members: { id: string; label: string }[];
}) {
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | undefined>(undefined);
  const [isPending, startTransition] = useTransition();

  function onSubmit(formData: FormData) {
    setError(undefined);
    startTransition(async () => {
      const result = await inviteMember(orgId, formData);
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
        <Button>+ دعوت عضو</Button>
      </DialogTrigger>
      <DialogContent>
        <form action={onSubmit} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>دعوت عضو جدید</DialogTitle>
            <DialogDescription>
              یک ایمیل دعوت برای این فرد ارسال می‌شود. اگر قبلاً حساب کاربری
              داشته باشد، مستقیم به این سازمان اضافه می‌شود.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-2">
            <Label htmlFor="email">ایمیل</Label>
            <Input
              id="email"
              name="email"
              type="email"
              dir="ltr"
              placeholder="person@example.com"
              required
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="roleId">نقش</Label>
            <Select name="roleId" required>
              <SelectTrigger id="roleId" className="w-full">
                <SelectValue placeholder="یک نقش انتخاب کنید" />
              </SelectTrigger>
              <SelectContent>
                {roles.map((role) => (
                  <SelectItem key={role.id} value={role.id}>
                    {role.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="managerId">سرپرست مستقیم (اختیاری)</Label>
            <Select name="managerId">
              <SelectTrigger id="managerId" className="w-full">
                <SelectValue placeholder="بدون سرپرست" />
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
          {error && <p className="text-destructive text-sm">{error}</p>}
          <DialogFooter>
            <Button type="submit" disabled={isPending}>
              ارسال دعوت
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
