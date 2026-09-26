"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairPlanApprovalAction, saveRepairActionPlanAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

type Route = "repair" | "replacement" | "return";
type Plan = { id: string; revision: number; route: string; scope: string; financial_basis: string;
  amount_irr: number; parts_strategy: string | null; replacement_model: string | null;
  replacement_reason: string | null; original_disposition: string | null };
type Approval = { id: string; kind: string; decision: string; recorded_at: string };

const routeNames: Record<Route, string> = { repair: "تعمیر", replacement: "تعویض", return: "عودت بدون تعمیر" };
const basisNames: Record<string, string> = { warranty: "گارانتی؛ مبلغ صفر", customer_paid: "پرداخت مشتری", none: "بدون هزینهٔ اقدام" };
const reasonNames: Record<string, string> = { irreparable: "غیرقابل تعمیر", uneconomical: "تعمیر غیراقتصادی", policy: "طبق سیاست خدمت", other: "سایر" };
const dispositionNames: Record<string, string> = { return_to_customer: "بازگشت دستگاه قبلی به مشتری", scrap_proposed: "پیشنهاد اسقاط", refurbish_proposed: "پیشنهاد بازسازی", parts_proposed: "پیشنهاد داغی" };
function localDateTimeNow() {
  const date = new Date();
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset());
  return date.toISOString().slice(0, 16);
}

