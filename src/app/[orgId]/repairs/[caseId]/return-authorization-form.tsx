"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordRepairReturnAuthorizationAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

function localDateTimeNow() {
  const date = new Date();
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset());
  return date.toISOString().slice(0, 19);
}

export function ReturnAuthorizationForm({ orgId, caseId, planId, planRevision, expectedVersion,
  canAuthorize, authorization }: {
  orgId: string; caseId: string; planId: string; planRevision: number; expectedVersion: number;
  canAuthorize: boolean;
  authorization: { notification_channel: string; notified_person: string; notification_reference: string;
    notified_at: string; protocol_code: string } | null;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ channel: "", person: "", reference: "", notifiedAt: localDateTimeNow() });

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setError("");
    const notifiedAt = new Date(form.notifiedAt);
    if (Number.isNaN(notifiedAt.getTime())) { setError("زمان اطلاع‌رسانی معتبر نیست."); return; }
    setPending(true);
    key.current ??= crypto.randomUUID();
    try {
      const result = await recordRepairReturnAuthorizationAction({
        orgId, caseId, planId, expectedVersion, idempotencyKey: key.current,
        notificationChannel: form.channel, notifiedPerson: form.person,
        notificationReference: form.reference, notifiedAt: notifiedAt.toISOString(),
      });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }

  return <Card><CardHeader><CardTitle>مجوز عودت بدون تعمیر · نسخهٔ {planRevision}</CardTitle></CardHeader>
    <CardContent className="grid gap-4 text-sm">
      <p className="text-muted-foreground">اطلاع‌رسانی انجام‌شده را با مرجع آن ثبت کنید. مجوز این بخش، پروتکل «کنترل خروج عودت» را برای مرحلهٔ تست انتخاب می‌کند؛ به معنی انجام تست یا تحویل دستگاه نیست.</p>
      {authorization ? <div className="rounded-xl border border-primary/25 bg-primary/5 p-4">
        <p className="font-medium">مجوز عودت برای این نسخه ثبت شده است.</p>
        <p className="mt-1 text-muted-foreground">اطلاع به {authorization.notified_person} · مرجع {authorization.notification_reference} · پروتکل {authorization.protocol_code}</p>
      </div> : canAuthorize ? <form onSubmit={submit} className="grid gap-3 sm:grid-cols-2">
        <div className="grid gap-2"><Label htmlFor="return-channel">روش اطلاع‌رسانی انجام‌شده</Label><select id="return-channel" required className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.channel} onChange={(event) => { key.current = null; setForm({ ...form, channel: event.target.value }); }}><option value="">انتخاب کنید</option><option value="phone">تلفنی</option><option value="message">پیامک</option><option value="chat">چت</option><option value="in_person">حضوری</option><option value="agency">نمایندگی</option><option value="other">سایر</option></select></div>
        <div className="grid gap-2"><Label htmlFor="return-person">شخص مطلع‌شده</Label><Input id="return-person" required maxLength={160} value={form.person} onChange={(event) => { key.current = null; setForm({ ...form, person: event.target.value }); }} /></div>
        <div className="grid gap-2"><Label htmlFor="return-reference">مرجع تماس یا پیام</Label><Input id="return-reference" required maxLength={240} value={form.reference} onChange={(event) => { key.current = null; setForm({ ...form, reference: event.target.value }); }} /></div>
        <div className="grid gap-2"><Label htmlFor="return-time">زمان اطلاع‌رسانی</Label><Input id="return-time" type="datetime-local" step="1" required value={form.notifiedAt} onChange={(event) => { key.current = null; setForm({ ...form, notifiedAt: event.target.value }); }} /></div>
        {error && <p role="alert" className="text-destructive sm:col-span-2">{error}</p>}
        <div className="flex justify-end sm:col-span-2"><Button type="submit" disabled={pending}>{pending ? "در حال ثبت…" : "ثبت اطلاع‌رسانی و مجوز عودت"}</Button></div>
      </form> : <p className="text-muted-foreground">ثبت مجوز عودت به دسترسی مستقل نیاز دارد.</p>}
    </CardContent>
  </Card>;
}
