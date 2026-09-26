"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { executeRepairReplacementForTestAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function ReplacementExecutionPanel({ orgId, caseId, expectedVersion, allocatedImei,
  canExecute, custodyBlocked, originalBaselineReady }: {
  orgId: string; caseId: string; expectedVersion: number; allocatedImei: string | null;
  canExecute: boolean; custodyBlocked: boolean; originalBaselineReady: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [reference, setReference] = useState("");
  const [evidence, setEvidence] = useState("");
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const ready = canExecute && Boolean(allocatedImei) && originalBaselineReady && !custodyBlocked && reference.trim() && evidence.trim();
  function edit() { key.current = null; setError(""); }
  async function confirm() {
    if (!ready || busy) return;
    key.current ??= crypto.randomUUID(); setBusy(true); setError("");
    try {
      const result = await executeRepairReplacementForTestAction({ orgId, caseId, expectedVersion,
        idempotencyKey: key.current, executionReference: reference, evidenceReference: evidence });
      if (result.error) { setError(result.error); return; }
      key.current = null; setOpen(false); router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setBusy(false); }
  }
  return <Card><CardHeader><CardTitle>اجرای تعویض و ارجاع به تست</CardTitle></CardHeader>
    <CardContent className="grid gap-4 text-sm">
      <p className="text-muted-foreground">اجرای واقعی تعویض برای دستگاه تخصیص‌یافته ثبت می‌شود. دستگاه اصلی همچنان با موقعیت فیزیکی مستقل، منتظر تعیین تکلیف است؛ نتیجهٔ تست و تحویل هنوز جدا هستند.</p>
      {allocatedImei ? <p>دستگاه جایگزین: <strong dir="ltr">{allocatedImei}</strong></p>
        : <p className="text-destructive">ابتدا دستگاه جایگزین مشخصی را تخصیص دهید.</p>}
      {custodyBlocked && <p className="text-destructive">انتقال یا مغایرت باز هر یک از دو دستگاه باید تعیین تکلیف شود.</p>}
      {!originalBaselineReady && <p className="text-destructive">ابتدا موقعیت و نگهدارندهٔ فیزیکی دستگاه اصلی را در بخش نگهداری تأیید کنید.</p>}
      {!canExecute && <p className="text-muted-foreground">مجوز اجرای تعویض و انتقال T07 لازم است.</p>}
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="grid gap-1"><Label htmlFor="replacement-execution-reference">مرجع یکتای اجرای تعویض</Label>
          <Input id="replacement-execution-reference" required maxLength={160} value={reference}
            onChange={(event) => { edit(); setReference(event.target.value); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-execution-evidence">مرجع شاهد اجرای فیزیکی</Label>
          <Input id="replacement-execution-evidence" required maxLength={500} value={evidence}
            onChange={(event) => { edit(); setEvidence(event.target.value); }} /></div>
      </div>
      {error && !open && <p role="alert" className="text-destructive">{error}</p>}
      {canExecute && <Button disabled={!ready || busy} className="justify-self-start" onClick={() => setOpen(true)}>ثبت اجرا و ارجاع به تست</Button>}
      <Dialog open={open} onOpenChange={(value) => { if (!value && !busy) setOpen(false); }}>
        <DialogContent showCloseButton={false}><DialogHeader><DialogTitle>تعویض اجرا شده و پرونده به تست برود؟</DialogTitle>
          <DialogDescription>IMEI دستگاه تخصیص‌یافته و مرجع اجرا ثبت می‌شود. این تأیید، نتیجهٔ تست یا تحویل به مشتری نیست.</DialogDescription>
        </DialogHeader>{error && <p role="alert" className="text-destructive">{error}</p>}
          <DialogFooter><Button variant="outline" disabled={busy} onClick={() => setOpen(false)}>انصراف</Button>
            <Button disabled={busy} onClick={confirm}>{busy ? "در حال ثبت…" : "تأیید"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </CardContent>
  </Card>;
}
