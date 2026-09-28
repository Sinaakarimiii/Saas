"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { transitionRepairCaseAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type TransitionCode = "T01" | "T02" | "T03" | "T04" | "T05" | "T08" | "T09" | "T10" | "T11";

export function StageTransition({ orgId, caseId, trackingCode, stage, expectedVersion,
  canAdvance, canAdvanceDecision, canAdvanceRepair, canAdvanceReplacement, canAdvanceReturn, canAdvanceDelivery, canRetestAfterDamage, canClose, handoverReady, damageNeedsRetest, damageReturned, canReturn, intakeReady, diagnosisReady, decisionReady, deliveryReady, decisionRoute, deliveryRoute }: {
  orgId: string; caseId: string; trackingCode: string | null; stage: string; expectedVersion: number;
  canAdvance: boolean; canAdvanceDecision: boolean; canAdvanceRepair: boolean; canAdvanceReplacement: boolean; canAdvanceReturn: boolean; canAdvanceDelivery: boolean;
  canReturn: boolean; intakeReady: boolean; diagnosisReady: boolean; decisionReady: boolean; deliveryReady: boolean; deliveryRoute: "return" | "repair" | "replacement" | null;
  canRetestAfterDamage: boolean; damageNeedsRetest: boolean; damageReturned: boolean;
  canClose: boolean; handoverReady: boolean;
  decisionRoute: "repair" | "replacement" | "return" | null;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [selected, setSelected] = useState<TransitionCode | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const destination = selected === "T01" ? "کارشناسی" : selected === "T02" ? "تصمیم و هماهنگی" : selected === "T03" ? "تعمیر" : selected === "T04" ? "تعویض" : selected === "T05" || selected === "T11" ? "تست و کنترل خروج" : selected === "T08" ? "تحویل" : selected === "T09" ? "بسته‌شده" : "پذیرش";
  const origin = selected === "T01" ? "پذیرش" : selected === "T02" || selected === "T10" ? "کارشناسی" : selected === "T08" ? "تست و کنترل خروج" : selected === "T11" || selected === "T09" ? "تحویل" : "تصمیم و هماهنگی";

  async function confirm() {
    if (!selected || pending) return;
    setPending(true);
    setError("");
    key.current ??= crypto.randomUUID();
    try {
      const result = await transitionRepairCaseAction({ orgId, caseId, expectedVersion,
        transitionCode: selected, idempotencyKey: key.current });
      if (result.error) { setError(result.error); return; }
      setSelected(null);
      router.refresh();
    } catch {
      setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید.");
    } finally { setPending(false); }
  }

  function open(code: TransitionCode) {
    key.current = null;
    setError("");
    setSelected(code);
  }

  if (stage !== "intake" && stage !== "diagnosis" && stage !== "decision" && stage !== "test" && !(stage === "delivery" && deliveryRoute)) return null;
  return <>
    <Card>
      <CardHeader><CardTitle>ادامهٔ فرایند</CardTitle></CardHeader>
      <CardContent className="grid gap-4">
        {stage === "intake" && <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-primary/25 bg-primary/5 p-4">
          <div><p className="font-medium">گام رو به جلو: کارشناسی</p><p className="mt-1 text-sm text-muted-foreground">پس از ثبت دریافت و شناسهٔ قابل پیگیری، پرونده برای بررسی فنی آماده می‌شود.</p></div>
          {canAdvance && <Button disabled={!intakeReady} onClick={() => open("T01")}>ارجاع به کارشناسی</Button>}
        </div>}
        {stage === "intake" && !intakeReady && <p className="text-sm text-muted-foreground">برای ادامه، دریافت فیزیکی، محل و مسئول دستگاه و شناسهٔ اولیه یا IMEI تأییدشده را کامل کنید.</p>}
        {stage === "intake" && !canAdvance && <p className="text-sm text-muted-foreground">ارجاع به کارشناسی به مجوز مستقل این انتقال نیاز دارد.</p>}
        {stage === "diagnosis" && <>
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-primary/25 bg-primary/5 p-4"><div><p className="font-medium">گام رو به جلو: تصمیم و هماهنگی</p><p className="mt-1 text-sm text-muted-foreground">آخرین نسخهٔ تشخیص این نوبت باید نهایی شده باشد.</p></div>{canAdvanceDecision && <Button disabled={!diagnosisReady} onClick={() => open("T02")}>ارجاع به تصمیم</Button>}</div>
          {!diagnosisReady && <p className="text-sm text-muted-foreground">ابتدا تشخیص این نوبت را ثبت و نهایی کنید.</p>}
          {!canAdvanceDecision && <p className="text-sm text-muted-foreground">ارجاع به تصمیم به مجوز انتقال و نهایی‌سازی تشخیص نیاز دارد.</p>}
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border/70 p-4">
            <div><p className="font-medium">بازگشت به پذیرش</p><p className="mt-1 text-sm text-muted-foreground">برای اصلاح داده‌های پذیرش؛ دریافت و سوابق قبلی حفظ می‌شوند.</p></div>
            {canReturn && <Button variant="outline" onClick={() => open("T10")}>بازگشت به پذیرش</Button>}
          </div>
          {!canReturn && <p className="text-sm text-muted-foreground">بازگشت به پذیرش به مجوز مستقل این انتقال نیاز دارد.</p>}
        </>}
        {stage === "test" && deliveryRoute && <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-primary/25 bg-primary/5 p-4">
          <div><p className="font-medium">گام رو به جلو: تحویل</p><p className="mt-1 text-sm text-muted-foreground">آخرین کنترل خروج باید آزاد شده باشد{deliveryRoute !== "return" ? " و مبلغ برنامه تسویه شده باشد" : ""}. این ارجاع، تحویل فیزیکی را ثبت نمی‌کند.</p></div>
          {canAdvanceDelivery && <Button disabled={!deliveryReady} onClick={() => open("T08")}>ارجاع به تحویل</Button>}
          {!canAdvanceDelivery && <p className="text-sm text-muted-foreground">مجوز این انتقال را ندارید.</p>}
        </div>}
        {stage === "delivery" && damageNeedsRetest && <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4">
          <div><p className="font-medium">بازگشت به تست پس از آسیب‌دیدگی</p><p className="mt-1 text-sm text-muted-foreground">کنترل خروج و آزادسازی قبلی دیگر معتبر نیست. پس از ثبت رسید بازگشت فیزیکی، پرونده را به تست برگردانید؛ سپس مغایرت را تعیین تکلیف و کنترل تازه ثبت کنید. تحویل نهایی تا آن زمان مسدود است.</p></div>
          {canRetestAfterDamage && <Button variant="outline" disabled={!damageReturned} onClick={() => open("T11")}>بازگشت به تست</Button>}
          {!canRetestAfterDamage && <p className="text-sm text-muted-foreground">مجوز بازگشت به تست را ندارید.</p>}
          {!damageReturned && <p className="text-sm text-muted-foreground">رسید بازگشت فیزیکی دستگاه آسیب‌دیده لازم است.</p>}
        </div>}
        {stage === "delivery" && deliveryRoute && !damageNeedsRetest && <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-primary/25 bg-primary/5 p-4">
          <div><p className="font-medium">گام رو به جلو: بستن پرونده</p><p className="mt-1 text-sm text-muted-foreground">پس از رسید دریافت واقعی، رفع مانع‌های باز و کنترل دوبارهٔ کیفیت، پرونده بسته می‌شود.</p></div>
          {canClose && <Button disabled={!handoverReady || !deliveryReady} onClick={() => open("T09")}>بستن پرونده</Button>}
          {!canClose && <p className="text-sm text-muted-foreground">مجوز مستقل بستن پرونده لازم است.</p>}
        </div>}
        {stage === "decision" && <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-primary/25 bg-primary/5 p-4">
          <div><p className="font-medium">گام رو به جلو: {decisionRoute === "replacement" ? "تعویض" : decisionRoute === "return" ? "تست خروج" : "تعمیر"}</p>
            <p className="mt-1 text-sm text-muted-foreground">آخرین نسخهٔ برنامه و تأییدهای مربوط باید کامل باشند. ارجاع، اقدام فیزیکی یا برداشت از انبار نیست.</p></div>
          {decisionRoute === "repair" && canAdvanceRepair && <Button disabled={!decisionReady} onClick={() => open("T03")}>ارجاع به تعمیر</Button>}
          {decisionRoute === "replacement" && canAdvanceReplacement && <Button disabled={!decisionReady} onClick={() => open("T04")}>ارجاع به تعویض</Button>}
          {decisionRoute === "return" && canAdvanceReturn && <Button disabled={!decisionReady} onClick={() => open("T05")}>ارجاع به کنترل خروج</Button>}
        </div>}
      </CardContent>
    </Card>
    <Dialog open={selected !== null} onOpenChange={(open) => { if (!open && !pending) setSelected(null); }}>
      <DialogContent showCloseButton={false}>
        <DialogHeader>
          <DialogTitle>{selected === "T09" ? "بستن پرونده؟" : selected === "T10" || selected === "T11" ? `بازگشت به ${destination}؟` : `ارجاع به ${destination}؟`}</DialogTitle>
          <DialogDescription>پروندهٔ {trackingCode ?? "تعمیر"} از {origin} به {destination} منتقل می‌شود. سوابق و محل فیزیکی دستگاه حفظ می‌شوند.</DialogDescription>
        </DialogHeader>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <DialogFooter>
          <Button variant="outline" disabled={pending} onClick={() => setSelected(null)}>انصراف</Button>
          <Button disabled={pending} onClick={confirm}>{pending ? "در حال ثبت…" : "تأیید"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </>;
}
