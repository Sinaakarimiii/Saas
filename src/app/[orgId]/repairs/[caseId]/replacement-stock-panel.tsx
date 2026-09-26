"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { allocateRepairReplacementDeviceAction, receiveRepairReplacementStockAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Stock = { device_id: string; model: string; location: string; custodian_label: string;
  repair_devices: { imei: string } | null };

export function ReplacementStockPanel({ orgId, caseId, planId, model, expectedVersion,
  members, stock, allocated, canReceive, canAllocate }: {
  orgId: string; caseId: string; planId: string; model: string; expectedVersion: number;
  members: { id: string; label: string }[]; stock: Stock[];
  allocated: Stock | null; canReceive: boolean; canAllocate: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [received, setReceived] = useState({ imei: "", location: "", custodianUserId: "",
    evidence: "", receiptReference: "" });
  const [deviceId, setDeviceId] = useState("");
  const [allocationReference, setAllocationReference] = useState("");
  function edit() { key.current = null; setError(""); }
  async function submit(action: () => Promise<{ error?: string }>) {
    if (busy) return;
    key.current ??= crypto.randomUUID(); setBusy(true); setError("");
    try {
      const result = await action();
      if (result.error) { setError(result.error); return; }
      key.current = null; router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت موجودی را بررسی کنید و دوباره تلاش کنید."); }
    finally { setBusy(false); }
  }
  return <Card><CardHeader><CardTitle>دستگاه جایگزین · مدل {model}</CardTitle></CardHeader>
    <CardContent className="grid gap-4 text-sm">
      <p className="text-muted-foreground">دریافت موجودی با IMEI و مدرک، محل و نگهدارنده ثبت می‌شود. تخصیص یک دستگاه مشخص را برای همین نسخهٔ برنامه رزرو می‌کند؛ اجرای تعویض و تحویل هنوز جدا هستند.</p>
      {allocated ? <p className="rounded-lg border p-3">دستگاه تخصیص‌یافته: <strong dir="ltr">{allocated.repair_devices?.imei}</strong> · {allocated.location} · نزد {allocated.custodian_label}</p>
        : <p className="text-amber-700 dark:text-amber-300">هنوز دستگاه مشخصی به پرونده تخصیص داده نشده است.</p>}
      {!allocated && canAllocate && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => allocateRepairReplacementDeviceAction({ orgId, caseId,
          planId, deviceId, allocationReference, expectedVersion, idempotencyKey: key.current }));
      }}>
        <div className="grid gap-1"><Label htmlFor="replacement-device">دستگاه آزادِ همین مدل</Label><select id="replacement-device" required className="h-9 rounded-lg border border-input bg-background px-2" value={deviceId} onChange={(event) => { edit(); setDeviceId(event.target.value); }}><option value="">انتخاب کنید</option>{stock.map((item) => <option key={item.device_id} value={item.device_id}>{item.repair_devices?.imei} · {item.location} · {item.custodian_label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="replacement-allocation-reference">مرجع یکتای تخصیص</Label><Input id="replacement-allocation-reference" required maxLength={160} value={allocationReference} onChange={(event) => { edit(); setAllocationReference(event.target.value); }} /></div>
        <Button disabled={busy || stock.length === 0} className="sm:col-span-2">{busy ? "در حال ثبت…" : "تخصیص دستگاه مشخص"}</Button>
      </form>}
      {canReceive && <form className="grid gap-3 rounded-xl border p-4 sm:grid-cols-2" onSubmit={(event) => {
        event.preventDefault(); void submit(() => receiveRepairReplacementStockAction({ orgId, caseId,
          model, ...received, idempotencyKey: key.current }));
      }}>
        <p className="font-medium sm:col-span-2">دریافت دستگاه سریال‌دار به موجودی</p>
        <div className="grid gap-1"><Label htmlFor="replacement-imei">IMEI مطابق برچسب</Label><Input id="replacement-imei" required inputMode="numeric" pattern="[0-9]{15}" maxLength={15} value={received.imei} onChange={(event) => { edit(); setReceived({ ...received, imei: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-location">محل فیزیکی فعلی</Label><Input id="replacement-location" required maxLength={200} value={received.location} onChange={(event) => { edit(); setReceived({ ...received, location: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-custodian">نگهدارندهٔ فعلی</Label><select id="replacement-custodian" required className="h-9 rounded-lg border border-input bg-background px-2" value={received.custodianUserId} onChange={(event) => { edit(); setReceived({ ...received, custodianUserId: event.target.value }); }}><option value="">انتخاب کنید</option>{members.map((member) => <option key={member.id} value={member.id}>{member.label}</option>)}</select></div>
        <div className="grid gap-1"><Label htmlFor="replacement-evidence">مرجع مدرک برچسب و دریافت</Label><Input id="replacement-evidence" required maxLength={240} value={received.evidence} onChange={(event) => { edit(); setReceived({ ...received, evidence: event.target.value }); }} /></div>
        <div className="grid gap-1"><Label htmlFor="replacement-receipt-reference">مرجع یکتای ورود موجودی</Label><Input id="replacement-receipt-reference" required maxLength={160} value={received.receiptReference} onChange={(event) => { edit(); setReceived({ ...received, receiptReference: event.target.value }); }} /></div>
        <Button disabled={busy} className="sm:col-span-2">{busy ? "در حال ثبت…" : "ثبت در موجودی"}</Button>
      </form>}
      {error && <p role="alert" className="text-destructive">{error}</p>}
    </CardContent></Card>;
}
