"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { releaseRepairReplacementCustodyAction, resolveRepairReplacementCustodyAction,
  recordRepairCustodyDiscrepancyAction, resolveRepairCustodyDiscrepancyAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { formatJalaliDateTime } from "@/lib/jalali";

type Transfer = { id: string; source_location: string; destination_location: string;
  source_custodian_user_id: string; destination_user_id: string; status: string;
  release_reference: string; resolution_reference: string | null; version: number };
type Discrepancy = { id: string; transfer_id: string; kind: string; reference: string;
  evidence: string; responsible_user_id: string; due_at: string; status: string; version: number;
  resolution_reference: string | null };
const discrepancyNames: Record<string, string> = {
  identity_mismatch: "اختلاف شناسهٔ دستگاه", destination_mismatch: "اختلاف مقصد", damage: "آسیب‌دیدگی",
};

export function ReplacementCustodyPanel({ orgId, caseId, deviceId, imei, expectedVersion,
  currentUserId, location, custodianUserId, members, transfers, discrepancies,
  canRelease, canAccept, canReturn, canRecordDiscrepancy, canResolveDiscrepancy }: {
  orgId: string; caseId: string; deviceId: string; imei: string; expectedVersion: number;
  currentUserId: string; location: string; custodianUserId: string;
  members: { id: string; label: string }[]; transfers: Transfer[]; discrepancies: Discrepancy[];
  canRelease: boolean; canAccept: boolean; canReturn: boolean;
  canRecordDiscrepancy: boolean; canResolveDiscrepancy: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [release, setRelease] = useState({ destinationLocation: "", destinationUserId: "",
    carrier: "", releaseReference: "", releaseEvidence: "" });
  const [resolution, setResolution] = useState<{ transferId: string; outcome: "accepted" | "returned" } | null>(null);
  const [reference, setReference] = useState("");
  const [evidence, setEvidence] = useState("");
  const [discrepancyForm, setDiscrepancyForm] = useState(false);
  const [discrepancy, setDiscrepancy] = useState({ kind: "identity_mismatch", reference: "", evidence: "",
    responsibleUserId: "", dueAt: "" });
  const [resolutionForm, setResolutionForm] = useState<string | null>(null);
  const [resolutionData, setResolutionData] = useState({ reference: "", evidence: "" });
  const open = transfers.find((item) => item.status === "in_transit");
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
    } catch { setError("ارتباط برقرار نشد. وضعیت دستگاه را تازه کنید و دوباره تلاش کنید."); }
    finally { setBusy(false); }
  }
  return <Card><CardHeader><CardTitle>جابه‌جایی داخلی دستگاه جایگزین</CardTitle></CardHeader>
    <CardContent className="grid gap-4 text-sm">
      <p>IMEI: <strong dir="ltr">{imei}</strong> · محل تأییدشده: <strong>{location}</strong></p>
      <p className="text-muted-foreground">حواله، محل موجودی را تغییر نمی‌دهد. دریافت واقعی مقصد، محل و نگهدارندهٔ همین دستگاه را در موجودی به‌روز می‌کند.</p>
      {open && <div className="grid gap-2 rounded-xl border p-4">
        <p>حوالهٔ باز: {open.source_location} ← {open.destination_location} · {open.release_reference}</p>
        <div className="flex gap-2">
          {canAccept && !openDiscrepancy && currentUserId === open.destination_user_id && <Button type="button" disabled={busy} onClick={() => { edit(); setResolution({ transferId: open.id, outcome: "accepted" }); }}>ثبت دریافت مقصد</Button>}
          {canReturn && currentUserId === open.source_custodian_user_id && <Button type="button" variant="outline" disabled={busy} onClick={() => { edit(); setResolution({ transferId: open.id, outcome: "returned" }); }}>ثبت بازگشت به مبدأ</Button>}
          {canRecordDiscrepancy && !openDiscrepancy && currentUserId === open.destination_user_id && <Button type="button" variant="outline" disabled={busy} onClick={() => { edit(); setResolution(null); setDiscrepancyForm(true); }}>ثبت مغایرت پذیرش</Button>}
        </div>
      </div>}
      {resolution && (!openDiscrepancy || resolution.outcome === "returned") && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => resolveRepairReplacementCustodyAction({ orgId, caseId,
          ...resolution, reference, evidence, expectedVersion, idempotencyKey: key.current }));
      }}>
        <p className="sm:col-span-2 font-medium">{resolution.outcome === "accepted" ? "رسید دریافت فیزیکی مقصد" : "رسید بازگشت فیزیکی به مبدأ"}</p>
        <div className="grid gap-1"><Label htmlFor="replacement-custody-resolution-ref">مرجع یکتای رسید</Label><Input id="replacement-custody-resolution-ref" required maxLength={160} value={reference} onChange={(event) => { edit(); setReference(event.target.value); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-custody-resolution-evidence">مرجع مدرک</Label><Input id="replacement-custody-resolution-evidence" required maxLength={240} value={evidence} onChange={(event) => { edit(); setEvidence(event.target.value); }} /></div>
        <div className="flex gap-2 sm:col-span-2"><Button type="button" variant="outline" onClick={() => setResolution(null)}>انصراف</Button><Button disabled={busy}>ثبت رسید</Button></div>
      </form>}
      {open && discrepancyForm && !openDiscrepancy && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => recordRepairCustodyDiscrepancyAction({ orgId, caseId,
          transferId: open.id, ...discrepancy, dueAt: new Date(discrepancy.dueAt).toISOString(),
          expectedVersion, expectedTransferVersion: open.version, idempotencyKey: key.current }));
      }}>
        <p className="sm:col-span-2 font-medium">مغایرت دستگاه جایگزین</p>
        <div className="grid gap-1"><Label htmlFor="replacement-discrepancy-kind">نوع</Label><select id="replacement-discrepancy-kind" className="h-9 rounded-lg border border-input bg-background px-2" value={discrepancy.kind} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, kind: event.target.value }); }}>{Object.entries(discrepancyNames).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="replacement-discrepancy-responsible">مسئول پیگیری</Label><select id="replacement-discrepancy-responsible" required className="h-9 rounded-lg border border-input bg-background px-2" value={discrepancy.responsibleUserId} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, responsibleUserId: event.target.value }); }}><option value="">انتخاب کنید</option>{members.map((member) => <option key={member.id} value={member.id}>{member.label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="replacement-discrepancy-due">موعد پیگیری</Label><Input id="replacement-discrepancy-due" type="datetime-local" required value={discrepancy.dueAt} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, dueAt: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-discrepancy-ref">مرجع یکتا</Label><Input id="replacement-discrepancy-ref" required maxLength={160} value={discrepancy.reference} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, reference: event.target.value }); }} /></div>
        <div className="grid gap-1 sm:col-span-2"><Label htmlFor="replacement-discrepancy-evidence">مرجع مدرک</Label><Input id="replacement-discrepancy-evidence" required maxLength={240} value={discrepancy.evidence} onChange={(event) => { edit(); setDiscrepancy({ ...discrepancy, evidence: event.target.value }); }} /></div>
        <div className="flex gap-2 sm:col-span-2"><Button type="button" variant="outline" onClick={() => setDiscrepancyForm(false)}>انصراف</Button><Button disabled={busy}>ثبت مغایرت</Button></div>
      </form>}
      {openDiscrepancy && <div className="grid gap-2 rounded-xl border border-amber-500/50 bg-amber-500/10 p-4">
        <p className="font-medium">مغایرت فعال: {discrepancyNames[openDiscrepancy.kind]}</p>
        <p>مرجع {openDiscrepancy.reference} · مسئول {members.find((member) => member.id === openDiscrepancy.responsible_user_id)?.label ?? "عضو سازمان"} · موعد {formatJalaliDateTime(openDiscrepancy.due_at)}</p>
        <p>مدرک: {openDiscrepancy.evidence}</p>
        <p>{openDiscrepancy.kind === "damage" ? "ابتدا بازگشت واقعی به مبدأ را با رسید مستقل ثبت کنید؛ سپس آسیب را تعیین تکلیف کنید." : discrepancyTransfer?.status === "returned" ? "دستگاه به مبدأ برگشته است؛ پس از رفع مغایرت می‌توان حوالهٔ تازه ثبت کرد." : "رفع مغایرت فقط امکان ثبت رسید تازهٔ مقصد را باز می‌کند."}</p>
        {canResolveDiscrepancy && discrepancyTransfer && (openDiscrepancy.kind !== "damage" || discrepancyTransfer.status === "returned") && <Button type="button" size="sm" variant="outline" className="w-fit" onClick={() => { edit(); setResolutionForm(openDiscrepancy.id); }}>ثبت رفع مستند</Button>}
      </div>}
      {openDiscrepancy && resolutionForm === openDiscrepancy.id && discrepancyTransfer && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => resolveRepairCustodyDiscrepancyAction({ orgId, caseId,
          discrepancyId: openDiscrepancy.id, ...resolutionData, expectedVersion,
          expectedTransferVersion: discrepancyTransfer.version, expectedDiscrepancyVersion: openDiscrepancy.version,
          idempotencyKey: key.current }));
      }}>
        <p className="sm:col-span-2 font-medium">رفع مستند مغایرت</p>
        <div className="grid gap-1"><Label htmlFor="replacement-discrepancy-resolution-ref">مرجع یکتای رفع</Label><Input id="replacement-discrepancy-resolution-ref" required maxLength={160} value={resolutionData.reference} onChange={(event) => { edit(); setResolutionData({ ...resolutionData, reference: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-discrepancy-resolution-evidence">مرجع مدرک رفع</Label><Input id="replacement-discrepancy-resolution-evidence" required maxLength={240} value={resolutionData.evidence} onChange={(event) => { edit(); setResolutionData({ ...resolutionData, evidence: event.target.value }); }} /></div>
        <div className="flex gap-2 sm:col-span-2"><Button type="button" variant="outline" onClick={() => setResolutionForm(null)}>انصراف</Button><Button disabled={busy}>ثبت رفع</Button></div>
      </form>}
      {!open && !openDiscrepancy && canRelease && currentUserId === custodianUserId && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => releaseRepairReplacementCustodyAction({ orgId, caseId, deviceId,
          ...release, expectedVersion, idempotencyKey: key.current }));
      }}>
        <p className="sm:col-span-2 font-medium">حوالهٔ خروج داخلی جدید</p>
        <div className="grid gap-1"><Label htmlFor="replacement-custody-location">محل مقصد</Label><Input id="replacement-custody-location" required maxLength={200} value={release.destinationLocation} onChange={(event) => { edit(); setRelease({ ...release, destinationLocation: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-custody-user">گیرندهٔ مقصد</Label><select id="replacement-custody-user" required className="h-9 rounded-lg border border-input bg-background px-2" value={release.destinationUserId} onChange={(event) => { edit(); setRelease({ ...release, destinationUserId: event.target.value }); }}><option value="">انتخاب کنید</option>{members.map((member) => <option key={member.id} value={member.id}>{member.label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="replacement-custody-carrier">حامل / روش انتقال</Label><Input id="replacement-custody-carrier" required maxLength={160} value={release.carrier} onChange={(event) => { edit(); setRelease({ ...release, carrier: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-custody-release-ref">مرجع یکتای حواله</Label><Input id="replacement-custody-release-ref" required maxLength={160} value={release.releaseReference} onChange={(event) => { edit(); setRelease({ ...release, releaseReference: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-custody-release-evidence">مرجع مدرک خروج</Label><Input id="replacement-custody-release-evidence" required maxLength={240} value={release.releaseEvidence} onChange={(event) => { edit(); setRelease({ ...release, releaseEvidence: event.target.value }); }} /></div>
        <div className="self-end"><Button disabled={busy}>ثبت خروج فیزیکی</Button></div>
      </form>}
      {error && <p role="alert" className="text-destructive">{error}</p>}
      {transfers.length > 0 && <div className="grid gap-2 border-t pt-4"><p className="font-medium">سابقهٔ حواله‌ها</p>{transfers.map((item) => <p key={item.id} className="rounded-lg border p-3">{item.source_location} ← {item.destination_location} · {item.status === "in_transit" ? "در مسیر" : item.status === "accepted" ? "دریافت‌شده" : "بازگشته"} · {item.release_reference}{item.resolution_reference && ` · رسید: ${item.resolution_reference}`}</p>)}</div>}
      {discrepancies.length > 0 && <div className="grid gap-2 border-t pt-4"><p className="font-medium">سابقهٔ مغایرت‌ها</p>{discrepancies.map((item) => <p key={item.id} className="rounded-lg border p-3">{discrepancyNames[item.kind]} · {item.status === "open" ? "باز" : "رفع‌شده"} · {item.reference}{item.resolution_reference && ` · رفع: ${item.resolution_reference}`}</p>)}</div>}
    </CardContent></Card>;
}
