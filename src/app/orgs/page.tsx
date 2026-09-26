import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default async function OrgsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: memberships, error: membershipsError } = await supabase
    .from("org_members")
    .select("org_id, organizations(id, name)")
    .eq("user_id", user.id)
    .is("deleted_at", null)
    .order("created_at", { ascending: true });

  if (membershipsError) {
    throw new Error("Could not load organization memberships", {
      cause: membershipsError,
    });
  }

  const orgs = (memberships ?? [])
    .map((m) => m.organizations)
    .filter((o): o is { id: string; name: string } => o !== null);

  if (orgs.length === 0) {
    redirect("/orgs/new");
  }

  if (orgs.length === 1) {
    redirect(`/${orgs[0].id}/dashboard`);
  }

  return (
    <div className="mx-auto flex w-full max-w-xl flex-1 flex-col gap-4 p-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">سازمان‌های شما</h1>
        <Button asChild variant="outline">
          <Link href="/orgs/new">+ سازمان جدید</Link>
        </Button>
      </div>
      <div className="grid gap-3">
        {orgs.map((org) => (
          <Link key={org.id} href={`/${org.id}/dashboard`}>
            <Card className="hover:bg-muted/50 transition-colors">
              <CardHeader>
                <CardTitle>{org.name}</CardTitle>
                <CardDescription>ورود به این سازمان</CardDescription>
                <CardAction>←</CardAction>
              </CardHeader>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  );
}
