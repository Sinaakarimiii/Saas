import { notFound } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDateTime } from "@/lib/jalali";
import { Badge } from "@/components/ui/badge";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
import { FieldEditDialog } from "./field-edit-dialog";
import { StatusToggle } from "./status-toggle";
import type { FormFieldDef } from "../field-input";
import type { Json } from "@/lib/supabase/types";

function displayValue(fieldType: string, value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (fieldType === "file" && typeof value === "object") {
    const v = value as { file_name?: string };
    return v.file_name ?? "فایل";
  }
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}

export default async function TicketDetailPage({
  params,
}: PageProps<"/[orgId]/tickets/[ticketId]">) {
  const { orgId, ticketId } = await params;
  const ctx = await getOrgContext(orgId);
  const supabase = await createClient();

  const { data: ticket } = await supabase
    .from("tickets")
    .select(
      "id, tracking_code, title, status, created_by, created_at, form_template_id, form_templates(name)",
    )
    .eq("id", ticketId)
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .maybeSingle();

  if (!ticket) {
    notFound();
  }

  const [{ data: fields }, { data: fieldValues }, { data: auditEntries }] =
    await Promise.all([
      supabase
        .from("form_fields")
        .select("id, key, label, field_type, is_required, options")
        .eq("form_template_id", ticket.form_template_id)
        .is("deleted_at", null)
        .order("sort_order", { ascending: true }),
      supabase
        .from("ticket_field_values")
        .select("form_field_id, value")
        .eq("ticket_id", ticket.id),
      supabase
        .from("audit_log")
        .select("id, acted_at, actor_id, field_name, old_value, new_value, note, action")
        .eq("record_id", ticket.id)
        .order("acted_at", { ascending: true }),
    ]);

  const valueByFieldId = new Map<string, Json>(
    (fieldValues ?? []).map((v) => [v.form_field_id, v.value]),
  );

  const fileFieldIds = (fields ?? [])
    .filter((f) => f.field_type === "file")
    .map((f) => f.id);
  const signedUrlByFieldId = new Map<string, string>();
  await Promise.all(
    fileFieldIds.map(async (fieldId) => {
      const value = valueByFieldId.get(fieldId) as
        | { storage_path?: string }
        | undefined;
      if (!value?.storage_path) return;
      const { data } = await supabase.storage
        .from("ticket-attachments")
        .createSignedUrl(value.storage_path, 3600);
      if (data?.signedUrl) {
        signedUrlByFieldId.set(fieldId, data.signedUrl);
      }
    }),
  );

  const actorIds = Array.from(
    new Set((auditEntries ?? []).map((e) => e.actor_id).filter(Boolean)),
  ) as string[];
  const { data: actors } =
    actorIds.length > 0
      ? await supabase.from("profiles").select("id, full_name, email").in("id", actorIds)
      : { data: [] };
  const actorNameById = new Map(
    (actors ?? []).map((a) => [a.id, a.full_name || a.email]),
  );

  const scope = ctx.scopeOf(PERMISSIONS.TICKET_EDIT);
  const canEditThisTicket =
    scope === "all" || (scope === "own" && ticket.created_by === ctx.user.id);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-2xl font-bold">{ticket.title || "تیکت بدون عنوان"}</h1>
          <p className="text-muted-foreground font-mono text-sm" dir="ltr">
            {ticket.tracking_code}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant={ticket.status === "open" ? "default" : "secondary"}>
            {ticket.status === "open" ? "باز" : "بسته"}
          </Badge>
          {canEditThisTicket && (
            <StatusToggle
              orgId={orgId}
              ticketId={ticket.id}
              status={ticket.status as "open" | "closed"}
            />
          )}
        </div>
      </div>

      <Tabs defaultValue="details">
        <TabsList>
          <TabsTrigger value="details">جزییات</TabsTrigger>
          <TabsTrigger value="history">تاریخچه</TabsTrigger>
        </TabsList>

        <TabsContent value="details" className="grid gap-3">
          {(fields ?? []).map((field) => (
            <div
              key={field.id}
              className="flex items-center justify-between gap-3 border-b py-2"
            >
              <div>
                <p className="text-muted-foreground text-xs">{field.label}</p>
                {field.field_type === "file" && signedUrlByFieldId.has(field.id) ? (
                  <a
                    href={signedUrlByFieldId.get(field.id)}
                    target="_blank"
                    rel="noreferrer"
                    className="text-primary underline"
                  >
                    {displayValue(field.field_type, valueByFieldId.get(field.id))}
                  </a>
                ) : (
                  <p>
                    {displayValue(field.field_type, valueByFieldId.get(field.id))}
                  </p>
                )}
              </div>
              {canEditThisTicket && (
                <FieldEditDialog
                  orgId={orgId}
                  ticketId={ticket.id}
                  field={field as FormFieldDef}
                  currentValue={valueByFieldId.get(field.id) ?? null}
                />
              )}
            </div>
          ))}
        </TabsContent>

        <TabsContent value="history" className="grid gap-3">
          {(auditEntries ?? []).length === 0 && (
            <p className="text-muted-foreground text-sm">تاریخچه‌ای ثبت نشده.</p>
          )}
          {(auditEntries ?? []).map((entry) => (
            <div key={entry.id} className="border-b pb-2 text-sm">
              <p className="text-muted-foreground text-xs">
                {formatJalaliDateTime(entry.acted_at)} —{" "}
                {actorNameById.get(entry.actor_id ?? "") ?? "—"}
              </p>
              {entry.action === "insert" && !entry.field_name && (
                <p>تیکت ساخته شد</p>
              )}
              {entry.action === "insert" && entry.field_name && (
                <p>
                  «{entry.field_name}» = {entry.new_value}
                </p>
              )}
              {entry.action === "update" && (
                <p>
                  «{entry.field_name}» از «{entry.old_value}» به «{entry.new_value}» تغییر کرد
                </p>
              )}
              {entry.note && (
                <p className="text-muted-foreground italic">توضیح: {entry.note}</p>
              )}
            </div>
          ))}
        </TabsContent>
      </Tabs>
    </div>
  );
}
