"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function createOrganization(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) {
    return { error: "نام سازمان نمی‌تواند خالی باشد" };
  }

  const supabase = await createClient();
  // create_organization returns a single row (not a set), so its Result
  // type is already the plain row -- calling .single() here would actually
  // break the inferred type (it unwraps an array type that doesn't exist).
  const { data, error } = await supabase.rpc("create_organization", {
    p_name: name,
  });

  if (error || !data) {
    return { error: "ساخت سازمان انجام نشد. دوباره تلاش کنید." };
  }

  redirect(`/${data.id}/dashboard`);
}
