# ۰۷ — کاتالوگ Node های Workflow Builder

منبع: مقایسه‌ی مستقیم واژگان BPMN 2.0 (استاندارد OMG) با پنج موتور واقعی — Camunda، AWS Step Functions، n8n، ServiceNow Flow Designer، Pega. برای هر Node: هدف، Input/Output، Configuration، وضعیت‌های ممکن، اعتبارسنجی، مجوز، مدیریت خطا، نیاز به Audit — طبق درخواست صریح کاربر.

## اصل طراحی: چهار دسته‌ی بالادستی

هر Node دقیقاً در یکی از این چهار دسته قرار می‌گیرد (این دسته‌بندی از تلفیق BPMN Flow-Object-types با واژگان n8n/Step Functions به‌دست آمد):

1. **Flow Control** — مسیر اجرا را تعیین می‌کند، خودش کار کسب‌وکاری انجام نمی‌دهد (Start/End/Gateway/Wait/Loop/Merge)
2. **Human Work** — منتظر یک Actor انسانی می‌ماند (Task/Approval/Review/Form)
3. **Automation** — بدون انسان اجرا می‌شود (Create/Update Record، Send Notification، Webhook، Script)
4. **Sub-graph** — یک گراف دیگر را فرامی‌خواند (Subprocess/Call Process)

## جدول کامل

