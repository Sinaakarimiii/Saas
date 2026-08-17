"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type NavItem = {
  href: string;
  label: string;
};

export function OrgSidebar({
  orgId,
  orgName,
  roleName,
  navItems,
}: {
  orgId: string;
  orgName: string;
  roleName: string;
  navItems: NavItem[];
}) {
  const pathname = usePathname();
  const router = useRouter();

  async function signOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <aside className="bg-muted/30 flex w-56 shrink-0 flex-col gap-4 border-l p-4">
      <div>
        <p className="truncate font-semibold">{orgName}</p>
        <p className="text-muted-foreground text-xs">{roleName}</p>
      </div>
      <nav className="flex flex-col gap-1">
        {navItems.map((item) => {
          const href = `/${orgId}${item.href}`;
          const active = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={item.href}
              href={href}
              className={cn(
                "rounded-md px-3 py-2 text-sm transition-colors",
                active
                  ? "bg-primary text-primary-foreground"
                  : "hover:bg-muted",
              )}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>
      <div className="mt-auto flex flex-col gap-2">
        <Button asChild variant="ghost" size="sm">
          <Link href="/orgs">تعویض سازمان</Link>
        </Button>
        <Button variant="ghost" size="sm" onClick={signOut}>
          خروج
        </Button>
      </div>
    </aside>
  );
}
