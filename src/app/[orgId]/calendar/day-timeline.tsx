import { cn } from "@/lib/utils";
import { tehranMidnightUTC } from "@/lib/tehran-time";

const HOUR_HEIGHT_PX = 40;
const MINUTES_IN_DAY = 24 * 60;

export type TimelineShift = {
  id: string;
  memberLabel: string;
  title: string;
  startTime: string; // "HH:MM:SS"
  endTime: string;
  startMinute: number;
  endMinute: number;
  continuesFromPreviousDay: boolean;
  colorHex: string;
};

export type TimelineLeave = {
  memberLabel: string;
  leaveTypeName: string;
  startsAt: string; // timestamptz
  endsAt: string; // timestamptz
};

// Position of a timestamptz within the given Gregorian ISO day, clipped to
// [0, 1440] so multi-day leave still renders sensibly on this one day's grid.
function minutesWithinDay(iso: string, dayIso: string): number {
  const dayStart = tehranMidnightUTC(dayIso);
  const diff = Math.round((new Date(iso).getTime() - dayStart.getTime()) / 60000);
  return Math.min(MINUTES_IN_DAY, Math.max(0, diff));
}

// Greedy lane assignment so overlapping shifts render side-by-side instead
// of stacking on top of each other. `items` must already be sorted by start.
function assignLanes(items: { start: number; end: number }[]): number[] {
  const laneEnds: number[] = [];
  const lanes: number[] = [];
  for (const item of items) {
    let lane = laneEnds.findIndex((end) => end <= item.start);
    if (lane === -1) {
      lane = laneEnds.length;
      laneEnds.push(item.end);
    } else {
      laneEnds[lane] = item.end;
    }
    lanes.push(lane);
  }
  return lanes;
}

export function DayTimeline({
  dayIso,
  shifts,
  leaves,
}: {
  dayIso: string;
  shifts: TimelineShift[];
  leaves: TimelineLeave[];
}) {
  const sortedShifts = [...shifts].sort(
    (a, b) => a.startMinute - b.startMinute,
  );
  const shiftRanges = sortedShifts.map((s) => {
    return { start: s.startMinute, end: s.endMinute };
  });
  const lanes = assignLanes(shiftRanges);
  const laneCount = Math.max(1, ...lanes.map((l) => l + 1));

  const leaveRanges = leaves.map((l) => ({
    start: minutesWithinDay(l.startsAt, dayIso),
    end: Math.max(
      minutesWithinDay(l.startsAt, dayIso) + 15,
      minutesWithinDay(l.endsAt, dayIso),
    ),
  }));

  const totalHeight = HOUR_HEIGHT_PX * 24;
  const toPx = (minutes: number) => (minutes / 60) * HOUR_HEIGHT_PX;

  return (
    <div className="flex text-xs">
      <div className="text-muted-foreground w-10 shrink-0">
        {Array.from({ length: 24 }, (_, h) => (
          <div
            key={h}
            className="border-t pe-1 text-left"
            style={{ height: HOUR_HEIGHT_PX }}
          >
            {String(h).padStart(2, "0")}:00
          </div>
        ))}
      </div>

      <div className="relative flex-1 border-s" style={{ height: totalHeight }}>
        {Array.from({ length: 24 }, (_, h) => (
          <div
            key={h}
            className="border-muted absolute inset-x-0 border-t"
            style={{ top: toPx(h * 60) }}
          />
        ))}

        {leaves.map((l, i) => {
          const range = leaveRanges[i];
          return (
            <div
              key={`leave-${i}`}
              className="bg-muted text-muted-foreground absolute inset-x-1 flex items-center overflow-hidden rounded px-2 opacity-80"
              style={{ top: toPx(range.start), height: Math.max(18, toPx(range.end - range.start)) }}
            >
              مرخصی: {l.memberLabel} ({l.leaveTypeName})
            </div>
          );
        })}

        {sortedShifts.map((s, i) => {
          const range = shiftRanges[i];
          const lane = lanes[i];
          return (
            <div
              key={s.id}
              className={cn("absolute overflow-hidden rounded border px-1.5 py-0.5")}
              style={{
                top: toPx(range.start),
                height: Math.max(20, toPx(range.end - range.start)),
                insetInlineStart: `${(lane / laneCount) * 100}%`,
                width: `${100 / laneCount}%`,
                backgroundColor: `${s.colorHex}26`,
                borderColor: `${s.colorHex}80`,
              }}
              title={`${s.memberLabel} — ${s.title} (${s.startTime.slice(0, 5)}–${s.endTime.slice(0, 5)})`}
            >
              <p className="truncate font-medium">{s.memberLabel}</p>
              <p className="text-muted-foreground truncate">
                {s.continuesFromPreviousDay ? "ادامهٔ شیفت شب: " : ""}{s.title}
              </p>
            </div>
          );
        })}

        {shifts.length === 0 && leaves.length === 0 && (
          <p className="text-muted-foreground absolute inset-x-2 top-2">
            شیفت یا مرخصی‌ای برای این روز ثبت نشده.
          </p>
        )}
      </div>
    </div>
  );
}
