import Link from "next/link";
import { redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { NewTicketForm } from "./new-ticket-form";

export default async function NewTicketPage({
  params,
}: PageProps<"/[orgId]/tickets/new">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);

  if (!ctx.can(PERMISSIONS.TICKET_CREATE)) {
    redirect(`/${orgId}/tickets`);
  }

  const supabase = await createClient();
  const { data: templates } = await supabase
    .from("form_templates")
    .select(
      "id, name, form_fields(id, key, label, field_type, is_required, options, sort_order, deleted_at)",
    )
    .eq("org_id", orgId)
    .eq("is_active", true)
    .is("deleted_at", null)
    .order("created_at", { ascending: true });

  const preparedTemplates = (templates ?? []).map((t) => ({
    id: t.id,
    name: t.name,
    fields: (t.form_fields ?? [])
      .filter((f) => f.deleted_at === null)
      .sort((a, b) => a.sort_order - b.sort_order),
  }));

  if (preparedTemplates.length === 0) {
    return (
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-bold">تیکت جدید</h1>
        <p className="text-muted-foreground">
          هنوز هیچ فرم فعالی برای تیکت وجود ندارد.
          {ctx.can(PERMISSIONS.MANAGE_FORMS) && (
            <>
              {" "}
              <Link href={`/${orgId}/forms`} className="text-primary underline">
                ساخت فرم
              </Link>
            </>
          )}
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">تیکت جدید</h1>
      <NewTicketForm orgId={orgId} templates={preparedTemplates} />
    </div>
  );
}
