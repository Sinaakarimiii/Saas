"use client";
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordReplacementWarehouseReceiptAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function ReplacementWarehouseReceipt({ orgId, caseId, expectedVersion, disposition, canRecord, ready, transfer, receipt }: {
  orgId: string; caseId: string; expectedVersion: number; disposition: string; canRecord: boolean; ready: boolean;
  transfer: { id: string; destination_location: string; resolution_reference: string | null } | null;
  receipt: { transfer_id: string; location: string; receipt_reference: string; condition_note: string } | null;
}) {
  const router = useRouter(); const key = useRef<string | null>(null);
  const [condition, setCondition] = useState(""); const [pending, setPending] = useState(false); const [error, setError] = useState("");
  const purpose = disposition === "parts_proposed" ? "داغی / قطعات" : "بازسازی";
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (pending || !transfer) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await recordReplacementWarehouseReceiptAction({ orgId, caseId, expectedVersion,
        idempotencyKey: key.current, transferId: transfer.id, conditionNote: condition });
      if (result.error) { setError(result.error); return; } router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  return <Card><CardHeader><CardTitle>دریافت دستگاه اولیه برای {purpose}</CardTitle></CardHeader>
    <CardContent className="grid gap-4 text-sm">
      {receipt && <><p>دستگاه اولیه در {receipt.location} دریافت شد؛ رسید: {receipt.receipt_reference}.</p><p className="text-muted-foreground">وضعیت دستگاه و اقلام: {receipt.condition_note}</p></>}
      {(!receipt || (transfer && transfer.id !== receipt.transfer_id)) && <>
          <p className="text-muted-foreground">ابتدا در بخش انتقال داخلی دستگاه اولیه، خروج به مسئول انبار و تأیید دریافت در مقصد را ثبت کنید. مسئول دریافت‌کننده با ثبت زیر، ورود برای {purpose} را نهایی می‌کند.</p>
          <p className="text-muted-foreground">تحویل مستند به انبار برای بستن پرونده کافی است؛ پایان بازسازی یا قطعه‌برداری جداگانه پیگیری می‌شود.</p>
          {transfer ? <p>مقصد دریافت‌شده: {transfer.destination_location}؛ رسید: {transfer.resolution_reference}</p>
            : <p>انتقال تأییدشدهٔ فعلی به نام شما موجود نیست.</p>}
          {!ready && <p className="text-muted-foreground">تحویل دستگاه جایگزین و رفع مانع‌های باز لازم است.</p>}
          {canRecord ? <form onSubmit={submit} className="grid gap-3">
            <div className="grid gap-2"><Label htmlFor="warehouse-original-condition">وضعیت دستگاه اولیه و اقلام دریافتی</Label><Input id="warehouse-original-condition" required maxLength={500} value={condition} onChange={(event) => { key.current = null; setCondition(event.target.value); }} /></div>
            {error && <p role="alert" className="text-destructive">{error}</p>}
            <div className="flex justify-end"><Button type="submit" disabled={pending || !ready || !transfer}>{pending ? "در حال ثبت…" : `ثبت ${receipt ? "دریافت جدید" : "دریافت"} برای ${purpose}`}</Button></div>
          </form> : <p className="text-muted-foreground">مجوز مستقل ثبت دریافت انبار لازم است.</p>}
        </>}
    </CardContent></Card>;
}
