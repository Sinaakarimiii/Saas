"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairFunctionalTestAction, releaseRepairFunctionalTestAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

type Item = "identity" | "power" | "position" | "configuration";
type Status = "pass" | "fail" | "not_applicable";
type Answer = { status: Status; evidence: string };
type Test = {
  id: string; revision: number; plan_id: string; completion_id: string; device_id: string;
  custody_damage_epoch: number; passed: boolean; recorded_at: string;
  identity_status: string; identity_evidence: string; power_status: string; power_evidence: string;
  position_status: string; position_evidence: string;
  configuration_status: string; configuration_evidence: string;
};
const items: { key: Item; label: string; optional: boolean; hint: string }[] = [
  { key: "identity", label: "شناسه و اقلام دستگاه", optional: false, hint: "IMEI و اقلام را با پرونده و رسید دریافت تطبیق دهید." },
  { key: "power", label: "روشن‌شدن و عملکرد پایه", optional: false, hint: "نتیجهٔ راه‌اندازی و عملکرد پایه را ثبت کنید." },
  { key: "position", label: "موقعیت و ارتباط", optional: true, hint: "اگر برای این مدل کاربرد ندارد، علت نامرتبط بودن را بنویسید." },
  { key: "configuration", label: "تنظیمات و خدمات", optional: true, hint: "تنظیمات و خدمات مربوط به این دستگاه را بررسی کنید." },
];
const initial: Record<Item, Answer> = {
  identity: { status: "pass", evidence: "" }, power: { status: "pass", evidence: "" },
  position: { status: "pass", evidence: "" }, configuration: { status: "pass", evidence: "" },
};
const statusLabel: Record<string, string> = { pass: "قبول", fail: "رد", not_applicable: "نامرتبط" };

export function RepairFunctionalTest({ orgId, caseId, expectedVersion, planId, completionId, deviceId,
  damageEpoch, stageEnteredAt, latest, released, canRecord, canRelease, custodyBlocked }: {
  orgId: string; caseId: string; expectedVersion: number; planId: string; completionId: string | null;
  deviceId: string | null; damageEpoch: number; stageEnteredAt: string; latest: Test | null;
  released: boolean; canRecord: boolean; canRelease: boolean; custodyBlocked: boolean;
}) {
  const router = useRouter();
  const recordKey = useRef<string | null>(null);
  const releaseKey = useRef<string | null>(null);
  const [answers, setAnswers] = useState<Record<Item, Answer>>(initial);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const current = Boolean(latest && latest.plan_id === planId && latest.completion_id === completionId
    && latest.device_id === deviceId && latest.custody_damage_epoch === damageEpoch
    && new Date(latest.recorded_at).getTime() >= new Date(stageEnteredAt).getTime());
  async function record(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); recordKey.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairFunctionalTestAction({
        orgId, caseId, expectedVersion, idempotencyKey: recordKey.current,
        identityStatus: answers.identity.status, identityEvidence: answers.identity.evidence,
        powerStatus: answers.power.status, powerEvidence: answers.power.evidence,
        positionStatus: answers.position.status, positionEvidence: answers.position.evidence,
        configurationStatus: answers.configuration.status, configurationEvidence: answers.configuration.evidence,
      });
      if (result.error) { setError(result.error); return; }
      recordKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  async function release() {
    if (!latest || pending) return;
    setPending(true); setError(""); releaseKey.current ??= crypto.randomUUID();
    try {
      const result = await releaseRepairFunctionalTestAction({
        orgId, caseId, testId: latest.id, expectedVersion, idempotencyKey: releaseKey.current,
      });
      if (result.error) { setError(result.error); return; }
      releaseKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  return <Card><CardHeader><CardTitle>آزمون عملکرد تعمیر</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">نتیجهٔ هر کنترل با شاهد آن ثبت می‌شود. نتیجهٔ کلی از کنترل‌ها محاسبه می‌شود؛ تست ردشده در سابقه می‌ماند و تست تازه لازم دارد. آزادسازی کیفیت یک اقدام مستقل است و هنوز پرونده را به تحویل نمی‌برد.</p>
    {custodyBlocked && <p role="alert" className="text-destructive">انتقال یا مغایرت باز دستگاه باید تعیین تکلیف شود.</p>}
    {latest && <div className="rounded-xl border border-border/70 p-4">
      <p className="font-medium">آخرین تست · نسخهٔ {latest.revision}: {current ? latest.passed ? released ? "موفق و آزادشده" : "موفق، منتظر آزادسازی کیفیت" : "ناموفق؛ تست دوباره لازم است" : "نامعتبر برای وضعیت فعلی دستگاه"}</p>
      <ul className="mt-2 grid gap-1">{items.map(({ key, label }) => <li key={key}>{label}: {statusLabel[latest[`${key}_status`]]} · {latest[`${key}_evidence`]}</li>)}</ul>
      {current && latest.passed && !released && !custodyBlocked && (canRelease
        ? <Button className="mt-3" disabled={pending} onClick={release}>آزادسازی مستقل تست</Button>
        : <p className="mt-2 text-muted-foreground">برای آزادسازی، مجوز مستقل کیفیت لازم است.</p>)}
    </div>}
    {canRecord && completionId && deviceId ? <form onSubmit={record} className="grid gap-4">
      {items.map(({ key, label, optional, hint }) => <fieldset key={key} className="grid gap-2 rounded-xl border border-border/70 p-3">
        <legend className="px-1 font-medium">{label}</legend><p className="text-muted-foreground">{hint}</p>
        <div className="flex flex-wrap gap-4">{(["pass", "fail", ...(optional ? ["not_applicable"] : [])] as Status[]).map((status) =>
          <label key={status} className="flex items-center gap-1"><input type="radio" name={`test-${key}`} checked={answers[key].status === status}
            onChange={() => { recordKey.current = null; setAnswers({ ...answers, [key]: { ...answers[key], status } }); }} />{statusLabel[status]}</label>)}</div>
        <Input required maxLength={500} aria-label={`شاهد ${label}`} placeholder={answers[key].status === "not_applicable" ? "علت نامرتبط بودن" : "مرجع سند یا مشاهدهٔ فنی"}
          value={answers[key].evidence} onChange={(event) => { recordKey.current = null; setAnswers({ ...answers, [key]: { ...answers[key], evidence: event.target.value } }); }} />
      </fieldset>)}
      {error && <p role="alert" className="text-destructive">{error}</p>}
      <Button type="submit" disabled={pending || custodyBlocked} className="justify-self-start">{pending ? "در حال ثبت…" : "ثبت نسخهٔ تست"}</Button>
    </form> : !canRecord ? <p className="text-muted-foreground">ثبت تست به مجوز مستقل نیاز دارد.</p>
      : <p className="text-destructive">تکمیل تعمیر و شناسایی دستگاه برای آزمون لازم است.</p>}
    {error && !canRecord && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
