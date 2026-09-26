"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { completeRepairForTestAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function RepairCompletionPanel({ orgId, caseId, expectedVersion, canComplete, verified,
  needsParts, partsComplete, custodyBlocked }: {
  orgId: string; caseId: string; expectedVersion: number; canComplete: boolean; verified: boolean;
  needsParts: boolean; partsComplete: boolean; custodyBlocked: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [protocol, setProtocol] = useState("");
  const [description, setDescription] = useState("");
  const [reference, setReference] = useState("");
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const ready = canComplete && verified && (!needsParts || partsComplete) && !custodyBlocked
    && protocol === "repair_functional_v1" && (needsParts || (description.trim() && reference.trim()))
    && Boolean(description.trim()) === Boolean(reference.trim());
  async function confirm() {
    if (!ready || busy) return;
    key.current ??= crypto.randomUUID();
    setBusy(true); setError("");
    try {
      const result = await completeRepairForTestAction({ orgId, caseId, expectedVersion,
        idempotencyKey: key.current, protocolCode: "repair_functional_v1",
        workDescription: description, workReference: reference });
      if (result.error) { setError(result.error); return; }
      key.current = null; setOpen(false); router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setBusy(false); }
  }
  function edit() { key.current = null; setError(""); }
  return <Card><CardHeader><CardTitle>تکمیل تعمیر و ارجاع به آزمون</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">این ثبت فقط انجام کار تعمیر را مستند می‌کند. نتیجهٔ آزمون و مجوز خروج کیفیت در مرحلهٔ بعد مستقل ثبت می‌شوند.</p>
    {needsParts ? <p>همهٔ قطعات برنامه باید مصرف و حوالهٔ اقدامشان ثبت شده باشد؛ رزرو باز اجازهٔ تکمیل نمی‌دهد.</p>
      : <p>چون برنامه بدون قطعه است، اقدام انجام‌شده و مرجع آن را ثبت کنید.</p>}
    <div className="grid gap-3 sm:grid-cols-2">
      <div className="grid gap-1 sm:col-span-2"><Label htmlFor="repair-protocol">پروتکل آزمون مقصد</Label>
        <select id="repair-protocol" required className="h-9 rounded-lg border border-input bg-background px-2" value={protocol}
          onChange={(event) => { edit(); setProtocol(event.target.value); }}>
          <option value="">انتخاب کنید</option><option value="repair_functional_v1">آزمون عملکرد تعمیر · نسخهٔ ۱</option>
        </select></div>
      <div className="grid gap-1"><Label htmlFor="repair-work-description">{needsParts ? "اقدام تکمیلی (اختیاری)" : "شرح اقدام انجام‌شده"}</Label>
        <Input id="repair-work-description" maxLength={2000} required={!needsParts} value={description}
          onChange={(event) => { edit(); setDescription(event.target.value); }} /></div>
      <div className="grid gap-1"><Label htmlFor="repair-work-reference">{needsParts ? "مرجع اقدام تکمیلی (اختیاری)" : "مرجع اقدام"}</Label>
        <Input id="repair-work-reference" maxLength={240} required={!needsParts} value={reference}
          onChange={(event) => { edit(); setReference(event.target.value); }} /></div>
    </div>
    {!verified && <p className="text-destructive">IMEI دستگاه اصلی باید هنگام دریافت فیزیکی تأیید شده باشد.</p>}
    {needsParts && !partsComplete && <p className="text-destructive">مصرف همهٔ قطعات برنامه و بستن رزروهای باز لازم است.</p>}
    {custodyBlocked && <p className="text-destructive">انتقال یا مغایرت باز دستگاه باید تعیین تکلیف شود.</p>}
    {!canComplete && <p className="text-muted-foreground">برای تکمیل تعمیر، هر دو مجوز تخصصی تکمیل و انتقال T06 لازم است.</p>}
    {error && !open && <p role="alert" className="text-destructive">{error}</p>}
    {canComplete && <Button disabled={!ready || busy} onClick={() => setOpen(true)} className="justify-self-start">ارجاع تعمیر به آزمون</Button>}
    <Dialog open={open} onOpenChange={(value) => { if (!value && !busy) setOpen(false); }}>
      <DialogContent showCloseButton={false}><DialogHeader><DialogTitle>تکمیل تعمیر و ارجاع به آزمون؟</DialogTitle>
        <DialogDescription>پرونده به مرحلهٔ آزمون منتقل می‌شود. این تأیید، نتیجهٔ تست یا مجوز تحویل نیست.</DialogDescription>
      </DialogHeader>{error && <p role="alert" className="text-destructive">{error}</p>}
        <DialogFooter><Button variant="outline" disabled={busy} onClick={() => setOpen(false)}>انصراف</Button>
          <Button disabled={busy} onClick={confirm}>{busy ? "در حال ثبت…" : "تأیید"}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </CardContent></Card>;
}
