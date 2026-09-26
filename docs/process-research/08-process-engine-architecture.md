# ۰۸ — معماری پیشنهادی Process Engine

## معماری لایه‌ای اصلی

پیشنهاد اولیه‌ی کاربر (`Process Definition → Workflow Definition → Workflow Version → Workflow Instance → Work Items → Tasks/Approvals/Forms/Events → Completion/Escalation/Exception`) بعد از Research **تأیید می‌شود، با یک اصلاح مهم**: بر اساس بررسی مستقیم Camunda 7/8، Temporal، و AWS Step Functions (سند [۱۵-versioning](15-versioning.md))، هر سه موتور واقعی **«Definition» و «Version» را عملاً یک خانواده از رکوردها می‌دانند** (هر Version یک Snapshot غیرقابل‌تغییر از همان Definition است)، نه دو لایه‌ی مجزا در توالی عمودی. پس معماری اصلاح‌شده:

```
Process (Taxonomy — از APQC/Library، بدون گراف اجرایی)
        │  ۰..N پیاده‌سازی
        ▼
Workflow Template  (شناسه‌ی پایدار، معادل bpmnProcessId در Camunda 8)
        │  هر انتشار یک نسخه‌ی غیرقابل‌تغییر می‌سازد
        ▼
Workflow Version   (Snapshot گراف Node/Edge، شماره‌ی صحیح صعودی — این خودِ "Definition" اجراشدنی است)
        │  هر شروع، دقیقاً به یک نسخه‌ی مشخص گره می‌خورد (نه به Template)
        ▼
Workflow Instance  (یک اجرای واقعی و زمان‌دار، وضعیت + متغیرها)
        │  هر Node اجراشونده یک یا چند مورد زیر تولید می‌کند
        ▼
Work Items         (Task / Approval / Form / Event / Automation — واحد قابل‌تخصیص یا رویداد)
        │
        ▼
Completion  یا  Escalation  یا  Exception   (خروج از Work Item، نه لزوماً خروج از Instance)
        │
        ▼
Instance Completion (Success) | Instance Terminated (Cancelled/Failed)
```

**چرا این اصلاح مهم است:** اگر «Workflow Definition» و «Workflow Version» دو جدول جدا با رابطه‌ی یک‌به‌چند باشند، تغییر می‌کند به دو جدول با معنای تقریباً یکسان و ریسک ناهم‌گامی. مدل صحیح (که هر سه موتور بررسی‌شده استفاده می‌کنند): `workflow_templates` فقط شناسه‌ی پایدار + Metadata نگه می‌دارد؛ خودِ گراف در `workflow_versions` است و هرگز In-place ویرایش نمی‌شود — نسخه‌ی جدید یعنی ردیف جدید.

## چرا نه Definition-محور صرف (BPMN) و نه Code-محور صرف (Temporal)

Research دو الگوی رقیب پیدا کرد:
- **BPMN/Camunda (Graph-defined)**: گراف Node/Edge داده‌محور، مناسب برای کاربر غیرتوسعه‌دهنده که با Builder بصری کار می‌کند.
- **Temporal (Code-defined)**: Workflow = کد، اجرا = Durable Execution با Replay قطعی؛ برای این نوع پروژه نامناسب چون **کاربر نهایی محصول ما مدیر سازمان است، نه توسعه‌دهنده** — نمی‌تواند کد بنویسد.

**تصمیم**: معماری Graph-defined (شبیه BPMN/Camunda) پایه قرار می‌گیرد، چون تنها الگویی است که یک Builder بصری/غیرکدنویسی روی آن قابل‌ساخت است — دقیقاً همان دلیلی که n8n، Power Automate، ServiceNow Flow Designer و Zapier (همه در دسته‌ی ابزار کاربر-نهایی) هم از الگوی Node/Edge استفاده می‌کنند نه الگوی کد.

## مرز Template در برابر Runtime

