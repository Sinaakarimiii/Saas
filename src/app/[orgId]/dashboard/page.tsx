import { getOrgContext } from "@/lib/org-context";

export default async function DashboardPage({
  params,
}: PageProps<"/[orgId]/dashboard">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);

  return (
    <div className="flex flex-col gap-2">
      <h1 className="text-2xl font-bold">خوش آمدید</h1>
      <p className="text-muted-foreground">
        عضو سازمان «{ctx.org.name}» با نقش «{ctx.roleName}» هستید.
      </p>
    </div>
  );
}
