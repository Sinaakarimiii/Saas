import { getOrgContext } from "@/lib/org-context";
import { PERMISSIONS } from "@/lib/permissions";
import {
  JALALI_MONTH_NAMES,
  addJalaliDays,
  formatGregorianShort,
  gregorianISODateToJalali,
  jalaliToGregorianISODate,
  startOfJalaliWeek,
  todayJalali,
  toPersianDigits,
} from "@/lib/jalali";
import { ViewSwitcher } from "./view-switcher";
import { CalendarNav } from "./calendar-nav";
import { ViewTransition } from "./view-transition";
import { MonthView } from "./month-view";
import { WeekView } from "./week-view";
import { YearView } from "./year-view";
import { DayView } from "./day-view";
import { CALENDAR_VIEWS, type CalendarView } from "./types";

const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function viewTitle(view: CalendarView, anchor: ReturnType<typeof todayJalali>): string {
  if (view === "month") {
    return `${JALALI_MONTH_NAMES[anchor.month - 1]} ${toPersianDigits(anchor.year)}`;
  }
  if (view === "year") {
    return `سال ${toPersianDigits(anchor.year)}`;
  }
  if (view === "week") {
    const start = startOfJalaliWeek(anchor);
    const end = addJalaliDays(start, 6);
    const sameMonth = start.month === end.month && start.year === end.year;
    const startLabel = `${toPersianDigits(start.day)} ${JALALI_MONTH_NAMES[start.month - 1]}`;
    const endLabel = sameMonth
      ? toPersianDigits(end.day)
      : `${toPersianDigits(end.day)} ${JALALI_MONTH_NAMES[end.month - 1]}`;
    return `${startLabel} تا ${endLabel} ${toPersianDigits(end.year)}`;
  }
  return "";
}

export default async function CalendarPage({
  params,
  searchParams,
}: PageProps<"/[orgId]/calendar">) {
  const { orgId } = await params;
  const sp = await searchParams;
  const ctx = await getOrgContext(orgId);
  const canManageDays = ctx.can(PERMISSIONS.CALENDAR_MANAGE_DAYS);

  const rawView = Array.isArray(sp.view) ? sp.view[0] : sp.view;
  const view: CalendarView = CALENDAR_VIEWS.includes(rawView as CalendarView)
    ? (rawView as CalendarView)
    : "month";

  const rawDate = Array.isArray(sp.date) ? sp.date[0] : sp.date;
  const today = todayJalali();
  const todayIso = jalaliToGregorianISODate(today);
  const anchorIso = rawDate && ISO_DATE_RE.test(rawDate) ? rawDate : todayIso;
  const anchor = gregorianISODateToJalali(anchorIso);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          {view !== "day" && (
            <h1 className="text-2xl font-bold text-(--text)">{viewTitle(view, anchor)}</h1>
          )}
          <p className="text-xs text-(--text-muted)">
            امروز: {toPersianDigits(today.day)} {JALALI_MONTH_NAMES[today.month - 1]}{" "}
            {toPersianDigits(today.year)}{" "}
            <span dir="ltr" className="inline-block">
              ({formatGregorianShort(todayIso)} {todayIso.slice(0, 4)})
            </span>
          </p>
        </div>
        <ViewSwitcher orgId={orgId} view={view} dateIso={anchorIso} />
      </div>

      <CalendarNav orgId={orgId} view={view} anchor={anchor} />

      <ViewTransition viewKey={`${view}-${anchorIso}`}>
        {view === "month" && (
          <MonthView orgId={orgId} anchor={anchor} canManageDays={canManageDays} />
        )}
        {view === "week" && (
          <WeekView orgId={orgId} anchor={anchor} canManageDays={canManageDays} />
        )}
        {view === "year" && <YearView orgId={orgId} year={anchor.year} />}
        {view === "day" && <DayView orgId={orgId} date={anchorIso} ctx={ctx} />}
      </ViewTransition>
    </div>
  );
}
