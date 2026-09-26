"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { approveRepairPaymentCreditTransferAction, requestRepairPaymentCreditTransferAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

type OldPayment = { id: string; plan_id: string; amount_irr: number; external_reference: string };
type Transfer = {
  id: string; source_payment_id: string; target_plan_id: string; amount_irr: number;
  request_reference: string; request_evidence: string; requested_by: string; requested_at: string;
  approval_reference: string | null; approved_by: string | null; approved_at: string | null;
};

export function RepairCreditTransferPanel({ orgId, caseId, currentUserId, expectedVersion, planId, planAmount,
  oldPayments, verifications, corrections, transfers, refunds, canRequest, canApprove }: {
  orgId: string; caseId: string; currentUserId: string; expectedVersion: number;
  planId: string; planAmount: number; oldPayments: OldPayment[];
  verifications: { payment_id: string }[]; corrections: { payment_id: string }[];
  transfers: Transfer[]; refunds: { source_payment_id: string; amount_irr: number; approved_at: string | null }[];
  canRequest: boolean; canApprove: boolean;
}) {
  const router = useRouter();
  const requestKey = useRef<string | null>(null);
  const approvalKey = useRef<string | null>(null);
  const [sourcePaymentId, setSourcePaymentId] = useState("");
  const [amountIrr, setAmountIrr] = useState("");
  const [requestReference, setRequestReference] = useState("");
  const [requestEvidence, setRequestEvidence] = useState("");
  const [approvalReferences, setApprovalReferences] = useState<Record<string, string>>({});
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const verified = new Set(verifications.map((item) => item.payment_id));
  const corrected = new Set(corrections.map((item) => item.payment_id));
  const eligible = oldPayments.map((payment) => ({
    ...payment,
    available: payment.amount_irr - transfers.reduce((sum, transfer) =>
      sum + (transfer.source_payment_id === payment.id && transfer.approved_at ? transfer.amount_irr : 0), 0)
      - refunds.reduce((sum, refund) => sum + (refund.source_payment_id === payment.id && refund.approved_at ? refund.amount_irr : 0), 0),
  })).filter((payment) => verified.has(payment.id) && !corrected.has(payment.id) && payment.available > 0);
  const currentTransfers = transfers.filter((transfer) => transfer.target_plan_id === planId);
  const approvedAmount = currentTransfers.reduce((sum, transfer) => sum + (transfer.approved_at ? transfer.amount_irr : 0), 0);

  async function request(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); requestKey.current ??= crypto.randomUUID();
    try {
      const result = await requestRepairPaymentCreditTransferAction({ orgId, caseId, expectedVersion,
        idempotencyKey: requestKey.current, sourcePaymentId, amountIrr: Number(amountIrr), requestReference, requestEvidence });
      if (result.error) { setError(result.error); return; }
      requestKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  async function approve(transferId: string) {
    if (pending) return;
    setPending(true); setError(""); approvalKey.current ??= crypto.randomUUID();
    try {
      const result = await approveRepairPaymentCreditTransferAction({ orgId, caseId, transferId, expectedVersion,
        idempotencyKey: approvalKey.current, approvalReference: approvalReferences[transferId] ?? "" });
      if (result.error) { setError(result.error); return; }
      approvalKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  if (!eligible.length && !currentTransfers.length) return null;
  return <Card><CardHeader><CardTitle>انتقال اعتبار از برنامهٔ قبلی</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">اعتبار تأییدشدهٔ منتقل‌شده: {approvedAmount.toLocaleString("fa-IR")} ریال از {planAmount.toLocaleString("fa-IR")} ریال. درخواست تا پیش از تأیید فرد دوم در مانده حساب نمی‌شود.</p>
    {currentTransfers.map((transfer) => <div key={transfer.id} className="rounded-xl border border-border/70 p-3">
      <p className="font-medium">{transfer.amount_irr.toLocaleString("fa-IR")} ریال · {transfer.approved_at ? "تأییدشده" : "در انتظار تأیید مستقل"}</p>
      <p className="text-muted-foreground">رسید مبدأ: {oldPayments.find((payment) => payment.id === transfer.source_payment_id)?.external_reference ?? transfer.source_payment_id} · مرجع درخواست: {transfer.request_reference} · شاهد: {transfer.request_evidence}</p>
      {transfer.approval_reference && <p className="text-muted-foreground">مرجع تأیید: {transfer.approval_reference}</p>}
      {!transfer.approved_at && canApprove && transfer.requested_by !== currentUserId && <div className="mt-3 flex flex-wrap items-center gap-2">
        <Input className="max-w-xs" required maxLength={160} aria-label="مرجع تأیید انتقال اعتبار"
          placeholder="مرجع تأیید مستقل" value={approvalReferences[transfer.id] ?? ""}
          onChange={(event) => { approvalKey.current = null; setApprovalReferences({ ...approvalReferences, [transfer.id]: event.target.value }); }} />
        <Button type="button" disabled={pending || !approvalReferences[transfer.id]?.trim()} onClick={() => approve(transfer.id)}>تأیید انتقال</Button>
      </div>}
      {!transfer.approved_at && transfer.requested_by === currentUserId && <p className="text-muted-foreground">این درخواست باید توسط فرد دیگری با دسترسی تأیید شود.</p>}
    </div>)}
    {canRequest && eligible.length > 0 && <form onSubmit={request} className="grid gap-2 rounded-xl border border-border/70 p-3">
      <p className="font-medium">درخواست انتقال اعتبار</p>
      <select required className="h-10 rounded-md border border-input bg-background px-3" aria-label="رسید پرداخت برنامهٔ قبلی"
        value={sourcePaymentId} onChange={(event) => { requestKey.current = null; setSourcePaymentId(event.target.value); }}>
        <option value="">رسید تطبیق‌شدهٔ قبلی را انتخاب کنید</option>
        {eligible.map((payment) => <option key={payment.id} value={payment.id}>
          {payment.external_reference} · ماندهٔ قابل انتقال {payment.available.toLocaleString("fa-IR")} ریال
        </option>)}
      </select>
      <Input required type="number" min="1" max={Math.min(planAmount, eligible.find((payment) => payment.id === sourcePaymentId)?.available ?? planAmount)}
        step="1" inputMode="numeric" aria-label="مبلغ انتقال ریال" placeholder="مبلغ انتقال به ریال"
        value={amountIrr} onChange={(event) => { requestKey.current = null; setAmountIrr(event.target.value); }} />
      <Input required maxLength={160} aria-label="مرجع درخواست انتقال" placeholder="شناسهٔ یکتای درخواست انتقال"
        value={requestReference} onChange={(event) => { requestKey.current = null; setRequestReference(event.target.value); }} />
      <Input required maxLength={500} aria-label="شاهد انتقال اعتبار" placeholder="مرجع بررسی مالی"
        value={requestEvidence} onChange={(event) => { requestKey.current = null; setRequestEvidence(event.target.value); }} />
      <Button type="submit" disabled={pending} className="justify-self-start">ثبت درخواست انتقال</Button>
    </form>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
