# ۰۱ — خلاصه‌ی مدیریتی (Executive Summary)

> این سند ورودی کل Research است اما **آخرین سندی است که نوشته شد** — چون فقط بعد از تکمیل بقیه می‌شد جمع‌بندی درست کرد. اگر برای اولین بار این پوشه را می‌خوانید، از همین‌جا شروع کنید.

## این Research چه چیزی تولید کرد

بر مبنای تحقیق چندمنبعی روی APQC PCF (با استخراج مستقیم از PDF رسمی، نه خلاصه‌ی ثانویه)، استاندارد BPMN/DMN، و بررسی معماری واقعی پنج پلتفرم صنعتی (Camunda، ServiceNow، Salesforce، Pega، Zendesk/AWS Step Functions/n8n)، این پوشه یک **Taxonomy کامل + Data Model + Process Library با ۵۱ فرایند واقعی (۲۰ نمونه‌ی کاملاً بازشده)** تولید کرد که مستقیماً قابل تبدیل به Migration، Seed Data، و طراحی Builder است — بدون آنکه تیم توسعه مجبور شود دوباره از صفر درباره‌ی ماهیت Processها تحقیق کند.

**هیچ کدی در پروژه تغییر نکرد.** فقط این پوشه (`docs/process-research/`) و `data/process-library/` ساخته شدند.

## پاسخ به ۱۰ سؤال کلیدی

**۱. یک Process Builder واقعاً Generic چه ویژگی‌هایی باید داشته باشد؟**
باید گراف Node/Edge باشد (نه Code-محور مثل Temporal) چون کاربر نهایی توسعه‌دهنده نیست؛ Approval باید Node مستقل با پشتیبانی Multi-level/Parallel باشد (نه یک Task ساده)؛ Rule Engine باید کاملاً از گراف جدا باشد (الگوی DMN)؛ و باید از ابتدا Template/Version/Instance را جدا نگه دارد (نگاه کنید [۰۸](08-process-engine-architecture.md)).

