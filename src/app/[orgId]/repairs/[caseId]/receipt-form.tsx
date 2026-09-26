"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { receiveRepairDeviceAction } from "../actions";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

export function ReceiptForm({ orgId, caseId, expectedVersion, canOverride }: {
  orgId: string; caseId: string; expectedVersion: number; canOverride: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const uploadedEvidence = useRef<{ file: File; path: string } | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [override, setOverride] = useState(false);
  const [evidenceFile, setEvidenceFile] = useState<File | null>(null);
  const [form, setForm] = useState({ method: "walk_in", location: "", custodian: "", items: "", verifiedImei: "", duplicateReason: "", duplicateReference: "" });
  function change(name: keyof typeof form, value: string) {
    key.current = null;
    setForm((previous) => ({ ...previous, [name]: value }));
  }
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true);
    setError("");
    key.current ??= crypto.randomUUID();
    try {
      let imeiEvidence = "";
      if (form.verifiedImei) {
        if (!evidenceFile) { setError("برای تأیید IMEI، عکس برچسب دستگاه را انتخاب کنید."); return; }
        const contentTypes: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
        const extension = contentTypes[evidenceFile.type];
        if (!extension || evidenceFile.size < 1 || evidenceFile.size > 5 * 1024 * 1024) {
          setError("عکس باید JPG، PNG یا WebP و حداکثر ۵ مگابایت باشد."); return;
        }
        if (uploadedEvidence.current?.file === evidenceFile) {
          imeiEvidence = uploadedEvidence.current.path;
        } else {
          const path = `${orgId}/${caseId}/${crypto.randomUUID()}.${extension}`;
          const { error: uploadError } = await createClient().storage.from("repair-imei-evidence")
            .upload(path, evidenceFile, { contentType: evidenceFile.type, upsert: false });
          if (uploadError) { setError("بارگذاری عکس انجام نشد. دوباره تلاش کنید."); return; }
          uploadedEvidence.current = { file: evidenceFile, path };
          imeiEvidence = path;
        }
      }
      const result = await receiveRepairDeviceAction({ orgId, caseId, expectedVersion, idempotencyKey: key.current,
        ...form, imeiEvidence, duplicateReason: override ? form.duplicateReason : "", duplicateReference: override ? form.duplicateReference : "" });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch {
      setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و سپس دوباره تلاش کنید.");
    } finally { setPending(false); }
  }
  return (
    <Card>
      <CardHeader><CardTitle>ثبت دریافت فیزیکی</CardTitle></CardHeader>
      <form onSubmit={submit}>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <div className="grid gap-2"><Label htmlFor="receipt-method">روش تحویل</Label><select id="receipt-method" className="h-8 w-full rounded-lg border border-input bg-background px-2.5 text-sm" value={form.method} onChange={(e) => change("method", e.target.value)}><option value="walk_in">حضوری</option><option value="post">پست</option><option value="courier">پیک</option><option value="agency">نمایندگی</option><option value="internal">همکار / داخلی</option></select></div>
          <div className="grid gap-2"><Label htmlFor="receipt-location">محل فیزیکی دستگاه</Label><Input id="receipt-location" required maxLength={200} value={form.location} onChange={(e) => change("location", e.target.value)} /></div>
          <div className="grid gap-2"><Label htmlFor="receipt-custodian">تحویل‌گیرندهٔ مسئول</Label><Input id="receipt-custodian" required maxLength={160} value={form.custodian} onChange={(e) => change("custodian", e.target.value)} /></div>
          <div className="grid gap-2"><Label htmlFor="receipt-items">اقلام همراه</Label><Input id="receipt-items" maxLength={1000} value={form.items} onChange={(e) => change("items", e.target.value)} /></div>
          <div className="grid gap-2"><Label htmlFor="receipt-imei">IMEI تطبیق‌داده‌شده با برچسب</Label><Input id="receipt-imei" dir="ltr" inputMode="numeric" pattern="[0-9]{15}" maxLength={15} value={form.verifiedImei} onChange={(e) => change("verifiedImei", e.target.value)} /><p className="text-xs text-muted-foreground">اگر اکنون قابل تأیید نیست، خالی بگذارید. شناسهٔ اولیه خودکار تأیید نمی‌شود.</p></div>
          <div className="grid gap-2"><Label htmlFor="receipt-evidence">عکس برچسب دستگاه</Label><Input id="receipt-evidence" type="file" accept="image/jpeg,image/png,image/webp" required={Boolean(form.verifiedImei)} onChange={(e) => { key.current = null; uploadedEvidence.current = null; setEvidenceFile(e.target.files?.[0] ?? null); }} /><p className="text-xs text-muted-foreground">برای تأیید IMEI الزامی است. JPG، PNG یا WebP، حداکثر ۵ مگابایت.</p></div>
          {canOverride && <div className="sm:col-span-2"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={override} onChange={(e) => { key.current = null; setOverride(e.target.checked); }} />ثبت استثنا در صورت وجود پروندهٔ باز دیگر</label></div>}
          {canOverride && override && <>
            <div className="grid gap-2"><Label htmlFor="duplicate-reason">علت استثنا</Label><Textarea id="duplicate-reason" required maxLength={500} value={form.duplicateReason} onChange={(e) => change("duplicateReason", e.target.value)} /></div>
            <div className="grid gap-2"><Label htmlFor="duplicate-reference">مرجع تأیید استثنا</Label><Input id="duplicate-reference" required maxLength={120} value={form.duplicateReference} onChange={(e) => change("duplicateReference", e.target.value)} /></div>
          </>}
          {error && <p role="alert" className="text-sm text-destructive sm:col-span-2">{error}</p>}
        </CardContent>
        <CardFooter className="mt-4 justify-end"><Button type="submit" disabled={pending}>{pending ? "در حال ثبت…" : "ثبت دریافت دستگاه"}</Button></CardFooter>
      </form>
    </Card>
  );
}
