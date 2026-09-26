import "server-only";

export function incidentQueueNow(): number {
  return Date.now();
}

export function formatIncidentDueAt(dueAt: string): string {
  return new Intl.DateTimeFormat("fa-IR-u-ca-persian", {
    timeZone: "Asia/Tehran",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).format(new Date(dueAt));
}
