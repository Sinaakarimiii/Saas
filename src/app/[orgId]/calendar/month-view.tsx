import { createClient } from "@/lib/supabase/server";
import {
  JALALI_MONTH_NAMES,
  JALALI_WEEKDAY_NAMES,
  daysInJalaliMonth,
  firstWeekdayOfJalaliMonth,
  jalaliToGregorianISODate,
  toPersianDigits,
  todayJalali,
  type JalaliYMD,
} from "@/lib/jalali";
import {
  fetchDayStatusOverrides,
  fetchHolidayDates,
  resolveDayStatus,
} from "@/lib/holidays";
import { cn } from "@/lib/utils";
import { tehranDayBounds } from "@/lib/tehran-time";
import { previousISODate, shiftSegmentForDay } from "@/lib/shift-day";
import { DayCell } from "./day-cell";

export async function MonthView({
  orgId,
  anchor,
  canManageDays,
}: {
  orgId: string;
  anchor: Pick<JalaliYMD, "year" | "month">;
  canManageDays: boolean;
}) {
  const supabase = await createClient();
  const { year, month } = anchor;
  const today = todayJalali();

  const dayCount = daysInJalaliMonth(year, month);
  const firstDayIso = jalaliToGregorianISODate({ year, month, day: 1 });
  const lastDayIso = jalaliToGregorianISODate({ year, month, day: dayCount });

  const [{ data: events }, { data: leaves }, { data: shifts }, holidayDates, dayStatusOverrides] =
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
      supabase.from("shift_assignments")
        .select("work_date, start_time, end_time")
        .eq("org_id", orgId)
        .gte("work_date", previousISODate(firstDayIso))
        .lte("work_date", lastDayIso)
        .is("deleted_at", null),
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

  // A leave appears on each Tehran calendar day it overlaps.
  const leaveDays = new Set<number>();
  for (const l of leaves ?? []) {
    for (let d = 1; d <= dayCount; d++) {
      const dayIso = jalaliToGregorianISODate({ year, month, day: d });
      const { start, end } = tehranDayBounds(dayIso);
      if (Date.parse(l.starts_at!) < Date.parse(end) && Date.parse(l.ends_at!) > Date.parse(start)) {
        leaveDays.add(d);
      }
    }
  }
  const shiftDays = new Set<string>();
  for (let day = 1; day <= dayCount; day++) {
    const iso = jalaliToGregorianISODate({ year, month, day });
    if ((shifts ?? []).some((shift) => shiftSegmentForDay({
      workDate: shift.work_date, startTime: shift.start_time, endTime: shift.end_time,
    }, iso))) shiftDays.add(iso);
  }

  const leadingBlanks = firstWeekdayOfJalaliMonth(year, month);
  const cells: { day: number | null }[] = [
    ...Array.from({ length: leadingBlanks }, () => ({ day: null })),
    ...Array.from({ length: dayCount }, (_, i) => ({ day: i + 1 })),
  ];

  return (
    <div className="grid grid-cols-7 gap-2 text-center text-sm font-medium">
      {JALALI_WEEKDAY_NAMES.map((w, i) => (
        <div key={w} className={cn("py-1", i === 6 ? "text-(--error)" : "text-(--text-muted)")}>
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
        const isToday = year === today.year && month === today.month && cell.day === today.day;
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
            hasShift={shiftDays.has(iso)}
            isToday={isToday}
            canManageDays={canManageDays}
          />
        );
      })}
    </div>
  );
}
