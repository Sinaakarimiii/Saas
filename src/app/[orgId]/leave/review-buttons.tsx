"use client";

import { useState, useTransition } from "react";
import { reviewLeaveRequest } from "./actions";
import { Button } from "@/components/ui/button";

export function ReviewButtons({
  orgId,
  requestId,
}: {
  orgId: string;
  requestId: string;
}) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function decide(status: "approved" | "rejected") {
    setError(null);
    const reviewNote =
      status === "rejected" ? prompt("دلیل رد (اختیاری):") ?? "" : "";
    startTransition(async () => {
      const result = await reviewLeaveRequest(orgId, requestId, status, reviewNote);
      if (result.error) setError(result.error);
    });
  }

  return (
    <div className="flex items-center gap-2">
      <Button size="sm" disabled={isPending} onClick={() => decide("approved")}>
        تایید
      </Button>
      <Button
        size="sm"
        variant="outline"
        disabled={isPending}
        onClick={() => decide("rejected")}
      >
        رد
      </Button>
      {error && <span className="text-destructive text-xs">{error}</span>}
    </div>
  );
}
