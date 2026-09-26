"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { correctRepairPaymentEvidenceAction, recordRepairPaymentEvidenceAction, verifyRepairPaymentEvidenceAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

type Payment = {
  id: string; amount_irr: number; method: string; external_reference: string;
  evidence_reference: string; recorded_at: string;
};
type Verification = { payment_id: string; verification_reference: string };
type Correction = { payment_id: string; reason: string; explanation: string; correction_reference: string; evidence_reference: string; corrected_at: string };
const methodNames: Record<string, string> = { card: "کارت", bank_transfer: "حوالهٔ بانکی", cash: "نقد" };
const reasonNames: Record<string, string> = { duplicate: "سند تکراری", not_received: "وجه دریافت نشده", incorrect_details: "مشخصات سند نادرست" };

export function RepairPaymentPanel({ orgId, caseId, expectedVersion, planAmount, payments, verifications, corrections, approvedCreditAmount,
  canRecord, canVerify, canCorrect }: {
  orgId: string; caseId: string; expectedVersion: number; planAmount: number;
  payments: Payment[]; verifications: Verification[]; corrections: Correction[]; approvedCreditAmount: number;
  canRecord: boolean; canVerify: boolean; canCorrect: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const verificationKey = useRef<string | null>(null);
  const correctionKey = useRef<string | null>(null);
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState<"card" | "bank_transfer" | "cash">("card");
  const [externalReference, setExternalReference] = useState("");
  const [evidenceReference, setEvidenceReference] = useState("");
  const [verificationReference, setVerificationReference] = useState<Record<string, string>>({});
  const [correctionReason, setCorrectionReason] = useState<Record<string, "duplicate" | "not_received" | "incorrect_details">>({});
  const [correctionExplanation, setCorrectionExplanation] = useState<Record<string, string>>({});
  const [correctionReference, setCorrectionReference] = useState<Record<string, string>>({});
  const [correctionEvidence, setCorrectionEvidence] = useState<Record<string, string>>({});
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const verified = new Set(verifications.map((item) => item.payment_id));
  const correctionByPayment = new Map(corrections.map((item) => [item.payment_id, item]));
  const confirmed = payments.reduce((sum, payment) => sum + (verified.has(payment.id) && !correctionByPayment.has(payment.id) ? payment.amount_irr : 0), 0);
  const remaining = Math.max(0, planAmount - confirmed - approvedCreditAmount);
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
  async function correct(event: React.FormEvent<HTMLFormElement>, paymentId: string) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); correctionKey.current ??= crypto.randomUUID();
    try {
      const result = await correctRepairPaymentEvidenceAction({ orgId, caseId, paymentId, expectedVersion,
        idempotencyKey: correctionKey.current, reason: correctionReason[paymentId] ?? "incorrect_details",
        explanation: correctionExplanation[paymentId] ?? "", correctionReference: correctionReference[paymentId] ?? "",
        evidenceReference: correctionEvidence[paymentId] ?? "" });
      if (result.error) { setError(result.error); return; }
      correctionKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  return <Card><CardHeader><CardTitle>اسناد پرداخت برنامهٔ جاری</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">مبلغ برنامه: {planAmount.toLocaleString("fa-IR")} ریال · پرداخت تطبیق‌شده: {confirmed.toLocaleString("fa-IR")} ریال · اعتبار منتقل‌شده: {approvedCreditAmount.toLocaleString("fa-IR")} ریال · مانده: {remaining.toLocaleString("fa-IR")} ریال</p>
    <p className="text-muted-foreground">ثبت سند، دریافت وجه را تأیید نمی‌کند. هر سند با مجوز مستقل و مرجع تطبیق بررسی می‌شود. اصلاح سند اشتباه از محاسبهٔ مانده کسر می‌شود و به معنای استرداد وجه نیست.</p>
    {payments.map((payment) => <div key={payment.id} className="rounded-xl border border-border/70 p-3">
      <p className="font-medium">{payment.amount_irr.toLocaleString("fa-IR")} ریال · {methodNames[payment.method] ?? payment.method} · {correctionByPayment.has(payment.id) ? "اصلاح‌شده / خارج از محاسبه" : verified.has(payment.id) ? "تطبیق‌شده" : "منتظر تطبیق"}</p>
      <p>مرجع تراکنش: {payment.external_reference} · شاهد: {payment.evidence_reference}</p>
      {correctionByPayment.has(payment.id) && <p className="mt-2 text-muted-foreground">علت اصلاح: {reasonNames[correctionByPayment.get(payment.id)!.reason]} · {correctionByPayment.get(payment.id)!.explanation} · مرجع: {correctionByPayment.get(payment.id)!.correction_reference} · شاهد: {correctionByPayment.get(payment.id)!.evidence_reference}</p>}
      {!verified.has(payment.id) && !correctionByPayment.has(payment.id) && canVerify && <div className="mt-2 flex flex-wrap items-center gap-2">
        <Input className="max-w-xs" aria-label="مرجع تطبیق پرداخت" placeholder="مرجع تطبیق حساب" maxLength={160}
          value={verificationReference[payment.id] ?? ""}
          onChange={(event) => { verificationKey.current = null; setVerificationReference({ ...verificationReference, [payment.id]: event.target.value }); }} />
        <Button type="button" disabled={pending || !verificationReference[payment.id]?.trim()} onClick={() => verify(payment.id)}>تأیید تطبیق</Button>
      </div>}
      {!verified.has(payment.id) && !correctionByPayment.has(payment.id) && !canVerify && <p className="text-muted-foreground">مجوز مستقل تطبیق پرداخت لازم است.</p>}
      {!correctionByPayment.has(payment.id) && canCorrect && <details className="mt-3 border-t border-border/70 pt-3">
        <summary className="cursor-pointer font-medium">اصلاح سند اشتباه</summary>
        <form onSubmit={(event) => correct(event, payment.id)} className="mt-3 grid gap-2">
        <select className="h-10 rounded-md border border-input bg-background px-3" aria-label="علت اصلاح سند" value={correctionReason[payment.id] ?? "incorrect_details"}
          onChange={(event) => { correctionKey.current = null; setCorrectionReason({ ...correctionReason, [payment.id]: event.target.value as typeof correctionReason[string] }); }}>
          <option value="incorrect_details">مشخصات سند نادرست</option><option value="duplicate">سند تکراری</option><option value="not_received">وجه دریافت نشده</option>
        </select>
        <Input required minLength={5} maxLength={1000} aria-label="شرح اصلاح سند" placeholder="شرح اشتباه (حداقل ۵ حرف)"
          value={correctionExplanation[payment.id] ?? ""} onChange={(event) => { correctionKey.current = null; setCorrectionExplanation({ ...correctionExplanation, [payment.id]: event.target.value }); }} />
        <Input required maxLength={160} aria-label="مرجع اصلاح سند" placeholder="شناسهٔ یکتای اصلاح"
          value={correctionReference[payment.id] ?? ""} onChange={(event) => { correctionKey.current = null; setCorrectionReference({ ...correctionReference, [payment.id]: event.target.value }); }} />
        <Input required maxLength={500} aria-label="شاهد اصلاح سند" placeholder="مرجع سند یا بررسی مالی"
          value={correctionEvidence[payment.id] ?? ""} onChange={(event) => { correctionKey.current = null; setCorrectionEvidence({ ...correctionEvidence, [payment.id]: event.target.value }); }} />
        <Button type="submit" variant="outline" disabled={pending} className="justify-self-start">ثبت اصلاح و خروج از محاسبه</Button>
        </form>
      </details>}
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