| لایه | شامل چه چیزی؟ | تغییرپذیر؟ |
|---|---|---|
| **Template** (`workflow_templates` + `workflow_versions`) | گراف Node/Edge، Formهای متصل، Ruleهای ارجاع‌شده، SLA پیش‌فرض، نقش‌های Assignment | فقط با انتشار نسخه‌ی جدید؛ نسخه‌ی منتشرشده هرگز In-place ویرایش نمی‌شود (طبق الگوی هر سه موتور بررسی‌شده) |
| **Runtime** (`workflow_instances` + `work_items` + `process_variables`) | وضعیت واقعی، مقادیر واقعی متغیرها، Actor واقعی هر Work Item، Timestampها | دائماً در حال تغییر تا لحظه‌ی Completion |

قانون طلایی (مستخرج از هر سه موتور بررسی‌شده): **یک Instance که قبلاً شروع شده، به نسخه‌ای که با آن شروع شده «سنجاق (Pin)» می‌ماند** و با انتشار نسخه‌ی جدید خودکار منتقل نمی‌شود؛ انتقال (Migration) همیشه یک عملیات صریح و جداگانه است (جزئیات در [۱۵-versioning](15-versioning.md)).

## Reusable Sub-process (پاسخ به الزام «Manager Approval قابل‌استفاده در چند Process»)

دو الگوی متفاوت و هر دو معتبر پیدا شد (نگاه کنید به Research BPMN):

1. **BPMN Call Activity (الگوی Camunda)**: فراخوانی یک Process **کاملاً مستقل** که به‌تنهایی هم قابل‌اجراست، اما Process دیگری هم می‌تواند آن را صدا بزند. Parent در محل Call Activity **مسدود (Block)** می‌شود تا Child کامل شود؛ داده با `in`/`out` Mapping (نگاشت متغیر به متغیر) رد و بدل می‌شود، پیش‌فرض: هم‌نام بدون Mapping صریح منتقل می‌شود.
2. **ServiceNow Subflow (الگوی Function-like)**: یک واحد **فقط-قابل‌فراخوانی** که خودش هیچ Trigger مستقلی ندارد — دقیقاً مثل یک تابع: Inputهای Typed می‌گیرد، Outputهای Typed برمی‌گرداند.

**تصمیم برای این محصول**: هر دو الگو را با یک Flag پشتیبانی کنید: `workflow_templates.is_callable_only boolean`. اگر `true`، این Template در لیست «شروع مستقل» به کاربر نشان داده نمی‌شود و فقط به‌عنوان یک Node از نوع `Subprocess`/`Call Process` در Templateهای دیگر قابل‌ارجاع است. «Manager Approval» به‌طور طبیعی `is_callable_only = true` خواهد بود؛ اما مثلاً «Purchase Request» که هم مستقل هم به‌عنوان زیرفرایند در «Vendor Onboarding» قابل‌فراخوانی است، `false` می‌ماند — این دقیقاً همان انعطاف BPMN Call Activity است.

Input/Output هر Sub-process با یک Contract صریح تعریف می‌شود (شبیه ServiceNow، نه Mapping آزاد Camunda، چون برای کاربر غیرفنی خواناتر است):
```json
{
  "subprocess_template_id": "manager-approval-v3",
  "inputs": [
    { "variable": "requester_id", "type": "uuid", "required": true },
    { "variable": "amount", "type": "number", "required": false },
    { "variable": "request_type", "type": "string", "required": true }
  ],
  "outputs": [
    { "variable": "decision", "type": "enum[approved,rejected]" },
    { "variable": "decision_note", "type": "string" },
    { "variable": "decided_by", "type": "uuid" }
  ]
}
```

## چرخه‌ی کامل یک اجرا

