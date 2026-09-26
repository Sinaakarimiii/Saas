"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { receiveRepairPartAction, requireRepairPartAction, reserveRepairPartAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Part = { id: string; sku: string; name: string; on_hand: number; free: number };
type Requirement = { part_id: string; quantity: number; reserved: boolean };

export function PartsPanel({ orgId, caseId, planId, expectedVersion, parts, requirements,
  canReceive, canRequire, canReserve }: {
  orgId: string; caseId: string; planId: string; expectedVersion: number;
  parts: Part[]; requirements: Requirement[];
  canReceive: boolean; canRequire: boolean; canReserve: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [receipt, setReceipt] = useState({ sku: "", name: "", quantity: "1", evidenceReference: "" });
  const [requirement, setRequirement] = useState({ partId: "", quantity: "1" });
  function resetKey() { key.current = null; setError(""); }
  async function run(operation: () => Promise<{ error?: string }>) {
    if (busy) return;
    setBusy(true); setError("");
    try {
      const result = await operation();
      if (result.error) { setError(result.error); return; }
      key.current = null;
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت ثبت را بررسی کنید و دوباره تلاش کنید."); }
    finally { setBusy(false); }
  }
  const allReady = requirements.length > 0 && requirements.every((item) => item.reserved);
  return <Card><CardHeader><CardTitle>تأمین قطعات برنامه</CardTitle></CardHeader><CardContent className="grid gap-5 text-sm">
    <p className="text-muted-foreground">برای ورود به تعمیر، همهٔ قطعات لازم همین نسخهٔ برنامه باید از موجودی آزاد رزرو شوند. رزرو به‌معنای مصرف قطعه نیست.</p>
    <p className={allReady ? "text-emerald-700 dark:text-emerald-300" : "text-amber-700 dark:text-amber-300"}>
      {allReady ? "قطعات این برنامه آمادهٔ شروع تعمیرند." : "نیاز قطعه یا رزرو آن هنوز کامل نیست."}
    </p>
    {requirements.length > 0 && <ul className="grid gap-2">{requirements.map((item) => {
      const part = parts.find((entry) => entry.id === item.part_id);
      return <li key={item.part_id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border p-3">
        <span>{part?.name ?? "قطعه"} · {part?.sku ?? item.part_id} · {item.quantity.toLocaleString("fa-IR")} عدد</span>
        {item.reserved ? <span className="text-emerald-700 dark:text-emerald-300">رزرو شده</span>
          : canReserve ? <Button size="sm" disabled={busy} onClick={() => { key.current ??= crypto.randomUUID(); void run(() => reserveRepairPartAction({ orgId, caseId, planId, partId: item.part_id, expectedVersion, idempotencyKey: key.current })); }}>رزرو از موجودی</Button>
          : <span>در انتظار رزرو</span>}
      </li>;
    })}</ul>}
    {canRequire && <form className="grid gap-3 sm:grid-cols-[1fr_8rem_auto] sm:items-end" onSubmit={(event) => {
      event.preventDefault(); key.current ??= crypto.randomUUID();
      void run(() => requireRepairPartAction({ orgId, caseId, planId, partId: requirement.partId,
        quantity: Number(requirement.quantity), expectedVersion, idempotencyKey: key.current }));
    }}>
      <div className="grid gap-1"><Label htmlFor="required-part">قطعهٔ موردنیاز</Label><select id="required-part" required className="h-9 rounded-lg border border-input bg-background px-2" value={requirement.partId} onChange={(event) => { resetKey(); setRequirement({ ...requirement, partId: event.target.value }); }}><option value="">انتخاب قطعه</option>{parts.filter((part) => !requirements.some((item) => item.part_id === part.id)).map((part) => <option key={part.id} value={part.id}>{part.name} · {part.sku} · آزاد {part.free}</option>)}</select></div>
      <div className="grid gap-1"><Label htmlFor="required-quantity">تعداد</Label><Input id="required-quantity" type="number" min="1" step="1" required value={requirement.quantity} onChange={(event) => { resetKey(); setRequirement({ ...requirement, quantity: event.target.value }); }} /></div>
      <Button type="submit" disabled={busy || !requirement.partId}>افزودن نیاز</Button>
    </form>}
    {canReceive && <form className="grid gap-3 border-t pt-4 sm:grid-cols-2" onSubmit={(event) => {
      event.preventDefault(); key.current ??= crypto.randomUUID();
      void run(() => receiveRepairPartAction({ orgId, sku: receipt.sku, name: receipt.name,
        quantity: Number(receipt.quantity), evidenceReference: receipt.evidenceReference, idempotencyKey: key.current }));
    }}>
      <p className="sm:col-span-2 font-medium">ثبت ورود مستند قطعه به موجودی سازمان</p>
      <div className="grid gap-1"><Label htmlFor="part-sku">شناسهٔ قطعه (SKU)</Label><Input id="part-sku" required maxLength={64} value={receipt.sku} onChange={(event) => { resetKey(); setReceipt({ ...receipt, sku: event.target.value }); }} /></div>
      <div className="grid gap-1"><Label htmlFor="part-name">نام قطعه</Label><Input id="part-name" required maxLength={160} value={receipt.name} onChange={(event) => { resetKey(); setReceipt({ ...receipt, name: event.target.value }); }} /></div>
      <div className="grid gap-1"><Label htmlFor="part-quantity">تعداد ورودی</Label><Input id="part-quantity" type="number" min="1" step="1" required value={receipt.quantity} onChange={(event) => { resetKey(); setReceipt({ ...receipt, quantity: event.target.value }); }} /></div>
      <div className="grid gap-1"><Label htmlFor="part-evidence">مرجع سند ورود</Label><Input id="part-evidence" required maxLength={240} value={receipt.evidenceReference} onChange={(event) => { resetKey(); setReceipt({ ...receipt, evidenceReference: event.target.value }); }} /></div>
      <Button className="sm:col-span-2 sm:justify-self-start" type="submit" disabled={busy}>ثبت ورود قطعه</Button>
    </form>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
