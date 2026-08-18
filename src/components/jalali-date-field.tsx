"use client";

import { useMemo } from "react";
import DatePicker from "react-multi-date-picker";
import DateObject from "react-date-object";
import persian from "react-date-object/calendars/persian";
import persian_fa from "react-date-object/locales/persian_fa";
import gregorian from "react-date-object/calendars/gregorian";
import gregorian_en from "react-date-object/locales/gregorian_en";
import { isRedDay, redDayClassName } from "@/lib/holidays";

const dateInputClass =
  "flex h-9 w-full rounded-lg border border-input bg-transparent px-2.5 py-1 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30";

// Persian-calendar date picker: takes/emits a plain Gregorian ISO date
// string (YYYY-MM-DD) so callers can keep working with the same values the
// database stores, and marks official holidays + every Friday in red.
export function JalaliDateField({
  id,
  value,
  onChange,
  holidays,
}: {
  id?: string;
  value: string;
  onChange: (iso: string) => void;
  holidays: string[];
}) {
  const holidaySet = useMemo(() => new Set(holidays), [holidays]);

  return (
    <DatePicker
      id={id}
      calendar={persian}
      locale={persian_fa}
      value={
        value
          ? new DateObject({
              date: value,
              format: "YYYY-MM-DD",
              calendar: gregorian,
              locale: gregorian_en,
            }).convert(persian, persian_fa)
          : ""
      }
      onChange={(date) => {
        if (!date || Array.isArray(date)) return;
        onChange(new DateObject(date).convert(gregorian, gregorian_en).format("YYYY-MM-DD"));
      }}
      mapDays={({ date }) =>
        isRedDay(date, holidaySet) ? { className: redDayClassName } : undefined
      }
      inputClass={dateInputClass}
      containerClassName="w-full"
    />
  );
}
