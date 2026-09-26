# org_platform

برنامهٔ سازمانی با Next.js 16 و Supabase. وضعیت احیا، تصمیم‌ها، نتایج آزمون و کارهای باز در [status.md](status.md) ثبت شده‌اند. [گزارش فنی ۱۹ سپتامبر ۲۰۲۶](technical-review-2026-09-19.md) مبنای بررسی اولیه بود.

## راه‌اندازی آزمایشی محلی

پیش‌نیاز: Node.js 22، npm، Docker Desktop فعال و Supabase CLI نسخهٔ `2.113.0`. نسخهٔ Node را با `node --version` بررسی کنید. نصب وابستگی‌ها از lockfile با `npm ci` انجام می‌شود. سرویس محلی موجود با شناسهٔ `org_platform` یا فایل `supabase/.temp` ممکن است به محیط دیگری متصل باشند؛ دستورهای زیر محیط تازه‌ای با شناسه و پورت مستقل می‌سازند.

```sh
node scripts/start-local-validation.mjs
```

اسکریپت، مسیر محیط آزمایشی را چاپ می‌کند. در دستورهای زیر آن را جایگزین `<validation-workdir>` کنید. کلیدها در `status.json` خصوصی همان پوشه نگه داشته می‌شوند؛ آن فایل را در Git یا گزارش قرار ندهید.

```sh
node scripts/verify-local-baseline.mjs <validation-workdir>
node scripts/with-local-env.mjs <validation-workdir> -- npm run build
node scripts/with-local-env.mjs <validation-workdir> -- npm run dev -- -p 3100
```

`verify-local-baseline` با `createUser` چهار کاربر آزمایشی `example.test` می‌سازد؛ ایمیل دعوت بیرونی ارسال نمی‌کند و رد درج audit جعلی را بررسی می‌کند. برای آزمون‌های کامل‌تر RLS، RPC و Storage، `node scripts/verify-security-stage2.mjs <validation-workdir>` را اجرا کنید. سرویس محلی Mailpit روی `http://127.0.0.1:55324` است؛ آزمایش دعوت در مراحل بعد فقط با گیرندهٔ آزمایشی انجام می‌شود.

برای دیدن دستورهای CLI از `supabase --help` استفاده کنید. اگر محیط آزمایشی قبلی هنوز روی پورت‌های `5532x` اجراست، پیش از ساخت محیط تازه فقط همان را با `supabase stop --workdir <validation-workdir>` متوقف کنید؛ گزینهٔ حذف داده را به کار نبرید. به محیط `org_platform` موجود و اتصال ذخیره‌شدهٔ غیرمحلی دست نزنید.

## بررسی‌های فعلی

```sh
npm run lint
./node_modules/.bin/tsc --noEmit --incremental false
```

فایل `.env.example` فقط نام متغیرها را نشان می‌دهد. مقدارهای محلی را از محیط آزمایشی خود تهیه کنید؛ `with-local-env` آن‌ها را بدون ساخت `.env.local` در فرمان‌های آزمایشی اعمال می‌کند. build و lint مجوز داده یا امنیت RLS را ثابت نمی‌کنند؛ نتایج مرتبط در سند وضعیت آمده‌اند.
