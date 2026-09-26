"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairOutgoingCheckAction, releaseRepairOutgoingCheckAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

type Item = "identity" | "items" | "condition" | "transport";
type Answer = { pass: boolean; evidence: string };
type Check = {
  id: string; revision: number; plan_id: string; functional_test_id: string; device_id: string;
  custody_damage_epoch: number; recorded_at: string; intended_recipient: string;
  recipient_role: string; authority_reference: string | null;
  identity_pass: boolean; identity_evidence: string; items_pass: boolean; items_evidence: string;
  condition_pass: boolean; condition_evidence: string; transport_pass: boolean; transport_evidence: string;
};
const items: { key: Item; label: string }[] = [
  { key: "identity", label: "شناسهٔ دستگاه" }, { key: "items", label: "اقلام همراه" },
  { key: "condition", label: "وضعیت فنی پس از تعمیر" }, { key: "transport", label: "ایمنی حمل" },
];
const initial: Record<Item, Answer> = {
  identity: { pass: true, evidence: "" }, items: { pass: true, evidence: "" },
  condition: { pass: true, evidence: "" }, transport: { pass: true, evidence: "" },
};

export function RepairOutgoingCheck({ orgId, caseId, expectedVersion, planId, testId, deviceId,
  damageEpoch, stageEnteredAt, latest, released, functionalReleased, custodyBlocked, canRecord, canRelease }: {
  orgId: string; caseId: string; expectedVersion: number; planId: string; testId: string | null;
  deviceId: string | null; damageEpoch: number; stageEnteredAt: string; latest: Check | null;
  released: boolean; functionalReleased: boolean; custodyBlocked: boolean;
  canRecord: boolean; canRelease: boolean;
}) {
  const router = useRouter();
  const recordKey = useRef<string | null>(null);
  const releaseKey = useRef<string | null>(null);
  const [answers, setAnswers] = useState<Record<Item, Answer>>(initial);
  const [recipient, setRecipient] = useState("");
  const [role, setRole] = useState<"owner" | "authorized_representative" | "colleague">("owner");
  const [authority, setAuthority] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const current = Boolean(latest && latest.plan_id === planId && latest.functional_test_id === testId
    && latest.device_id === deviceId && latest.custody_damage_epoch === damageEpoch
    && new Date(latest.recorded_at).getTime() >= new Date(stageEnteredAt).getTime());
  const passed = Boolean(current && latest?.identity_pass && latest.items_pass && latest.condition_pass && latest.transport_pass);
  async function record(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); recordKey.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairOutgoingCheckAction({ orgId, caseId, expectedVersion,
        idempotencyKey: recordKey.current,
        identityPass: answers.identity.pass, identityEvidence: answers.identity.evidence,
        itemsPass: answers.items.pass, itemsEvidence: answers.items.evidence,
        conditionPass: answers.condition.pass, conditionEvidence: answers.condition.evidence,
        transportPass: answers.transport.pass, transportEvidence: answers.transport.evidence,
        intendedRecipient: recipient, recipientRole: role, authorityReference: authority });
      if (result.error) { setError(result.error); return; }
      recordKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  async function release() {
    if (!latest || pending) return;
    setPending(true); setError(""); releaseKey.current ??= crypto.randomUUID();
    try {
      const result = await releaseRepairOutgoingCheckAction({ orgId, caseId, checkId: latest.id,
        expectedVersion, idempotencyKey: releaseKey.current });
      if (result.error) { setError(result.error); return; }
      releaseKey.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  return <Card><CardHeader><CardTitle>کنترل خروج دستگاه تعمیرشده</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">پس از آزادسازی آزمون عملکرد، چهار کنترل خروج و گیرندهٔ موردنظر را ثبت کنید. نتیجهٔ ناموفق در سابقه می‌ماند و به کنترل تازه نیاز دارد. آزادسازی این کنترل هنوز انتقال به تحویل یا رسید فیزیکی نیست.</p>
    {!functionalReleased && <p className="text-muted-foreground">ابتدا آخرین آزمون عملکرد موفق را آزاد کنید.</p>}
    {custodyBlocked && <p role="alert" className="text-destructive">انتقال یا مغایرت باز دستگاه باید تعیین تکلیف شود.</p>}
    {latest && <div className="rounded-xl border border-border/70 p-3">
      <p className="font-medium">آخرین کنترل · نسخهٔ {latest.revision}: {current ? passed ? released ? "موفق و آزادشده" : "موفق، منتظر آزادسازی" : "ناموفق؛ کنترل دوباره لازم است" : "نامعتبر برای وضعیت فعلی"}</p>
      <p>گیرندهٔ موردنظر: {latest.intended_recipient} · {latest.recipient_role === "owner" ? "صاحب دستگاه" : latest.recipient_role === "colleague" ? "همکار" : "نمایندهٔ مجاز"} · مرجع اختیار: {latest.authority_reference ?? "—"}</p>
      <ul className="mt-2 grid gap-1">{items.map(({ key, label }) => <li key={key}>{label}: {latest[`${key}_pass`] ? "قبول" : "رد"} · {latest[`${key}_evidence`]}</li>)}</ul>
      {current && passed && !released && functionalReleased && !custodyBlocked && (canRelease
        ? <Button className="mt-3" disabled={pending} onClick={release}>آزادسازی مستقل کنترل خروج</Button>
        : <p className="text-muted-foreground">مجوز مستقل کیفیت لازم است.</p>)}
    </div>}
    {canRecord && functionalReleased && testId && deviceId && !custodyBlocked && <form onSubmit={record} className="grid gap-3">
      {items.map(({ key, label }) => <fieldset key={key} className="grid gap-2 rounded-xl border border-border/70 p-3">
        <legend className="px-1 font-medium">{label}</legend>
        <div className="flex gap-4">{[true, false].map((pass) => <label key={String(pass)} className="flex items-center gap-1">
          <input type="radio" name={`repair-outgoing-${key}`} checked={answers[key].pass === pass}
            onChange={() => { recordKey.current = null; setAnswers({ ...answers, [key]: { ...answers[key], pass } }); }} />{pass ? "قبول" : "رد"}</label>)}</div>
        <Input required maxLength={500} aria-label={`شاهد ${label}`} placeholder="مرجع سند یا مشاهده"
          value={answers[key].evidence} onChange={(event) => { recordKey.current = null; setAnswers({ ...answers, [key]: { ...answers[key], evidence: event.target.value } }); }} />
      </fieldset>)}
      <Input required maxLength={160} aria-label="گیرندهٔ موردنظر" placeholder="نام گیرندهٔ موردنظر" value={recipient}
        onChange={(event) => { recordKey.current = null; setRecipient(event.target.value); }} />
      <select className="h-10 rounded-md border border-input bg-background px-3" aria-label="نسبت گیرنده" value={role}
        onChange={(event) => { recordKey.current = null; setRole(event.target.value as typeof role); }}>
        <option value="owner">صاحب دستگاه</option><option value="authorized_representative">نمایندهٔ مجاز</option><option value="colleague">همکار</option>
      </select>
      {role !== "owner" && <Input required maxLength={240} aria-label="مرجع اختیار گیرنده" placeholder="مرجع اختیار تحویل"
        value={authority} onChange={(event) => { recordKey.current = null; setAuthority(event.target.value); }} />}
      <Button type="submit" disabled={pending} className="justify-self-start">ثبت نسخهٔ کنترل خروج</Button>
    </form>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
