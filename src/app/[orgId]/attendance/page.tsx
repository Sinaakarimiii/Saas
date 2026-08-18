import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDateTime, jalaliToGregorianISODate, todayJalali } from "@/lib/jalali";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ClockButtons } from "./clock-buttons";
import { VoidLogButton } from "./void-button";
import { NewAttendanceEventTypeDialog } from "./event-type-dialog";

type DayStatus = "scheduled_present" | "scheduled_absent" | "unscheduled_present" | "on_leave";

const STATUS_LABEL: Record<DayStatus, string> = {
  scheduled_present: "طبق برنامه، حاضر",
  scheduled_absent: "طبق برنامه، غایب",
  unscheduled_present: "خارج از برنامه، حاضر",
  on_leave: "مرخصی",
};

// success / error / info / neutral, per the 4-state design agreed for this
// module (see ROADMAP.md section 4) — same mapping, Glass v2 semantic tokens.
const STATUS_CLASS: Record<DayStatus, string> = {
  scheduled_present: "bg-(--success-soft) text-(--success)",
  scheduled_absent: "bg-(--error-soft) text-(--error)",
  unscheduled_present: "bg-(--info-soft) text-(--info)",
  on_leave: "bg-(--neutral-soft) text-(--neutral)",
};

export default async function AttendancePage({
  params,
}: PageProps<"/[orgId]/attendance">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);
  const supabase = await createClient();

  const today = todayJalali();
  const todayIso = jalaliToGregorianISODate(today);
  // No trailing "Z" here on purpose: todayIso is a *local* calendar date, so
  // it must be parsed as local wall-clock time and converted to its real UTC
  // instant -- treating it as if it were already UTC midnight silently
  // shifts the "today" window by the server's UTC offset (breaks for a few
  // hours around local midnight in any timezone ahead of UTC, e.g. Iran).
  const dayStart = new Date(`${todayIso}T00:00:00`).toISOString();
  const dayEnd = new Date(`${todayIso}T23:59:59`).toISOString();

  const { data: eventTypes } = await supabase
    .from("attendance_event_types")
    .select("id, name, kind, toggle")
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .order("is_system", { ascending: false });

  const { data: myTodayLogs } = await supabase
    .from("attendance_logs")
    .select("event_type_id, occurred_at")
    .eq("org_id", orgId)
    .eq("member_id", ctx.memberId)
    .is("voided_at", null)
    .gte("occurred_at", dayStart)
    .order("occurred_at", { ascending: false });

  // Toggle-style events (e.g. جلسه/استراحت) don't have a separate "end"
  // type -- the same button reports both, so whether it's currently "on"
  // is just the parity of today's unvoided clicks for that one type.
  const countByType = new Map<string, number>();
  for (const log of myTodayLogs ?? []) {
    countByType.set(log.event_type_id, (countByType.get(log.event_type_id) ?? 0) + 1);
  }
  const toggleOnByType: Record<string, boolean> = {};
  for (const et of eventTypes ?? []) {
    if (et.toggle) toggleOnByType[et.id] = (countByType.get(et.id) ?? 0) % 2 === 1;
  }

  const canViewAll = ctx.scopeOf(PERMISSIONS.ATTENDANCE_VIEW) === "all";

  let todayStatuses: { member: string; status: DayStatus }[] = [];
  if (canViewAll) {
    const [{ data: members }, { data: shifts }, { data: leaves }, { data: logs }] =
      await Promise.all([
        supabase
          .from("org_members")
          .select("id, profiles(full_name, email)")
          .eq("org_id", orgId)
          .is("deleted_at", null),
        supabase
          .from("shift_assignments")
          .select("member_id")
          .eq("org_id", orgId)
          .eq("work_date", todayIso)
          .is("deleted_at", null),
        supabase
          .from("leave_requests")
          .select("member_id")
          .eq("org_id", orgId)
          .eq("status", "approved")
          .is("deleted_at", null)
          .lte("starts_at", dayEnd)
          .gte("ends_at", dayStart),
        supabase
          .from("attendance_logs")
          .select("member_id, occurred_at, attendance_event_types(kind)")
          .eq("org_id", orgId)
          .is("voided_at", null)
          .gte("occurred_at", dayStart)
          .order("occurred_at", { ascending: true }),
      ]);

    const scheduledMemberIds = new Set((shifts ?? []).map((s) => s.member_id));
    const onLeaveMemberIds = new Set((leaves ?? []).map((l) => l.member_id));

    const lastKindByMember = new Map<string, string>();
    for (const log of logs ?? []) {
      const kind = log.attendance_event_types?.kind;
      if (kind) lastKindByMember.set(log.member_id, kind);
    }

    todayStatuses = (members ?? [])
      .map((m) => {
        const label = m.profiles?.full_name || m.profiles?.email || "—";
        const isScheduled = scheduledMemberIds.has(m.id);
        const isPresent = lastKindByMember.get(m.id) === "clock_in";
        const isOnLeave = onLeaveMemberIds.has(m.id);

        // Someone with no shift today, not present, and not on leave has
        // nothing worth flagging -- the 4-state design (ROADMAP.md section
        // 4) doesn't define a 5th "irrelevant today" color, so they're
        // left out of the list rather than wrongly painted red/"absent".
        let status: DayStatus | null;
        if (isOnLeave) status = "on_leave";
        else if (isScheduled && isPresent) status = "scheduled_present";
        else if (isScheduled && !isPresent) status = "scheduled_absent";
        else if (!isScheduled && isPresent) status = "unscheduled_present";
        else status = null;

        return status ? { member: label, status } : null;
      })
      .filter((s): s is { member: string; status: DayStatus } => s !== null);
  }

  const { data: logs } = await supabase
    .from("attendance_logs")
    .select(
      "id, occurred_at, note, voided_at, attendance_event_types(name), org_members(id, profiles(full_name, email))",
    )
    .eq("org_id", orgId)
    .order("occurred_at", { ascending: false })
    .limit(100);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold">حضور و غیاب</h1>

      {ctx.can(PERMISSIONS.ATTENDANCE_RECORD) && (
        <div>
          <div className="mb-2 flex items-center justify-between">
            <h2 className="text-lg font-semibold">ثبت حضور من</h2>
            {ctx.can(PERMISSIONS.SHIFT_MANAGE) && (
              <NewAttendanceEventTypeDialog orgId={orgId} />
            )}
          </div>
          <ClockButtons
            orgId={orgId}
            eventTypes={eventTypes ?? []}
            lastEventTypeId={myTodayLogs?.[0]?.event_type_id ?? null}
            toggleOnByType={toggleOnByType}
          />
        </div>
      )}

      {canViewAll && (
        <div>
          <h2 className="mb-2 text-lg font-semibold">وضعیت امروز اعضا</h2>
          {todayStatuses.length === 0 ? (
            <p className="text-muted-foreground">
              امروز شیفت، حضور یا مرخصی‌ای ثبت نشده.
            </p>
          ) : (
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {todayStatuses.map((s, i) => (
                <div
                  key={i}
                  className={`flex items-center justify-between rounded-md px-3 py-2 text-sm ${STATUS_CLASS[s.status]}`}
                >
                  <span>{s.member}</span>
                  <span>{STATUS_LABEL[s.status]}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      <div>
        <h2 className="mb-2 text-lg font-semibold">لاگ حضور</h2>
        {(logs ?? []).length === 0 ? (
          <p className="text-muted-foreground">ثبتی وجود ندارد.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>زمان</TableHead>
                <TableHead>عضو</TableHead>
                <TableHead>رویداد</TableHead>
                <TableHead>توضیح</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {(logs ?? []).map((l) => (
                <TableRow key={l.id} className={l.voided_at ? "opacity-50" : ""}>
                  <TableCell>{formatJalaliDateTime(l.occurred_at)}</TableCell>
                  <TableCell>
                    {l.org_members?.profiles?.full_name || l.org_members?.profiles?.email}
                  </TableCell>
                  <TableCell>
                    {l.attendance_event_types?.name}
                    {l.voided_at && <Badge variant="outline" className="mr-2">باطل‌شده</Badge>}
                  </TableCell>
                  <TableCell className="max-w-40 truncate">{l.note}</TableCell>
                  <TableCell>
                    {!l.voided_at &&
                      l.org_members?.id === ctx.memberId &&
                      ctx.can(PERMISSIONS.ATTENDANCE_RECORD) && (
                        <VoidLogButton orgId={orgId} logId={l.id} />
                      )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>
    </div>
  );
}
