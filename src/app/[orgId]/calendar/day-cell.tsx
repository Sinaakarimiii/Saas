import Link from "next/link";
import { Flag, FlagOff, Info } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { DayStatusControl } from "./day-status-control";
import {
  DAY_STATUS_LABEL_FA,
  DAY_STATUS_TEXT_CLASS,
  DAY_STATUS_TINT_CLASS,
  type DayStatus,
} from "@/lib/holidays";
import { formatGregorianShort, toPersianDigits } from "@/lib/jalali";
import { cn } from "@/lib/utils";

// One icon per status -- shape carries the meaning (not just color), and
// doubles as the "click for details" affordance so there's a single,
// clearly-visible element per cell instead of a near-invisible dot.
const STATUS_ICON: Record<DayStatus, typeof Flag | null> = {
  official_holiday: Flag,
  unofficial_holiday: FlagOff,
  workday: null,
};

export function DayCell({
  orgId,
  iso,
  jalaliDay,
  jalaliLabel,
  status,
  isOverridden,
  overrideNote,
  occasions,
  hasLeave,
  hasShift,
  isToday,
  canManageDays,
  size = "default",
  weekdayLabel,
}: {
  orgId: string;
  iso: string;
  jalaliDay: number;
  /** Full Jalali date label for the dialog title, e.g. "۲۸ مرداد ۱۴۰۵". */
  jalaliLabel: string;
  status: DayStatus;
  /** Whether `status` came from a manual calendar_day_status row (vs. the computed default). */
  isOverridden: boolean;
  overrideNote: string | null;
  occasions: { title: string }[];
  hasLeave: boolean;
  hasShift: boolean;
  isToday: boolean;
  canManageDays: boolean;
  size?: "default" | "sm" | "lg";
  /** Weekday name shown above the day number -- week view only, where there's no separate header row. */
  weekdayLabel?: string;
}) {
  // Something to open a dialog for: a real occasion, or a manual override
  // (so anyone can see why/who changed it, even with no occasion that day).
  // A plain day with neither gets no icon at all -- permitted users set an
  // initial status from the day-detail view instead (the whole cell already
  // links there).
  const showTrigger = occasions.length > 0 || isOverridden;
  const StatusIcon = STATUS_ICON[status];
  // Workday cells with nothing else to show get a neutral info glyph;
  // holiday cells always show their status icon (it already implies "click
  // for details").
  const TriggerIcon = StatusIcon ?? Info;
  const iconColorClass = StatusIcon ? DAY_STATUS_TEXT_CLASS[status] : "text-(--accent)";

  return (
    <div className="relative">
      <Link
        href={`/${orgId}/calendar?view=day&date=${iso}`}
        className={cn(
          "flex flex-col items-center gap-0.5 rounded-(--glass-radius) [border:var(--glass-hairline)] p-1.5 pt-4 transition-colors hover:brightness-95",
          DAY_STATUS_TINT_CLASS[status],
          size === "sm" && "min-h-12",
          size === "default" && "min-h-16",
          size === "lg" && "min-h-28 gap-1",
          isToday && "ring-2 ring-(--accent)",
        )}
      >
        {weekdayLabel && (
          <span className="text-xs text-(--text-muted)">{weekdayLabel}</span>
        )}
        <span
          className={cn(
            "flex items-center gap-1 font-semibold",
            size === "lg" ? "text-lg" : "text-sm",
            DAY_STATUS_TEXT_CLASS[status],
          )}
        >
          {toPersianDigits(jalaliDay)}
          {hasLeave && (
            <span className="inline-block size-1.5 rounded-full bg-(--neutral)" title="مرخصی" />
          )}
          {hasShift && (
            <span className="inline-block size-1.5 rounded-full bg-(--accent)" title="شیفت" />
          )}
        </span>
        <span className="text-[10px] text-(--text-muted)" dir="ltr">
          {formatGregorianShort(iso)}
        </span>
      </Link>

      {showTrigger && (
        <Dialog>
          <DialogTrigger asChild>
            <button
              type="button"
              aria-label={`${DAY_STATUS_LABEL_FA[status]} -- مناسبت و وضعیت این روز`}
              className="absolute top-1 start-1 p-0.5"
            >
              <TriggerIcon className={cn("size-4", iconColorClass)} strokeWidth={2.25} />
            </button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>{jalaliLabel}</DialogTitle>
              <DialogDescription dir="ltr">{iso}</DialogDescription>
            </DialogHeader>

            {occasions.length > 0 ? (
              <ul className="flex flex-col gap-1 text-sm text-(--text)">
                {occasions.map((o, i) => (
                  <li key={i}>{o.title}</li>
                ))}
              </ul>
            ) : (
              <p className="text-sm text-(--text-muted)">مناسبتی برای این روز ثبت نشده</p>
            )}

            <p className={cn("flex items-center gap-1 text-xs", DAY_STATUS_TEXT_CLASS[status])}>
              <TriggerIcon className="size-3" strokeWidth={2} />
              {DAY_STATUS_LABEL_FA[status]}
            </p>
            {isOverridden && overrideNote && (
              <p className="text-xs text-(--text-muted)">دلیل: {overrideNote}</p>
            )}

            {canManageDays && (
              <DialogFooter className="!justify-start">
                <DayStatusControl
                  orgId={orgId}
                  date={iso}
                  current={status}
                  currentNote={overrideNote}
                />
              </DialogFooter>
            )}
          </DialogContent>
        </Dialog>
      )}
    </div>
  );
}
