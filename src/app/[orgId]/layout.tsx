import { getOrgContext } from "@/lib/org-context";
import { PERMISSIONS } from "@/lib/permissions";
import { OrgSidebar } from "./nav";

export default async function OrgLayout({
  children,
  params,
}: LayoutProps<"/[orgId]">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);

  const navItems = [
    { href: "/dashboard", label: "خانه" },
    { href: "/tickets", label: "تیکت‌ها" },
    { href: "/calendar", label: "تقویم" },
    ...(ctx.can(PERMISSIONS.SHIFT_MANAGE)
      ? [{ href: "/shifts", label: "شیفت‌ها" }]
      : []),
    ...(ctx.can(PERMISSIONS.LEAVE_REQUEST) || ctx.can(PERMISSIONS.LEAVE_APPROVE)
      ? [{ href: "/leave", label: "مرخصی" }]
      : []),
    ...(ctx.can(PERMISSIONS.ATTENDANCE_RECORD) || ctx.can(PERMISSIONS.ATTENDANCE_VIEW)
      ? [{ href: "/attendance", label: "حضور و غیاب" }]
      : []),
    ...(ctx.can(PERMISSIONS.MANAGE_FORMS)
      ? [{ href: "/forms", label: "فرم‌ها" }]
      : []),
    ...(ctx.can(PERMISSIONS.MANAGE_MEMBERS)
      ? [{ href: "/members", label: "اعضا" }]
      : []),
    ...(ctx.can(PERMISSIONS.MANAGE_ROLES)
      ? [{ href: "/roles", label: "نقش‌ها" }]
      : []),
  ];

  return (
    <div className="flex min-h-full flex-1">
      <OrgSidebar
        orgId={orgId}
        orgName={ctx.org.name}
        roleName={ctx.roleName}
        navItems={navItems}
      />
      <main className="flex-1 overflow-x-hidden p-6">{children}</main>
    </div>
  );
}
