"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordReplacementOriginalReturnAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function ReplacementOriginalReturn({ orgId, caseId, expectedVersion, disposition,
  recipientName, canRecord, ready, returned }: {
  orgId: string; caseId: string; expectedVersion: number; disposition: string;
  recipientName: string; canRecord: boolean; ready: boolean;
  returned: { receipt_reference: string; condition_note: string; recipient_name: string } | null;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [reference, setReference] = useState("");
  const [evidence, setEvidence] = useState("");
  const [condition, setCondition] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await recordReplacementOriginalReturnAction({ orgId, caseId, expectedVersion,
        idempotencyKey: key.current, receiptReference: reference, receiptEvidence: evidence, conditionNote: condition });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  const proposals: Record<string, string> = {
    scrap_proposed: "پیشنهاد اسقاط", refurbish_proposed: "پیشنهاد بازسازی", parts_proposed: "پیشنهاد استفاده برای قطعات",
  };
  return <Card><CardHeader><CardTitle>تعیین تکلیف دستگاه اولیه</CardTitle></CardHeader>
    <CardContent className="grid gap-4 text-sm">
      {returned ? <><p>دستگاه اولیه به {returned.recipient_name} عودت شد؛ رسید: {returned.receipt_reference}.</p>
        <p className="text-muted-foreground">وضعیت هنگام عودت: {returned.condition_note}</p></>
        : disposition !== "return_to_customer" ? <p>{proposals[disposition] ?? "تعیین تکلیف نامشخص"} هنوز انجام‌شده نیست؛ پرونده تا ثبت اجرای مستند این عملیات باز می‌ماند.</p>
        : <>
          <p className="text-muted-foreground">پس از عودت واقعی دستگاه اولیه به گیرندهٔ تأییدشده ({recipientName})، رسید مستقل و وضعیت آن را ثبت کنید. این رسید مخصوص دستگاه اولیه است.</p>
          {!ready && <p className="text-muted-foreground">ابتدا تحویل دستگاه جایگزین ثبت شود و مانع‌های باز برطرف شوند.</p>}
          {canRecord ? <form onSubmit={submit} className="grid gap-3">
            <div className="grid gap-2"><Label htmlFor="original-return-reference">مرجع رسید دستگاه اولیه</Label><Input id="original-return-reference" required maxLength={160} value={reference} onChange={(event) => { key.current = null; setReference(event.target.value); }} /></div>
            <div className="grid gap-2"><Label htmlFor="original-return-evidence">مدرک دریافت دستگاه اولیه</Label><Input id="original-return-evidence" required maxLength={240} value={evidence} onChange={(event) => { key.current = null; setEvidence(event.target.value); }} /></div>
            <div className="grid gap-2"><Label htmlFor="original-return-condition">شرح وضعیت و اقلام هنگام عودت</Label><Input id="original-return-condition" required maxLength={500} value={condition} onChange={(event) => { key.current = null; setCondition(event.target.value); }} /></div>
            {error && <p role="alert" className="text-destructive">{error}</p>}
            <div className="flex justify-end"><Button disabled={pending || !ready} type="submit">{pending ? "در حال ثبت…" : "ثبت عودت واقعی دستگاه اولیه"}</Button></div>
          </form> : <p className="text-muted-foreground">مجوز مستقل عودت دستگاه اولیه لازم است.</p>}
        </>}
    </CardContent></Card>;
}
