"use client";

import { useState, useTransition } from "react";
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
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="flex flex-col items-start gap-1">
      <Button
        variant="ghost"
        size="sm"
        disabled={isPending}
        onClick={() => {
          if (!confirm("این شیفت حذف شود؟")) return;
          setError(null);
          startTransition(async () => {
            const result = await removeShiftAssignment(orgId, assignmentId);
            if (result.error) setError(result.error);
          });
        }}
      >
        حذف
      </Button>
      {error && <p role="alert" className="text-destructive text-xs">{error}</p>}
    </div>
  );
}
