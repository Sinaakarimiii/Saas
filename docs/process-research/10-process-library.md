# ۱۰ — Process Library

## ساختار Library

```
Process Library
├── Human Capital (HR)
├── Financial Resources (Finance)
├── Supply Chain & Procurement
├── Information Technology
├── Marketing & Sales
├── Customer Service
├── Risk, Compliance & Resiliency (Legal/Compliance/Quality/Security)
├── Asset Management (Facilities/Maintenance)
├── Business Capabilities (Document/Knowledge Management, Project Management, Administration)
├── Vision & Strategy
├── Product & Service Development
├── Service Delivery
├── External Relationships
└── Industry-Specific (زیرمجموعه‌ی اختیاری هر Domain، فیلترشده با `process_industries`)
```

این ساختار مستقیماً از ۱۳ Category تأییدشده‌ی APQC می‌آید (نگاه کنید [۰۴](04-domain-taxonomy.md))، نه یک دسته‌بندی اختراعی — انتخابی که ریسک «Duplicate کردن یک استاندارد جا‌افتاده» را حذف می‌کند.

## Metadata هر Process Template (طبق درخواست دقیق کاربر)

هر ردیف `processes.json` این فیلدها را دارد (نگاه کنید [۰۹-data-model](09-data-model.md) برای Schema کامل): `id/slug`، `canonical_name_en/fa`، `description`، `domain_id`، `function_id`، `process_type_id` (طبق [۰۵](05-process-taxonomy.md))، `parent_process_id`، `complexity`، `status`، `version`، `source_confidence`، `source_reference`، به‌علاوه `process_synonyms` و `process_tags` به‌صورت جدول‌های چندبه‌چند مرتبط. «Required Roles/Forms/Documents/SLA» — که کاربر در Metadata خواسته بود — **عمداً روی خودِ `processes` ذخیره نشدند**؛ چون این‌ها به ازای هر Workflow Template (پیاده‌سازی) می‌توانند فرق کنند (نگاه کنید تفاوت Process/Workflow در [۰۲](02-process-concepts.md)) — به‌جایش در سطح `workflow_templates`/نمونه‌های کامل Seed (`sample-full-processes.json`) نگه داشته می‌شوند.

## ۲۰ نمونه‌ی کاملاً بازشده

طبق درخواست صریح کاربر، ۲۰ Process به‌طور کامل (Trigger/Actors/Steps/Forms/Rules/SLA) در `data/process-library/sample-full-processes.json` آماده شدند. فهرست نهایی (با یک جایگزینی آگاهانه نسبت به لیست پیشنهادی اولیه‌ی کاربر — نگاه کنید یادداشت پایین):

Leave Request · Purchase Requisition · Employee Onboarding · Employee Offboarding · Recruitment · Expense Reimbursement · Training Request · Incident Management · Change Management · IT Access Request · IT Asset Request · Service Request Fulfillment · Vendor Onboarding · Invoice Approval · Contract Review (Legal) · Audit Finding Remediation · Maintenance/Repair Request · Document Approval Cycle · Refund/Return Request · Customer Complaint Handling

**یادداشت شفافیت:** لیست پیشنهادی کاربر شامل «Project Change Request» بود. Research نشان داد Domain «Project Management» در منابع Vendor واقعی (ServiceNow/Salesforce/SAP/...) به‌اندازه‌ی کافی مستند نبود تا یک نمونه‌ی معتبر و غیرحدسی ساخته شود (نگاه کنید [۱۶-gap-analysis](16-gap-analysis.md)) — به‌جایش «Employee Offboarding» (که منبع معتبر Vendor دارد) جایگزین شد تا طبق قانون صریح کاربر («بین Fact و حدس تفاوت بگذار») چیزی حدسی وارد Seed Data نشود.

## Reusability (پاسخ به بخش دوازدهم — «Manager Approval به‌عنوان Subprocess در چند Process»)

طبق [۰۸-engine-architecture](08-process-engine-architecture.md)، الگوی فنی این کار `is_callable_only=true` + Input/Output Contract است. در سطح Library، این یعنی:

```
workflow_templates
  ├── manager-approval (is_callable_only=true)   ← یک‌بار تعریف
  ├── leave-request         → Node "Subprocess" → ارجاع به manager-approval
  ├── purchase-requisition  → Node "Subprocess" → ارجاع به manager-approval
  ├── expense-reimbursement → Node "Subprocess" → ارجاع به manager-approval
  └── recruitment-requisition-to-hire → Node "Subprocess" → ارجاع به manager-approval
```

در `sample-full-processes.json` این چهار Process فعلاً Approval را Inline (نه به‌صورت Subprocess ارجاع‌شده) نشان می‌دهند — این یک تصمیم آگاهانه برای خوانایی Seed Data است؛ در پیاده‌سازی واقعی Builder، این چهار Approval باید به یک `manager-approval` Template مشترک تبدیل شوند (این خودش اولین Refactor پیشنهادی هنگام ساخت Builder واقعی است، نه یک اشتباه در Seed).

## چگونه فایل‌های JSON به هم وصل می‌شوند

```
industries.json ──┐
domains.json ──────┼──< processes.json >── process-types.json
                    │        │
                    │        └──< sample-full-processes.json (نمونه‌ی کامل، ۲۰ مورد)
                    │                 │
                    │                 ├──< forms.json (ارجاع با slug)
                    │                 ├──< documents.json (ارجاع با slug)
                    │                 ├──< roles.json (ارجاع با slug)
                    │                 ├──< slas.json (ارجاع با slug)
                    │                 └──< workflow-nodes.json (هر step.node_type)
                    │
workflow-patterns.json ── هرکدام ترکیبی از workflow-nodes.json
process-steps.json ── لایه‌ی میانی بین Pattern و Node (نگاه کنید [۰۹](09-data-model.md))
```

---
**اسناد مرتبط:** [۰۵-Process Taxonomy](05-process-taxonomy.md) · [۰۸-Engine Architecture](08-process-engine-architecture.md) · [۱۶-Gap Analysis](16-gap-analysis.md)
