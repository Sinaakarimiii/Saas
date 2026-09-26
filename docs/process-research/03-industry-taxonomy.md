# ۰۳ — Industry Taxonomy

## پایه: نسخه‌های صنعتی واقعی APQC (تأییدشده از منبع اصلی PCF)

Research نشان داد APQC دقیقاً **۱۹ نسخه‌ی صنعتی مستقل** از PCF منتشر کرده (استخراج مستقیم از سند رسمی APQC، «Understanding the Elements of PCF»، ۲۰۱۸، و بازبینی‌شده با جست‌وجوی ۲۰۲۶). این‌ها صنایعی هستند که APQC عمق Level 3/4 اضافه‌ای برایشان منتشر کرده — نه یک اسکلت جدا، بلکه همان ۱۳ Category با شاخه‌های عمیق‌تر (نمونه‌ی تأییدشده: Process Group 4.3 در حالت عمومی ۴ Process دارد، در نسخه‌ی Aerospace &amp; Defense به ۱۶ Process می‌رسد).

| # | Industry (APQC-verified) | name_fa | apqc_variant_available |
|---|---|---|---|
| 1 | Aerospace &amp; Defense | هوافضا و دفاعی | ✅ |
| 2 | Airline | هواپیمایی | ✅ |
| 3 | Automotive | خودروسازی | ✅ |
| 4 | Banking | بانکداری | ✅ |
| 5 | Broadcasting | پخش رادیویی/تلویزیونی | ✅ |
| 6 | City Government | شهرداری/دولت محلی | ✅ |
| 7 | Consumer Electronics | الکترونیک مصرفی | ✅ |
| 8 | Consumer Products | کالاهای مصرفی | ✅ |
| 9 | Corrosion (industry) | صنعت خوردگی | ✅ |
| 10 | Downstream Petroleum | پایین‌دستی نفت | ✅ |
| 11 | Education | آموزش | ✅ |
| 12 | Health Insurance Payor | بیمه‌گر سلامت | ✅ |
| 13 | Healthcare Provider | ارائه‌دهنده‌ی خدمات درمانی | ✅ |
| 14 | Insurance | بیمه | ✅ |
| 15 | Life Sciences | علوم زیستی/دارویی | ✅ |
| 16 | Retail | خرده‌فروشی | ✅ |
| 17 | Telecommunications | مخابرات | ✅ |
| 18 | Upstream Petroleum | بالادستی نفت | ✅ |
| 19 | Utilities | خدمات آب/برق/گاز | ✅ |

**سطح اطمینان:** High — استخراج مستقیم از PDF رسمی APQC، نه خلاصه‌ی ثانویه.

## گسترش: صنایع درخواستی کاربر که APQC نسخه‌ی مستقل ندارد

این صنایع طبق فهرست صریح کاربر (بخش چهارم Prompt) اضافه شدند؛ همه از **Cross-Industry PCF** به‌عنوان پایه استفاده می‌کنند (چون نسخه‌ی اختصاصی APQC ندارند)، اما به‌عنوان برچسب `industry` روی Organization معنادار و لازم‌اند تا فیلتر/پیشنهاد Process درست کار کند.

| Industry | name_fa | زیرمجموعه‌ی نزدیک‌ترین APQC Industry (اگر هست) |
|---|---|---|
| Technology / Software / SaaS | فناوری/نرم‌افزار/سرویس ابری | نزدیک‌ترین: Consumer Electronics (سخت‌افزار) — برای نرم‌افزار خالص معادل مستقیم APQC نیست |
| Construction | ساخت‌وساز | — |
| Engineering | مهندسی | — |
| Architecture | معماری | — |
| Pharmaceutical | داروسازی | زیرمجموعه‌ی Life Sciences |
| Financial Services (غیربانکی) | خدمات مالی | نزدیک به Banking/Insurance اما مستقل |
| Retail / E-commerce | خرده‌فروشی/تجارت الکترونیک | Retail (APQC) پوشش می‌دهد؛ E-commerce زیرمجموعه |
| Logistics / Transportation / Warehousing | لجستیک/حمل‌ونقل/انبارداری | نزدیک‌ترین: Airline (فقط هوایی)؛ فاقد پوشش زمینی مستقل در APQC |
| Government / Municipality | دولت/شهرداری | City Government (APQC) فقط سطح شهرداری را پوشش می‌دهد؛ دولت ملی مستقل نیست |
| Energy / Oil &amp; Gas / Mining | انرژی/نفت‌وگاز/معدن | Upstream/Downstream Petroleum (APQC) نفت را پوشش می‌دهد؛ معدن مستقل نیست |
| Agriculture / Food | کشاورزی/غذایی | نزدیک به Consumer Products |
| Hospitality / Travel | مهمان‌نوازی/گردشگری | — |
| Real Estate / Property Management | املاک/مدیریت ساختمان | — |
| Media / Advertising | رسانه/تبلیغات | نزدیک به Broadcasting (فقط پخش) |
| Consulting / Professional Services | مشاوره/خدمات حرفه‌ای | — |
| Legal Services | خدمات حقوقی | — |
| Security Services | خدمات امنیتی | — |
| Nonprofit | غیرانتفاعی | — |

**نتیجه‌ی طراحی:** فیلد `industries.apqc_variant_available` این تفاوت را در Data Model کدگذاری می‌کند (نگاه کنید [۰۹](09-data-model.md)) — برای صنایع بدون نسخه‌ی اختصاصی، محصول باید صریحاً Cross-Industry Process پیشنهاد بدهد، نه وانمود کند نسخه‌ی تخصصی وجود دارد.

## قانون طلایی: صنعت یک لایه‌ی Taxonomy نیست، یک برچسب فیلترکننده است

طبق یافته‌ی Research (بخش ۵ گزارش APQC): «industry variants share the same root skeleton/coordinates, differing mainly in Level 3/4 depth». یعنی `industries` در Data Model **به `processes` مستقیم متصل نمی‌شود** با یک ستون `industry_id` ساده؛ به‌جایش جدول چندبه‌چند `process_industries(process_id, industry_id, relevance)` استفاده می‌شود (نگاه کنید [۰۹](09-data-model.md)) — چون اکثر Processها (مثل «Leave Request») در همه‌ی صنایع یکسان‌اند و فقط تعداد کمی (مثل «Vendor Onboarding» در Downstream Petroleum) واقعاً صنعت-محور می‌شوند.

---
**اسناد مرتبط:** [۰۴-Domain Taxonomy](04-domain-taxonomy.md) · [۰۵-Process Taxonomy](05-process-taxonomy.md) · `data/process-library/industries.json`
