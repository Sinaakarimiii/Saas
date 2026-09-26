# ۱۷ — توصیه‌های محصول: MVP در برابر V2 در برابر Enterprise، و مقایسه با پروژه‌ی فعلی

## بخش الف — MVP / V2 / Enterprise

| Capability | سطح | Priority | Complexity | Business Value | Dependency |
|---|---|---|---|---|---|
| Workflow Template + Version (بدون Migration) | MVP | P0 | متوسط | بسیار بالا | هیچ (پایه‌ی همه‌چیز) |
| Node: Start/End/Task/Approval/Decision/Branch/Parallel/Merge | MVP | P0 | متوسط | بسیار بالا | Template/Version |
| Form Node + اتصال به Form Builder موجود | MVP | P0 | کم (زیرساخت از قبل هست) | بسیار بالا | ماژول Form Builder موجود پروژه |
| Assignment: Specific User/Role/Requester/Requester's Manager | MVP | P0 | کم | بسیار بالا | `org_members`/`manager_id` موجود |
| Work Item + وضعیت پایه (pending/completed) | MVP | P0 | کم | بسیار بالا | — |
| Audit Log Integration (نوشتن به `audit_log` موجود) | MVP | P0 | کم | بالا (امنیتی) | جدول `audit_log` موجود پروژه |
| Rule Engine ساده (Decision Table تک‌ورودی، Hit Policy=Unique) | MVP | P1 | متوسط | بالا | Node Decision |
| SLA پایه (یک Target، بدون Pause/Business Calendar) | V2 | P1 | متوسط | بالا | `schedules` |
| Escalation چندسطحی | V2 | P1 | متوسط | بالا | SLA پایه |
| Node: Timer/Wait/Loop/Multi-Instance | V2 | P2 | بالا | متوسط | Engine پایه |
| Reusable Subprocess (`is_callable_only`) | V2 | P1 | بالا | بالا (کاهش تکرار الگوی Approval) | Template/Version پایدار |
| Assignment: Round Robin/Load Balancing/Skill-Based | V2 | P2 | بالا | متوسط | Assignment پایه |
| Business Calendar کامل (Business Hours/Holidays/Pause-Resume) | V2 | P2 | بالا | متوسط | ماژول تقویم موجود پروژه |
| Delegation (غیبت موقت) | V2 | P2 | متوسط | متوسط | Assignment پایه |
| Process Instance Migration | Enterprise | P3 | بسیار بالا | کم (فقط سازمان‌های بزرگ با Instanceهای طولانی‌مدت لازم دارند) | Version پایدار + تست گسترده |
| Webhook/API Call Node + Integration بیرونی | Enterprise | P2 | بالا | بالا (برای مشتریان بزرگ) | زیرساخت امنیتی/Secret Management که هنوز در پروژه نیست |
| Script/Function Node (Sandbox) | Enterprise | P3 | بسیار بالا (ریسک امنیتی Sandbox) | متوسط | زیرساخت Sandbox که هنوز وجود ندارد |
| Round-trip Editor بصری (Drag &amp; Drop Builder) | MVP-تا-V2 (مرحله‌ای) | P1 | بسیار بالا | بسیار بالا | Node Catalog + Data Model پایدار |
| Process Library UI (مرور/جستجو/فیلتر Catalog) | V2 | P2 | متوسط | متوسط | `processes.json` Seed شده در DB |
| Analytics/KPI Dashboard روی Process Metrics | Enterprise | P3 | بالا | متوسط | حجم داده‌ی کافی از اجرای واقعی |

## بخش ب — Universal Process Builder Capability Matrix

| Capability | MVP | V2 | Enterprise | چرا |
|---|:---:|:---:|:---:|---|
| Form | ✅ | | | بدون آن هیچ Process‌ای داده جمع نمی‌کند |
| Approval (تک‌سطحی) | ✅ | | | پرتکرارترین Node در ۲۰ نمونه‌ی کامل ([۱۰](10-process-library.md)) |
| Approval (چندسطحی/موازی) | | ✅ | | نیاز به Assignment پیچیده‌تر و UI بیشتر دارد |
| Decision (شرط ساده) | ✅ | | | لازم برای حتی ساده‌ترین Branching |
| Rule Engine (Decision Table کامل با Hit Policy) | | ✅ | | تا وقتی شرط‌ها ساده‌اند، نیاز فوری نیست |
| Parallel/Merge | | ✅ | | اکثر فرایندهای ساده خطی‌اند؛ فقط Onboarding-type نیاز دارند |
| SLA (پایه) | | ✅ | | ارزش بالا اما بدون Business Calendar کامل، دقتش محدود است |
| Escalation | | ✅ | | وابسته به SLA |
| Reusable Subprocess | | ✅ | | ارزش بالا اما بدون Template پایدار خطرناک است (نگاه کنید [۱۵-versioning](15-versioning.md)) |
| Delegation | | ✅ | | نیاز واقعی اما نه برای اولین انتشار |
| Version Migration | | | ✅ | فقط سازمان‌های با Instanceهای بسیار طولانی نیاز دارند |
| API/Webhook Integration | | | ✅ | ریسک امنیتی بالا، نیاز به زیرساخت Secret Management |
| Script/Function (Sandbox) | | | ✅ | بالاترین ریسک امنیتی کل کاتالوگ Node |
| Multi-language Process Library UI | ✅ (فقط fa/en) | | | داده از ابتدا `name_en`/`name_fa` دارد، هزینه‌ی اضافه‌ی UI کم است |
| Business Calendar کامل | | ✅ | | وابسته به هماهنگی با ماژول تقویم موجود که هنوز کامل نیست (نگاه کنید Gap در بخش پ) |

