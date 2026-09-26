"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairReturnOutgoingCheckAction, releaseRepairReturnOutgoingCheckAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type ItemKey = "identity" | "items" | "condition" | "transport";
const checks: { key: ItemKey; label: string; hint: string }[] = [
  { key: "identity", label: "هویت دستگاه", hint: "تطبیق IMEI با برچسب و پرونده" },
  { key: "items", label: "اقلام همراه", hint: "تطبیق اقلام خروجی با رسید دریافت" },
  { key: "condition", label: "وضعیت فنی اعلام‌شده", hint: "تطبیق برگهٔ عودت با نتیجهٔ تشخیص و اطلاع‌رسانی؛ به معنی سلامت نیست" },
  { key: "transport", label: "ایمنی حمل", hint: "آمادگی بسته‌بندی و حمل بدون آسیب بیشتر" },
];
type LatestCheck = {
  id: string; revision: number; plan_id: string; authorization_id: string; device_id: string;
  custody_damage_epoch: number;
  identity_pass: boolean; identity_evidence: string; items_pass: boolean; items_evidence: string;
  condition_pass: boolean; condition_evidence: string; transport_pass: boolean; transport_evidence: string;
  intended_recipient: string; recipient_role: string; authority_reference: string | null; created_at: string;
};

export function ReturnOutgoingCheck({ orgId, caseId, expectedVersion, planId, authorizationId, deviceId,
  stageEnteredAt, latest, released, canRecord, canRelease, damageEpoch, openDamage }: {
  orgId: string; caseId: string; expectedVersion: number; planId: string; authorizationId: string;
  deviceId: string | null; stageEnteredAt: string; latest: LatestCheck | null; released: boolean;
  canRecord: boolean; canRelease: boolean; damageEpoch: number; openDamage: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [recipient, setRecipient] = useState("");
  const [role, setRole] = useState<"owner" | "authorized_representative" | "colleague">("owner");
  const [authority, setAuthority] = useState("");
  const [answers, setAnswers] = useState<Record<ItemKey, { pass: boolean; evidence: string }>>({
    identity: { pass: true, evidence: "" }, items: { pass: true, evidence: "" },
    condition: { pass: true, evidence: "" }, transport: { pass: true, evidence: "" },
  });
  const current = Boolean(latest && latest.plan_id === planId && latest.authorization_id === authorizationId
    && latest.device_id === deviceId && latest.custody_damage_epoch === damageEpoch
    && new Date(latest.created_at).getTime() >= new Date(stageEnteredAt).getTime());
  const passed = Boolean(current && latest?.identity_pass && latest.items_pass && latest.condition_pass && latest.transport_pass);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairReturnOutgoingCheckAction({
        orgId, caseId, expectedVersion, idempotencyKey: key.current,
        identityPass: answers.identity.pass, identityEvidence: answers.identity.evidence,
        itemsPass: answers.items.pass, itemsEvidence: answers.items.evidence,
        conditionPass: answers.condition.pass, conditionEvidence: answers.condition.evidence,
        transportPass: answers.transport.pass, transportEvidence: answers.transport.evidence,
        intendedRecipient: recipient, recipientRole: role, authorityReference: authority,
      });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  async function release() {
    if (!latest || pending) return;
    setPending(true); setError(""); key.current = crypto.randomUUID();
    try {
      const result = await releaseRepairReturnOutgoingCheckAction({
        orgId, caseId, checkId: latest.id, expectedVersion, idempotencyKey: key.current,
      });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  return <Card><CardHeader><CardTitle>کنترل خروج عودت</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">این پروتکل فقط آمادگی عودت را می‌سنجد و دستگاه را سالم یا تعمیرشده اعلام نمی‌کند. مرجع شواهد هر کنترل را ثبت کنید؛ می‌توانید نتیجهٔ ناموفق را نیز ثبت و سپس کنترل تازه‌ای انجام دهید.</p>
    {!deviceId && <p role="alert" className="text-destructive">IMEI هنوز با برچسب و مدرک تأیید نشده و کنترل خروج قابل ثبت نیست.</p>}
    {openDamage && <p role="alert" className="text-destructive">آسیب‌دیدگی باز است. پس از رسید بازگشت فیزیکی و تعیین تکلیف مستند، کنترل خروج تازه ثبت کنید.</p>}
    {!openDamage && latest && latest.custody_damage_epoch !== damageEpoch && <p role="alert" className="text-destructive">کنترل و آزادسازی قبلی با ثبت آسیب‌دیدگی نامعتبر شده‌اند؛ کنترل تازه لازم است.</p>}
    {latest && <div className="rounded-xl border border-border/70 p-4">
      <p className="font-medium">آخرین کنترل: نسخهٔ {latest.revision} · {current ? passed ? released ? "آزادشده" : "موفق، منتظر آزادسازی" : "ناموفق؛ کنترل دوباره لازم است" : "نامعتبر برای این نوبت"}</p>
      <p className="mt-1 text-muted-foreground">گیرندهٔ موردنظر: {latest.intended_recipient} · مرجع اختیار: {latest.authority_reference ?? "صاحب دستگاه"}</p>
      <ul className="mt-2 grid gap-1">{checks.map(({ key, label }) => <li key={key}>{label}: {latest[`${key}_pass`] ? "قبول" : "رد"} · {latest[`${key}_evidence`]}</li>)}</ul>
      {current && passed && !released && !openDamage && (canRelease ? <Button className="mt-3" disabled={pending} onClick={release}>آزادسازی مستقل کنترل خروج</Button>
        : <p className="mt-2 text-muted-foreground">آزادسازی به مجوز مستقل کیفیت نیاز دارد.</p>)}
    </div>}
    {canRecord && deviceId && !openDamage ? <form onSubmit={submit} className="grid gap-4">
      {checks.map(({ key: item, label, hint }) => <fieldset key={item} className="grid gap-2 rounded-xl border border-border/70 p-3">
        <legend className="px-1 font-medium">{label}</legend><p className="text-muted-foreground">{hint}</p>
        <div className="flex gap-4"><label><input type="radio" checked={answers[item].pass} onChange={() => { key.current = null; setAnswers({ ...answers, [item]: { ...answers[item], pass: true } }); }} /> قبول</label>
          <label><input type="radio" checked={!answers[item].pass} onChange={() => { key.current = null; setAnswers({ ...answers, [item]: { ...answers[item], pass: false } }); }} /> رد</label></div>
        <Input required maxLength={500} aria-label={`مرجع شواهد ${label}`} placeholder="مرجع سند یا توضیح مشاهده‌شده" value={answers[item].evidence}
          onChange={(event) => { key.current = null; setAnswers({ ...answers, [item]: { ...answers[item], evidence: event.target.value } }); }} />
      </fieldset>)}
      <div className="grid gap-3 sm:grid-cols-2"><div className="grid gap-2"><Label htmlFor="qc-recipient">گیرندهٔ موردنظر</Label><Input id="qc-recipient" required maxLength={160} value={recipient} onChange={(event) => { key.current = null; setRecipient(event.target.value); }} /></div>
        <div className="grid gap-2"><Label htmlFor="qc-role">نسبت گیرنده</Label><select id="qc-role" className="h-9 rounded-lg border border-input bg-background px-2" value={role} onChange={(event) => { key.current = null; setRole(event.target.value as typeof role); }}><option value="owner">صاحب دستگاه</option><option value="authorized_representative">نمایندهٔ مجاز</option><option value="colleague">همکار</option></select></div></div>
      {role !== "owner" && <div className="grid gap-2"><Label htmlFor="qc-authority">مرجع اختیار تحویل</Label><Input id="qc-authority" required maxLength={240} value={authority} onChange={(event) => { key.current = null; setAuthority(event.target.value); }} /></div>}
      {error && <p role="alert" className="text-destructive">{error}</p>}
      <div className="flex justify-end"><Button type="submit" disabled={pending}>{pending ? "در حال ثبت…" : "ثبت نسخهٔ کنترل خروج"}</Button></div>
    </form> : !canRecord && <p className="text-muted-foreground">ثبت کنترل خروج به مجوز مستقل نیاز دارد.</p>}
    {error && (!canRecord || !deviceId) && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
