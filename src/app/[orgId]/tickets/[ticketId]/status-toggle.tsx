"use client";

import { useState, useTransition } from "react";
import { updateTicketStatusAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

export function StatusToggle({
  orgId,
  ticketId,
  status,
}: {
  orgId: string;
  ticketId: string;
  status: "open" | "closed";
}) {
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const nextStatus = status === "open" ? "closed" : "open";
  const actionLabel = status === "open" ? "بستن تیکت" : "بازکردن دوباره";

  function onSubmit() {
    setError(null);
    startTransition(async () => {
      const result = await updateTicketStatusAction(
        orgId,
        ticketId,
        nextStatus,
        note,
      );
      if (result.error) {
        setError(result.error);
        return;
      }
      setOpen(false);
      setNote("");
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          {actionLabel}
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{actionLabel}</DialogTitle>
        </DialogHeader>
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="status-note">توضیح (اختیاری)</Label>
            <Textarea
              id="status-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
            />
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button onClick={onSubmit} disabled={isPending}>
            تایید
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
