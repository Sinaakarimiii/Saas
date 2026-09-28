"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairDeliveryReceiptAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type RecipientRole = "owner" | "authorized_representative" | "colleague";

export function DeliveryReceipt({ orgId, caseId, expectedVersion, intendedRecipient, recipientRole,
  authorityReference, receipt, canRecord, ready, deviceIdentifier, route = "return" }: {
  orgId: string; caseId: string; expectedVersion: number; intendedRecipient: string;
  recipientRole: RecipientRole; authorityReference: string | null;
  receipt: { recipient_name: string; receipt_reference: string; received_at: string } | null;
  canRecord: boolean; ready: boolean; deviceIdentifier?: string; route?: "return" | "repair" | "replacement";
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [reference, setReference] = useState("");
  const [evidence, setEvidence] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true);
    setError("");
    key.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairDeliveryReceiptAction({ orgId, caseId, expectedVersion,
        idempotencyKey: key.current, recipientName: intendedRecipient, recipientRole,
        authorityReference: authorityReference ?? "", receiptReference: reference, receiptEvidence: evidence });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  return <Card><CardHeader><CardTitle>رسید تحویل واقعی · {route === "replacement" ? "دستگاه جایگزین" : route === "repair" ? "دستگاه تعمیرشده" : "عودت حضوری"}</CardTitle></CardHeader>
    <CardContent className="grid gap-4 text-sm">
      {deviceIdentifier && <p>IMEI دستگاه تحویلی: <strong dir="ltr" className="inline-block tabular-nums">{deviceIdentifier}</strong></p>}
      {receipt ? <p className="rounded-xl border border-primary/25 bg-primary/5 p-4">تحویل به {receipt.recipient_name} ثبت شد؛ مرجع دریافت: {receipt.receipt_reference}.</p>
        : <>
          <p className="text-muted-foreground">این فرم فقط پس از دریافت واقعی دستگاه توسط گیرنده پر می‌شود. گیرندهٔ ثبت‌شده در کنترل خروج: {intendedRecipient}. {route === "replacement" ? "تحویل این دستگاه در مسیر فعلی حضوری است." : "برای پست یا پیک، مسیر ارسال و رسید مقصد جداگانه لازم است."}</p>
          {!ready && <p className="text-destructive">کنترل خروج معتبر یا شرایط تحویل کامل نیست.</p>}
          {canRecord ? <form onSubmit={submit} className="grid gap-3">
            <p>تحویل به: <strong>{intendedRecipient}</strong> · {recipientRole === "owner" ? "مالک" : recipientRole === "colleague" ? "همکار" : "نمایندهٔ مجاز"}</p>
            {authorityReference && <p>مرجع اختیار: {authorityReference}</p>}
            <div className="grid gap-2"><Label htmlFor="delivery-reference">مرجع یکتای رسید دریافت</Label><Input id="delivery-reference" required maxLength={160} value={reference} onChange={(event) => { key.current = null; setReference(event.target.value); }} /></div>
            <div className="grid gap-2"><Label htmlFor="delivery-evidence">مدرک مستقل دریافت</Label><Input id="delivery-evidence" required maxLength={240} value={evidence} onChange={(event) => { key.current = null; setEvidence(event.target.value); }} /></div>
            {error && <p role="alert" className="text-destructive">{error}</p>}
            <div className="flex justify-end"><Button type="submit" disabled={pending || !ready}>{pending ? "در حال ثبت…" : "ثبت رسید دریافت واقعی"}</Button></div>
          </form> : <p className="text-muted-foreground">ثبت رسید به مجوز مستقل نیاز دارد.</p>}
        </>}
    </CardContent></Card>;
}
