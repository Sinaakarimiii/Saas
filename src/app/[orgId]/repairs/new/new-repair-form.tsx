"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createRepairCaseAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

export function NewRepairForm({ orgId }: { orgId: string }) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ customerName: "", deviceModel: "", rawIdentifier: "", issue: "", priority: "normal", source: "walk_in" });
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
      const result = await createRepairCaseAction({ orgId, ...form, idempotencyKey: key.current });
      if (result.error) { setError(result.error); return; }
      router.push(`/${orgId}/repairs/${result.caseId}`);
    } catch {
      setError("ارتباط برقرار نشد. دوباره تلاش کنید؛ درخواست تکراری ساخته نمی‌شود.");
    } finally { setPending(false); }
  }
  return (
    <Card>
      <CardHeader><CardTitle>اطلاعات درخواست</CardTitle></CardHeader>
      <form onSubmit={submit}>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <div className="grid gap-2"><Label htmlFor="repair-customer">نام مشتری</Label><Input id="repair-customer" required maxLength={160} value={form.customerName} onChange={(e) => change("customerName", e.target.value)} /></div>
          <div className="grid gap-2"><Label htmlFor="repair-model">مدل دستگاه</Label><Input id="repair-model" required maxLength={160} value={form.deviceModel} onChange={(e) => change("deviceModel", e.target.value)} /></div>
          <div className="grid gap-2 sm:col-span-2"><Label htmlFor="repair-identifier">شناسهٔ اعلام‌شده (اختیاری)</Label><Input id="repair-identifier" dir="ltr" maxLength={120} value={form.rawIdentifier} onChange={(e) => change("rawIdentifier", e.target.value)} /><p className="text-xs text-muted-foreground">این شناسه تا تطبیق با برچسب دستگاه، IMEI تأییدشده محسوب نمی‌شود.</p></div>
          <div className="grid gap-2 sm:col-span-2"><Label htmlFor="repair-issue">شرح ایراد</Label><Textarea id="repair-issue" required maxLength={2000} value={form.issue} onChange={(e) => change("issue", e.target.value)} /></div>
          <div className="grid gap-2"><Label htmlFor="repair-priority">اولویت</Label><select id="repair-priority" className="h-8 w-full rounded-lg border border-input bg-background px-2.5 text-sm" value={form.priority} onChange={(e) => change("priority", e.target.value)}><option value="normal">عادی</option><option value="high">بالا</option><option value="urgent">فوری</option></select></div>
          <div className="grid gap-2"><Label htmlFor="repair-source">مسیر درخواست</Label><select id="repair-source" className="h-8 w-full rounded-lg border border-input bg-background px-2.5 text-sm" value={form.source} onChange={(e) => change("source", e.target.value)}><option value="walk_in">حضوری</option><option value="phone">تلفنی</option><option value="chat">گفت‌وگو</option><option value="agency">نمایندگی</option><option value="post">پستی</option><option value="internal">داخلی</option><option value="other">سایر</option></select></div>
          {error && <p role="alert" className="text-sm text-destructive sm:col-span-2">{error}</p>}
        </CardContent>
        <CardFooter className="mt-4 justify-end"><Button disabled={pending} type="submit">{pending ? "در حال ثبت…" : "ثبت پرونده"}</Button></CardFooter>
      </form>
    </Card>
  );
}
