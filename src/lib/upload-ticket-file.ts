import { createClient } from "@/lib/supabase/client";

export async function uploadTicketFile(
  orgId: string,
  formFieldId: string,
  file: File,
) {
  const supabase = createClient();
  const path = `${orgId}/${formFieldId}/${crypto.randomUUID()}-${file.name}`;
  const { error } = await supabase.storage
    .from("ticket-attachments")
    .upload(path, file);

  if (error) {
    throw new Error("آپلود فایل انجام نشد");
  }

  return { storage_path: path, file_name: file.name, size: file.size };
}
