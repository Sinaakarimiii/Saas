# org_platform

سامانهٔ مدیریت سازمان با Next.js 16 و Supabase. کد فعلی قابلیت‌های عضویت و نقش، فرم و تیکت، پیوست، شیفت، مرخصی، حضور و تقویم را دارد. موتور فرایندِ MVP هنوز ساخته نشده است.

برای اجرای محلی به Node.js 22.23.2، npm، Docker Desktop و Supabase CLI 2.113.0 نیاز دارید. پروژه را با `npm ci` آماده کنید. راه‌اندازی و آزمون را در محیط Supabase جداگانه انجام دهید؛ دستورها و مرزهای محیط در [راهنمای محلی](docs/revival/setup.md) آمده‌اند.

```sh
node scripts/start-local-validation.mjs --secondary
node scripts/verify-security-stage2.mjs <validation-workdir> --secondary
node scripts/with-local-env.mjs <validation-workdir> --secondary -- npm run dev -- -p 3200
```

آزمون‌ها فقط روی محیط تازهٔ محلی اجرا شوند. هر بار `start-local-validation` یک پوشهٔ خصوصی و پورت‌های مستقل می‌سازد. ایمیل‌های آزمایشی به Mailpit محلی می‌روند. فایل‌های `.env.local` و `status.json` حاوی مقادیر خصوصی‌اند و نباید وارد Git شوند.

کنترل‌های کد: `npm run lint`، `npm run typecheck` و `npm run build`. برای build به متغیرهای نمونهٔ [.env.example](.env.example) یا محیط محلی معتبر نیاز است. وضعیت مراحل، تصمیم‌ها و محدودیت‌های آزمون در [گزارش احیا](docs/revival/status.md) ثبت می‌شود.
