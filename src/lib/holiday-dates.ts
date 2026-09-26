import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";

export async function fetchHolidayDates(
  supabase: SupabaseClient<Database>,
): Promise<string[]> {
  const pageSize = 500;
  const dates: string[] = [];
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await supabase
      .from("calendar_events")
      .select("gregorian_date")
      .eq("is_holiday", true)
      .order("gregorian_date")
      .order("id")
      .range(offset, offset + pageSize - 1);
    if (error) throw new Error("دریافت تعطیلات انجام نشد", { cause: error });
    dates.push(...(data ?? []).map((row) => row.gregorian_date));
    if (!data || data.length < pageSize) break;
  }
  return dates;
}
