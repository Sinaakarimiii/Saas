import DateObject from "react-date-object";
import persian from "react-date-object/calendars/persian";
import persian_fa from "react-date-object/locales/persian_fa";
import gregorian from "react-date-object/calendars/gregorian";
import gregorian_en from "react-date-object/locales/gregorian_en";
import { tehranISODate } from "./tehran-time";

// Display-only Gregorian -> Jalali formatting. The database always stores
// standard timestamptz/date values; this is purely for what the user sees.
export function formatJalaliDate(dateInput: string | Date): string {
  return new DateObject({
    date: new Date(dateInput),
    calendar: persian,
    locale: persian_fa,
  }).format("YYYY/MM/DD");
}

export function formatJalaliDateTime(dateInput: string | Date): string {
  return new DateObject({
    date: new Date(dateInput),
    calendar: persian,
    locale: persian_fa,
  }).format("YYYY/MM/DD HH:mm");
}

export type JalaliYMD = { year: number; month: number; day: number };

// NOTE on this library's quirks (verified by hand, see git history): a
// DateObject's .convert() mutates the instance in place and returns it --
// never reuse the source object afterwards, and always pass the target
// locale as convert()'s 2nd argument or month/day *names* come out mixed
// up with the wrong calendar (numbers stay correct either way).

export function todayJalali(): JalaliYMD {
  return gregorianISODateToJalali(tehranISODate());
}

// Jalali y/m/d -> Gregorian ISO date string (YYYY-MM-DD), e.g. for querying
// gregorian_date/work_date columns.
export function jalaliToGregorianISODate({ year, month, day }: JalaliYMD): string {
  const d = new DateObject({ calendar: persian, locale: persian_fa }).set({
    year,
    month,
    day,
  });
  return d.convert(gregorian, gregorian_en).format("YYYY-MM-DD");
}

// Gregorian ISO date string -> Jalali y/m/d.
export function gregorianISODateToJalali(iso: string): JalaliYMD {
  const d = new DateObject({
    date: iso,
    format: "YYYY-MM-DD",
    calendar: gregorian,
    locale: gregorian_en,
  }).convert(persian, persian_fa);
  return { year: d.year, month: d.month.number, day: d.day };
}

export function daysInJalaliMonth(year: number, month: number): number {
  return new DateObject({ calendar: persian, locale: persian_fa }).set({
    year,
    month,
    day: 1,
  }).month.length;
}

export const JALALI_MONTH_NAMES = [
  "فروردین",
  "اردیبهشت",
  "خرداد",
  "تیر",
  "مرداد",
  "شهریور",
  "مهر",
  "آبان",
  "آذر",
  "دی",
  "بهمن",
  "اسفند",
] as const;

// Sat=0 ... Fri=6, matching this calendar's own week start (weekStartDayIndex).
export const JALALI_WEEKDAY_NAMES = [
  "شنبه",
  "یک‌شنبه",
  "دوشنبه",
  "سه‌شنبه",
  "چهارشنبه",
  "پنج‌شنبه",
  "جمعه",
] as const;

// weekDay.index of the 1st of the given Jalali month (0=Saturday..6=Friday)
// -- how many empty leading cells a month-grid needs.
export function firstWeekdayOfJalaliMonth(year: number, month: number): number {
  return new DateObject({ calendar: persian, locale: persian_fa }).set({
    year,
    month,
    day: 1,
  }).weekDay.index;
}

// weekDay.index (0=Saturday..6=Friday) of a Gregorian ISO date string.
export function weekdayIndexOfISODate(iso: string): number {
  return new DateObject({
    date: iso,
    format: "YYYY-MM-DD",
    calendar: gregorian,
    locale: gregorian_en,
  })
    .convert(persian, persian_fa)
    .weekDay.index;
}

export function addJalaliMonths(
  { year, month }: Pick<JalaliYMD, "year" | "month">,
  amount: number,
): { year: number; month: number } {
  const d = new DateObject({ calendar: persian, locale: persian_fa })
    .set({ year, month, day: 1 })
    .add(amount, "months");
  return { year: d.year, month: d.month.number };
}

export function addJalaliDays(ymd: JalaliYMD, amount: number): JalaliYMD {
  const d = new DateObject({ calendar: persian, locale: persian_fa })
    .set(ymd)
    .add(amount, "days");
  return { year: d.year, month: d.month.number, day: d.day };
}

export function addJalaliWeeks(ymd: JalaliYMD, amount: number): JalaliYMD {
  return addJalaliDays(ymd, amount * 7);
}

export function addJalaliYears(
  { year, month, day }: JalaliYMD,
  amount: number,
): JalaliYMD {
  const d = new DateObject({ calendar: persian, locale: persian_fa })
    .set({ year, month, day })
    .add(amount, "years");
  return { year: d.year, month: d.month.number, day: d.day };
}

// Sat-start (this calendar's own week start): rewinds to the Saturday of the
// week containing the given date.
export function startOfJalaliWeek(ymd: JalaliYMD): JalaliYMD {
  const d = new DateObject({ calendar: persian, locale: persian_fa }).set(ymd);
  return addJalaliDays(ymd, -d.weekDay.index);
}

const PERSIAN_DIGITS = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"];

export function toPersianDigits(n: number): string {
  return String(n).replace(/[0-9]/g, (digit) => PERSIAN_DIGITS[Number(digit)]);
}

// Small Latin day+month label for a Gregorian ISO date, e.g. "12 Aug" -- the
// secondary sub-label under a day cell's (primary) Jalali day number.
export function formatGregorianShort(iso: string): string {
  return new DateObject({
    date: iso,
    format: "YYYY-MM-DD",
    calendar: gregorian,
    locale: gregorian_en,
  }).format("D MMM");
}
