"use client";
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { recordReplacementScrapAction, approveReplacementScrapAction } from "../actions";
import { formatJalaliDateTime } from "@/lib/jalali";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type Scrap = { id: string; reference: string; evidence: string; note: string; location: string;
  recorded_by: string; recorded_at: string; approved_by: string | null; approved_at: string | null };
export function ReplacementScrap({ orgId, caseId, expectedVersion, currentUserId, canRecord, canApprove, ready, scrap, deviceIdentifier, recordedByLabel, approvedByLabel }: {
  deviceIdentifier?: string; recordedByLabel?: string; approvedByLabel?: string;
  orgId: string; caseId: string; expectedVersion: number; currentUserId: string;
  canRecord: boolean; canApprove: boolean; ready: boolean; scrap: Scrap | null;
}) {
  const router = useRouter(); const key = useRef<string | null>(null);
  const [reference, setReference] = useState(""); const [evidence, setEvidence] = useState(""); const [note, setNote] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false); const [pending, setPending] = useState(false); const [error, setError] = useState("");
  async function submit() {
    if (pending) return; setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const common = { orgId, caseId, expectedVersion, idempotencyKey: key.current };
      const result = scrap ? await approveReplacementScrapAction({ ...common, scrapId: scrap.id })
        : await recordReplacementScrapAction({ ...common, reference, evidence, note });
      if (result.error) { setError(result.error); return; }
      setConfirmOpen(false); router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  return <Card><CardHeader><CardTitle>اسقاط دستگاه اولیه</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    {deviceIdentifier && <p>دستگاه اولیه · IMEI: <bdi className="tabular-nums">{deviceIdentifier}</bdi></p>}
    {scrap ? <>
      <p>اجرای اسقاط در {scrap.location} ثبت شد؛ مرجع: {scrap.reference} · {formatJalaliDateTime(scrap.recorded_at)}</p>
      <p className="text-muted-foreground">ثبت‌کننده: {recordedByLabel ?? scrap.recorded_by}</p>
      <p>مدرک اجرا: {scrap.evidence}</p><p className="text-muted-foreground">{scrap.note}</p>
      {scrap.approved_at ? <p className="font-medium">تأیید مستقل توسط {approvedByLabel ?? scrap.approved_by} ثبت شد · {formatJalaliDateTime(scrap.approved_at)}</p> : <>
        <p className="text-amber-700 dark:text-amber-300">در انتظار تأیید فرد دوم؛ بستن پرونده مسدود است.</p>
        {scrap.recorded_by === currentUserId ? <p className="text-muted-foreground">شما ثبت‌کننده هستید؛ فرد دیگری با مجوز مستقل تأیید اسقاط باید مدرک را بررسی کند.</p>
          : canApprove ? <Button className="justify-self-end" disabled={pending || !ready} onClick={() => { setError(""); setConfirmOpen(true); }}>تأیید مدرک اجرای اسقاط</Button>
            : <p className="text-muted-foreground">مجوز مستقل تأیید اسقاط لازم است.</p>}
      </>}
    </> : <>
      <p className="text-muted-foreground">پس از اجرای واقعی اسقاط، مرجع و مدرک آن را ثبت کنید. ثبت این نتیجه دستگاه را از چرخهٔ دریافت و جابه‌جایی خارج می‌کند؛ بستن پرونده به تأیید فرد دوم نیاز دارد.</p>
      {canRecord ? <form className="grid gap-3" onSubmit={(event) => { event.preventDefault(); setError(""); setConfirmOpen(true); }}>
        <div className="grid gap-2"><Label htmlFor="scrap-reference">مرجع اجرای اسقاط</Label><Input id="scrap-reference" required maxLength={160} value={reference} onChange={(event) => { key.current = null; setReference(event.target.value); }} /></div>
        <div className="grid gap-2"><Label htmlFor="scrap-evidence">مرجع مدرک اجرای واقعی</Label><Input id="scrap-evidence" required maxLength={240} value={evidence} onChange={(event) => { key.current = null; setEvidence(event.target.value); }} /></div>
        <div className="grid gap-2"><Label htmlFor="scrap-note">شرح اجرای اسقاط</Label><Input id="scrap-note" required maxLength={500} value={note} onChange={(event) => { key.current = null; setNote(event.target.value); }} /></div>
        <Button type="submit" className="justify-self-end" disabled={pending || !ready || !reference.trim() || !evidence.trim() || !note.trim()}>ثبت اجرای اسقاط</Button>
      </form> : <p className="text-muted-foreground">نگهدارندهٔ فعلی دستگاه اولیه با مجوز ثبت اسقاط می‌تواند این نتیجه را ثبت کند.</p>}
    </>}
    {!ready && !scrap?.approved_at && <p className="text-muted-foreground">ابتدا تحویل دستگاه جایگزین، تسویه و رفع مانع‌های باز را کامل کنید.</p>}
    <Dialog open={confirmOpen} onOpenChange={(open) => { if (!pending) setConfirmOpen(open); }}><DialogContent showCloseButton={false}>
      <DialogHeader><DialogTitle>{scrap ? "تأیید اجرای اسقاط؟" : "ثبت اجرای واقعی اسقاط؟"}</DialogTitle>
        <DialogDescription>{scrap ? "مدرک اجرای اسقاط دستگاه اولیه را بررسی کرده‌اید و آن را تأیید می‌کنید؟" : "اسقاط واقعاً اجرا شده است؟ با ثبت، دستگاه از چرخهٔ دریافت و جابه‌جایی خارج می‌شود."}</DialogDescription></DialogHeader>
      {error && <p role="alert" className="text-destructive">{error}</p>}
      <DialogFooter><Button variant="outline" disabled={pending} onClick={() => setConfirmOpen(false)}>انصراف</Button><Button disabled={pending} onClick={submit}>{pending ? "در حال ثبت…" : "تأیید"}</Button></DialogFooter>
    </DialogContent></Dialog>
  </CardContent></Card>;
}
