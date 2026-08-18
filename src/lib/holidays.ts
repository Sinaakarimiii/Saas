import DateObject from "react-date-object";
import gregorian from "react-date-object/calendars/gregorian";
import gregorian_en from "react-date-object/locales/gregorian_en";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";

// Fridays are the Iranian weekend and aren't individually rowed in
// calendar_events (the source dataset only lists named holidays/occasions),
// so "red day" = official holiday OR Friday. weekDay.index follows this
// calendar's own week start: Sat=0 ... Fri=6 (see JALALI_WEEKDAY_NAMES).
export function isRedDay(date: DateObject, holidays: ReadonlySet<string>): boolean {
  if (date.weekDay.index === 6) return true;
  const iso = new DateObject(date).convert(gregorian, gregorian_en).format("YYYY-MM-DD");
  return holidays.has(iso);
}

export const redDayClassName = "text-red-600 dark:text-red-400 font-semibold";

// Global reference data (not org-scoped) -- safe to fetch once per page and
// pass down to every calendar/date-picker on it.
export async function fetchHolidayDates(
  supabase: SupabaseClient<Database>,
): Promise<string[]> {
  const { data } = await supabase
    .from("calendar_events")
    .select("gregorian_date")
    .eq("is_holiday", true);
  return (data ?? []).map((r) => r.gregorian_date);
}

export type DayStatus = "official_holiday" | "unofficial_holiday" | "workday";
export type DayStatusOverride = { status: DayStatus; note: string | null };

// Per-org manual overrides (calendar_day_status) -- always wins over the
// computed default (see resolveDayStatus). Keyed by Gregorian ISO date.
export async function fetchDayStatusOverrides(
  supabase: SupabaseClient<Database>,
  orgId: string,
  range?: { from: string; to: string },
): Promise<Map<string, DayStatusOverride>> {
  let query = supabase
    .from("calendar_day_status")
    .select("gregorian_date, status, note")
    .eq("org_id", orgId);
  if (range) {
    query = query.gte("gregorian_date", range.from).lte("gregorian_date", range.to);
  }
  const { data } = await query;
  return new Map(
    (data ?? []).map((r) => [r.gregorian_date, { status: r.status as DayStatus, note: r.note }]),
  );
}

// Merges the manual override (if any) with the computed default: Friday or
// a calendar_events.is_holiday row -> official_holiday, otherwise workday.
// unofficial_holiday only ever comes from an explicit override.
export function resolveDayStatus(
  iso: string,
  isFriday: boolean,
  holidays: ReadonlySet<string>,
  overrides: ReadonlyMap<string, DayStatusOverride>,
): DayStatus {
  const override = overrides.get(iso);
  if (override) return override.status;
  return isFriday || holidays.has(iso) ? "official_holiday" : "workday";
}

// Glass semantic tokens per status -- conveyed by color plus a distinct
// status icon (see day-cell.tsx's STATUS_ICON), so status isn't
// communicated by hue alone.
export const DAY_STATUS_TEXT_CLASS: Record<DayStatus, string> = {
  official_holiday: "text-(--error)",
  unofficial_holiday: "text-(--warning)",
  workday: "text-(--text)",
};

export const DAY_STATUS_TINT_CLASS: Record<DayStatus, string> = {
  official_holiday: "bg-(--error-soft)",
  unofficial_holiday: "bg-(--warning-soft)",
  workday: "bg-(--glass)",
};

export const DAY_STATUS_LABEL_FA: Record<DayStatus, string> = {
  official_holiday: "تعطیل رسمی",
  unofficial_holiday: "تعطیل غیررسمی",
  workday: "روز کاری",
};
