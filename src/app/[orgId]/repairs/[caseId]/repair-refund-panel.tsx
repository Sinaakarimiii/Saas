"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { approveRepairPaymentRefundAction, requestRepairPaymentRefundAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

type Payment = { id: string; plan_id: string; amount_irr: number; external_reference: string };
type Refund = {
  id: string; source_payment_id: string; amount_irr: number; reason: string;
  request_reference: string; requested_by: string; requested_at: string;
  outbound_method: string | null; outbound_reference: string | null; outbound_evidence: string | null;
  approval_reference: string | null; approved_by: string | null; approved_at: string | null;
};
const methodNames: Record<string, string> = {
  bank_transfer: "حوالهٔ بانکی", card_reversal: "برگشت تراکنش کارت", cash: "نقد",
};

export function RepairRefundPanel({ orgId, caseId, currentUserId, expectedVersion, payments,
  verifications, corrections, transfers, refunds, canRequest, canApprove }: {
  orgId: string; caseId: string; currentUserId: string; expectedVersion: number;
  payments: Payment[]; verifications: { payment_id: string }[];
  corrections: { payment_id: string }[];
  transfers: { source_payment_id: string; amount_irr: number; approved_at: string | null }[];
  refunds: Refund[]; canRequest: boolean; canApprove: boolean;
}) {
  const router = useRouter();
  const requestKey = useRef<string | null>(null);
  const approvalKey = useRef<string | null>(null);
  const [sourcePaymentId, setSourcePaymentId] = useState("");
  const [amountIrr, setAmountIrr] = useState("");
  const [reason, setReason] = useState("");
  const [requestReference, setRequestReference] = useState("");
  const [approvalInputs, setApprovalInputs] = useState<Record<string, {
    method: "bank_transfer" | "card_reversal" | "cash"; outboundReference: string;
    outboundEvidence: string; approvalReference: string;
  }>>({});
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const verified = new Set(verifications.map((item) => item.payment_id));
  const corrected = new Set(corrections.map((item) => item.payment_id));
  const availablePayments = payments.map((payment) => ({
    ...payment,
    available: payment.amount_irr
      - transfers.reduce((sum, transfer) => sum + (transfer.source_payment_id === payment.id && transfer.approved_at ? transfer.amount_irr : 0), 0)
      - refunds.reduce((sum, refund) => sum + (refund.source_payment_id === payment.id && refund.approved_at ? refund.amount_irr : 0), 0),
  })).filter((payment) => verified.has(payment.id) && !corrected.has(payment.id) && payment.available > 0);

  async function request(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); requestKey.current ??= crypto.randomUUID();
    try {
      const result = await requestRepairPaymentRefundAction({ orgId, caseId, sourcePaymentId,
        expectedVersion, idempotencyKey: requestKey.current, amountIrr: Number(amountIrr), reason, requestReference });
      if (result.error) { setError(result.error); return; }
      requestKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  async function approve(refundId: string) {
    if (pending) return;
    const input = approvalInputs[refundId];
    if (!input) return;
    setPending(true); setError(""); approvalKey.current ??= crypto.randomUUID();
    try {
      const result = await approveRepairPaymentRefundAction({ orgId, caseId, refundId, expectedVersion,
        idempotencyKey: approvalKey.current, outboundMethod: input.method,
        outboundReference: input.outboundReference, outboundEvidence: input.outboundEvidence,
        approvalReference: input.approvalReference });
      if (result.error) { setError(result.error); return; }
      approvalKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  function setApproval(refundId: string, field: "method" | "outboundReference" | "outboundEvidence" | "approvalReference", value: string) {
    approvalKey.current = null;
    const previous = approvalInputs[refundId] ?? { method: "bank_transfer", outboundReference: "", outboundEvidence: "", approvalReference: "" };
    setApprovalInputs({ ...approvalInputs, [refundId]: { ...previous, [field]: value } });
  }

  if (!availablePayments.length && !refunds.length) return null;
  return <Card><CardHeader><CardTitle>استرداد واقعی وجه</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">درخواست استرداد به‌تنهایی خروج پول را ثبت نمی‌کند. فرد دوم پس از انجام پرداخت، رسید خروج وجه و مرجع تأیید مستقل را ثبت می‌کند.</p>
    {refunds.map((refund) => {
      const input = approvalInputs[refund.id] ?? { method: "bank_transfer", outboundReference: "", outboundEvidence: "", approvalReference: "" };
      return <div key={refund.id} className="rounded-xl border border-border/70 p-3">
        <p className="font-medium">{refund.amount_irr.toLocaleString("fa-IR")} ریال · {refund.approved_at ? "وجه خارج‌شده و تأییدشده" : "در انتظار خروج وجه و تأیید"}</p>
        <p className="text-muted-foreground">رسید اولیه: {payments.find((payment) => payment.id === refund.source_payment_id)?.external_reference ?? refund.source_payment_id} · علت: {refund.reason} · مرجع درخواست: {refund.request_reference}</p>
        {refund.approved_at && <p className="text-muted-foreground">روش: {methodNames[refund.outbound_method ?? ""] ?? refund.outbound_method} · مرجع خروج: {refund.outbound_reference} · شاهد: {refund.outbound_evidence} · مرجع تأیید: {refund.approval_reference}</p>}
        {!refund.approved_at && refund.requested_by === currentUserId && <p className="mt-2 text-muted-foreground">تأیید این درخواست باید توسط فرد دیگری انجام شود.</p>}
        {!refund.approved_at && refund.requested_by !== currentUserId && canApprove && <div className="mt-3 grid gap-2 border-t border-border/70 pt-3">
          <p className="font-medium">تأیید پس از مشاهدهٔ رسید خروج وجه</p>
          <select className="h-10 rounded-md border border-input bg-background px-3" aria-label="روش خروج وجه" value={input.method}
            onChange={(event) => setApproval(refund.id, "method", event.target.value)}>
            <option value="bank_transfer">حوالهٔ بانکی</option><option value="card_reversal">برگشت تراکنش کارت</option><option value="cash">نقد</option>
          </select>
          <Input required maxLength={160} aria-label="مرجع خروج وجه" placeholder="شناسهٔ یکتای تراکنش خروج"
            value={input.outboundReference} onChange={(event) => setApproval(refund.id, "outboundReference", event.target.value)} />
          <Input required maxLength={500} aria-label="شاهد خروج وجه" placeholder="مرجع رسید بانکی یا رسید نقدی"
            value={input.outboundEvidence} onChange={(event) => setApproval(refund.id, "outboundEvidence", event.target.value)} />
          <Input required maxLength={160} aria-label="مرجع تأیید استرداد" placeholder="شناسهٔ یکتای تأیید مستقل"
            value={input.approvalReference} onChange={(event) => setApproval(refund.id, "approvalReference", event.target.value)} />
          <Button type="button" className="justify-self-start" disabled={pending || !input.outboundReference.trim() || !input.outboundEvidence.trim() || !input.approvalReference.trim()}
            onClick={() => approve(refund.id)}>ثبت خروج وجه و تأیید استرداد</Button>
        </div>}
      </div>;
    })}
    {canRequest && availablePayments.length > 0 && <form onSubmit={request} className="grid gap-2 rounded-xl border border-border/70 p-3">
      <p className="font-medium">درخواست استرداد</p>
      <select required className="h-10 rounded-md border border-input bg-background px-3" aria-label="رسید پرداخت برای استرداد"
        value={sourcePaymentId} onChange={(event) => { requestKey.current = null; setSourcePaymentId(event.target.value); }}>
        <option value="">رسید تطبیق‌شده را انتخاب کنید</option>
        {availablePayments.map((payment) => <option key={payment.id} value={payment.id}>
          {payment.external_reference} · ماندهٔ قابل استرداد {payment.available.toLocaleString("fa-IR")} ریال
        </option>)}
      </select>
      <Input required type="number" min="1" max={availablePayments.find((payment) => payment.id === sourcePaymentId)?.available ?? 1}
        step="1" inputMode="numeric" aria-label="مبلغ استرداد ریال" placeholder="مبلغ استرداد به ریال"
        value={amountIrr} onChange={(event) => { requestKey.current = null; setAmountIrr(event.target.value); }} />
      <Input required minLength={5} maxLength={1000} aria-label="علت استرداد" placeholder="علت استرداد (حداقل ۵ حرف)"
        value={reason} onChange={(event) => { requestKey.current = null; setReason(event.target.value); }} />
      <Input required maxLength={160} aria-label="مرجع درخواست استرداد" placeholder="شناسهٔ یکتای درخواست"
        value={requestReference} onChange={(event) => { requestKey.current = null; setRequestReference(event.target.value); }} />
      <Button type="submit" disabled={pending} className="justify-self-start">ثبت درخواست استرداد</Button>
    </form>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
