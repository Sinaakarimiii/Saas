"use client";

import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import type { CalendarView } from "./types";

const VIEW_OPTIONS: { value: CalendarView; label: string }[] = [
  { value: "day", label: "روز" },
  { value: "week", label: "هفته" },
  { value: "month", label: "ماه" },
  { value: "year", label: "سال" },
];

export function ViewSwitcher({
  orgId,
  view,
  dateIso,
}: {
  orgId: string;
  view: CalendarView;
  dateIso: string;
}) {
  const router = useRouter();

  return (
    <div
      role="group"
      aria-label="نمای تقویم"
      className="flex gap-1 rounded-(--glass-radius) bg-(--glass) p-1 [border:var(--glass-hairline)]"
    >
      {VIEW_OPTIONS.map((opt) => (
        <Button
          key={opt.value}
          type="button"
          size="sm"
          variant={view === opt.value ? "default" : "ghost"}
          aria-pressed={view === opt.value}
          onClick={() =>
            router.push(`/${orgId}/calendar?view=${opt.value}&date=${dateIso}`)
          }
        >
          {opt.label}
        </Button>
      ))}
    </div>
  );
}
