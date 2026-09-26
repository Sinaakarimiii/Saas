import { redirect } from "next/navigation";

// Kept for link stability (existing day-cell links point here) -- the day
// view now lives at /[orgId]/calendar?view=day&date=... alongside the other
// timeframes, so this route just forwards into the consolidated shell.
export default async function CalendarDayRedirect({
  params,
}: PageProps<"/[orgId]/calendar/[date]">) {
  const { orgId, date } = await params;
  redirect(`/${orgId}/calendar?view=day&date=${date}`);
}
