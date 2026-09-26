"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { resolveRepairPartQuarantineAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type ReturnMovement = { id: string; part_id: string; quantity: number; reference: string };
type Resolution = { id: string; return_movement_id: string; quantity: number;
  outcome: string; inspection_note: string; evidence_reference: string; decision_reference: string };
type Part = { id: string; sku: string; name: string };

export function QuarantinePanel({ orgId, caseId, expectedVersion, parts, returns,
  resolutions, canRestock, canReject }: {
  orgId: string; caseId: string; expectedVersion: number; parts: Part[];
  returns: ReturnMovement[]; resolutions: Resolution[];
  canRestock: boolean; canReject: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ returnMovementId: "", outcome: "", quantity: "1",
    inspectionNote: "", evidenceReference: "", decisionReference: "" });
  const pending = returns.map((item) => ({ ...item, remaining: item.quantity - resolutions
    .filter((resolution) => resolution.return_movement_id === item.id)
    .reduce((sum, resolution) => sum + resolution.quantity, 0),
  }));
  const available = pending.filter((item) => item.remaining > 0);
  const label = (partId: string) => {
    const part = parts.find((item) => item.id === partId);
    return part ? `${part.name} · ${part.sku}` : partId;
  };
  function update<K extends keyof typeof form>(keyName: K, value: (typeof form)[K]) {
    key.current = null; setError(""); setForm((previous) => ({ ...previous, [keyName]: value }));
  }
  if (returns.length === 0) return null;
  return <Card><CardHeader><CardTitle>تعیین تکلیف قطعات قرنطینه</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p className="text-muted-foreground">بازگشت از تعمیر تا ثبت نتیجهٔ بررسی، قابل رزرو نیست. «مردود» فقط به معنی نگهداری جداگانه است و اسقاط یا خروج فیزیکی را ثبت نمی‌کند.</p>
    <ul className="grid gap-2">{pending.map((item) => <li key={item.id} className="rounded-lg border p-3">
      {label(item.part_id)} · مرجع بازگشت {item.reference} · تعداد {item.quantity.toLocaleString("fa-IR")} · {item.remaining > 0 ? `در انتظار بررسی ${item.remaining.toLocaleString("fa-IR")}` : "تعیین تکلیف شد"}
    </li>)}</ul>
    {available.length > 0 && (canRestock || canReject) && <form className="grid gap-3 border-t pt-4 sm:grid-cols-2" onSubmit={async (event) => {
      event.preventDefault(); if (busy) return;
      key.current ??= crypto.randomUUID(); setBusy(true); setError("");
      try {
        const result = await resolveRepairPartQuarantineAction({ orgId, caseId,
          returnMovementId: form.returnMovementId, outcome: form.outcome,
          quantity: Number(form.quantity), inspectionNote: form.inspectionNote,
          evidenceReference: form.evidenceReference, decisionReference: form.decisionReference,
          expectedVersion, idempotencyKey: key.current });
        if (result.error) { setError(result.error); return; }
        key.current = null;
        setForm({ returnMovementId: "", outcome: "", quantity: "1",
          inspectionNote: "", evidenceReference: "", decisionReference: "" });
        router.refresh();
      } catch { setError("ارتباط برقرار نشد. وضعیت ثبت را بررسی کنید و دوباره تلاش کنید."); }
      finally { setBusy(false); }
    }}>
      <div className="grid gap-1"><Label htmlFor="quarantine-return">بازگشت مورد بررسی</Label><select id="quarantine-return" required className="h-9 rounded-lg border border-input bg-background px-2" value={form.returnMovementId} onChange={(event) => update("returnMovementId", event.target.value)}><option value="">انتخاب کنید</option>{available.map((item) => <option key={item.id} value={item.id}>{label(item.part_id)} · {item.reference} · مانده {item.remaining}</option>)}</select></div>
      <div className="grid gap-1"><Label htmlFor="quarantine-outcome">نتیجهٔ بررسی</Label><select id="quarantine-outcome" required className="h-9 rounded-lg border border-input bg-background px-2" value={form.outcome} onChange={(event) => update("outcome", event.target.value)}><option value="">انتخاب کنید</option>{canRestock && <option value="released_to_stock">قابل استفاده؛ ورود به موجودی آزاد</option>}{canReject && <option value="rejected_hold">مردود؛ نگهداری جداگانه</option>}</select></div>
      <div className="grid gap-1"><Label htmlFor="quarantine-quantity">تعداد</Label><Input id="quarantine-quantity" type="number" min="1" max={available.find((item) => item.id === form.returnMovementId)?.remaining} step="1" required value={form.quantity} onChange={(event) => update("quantity", event.target.value)} /></div>
      <div className="grid gap-1"><Label htmlFor="quarantine-note">نتیجه و شرح بررسی</Label><Input id="quarantine-note" required maxLength={1000} value={form.inspectionNote} onChange={(event) => update("inspectionNote", event.target.value)} /></div>
      <div className="grid gap-1"><Label htmlFor="quarantine-evidence">مرجع مدرک بررسی</Label><Input id="quarantine-evidence" required maxLength={240} value={form.evidenceReference} onChange={(event) => update("evidenceReference", event.target.value)} /></div>
      <div className="grid gap-1"><Label htmlFor="quarantine-reference">مرجع یکتای تصمیم</Label><Input id="quarantine-reference" required maxLength={240} value={form.decisionReference} onChange={(event) => update("decisionReference", event.target.value)} /></div>
      <Button type="submit" disabled={busy || !form.returnMovementId || !form.outcome}>ثبت نتیجهٔ بررسی</Button>
    </form>}
    {resolutions.length > 0 && <div className="grid gap-2 border-t pt-4"><p className="font-medium">تصمیم‌های ثبت‌شده</p>{resolutions.map((item) => <p key={item.id} className="rounded-lg border p-2">{item.outcome === "released_to_stock" ? "بازگشت به موجودی قابل استفاده" : "مردود؛ نگهداری جداگانه"} · {item.quantity.toLocaleString("fa-IR")} عدد · {item.decision_reference} · {item.inspection_note} · مدرک: {item.evidence_reference}</p>)}</div>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
