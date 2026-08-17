import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Button } from "@/components/ui/button";

export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    redirect("/orgs");
  }

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-6 p-6 text-center">
      <h1 className="text-3xl font-bold">پلتفرم اتوماسیون سازمانی</h1>
      <p className="text-muted-foreground max-w-md">
        هر سازمان ماژول‌های خودش را با تنظیمات دلخواه راه‌اندازی می‌کند —
        بدون نیاز به کد جدید.
      </p>
      <div className="flex gap-3">
        <Button asChild>
          <Link href="/signup">شروع کنید</Link>
        </Button>
        <Button asChild variant="outline">
          <Link href="/login">ورود</Link>
        </Button>
      </div>
    </div>
  );
}
