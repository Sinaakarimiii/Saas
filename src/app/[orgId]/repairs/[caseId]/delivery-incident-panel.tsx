"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairDeliveryIncidentAction, followupRepairDeliveryIncidentAction,
  resolveRepairDeliveryIncidentAction, receiveRepairDeliveryDamageReturnAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Incident = { id: string; kind: string; reference: string; evidence: string; status: string;
  responsible_user_id: string; due_at: string; version: number; resolution_reference: string | null };
type Followup = { id: string; reference: string; outcome: string; next_due_at: string; recorded_at: string };
type Member = { id: string; label: string };
const labels: Record<string, string> = { lost: "مفقودی", damage: "آسیب‌دیدگی", delivery_discrepancy: "اختلاف تحویل" };

export function DeliveryIncidentPanel({ orgId, caseId, dispatchId, expectedVersion, received, incidents,
  followups, members, canRecord, canFollowup, canResolve, canReturn, dispatchStatus, damageReturn }: {
  orgId: string; caseId: string; dispatchId: string; expectedVersion: number; received: boolean;
  incidents: Incident[]; followups: Followup[]; members: Member[];
  canRecord: boolean; canFollowup: boolean; canResolve: boolean; canReturn: boolean;
  dispatchStatus: string; damageReturn: { return_reference: string; location: string; condition_note: string } | null;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [kind, setKind] = useState<"lost" | "damage" | "delivery_discrepancy">("lost");
  const [reference, setReference] = useState("");
  const [evidence, setEvidence] = useState("");
  const [followupReference, setFollowupReference] = useState("");
  const [resolutionReference, setResolutionReference] = useState("");
  const [resolutionEvidence, setResolutionEvidence] = useState("");
  const [outcome, setOutcome] = useState("");
  const [returnLocation, setReturnLocation] = useState("");
  const [returnCondition, setReturnCondition] = useState("");
  const [returnReference, setReturnReference] = useState("");
  const [returnEvidence, setReturnEvidence] = useState("");
  const [memberId, setMemberId] = useState(members[0]?.id ?? "");
  const [dueAt, setDueAt] = useState("");
  const open = incidents.find((item) => item.status === "open");
  const edit = () => { key.current = null; setError(""); };
  async function submit(event: React.FormEvent<HTMLFormElement>, mode: "record" | "followup" | "resolve") {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const common = { orgId, caseId, expectedVersion, idempotencyKey: key.current };
      const result = mode === "record"
        ? await recordRepairDeliveryIncidentAction({ ...common, dispatchId, kind, reference, evidence,
            responsibleUserId: memberId, dueAt: new Date(dueAt).toISOString() })
        : mode === "followup" && open
        ? await followupRepairDeliveryIncidentAction({ ...common, incidentId: open.id,
            expectedIncidentVersion: open.version, reference: followupReference, outcome,
            responsibleUserId: memberId, dueAt: new Date(dueAt).toISOString() })
        : open ? await resolveRepairDeliveryIncidentAction({ ...common, incidentId: open.id,
            expectedIncidentVersion: open.version, resolutionReference, resolutionEvidence })
        : { error: "مسئلهٔ باز پیدا نشد." };
      if (result.error) { setError(result.error); return; }
      key.current = null; setReference(""); setEvidence(""); setFollowupReference("");
      setResolutionReference(""); setResolutionEvidence(""); setOutcome("");
      router.refresh();
    } catch { setError("ارتباط برقرار نشد یا موعد معتبر نیست. وضعیت پرونده را بررسی کنید."); }
    finally { setPending(false); }
  }
  async function submitReturn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending || !open || open.kind !== "damage") return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await receiveRepairDeliveryDamageReturnAction({ orgId, caseId, dispatchId,
        incidentId: open.id, expectedVersion, expectedIncidentVersion: open.version,
        idempotencyKey: key.current, location: returnLocation, conditionNote: returnCondition,
        returnReference, returnEvidence });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید."); }
    finally { setPending(false); }
  }
  return <Card><CardHeader><CardTitle>مسئله و پیگیری حمل</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    {incidents.map((item) => <div key={item.id} className="rounded-xl border border-border/70 bg-background/40 p-3">
      <p className="font-medium">{labels[item.kind]} · {item.status === "open" ? "باز و مانع تحویل" : "رفع‌شده"}</p>
      <p className="mt-1 text-muted-foreground">مرجع: {item.reference} · موعد: {new Date(item.due_at).toLocaleString("fa-IR")}</p>
      {item.resolution_reference && <p className="mt-1">مرجع رفع: {item.resolution_reference}</p>}
    </div>)}
    {damageReturn && <div className="rounded-xl border border-primary/30 bg-primary/5 p-3">
      بازگشت فیزیکی ثبت شد · {damageReturn.location} · مرجع {damageReturn.return_reference}
      <p className="mt-1 text-muted-foreground">وضعیت هنگام بازگشت: {damageReturn.condition_note}</p>
    </div>}
    {followups.map((item) => <div key={item.id} className="rounded-lg border border-border/50 p-3">
      پیگیری {item.reference}: {item.outcome} · موعد بعدی {new Date(item.next_due_at).toLocaleString("fa-IR")}
    </div>)}
    {!open && !received && dispatchStatus === "in_transit" && canRecord && <form onSubmit={(event) => submit(event, "record")} className="grid gap-3 sm:grid-cols-2">
      <div className="grid gap-2"><Label htmlFor="incident-kind">نوع مسئله</Label><select id="incident-kind" className="h-9 rounded-lg border border-input bg-background px-2" value={kind} onChange={(event) => { edit(); setKind(event.target.value as typeof kind); }}><option value="lost">مفقودی</option><option value="damage">آسیب‌دیدگی</option><option value="delivery_discrepancy">اختلاف تحویل</option></select></div>
      <div className="grid gap-2"><Label htmlFor="incident-ref">مرجع یکتای مسئله</Label><Input id="incident-ref" required maxLength={160} value={reference} onChange={(event) => { edit(); setReference(event.target.value); }} /></div>
      <div className="grid gap-2"><Label htmlFor="incident-evidence">مدرک مسئله</Label><Input id="incident-evidence" required maxLength={240} value={evidence} onChange={(event) => { edit(); setEvidence(event.target.value); }} /></div>
      {assignmentFields("record")}
      <div className="sm:col-span-2 flex justify-end"><Button disabled={pending} type="submit">ثبت مسئلهٔ حمل</Button></div>
    </form>}
    {open && <div className="grid gap-3">
      <p className="text-destructive">تا رفع مستند این مسئله، رسید مقصد و بستن پرونده مسدود است.</p>
      {canFollowup && <form onSubmit={(event) => submit(event, "followup")} className="grid gap-3 sm:grid-cols-2">
        <div className="grid gap-2"><Label htmlFor="followup-ref">مرجع یکتای پیگیری</Label><Input id="followup-ref" required maxLength={160} value={followupReference} onChange={(event) => { edit(); setFollowupReference(event.target.value); }} /></div>
        <div className="grid gap-2"><Label htmlFor="followup-outcome">نتیجهٔ پیگیری</Label><Input id="followup-outcome" required maxLength={1000} value={outcome} onChange={(event) => { edit(); setOutcome(event.target.value); }} /></div>
        {assignmentFields("followup")}
        <div className="sm:col-span-2 flex justify-end"><Button variant="outline" disabled={pending} type="submit">ثبت پیگیری</Button></div>
      </form>}
      {open.kind === "damage" ? canReturn ? <form onSubmit={submitReturn} className="grid gap-3 sm:grid-cols-2">
        <p className="sm:col-span-2">دریافت واقعی دستگاه از حامل را ثبت کنید. پس از آن، کنترل خروج قبلی باطل و بازگشت به تست ممکن می‌شود.</p>
        <div className="grid gap-2"><Label htmlFor="damage-return-location">محل دریافت فیزیکی</Label><Input id="damage-return-location" required maxLength={200} value={returnLocation} onChange={(event) => { edit(); setReturnLocation(event.target.value); }} /></div>
        <div className="grid gap-2"><Label htmlFor="damage-return-reference">مرجع یکتای بازگشت</Label><Input id="damage-return-reference" required maxLength={160} value={returnReference} onChange={(event) => { edit(); setReturnReference(event.target.value); }} /></div>
        <div className="grid gap-2 sm:col-span-2"><Label htmlFor="damage-return-condition">وضعیت دستگاه هنگام دریافت</Label><Input id="damage-return-condition" required maxLength={1000} value={returnCondition} onChange={(event) => { edit(); setReturnCondition(event.target.value); }} /></div>
        <div className="grid gap-2 sm:col-span-2"><Label htmlFor="damage-return-evidence">مدرک مستقل بازگشت</Label><Input id="damage-return-evidence" required maxLength={240} value={returnEvidence} onChange={(event) => { edit(); setReturnEvidence(event.target.value); }} /></div>
        <div className="sm:col-span-2 flex justify-end"><Button disabled={pending} type="submit">ثبت بازگشت فیزیکی</Button></div>
      </form> : <p>ثبت بازگشت فیزیکی به مجوز مستقل نیاز دارد.</p>
      : canResolve && <form onSubmit={(event) => submit(event, "resolve")} className="grid gap-3 sm:grid-cols-2">
        <div className="grid gap-2"><Label htmlFor="resolve-ref">مرجع یکتای رفع</Label><Input id="resolve-ref" required maxLength={160} value={resolutionReference} onChange={(event) => { edit(); setResolutionReference(event.target.value); }} /></div>
        <div className="grid gap-2"><Label htmlFor="resolve-evidence">مدرک رفع</Label><Input id="resolve-evidence" required maxLength={240} value={resolutionEvidence} onChange={(event) => { edit(); setResolutionEvidence(event.target.value); }} /></div>
        <div className="sm:col-span-2 flex justify-end"><Button disabled={pending} type="submit">رفع مسئله و ادامهٔ حمل</Button></div>
      </form>}
    </div>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;

  function assignmentFields(prefix: string) {
    return <><div className="grid gap-2"><Label htmlFor={`${prefix}-owner`}>مسئول پیگیری</Label><select id={`${prefix}-owner`} required className="h-9 rounded-lg border border-input bg-background px-2" value={memberId} onChange={(event) => { edit(); setMemberId(event.target.value); }}>{members.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></div>
      <div className="grid gap-2"><Label htmlFor={`${prefix}-due`}>موعد پیگیری</Label><Input id={`${prefix}-due`} type="datetime-local" required value={dueAt} onChange={(event) => { edit(); setDueAt(event.target.value); }} /></div></>;
  }
}
