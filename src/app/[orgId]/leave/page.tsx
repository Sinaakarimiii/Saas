import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDateTime } from "@/lib/jalali";
import { fetchHolidayDates } from "@/lib/holidays";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { NewLeaveRequestDialog } from "./request-dialog";
import { NewLeaveTypeDialog } from "./leave-type-dialog";
import { ReviewButtons } from "./review-buttons";
import { CreateLeaveForMemberDialog } from "./create-for-member-dialog";

function statusBadge(status: string) {
  if (status === "approved")
    return (
      <Badge className="bg-(--success-soft) text-(--success)">تاییدشده</Badge>
    );
  if (status === "rejected")
    return <Badge variant="destructive">ردشده</Badge>;
  return <Badge variant="secondary">در انتظار</Badge>;
}

function managedMemberIds(
  members: { id: string; manager_id: string | null }[],
  managerId: string,
) {
  const ids = new Set<string>();
  const queue = [managerId];
  while (queue.length > 0) {
    const current = queue.shift()!;
    for (const member of members) {
      if (member.manager_id === current && !ids.has(member.id)) {
        ids.add(member.id);
        queue.push(member.id);
      }
    }
  }
  return ids;
}

export default async function LeavePage({
  params,
}: PageProps<"/[orgId]/leave">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);
  const supabase = await createClient();

  const [{ data: leaveTypes }, holidays] = await Promise.all([
    supabase
      .from("leave_types")
      .select("id, name, unit")
      .eq("org_id", orgId)
      .is("deleted_at", null)
      .order("created_at", { ascending: true }),
    fetchHolidayDates(supabase),
  ]);

  const { data: myRequests } = await supabase
    .from("leave_requests")
    .select("id, tracking_code, starts_at, ends_at, status, note, leave_types(name)")
    .eq("org_id", orgId)
    .eq("member_id", ctx.memberId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  const canApprove = ctx.can(PERMISSIONS.LEAVE_APPROVE);
  const approvalScope = ctx.scopeOf(PERMISSIONS.LEAVE_APPROVE);
  const canManageLeaveTypes = approvalScope === "all";
  const [{ data: pending }, { data: allMembers }] = canApprove
    ? await Promise.all([
        supabase
          .from("leave_requests")
          .select(
            "id, tracking_code, starts_at, ends_at, note, leave_types(name), org_members(profiles(full_name, email))",
          )
          .eq("org_id", orgId)
          .eq("status", "pending")
          .is("deleted_at", null)
          .order("created_at", { ascending: true }),
        supabase
          .from("org_members")
          .select("id, manager_id, profiles(full_name, email)")
          .eq("org_id", orgId)
          .is("deleted_at", null),
      ])
    : [{ data: [] }, { data: [] }];

  const managedIds = approvalScope === "team"
    ? managedMemberIds(allMembers ?? [], ctx.memberId)
    : null;
  const memberOptions = (allMembers ?? [])
    .filter((m) => managedIds === null || managedIds.has(m.id))
    .map((m) => ({
    id: m.id,
    label: m.profiles?.full_name || m.profiles?.email || "—",
  }));

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">مرخصی</h1>
        <div className="flex gap-2">
          {canManageLeaveTypes && <NewLeaveTypeDialog orgId={orgId} />}
          {canApprove && (
            <CreateLeaveForMemberDialog
              orgId={orgId}
              leaveTypes={leaveTypes ?? []}
              members={memberOptions}
              holidays={holidays}
            />
          )}
          {ctx.can(PERMISSIONS.LEAVE_REQUEST) && (
            <NewLeaveRequestDialog
              orgId={orgId}
              leaveTypes={leaveTypes ?? []}
              holidays={holidays}
            />
          )}
        </div>
      </div>

      {canApprove && (
        <div>
          <h2 className="mb-2 text-lg font-semibold">در انتظار تایید</h2>
          {(pending ?? []).length === 0 ? (
            <p className="text-muted-foreground">درخواستی در انتظار نیست.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>کد پیگیری</TableHead>
                  <TableHead>عضو</TableHead>
                  <TableHead>نوع</TableHead>
                  <TableHead>از</TableHead>
                  <TableHead>تا</TableHead>
                  <TableHead>توضیح</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {(pending ?? []).map((r) => (
                  <TableRow key={r.id}>
                    <TableCell dir="ltr" className="text-right font-mono">
                      {r.tracking_code}
                    </TableCell>
                    <TableCell>
                      {r.org_members?.profiles?.full_name || r.org_members?.profiles?.email}
                    </TableCell>
                    <TableCell>{r.leave_types?.name}</TableCell>
                    <TableCell>{formatJalaliDateTime(r.starts_at)}</TableCell>
                    <TableCell>{formatJalaliDateTime(r.ends_at)}</TableCell>
                    <TableCell className="max-w-40 truncate">{r.note}</TableCell>
                    <TableCell>
                      <ReviewButtons orgId={orgId} requestId={r.id} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      )}

      <div>
        <h2 className="mb-2 text-lg font-semibold">درخواست‌های من</h2>
        {(myRequests ?? []).length === 0 ? (
          <p className="text-muted-foreground">درخواستی ثبت نکرده‌اید.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>کد پیگیری</TableHead>
                <TableHead>نوع</TableHead>
                <TableHead>از</TableHead>
                <TableHead>تا</TableHead>
                <TableHead>وضعیت</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(myRequests ?? []).map((r) => (
                <TableRow key={r.id}>
                  <TableCell dir="ltr" className="text-right font-mono">
                    {r.tracking_code}
                  </TableCell>
                  <TableCell>{r.leave_types?.name}</TableCell>
                  <TableCell>{formatJalaliDateTime(r.starts_at)}</TableCell>
                  <TableCell>{formatJalaliDateTime(r.ends_at)}</TableCell>
                  <TableCell>{statusBadge(r.status)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>
    </div>
  );
}
