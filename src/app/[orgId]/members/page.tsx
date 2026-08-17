import { redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDate } from "@/lib/jalali";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { InviteMemberDialog } from "./invite-dialog";

export default async function MembersPage({
  params,
}: PageProps<"/[orgId]/members">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);

  if (!ctx.can(PERMISSIONS.MANAGE_MEMBERS)) {
    redirect(`/${orgId}/dashboard`);
  }

  const supabase = await createClient();

  const [{ data: members }, { data: roles }] = await Promise.all([
    supabase
      .from("org_members")
      .select("id, created_at, profiles(full_name, email), roles(name)")
      .eq("org_id", orgId)
      .is("deleted_at", null)
      .order("created_at", { ascending: true }),
    supabase
      .from("roles")
      .select("id, name")
      .eq("org_id", orgId)
      .is("deleted_at", null)
      .order("created_at", { ascending: true }),
  ]);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">اعضا</h1>
        <InviteMemberDialog orgId={orgId} roles={roles ?? []} />
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>نام</TableHead>
            <TableHead>ایمیل</TableHead>
            <TableHead>نقش</TableHead>
            <TableHead>عضو از</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {(members ?? []).map((m) => (
            <TableRow key={m.id}>
              <TableCell>{m.profiles?.full_name || "—"}</TableCell>
              <TableCell dir="ltr" className="text-right">
                {m.profiles?.email}
              </TableCell>
              <TableCell>
                <Badge variant="secondary">{m.roles?.name}</Badge>
              </TableCell>
              <TableCell>{formatJalaliDate(m.created_at)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
