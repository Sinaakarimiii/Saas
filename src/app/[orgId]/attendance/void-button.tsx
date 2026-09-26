"use client";

import { useState, useTransition } from "react";
import { voidAttendanceLog } from "./actions";
import { Button } from "@/components/ui/button";

export function VoidLogButton({ orgId, logId }: { orgId: string; logId: string }) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="flex flex-col items-start gap-1">
      <Button
        variant="ghost"
        size="sm"
        disabled={isPending}
        onClick={() => {
          if (!confirm("این ثبت باطل شود؟ (حذف نمی‌شود، فقط باطل علامت می‌خورد)")) return;
          setError(null);
          startTransition(async () => {
            const result = await voidAttendanceLog(orgId, logId);
            if (result.error) setError(result.error);
          });
        }}
      >
        باطل کردن
      </Button>
      {error && <p role="alert" className="text-destructive text-xs">{error}</p>}
    </div>
  );
}
