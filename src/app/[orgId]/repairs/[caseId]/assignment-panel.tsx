"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { requestRepairCaseAssignmentAction, resolveRepairCaseAssignmentAction } from "../actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { formatJalaliDateTime } from "@/lib/jalali";

type Request = {
  id: string; from_user_id: string; target_user_id: string; requested_by: string;
  request_reference: string; requested_at: string; status: string;
  resolution_reason: string | null; resolution_reference: string | null; resolved_at: string | null;
};

type Decision = "accepted" | "rejected" | "withdrawn";
export function AssignmentPanel({ orgId, caseId, expectedVersion, currentUserId, assignedTo,
  members, requests, canAssign, canAccept, canReject, canWithdraw, closed }: {
  orgId: string; caseId: string; expectedVersion: number; currentUserId: string; assignedTo: string;
  members: { id: string; label: string }[]; requests: Request[];
  canAssign: boolean; canAccept: boolean; canReject: boolean; canWithdraw: boolean; closed: boolean;
}) {
  const router = useRouter();
  const key = useRef<string | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [target, setTarget] = useState("");
  const [reference, setReference] = useState("");
  const [resolution, setResolution] = useState<{ requestId: string; decision: Decision } | null>(null);
  const [reason, setReason] = useState("");
  const [resolutionReference, setResolutionReference] = useState("");
  const pendingRequest = requests.find((request) => request.status === "pending");
  const label = (id: string) => members.find((member) => member.id === id)?.label ?? id;

  async function submitRequest(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await requestRepairCaseAssignmentAction({ orgId, caseId, targetUserId: target,
        requestReference: reference, expectedVersion, idempotencyKey: key.current });
      if (result.error) { setError(result.error); return; }
      router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  async function submitResolution(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!resolution || pending) return;
    setPending(true); setError(""); key.current ??= crypto.randomUUID();
    try {
      const result = await resolveRepairCaseAssignmentAction({ orgId, caseId,
        requestId: resolution.requestId, decision: resolution.decision, reason,
        resolutionReference, expectedVersion, idempotencyKey: key.current });
      if (result.error) { setError(result.error); return; }
      setResolution(null); router.refresh();
    } catch { setError("ارتباط برقرار نشد. وضعیت پرونده را بررسی کنید و دوباره تلاش کنید."); }
    finally { setPending(false); }
  }
  function choose(requestId: string, decision: Decision) {
    key.current = null; setError(""); setReason(""); setResolutionReference("");
    setResolution({ requestId, decision });
  }

  return <Card><CardHeader><CardTitle>مسئول رسیدگی و واگذاری پرونده</CardTitle></CardHeader><CardContent className="grid gap-4 text-sm">
    <p>مسئول فعلی: <strong>{label(assignedTo)}</strong></p>
    <p className="text-muted-foreground">واگذاری فقط مسئول رسیدگی را تغییر می‌دهد. محل دستگاه و تحویل‌گیرندهٔ فیزیکی با رسید جابه‌جایی مستقل تغییر می‌کنند.</p>
    {pendingRequest && <div className="rounded-xl border border-primary/25 bg-primary/5 p-4">
      <p className="font-medium">در انتظار پاسخ {label(pendingRequest.target_user_id)}</p>
      <p className="mt-1 text-muted-foreground">مرجع {pendingRequest.request_reference} · {formatJalaliDateTime(pendingRequest.requested_at)}</p>
      <div className="mt-3 flex flex-wrap gap-2">
        {pendingRequest.target_user_id === currentUserId && canAccept && <Button size="sm" onClick={() => choose(pendingRequest.id, "accepted")}>پذیرش مسئولیت</Button>}
        {pendingRequest.target_user_id === currentUserId && canReject && <Button size="sm" variant="outline" onClick={() => choose(pendingRequest.id, "rejected")}>رد درخواست</Button>}
        {pendingRequest.requested_by === currentUserId && canWithdraw && <Button size="sm" variant="outline" onClick={() => choose(pendingRequest.id, "withdrawn")}>پس‌گرفتن درخواست</Button>}
      </div>
    </div>}
    {resolution && <form onSubmit={submitResolution} className="grid gap-3 rounded-xl border border-border/70 p-4">
      <p className="font-medium">{resolution.decision === "accepted" ? "پذیرش مسئولیت پرونده؟" : resolution.decision === "rejected" ? "رد درخواست واگذاری" : "پس‌گرفتن درخواست"}</p>
      {resolution.decision !== "accepted" && <><div className="grid gap-2"><Label htmlFor="assignment-reason">علت</Label><Input id="assignment-reason" required maxLength={500} value={reason} onChange={(event) => { key.current = null; setReason(event.target.value); }} /></div>
        <div className="grid gap-2"><Label htmlFor="assignment-resolution-ref">مرجع یکتا</Label><Input id="assignment-resolution-ref" required maxLength={160} value={resolutionReference} onChange={(event) => { key.current = null; setResolutionReference(event.target.value); }} /></div></>}
      <div className="flex gap-2"><Button type="button" variant="outline" disabled={pending} onClick={() => setResolution(null)}>انصراف</Button><Button disabled={pending} type="submit">تأیید</Button></div>
    </form>}
    {!pendingRequest && !closed && canAssign && <form onSubmit={submitRequest} className="grid gap-3 rounded-xl border border-border/70 p-4">
      <p className="font-medium">درخواست واگذاری جدید</p>
      <div className="grid gap-2"><Label htmlFor="assignment-target">عضو مقصد</Label><select id="assignment-target" required className="h-9 rounded-lg border border-input bg-background px-2" value={target} onChange={(event) => { key.current = null; setTarget(event.target.value); }}><option value="">انتخاب کنید</option>{members.filter((member) => member.id !== assignedTo).map((member) => <option value={member.id} key={member.id}>{member.label}</option>)}</select></div>
      <div className="grid gap-2"><Label htmlFor="assignment-reference">مرجع یکتای درخواست</Label><Input id="assignment-reference" required maxLength={160} value={reference} onChange={(event) => { key.current = null; setReference(event.target.value); }} /></div>
      <div><Button type="submit" disabled={pending || !target}>ارسال درخواست واگذاری</Button></div>
    </form>}
    {error && <p role="alert" className="text-destructive">{error}</p>}
    {requests.length > 0 && <div className="grid gap-2"><p className="font-medium">سابقهٔ واگذاری</p>{requests.map((request) => <div className="rounded-lg border border-border/60 p-3" key={request.id}>
      <p>{label(request.from_user_id)} ← {label(request.target_user_id)} · {request.status === "pending" ? "در انتظار" : request.status === "accepted" ? "پذیرفته‌شده" : request.status === "rejected" ? "ردشده" : "پس‌گرفته‌شده"}</p>
      <p className="text-muted-foreground">مرجع درخواست: {request.request_reference}{request.resolution_reference ? ` · مرجع پاسخ: ${request.resolution_reference}` : ""}{request.resolution_reason ? ` · علت: ${request.resolution_reason}` : ""}</p>
    </div>)}</div>}
  </CardContent></Card>;
}
