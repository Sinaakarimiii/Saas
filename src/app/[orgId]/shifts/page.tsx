import { redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDate } from "@/lib/jalali";
import { fetchHolidayDates } from "@/lib/holidays";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { NewTemplateDialog } from "./template-dialog";
import { AssignShiftDialog } from "./assign-dialog";
import { RemoveShiftAssignmentButton } from "./remove-assignment-button";

export default async function ShiftsPage({
  params,
  searchParams,
}: PageProps<"/[orgId]/shifts">) {
  const { orgId } = await params;
  const sp = await searchParams;
  const ctx = await getOrgContext(orgId);

  if (!ctx.can(PERMISSIONS.SHIFT_MANAGE)) {
    redirect(`/${orgId}/dashboard`);
  }

  const supabase = await createClient();
  const defaultDate = typeof sp.date === "string" ? sp.date : undefined;

  const [{ data: templates }, { data: members }, { data: assignments }, holidays] =
    await Promise.all([
      supabase
        .from("shift_templates")
        .select("id, name, start_time, end_time, color_hex")
        .eq("org_id", orgId)
        .is("deleted_at", null)
        .order("start_time", { ascending: true }),
      supabase
        .from("org_members")
        .select("id, profiles(full_name, email)")
        .eq("org_id", orgId)
        .is("deleted_at", null),
      supabase
        .from("shift_assignments")
        .select(
          "id, title, work_date, start_time, end_time, color_hex, org_members(profiles(full_name, email))",
        )
        .eq("org_id", orgId)
        .is("deleted_at", null)
        .order("work_date", { ascending: false })
        .limit(50),
      fetchHolidayDates(supabase),
    ]);

  const memberOptions = (members ?? []).map((m) => ({
    id: m.id,
    label: m.profiles?.full_name || m.profiles?.email || "—",
  }));

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">شیفت‌ها</h1>
        <div className="flex gap-2">
          <NewTemplateDialog orgId={orgId} />
          <AssignShiftDialog
            orgId={orgId}
            members={memberOptions}
            templates={templates ?? []}
            defaultDate={defaultDate}
            holidays={holidays}
          />
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">قالب‌های شیفت</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {(templates ?? []).length === 0 && (
            <p className="text-muted-foreground text-sm">قالبی ساخته نشده.</p>
          )}
          {(templates ?? []).map((t) => (
            <Badge key={t.id} variant="outline" className="text-sm">
              <span className="size-3 rounded-full" style={{ backgroundColor: t.color_hex }} />
              {t.name} ({t.start_time.slice(0, 5)}–{t.end_time.slice(0, 5)})
            </Badge>
          ))}
        </CardContent>
      </Card>

      <div>
        <h2 className="mb-2 text-lg font-semibold">برنامه‌ی شیفت‌ها (۵۰ مورد اخیر)</h2>
        {(assignments ?? []).length === 0 ? (
          <p className="text-muted-foreground">شیفتی ثبت نشده.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>تاریخ</TableHead>
                <TableHead>عضو</TableHead>
                <TableHead>عنوان</TableHead>
                <TableHead>ساعت</TableHead>
                <TableHead>رنگ</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {(assignments ?? []).map((a) => (
                <TableRow key={a.id}>
                  <TableCell>{formatJalaliDate(a.work_date)}</TableCell>
                  <TableCell>
                    {a.org_members?.profiles?.full_name || a.org_members?.profiles?.email}
                  </TableCell>
                  <TableCell>{a.title}</TableCell>
                  <TableCell dir="ltr" className="text-right font-mono">
                    {a.start_time?.slice(0, 5)}–{a.end_time?.slice(0, 5)}
                  </TableCell>
                  <TableCell><span className="inline-block size-4 rounded-full" style={{ backgroundColor: a.color_hex }} /></TableCell>
                  <TableCell>
                    <RemoveShiftAssignmentButton orgId={orgId} assignmentId={a.id} />
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
