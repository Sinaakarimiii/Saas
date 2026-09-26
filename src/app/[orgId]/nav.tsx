"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTheme } from "next-themes";
import { useState, useSyncExternalStore } from "react";
import { SunIcon, MoonIcon, MenuIcon, XIcon } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const noopSubscribe = () => () => {};

// Server always renders "not mounted yet" (getServerSnapshot); the client's
// first paint matches that, then flips true -- avoids the classic
// setState-in-effect hydration-guard pattern the lint rule flags.
function useHasMounted() {
  return useSyncExternalStore(
    noopSubscribe,
    () => true,
    () => false,
  );
}

function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme();
  const mounted = useHasMounted();

  return (
    <Button
      variant="ghost"
      size="sm"
      className="justify-start gap-2"
      onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
    >
      {mounted && resolvedTheme === "dark" ? (
        <SunIcon className="size-4" />
      ) : (
        <MoonIcon className="size-4" />
      )}
      {mounted && resolvedTheme === "dark" ? "حالت روز" : "حالت شب"}
    </Button>
  );
}

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
  const [mobileOpen, setMobileOpen] = useState(false);

  async function signOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <aside className="bg-muted/30 flex w-full shrink-0 flex-col gap-4 border-b p-4 md:w-56 md:border-b-0 md:border-l">
      <div className="flex items-center justify-between gap-2">
        <div className="min-w-0">
          <p className="truncate font-semibold">{orgName}</p>
          <p className="text-muted-foreground text-xs">{roleName}</p>
        </div>
        <Button type="button" variant="ghost" size="icon" className="md:hidden" aria-label={mobileOpen ? "بستن منو" : "باز کردن منو"} aria-expanded={mobileOpen} onClick={() => setMobileOpen((open) => !open)}>
          {mobileOpen ? <XIcon aria-hidden="true" /> : <MenuIcon aria-hidden="true" />}
        </Button>
      </div>
      <nav className={cn("flex-col gap-1 md:flex", mobileOpen ? "flex" : "hidden")}>
        {navItems.map((item) => {
          const href = `/${orgId}${item.href}`;
          const active = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={item.href}
              href={href}
              onClick={() => setMobileOpen(false)}
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
      <div className={cn("mt-auto flex-col gap-2 md:flex", mobileOpen ? "flex" : "hidden")}>
        <ThemeToggle />
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
