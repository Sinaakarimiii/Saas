import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import {
  JALALI_MONTH_NAMES,
  gregorianISODateToJalali,
  toPersianDigits,
  weekdayIndexOfISODate,
} from "@/lib/jalali";
import {
  DAY_STATUS_LABEL_FA,
  DAY_STATUS_TEXT_CLASS,
  fetchDayStatusOverrides,
  fetchHolidayDates,
  resolveDayStatus,
} from "@/lib/holidays";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { DayTimeline } from "./day-timeline";
import { DayStatusControl } from "./day-status-control";
import type { getOrgContext } from "@/lib/org-context";
import { previousISODate, shiftSegmentForDay } from "@/lib/shift-day";

export async function DayView({
  orgId,
  date,
  ctx,
}: {
  orgId: string;
  date: string;
  ctx: Awaited<ReturnType<typeof getOrgContext>>;
}) {
  const supabase = await createClient();
  const jalali = gregorianISODateToJalali(date);
  const isFriday = weekdayIndexOfISODate(date) === 6;
  const canManageDays = ctx.can(PERMISSIONS.CALENDAR_MANAGE_DAYS);

  const [{ data: events }, { data: shifts }, { data: leaves }, holidayDates, dayStatusOverrides] =
    await Promise.all([
      supabase.from("calendar_events").select("title, is_holiday").eq("gregorian_date", date),
      supabase
        .from("shift_assignments")
        .select("id, title, work_date, start_time, end_time, color_hex, org_members(profiles(full_name, email))")
        .eq("org_id", orgId)
        .gte("work_date", previousISODate(date))
        .lte("work_date", date)
        .is("deleted_at", null)
        .order("start_time", { ascending: true }),
      // Approved leave only, and only who/what/when -- never the requester's
      // note or the approver's review_note. Visible to every org member,
      // regardless of leave.approve (see 20260818090001_team_leave_calendar).
      supabase.rpc("team_leave_calendar", { p_org_id: orgId, p_from: date, p_to: date }),
      fetchHolidayDates(supabase),
      fetchDayStatusOverrides(supabase, orgId, { from: date, to: date }),
    ]);

  const status = resolveDayStatus(date, isFriday, new Set(holidayDates), dayStatusOverrides);
  const override = dayStatusOverrides.get(date);
  const visibleShifts = (shifts ?? []).flatMap((shift) => {
    const segment = shiftSegmentForDay({
      workDate: shift.work_date,
      startTime: shift.start_time,
      endTime: shift.end_time,
    }, date);
    if (!segment) return [];
    return [{
      id: shift.id,
      memberLabel: shift.org_members?.profiles?.full_name || shift.org_members?.profiles?.email || "—",
      title: shift.title,
      startTime: shift.start_time,
      endTime: shift.end_time,
      startMinute: segment.start,
      endMinute: segment.end,
      continuesFromPreviousDay: segment.continuesFromPreviousDay,
      colorHex: shift.color_hex,
    }];
  });

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-2xl font-bold text-(--text)">
            {toPersianDigits(jalali.day)} {JALALI_MONTH_NAMES[jalali.month - 1]}{" "}
            {toPersianDigits(jalali.year)}
          </h1>
          <p className="text-sm text-(--text-muted)" dir="ltr">
            {date}
          </p>
          <p className={cn("mt-1 text-xs", DAY_STATUS_TEXT_CLASS[status])}>
            {DAY_STATUS_LABEL_FA[status]}
          </p>
          {override?.note && (
            <p className="text-xs text-(--text-muted)">دلیل: {override.note}</p>
          )}
        </div>
        {ctx.can(PERMISSIONS.SHIFT_MANAGE) && (
          <Button asChild variant="outline" size="sm">
            <Link href={`/${orgId}/shifts?date=${date}`}>برنامه‌ریزی شیفت</Link>
          </Button>
        )}
      </div>

      {canManageDays && (
        <Card>
          <CardContent>
            <DayStatusControl
              orgId={orgId}
              date={date}
              current={status}
              currentNote={override?.note ?? null}
            />
          </CardContent>
        </Card>
      )}

      {(events ?? []).length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">مناسبت‌های امروز</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {(events ?? []).map((e, i) => (
              <div key={i} className="text-sm text-(--text)">
                {e.title}
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">برنامه‌ی امروز</CardTitle>
        </CardHeader>
        <CardContent>
          <DayTimeline
            dayIso={date}
            shifts={visibleShifts}
            leaves={(leaves ?? []).map((l) => ({
              memberLabel: l.member_name ?? "—",
              leaveTypeName: l.leave_type_name ?? "",
              startsAt: l.starts_at!,
              endsAt: l.ends_at!,
            }))}
          />
        </CardContent>
      </Card>
    </div>
  );
}
