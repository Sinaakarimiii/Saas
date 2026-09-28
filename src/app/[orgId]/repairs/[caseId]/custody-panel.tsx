"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairDeviceCustodyBaselineAction, releaseRepairDeviceCustodyAction,
  resolveRepairDeviceCustodyAction, recordRepairCustodyDiscrepancyAction,
  resolveRepairCustodyDiscrepancyAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { formatJalaliDateTime } from "@/lib/jalali";

type Position = { case_id: string; location: string; custodian_user_id: string | null; custodian_label: string;
  holder_kind: string; external_reference: string | null; confirmed_at: string };
type Transfer = { id: string; case_id: string; source_location: string; source_custodian_user_id: string;
  source_custodian_label: string; destination_location: string; destination_user_id: string;
  destination_label: string; carrier: string; release_reference: string; release_evidence: string;
  released_at: string; status: string; version: number; resolution_reference: string | null;
  resolution_evidence: string | null; resolved_at: string | null };
type Discrepancy = { id: string; transfer_id: string; kind: string; reference: string; evidence: string;
  responsible_user_id: string; due_at: string; recorded_at: string; status: string; version: number;
  resolution_reference: string | null; resolution_evidence: string | null; resolved_at: string | null };
const discrepancyNames: Record<string, string> = {
  identity_mismatch: "اختلاف شناسهٔ دستگاه", destination_mismatch: "اختلاف مقصد", damage: "آسیب‌دیدگی",
};