**۲. چه چیزهایی باید در Core Engine باشند؟**
دقیقاً ۱۵ عنصر «Universal Process Core» شناسایی‌شده در [۰۸](08-process-engine-architecture.md#universal-process-core-هسته‌ی-مشترک-همه‌ی-فرایندها): Request، Form، Task، Assignment، Approval، Decision، Notification، SLA، Escalation، Document، Comment، Attachment، Audit Log، Status، History.

**۳. چه چیزهایی نباید Hard-code شوند؟**
هر چیزی که در `data/process-library/*.json` به‌صورت Seed آمده — Domain، Process Type، Node Catalog، Assignment Method، Hit Policy — همه باید جدول Database باشند، نه Enum ثابت در کد Backend (نگاه کنید [۰۹-data-model](09-data-model.md)).

**۴. Process Library چگونه باید طراحی شود؟**
روی اسکلت ۱۳ Category تأییدشده‌ی APQC PCF، با یک لایه‌ی Process Type ثانویه (بر اساس رفتار، نه Domain) — نگاه کنید [۱۰-process-library](10-process-library.md).

**۵. چگونه می‌توان صدها/هزاران Process را بدون پیچیده‌شدن محصول مدیریت کرد؟**
با تفکیک صریح Taxonomy (طبقه‌بندی، ثابت و کم‌تغییر) از Workflow (اجرا، هرچقدر لازم است متنوع) — یک Process Taxonomy می‌تواند صدها Workflow Template مختلف در سازمان‌های مختلف داشته باشد بدون آنکه خودِ Taxonomy رشد کند (نگاه کنید تفاوت Process/Workflow در [۰۲](02-process-concepts.md)).

**۶. چه چیزهایی باید Template باشند؟**
`workflow_templates` + `workflow_versions` (گراف)، `form_versions`، `business_rule_versions` — همه‌ی این‌ها Snapshot غیرقابل‌تغییر بعد از انتشارند (نگاه کنید [۱۵-versioning](15-versioning.md)).

**۷. چه چیزهایی Runtime باشند؟**
`workflow_instances`، `work_items`، `process_variables` — همیشه در حال تغییر تا Completion.

**۸. چه چیزهایی باید Configurable باشند؟**
Assignment Rule، SLA Target، Escalation Level، Business Rule Threshold — همه از طریق Data، نه Deploy مجدد کد، قابل‌تغییر (نگاه کنید [۱۳](13-role-assignment-model.md), [۱۲](12-sla-and-escalation.md), [۱۴](14-rule-engine.md)).

**۹. چه چیزهایی باید Plugin/Integration باشند؟**
Webhook/API Call، اتصال به Calendar/Project/Task Manager/Notification (نگاه کنید [۱۱-integration-model](11-integration-model.md)) — این‌ها مرزهای محصول با دنیای بیرون/سایر ماژول‌ها هستند، باید Contract صریح داشته باشند نه اتصال مستقیم به جدول داخلی ماژول دیگر.

**۱۰. MVP چه بخش‌هایی را باید داشته باشد؟**
Template/Version پایه + Nodeهای Start/End/Task/Approval/Decision/Branch/Parallel/Merge + اتصال به Form Builder و Audit Log موجود پروژه — همه چیزهایی که روی زیرساخت فعلی `org_platform` بدون ریسک امنیتی جدید قابل‌ساخت است (نگاه کنید جدول کامل در [۱۷](17-product-recommendations.md)).

## یافته‌های کلیدی که مسیر تصمیم را عوض کردند

1. **APQC PCF واقعاً یک پایه‌ی اثبات‌شده است، نه یک انتخاب پرریسک** — SAP Signavio، MEGA، Interfacing، و حتی یک ابزار Workflow Automation (Workato) همین الگو را دنبال کرده‌اند (نگاه کنید [۰۳](03-industry-taxonomy.md)). این ریسک «کپی‌کردن بدون تحلیل» را که کاربر صریحاً نگرانش بود، رفع می‌کند — چون خودِ این Research نشان داد APQC فقط اسکلت طبقه‌بندی می‌دهد و مرز اجرا (Workflow) را عمداً خالی می‌گذارد؛ آن بخش کاملاً کار این محصول است.
2. **«Definition» و «Version» باید یک خانواده‌ی رکورد باشند، نه دو لایه‌ی جدا** — این برخلاف پیشنهاد اولیه‌ی خودِ کاربر بود اما با شواهد مستقیم از چهار موتور واقعی (Camunda 7/8، Step Functions، Temporal) اصلاح شد (نگاه کنید [۱۵](15-versioning.md)).
3. **`workflow_nodes`/`workflow_edges` نباید جدول SQL نرمال‌شده باشند** — هیچ موتور واقعی بررسی‌شده این کار را نمی‌کند؛ گراف باید JSON باشد (نگاه کنید [۰۹](09-data-model.md)).
4. **Escalation سه معماری رقیب معتبر دارد، نه یک استاندارد** — این محصول باید آگاهانه ترکیب دو مورد را انتخاب کند (نگاه کنید [۱۲](12-sla-and-escalation.md))، نه اینکه فرض کند یک «راه درست» وجود دارد.
5. **پروژه‌ی فعلی `org_platform` از قبل زیرساخت غیرمنتظره‌ای برای این هسته دارد** — `manager_id`، `audit_log` Append-only، Form Builder با ۷ نوع فیلد — یعنی Foundation واقعی MVP خیلی کمتر از صفر است (نگاه کنید [۱۷](17-product-recommendations.md) بخش پ).

## دیاگرام معماری نهایی پیشنهادی

```
                    ┌─────────────────────────┐
                    │   Process Taxonomy       │   (APQC-based: Industry/Domain/
                    │   (processes.json)        │    Function/Process/Type)
                    └────────────┬─────────────┘
                                 │ ۰..N پیاده‌سازی
                                 ▼
                    ┌─────────────────────────┐
                    │   Workflow Template       │   (شناسه‌ی پایدار)
                    └────────────┬─────────────┘
                                 │ هر انتشار
                                 ▼
                    ┌─────────────────────────┐
                    │   Workflow Version         │   (Snapshot غیرقابل‌تغییر: Graph،
                    │   (graph jsonb)            │    Form Binding، Rule Binding)
                    └────────────┬─────────────┘
                                 │ هر شروع، سنجاق به یک نسخه
                                 ▼
   ┌──────────┐     ┌─────────────────────────┐     ┌──────────────┐
   │  Rule     │◄────┤   Workflow Instance        │────►│  SLA/Escalation│
   │  Engine   │     │   (variables, status)       │     │  Engine        │
   └──────────┘     └────────────┬─────────────┘     └──────────────┘
                                 │ هر Node اجراشونده
                                 ▼
                    ┌─────────────────────────┐
                    │   Work Items                │──► Assignment Engine
                    │   (Task/Approval/Form/Event) │      (User/Role/Queue/Skill)
                    └────────────┬─────────────┘
                                 │
                 ┌───────────────┼───────────────┐
                 ▼               ▼               ▼
          Notification      Audit Log         سایر ماژول‌ها
          Engine             (موجود پروژه)      (Calendar/Ticket/Project/
                                                  Task Manager — نگاه کنید ۱۱)
```

## توصیه‌ی نهایی

شروع با MVP جدول [۱۷-product-recommendations](17-product-recommendations.md) بخش الف — روی زیرساخت `org_members`/`form_templates`/`audit_log` موجود پروژه، بدون لمس کد فعلی. اولین قدم واقعی پیاده‌سازی (بعد از تأیید این Research توسط شما) باید `workflow_templates`/`workflow_versions`/`workflow_instances`/`work_items` طبق [۰۹-data-model](09-data-model.md) و [۱۵-versioning](15-versioning.md) به‌عنوان Migration باشد — چون هر تصمیم دیگری (Node Catalog، Assignment، SLA) روی همین سه/چهار جدول سوار می‌شود.

---
**فهرست کامل اسناد:** [۰۲-Concepts](02-process-concepts.md) · [۰۳-Industry Taxonomy](03-industry-taxonomy.md) · [۰۴-Domain Taxonomy](04-domain-taxonomy.md) · [۰۵-Process Taxonomy](05-process-taxonomy.md) · [۰۶-Patterns](06-process-patterns.md) · [۰۷-Node Catalog](07-workflow-node-catalog.md) · [۰۸-Engine Architecture](08-process-engine-architecture.md) · [۰۹-Data Model](09-data-model.md) · [۱۰-Process Library](10-process-library.md) · [۱۱-Integration Model](11-integration-model.md) · [۱۲-SLA &amp; Escalation](12-sla-and-escalation.md) · [۱۳-Role &amp; Assignment](13-role-assignment-model.md) · [۱۴-Rule Engine](14-rule-engine.md) · [۱۵-Versioning](15-versioning.md) · [۱۶-Gap Analysis](16-gap-analysis.md) · [۱۷-Product Recommendations](17-product-recommendations.md)

**داده‌ی Seed:** `data/process-library/` — ۱۳ فایل JSON (industries، domains، process-types، processes، process-steps، workflow-patterns، workflow-nodes، roles، forms، documents، kpis، slas، sample-full-processes)
