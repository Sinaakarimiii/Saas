"use client";

import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { setDayStatus } from "./actions";
import { DAY_STATUS_LABEL_FA, type DayStatus } from "@/lib/holidays";

const OPTIONS: DayStatus[] = ["workday", "unofficial_holiday", "official_holiday"];

export function DayStatusControl({
  orgId,
  date,
  current,
  currentNote,
}: {
  orgId: string;
  date: string;
  current: DayStatus;
  currentNote: string | null;
}) {
  const [status, setStatus] = useState(current);
  const [note, setNote] = useState(currentNote ?? "");
  const [saved, setSaved] = useState(true);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function save(nextStatus: DayStatus) {
    setError(null);
    startTransition(async () => {
      const res = await setDayStatus(orgId, date, nextStatus, note);
      if (res.error) setError(res.error);
      else {
        setStatus(nextStatus);
        setSaved(true);
      }
    });
  }

  return (
    <div className="flex flex-col gap-2">
      <p className="text-xs text-(--text-muted)">تغییر وضعیت این روز</p>
      <div className="flex flex-wrap gap-2">
        {OPTIONS.map((opt) => (
          <Button
            key={opt}
            type="button"
            size="sm"
            variant={status === opt ? "default" : "secondary"}
            disabled={pending}
            onClick={() => save(opt)}
          >
            {DAY_STATUS_LABEL_FA[opt]}
          </Button>
        ))}
      </div>
      <textarea
        value={note}
        onChange={(e) => {
          setNote(e.target.value);
          setSaved(false);
        }}
        placeholder="توضیحات / دلیل (اختیاری)"
        rows={2}
        className="w-full rounded-(--glass-radius) bg-(--glass) p-2 text-xs text-(--text) [border:var(--glass-hairline)] placeholder:text-(--text-dim)"
      />
      {!saved && (
        <Button type="button" size="sm" variant="outline" disabled={pending} onClick={() => save(status)}>
          ثبت توضیحات
        </Button>
      )}
      {error && <p className="text-xs text-(--error)">{error}</p>}
    </div>
  );
}
