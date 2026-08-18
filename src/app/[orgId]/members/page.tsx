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
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { InviteMemberDialog } from "./invite-dialog";
import { EditMemberDialog } from "./edit-member-dialog";

type MemberNode = {
  id: string;
  label: string;
  roleName: string;
  managerId: string | null;
  children: MemberNode[];
};

function buildTree(members: MemberNode[]): MemberNode[] {
  const byId = new Map(members.map((m) => [m.id, { ...m, children: [] as MemberNode[] }]));
  const roots: MemberNode[] = [];

  for (const m of byId.values()) {
    if (m.managerId && byId.has(m.managerId)) {
      byId.get(m.managerId)!.children.push(m);
    } else {
      roots.push(m);
    }
  }
  return roots;
}

function TreeList({ nodes }: { nodes: MemberNode[] }) {
  if (nodes.length === 0) return null;
  return (
    <ul className="grid gap-1 border-r pr-3">
      {nodes.map((n) => (
        <li key={n.id}>
          <div className="flex items-center gap-2 text-sm">
            <span>{n.label}</span>
            <Badge variant="outline" className="text-xs">
              {n.roleName}
            </Badge>
          </div>
          {n.children.length > 0 && (
            <div className="mt-1 mr-3">
              <TreeList nodes={n.children} />
            </div>
          )}
        </li>
      ))}
    </ul>
  );
}

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
      .select("id, created_at, role_id, manager_id, profiles(full_name, email), roles(name)")
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

  const memberOptions = (members ?? []).map((m) => ({
    id: m.id,
    label: m.profiles?.full_name || m.profiles?.email || "—",
  }));

  const treeNodes: MemberNode[] = (members ?? []).map((m) => ({
    id: m.id,
    label: m.profiles?.full_name || m.profiles?.email || "—",
    roleName: m.roles?.name ?? "",
    managerId: m.manager_id,
    children: [],
  }));

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">اعضا</h1>
        <InviteMemberDialog orgId={orgId} roles={roles ?? []} members={memberOptions} />
      </div>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>نام</TableHead>
            <TableHead>ایمیل</TableHead>
            <TableHead>نقش</TableHead>
            <TableHead>سرپرست</TableHead>
            <TableHead>عضو از</TableHead>
            <TableHead />
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
              <TableCell>
                {memberOptions.find((o) => o.id === m.manager_id)?.label || "—"}
              </TableCell>
              <TableCell>{formatJalaliDate(m.created_at)}</TableCell>
              <TableCell>
                <EditMemberDialog
                  orgId={orgId}
                  memberId={m.id}
                  currentRoleId={m.role_id}
                  currentManagerId={m.manager_id}
                  roles={roles ?? []}
                  members={memberOptions}
                />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">نمودار سازمانی</CardTitle>
        </CardHeader>
        <CardContent>
          <TreeList nodes={buildTree(treeNodes)} />
        </CardContent>
      </Card>
    </div>
  );
}
