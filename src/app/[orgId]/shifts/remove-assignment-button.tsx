"use client";

import { useTransition } from "react";
import { removeShiftAssignment } from "./actions";
import { Button } from "@/components/ui/button";

export function RemoveShiftAssignmentButton({
  orgId,
  assignmentId,
}: {
  orgId: string;
  assignmentId: string;
}) {
  const [isPending, startTransition] = useTransition();

  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={isPending}
      onClick={() => {
        if (!confirm("این شیفت حذف شود؟")) return;
        startTransition(async () => {
          await removeShiftAssignment(orgId, assignmentId);
        });
      }}
    >
      حذف
    </Button>
  );
}
