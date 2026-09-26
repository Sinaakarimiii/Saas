"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { finalizeRepairDiagnosisAction, saveRepairDiagnosisAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

type Diagnosis = {
  id: string; revision: number; status: string; findings: string;
  technical_condition: string; recommended_action: string; warranty_coverage: string;
};

const conditions: Record<string, string> = {
  unknown: "هنوز نامشخص", needs_repair: "نیازمند تعمیر", healthy: "سالم / ایراد مشاهده نشد", irreparable: "غیرقابل تعمیر",
};
const actions: Record<string, string> = { repair: "تعمیر", replacement: "تعویض", return: "عودت بدون تعمیر" };
const coverages: Record<string, string> = { covered: "مشمول گارانتی", not_covered: "خارج از گارانتی", pending: "در انتظار تعیین پوشش" };

export function DiagnosisForm({ orgId, caseId, expectedVersion, latest, currentCycle, canRecord, canFinalize }: {
  orgId: string; caseId: string; expectedVersion: number; latest: Diagnosis | null;
  currentCycle: boolean; canRecord: boolean; canFinalize: boolean;
}) {
  const router = useRouter();
  const saveKey = useRef<string | null>(null);
  const finalizeKey = useRef<string | null>(null);
  const [pending, setPending] = useState(false);
  const [finalizeOpen, setFinalizeOpen] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({
    findings: currentCycle ? latest?.findings ?? "" : "",
    technicalCondition: currentCycle ? latest?.technical_condition ?? "unknown" : "unknown",
    recommendedAction: currentCycle ? latest?.recommended_action ?? "repair" : "repair",
    warrantyCoverage: currentCycle ? latest?.warranty_coverage ?? "pending" : "pending",
  });
  function change(name: keyof typeof form, value: string) {
    saveKey.current = null;
    setForm((previous) => ({ ...previous, [name]: value }));
  }
  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true);
    setError("");
    saveKey.current ??= crypto.randomUUID();
    try {
      const result = await saveRepairDiagnosisAction({ orgId, caseId, expectedVersion,
        idempotencyKey: saveKey.current, ...form });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  async function finalize() {
    if (!latest || pending) return;
    setPending(true);
    setError("");
    finalizeKey.current ??= crypto.randomUUID();
    try {
      const result = await finalizeRepairDiagnosisAction({ orgId, caseId, diagnosisId: latest.id,
        expectedVersion, idempotencyKey: finalizeKey.current });
      if (result.error) { setError(result.error); return; }
      setFinalizeOpen(false);
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  return <>
    <Card>
      <CardHeader><CardTitle>تشخیص فنی</CardTitle></CardHeader>
      <CardContent className="grid gap-4">
        {latest && <div className="rounded-xl border border-border/70 p-3 text-sm">
          <p className="font-medium">نسخهٔ {latest.revision} · {latest.status === "final" ? "نهایی‌شده" : "پیش‌نویس"}{!currentCycle ? " · مربوط به نوبت قبلی کارشناسی" : ""}</p>
          <p className="mt-1 whitespace-pre-wrap text-muted-foreground">{latest.findings}</p>
          <p className="mt-2 text-muted-foreground">{conditions[latest.technical_condition]} · {actions[latest.recommended_action]} · {coverages[latest.warranty_coverage]}</p>
        </div>}
        {!latest && <p className="text-sm text-muted-foreground">هنوز تشخیصی ثبت نشده است.</p>}
        {canRecord && <form onSubmit={save} className="grid gap-4">
          <div className="grid gap-2"><Label htmlFor="diagnosis-findings">یافته‌های فنی</Label><Textarea id="diagnosis-findings" required maxLength={3000} value={form.findings} onChange={(e) => change("findings", e.target.value)} /></div>
          <div className="grid gap-4 sm:grid-cols-3">
            <div className="grid gap-2"><Label htmlFor="diagnosis-condition">وضعیت فنی</Label><select id="diagnosis-condition" className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.technicalCondition} onChange={(e) => change("technicalCondition", e.target.value)}>{Object.entries(conditions).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></div>
            <div className="grid gap-2"><Label htmlFor="diagnosis-action">راه‌حل پیشنهادی</Label><select id="diagnosis-action" className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.recommendedAction} onChange={(e) => change("recommendedAction", e.target.value)}>{Object.entries(actions).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></div>
            <div className="grid gap-2"><Label htmlFor="diagnosis-coverage">پوشش این خرابی</Label><select id="diagnosis-coverage" className="h-9 rounded-lg border border-input bg-background px-2 text-sm" value={form.warrantyCoverage} onChange={(e) => change("warrantyCoverage", e.target.value)}>{Object.entries(coverages).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></div>
          </div>
          {error && !finalizeOpen && <p role="alert" className="text-sm text-destructive">{error}</p>}
          <CardFooter className="px-0 pb-0 justify-end"><Button type="submit" disabled={pending}>{pending ? "در حال ثبت…" : "ثبت نسخهٔ تشخیص"}</Button></CardFooter>
        </form>}
        {canFinalize && currentCycle && latest?.status === "draft" && <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border/70 pt-4 text-sm"><p>نهایی‌سازی، همین نسخه را مبنای تصمیم قرار می‌دهد.</p><Button variant="outline" disabled={pending || latest.technical_condition === "unknown"} onClick={() => { finalizeKey.current = null; setError(""); setFinalizeOpen(true); }}>نهایی‌سازی نسخهٔ {latest.revision}</Button></div>}
        {canFinalize && currentCycle && latest?.status === "draft" && latest.technical_condition === "unknown" && <p className="text-sm text-muted-foreground">برای نهایی‌سازی، وضعیت فنی را مشخص و نسخهٔ تازه‌ای ثبت کنید.</p>}
      </CardContent>
    </Card>
    <Dialog open={finalizeOpen} onOpenChange={(open) => { if (!pending) setFinalizeOpen(open); }}>
      <DialogContent showCloseButton={false}>
        <DialogHeader><DialogTitle>نهایی‌سازی تشخیص؟</DialogTitle><DialogDescription>نسخهٔ {latest?.revision} تشخیص مبنای تصمیم بعدی می‌شود. برای تغییر آن باید نسخهٔ تازه‌ای ثبت شود.</DialogDescription></DialogHeader>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <DialogFooter><Button variant="outline" disabled={pending} onClick={() => setFinalizeOpen(false)}>انصراف</Button><Button disabled={pending} onClick={finalize}>{pending ? "در حال ثبت…" : "تأیید"}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </>;
}
