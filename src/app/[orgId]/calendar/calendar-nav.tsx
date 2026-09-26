"use client";

import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { ChevronRight, ChevronLeft } from "lucide-react";
import {
  JALALI_MONTH_NAMES,
  addJalaliDays,
  addJalaliMonths,
  addJalaliWeeks,
  addJalaliYears,
  jalaliToGregorianISODate,
  todayJalali,
  toPersianDigits,
  type JalaliYMD,
} from "@/lib/jalali";
import type { CalendarView } from "./types";

const selectClass =
  "h-8 rounded-(--glass-radius) bg-(--glass) px-2 text-sm text-(--text) [border:var(--glass-hairline)]";

export function CalendarNav({
  orgId,
  view,
  anchor,
}: {
  orgId: string;
  view: CalendarView;
  anchor: JalaliYMD;
}) {
  const router = useRouter();
  const today = todayJalali();

  function goTo(target: JalaliYMD) {
    router.push(`/${orgId}/calendar?view=${view}&date=${jalaliToGregorianISODate(target)}`);
  }

  function step(amount: number) {
    switch (view) {
      case "day":
        return goTo(addJalaliDays(anchor, amount));
      case "week":
        return goTo(addJalaliWeeks(anchor, amount));
      case "year":
        return goTo(addJalaliYears(anchor, amount));
      case "month":
      default: {
        const next = addJalaliMonths(anchor, amount);
        return goTo({ year: next.year, month: next.month, day: 1 });
      }
    }
  }

  const rangeStart = Math.min(anchor.year, today.year) - 5;
  const rangeEnd = Math.max(anchor.year, today.year) + 5;
  const years = Array.from({ length: rangeEnd - rangeStart + 1 }, (_, i) => rangeStart + i);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Button type="button" variant="secondary" size="icon-sm" aria-label="قبلی" onClick={() => step(-1)}>
        <ChevronRight className="size-4" />
      </Button>
      <Button type="button" variant="outline" size="sm" onClick={() => goTo(today)}>
        امروز
      </Button>
      <Button type="button" variant="secondary" size="icon-sm" aria-label="بعدی" onClick={() => step(1)}>
        <ChevronLeft className="size-4" />
      </Button>

      {view === "month" && (
        <>
          <select
            aria-label="ماه"
            className={selectClass}
            value={anchor.month}
            onChange={(e) => goTo({ year: anchor.year, month: Number(e.target.value), day: 1 })}
          >
            {JALALI_MONTH_NAMES.map((name, i) => (
              <option key={name} value={i + 1}>
                {name}
              </option>
            ))}
          </select>
          <select
            aria-label="سال"
            className={selectClass}
            value={anchor.year}
            onChange={(e) => goTo({ year: Number(e.target.value), month: anchor.month, day: 1 })}
          >
            {years.map((y) => (
              <option key={y} value={y}>
                {toPersianDigits(y)}
              </option>
            ))}
          </select>
        </>
      )}

      {view === "year" && (
        <select
          aria-label="سال"
          className={selectClass}
          value={anchor.year}
          onChange={(e) => goTo({ year: Number(e.target.value), month: 1, day: 1 })}
        >
          {years.map((y) => (
            <option key={y} value={y}>
              {toPersianDigits(y)}
            </option>
          ))}
        </select>
      )}
    </div>
  );
}