export function DecisionPanel({ orgId, caseId, expectedVersion, route, diagnosisCoverage,
  latest, approvals, canRecord, canRecordCustomer, canApproveReplacement }: {
  orgId: string; caseId: string; expectedVersion: number; route: Route; diagnosisCoverage: string;
  latest: Plan | null; approvals: Approval[]; canRecord: boolean;
  canRecordCustomer: boolean; canApproveReplacement: boolean;
}) {
  const router = useRouter();
  const planKey = useRef<string | null>(null);
  const approvalKey = useRef<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [approvalError, setApprovalError] = useState("");
  const [replacementDecision, setReplacementDecision] = useState<"approved" | "rejected" | null>(null);
  const [form, setForm] = useState({
    scope: latest?.scope ?? "",
    financialBasis: latest?.financial_basis ?? (route === "return" ? "none" : ""),
    amountIrr: latest?.amount_irr ? String(latest.amount_irr) : "0",
    partsStrategy: latest?.parts_strategy ?? "",
    replacementModel: latest?.replacement_model ?? "",
    replacementReason: latest?.replacement_reason ?? "",
    originalDisposition: latest?.original_disposition ?? "",
  });
  const [customer, setCustomer] = useState({ decision: "approved", channel: "", subjectName: "",
    subjectRole: "owner", evidenceReference: "", authorityReference: "", statedAt: localDateTimeNow() });
  const customerLatest = approvals.find((item) => item.kind === "customer");
  const replacementLatest = approvals.find((item) => item.kind === "replacement");
  const customerRequired = latest?.route === "replacement" || latest?.financial_basis === "customer_paid";
  const basisResolved = latest?.financial_basis === "warranty" ? diagnosisCoverage === "covered"
    : latest?.financial_basis === "customer_paid" ? diagnosisCoverage === "not_covered" : true;

  function changePlan(name: keyof typeof form, value: string) {
    planKey.current = null;
    setForm((previous) => ({ ...previous, [name]: value }));
  }
  async function savePlan(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setError("");
    const amount = Number(form.amountIrr);
    if (!Number.isSafeInteger(amount) || amount < 0) { setError("مبلغ را به ریال و به‌صورت عدد صحیح وارد کنید."); return; }
    setPending(true);
    planKey.current ??= crypto.randomUUID();
    try {
      const result = await saveRepairActionPlanAction({ orgId, caseId, expectedVersion,
        idempotencyKey: planKey.current, route, scope: form.scope,
        financialBasis: form.financialBasis, amountIrr: amount,
        partsStrategy: route === "repair" ? form.partsStrategy || null : null,
        replacementModel: route === "replacement" ? form.replacementModel : "",
        replacementReason: route === "replacement" ? form.replacementReason || null : null,
        originalDisposition: route === "replacement" ? form.originalDisposition || null : null });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  async function recordCustomer(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!latest || pending) return;
    setApprovalError("");
    const statedAt = new Date(customer.statedAt);
    if (Number.isNaN(statedAt.getTime())) { setApprovalError("زمان اعلام مشتری معتبر نیست."); return; }
    setPending(true);
    approvalKey.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairPlanApprovalAction({ orgId, caseId, planId: latest.id,
        expectedVersion, idempotencyKey: approvalKey.current, kind: "customer",
        decision: customer.decision, channel: customer.channel || null,
        subjectName: customer.subjectName, subjectRole: customer.subjectRole,
        evidenceReference: customer.evidenceReference, authorityReference: customer.authorityReference,
        statedAt: statedAt.toISOString() });
      if (result.error) { setApprovalError(result.error); return; }
      approvalKey.current = null;
      router.refresh();
    } catch { setApprovalError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  async function recordReplacement() {
    if (!latest || !replacementDecision || pending) return;
    setApprovalError("");
    setPending(true);
    approvalKey.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairPlanApprovalAction({ orgId, caseId, planId: latest.id,
        expectedVersion, idempotencyKey: approvalKey.current, kind: "replacement",
        decision: replacementDecision, channel: null, subjectName: "", subjectRole: null,
        evidenceReference: "", authorityReference: "", statedAt: null });
      if (result.error) { setApprovalError(result.error); return; }
      approvalKey.current = null;
      setReplacementDecision(null);
      router.refresh();
    } catch { setApprovalError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  return <>
    <Card><CardHeader><CardTitle>برنامهٔ اقدام · {routeNames[route]}</CardTitle></CardHeader><CardContent className="grid gap-4">
      {latest ? <div className="rounded-xl border border-border/70 p-3 text-sm">
        <p className="font-medium">نسخهٔ {latest.revision} · {basisNames[latest.financial_basis]} · {latest.amount_irr.toLocaleString("fa-IR")} ریال</p>
        <p className="mt-2 whitespace-pre-wrap">{latest.scope}</p>
        {latest.route === "repair" && <p className="mt-2 text-muted-foreground">قطعات: {latest.parts_strategy === "no_parts" ? "نیاز ندارد" : "نیازمند قطعه و برنامهٔ تأمین"}</p>}
        {latest.route === "replacement" && <p className="mt-2 text-muted-foreground">مدل جایگزین پیشنهادی: {latest.replacement_model} · علت: {reasonNames[latest.replacement_reason ?? ""]} · دستگاه قبلی: {dispositionNames[latest.original_disposition ?? ""]}</p>}
      </div> : <p className="text-sm text-muted-foreground">هنوز برنامه‌ای برای تصمیم ثبت نشده است.</p>}
      {canRecord && <form onSubmit={savePlan} className="grid gap-4">
        <div className="grid gap-2"><Label htmlFor="plan-scope">شرح برنامه و دامنهٔ اقدام</Label><Textarea id="plan-scope" required maxLength={3000} value={form.scope} onChange={(e) => changePlan("scope", e.target.value)} /></div>
        {route !== "return" && <div className="grid gap-4 sm:grid-cols-2">
          <div className="grid gap-2"><Label htmlFor="plan-basis">مبنای مالی</Label><select id="plan-basis" required className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.financialBasis} onChange={(e) => changePlan("financialBasis", e.target.value)}><option value="">انتخاب کنید</option><option value="warranty">گارانتی؛ رایگان</option><option value="customer_paid">پرداخت مشتری</option></select></div>
          <div className="grid gap-2"><Label htmlFor="plan-amount">مبلغ نهایی · ریال</Label><Input id="plan-amount" dir="ltr" inputMode="numeric" pattern="[0-9]+" required value={form.amountIrr} onChange={(e) => changePlan("amountIrr", e.target.value)} /></div>
        </div>}
        {route === "repair" && <div className="grid gap-2"><Label htmlFor="plan-parts">نیاز به قطعه</Label><select id="plan-parts" required className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.partsStrategy} onChange={(e) => changePlan("partsStrategy", e.target.value)}><option value="">انتخاب کنید</option><option value="no_parts">بدون نیاز به قطعه</option><option value="requires_parts">نیازمند قطعه / برنامهٔ تأمین</option></select></div>}
        {route === "replacement" && <div className="grid gap-4 sm:grid-cols-2">
          <div className="grid gap-2"><Label htmlFor="plan-replacement-model">مدل جایگزین پیشنهادی</Label><Input id="plan-replacement-model" required maxLength={160} value={form.replacementModel} onChange={(e) => changePlan("replacementModel", e.target.value)} /></div>
          <div className="grid gap-2"><Label htmlFor="plan-reason">علت تعویض</Label><select id="plan-reason" required className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.replacementReason} onChange={(e) => changePlan("replacementReason", e.target.value)}><option value="">انتخاب کنید</option>{Object.entries(reasonNames).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></div>
          <div className="grid gap-2 sm:col-span-2"><Label htmlFor="plan-disposition">پیشنهاد تعیین تکلیف دستگاه قبلی</Label><select id="plan-disposition" required className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.originalDisposition} onChange={(e) => changePlan("originalDisposition", e.target.value)}><option value="">انتخاب کنید</option>{Object.entries(dispositionNames).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></div>
        </div>}
        {diagnosisCoverage === "pending" && route !== "return" && <p className="text-sm text-muted-foreground">پوشش این خرابی هنوز در انتظار تعیین است؛ ثبت برنامه به معنی تأیید شروع اقدام نیست.</p>}
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <div className="flex justify-end"><Button disabled={pending} type="submit">{pending ? "در حال ثبت…" : "ثبت نسخهٔ برنامه"}</Button></div>
      </form>}
    </CardContent></Card>

    {latest && <Card><CardHeader><CardTitle>تأییدهای مستقل · نسخهٔ {latest.revision}</CardTitle></CardHeader><CardContent className="grid gap-5">
      <div className="rounded-xl border border-border/70 p-3 text-sm"><p className="font-medium">پاسخ مشتری: {customerLatest ? customerLatest.decision === "approved" ? "تأیید شده" : "رد شده" : "ثبت نشده"}{!customerRequired ? " · برای این مسیر الزامی نیست" : ""}</p><p className="mt-1 text-muted-foreground">پاسخ به همین نسخهٔ برنامه و مبلغ {latest.amount_irr.toLocaleString("fa-IR")} ریال مربوط است.</p></div>
      {canRecordCustomer && <form onSubmit={recordCustomer} className="grid gap-3 border-t border-border/70 pt-4 sm:grid-cols-2">
        <div className="grid gap-2"><Label htmlFor="customer-decision">نتیجهٔ اعلام مشتری</Label><select id="customer-decision" className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={customer.decision} onChange={(e) => { approvalKey.current = null; setCustomer((old) => ({ ...old, decision: e.target.value })); }}><option value="approved">تأیید</option><option value="rejected">رد</option></select></div>
        <div className="grid gap-2"><Label htmlFor="customer-channel">روش اعلام</Label><select id="customer-channel" required className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={customer.channel} onChange={(e) => { approvalKey.current = null; setCustomer((old) => ({ ...old, channel: e.target.value })); }}><option value="">انتخاب کنید</option><option value="phone">تلفنی</option><option value="message">پیامک</option><option value="chat">چت</option><option value="in_person">حضوری</option><option value="agency">نمایندگی</option><option value="other">سایر</option></select></div>
        <div className="grid gap-2"><Label htmlFor="customer-name">نام اعلام‌کننده</Label><Input id="customer-name" required maxLength={160} value={customer.subjectName} onChange={(e) => { approvalKey.current = null; setCustomer((old) => ({ ...old, subjectName: e.target.value })); }} /></div>
        <div className="grid gap-2"><Label htmlFor="customer-role">سمت اعلام‌کننده</Label><select id="customer-role" className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={customer.subjectRole} onChange={(e) => { approvalKey.current = null; setCustomer((old) => ({ ...old, subjectRole: e.target.value })); }}><option value="owner">مالک / مشتری</option><option value="authorized_representative">نمایندهٔ دارای اختیار</option></select></div>
        <div className="grid gap-2"><Label htmlFor="customer-reference">مرجع اعلام</Label><Input id="customer-reference" required maxLength={240} value={customer.evidenceReference} onChange={(e) => { approvalKey.current = null; setCustomer((old) => ({ ...old, evidenceReference: e.target.value })); }} /></div>
        {customer.subjectRole === "authorized_representative" && <div className="grid gap-2"><Label htmlFor="customer-authority">مرجع اختیار نمایندگی</Label><Input id="customer-authority" required maxLength={240} value={customer.authorityReference} onChange={(e) => { approvalKey.current = null; setCustomer((old) => ({ ...old, authorityReference: e.target.value })); }} /></div>}
        <div className="grid gap-2"><Label htmlFor="customer-stated-at">زمان اعلام مشتری</Label><Input id="customer-stated-at" type="datetime-local" required value={customer.statedAt} onChange={(e) => { approvalKey.current = null; setCustomer((old) => ({ ...old, statedAt: e.target.value })); }} /></div>
        <div className="flex items-end justify-end sm:col-span-2"><Button disabled={pending} type="submit">{pending ? "در حال ثبت…" : "ثبت پاسخ مشتری"}</Button></div>
      </form>}
      {latest.route === "replacement" && <div className="grid gap-3 border-t border-border/70 pt-4 text-sm"><p className="font-medium">مصوبهٔ تعویض: {replacementLatest ? replacementLatest.decision === "approved" ? "تأیید شده" : "رد شده" : "ثبت نشده"}</p><p className="text-muted-foreground">دارندهٔ مجوز مستقل تأیید تعویض می‌تواند همان شخصِ ثبت‌کنندهٔ برنامه باشد. این مصوبه، تعویض فیزیکی یا برداشت از انبار نیست.</p>{canApproveReplacement && <div className="flex flex-wrap gap-2"><Button type="button" disabled={pending} onClick={() => { approvalKey.current = null; setApprovalError(""); setReplacementDecision("approved"); }}>تأیید تعویض</Button><Button type="button" variant="outline" disabled={pending} onClick={() => { approvalKey.current = null; setApprovalError(""); setReplacementDecision("rejected"); }}>رد تعویض</Button></div>}</div>}
      {approvalError && <p role="alert" className="text-sm text-destructive">{approvalError}</p>}
    </CardContent></Card>}

    {latest && <Card><CardHeader><CardTitle>پیش‌نیازهای گام بعد</CardTitle></CardHeader><CardContent className="grid gap-2 text-sm">
      <p>مبنای مالی و پوشش: {basisResolved ? "هماهنگ" : "نیازمند تعیین یا اصلاح تشخیص"}</p>
      {customerRequired && <p>رضایت مشتری برای همین نسخه: {customerLatest?.decision === "approved" ? "ثبت‌شده" : "ناقص"}</p>}
      {latest.route === "replacement" && <p>مصوبهٔ مستقل تعویض: {replacementLatest?.decision === "approved" ? "ثبت‌شده" : "ناقص"}</p>}
      {latest.route === "repair" && <p>وضعیت قطعه: {latest.parts_strategy === "no_parts" ? "بدون قطعه در برنامه" : "نیازمند کنترل تأمین و موجودی"}</p>}
      <p className="text-muted-foreground">ارجاع مسیر آماده از بخش «ادامهٔ فرایند» انجام می‌شود. برای تعمیرِ نیازمند قطعه، همهٔ قطعات برنامهٔ جاری را در بخش تأمین قطعات ثبت و رزرو کنید. برای عودت، اطلاع‌رسانی و مجوز مستقل را در بخش بعد ثبت کنید؛ اجرای کنترل خروج و تحویل دستگاه مراحل جداگانه‌اند.</p>
    </CardContent></Card>}

    <Dialog open={replacementDecision !== null} onOpenChange={(open) => { if (!open && !pending) setReplacementDecision(null); }}>
      <DialogContent showCloseButton={false}><DialogHeader><DialogTitle>{replacementDecision === "approved" ? "تأیید برنامهٔ تعویض؟" : "رد برنامهٔ تعویض؟"}</DialogTitle><DialogDescription>این تصمیم فقط برای نسخهٔ {latest?.revision} برنامه و مبلغ {latest?.amount_irr.toLocaleString("fa-IR")} ریال ثبت می‌شود.</DialogDescription></DialogHeader>{approvalError && <p role="alert" className="text-sm text-destructive">{approvalError}</p>}<DialogFooter><Button variant="outline" disabled={pending} onClick={() => setReplacementDecision(null)}>انصراف</Button><Button disabled={pending} onClick={recordReplacement}>{pending ? "در حال ثبت…" : "تأیید"}</Button></DialogFooter></DialogContent>
    </Dialog>
  </>;
}
