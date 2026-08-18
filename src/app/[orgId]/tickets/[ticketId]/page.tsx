import { notFound } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDateTime } from "@/lib/jalali";
import { fetchHolidayDates } from "@/lib/holidays";
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
  if (fieldType === "boolean") return value === true ? "بله" : "خیر";
  if (Array.isArray(value)) {
    if (value.length === 0) return "—";
    return value.map((v) => displayValue(fieldType, v)).join("، ");
  }
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

  const [{ data: fields }, { data: fieldValues }, { data: auditEntries }, holidays] =
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
      fetchHolidayDates(supabase),
    ]);

  const valueByFieldId = new Map<string, Json>(
    (fieldValues ?? []).map((v) => [v.form_field_id, v.value]),
  );

  const fileFieldIds = (fields ?? [])
    .filter((f) => f.field_type === "file")
    .map((f) => f.id);
  // A repeatable file field stores an array of {storage_path,...} instead of
  // one -- normalize both shapes to a list of signed links per field.
  const signedFilesByFieldId = new Map<string, { url: string; fileName: string }[]>();
  await Promise.all(
    fileFieldIds.map(async (fieldId) => {
      const raw = valueByFieldId.get(fieldId);
      const entries = (Array.isArray(raw) ? raw : raw ? [raw] : []) as {
        storage_path?: string;
        file_name?: string;
      }[];
      const links = (
        await Promise.all(
          entries.map(async (entry) => {
            if (!entry.storage_path) return null;
            const { data } = await supabase.storage
              .from("ticket-attachments")
              .createSignedUrl(entry.storage_path, 3600);
            return data?.signedUrl
              ? { url: data.signedUrl, fileName: entry.file_name ?? "فایل" }
              : null;
          }),
        )
      ).filter((l): l is { url: string; fileName: string } => l !== null);
      if (links.length > 0) signedFilesByFieldId.set(fieldId, links);
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
                {field.field_type === "file" && signedFilesByFieldId.has(field.id) ? (
                  <div className="flex flex-col gap-1">
                    {signedFilesByFieldId.get(field.id)!.map((f, i) => (
                      <a
                        key={i}
                        href={f.url}
                        target="_blank"
                        rel="noreferrer"
                        className="text-primary underline"
                      >
                        {f.fileName}
                      </a>
                    ))}
                  </div>
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
                  holidays={holidays}
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