| Node | دسته | هدف | Input | Output | Config کلیدی | State ها | اعتبارسنجی | مجوز | خطا/Retry | Audit |
|---|---|---|---|---|---|---|---|---|---|---|
| **Start** | Flow Control | نقطه‌ی ورود گراف؛ می‌تواند دستی، زمان‌بندی‌شده، یا رویدادمحور باشد (طبق BPMN Start Event: None/Message/Timer/Signal/Conditional) | Trigger payload | متغیرهای اولیه‌ی Instance | نوع Trigger؛ Formی که باید پر شود (اگر دستی) | — (لحظه‌ای) | اعتبارسنجی Form پیوست (اگر هست) | چه کسی/چه Roleای مجاز به شروع است | — | ساخت Instance همیشه Audit می‌شود |
| **End** | Flow Control | پایان یک مسیر؛ می‌تواند End موفق یا End شکست باشد (BPMN: None/Error/Terminate End) | — | نتیجه‌ی نهایی Instance | نوع پایان (success/fail/terminate) | — | — | — | Terminate End همه‌ی مسیرهای موازی باز را هم می‌بندد | همیشه |
| **Task** | Human Work | یک واحد کار دستی که موتور فقط تکمیلش را ثبت می‌کند، منتظر جزئیات نمی‌ماند (معادل BPMN Manual Task) | متن دستورالعمل | تیک تکمیل | Assignee/Role | pending→completed | — | Assignee/Role | — | تکمیل Audit می‌شود |
| **Approval** | Human Work | تصمیم Approve/Reject توسط یک یا چند Actor؛ اولین‌شهروند در Pega/ServiceNow، نه یک Task دستی معمولی | Context (رکورد/Formِ مرتبط) | decision: approved\|rejected + note | تک‌مرحله‌ای/چندمرحله‌ای، Sequential/Parallel، حداقل رأی لازم (برای Parallel) | pending→(approved\|rejected)→(escalated) | حداقل یک نظر برای Reject الزامی (Config) | لیست Approverها (User/Role/Dynamic Expression) | Timeout → Escalation (نگاه کنید [۱۲](12-sla-and-escalation.md)) | تصمیم + دلیل همیشه Audit می‌شود |
| **Review** | Human Work | بازبینی بدون تصمیم دودویی؛ خروجی می‌تواند Approve/Request-Changes/Comment باشد (شبیه چرخه‌ی Sequential Review) | سند/داده‌ی مرور | نظرات + وضعیت | نیاز به چند دور بازبینی؟ | pending→(approved\|changes_requested) | — | Reviewer role | برگشت به فرستنده در Request-Changes | همیشه |
| **Form** | Human Work | جمع‌آوری داده‌ی ساختاریافته از یک Actor؛ خروجی مستقیماً `process_variables` می‌شود | form_version_id | داده‌ی پرشده | کدام نسخه‌ی Form (نگاه کنید [۱۵](15-versioning.md)) | pending→submitted | طبق Schema فیلدهای Form | چه کسی مجاز به پر کردن | ذخیره‌ی پیش‌نویس (Draft Save) اختیاری | ثبت پر شدن |
| **Decision / Condition** | Flow Control | مسیر را بر اساس داده تعیین می‌کند؛ خودکار، بدون Actor — معادل BPMN Exclusive Gateway ساده یا Business Rule Task اگر به Decision Table وصل شود | متغیرهای Instance | مسیر انتخابی | عبارت شرطی ساده، یا ارجاع به `business_rules` (نگاه کنید [۱۴](14-rule-engine.md)) | بی‌درنگ | نوع داده‌ی مقایسه‌شده باید معتبر باشد | — | شرط نامعتبر → Exception | فقط اگر به Rule Engine وصل است |
| **Branch (Exclusive)** | Flow Control | دقیقاً یک مسیر از N مسیر انتخاب می‌شود (BPMN Exclusive/XOR Gateway) | نتیجه‌ی Decision قبلی | یک مسیر خروجی | مسیر پیش‌فرض برای «هیچ‌کدام مچ نشد» الزامی | — | باید دقیقاً یک مسیر مچ شود یا Default باشد | — | نبود Default + عدم تطبیق → Exception | خیر |
| **Parallel (Fork)** | Flow Control | چند مسیر هم‌زمان باز می‌شوند (BPMN Parallel/AND Gateway) | — | N مسیر فعال | چند مسیر | — | — | — | — | خیر |
| **Merge (Join)** | Flow Control | مسیرهای موازی به یک مسیر برمی‌گردند؛ منتظر همه یا حداقل تعداد مشخص می‌ماند | N مسیر ورودی | یک مسیر خروجی | Wait-for-all یا Wait-for-N (Inclusive Gateway) | waiting→merged | — | — | مسیر گم‌شده/بی‌پایان → Timeout Exception | خیر |
| **Wait / Delay** | Flow Control | مکث تا زمان مشخص یا مدت مشخص (BPMN Timer Intermediate Event) | — | ادامه‌ی مسیر | مدت یا Timestamp مطلق، احترام به Business Calendar یا نه | waiting→resumed | — | — | — | شروع/پایان انتظار |
| **Timer / Reminder** | Flow Control | مشابه Wait اما غیرقطع‌کننده — کنار یک Human Node می‌نشیند و بدون توقف کار اصلی هشدار می‌دهد (BPMN Non-interrupting Timer Boundary Event) | — | Notification | مدت، تکرارشونده یا یک‌باره | armed→fired | — | — | — | هر بار Fire شدن |
| **Escalation** | Flow Control | تغییر Actor/سطح مسئولیت یک Work Item بدون لغو آن (BPMN Escalation Event) | Work Item فعلی | Work Item با Assignee/Role جدید | سطوح Escalation (نگاه کنید [۱۲](12-sla-and-escalation.md)) | — | — | سطح بعدی باید معتبر باشد | خودش واکنش به خطا/تأخیر است | همیشه، حیاتی برای ردیابی |
| **Loop** | Flow Control | تکرار یک زیرمسیر تا شرط خروج (BPMN Standard Loop) | شرط ادامه | — | حداکثر تکرار (جلوگیری از Infinite Loop) | — | حداکثر تکرار الزامی در Config | — | عبور از حداکثر تکرار → Exception | خیر |
| **Multi-Instance (Map)** | Flow Control | همان زیرگراف روی هر عضو یک آرایه اجرا می‌شود (معادل Step Functions `Map` / BPMN Multi-Instance marker) | آرایه‌ی ورودی | آرایه‌ی نتایج | Sequential یا Parallel، حداکثر همزمانی | — | آرایه‌ی ورودی نباید خالی/نامعتبر باشد | — | شکست یک عضو: ادامه یا توقف کل (Config) | تجمیع در پایان |
| **Subprocess / Call Process** | Sub-graph | فراخوانی یک `workflow_template` دیگر (نگاه کنید [۰۸](08-process-engine-architecture.md)) | Contract ورودی تعریف‌شده | Contract خروجی تعریف‌شده | کدام Template/نسخه (latest یا Pin شده) | waiting_for_child→resumed | Inputهای الزامی Contract باید پر باشند | — | شکست Child → Exception در Parent (Config قابل Catch) | شروع/پایان Child |
| **Create Record / Update Record** | Automation | ساخت یا ویرایش یک رکورد در یکی از ماژول‌های محصول (Ticket، Task، Project، …) | فیلدهای رکورد | شناسه‌ی رکورد ساخته/ویرایش‌شده | کدام نوع رکورد، Mapping فیلد | — | طبق Schema رکورد مقصد | مجوز نوشتن روی آن نوع رکورد | خطای DB → Retry با Backoff | همیشه |
| **Create Task / Create Ticket / Create Project** | Automation | نمونه‌ی خاص Create Record برای ماژول‌های اصلی محصول (نگاه کنید [۱۱-integration](11-integration-model.md)) | — | شناسه‌ی رکورد ساخته‌شده در ماژول مقصد | ماژول مقصد + Mapping | — | — | — | — | همیشه |
| **Send Email / Send SMS / In-app Notification** | Automation | اطلاع‌رسانی یک‌طرفه (نگاه کنید Notification در [۰۲](02-process-concepts.md)) | گیرنده + Template پیام | رسید ارسال | کانال، Template، زبان | sent→delivered\|failed | آدرس گیرنده معتبر باشد | — | شکست ارسال → Retry محدود، سپس Log خطا (بدون توقف Instance) | لاگ ارسال (نه لزوماً کل محتوا) |
| **Webhook / API Call / Integration** | Automation | فراخوانی یک سیستم بیرونی (معادل BPMN Service Task) | URL/Payload | Response | Method، Headers، Timeout، Auth | pending→success\|failed | Schema پاسخ اگر تعریف شده | کلید API محدود به Scope لازم | Retry با Exponential Backoff + Circuit Breaker پیشنهادی | Request/Response Metadata (نه Secret) |
| **Script / Function** | Automation | منطق سفارشی کوتاه (معادل BPMN Script Task) — باید محدود و Sandbox شود، نه دسترسی آزاد به کل سیستم | متغیرهای Instance | متغیرهای جدید/تغییریافته | کد Sandbox‌شده | — | خروجی باید با نوع اعلام‌شده مطابق باشد | چه کسی مجاز به ویرایش Script است (باید محدودتر از بقیه‌ی Nodeها باشد) | Timeout اجباری، خطا → Exception | نسخه‌ی کد اجراشده |
| **Manual Action** | Human Work | معادل Task ولی بدون هیچ ردیابی جزئیات (BPMN Manual Task — مثل «تماس تلفنی بگیر») | — | تیک تکمیل | — | pending→completed | — | — | — | فقط تکمیل |

## قاعده‌ی طراحی مهم: Approval یک Node مجزا از Task است

طبق یافته‌ی Research (Pega: «Approve/Reject به‌عنوان Step Type آماده، نه منطق دستی»؛ ServiceNow: Approval به‌عنوان Action-Category مجزا)، **Approval نباید صرفاً یک Task با یک Checkbox باشد** — باید از ابتدا Node مستقل با مفاهیم Multi-level/Parallel/Threshold باشد، چون این دقیقاً پرتکرارترین Pattern در کل Research بود (نگاه کنید [۰۶-patterns](06-process-patterns.md)).

---
**اسناد مرتبط:** [۰۶-Process Patterns](06-process-patterns.md) · [۰۸-Engine Architecture](08-process-engine-architecture.md) · [۱۴-Rule Engine](14-rule-engine.md)