```
[Trigger رخ می‌دهد: کاربر Form می‌فرستد | Event | Schedule]
        │
        ▼
[Workflow Instance ساخته می‌شود، روی آخرین نسخه‌ی منتشرشده‌ی Template پین می‌شود]
        │
        ▼
┌─── حلقه‌ی اجرای گراف (تا رسیدن به End Node) ───┐
│  Node فعلی اجرا می‌شود:                         │
│    • Automation → بی‌درنگ                       │
│    • Human (Task/Approval/Form) → Work Item ساخته می‌شود، SLA شروع │
│    • Decision/Condition → Rule Engine صدا زده می‌شود، بدون Work Item │
│    • Gateway → مسیر بعدی طبق شرط/موازی تعیین می‌شود │
│  اگر Exception/SLA Breach → Escalation یا مسیر Exception │
└──────────────────────────────────────────────┘
        │
        ▼
[End Node → Instance = Completed | Terminated]
        │
        ▼
[رویدادهای پایانی: Notification، Audit Log، به‌روزرسانی KPI]
```

## Universal Process Core (هسته‌ی مشترک همه‌ی فرایندها)

بعد از بررسی همه‌ی ۲۰ فرایند کامل در `data/process-library/sample-full-processes.json` و همه‌ی الگوهای [۰۶](06-process-patterns.md)، این عناصر در **تقریباً همه‌ی Processها** (بدون استثنای معنادار) تکرار شدند:

| عنصر | چرا Universal است |
|---|---|
| Request | هر Instance با یک درخواست/Trigger شروع می‌شود |
| Form | هر Request داده‌ی ساختاریافته جمع می‌کند |
| Task | واحد پایه‌ی کار انسانی، در همه‌ی ۲۰ نمونه حضور دارد |
| Assignment | هر Work Item به کسی باید برسد |
| Approval | در ۱۶ از ۲۰ نمونه‌ی کامل مستقیماً حاضر است |
| Decision | حتی وقتی پنهان است (مثل Threshold Routing)، در اکثر نمونه‌ها هست |
| Notification | هر نمونه حداقل یک Notify دارد |
| SLA | در ۱۴ از ۲۰ نمونه صریحاً تعریف شده |
| Escalation | زیرمجموعه‌ی طبیعی SLA، در نمونه‌های Human-in-the-loop تکرار می‌شود |
| Document | حداقل نصف نمونه‌ها یک سند تولید/مصرف می‌کنند |
| Comment | در هیچ نمونه‌ای صریحاً مدل نشد اما در تمام Approval/Review Nodeها به‌عنوان بخشی از `result` ضمنی حاضر است — باید صریح شود (نگاه کنید [۱۷](17-product-recommendations.md) بخش MVP) |
| Attachment | فایل ضمیمه در فرم‌های Expense/Ticket/Audit تکرار شد |
| Audit Log | زیرساخت موجود پروژه (`audit_log`) از قبل این نقش را دارد — باید Workflow Engine هم به همان جدول بنویسد، نه جدول جدا |
| Status | هر Work Item و هر Instance یک وضعیت دارد |
| History | نتیجه‌ی طبیعی Audit Log + Version + Assignment History |

**نتیجه:** این ۱۵ عنصر باید **هسته‌ی غیرقابل‌حذف Process Engine** باشند — یعنی هر Node/Pattern جدیدی که در آینده اضافه می‌شود باید از این هسته استفاده کند، نه اینکه دوباره Request/Task/Notification از صفر بسازد. این دقیقاً پاسخ به سؤال «چه چیزی نباید Hard-code شود» در Executive Summary ([۰۱](01-executive-summary.md)) است: خودِ این ۱۵ عنصر ثابت‌اند (Core)، اما محتوای هرکدام (کدام Form، کدام SLA، کدام Approver) کاملاً Configuration-driven است.

---
**اسناد مرتبط:** [۰۷-Node Catalog](07-workflow-node-catalog.md) · [۰۹-Data Model](09-data-model.md) · [۱۵-Versioning](15-versioning.md) · [۱۷-Product Recommendations](17-product-recommendations.md)
