"use client";

import { useTransition } from "react";
import { voidAttendanceLog } from "./actions";
import { Button } from "@/components/ui/button";

export function VoidLogButton({ orgId, logId }: { orgId: string; logId: string }) {
  const [isPending, startTransition] = useTransition();

  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={isPending}
      onClick={() => {
        if (!confirm("این ثبت باطل شود؟ (حذف نمی‌شود، فقط باطل علامت می‌خورد)")) return;
        startTransition(async () => {
          await voidAttendanceLog(orgId, logId);
        });
      }}
    >
      باطل کردن
    </Button>
  );
}
