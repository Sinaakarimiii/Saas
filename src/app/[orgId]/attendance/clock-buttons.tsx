"use client";

import { useState, useTransition } from "react";
import { recordAttendance } from "./actions";
import { Button } from "@/components/ui/button";

type EventType = { id: string; name: string; kind: string; toggle: boolean };

export function ClockButtons({
  orgId,
  eventTypes,
  lastEventTypeId,
  toggleOnByType,
}: {
  orgId: string;
  eventTypes: EventType[];
  lastEventTypeId: string | null;
  toggleOnByType: Record<string, boolean>;
}) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [justLogged, setJustLogged] = useState<string | null>(null);

  function click(eventTypeId: string) {
    setError(null);
    startTransition(async () => {
      const result = await recordAttendance(orgId, eventTypeId, "");
      if (result.error) {
        setError(result.error);
        return;
      }
      setJustLogged(eventTypeId);
    });
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap gap-2">
        {eventTypes.map((et) => {
          if (et.toggle) {
            const isOn = toggleOnByType[et.id] ?? false;
            return (
              <Button
                key={et.id}
                variant={isOn ? "default" : "outline"}
                disabled={isPending}
                onClick={() => click(et.id)}
              >
                {isOn ? `پایان ${et.name}` : `شروع ${et.name}`}
              </Button>
            );
          }
          const isCurrent = lastEventTypeId === et.id || justLogged === et.id;
          return (
            <Button
              key={et.id}
              variant={isCurrent ? "default" : "outline"}
              disabled={isPending}
              onClick={() => click(et.id)}
            >
              {et.name}
            </Button>
          );
        })}
      </div>
      {error && <p className="text-destructive text-sm">{error}</p>}
    </div>
  );
}
