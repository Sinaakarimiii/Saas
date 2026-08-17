import Link from "next/link";
import { redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { NewFormDialog } from "./new-form-dialog";

export default async function FormsPage({
  params,
}: PageProps<"/[orgId]/forms">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);

  if (!ctx.can(PERMISSIONS.MANAGE_FORMS)) {
    redirect(`/${orgId}/dashboard`);
  }

  const supabase = await createClient();
  const { data: templates } = await supabase
    .from("form_templates")
    .select("id, name, form_fields(count)")
    .eq("org_id", orgId)
    .is("deleted_at", null)
    .order("created_at", { ascending: true });

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">فرم‌ها</h1>
        <NewFormDialog orgId={orgId} />
      </div>

      {(templates ?? []).length === 0 && (
        <p className="text-muted-foreground">هنوز فرمی ساخته نشده.</p>
      )}

      <div className="grid gap-3 sm:grid-cols-2">
        {(templates ?? []).map((t) => (
          <Link key={t.id} href={`/${orgId}/forms/${t.id}`}>
            <Card className="hover:bg-muted/50 transition-colors">
              <CardHeader>
                <CardTitle>{t.name}</CardTitle>
                <CardDescription>
                  {t.form_fields?.[0]?.count ?? 0} فیلد
                </CardDescription>
              </CardHeader>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  );
}
