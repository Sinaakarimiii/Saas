"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { consumeRepairPartAction, releaseUnusedRepairPartAction, returnConsumedRepairPartAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Part = { id: string; sku: string; name: string };
type Reservation = { id: string; part_id: string; quantity: number; consumed_quantity: number; status: string };
type Movement = { id: string; part_id: string; kind: string; quantity: number; reference: string;
  action_description: string | null; reason: string | null; source_consumption_id: string | null; recorded_at: string };

export function RepairExecutionPanel({ orgId, caseId, planId, expectedVersion, parts, reservations,
  movements, canConsume, canRelease, canReturn }: {
  orgId: string; caseId: string; planId: string; expectedVersion: number;
  parts: Part[]; reservations: Reservation[]; movements: Movement[];
  canConsume: boolean; canRelease: boolean; canReturn: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [consume, setConsume] = useState({ partId: "", quantity: "1", actionDescription: "", reference: "" });
  const [release, setRelease] = useState({ partId: "", reason: "", reference: "" });
  const [returnForm, setReturnForm] = useState({ consumptionId: "", quantity: "1", reason: "", reference: "" });
  function edit() { key.current = null; setError(""); }
  async function submit(operation: () => Promise<{ error?: string }>) {
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
  const partLabel = (id: string) => {
    const part = parts.find((item) => item.id === id);
    return part ? `${part.name} · ${part.sku}` : id;
  };
  const active = reservations.filter((item) => item.status === "active" && item.quantity > item.consumed_quantity);
  const consumptions = movements.filter((item) => item.kind === "consumption").map((item) => ({ ...item,
    returnable: item.quantity - movements.filter((other) => other.kind === "return_quarantine" && other.source_consumption_id === item.id)
      .reduce((sum, other) => sum + other.quantity, 0),
  }));
  return <Card><CardHeader><CardTitle>اقدامات تعمیر و گردش قطعه</CardTitle></CardHeader><CardContent className="grid gap-5 text-sm">
    <p className="text-muted-foreground">مصرف از رزرو همین برنامه کسر می‌شود. قطعهٔ مصرف‌شده در صورت بازگشت، تا تعیین تکلیف در قرنطینه می‌ماند و به موجودی آزاد افزوده نمی‌شود.</p>
    {reservations.length > 0 && <ul className="grid gap-2">{reservations.map((item) => <li key={item.id} className="rounded-lg border p-3">
      {partLabel(item.part_id)} · رزرو {item.quantity.toLocaleString("fa-IR")} · مصرف {item.consumed_quantity.toLocaleString("fa-IR")} · {item.status === "active" ? `ماندهٔ رزرو ${(item.quantity - item.consumed_quantity).toLocaleString("fa-IR")}` : item.status === "released" ? "مانده آزاد شد" : "تماماً مصرف شد"}
    </li>)}</ul>}
    {canConsume && active.length > 0 && <form className="grid gap-3 border-t pt-4 sm:grid-cols-2" onSubmit={(event) => {
      event.preventDefault(); key.current ??= crypto.randomUUID();
      void submit(() => consumeRepairPartAction({ orgId, caseId, planId, partId: consume.partId,
        quantity: Number(consume.quantity), actionDescription: consume.actionDescription,
        reference: consume.reference, expectedVersion, idempotencyKey: key.current }));
    }}>
      <p className="sm:col-span-2 font-medium">ثبت اقدام و حوالهٔ مصرف</p>
      <div className="grid gap-1"><Label htmlFor="consume-part">قطعهٔ رزروشده</Label><select id="consume-part" required className="h-9 rounded-lg border border-input bg-background px-2" value={consume.partId} onChange={(event) => { edit(); setConsume({ ...consume, partId: event.target.value }); }}><option value="">انتخاب کنید</option>{active.map((item) => <option key={item.id} value={item.part_id}>{partLabel(item.part_id)} · مانده {item.quantity - item.consumed_quantity}</option>)}</select></div>
      <div className="grid gap-1"><Label htmlFor="consume-quantity">تعداد مصرف</Label><Input id="consume-quantity" type="number" min="1" max={active.find((item) => item.part_id === consume.partId)?.quantity ? active.find((item) => item.part_id === consume.partId)!.quantity - active.find((item) => item.part_id === consume.partId)!.consumed_quantity : undefined} step="1" required value={consume.quantity} onChange={(event) => { edit(); setConsume({ ...consume, quantity: event.target.value }); }} /></div>
      <div className="grid gap-1 sm:col-span-2"><Label htmlFor="consume-action">شرح اقدام فنی</Label><Input id="consume-action" required maxLength={2000} value={consume.actionDescription} onChange={(event) => { edit(); setConsume({ ...consume, actionDescription: event.target.value }); }} /></div>
      <div className="grid gap-1"><Label htmlFor="consume-ref">مرجع یکتای حواله</Label><Input id="consume-ref" required maxLength={240} value={consume.reference} onChange={(event) => { edit(); setConsume({ ...consume, reference: event.target.value }); }} /></div>
      <Button type="submit" disabled={busy || !consume.partId} className="sm:self-end">ثبت مصرف</Button>
    </form>}
    {canRelease && active.length > 0 && <form className="grid gap-3 border-t pt-4 sm:grid-cols-2" onSubmit={(event) => {
      event.preventDefault(); key.current ??= crypto.randomUUID();
      void submit(() => releaseUnusedRepairPartAction({ orgId, caseId, planId, partId: release.partId,
        reason: release.reason, reference: release.reference, expectedVersion, idempotencyKey: key.current }));
    }}>
      <p className="sm:col-span-2 font-medium">آزادسازی ماندهٔ مصرف‌نشده</p>
      <div className="grid gap-1"><Label htmlFor="release-part">قطعه</Label><select id="release-part" required className="h-9 rounded-lg border border-input bg-background px-2" value={release.partId} onChange={(event) => { edit(); setRelease({ ...release, partId: event.target.value }); }}><option value="">انتخاب کنید</option>{active.map((item) => <option key={item.id} value={item.part_id}>{partLabel(item.part_id)} · مانده {item.quantity - item.consumed_quantity}</option>)}</select></div>
      <div className="grid gap-1"><Label htmlFor="release-reason">علت آزادسازی</Label><Input id="release-reason" required maxLength={500} value={release.reason} onChange={(event) => { edit(); setRelease({ ...release, reason: event.target.value }); }} /></div>
      <div className="grid gap-1"><Label htmlFor="release-ref">مرجع یکتا</Label><Input id="release-ref" required maxLength={240} value={release.reference} onChange={(event) => { edit(); setRelease({ ...release, reference: event.target.value }); }} /></div>
      <Button type="submit" disabled={busy || !release.partId} className="sm:self-end">آزادسازی مانده</Button>
    </form>}
    {canReturn && consumptions.some((item) => item.returnable > 0) && <form className="grid gap-3 border-t pt-4 sm:grid-cols-2" onSubmit={(event) => {
      event.preventDefault(); key.current ??= crypto.randomUUID();
      void submit(() => returnConsumedRepairPartAction({ orgId, caseId, consumptionId: returnForm.consumptionId,
        quantity: Number(returnForm.quantity), reason: returnForm.reason, reference: returnForm.reference,
        expectedVersion, idempotencyKey: key.current }));
    }}>
      <p className="sm:col-span-2 font-medium">بازگشت قطعهٔ مصرف‌شده به قرنطینه</p>
      <div className="grid gap-1"><Label htmlFor="return-consumption">حوالهٔ مصرف</Label><select id="return-consumption" required className="h-9 rounded-lg border border-input bg-background px-2" value={returnForm.consumptionId} onChange={(event) => { edit(); setReturnForm({ ...returnForm, consumptionId: event.target.value }); }}><option value="">انتخاب کنید</option>{consumptions.filter((item) => item.returnable > 0).map((item) => <option key={item.id} value={item.id}>{partLabel(item.part_id)} · {item.reference} · قابل بازگشت {item.returnable}</option>)}</select></div>
      <div className="grid gap-1"><Label htmlFor="return-quantity">تعداد بازگشت</Label><Input id="return-quantity" type="number" min="1" max={consumptions.find((item) => item.id === returnForm.consumptionId)?.returnable} step="1" required value={returnForm.quantity} onChange={(event) => { edit(); setReturnForm({ ...returnForm, quantity: event.target.value }); }} /></div>
      <div className="grid gap-1"><Label htmlFor="return-reason">علت بازگشت</Label><Input id="return-reason" required maxLength={500} value={returnForm.reason} onChange={(event) => { edit(); setReturnForm({ ...returnForm, reason: event.target.value }); }} /></div>
      <div className="grid gap-1"><Label htmlFor="return-ref">مرجع یکتا</Label><Input id="return-ref" required maxLength={240} value={returnForm.reference} onChange={(event) => { edit(); setReturnForm({ ...returnForm, reference: event.target.value }); }} /></div>
      <Button type="submit" disabled={busy || !returnForm.consumptionId}>ثبت بازگشت به قرنطینه</Button>
    </form>}
    {movements.length > 0 && <div className="grid gap-2 border-t pt-4"><p className="font-medium">گردش ثبت‌شده</p>{movements.map((item) => <p key={item.id} className="rounded-lg border p-2">{item.kind === "consumption" ? "مصرف" : "بازگشت به قرنطینه"} · {partLabel(item.part_id)} · {item.quantity.toLocaleString("fa-IR")} عدد · {item.reference}{item.action_description ? ` · ${item.action_description}` : item.reason ? ` · ${item.reason}` : ""}</p>)}</div>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
  </CardContent></Card>;
}
