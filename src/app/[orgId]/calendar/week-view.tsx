import { createClient } from "@/lib/supabase/server";
import {
  JALALI_MONTH_NAMES,
  JALALI_WEEKDAY_NAMES,
  addJalaliDays,
  gregorianISODateToJalali,
  jalaliToGregorianISODate,
  startOfJalaliWeek,
  todayJalali,
  toPersianDigits,
  weekdayIndexOfISODate,
  type JalaliYMD,
} from "@/lib/jalali";
import {
  fetchDayStatusOverrides,
  fetchHolidayDates,
  resolveDayStatus,
} from "@/lib/holidays";
import { DayCell } from "./day-cell";
import { tehranDayBounds } from "@/lib/tehran-time";
import { previousISODate, shiftSegmentForDay } from "@/lib/shift-day";

export async function WeekView({
  orgId,
  anchor,
  canManageDays,
}: {
  orgId: string;
  anchor: JalaliYMD;
  canManageDays: boolean;
}) {
  const supabase = await createClient();
  const today = todayJalali();
  const weekStart = startOfJalaliWeek(anchor);
  const days = Array.from({ length: 7 }, (_, i) => addJalaliDays(weekStart, i));
  const firstIso = jalaliToGregorianISODate(days[0]);
  const lastIso = jalaliToGregorianISODate(days[6]);

  const [{ data: events }, { data: leaves }, { data: shifts }, holidayDates, dayStatusOverrides] =
    await Promise.all([
      supabase
        .from("calendar_events")
        .select("gregorian_date, title, is_holiday")
        .gte("gregorian_date", firstIso)
        .lte("gregorian_date", lastIso),
      supabase.rpc("team_leave_calendar", { p_org_id: orgId, p_from: firstIso, p_to: lastIso }),
      supabase.from("shift_assignments")
        .select("work_date, start_time, end_time")
        .eq("org_id", orgId)
        .gte("work_date", previousISODate(firstIso))
        .lte("work_date", lastIso)
        .is("deleted_at", null),
      fetchHolidayDates(supabase),
      fetchDayStatusOverrides(supabase, orgId, { from: firstIso, to: lastIso }),
    ]);
  const holidaySet = new Set(holidayDates);

  const eventsByIso = new Map<string, { title: string; is_holiday: boolean }[]>();
  for (const e of events ?? []) {
    const list = eventsByIso.get(e.gregorian_date) ?? [];
    list.push({ title: e.title, is_holiday: e.is_holiday });
    eventsByIso.set(e.gregorian_date, list);
  }

  const leaveDays = new Set<string>();
  for (const l of leaves ?? []) {
    for (const day of days) {
      const dayIso = jalaliToGregorianISODate(day);
      const { start, end } = tehranDayBounds(dayIso);
      if (Date.parse(l.starts_at!) < Date.parse(end) && Date.parse(l.ends_at!) > Date.parse(start)) {
        leaveDays.add(dayIso);
      }
    }
  }
  const shiftDays = new Set(days.map((day) => jalaliToGregorianISODate(day)).filter((iso) =>
    (shifts ?? []).some((shift) => shiftSegmentForDay({
      workDate: shift.work_date, startTime: shift.start_time, endTime: shift.end_time,
    }, iso)),
  ));

  return (
    <div className="grid grid-cols-7 gap-2">
      {days.map((day, i) => {
        const iso = jalaliToGregorianISODate(day);
        const isFriday = weekdayIndexOfISODate(iso) === 6;
        const override = dayStatusOverrides.get(iso);
        const status = resolveDayStatus(iso, isFriday, holidaySet, dayStatusOverrides);
        const isToday = day.year === today.year && day.month === today.month && day.day === today.day;
        const jalaliForLabel = gregorianISODateToJalali(iso);

        return (
          <DayCell
            key={iso}
            orgId={orgId}
            iso={iso}
            jalaliDay={day.day}
            jalaliLabel={`${toPersianDigits(jalaliForLabel.day)} ${JALALI_MONTH_NAMES[jalaliForLabel.month - 1]} ${toPersianDigits(jalaliForLabel.year)}`}
            status={status}
            isOverridden={!!override}
            overrideNote={override?.note ?? null}
            occasions={eventsByIso.get(iso) ?? []}
            hasLeave={leaveDays.has(iso)}
            hasShift={shiftDays.has(iso)}
            isToday={isToday}
            canManageDays={canManageDays}
            size="lg"
            weekdayLabel={JALALI_WEEKDAY_NAMES[i]}
          />
        );
      })}
    </div>
  );
}