export function CustodyPanel({ orgId, caseId, expectedVersion, deviceId, receiptLocation,
  currentUserId, members, position, transfers, discrepancies, canBaseline, canRelease, canAccept, canReturn,
  canRecordDiscrepancy, canResolveDiscrepancy, closed }: {
  orgId: string; caseId: string; expectedVersion: number; deviceId: string | null;
  receiptLocation: string | null; currentUserId: string; members: { id: string; label: string }[];
  position: Position | null; transfers: Transfer[]; discrepancies: Discrepancy[];
  canBaseline: boolean; canRelease: boolean; canAccept: boolean; canReturn: boolean;
  canRecordDiscrepancy: boolean; canResolveDiscrepancy: boolean; closed: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [baseline, setBaseline] = useState({ location: receiptLocation ?? "", custodianUserId: "", evidence: "" });
  const [release, setRelease] = useState({ destinationLocation: "", destinationUserId: "", carrier: "",
    releaseReference: "", releaseEvidence: "" });
  const [resolution, setResolution] = useState<{ transferId: string; outcome: "accepted" | "returned" } | null>(null);
  const [reference, setReference] = useState("");
  const [evidence, setEvidence] = useState("");
  const [discrepancyForm, setDiscrepancyForm] = useState(false);
  const [discrepancy, setDiscrepancy] = useState({ kind: "identity_mismatch", reference: "", evidence: "",
    responsibleUserId: "", dueAt: "" });
  const [resolutionForm, setResolutionForm] = useState<string | null>(null);
  const [resolutionData, setResolutionData] = useState({ reference: "", evidence: "" });
  const open = transfers.find((item) => item.status === "in_transit");
  const needsNewBaseline = !position || (position.holder_kind === "recipient" && position.case_id !== caseId);
  const openDiscrepancy = discrepancies.find((item) => item.status === "open");
  const discrepancyTransfer = openDiscrepancy && transfers.find((item) => item.id === openDiscrepancy.transfer_id);
  function edit() { key.current = null; setError(""); }
  async function submit(action: () => Promise<{ error?: string }>) {
    if (busy) return;
    key.current ??= crypto.randomUUID(); setBusy(true); setError("");
    try {
      const result = await action();
      if (result.error) { setError(result.error); return; }
      key.current = null; setResolution(null); setDiscrepancyForm(false); setResolutionForm(null); router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت دستگاه را بررسی کنید و دوباره تلاش کنید."); }
    finally { setBusy(false); }
  }
  if (!deviceId) return null;
  return <Card><CardHeader><CardTitle>موقعیت و جابه‌جایی فیزیکی دستگاه اصلی</CardTitle></CardHeader>
    <CardContent className="grid gap-4 text-sm">
      <p className="text-muted-foreground">مسئول رسیدگی پرونده از نگهدارندهٔ فیزیکی دستگاه مستقل است. حوالهٔ داخلی پس از رسید مقصد و خروج بیرونی پس از ثبت ارسال یا تحویل واقعی، موقعیت را به‌روز می‌کند.</p>
      {position ? <p>{position.holder_kind === "scrapped" ? "محل اجرای اسقاط:" : "محل تأییدشده:"} <strong>{position.location}</strong> · {position.holder_kind === "staff" ? "نگهدارندهٔ سازمانی" : position.holder_kind === "carrier" ? "حامل" : position.holder_kind === "scrapped" ? "وضعیت نهایی" : "گیرنده"}: <strong>{position.custodian_label}</strong> · {formatJalaliDateTime(position.confirmed_at)}</p>
        : <p className="text-amber-700 dark:text-amber-300">برای این دستگاه هنوز محل و نگهدارندهٔ تأییدشده ثبت نشده است.</p>}
      {position?.holder_kind === "recipient" && position.case_id !== caseId && <p className="text-amber-700 dark:text-amber-300">دستگاه در پروندهٔ قبلی به گیرنده تحویل شده است. دریافت فیزیکی این پرونده ثبت شده؛ پیش از جابه‌جایی داخلی، محل و نگهدارندهٔ فعلی را با مدرک تازه تأیید کنید.</p>}
      {needsNewBaseline && !closed && canBaseline && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => recordRepairDeviceCustodyBaselineAction({ orgId, caseId,
          ...baseline, expectedVersion, idempotencyKey: key.current }));
      }}>
        <div className="grid gap-1"><Label htmlFor="custody-location">محل فعلی تأییدشده</Label><Input id="custody-location" required maxLength={200} value={baseline.location} onChange={(event) => { edit(); setBaseline({ ...baseline, location: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="custody-member">نگهدارندهٔ فعلی</Label><select id="custody-member" required className="h-9 rounded-lg border border-input bg-background px-2" value={baseline.custodianUserId} onChange={(event) => { edit(); setBaseline({ ...baseline, custodianUserId: event.target.value }); }}><option value="">انتخاب کنید</option>{members.map((member) => <option key={member.id} value={member.id}>{member.label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="custody-baseline-evidence">مرجع مدرک بررسی فیزیکی</Label><Input id="custody-baseline-evidence" required maxLength={240} value={baseline.evidence} onChange={(event) => { edit(); setBaseline({ ...baseline, evidence: event.target.value }); }} /></div>
        <div className="self-end"><Button type="submit" disabled={busy}>تأیید موقعیت فعلی</Button></div>
      </form>}
      {open && <div className="grid gap-2 rounded-xl border border-primary/30 bg-primary/5 p-4">
        <p className="font-medium">در مسیر: {open.source_location} ← {open.destination_location}</p>
        <p>گیرندهٔ مقصد: {open.destination_label} · حامل: {open.carrier}</p>
        <p className="text-muted-foreground">حواله: {open.release_reference} · مدرک خروج: {open.release_evidence} · {formatJalaliDateTime(open.released_at)}</p>
        <div className="flex flex-wrap gap-2">
          {open.case_id === caseId && !openDiscrepancy && canAccept && open.destination_user_id === currentUserId && <Button size="sm" onClick={() => { edit(); setResolution({ transferId: open.id, outcome: "accepted" }); }}>ثبت دریافت واقعی مقصد</Button>}
          {open.case_id === caseId && canReturn && open.source_custodian_user_id === currentUserId && <Button size="sm" variant="outline" onClick={() => { edit(); setResolution({ transferId: open.id, outcome: "returned" }); }}>ثبت بازگشت واقعی به مبدأ</Button>}
          {open.case_id === caseId && !openDiscrepancy && canRecordDiscrepancy && open.destination_user_id === currentUserId && <Button size="sm" variant="outline" onClick={() => { edit(); setResolution(null); setDiscrepancyForm(true); }}>ثبت مغایرت پذیرش</Button>}
        </div>
      </div>}
      {open && (!openDiscrepancy || resolution?.outcome === "returned") && resolution?.transferId === open.id && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => resolveRepairDeviceCustodyAction({ orgId, caseId,
          ...resolution, reference, evidence, expectedVersion, idempotencyKey: key.current }));
      }}>
        <p className="sm:col-span-2 font-medium">{resolution.outcome === "accepted" ? "رسید واقعی مقصد" : "رسید بازگشت واقعی به مبدأ"}</p>
        <div className="grid gap-1"><Label htmlFor="custody-receipt-ref">مرجع یکتای رسید</Label><Input id="custody-receipt-ref" required maxLength={160} value={reference} onChange={(event) => { edit(); setReference(event.target.value); }} /></div>
        <div className="grid gap-1"><Label htmlFor="custody-receipt-evidence">مرجع مدرک دریافت فیزیکی</Label><Input id="custody-receipt-evidence" required maxLength={240} value={evidence} onChange={(event) => { edit(); setEvidence(event.target.value); }} /></div>
        <div className="flex gap-2 sm:col-span-2"><Button type="button" variant="outline" onClick={() => setResolution(null)}>انصراف</Button><Button type="submit" disabled={busy}>تأیید رسید</Button></div>
      </form>}
      {open && discrepancyForm && !openDiscrepancy && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => recordRepairCustodyDiscrepancyAction({ orgId, caseId,
          transferId: open.id, ...discrepancy, dueAt: new Date(discrepancy.dueAt).toISOString(),
          expectedVersion, expectedTransferVersion: open.version, idempotencyKey: key.current }));
      }}>
        <p className="sm:col-span-2 font-medium">ثبت مغایرت این حواله</p>
        <div className="grid gap-1"><Label htmlFor="custody-discrepancy-kind">نوع</Label><select id="custody-discrepancy-kind" className="h-9 rounded-lg border border-input bg-background px-2" value={discrepancy.kind} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, kind: event.target.value }); }}>{Object.entries(discrepancyNames).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="custody-discrepancy-responsible">مسئول پیگیری</Label><select id="custody-discrepancy-responsible" required className="h-9 rounded-lg border border-input bg-background px-2" value={discrepancy.responsibleUserId} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, responsibleUserId: event.target.value }); }}><option value="">انتخاب کنید</option>{members.map((member) => <option key={member.id} value={member.id}>{member.label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="custody-discrepancy-due">موعد پیگیری</Label><Input id="custody-discrepancy-due" type="datetime-local" required value={discrepancy.dueAt} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, dueAt: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="custody-discrepancy-ref">مرجع یکتا</Label><Input id="custody-discrepancy-ref" required maxLength={160} value={discrepancy.reference} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, reference: event.target.value }); }} /></div>
        <div className="grid gap-1 sm:col-span-2"><Label htmlFor="custody-discrepancy-evidence">مرجع مدرک مغایرت</Label><Input id="custody-discrepancy-evidence" required maxLength={240} value={discrepancy.evidence} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, evidence: event.target.value }); }} /></div>
        <div className="flex gap-2 sm:col-span-2"><Button type="button" variant="outline" onClick={() => setDiscrepancyForm(false)}>انصراف</Button><Button type="submit" disabled={busy}>ثبت مغایرت</Button></div>
      </form>}
      {openDiscrepancy && <div className="grid gap-2 rounded-xl border border-amber-500/50 bg-amber-500/10 p-4">
        <p className="font-medium">مغایرت فعال: {discrepancyNames[openDiscrepancy.kind]}</p>
        <p>مرجع {openDiscrepancy.reference} · مسئول {members.find((member) => member.id === openDiscrepancy.responsible_user_id)?.label ?? "عضو سازمان"} · موعد {formatJalaliDateTime(openDiscrepancy.due_at)}</p>
        <p>مدرک: {openDiscrepancy.evidence}</p>
        {openDiscrepancy.kind === "damage" && discrepancyTransfer?.status !== "returned" && <p>برای آسیب‌دیدگی، ابتدا بازگشت واقعی به مبدأ را با رسید مستقل ثبت کنید؛ سپس بازبینی تست لازم است.</p>}
        {openDiscrepancy.kind !== "damage" && <p>{discrepancyTransfer?.status === "returned" ? "دستگاه به مبدأ برگشته است؛ پس از رفع مغایرت می‌توان حوالهٔ تازه ثبت کرد." : "رفع این مغایرت فقط راه ثبت رسید تازهٔ مقصد را باز می‌کند."}</p>}
        {canResolveDiscrepancy && discrepancyTransfer && (openDiscrepancy.kind !== "damage" || discrepancyTransfer.status === "returned") && <Button size="sm" variant="outline" className="w-fit" onClick={() => { edit(); setResolutionForm(openDiscrepancy.id); }}>ثبت رفع مستند</Button>}
      </div>}
      {openDiscrepancy && resolutionForm === openDiscrepancy.id && discrepancyTransfer && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => resolveRepairCustodyDiscrepancyAction({ orgId, caseId,
          discrepancyId: openDiscrepancy.id, ...resolutionData, expectedVersion,
          expectedTransferVersion: discrepancyTransfer.version, expectedDiscrepancyVersion: openDiscrepancy.version,
          idempotencyKey: key.current }));
      }}>
        <p className="sm:col-span-2 font-medium">رفع مستند مغایرت</p>
        <div className="grid gap-1"><Label htmlFor="custody-discrepancy-resolve-ref">مرجع یکتای رفع</Label><Input id="custody-discrepancy-resolve-ref" required maxLength={160} value={resolutionData.reference} onChange={(event) => { edit(); setResolutionData({ ...resolutionData, reference: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="custody-discrepancy-resolve-evidence">مرجع مدرک رفع</Label><Input id="custody-discrepancy-resolve-evidence" required maxLength={240} value={resolutionData.evidence} onChange={(event) => { edit(); setResolutionData({ ...resolutionData, evidence: event.target.value }); }} /></div>
        <div className="flex gap-2 sm:col-span-2"><Button type="button" variant="outline" onClick={() => setResolutionForm(null)}>انصراف</Button><Button type="submit" disabled={busy}>ثبت رفع</Button></div>
      </form>}
      {position && position.case_id === caseId && position.holder_kind === "staff" && !open && !openDiscrepancy && !closed && canRelease && position.custodian_user_id === currentUserId && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => releaseRepairDeviceCustodyAction({ orgId, caseId,
          ...release, expectedVersion, idempotencyKey: key.current }));
      }}>
        <p className="sm:col-span-2 font-medium">ثبت حوالهٔ خروج جدید</p>
        <div className="grid gap-1"><Label htmlFor="custody-destination">محل مقصد</Label><Input id="custody-destination" required maxLength={200} value={release.destinationLocation} onChange={(event) => { edit(); setRelease({ ...release, destinationLocation: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="custody-target">گیرندهٔ مقصد</Label><select id="custody-target" required className="h-9 rounded-lg border border-input bg-background px-2" value={release.destinationUserId} onChange={(event) => { edit(); setRelease({ ...release, destinationUserId: event.target.value }); }}><option value="">انتخاب کنید</option>{members.map((member) => <option key={member.id} value={member.id}>{member.label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="custody-carrier">حامل / روش انتقال</Label><Input id="custody-carrier" required maxLength={160} value={release.carrier} onChange={(event) => { edit(); setRelease({ ...release, carrier: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="custody-issue-ref">مرجع یکتای حواله</Label><Input id="custody-issue-ref" required maxLength={160} value={release.releaseReference} onChange={(event) => { edit(); setRelease({ ...release, releaseReference: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="custody-release-evidence">مرجع مدرک خروج</Label><Input id="custody-release-evidence" required maxLength={240} value={release.releaseEvidence} onChange={(event) => { edit(); setRelease({ ...release, releaseEvidence: event.target.value }); }} /></div>
        <div className="self-end"><Button type="submit" disabled={busy}>ثبت خروج فیزیکی</Button></div>
      </form>}
      {error && <p role="alert" className="text-destructive">{error}</p>}
      {transfers.length > 0 && <div className="grid gap-2 border-t pt-4"><p className="font-medium">سابقهٔ حواله‌ها</p>{transfers.map((item) => <p key={item.id} className="rounded-lg border p-3">
        {item.source_location} ← {item.destination_location} · {item.status === "in_transit" ? "در مسیر" : item.status === "accepted" ? "دریافت‌شده در مقصد" : "بازگشته به مبدأ"} · {item.release_reference}
        {item.resolution_reference && ` · رسید: ${item.resolution_reference}`}{item.resolution_evidence && ` · مدرک: ${item.resolution_evidence}`}
      </p>)}</div>}
      {discrepancies.length > 0 && <div className="grid gap-2 border-t pt-4"><p className="font-medium">سابقهٔ مغایرت‌ها</p>{discrepancies.map((item) => <p key={item.id} className="rounded-lg border p-3">
        {discrepancyNames[item.kind]} · {item.status === "open" ? "باز" : "رفع‌شده"} · {item.reference}
        {item.resolution_reference && ` · رفع: ${item.resolution_reference}`}
      </p>)}</div>}
    </CardContent></Card>;
}
