"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { confirmRepairDeliveryReceiptAction, recordRepairDeliveryDispatchAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Dispatch = { id: string; method: string; carrier: string; destination_name: string;
  destination_role: string; authority_reference: string | null; destination_address: string;
  tracking_code: string; dispatch_reference: string; dispatched_at: string };

export function DeliveryShipment({ orgId, caseId, expectedVersion, intendedRecipient,
  dispatch, received, incidentOpen, canDispatch, canConfirm, ready, deviceIdentifier }: {
  orgId: string; caseId: string; expectedVersion: number; intendedRecipient: string; deviceIdentifier?: string;
  dispatch: Dispatch | null;
  received: boolean; incidentOpen: boolean; canDispatch: boolean; canConfirm: boolean; ready: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ method: "post" as "post" | "courier", carrier: "",
    address: "", tracking: "", reference: "", evidence: "" });
  const [receiptReference, setReceiptReference] = useState("");
  const [receiptEvidence, setReceiptEvidence] = useState("");

  async function submitDispatch(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairDeliveryDispatchAction({ orgId, caseId, expectedVersion,
        idempotencyKey: key.current, method: form.method, carrier: form.carrier,
        destinationAddress: form.address, trackingCode: form.tracking,
        dispatchReference: form.reference, dispatchEvidence: form.evidence });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  async function submitReceipt(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending || !dispatch) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await confirmRepairDeliveryReceiptAction({ orgId, caseId, dispatchId: dispatch.id,
        expectedVersion, idempotencyKey: key.current, recipientName: dispatch.destination_name,
        recipientRole: dispatch.destination_role, authorityReference: dispatch.authority_reference ?? "",
        receiptReference, receiptEvidence });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  return <Card><CardHeader><CardTitle>تحویل با پست یا پیک</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    {deviceIdentifier && <p>دستگاه جایگزین · IMEI: <bdi className="font-mono">{deviceIdentifier}</bdi></p>}
    {!ready && !received && <p className="text-muted-foreground">ثبت ارسال یا دریافت پس از تکمیل کنترل‌های خروج، تسویه و رفع موانع باز پرونده فعال می‌شود.</p>}
    {!dispatch ? <>
      <p className="text-muted-foreground">خروج به حامل، دریافت مشتری نیست. گیرندهٔ مقصد مطابق کنترل خروج: {intendedRecipient}. پس از ارسال، کد رهگیری و وضعیت «در مسیر تحویل» نمایش داده می‌شود.</p>
      {canDispatch ? <form onSubmit={submitDispatch} className="grid gap-3 sm:grid-cols-2">
        <div className="grid gap-2"><Label htmlFor="dispatch-method">روش ارسال</Label><select id="dispatch-method" className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.method} onChange={(event) => { key.current = null; setForm({ ...form, method: event.target.value as "post" | "courier" }); }}><option value="post">پست</option><option value="courier">پیک</option></select></div>
        <div className="grid gap-2"><Label htmlFor="dispatch-carrier">حامل</Label><Input id="dispatch-carrier" required maxLength={160} value={form.carrier} onChange={(event) => { key.current = null; setForm({ ...form, carrier: event.target.value }); }} /></div>
        <div className="grid gap-2 sm:col-span-2"><Label htmlFor="dispatch-address">نشانی مقصد گیرنده</Label><Input id="dispatch-address" required maxLength={300} value={form.address} onChange={(event) => { key.current = null; setForm({ ...form, address: event.target.value }); }} /></div>
        <div className="grid gap-2"><Label htmlFor="dispatch-tracking">کد رهگیری</Label><Input id="dispatch-tracking" required maxLength={240} value={form.tracking} onChange={(event) => { key.current = null; setForm({ ...form, tracking: event.target.value }); }} /></div>
        <div className="grid gap-2"><Label htmlFor="dispatch-reference">مرجع یکتای خروج</Label><Input id="dispatch-reference" required maxLength={160} value={form.reference} onChange={(event) => { key.current = null; setForm({ ...form, reference: event.target.value }); }} /></div>
        <div className="grid gap-2 sm:col-span-2"><Label htmlFor="dispatch-evidence">مدرک خروج و تحویل به حامل</Label><Input id="dispatch-evidence" required maxLength={240} value={form.evidence} onChange={(event) => { key.current = null; setForm({ ...form, evidence: event.target.value }); }} /></div>
        {error && <p role="alert" className="text-destructive sm:col-span-2">{error}</p>}
        <div className="flex justify-end sm:col-span-2"><Button type="submit" disabled={pending || !ready}>{pending ? "در حال ثبت…" : "ثبت خروج به حامل"}</Button></div>
      </form> : <p className="text-muted-foreground">ثبت ارسال به مجوز مستقل و مسئولیت فعلی نگهداری دستگاه نیاز دارد.</p>}
    </> : <>
      <div className="rounded-xl border border-primary/25 bg-primary/5 p-4">
        <p className="font-medium">{received ? "دریافت مقصد تأیید شد" : incidentOpen ? "مسئلهٔ حمل باز؛ دریافت مقصد مسدود" : "در مسیر تحویل"}</p>
        <p className="mt-1 text-muted-foreground">{dispatch.method === "post" ? "پست" : "پیک"} · {dispatch.carrier} · کد رهگیری {dispatch.tracking_code}</p>
        <p className="mt-1 text-muted-foreground">گیرنده: {dispatch.destination_name} · نشانی: {dispatch.destination_address}</p>
      </div>
      {!received && (canConfirm ? <form onSubmit={submitReceipt} className="grid gap-3">
        <p>فقط پس از تأیید دریافت واقعی همان ارسال در مقصد، مرجع و مدرک مستقل دریافت را ثبت کنید.</p>
        <div className="grid gap-2"><Label htmlFor="remote-receipt-reference">مرجع رسید مقصد</Label><Input id="remote-receipt-reference" required maxLength={160} value={receiptReference} onChange={(event) => { key.current = null; setReceiptReference(event.target.value); }} /></div>
        <div className="grid gap-2"><Label htmlFor="remote-receipt-evidence">مدرک دریافت مقصد</Label><Input id="remote-receipt-evidence" required maxLength={240} value={receiptEvidence} onChange={(event) => { key.current = null; setReceiptEvidence(event.target.value); }} /></div>
        {error && <p role="alert" className="text-destructive">{error}</p>}
        <div className="flex justify-end"><Button type="submit" disabled={pending || !ready}>{pending ? "در حال ثبت…" : "تأیید دریافت مقصد"}</Button></div>
      </form> : <p className="text-muted-foreground">تأیید دریافت مقصد به مجوز مستقل نیاز دارد.</p>)}
    </>}
  </CardContent></Card>;
}
