"use client";

import { useActionState, useState } from "react";
import { createFormTemplate } from "./actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

const initialState = { error: undefined as string | undefined };

export function NewFormDialog({ orgId }: { orgId: string }) {
  const [open, setOpen] = useState(false);
  const [state, formAction, isPending] = useActionState(
    async (_prev: typeof initialState, formData: FormData) => {
      const result = await createFormTemplate(orgId, formData);
      return result ?? initialState;
    },
    initialState,
  );

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>+ فرم جدید</Button>
      </DialogTrigger>
      <DialogContent>
        <form action={formAction} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>ساخت فرم جدید</DialogTitle>
          </DialogHeader>
          <div className="grid gap-2">
            <Label htmlFor="form-name">نام فرم</Label>
            <Input
              id="form-name"
              name="name"
              placeholder="مثلاً فرم تیکت پشتیبانی"
              required
            />
          </div>
          {state.error && (
            <p className="text-destructive text-sm">{state.error}</p>
          )}
          <DialogFooter>
            <Button type="submit" disabled={isPending}>
              ساخت و افزودن فیلد
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
