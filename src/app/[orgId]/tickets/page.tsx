import Link from "next/link";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDateTime } from "@/lib/jalali";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export default async function TicketsPage({
  params,
}: PageProps<"/[orgId]/tickets">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);
  const supabase = await createClient();

  const { data: tickets } = await supabase
    .from("tickets")
    .select("id, tracking_code, title, status, created_at, form_templates(name)")
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">تیکت‌ها</h1>
        {ctx.can(PERMISSIONS.TICKET_CREATE) && (
          <Button asChild>
            <Link href={`/${orgId}/tickets/new`}>+ تیکت جدید</Link>
          </Button>
        )}
      </div>

      {(tickets ?? []).length === 0 && (
        <p className="text-muted-foreground">تیکتی برای نمایش وجود ندارد.</p>
      )}

      {(tickets ?? []).length > 0 && (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>کد پیگیری</TableHead>
              <TableHead>عنوان</TableHead>
              <TableHead>فرم</TableHead>
              <TableHead>وضعیت</TableHead>
              <TableHead>تاریخ ثبت</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(tickets ?? []).map((t) => (
              <TableRow key={t.id}>
                <TableCell dir="ltr" className="text-right font-mono">
                  <Link
                    href={`/${orgId}/tickets/${t.id}`}
                    className="text-primary underline"
                  >
                    {t.tracking_code}
                  </Link>
                </TableCell>
                <TableCell>{t.title || "—"}</TableCell>
                <TableCell>{t.form_templates?.name}</TableCell>
                <TableCell>
                  <Badge variant={t.status === "open" ? "default" : "secondary"}>
                    {t.status === "open" ? "باز" : "بسته"}
                  </Badge>
                </TableCell>
                <TableCell>{formatJalaliDateTime(t.created_at)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
