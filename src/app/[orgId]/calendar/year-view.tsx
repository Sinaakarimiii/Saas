import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import {
  JALALI_MONTH_NAMES,
  daysInJalaliMonth,
  firstWeekdayOfJalaliMonth,
  jalaliToGregorianISODate,
  todayJalali,
  toPersianDigits,
} from "@/lib/jalali";
import {
  DAY_STATUS_TEXT_CLASS,
  fetchDayStatusOverrides,
  fetchHolidayDates,
  resolveDayStatus,
} from "@/lib/holidays";
import { cn } from "@/lib/utils";

// Compact, non-interactive overview -- day status by color, occasion
// presence by a small dot. Clicking a month's header jumps to the full
// month view for a closer look (per the approved plan's 12-mini-months
// design, Google Calendar style).
export async function YearView({ orgId, year }: { orgId: string; year: number }) {
  const supabase = await createClient();
  const today = todayJalali();

  const firstIso = jalaliToGregorianISODate({ year, month: 1, day: 1 });
  const lastIso = jalaliToGregorianISODate({ year, month: 12, day: daysInJalaliMonth(year, 12) });

  const [{ data: events }, holidayDates, dayStatusOverrides] = await Promise.all([
    supabase.from("calendar_events").select("jalali_month, jalali_day").eq("jalali_year", year),
    fetchHolidayDates(supabase),
    fetchDayStatusOverrides(supabase, orgId, { from: firstIso, to: lastIso }),
  ]);
  const holidaySet = new Set(holidayDates);
  const occasionDays = new Set((events ?? []).map((e) => `${e.jalali_month}-${e.jalali_day}`));

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {JALALI_MONTH_NAMES.map((name, monthIndex) => {
        const month = monthIndex + 1;
        const dayCount = daysInJalaliMonth(year, month);
        const leadingBlanks = firstWeekdayOfJalaliMonth(year, month);
        const cells: (number | null)[] = [
          ...Array.from({ length: leadingBlanks }, () => null),
          ...Array.from({ length: dayCount }, (_, i) => i + 1),
        ];

        return (
          <div
            key={month}
            className="rounded-(--glass-radius) bg-(--glass) p-3 [border:var(--glass-hairline)]"
          >
            <Link
              href={`/${orgId}/calendar?view=month&date=${jalaliToGregorianISODate({ year, month, day: 1 })}`}
              className="mb-2 block text-center text-sm font-semibold text-(--text) hover:text-(--accent)"
            >
              {name}
            </Link>
            <div className="grid grid-cols-7 gap-y-1 text-center text-[10px] text-(--text-dim)">
              {cells.map((day, i) => {
                if (day === null) return <div key={`b-${i}`} />;
                const weekdayIndex = (leadingBlanks + day - 1) % 7;
                const isFriday = weekdayIndex === 6;
                const iso = jalaliToGregorianISODate({ year, month, day });
                const status = resolveDayStatus(iso, isFriday, holidaySet, dayStatusOverrides);
                const isToday = year === today.year && month === today.month && day === today.day;
                const hasOccasion = occasionDays.has(`${month}-${day}`);

                return (
                  <div key={day} className="relative flex justify-center py-0.5">
                    <span
                      className={cn(
                        "flex size-4.5 items-center justify-center rounded-full",
                        DAY_STATUS_TEXT_CLASS[status],
                        isToday && "bg-(--accent-soft) font-bold",
                      )}
                    >
                      {toPersianDigits(day)}
                    </span>
                    {hasOccasion && (
                      <span className="absolute -bottom-0.5 size-1 rounded-full bg-(--accent)" />
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
