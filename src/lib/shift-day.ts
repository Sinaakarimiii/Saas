export type DatedShift = {
  workDate: string;
  startTime: string;
  endTime: string;
};

export function previousISODate(dateIso: string): string {
  const instant = Date.parse(`${dateIso}T00:00:00Z`);
  if (!Number.isFinite(instant)) throw new Error("Invalid ISO date");
  return new Date(instant - 86_400_000).toISOString().slice(0, 10);
}

function minutes(time: string): number {
  const [hours, minute] = time.split(":").map(Number);
  return hours * 60 + minute;
}

export function shiftSegmentForDay(
  shift: DatedShift,
  dayIso: string,
): { start: number; end: number; continuesFromPreviousDay: boolean } | null {
  const start = minutes(shift.startTime);
  const end = minutes(shift.endTime);
  const overnight = end <= start;
  if (shift.workDate === dayIso) {
    return { start, end: overnight ? 1440 : end, continuesFromPreviousDay: false };
  }
  if (overnight && shift.workDate === previousISODate(dayIso) && end > 0) {
    return { start: 0, end, continuesFromPreviousDay: true };
  }
  return null;
}
