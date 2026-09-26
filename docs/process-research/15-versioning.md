# ۱۵ — مدل Versioning (Template در برابر Instance)

## یافته‌ی مرکزی Research

سه موتور واقعی (Camunda 7، Camunda 8/Zeebe، AWS Step Functions) و یک موتور Code-محور (Temporal) بررسی شدند. با وجود تفاوت در پیاده‌سازی، **الگوی رفتاری هر چهار مورد یکسان است**:

> نسخه‌ی جدید = رکورد جدید و غیرقابل‌تغییر. Instanceهای در حال اجرا روی نسخه‌ای که با آن شروع شده‌اند «سنجاق» می‌مانند. انتقال به نسخه‌ی جدید هرگز خودکار نیست — همیشه یک عملیات صریح و جداگانه با نگاشت عنصر-به-عنصر است.

| موتور | چگونه Version تعریف می‌شود | رفتار پیش‌فرض Instance موجود هنگام انتشار نسخه‌ی جدید | مکانیزم Migration |
|---|---|---|---|
| Camunda 7 | Deploy مجدد همان process key → شماره‌ی نسخه خودکار +۱ | بدون تغییر؛ instance جدید همیشه روی آخرین نسخه شروع می‌شود | `RuntimeService` + Migration Plan (نگاشت Activity ID مبدأ → مقصد، فقط هم‌نوع) |
| Camunda 8 / Zeebe | Deploy → `version` عدد صحیح، خودکار توسط موتور تخصیص | بدون تغییر؛ `processDefinitionKey`/`version` instance ثابت می‌ماند | Process Instance Migration — Migration Plan با «Mapping Instructions» عنصر-به-عنصر؛ متغیرهای全局 منتقل می‌شوند |
| AWS Step Functions | `UpdateStateMachine` تعریف را جای‌گزین می‌کند؛ با `publish=true` یک **Version** غیرقابل‌تغییر و شماره‌گذاری‌شده می‌سازد | Executionهای در حال اجرا با نسخه‌ی قدیم تمام می‌شوند؛ Executionهای جدید (چند ثانیه بعد) نسخه‌ی جدید می‌گیرند | **بدون** مفهوم Migration اصلاً — یک Execution همیشه با همان Snapshot تمام می‌شود؛ به‌جایش **Alias** (اشاره‌گر قابل‌جابه‌جایی بین حداکثر ۲ نسخه، برای Canary/Blue-Green) دارند |
| Temporal | بدون جدول Definition/Version؛ نسخه‌بندی از طریق **Worker Versioning** یا **Patching** (شاخه‌ی `if(patched)` در کد) | Executionهای در حال اجرا باید دقیقاً همان مسیر کد را Replay کنند؛ کد جدید فقط شاخه‌های جدید می‌گیرد | نسخه‌بندی درون‌کدی، نه سطح داده — مرجع مقایسه‌ای، نه الگوی مستقیم قابل‌کپی برای این محصول |

## مدل داده‌ی پیشنهادی (سه جدول، نه دو)

```
workflow_templates
  id (پایدار، هرگز عوض نمی‌شود)
  org_id
  process_id (FK → processes، پیوند به Taxonomy)
  slug, name_en, name_fa
  is_callable_only boolean
  current_published_version_id (FK → workflow_versions، nullable تا اولین انتشار)
  status: draft | active | deprecated | archived
  created_at, created_by

workflow_versions            -- خودِ Definition اجراشدنی؛ غیرقابل‌تغییر پس از انتشار
  id
  template_id (FK)
  version_number (صحیح، صعودی، منحصربه‌فرد در سطح template_id)
  graph jsonb                -- Nodeها/Edgeها، نگاه کنید به ۰۹-data-model
  form_bindings jsonb
  status: draft | published | deprecated
  published_at, published_by
  change_note

workflow_instances
  id
  workflow_version_id (FK — نه template_id؛ این خودِ «سنجاق‌شدن» است)
  org_id
  status: running | completed | terminated | migrated
  variables jsonb
  started_at, started_by, ended_at
```

**چرا `workflow_instances.workflow_version_id` و نه `template_id`:** اگر Instance به `template_id` وصل شود و گراف اجرا از «آخرین نسخه» خوانده شود، هر Instance در حال اجرا با هر انتشار جدید بی‌سروصدا رفتارش عوض می‌شود — دقیقاً نقطه‌ضعفی که هیچ‌کدام از چهار موتور بررسی‌شده اجازه‌اش نمی‌دهند. اتصال مستقیم به `workflow_versions.id` این خطا را از ریشه غیرممکن می‌کند.

## جدول اختیاری Migration (فاز بعدی، نه MVP)

```
workflow_instance_migrations
  id
  instance_id (FK)
  from_version_id (FK)
  to_version_id (FK)
  node_mapping jsonb   -- [{ "from_node_id": "...", "to_node_id": "..." }]
  migrated_at, migrated_by
```

طبق الگوی Camunda: نگاشت فقط بین Nodeهای **هم‌نوع** مجاز است (مثلاً Task→Task، نه Task→Gateway)؛ Instanceهایی که در لحظه‌ی Migration داخل یک Nodeی حذف‌شده در نسخه‌ی جدید هستند، باید صراحتاً رد یا به یک Node جایگزین نگاشت شوند — بدون نگاشت، Migration باید Reject شود، نه حدس زده شود.

## Form Versioning (پاسخ به سؤال صریح کاربر در بخش ۱۳)

همان اصل: `form_templates` → `form_versions` (نه ویرایش In-place). یک `workflow_versions.form_bindings` به `form_versions.id` مشخص ارجاع می‌دهد، نه به `form_templates.id`. یعنی اگر Form بعداً تغییر کند (فیلد اضافه/حذف شود)، نسخه‌ی منتشرشده‌ی Workflow که از قبل به نسخه‌ی قدیم Form پین شده، دست‌نخورده می‌ماند؛ برای استفاده از Form جدید، باید نسخه‌ی جدید Workflow هم منتشر شود — همان قانون طلایی، بدون استثنا برای Form.

## Rule/Decision Versioning

طبق الگوی DMN (سند [۱۴](14-rule-engine.md))، Decision Tableها هم خودشان نسخه‌بندی مستقل دارند (`business_rules` → نسخه‌های خودشان)؛ یک Business Rule Task در `workflow_versions.graph` می‌تواند به یک نسخه‌ی مشخص یا به «آخرین نسخه‌ی منتشرشده» ارجاع دهد (`bindingType: latest | version` — دقیقاً الگوی `zeebe:calledDecision` که در Research تأیید شد). Binding از نوع `latest` یعنی تغییر آستانه‌ی تأیید بدون نیاز به انتشار نسخه‌ی جدید Workflow اعمال می‌شود — این همان مزیت اصلی جداسازی Rule از Workflow است.

---
**اسناد مرتبط:** [۰۸-Engine Architecture](08-process-engine-architecture.md) · [۰۹-Data Model](09-data-model.md) · [۱۴-Rule Engine](14-rule-engine.md)
