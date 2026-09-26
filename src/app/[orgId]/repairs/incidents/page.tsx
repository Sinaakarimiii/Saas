import Link from "next/link";
import { redirect } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getOrgContext } from "@/lib/org-context";
import { PERMISSIONS } from "@/lib/permissions";
import { formatIncidentDueAt, incidentQueueNow } from "@/lib/repair-incident-queue";
import { createClient } from "@/lib/supabase/server";

const kinds: Record<string, string> = {
  lost: "مفقودی",
  damage: "آسیب‌دیدگی",
  delivery_discrepancy: "اختلاف تحویل",
};

export default async function DeliveryIncidentQueuePage({ params, searchParams }: PageProps<"/[orgId]/repairs/incidents">) {
  const { orgId } = await params;
  const query = await searchParams;
  const ctx = await getOrgContext(orgId);
  if (!ctx.can(PERMISSIONS.REPAIR_CASE_VIEW)) redirect(`/${orgId}/dashboard`);

  const requestedPage = typeof query.page === "string" ? Number(query.page) : 1;
  const page = Number.isSafeInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
  const mine = query.mine === "1";
  const pageSize = 30;
  const supabase = await createClient();
  let incidentsQuery = supabase.from("repair_delivery_incidents")
    .select("id, case_id, kind, reference, due_at, responsible_user_id, repair_cases(tracking_code, customer_name)", { count: "exact" })
    .eq("org_id", orgId).eq("status", "open");
  if (mine) incidentsQuery = incidentsQuery.eq("responsible_user_id", ctx.user.id);
  const { data: incidents, count, error } = await incidentsQuery
    .order("due_at", { ascending: true }).order("id", { ascending: true })
    .range((page - 1) * pageSize, page * pageSize - 1);
  if (error) throw new Error("Could not load delivery incident queue", { cause: error });

  const responsibleIds = [...new Set((incidents ?? []).map((item) => item.responsible_user_id))];
  const { data: members, error: membersError } = responsibleIds.length
    ? await supabase.from("org_members").select("user_id, profiles(full_name, email)")
      .eq("org_id", orgId).in("user_id", responsibleIds)
    : { data: [], error: null };
  if (membersError) throw new Error("Could not load incident owners", { cause: membersError });
  const memberNames = new Map((members ?? []).map((member) => [member.user_id,
    member.profiles?.full_name || member.profiles?.email || "عضو سازمان"]));
  const totalPages = Math.max(1, Math.ceil((count ?? 0) / pageSize));
  const now = incidentQueueNow();
  const queueUrl = (targetPage: number) => `/${orgId}/repairs/incidents?${mine ? "mine=1&" : ""}page=${targetPage}`;

  return <div className="mx-auto flex w-full max-w-6xl flex-col gap-5">
    <div>
      <Link className="text-sm text-primary underline-offset-4 hover:underline" href={`/${orgId}/repairs`}>بازگشت به پرونده‌ها</Link>
      <h1 className="mt-2 text-2xl font-semibold">صف پیگیری مسائل حمل</h1>
      <p className="mt-1 text-sm text-muted-foreground">موارد بازِ پرونده‌های قابل مشاهده در کل سازمان، به ترتیب نزدیک‌ترین موعد؛ موعدهای گذشته در ابتدا هستند. ساعت‌ها به وقت تهران‌اند.</p>
    </div>
    <nav aria-label="فیلتر مسئول مسئلهٔ حمل" className="flex flex-wrap gap-2 text-sm">
      <Link aria-current={!mine ? "page" : undefined} className={`rounded-lg border px-3 py-2 ${!mine ? "bg-primary text-primary-foreground" : "border-border/70 hover:bg-muted/50"}`} href={`/${orgId}/repairs/incidents`}>همهٔ موارد</Link>
      <Link aria-current={mine ? "page" : undefined} className={`rounded-lg border px-3 py-2 ${mine ? "bg-primary text-primary-foreground" : "border-border/70 hover:bg-muted/50"}`} href={`/${orgId}/repairs/incidents?mine=1`}>موارد من</Link>
    </nav>
    <Card><CardContent>
      <p className="mb-3 text-sm text-muted-foreground">{count ?? 0} مسئلهٔ باز</p>
      {(incidents ?? []).length === 0 ? <p className="py-10 text-center text-sm text-muted-foreground">در این صف مسئلهٔ باز وجود ندارد.</p> :
        <div className="overflow-x-auto"><Table>
          <TableHeader><TableRow>
            <TableHead>وضعیت موعد</TableHead><TableHead>پرونده</TableHead><TableHead>نوع و مرجع</TableHead>
            <TableHead>مسئول</TableHead><TableHead>موعد به وقت تهران</TableHead><TableHead>اقدام</TableHead>
          </TableRow></TableHeader>
          <TableBody>{incidents?.map((item) => {
            const overdue = new Date(item.due_at).getTime() < now;
            return <TableRow key={item.id}>
              <TableCell><Badge variant={overdue ? "destructive" : "secondary"}>{overdue ? "سررسیدگذشته" : "پیش رو"}</Badge></TableCell>
              <TableCell><span className="block font-medium">{item.repair_cases?.tracking_code}</span><span className="text-xs text-muted-foreground">{item.repair_cases?.customer_name}</span></TableCell>
              <TableCell>{kinds[item.kind] ?? item.kind}<span className="block text-xs text-muted-foreground">{item.reference}</span></TableCell>
              <TableCell>{item.responsible_user_id === ctx.user.id ? "من" : memberNames.get(item.responsible_user_id) ?? "عضو سازمان"}</TableCell>
              <TableCell><time dateTime={item.due_at}>{formatIncidentDueAt(item.due_at)}</time></TableCell>
              <TableCell><Link className="text-primary underline-offset-4 hover:underline" href={`/${orgId}/repairs/${item.case_id}#delivery-incidents`}>{ctx.can(PERMISSIONS.REPAIR_DELIVERY_INCIDENT_FOLLOWUP) ? "ثبت پیگیری در پرونده" : "مشاهدهٔ پرونده"}</Link></TableCell>
            </TableRow>;
          })}</TableBody>
        </Table></div>}
    </CardContent></Card>
    {totalPages > 1 && <nav aria-label="صفحه‌بندی مسائل حمل" className="flex items-center justify-between text-sm">
      {page > 1 ? <Link className="text-primary underline-offset-4 hover:underline" href={queueUrl(page - 1)}>صفحهٔ قبل</Link> : <span />}
      <span>صفحهٔ {Math.min(page, totalPages)} از {totalPages}</span>
      {page < totalPages ? <Link className="text-primary underline-offset-4 hover:underline" href={queueUrl(page + 1)}>صفحهٔ بعد</Link> : <span />}
    </nav>}
  </div>;
}
