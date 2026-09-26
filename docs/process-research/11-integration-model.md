# ۱۱ — ارتباط Process Builder با سایر ماژول‌های محصول

Process Builder نباید یک ماژول جزیره‌ای باشد. برای هر Integration: Trigger، Input، Output، Data Contract، Dependency، Ownership.

## Calendar / Shift (ماژول موجود پروژه: `calendar`, `shifts`, `holidays.ts`)

| | |
|---|---|
| Trigger | یک `Wait`/`Timer`/`Due Date` Node در Workflow نیاز به محاسبه‌ی «چند روز کاری بعد» دارد |
| Input | تاریخ شروع + `schedule_id` (که باید معادل تقویم/شیفت همان Organization باشد) |
| Output | تاریخ/ساعت واقعی سررسید، با احتساب تعطیلات و ساعت کاری |
| Data Contract | `schedules`/`schedule_holidays` (سند [۱۲](12-sla-and-escalation.md)) باید از همان منبع تعطیلات رسمی ایران که `holidays.ts`/`calendar_events` موجود پروژه دارند تغذیه شوند — **نباید دو منبع حقیقت برای تعطیلات وجود داشته باشد** |
| Dependency | Process Engine بدون این ادغام هم کار می‌کند (Calendar Hours ساده) اما SLA دقیق (Business Hours) بدون آن ناقص است |
| Ownership | ماژول تقویم مالک داده‌ی تعطیلات/شیفت است؛ Process Engine فقط مصرف‌کننده است، نه Cache مستقل نگه می‌دارد |

## Project Management (گام ۳ نقشه‌راه)

| | |
|---|---|
| Trigger | Node از نوع `Create Record` با نوع مقصد `project`/`milestone`/`task` |
| Input | عنوان، تاریخ‌ها، Owner، متغیرهای Instance که باید به فیلدهای پروژه Map شوند |
| Output | شناسه‌ی Project/Milestone/Task ساخته‌شده، برگردانده به `process_variables` برای استفاده در Nodeهای بعدی |
| Data Contract | Mapping فیلد صریح (نه ضمنی) طبق همان الگوی Contract-based Input/Output در [۰۸](08-process-engine-architecture.md) |
| Dependency | مستقل — Project Module می‌تواند بدون Process Engine هم کار کند؛ این یک ادغام یک‌طرفه است (Workflow → Project، نه برعکس، حداقل در فاز اول) |
| Ownership | ماژول Project مالک Schema پروژه/Milestone است |

## Task Manager

| | |
|---|---|
| Trigger | هر Human Work Node (`Task`) می‌تواند به‌صورت اختیاری یک کارت Task Manager هم بسازد (برای نمایش در Kanban ماژول مربوطه)، نه فقط `work_items` داخلی |
| Input | عنوان، Assignee، Deadline از خودِ Work Item |
| Output | وضعیت تکمیل Task Manager باید Work Item مربوطه را هم به‌روزرسانی کند (دوطرفه، برخلاف اکثر Integrationهای این سند) |
| Data Contract | `work_items.external_ref jsonb` (اشاره به رکورد Task Manager) + Webhook/Event برعکس برای Sync وضعیت |
| Dependency | طبق ROADMAP.md، Task Manager موتور جدا ندارد و باید از همین Workflow Engine استفاده کند — این یعنی این Integration در واقع «همان سیستم»، نه دو سیستم جدا با پل ارتباطی |
| Ownership | مشترک — این تنها Integration در این سند است که واقعاً دوطرفه و بدون مالک یکتا است |

## Ticketing (ماژول موجود پروژه: `tickets`)

| | |
|---|---|
| Trigger | `Create Ticket` Node، یا برعکس: تغییر وضعیت یک Ticket موجود می‌تواند یک Workflow Instance را Trigger کند (مثلاً «Ticket بسته شد → شروع فرایند نظرسنجی رضایت») |
| Input | فیلدهای Ticket (که خودشان از `form_fields` موجود پروژه می‌آیند — دقیقاً همان Contract با ماژول Form Builder، تکراری نساز) |
| Output | `tracking_code` موجود پروژه، شناسه‌ی Ticket |
| Data Contract | `tickets.id` ↔ `workflow_instances.related_record_type='ticket', related_record_id` |
| Dependency | Ticketing موجود در پروژه از قبل کار می‌کند بدون Workflow Engine؛ این Integration باید **افزایشی (Additive)** باشد — رفتار فعلی Ticket را نشکند (طبق قانون کاربر «کدنویسی اپلیکیشن تغییر نکند» در همین Research) |
| Ownership | ماژول Ticketing مالک داده‌ی Ticket است |

## Form Builder (ماژول موجود پروژه: `form_templates`, `form_fields`)

نگاه کنید به [۰۹-data-model](09-data-model.md) بخش Forms و [۱۵-versioning](15-versioning.md) برای مدل نسخه‌بندی کامل. خلاصه:
| | |
|---|---|
| Trigger | `Form` Node در گراف Workflow |
| Data Contract | هر فیلد Form با یک `variable name` مشخص، مستقیم به `process_variables` نگاشت می‌شود؛ نوع فیلد Form باید با نوع اعلام‌شده در ورودی Node بعدی سازگار باشد (اعتبارسنجی زمان طراحی، نه فقط زمان اجرا) |
| Dependency | Workflow Engine به Form Builder موجود پروژه وابسته است، نه برعکس — Form Builder باید بدون تغییر بماند، فقط یک لایه‌ی نسخه‌بندی (`form_versions`) رویش اضافه می‌شود |

## Document Management

| | |
|---|---|
| Trigger | `Create Record` با نوع مقصد `document`، یا Sub-pattern «Document Sign-off» ([۰۶](06-process-patterns.md) الگو ۳) |
| Output | سند تولیدشده + وضعیت امضا/تأیید |
| Dependency | این ماژول در ROADMAP.md فعلی تعریف‌نشده — طبق [۱۶-gap-analysis](16-gap-analysis.md) یک Gap واقعی است، نه صرفاً Integration نظری |

## Correspondence (نامه‌های اداری)

| | |
|---|---|
| Trigger | الگوی Document Sign-off + Notification |
| Dependency | طبق ROADMAP.md، این پروفایل «عملیات» بعداً روی همین موتور ساخته می‌شود (گام ۴)، بدون تغییر هسته |

## Timesheet

| | |
|---|---|
| Trigger | `Work Item` از نوع خاص می‌تواند Start/Stop زمان را ثبت کند |
| Data Contract | این دقیقاً معادل Runtime `attendance_logs` موجود پروژه است — باید بررسی شود آیا Timesheet یک ماژول جدا لازم دارد یا می‌تواند روی همان `attendance` موجود بنا شود (توصیه: بنا شود، نه بازسازی) |

## Notification

| | |
|---|---|
| Trigger | هر Node که به Notification نیاز دارد (`Send Email`/`Send SMS`/`In-app`، نگاه کنید [۰۷](07-workflow-node-catalog.md)) |
| Data Contract | یک صف Notification مرکزی (خارج از Scope این Research، اما باید به‌عنوان یک Entity/Service مستقل طراحی شود که همه‌ی ماژول‌ها از جمله Process Engine از آن استفاده کنند — نه اینکه هر Node مستقیم ایمیل بفرستد) |
| Ownership | این سرویس باید مالک واحد داشته باشد؛ Process Engine فقط صف را پر می‌کند |

---
**اسناد مرتبط:** [۰۸-Engine Architecture](08-process-engine-architecture.md) · [۱۲-SLA](12-sla-and-escalation.md) · [۱۶-Gap Analysis](16-gap-analysis.md)
