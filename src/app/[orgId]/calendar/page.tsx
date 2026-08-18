import Link from "next/link";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import {
  JALALI_MONTH_NAMES,
  JALALI_WEEKDAY_NAMES,
  addJalaliMonths,
  daysInJalaliMonth,
  firstWeekdayOfJalaliMonth,
  formatGregorianShort,
  jalaliToGregorianISODate,
  todayJalali,
  toPersianDigits,
} from "@/lib/jalali";
import {
  fetchDayStatusOverrides,
  fetchHolidayDates,
  resolveDayStatus,
} from "@/lib/holidays";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { DayCell } from "./day-cell";

export default async function CalendarPage({
  params,
  searchParams,
}: PageProps<"/[orgId]/calendar">) {
  const { orgId } = await params;
  const sp = await searchParams;
  const ctx = await getOrgContext(orgId);
  const supabase = await createClient();
  const canManageDays = ctx.can(PERMISSIONS.CALENDAR_MANAGE_DAYS);

  const today = todayJalali();
  const todayIso = jalaliToGregorianISODate(today);
  const year = Number(sp.y) || today.year;
  const month = Number(sp.m) || today.month;

  const dayCount = daysInJalaliMonth(year, month);
  const firstDayIso = jalaliToGregorianISODate({ year, month, day: 1 });
  const lastDayIso = jalaliToGregorianISODate({ year, month, day: dayCount });

  const [{ data: events }, { data: leaves }, holidayDates, dayStatusOverrides] =
    await Promise.all([
      supabase
        .from("calendar_events")
        .select("jalali_day, title, is_holiday")
        .eq("jalali_year", year)
        .eq("jalali_month", month)
        .order("jalali_day", { ascending: true }),
      supabase.rpc("team_leave_calendar", {
        p_org_id: orgId,
        p_from: firstDayIso,
        p_to: lastDayIso,
      }),
      fetchHolidayDates(supabase),
      fetchDayStatusOverrides(supabase, orgId, { from: firstDayIso, to: lastDayIso }),
    ]);
  const holidaySet = new Set(holidayDates);

  const eventsByDay = new Map<number, { title: string; is_holiday: boolean }[]>();
  for (const e of events ?? []) {
    const list = eventsByDay.get(e.jalali_day) ?? [];
    list.push({ title: e.title, is_holiday: e.is_holiday });
    eventsByDay.set(e.jalali_day, list);
  }

  // Each leave can span multiple days -- mark every day of the month it
  // overlaps, not just its start. dayIso is a *local* calendar date, so its
  // start/end must be parsed as local time (no "Z") before comparing against
  // starts_at/ends_at -- otherwise the window silently shifts by the
  // server's UTC offset for a few hours around local midnight.
  const leaveDays = new Set<number>();
  for (const l of leaves ?? []) {
    for (let d = 1; d <= dayCount; d++) {
      const dayIso = jalaliToGregorianISODate({ year, month, day: d });
      const dayStartMs = new Date(`${dayIso}T00:00:00`).getTime();
      const dayEndMs = new Date(`${dayIso}T23:59:59`).getTime();
      if (new Date(l.starts_at!).getTime() <= dayEndMs && new Date(l.ends_at!).getTime() >= dayStartMs) {
        leaveDays.add(d);
      }
    }
  }

  const prev = addJalaliMonths({ year, month }, -1);
  const next = addJalaliMonths({ year, month }, 1);
  const leadingBlanks = firstWeekdayOfJalaliMonth(year, month);

  const cells: { day: number | null }[] = [
    ...Array.from({ length: leadingBlanks }, () => ({ day: null })),
    ...Array.from({ length: dayCount }, (_, i) => ({ day: i + 1 })),
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-(--text)">
            تقویم {JALALI_MONTH_NAMES[month - 1]} {year}
          </h1>
          <p className="text-xs text-(--text-muted)">
            امروز: {toPersianDigits(today.day)} {JALALI_MONTH_NAMES[today.month - 1]}{" "}
            {toPersianDigits(today.year)}{" "}
            <span dir="ltr" className="inline-block">
              ({formatGregorianShort(todayIso)} {todayIso.slice(0, 4)})
            </span>
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button asChild variant="outline" size="sm">
            <Link href={`/${orgId}/calendar?y=${prev.year}&m=${prev.month}`}>
              ماه قبل
            </Link>
          </Button>
          <Button asChild variant="outline" size="sm">
            <Link href={`/${orgId}/calendar?y=${today.year}&m=${today.month}`}>
              امروز
            </Link>
          </Button>
          <Button asChild variant="outline" size="sm">
            <Link href={`/${orgId}/calendar?y=${next.year}&m=${next.month}`}>
              ماه بعد
            </Link>
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-7 gap-2 text-center text-sm font-medium">
        {JALALI_WEEKDAY_NAMES.map((w, i) => (
          <div
            key={w}
            className={cn("py-1", i === 6 ? "text-(--error)" : "text-(--text-muted)")}
          >
            {w}
          </div>
        ))}
        {cells.map((cell, i) => {
          if (cell.day === null) {
            return <div key={`blank-${i}`} />;
          }
          const dayEvents = eventsByDay.get(cell.day) ?? [];
          const weekdayIndex = (leadingBlanks + cell.day - 1) % 7;
          const isFriday = weekdayIndex === 6;
          const hasLeave = leaveDays.has(cell.day);
          const isToday =
            year === today.year && month === today.month && cell.day === today.day;
          const iso = jalaliToGregorianISODate({ year, month, day: cell.day });
          const override = dayStatusOverrides.get(iso);
          const status = resolveDayStatus(iso, isFriday, holidaySet, dayStatusOverrides);

          return (
            <DayCell
              key={cell.day}
              orgId={orgId}
              iso={iso}
              jalaliDay={cell.day}
              jalaliLabel={`${toPersianDigits(cell.day)} ${JALALI_MONTH_NAMES[month - 1]} ${toPersianDigits(year)}`}
              status={status}
              isOverridden={!!override}
              overrideNote={override?.note ?? null}
              occasions={dayEvents}
              hasLeave={hasLeave}
              isToday={isToday}
              canManageDays={canManageDays}
            />
          );
        })}
      </div>
    </div>
  );
}
