"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairPaymentEvidenceAction, verifyRepairPaymentEvidenceAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

type Payment = {
  id: string; amount_irr: number; method: string; external_reference: string;
  evidence_reference: string; recorded_at: string;
};
type Verification = { payment_id: string; verification_reference: string };
const methodNames: Record<string, string> = { card: "کارت", bank_transfer: "حوالهٔ بانکی", cash: "نقد" };

export function RepairPaymentPanel({ orgId, caseId, expectedVersion, planAmount, payments, verifications,
  canRecord, canVerify }: {
  orgId: string; caseId: string; expectedVersion: number; planAmount: number;
  payments: Payment[]; verifications: Verification[]; canRecord: boolean; canVerify: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const verificationKey = useRef<string | null>(null);
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState<"card" | "bank_transfer" | "cash">("card");
  const [externalReference, setExternalReference] = useState("");
  const [evidenceReference, setEvidenceReference] = useState("");
  const [verificationReference, setVerificationReference] = useState<Record<string, string>>({});
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const verified = new Set(verifications.map((item) => item.payment_id));
  const confirmed = payments.reduce((sum, payment) => sum + (verified.has(payment.id) ? payment.amount_irr : 0), 0);
  const remaining = Math.max(0, planAmount - confirmed);
  async function record(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairPaymentEvidenceAction({ orgId, caseId, expectedVersion,
        idempotencyKey: key.current, amountIrr: Number(amount), method, externalReference, evidenceReference });
      if (result.error) { setError(result.error); return; }
      key.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  async function verify(paymentId: string) {
    if (pending) return;
    setPending(true); setError(""); verificationKey.current ??= crypto.randomUUID();
    try {
      const result = await verifyRepairPaymentEvidenceAction({ orgId, caseId, paymentId, expectedVersion,
        idempotencyKey: verificationKey.current, verificationReference: verificationReference[paymentId] ?? "" });
      if (result.error) { setError(result.error); return; }
      verificationKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  return <Card><CardHeader><CardTitle>اسناد پرداخت برنامهٔ جاری</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">مبلغ برنامه: {planAmount.toLocaleString("fa-IR")} ریال · تطبیق‌شده: {confirmed.toLocaleString("fa-IR")} ریال · مانده: {remaining.toLocaleString("fa-IR")} ریال</p>
    <p className="text-muted-foreground">ثبت سند، دریافت وجه را تأیید نمی‌کند. هر سند با مجوز مستقل و مرجع تطبیق بررسی می‌شود. تکمیل مبلغ هنوز مجوز انتقال به تحویل نیست.</p>
    {payments.map((payment) => <div key={payment.id} className="rounded-xl border border-border/70 p-3">
      <p className="font-medium">{payment.amount_irr.toLocaleString("fa-IR")} ریال · {methodNames[payment.method] ?? payment.method} · {verified.has(payment.id) ? "تطبیق‌شده" : "منتظر تطبیق"}</p>
      <p>مرجع تراکنش: {payment.external_reference} · شاهد: {payment.evidence_reference}</p>
      {!verified.has(payment.id) && canVerify && <div className="mt-2 flex flex-wrap items-center gap-2">
        <Input className="max-w-xs" aria-label="مرجع تطبیق پرداخت" placeholder="مرجع تطبیق حساب" maxLength={160}
          value={verificationReference[payment.id] ?? ""}
          onChange={(event) => { verificationKey.current = null; setVerificationReference({ ...verificationReference, [payment.id]: event.target.value }); }} />
        <Button type="button" disabled={pending || !verificationReference[payment.id]?.trim()} onClick={() => verify(payment.id)}>تأیید تطبیق</Button>
      </div>}
      {!verified.has(payment.id) && !canVerify && <p className="text-muted-foreground">مجوز مستقل تطبیق پرداخت لازم است.</p>}
    </div>)}
    {canRecord && <form onSubmit={record} className="grid gap-2 rounded-xl border border-border/70 p-3">
      <p className="font-medium">ثبت سند جدید</p>
      <Input required type="number" min="1" max={planAmount} step="1" inputMode="numeric" aria-label="مبلغ ریال"
        placeholder="مبلغ به ریال" value={amount} onChange={(event) => { key.current = null; setAmount(event.target.value); }} />
      <select className="h-10 rounded-md border border-input bg-background px-3" aria-label="روش پرداخت" value={method}
        onChange={(event) => { key.current = null; setMethod(event.target.value as typeof method); }}>
        <option value="card">کارت</option><option value="bank_transfer">حوالهٔ بانکی</option><option value="cash">نقد</option>
      </select>
      <Input required maxLength={160} aria-label="مرجع تراکنش" placeholder="شناسهٔ تراکنش یا شمارهٔ رسید"
        value={externalReference} onChange={(event) => { key.current = null; setExternalReference(event.target.value); }} />
      <Input required maxLength={500} aria-label="مرجع شاهد پرداخت" placeholder="مرجع سند بانکی یا رسید"
        value={evidenceReference} onChange={(event) => { key.current = null; setEvidenceReference(event.target.value); }} />
      <Button type="submit" disabled={pending} className="justify-self-start">ثبت سند پرداخت</Button>
    </form>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
