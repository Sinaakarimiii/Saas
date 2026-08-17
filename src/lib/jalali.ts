import DateObject from "react-date-object";
import persian from "react-date-object/calendars/persian";
import persian_fa from "react-date-object/locales/persian_fa";

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
