import { redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { RoleEditorDialog } from "./role-editor-dialog";

export default async function RolesPage({
  params,
}: PageProps<"/[orgId]/roles">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);

  if (!ctx.can(PERMISSIONS.MANAGE_ROLES)) {
    redirect(`/${orgId}/dashboard`);
  }

  const supabase = await createClient();

  const [{ data: roles }, { data: permissionsCatalog }, { data: rolePermissions }] =
    await Promise.all([
      supabase
        .from("roles")
        .select("id, name, is_system")
        .eq("org_id", orgId)
        .is("deleted_at", null)
        .order("created_at", { ascending: true }),
      supabase
        .from("permissions")
        .select("key, label_fa, scope_options")
        .order("key", { ascending: true }),
      supabase.from("role_permissions").select("role_id, permission_key, scope"),
    ]);

  const grantsByRole = new Map<string, Record<string, "own" | "all" | "team" | null>>();
  for (const rp of rolePermissions ?? []) {
    const map = grantsByRole.get(rp.role_id) ?? {};
    map[rp.permission_key] = rp.scope as "own" | "all" | "team" | null;
    grantsByRole.set(rp.role_id, map);
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">نقش‌ها</h1>
        <RoleEditorDialog
          orgId={orgId}
          permissionsCatalog={permissionsCatalog ?? []}
          trigger={<Button>+ نقش جدید</Button>}
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        {(roles ?? []).map((role) => {
          const grants = grantsByRole.get(role.id) ?? {};
          const grantedCount = Object.keys(grants).length;
          return (
            <Card key={role.id}>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  {role.name}
                  {role.is_system && <Badge variant="outline">سیستمی</Badge>}
                </CardTitle>
                <CardDescription>{grantedCount} دسترسی فعال</CardDescription>
              </CardHeader>
              <CardContent>
                <RoleEditorDialog
                  orgId={orgId}
                  permissionsCatalog={permissionsCatalog ?? []}
                  role={{
                    id: role.id,
                    name: role.name,
                    isSystem: role.is_system,
                    grants,
                  }}
                  trigger={
                    <Button variant="outline" size="sm">
                      {role.is_system ? "مشاهده" : "ویرایش"}
                    </Button>
                  }
                />
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
