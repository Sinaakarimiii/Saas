import Link from "next/link";
import { redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { PERMISSIONS } from "@/lib/permissions";
import { NewRepairForm } from "./new-repair-form";

export default async function NewRepairPage({ params }: PageProps<"/[orgId]/repairs/new">) {
  const { orgId } = await params;
  const ctx = await getOrgContext(orgId);
  if (!ctx.can(PERMISSIONS.REPAIR_CASE_CREATE)) redirect(`/${orgId}/repairs`);
  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <div>
        <Link href={`/${orgId}/repairs`} className="text-sm text-primary underline-offset-4 hover:underline">بازگشت به پرونده‌ها</Link>
        <h1 className="mt-3 text-2xl font-semibold">ثبت پروندهٔ تعمیر</h1>
        <p className="mt-1 text-sm text-muted-foreground">درخواست اولیه را ثبت کنید. تطبیق IMEI با برچسب و محل نگهداری هنگام دریافت فیزیکی ثبت می‌شوند.</p>
      </div>
      <NewRepairForm orgId={orgId} />
    </div>
  );
}
