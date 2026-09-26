import Link from "next/link";
import { redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDateTime } from "@/lib/jalali";
import { formatIncidentDueAt, incidentQueueNow } from "@/lib/repair-incident-queue";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

const stageNames: Record<string, string> = {
  intake: "پذیرش", diagnosis: "کارشناسی", decision: "تصمیم و هماهنگی",
  repair: "تعمیر", replacement: "تعویض", test: "تست", delivery: "تحویل", closed: "بسته‌شده",
};

export default async function RepairsPage({ params, searchParams }: PageProps<"/[orgId]/repairs">) {
  const { orgId } = await params;
  const query = await searchParams;
  const ctx = await getOrgContext(orgId);
  if (!ctx.can(PERMISSIONS.REPAIR_CASE_VIEW)) redirect(`/${orgId}/dashboard`);
  const requested = typeof query.page === "string" ? Number(query.page) : 1;
  const page = Number.isSafeInteger(requested) && requested > 0 ? requested : 1;
  const pageSize = 30;
  const supabase = await createClient();
  const { data: cases, count, error } = await supabase
    .from("repair_cases")
    .select("id, tracking_code, customer_name, device_model, raw_identifier, stage, received_at, created_at", { count: "exact" })
    .eq("org_id", orgId)
    .order("created_at", { ascending: false })
    .range((page - 1) * pageSize, page * pageSize - 1);
  if (error) throw new Error("Could not load repair cases", { cause: error });
  const { data: pendingForMe, error: pendingError } = await supabase
    .from("repair_case_assignment_requests")
    .select("id, case_id, request_reference, requested_at, repair_cases(tracking_code, customer_name)")
    .eq("org_id", orgId).eq("target_user_id", ctx.user.id).eq("status", "pending")
    .order("requested_at", { ascending: false }).limit(20);
  if (pendingError) throw new Error("Could not load pending assignments", { cause: pendingError });
  const [{ data: custodyForMe, error: custodyQueueError }, { data: discrepanciesForMe, error: discrepancyQueueError }] = await Promise.all([
    supabase.from("repair_device_custody_transfers")
        .select("id, case_id, release_reference, source_location, destination_location, released_at, repair_cases(tracking_code, customer_name)")
        .eq("org_id", orgId).eq("destination_user_id", ctx.user.id).eq("status", "in_transit")
        .order("released_at", { ascending: true }).limit(30),
    supabase.from("repair_device_custody_discrepancies")
        .select("id, case_id, kind, reference, due_at, repair_cases(tracking_code, customer_name)")
        .eq("org_id", orgId).eq("responsible_user_id", ctx.user.id).eq("status", "open")
        .order("due_at", { ascending: true }).limit(30)
  ]);
  if (custodyQueueError || discrepancyQueueError) throw new Error("Could not load custody queues", { cause: custodyQueueError ?? discrepancyQueueError });
  const { data: deliveryIncidents, count: openDeliveryIncidentCount, error: deliveryIncidentError } = await supabase
    .from("repair_delivery_incidents")
    .select("id, case_id, kind, reference, due_at, responsible_user_id, repair_cases(tracking_code, customer_name)", { count: "exact" })
    .eq("org_id", orgId).eq("status", "open")
    .order("due_at", { ascending: true }).order("id", { ascending: true }).limit(5);
  if (deliveryIncidentError) throw new Error("Could not load delivery incident queue", { cause: deliveryIncidentError });
  const totalPages = Math.max(1, Math.ceil((count ?? 0) / pageSize));
  const now = incidentQueueNow();

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">پرونده‌های تعمیر</h1>
          <p className="mt-1 text-sm text-muted-foreground">پیگیری درخواست‌ها، دریافت دستگاه و مرحلهٔ جاری هر پرونده</p>
        </div>
        {ctx.can(PERMISSIONS.REPAIR_CASE_CREATE) && (
          <Button asChild><Link href={`/${orgId}/repairs/new`}>ثبت پروندهٔ جدید</Link></Button>
        )}
      </div>
      {(openDeliveryIncidentCount ?? 0) > 0 && <Card><CardContent className="grid gap-2">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="font-medium">مسائل بازِ حمل در سازمان · {openDeliveryIncidentCount} مورد</p>
          <Link className="text-sm text-primary underline-offset-4 hover:underline" href={`/${orgId}/repairs/incidents`}>مشاهدهٔ صف کامل</Link>
        </div>
        {(deliveryIncidents ?? []).map((item) => {
          const overdue = new Date(item.due_at).getTime() < now;
          return <Link key={item.id} href={`/${orgId}/repairs/${item.case_id}`}
            className={`rounded-lg border p-3 text-sm hover:bg-muted/50 ${overdue ? "border-destructive/50" : "border-border/70"}`}>
            {item.repair_cases?.tracking_code} · {item.kind === "lost" ? "مفقودی" : item.kind === "damage" ? "آسیب‌دیدگی" : "اختلاف تحویل"} · مرجع {item.reference} · {overdue ? "سررسیدگذشته" : "موعد"} {formatIncidentDueAt(item.due_at)}{item.responsible_user_id === ctx.user.id ? " · مسئول: من" : ""}
          </Link>;
        })}
      </CardContent></Card>}
      {(pendingForMe ?? []).length > 0 && <Card><CardContent className="grid gap-2">
        <p className="font-medium">درخواست‌های واگذاری به من</p>
        {(pendingForMe ?? []).map((request) => <Link key={request.id} href={`/${orgId}/repairs/${request.case_id}`}
          className="rounded-lg border border-border/70 p-3 text-sm hover:bg-muted/50">
          {request.repair_cases?.tracking_code} · {request.repair_cases?.customer_name} · مرجع {request.request_reference}
        </Link>)}
      </CardContent></Card>}
      {(custodyForMe ?? []).length > 0 && <Card><CardContent className="grid gap-2">
        <p className="font-medium">حواله‌های دستگاه در انتظار دریافت من</p>
        {(custodyForMe ?? []).map((item) => <Link key={item.id} href={`/${orgId}/repairs/${item.case_id}`}
          className="rounded-lg border border-border/70 p-3 text-sm hover:bg-muted/50">
          {item.repair_cases?.tracking_code} · {item.repair_cases?.customer_name} · {item.source_location} ← {item.destination_location} · حواله {item.release_reference}
        </Link>)}
      </CardContent></Card>}
      {(discrepanciesForMe ?? []).length > 0 && <Card><CardContent className="grid gap-2">
        <p className="font-medium">مغایرت‌های واگذار شده به من</p>
        {(discrepanciesForMe ?? []).map((item) => <Link key={item.id} href={`/${orgId}/repairs/${item.case_id}`}
          className="rounded-lg border border-amber-500/40 p-3 text-sm hover:bg-amber-500/10">
          {item.repair_cases?.tracking_code} · {item.repair_cases?.customer_name} · {item.kind === "damage" ? "آسیب‌دیدگی" : item.kind === "identity_mismatch" ? "اختلاف شناسه" : "اختلاف مقصد"} · مرجع {item.reference} · موعد {formatJalaliDateTime(item.due_at)}
        </Link>)}
      </CardContent></Card>}
      <Card>
        <CardContent>
          {(cases ?? []).length === 0 ? (
            <div className="py-10 text-center">
              <p className="font-medium">هنوز پروندهٔ تعمیری ثبت نشده است.</p>
              <p className="mt-1 text-sm text-muted-foreground">با ثبت درخواست اولیه، پرونده کد پیگیری می‌گیرد؛ دریافت فیزیکی دستگاه جداگانه ثبت می‌شود.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>پرونده</TableHead><TableHead>مشتری و دستگاه</TableHead><TableHead>شناسهٔ اولیه</TableHead>
                  <TableHead>مرحله</TableHead><TableHead>دریافت</TableHead><TableHead>زمان ثبت</TableHead>
                </TableRow></TableHeader>
                <TableBody>{cases?.map((item) => (
                  <TableRow key={item.id}>
                    <TableCell><Link className="font-mono text-primary underline-offset-4 hover:underline" href={`/${orgId}/repairs/${item.id}`}>{item.tracking_code}</Link></TableCell>
                    <TableCell><span className="block font-medium">{item.customer_name}</span><span className="text-xs text-muted-foreground">{item.device_model}</span></TableCell>
                    <TableCell dir="ltr" className="text-right tabular-nums">{item.raw_identifier || "—"}</TableCell>
                    <TableCell><Badge variant="secondary">{stageNames[item.stage] ?? item.stage}</Badge></TableCell>
                    <TableCell>{item.received_at ? "ثبت‌شده" : "در انتظار"}</TableCell>
                    <TableCell>{formatJalaliDateTime(item.created_at)}</TableCell>
                  </TableRow>
                ))}</TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
      {totalPages > 1 && (
        <nav aria-label="صفحه‌بندی پرونده‌های تعمیر" className="flex items-center justify-between text-sm">
          {page > 1 ? <Link className="text-primary underline-offset-4 hover:underline" href={`/${orgId}/repairs?page=${page - 1}`}>صفحهٔ قبل</Link> : <span />}
          <span>صفحهٔ {Math.min(page, totalPages)} از {totalPages}</span>
          {page < totalPages ? <Link className="text-primary underline-offset-4 hover:underline" href={`/${orgId}/repairs?page=${page + 1}`}>صفحهٔ بعد</Link> : <span />}
        </nav>
      )}
    </div>
  );
}