## بخش پ — Current Project vs Target Architecture (پاسخ صریح به دستور کاربر)

این بخش وضعیت واقعی `org_platform` (بر اساس بررسی مستقیم Schema/کد در همین Session) را با معماری پیشنهادی مقایسه می‌کند.

### چه چیزی از قبل وجود دارد و مستقیماً قابل‌استفاده است

| موجود در پروژه | چگونه به معماری پیشنهادی وصل می‌شود |
|---|---|
| `organizations`, `org_members`, `roles`, `role_permissions`, تابع `has_permission`/`permission_scope` | مستقیماً به‌عنوان لایه‌ی Authorization زیر Assignment/Rule Engine استفاده می‌شود — نیازی به بازسازی نیست |
| `form_templates`, `form_fields` (با ۷ نوع فیلد طبق حافظه‌ی پروژه) | پایه‌ی `form_templates`/`form_versions` پیشنهادی؛ فقط یک لایه‌ی نسخه‌بندی روی آن اضافه می‌شود ([۱۵](15-versioning.md)) |
| `audit_log` (Append-only، Privilege-Revoked طبق Audit امنیتی قبلی همین Session) | Workflow Engine باید مستقیماً به همین جدول بنویسد، نه جدول موازی |
| `tickets`, `ticket_field_values`, `tracking_codes` | Ticket فعلی = یک نوع خاص و ساده از Case (نگاه کنید [۰۲](02-process-concepts.md))؛ می‌تواند اولین ماژول باشد که Workflow روی آن سوار می‌شود بدون بازنویسی |
| `org_members.manager_id` (سلسله‌مراتب مدیریتی، اضافه‌شده در گام ۲) | مستقیماً پایه‌ی Assignment «Requester's Manager» ([۱۳](13-role-assignment-model.md)) است — از قبل آماده است |
| `calendar_events`, `holidays.ts`, شیفت‌ها | پایه‌ی `schedules`/`schedule_holidays` پیشنهادی ([۱۲](12-sla-and-escalation.md)) — باید **Sync شود، نه بازسازی** |

### چه چیزی Missing است (باید از صفر ساخته شود)

- `workflow_templates`/`workflow_versions`/`workflow_instances`/`work_items` و کل موتور اجرا — **هیچ‌کدام در پروژه‌ی فعلی وجود ندارد**
- `business_rules`/Decision Table Engine — وجود ندارد
- `assignment_rules` متمرکز — فعلاً Assignment در پروژه (مثلاً تخصیص Leave Approval) مستقیماً در کد Server Action Hardcode است، نه Data-driven
- `slas`/`escalation_rules` — وجود ندارد (Attendance/Leave فعلی SLA ندارند)
- Notification Queue متمرکز — فعلاً پروژه اصلاً هیچ Notification (نه ایمیل نه Toast) پیاده‌سازی نکرده (طبق Audit امنیتی قبلی همین Session، Toaster نصب است اما هیچ‌جا صدا زده نمی‌شود)

### چه چیزی باید Refactor شود

- **`audit_log` Trigger Coverage**: طبق Audit امنیتی قبلی همین Session، فقط `tickets`/`leave_requests` روی Trigger لاگ دارند. قبل از اتصال Workflow Engine به این جدول، باید این پوشش تکمیل شود — وگرنه اجرای Workflow روی جداول دیگر (مثل `org_members`) باز هم نامرئی می‌ماند.
- **Server Actions موجود** (`shifts/actions.ts`, `leave/actions.ts`, …): این‌ها منطق Approval را Inline دارند. وقتی Workflow Engine ساخته شود، این منطق باید به‌تدریج به یک Workflow Instance واقعی منتقل شود، نه اینکه دو سیستم موازی (Hardcoded Approval قدیمی + Workflow Engine جدید) هم‌زمان زنده بمانند.

### چه چیزی باید حذف شود
هیچ‌چیز — طبق قانون صریح کاربر («در این مرحله کدی تغییر نکند»)، این Research هیچ کد موجودی را برای حذف پیشنهاد نمی‌دهد؛ فقط مسیر Migration تدریجی (بالا) را مشخص می‌کند.

### چه چیزی فعلاً نباید ساخته شود
- Script/Function Node (ریسک امنیتی Sandbox بدون زیرساخت آماده)
- Webhook/Integration بیرونی (بدون Secret Management که در Audit امنیتی قبلی همین Session به‌عنوان Gap شناسایی شد)
- Process Instance Migration (پیچیدگی بسیار بالا برای ارزش کم در فاز اول)

### چه بخش‌هایی برای MVP مناسب‌اند
جدول بخش الف بالا، ردیف‌های `MVP` — همگی روی زیرساخت موجود پروژه (Org/Role/Form/Audit Log) سوار می‌شوند، بدون نیاز به زیرساخت جدید پرریسک.

### چه بخش‌هایی معماری آینده را محدود می‌کنند (اگر اشتباه ساخته شوند)
- اگر `workflow_instances` به‌جای `workflow_version_id` به `workflow_template_id` وصل شود (اشتباه رایج) — طبق [۱۵-versioning](15-versioning.md) این تصمیم برگشت‌ناپذیر است بدون Migration دردناک داده‌های تولیدشده.
- اگر Assignment مستقیم در کد Node به‌جای `assignment_rules` جدول مستقل نوشته شود — دقیقاً همان اشتباهی که Server Actions فعلی پروژه دارند و باید اصلاح شود، نه تکرار.

---
**اسناد مرتبط:** [۰۱-Executive Summary](01-executive-summary.md) · [۰۸-Engine Architecture](08-process-engine-architecture.md) · [۱۶-Gap Analysis](16-gap-analysis.md)
