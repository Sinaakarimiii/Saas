const TIME_ZONE = "Asia/Tehran";

const dateFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});
const offsetFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: TIME_ZONE,
  timeZoneName: "shortOffset",
});

export function tehranISODate(instant: Date = new Date()): string {
  const parts = dateFormatter.formatToParts(instant);
  const value = (type: string) => parts.find((part) => part.type === type)?.value;
  return `${value("year")}-${value("month")}-${value("day")}`;
}

function tehranOffsetMinutes(instant: Date): number {
  const name = offsetFormatter.formatToParts(instant)
    .find((part) => part.type === "timeZoneName")?.value;
  const match = /^GMT([+-])(\d{1,2})(?::(\d{2}))?$/.exec(name ?? "");
  if (!match) throw new Error("Asia/Tehran offset is unavailable");
  const minutes = Number(match[2]) * 60 + Number(match[3] ?? 0);
  return match[1] === "+" ? minutes : -minutes;
}

export function tehranMidnightUTC(dateIso: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateIso)) throw new Error("Invalid ISO date");
  const [year, month, day] = dateIso.split("-").map(Number);
  const midnightAsUTC = Date.UTC(year, month - 1, day);
  if (new Date(midnightAsUTC).toISOString().slice(0, 10) !== dateIso) {
    throw new Error("Invalid ISO date");
  }
  let instant = midnightAsUTC;
  for (let attempt = 0; attempt < 3; attempt++) {
    const corrected = midnightAsUTC - tehranOffsetMinutes(new Date(instant)) * 60_000;
    if (corrected === instant) break;
    instant = corrected;
  }
  return new Date(instant);
}

export function tehranDayBounds(dateIso: string): { start: string; end: string } {
  const [year, month, day] = dateIso.split("-").map(Number);
  const nextDate = new Date(Date.UTC(year, month - 1, day + 1))
    .toISOString().slice(0, 10);
  return {
    start: tehranMidnightUTC(dateIso).toISOString(),
    end: tehranMidnightUTC(nextDate).toISOString(),
  };
}
