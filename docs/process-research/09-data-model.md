# ۰۹ — Data Model پیشنهادی

این سند خروجی بخش هشتم و نوزدهم درخواست کاربر است: طراحی مفهومی کامل موجودیت‌ها، نه SQL اجراشدنی (طبق قانون «هیچ Migration اجرا نشود»). Enumها/روابط/Index دقیق برای هر Entity آمده تا تیم توسعه بتواند مستقیماً از روی این سند Migration بنویسد.

## فهرست کامل Entityها (بازنگری‌شده نسبت به لیست اولیه‌ی کاربر)

لیست اولیه‌ی ۳۵ Entity کاربر پایه‌ی خوبی بود؛ بعد از Research چند اصلاح اعمال شد:
- **`workflow_nodes`/`workflow_edges` به‌عنوان جدول جدا حذف شدند** — طبق الگوی هر چهار موتور بررسی‌شده (Camunda/Zeebe/Step Functions/n8n)، گراف به‌صورت یک ساختار JSON منسجم داخل `workflow_versions.graph` نگه‌داری می‌شود، نه به‌صورت ردیف‌های نرمال‌شده در دو جدول — نرمال‌سازی گراف هزینه‌ی Join بالا برای سودی که در این مقیاس (چند صد Node در هر Template) وجود ندارد ایجاد می‌کند. `workflow_nodes` به‌عنوان **Catalog از انواع Node قابل‌استفاده** (نه نمونه‌ی واقعی هر Node) باقی می‌ماند — نگاه کنید به [۰۷](07-workflow-node-catalog.md).
- **`workflow_templates`/`workflow_versions` طبق [۱۵-versioning](15-versioning.md) به‌صورت سه‌جدولی (Template/Version/Instance) اصلاح شد.**
- **`business_rules` اضافه شد** (بخش کاربر آن را زیر Rule Engine در بخش ۱۴ خواسته بود ولی در لیست ۳۵تایی نبود) — طبق الگوی DMN، یک Entity مستقل و نسخه‌بندی‌شده.
- **`schedules`/`escalation_rules` اضافه شدند** (طبق الگوی ServiceNow/Zendesk در [۱۲-sla](12-sla-and-escalation.md) — تقویم کاری باید از خود SLA جدا باشد).
- **`process_synonyms`** اضافه شد (طبق الزام صریح کاربر در بخش ۲۶ برای مدیریت Synonym).

## نمودار روابط سطح‌بالا

```
industries ──┐
             ├──< processes >── process_types
domains ─────┤        │
functions ───┘        ├──< process_synonyms
                       ├──< process_tags
                       ├──1:0..N─< workflow_templates ──1:N─< workflow_versions ──1:N─< workflow_instances
                       │                                            │                        │
                       │                                            ├──< form_bindings        ├──< work_items ──< assignments
                       │                                            └──< rule_bindings         ├──< process_variables
                       │                                                                        └──< escalations
form_templates ──1:N── form_versions ──< form_fields
business_rules ──1:N── business_rule_versions ──< business_rule_conditions
roles ──< role_permissions (پروژه‌ی موجود)          departments (per-org)
slas ──< sla_targets            schedules ──< schedule_periods, schedule_holidays
documents, process_documents, process_kpis, process_metrics
```

## گروه ۱ — Taxonomy (طبقه‌بندی، بدون گراف اجرا)

### `industries`
| ستون | نوع | توضیح |
|---|---|---|
| id | uuid PK | |
| slug | text UNIQUE | مثل `healthcare`, `saas` |
| name_en | text NOT NULL | |
| name_fa | text NOT NULL | |
| category | enum(`cross_industry`,`industry_specific`) | |
| apqc_variant_available | boolean DEFAULT false | آیا APQC نسخه‌ی صنعتی مستقل دارد (نگاه کنید به [۰۳](03-industry-taxonomy.md)) |
| parent_industry_id | uuid FK→industries NULL | برای زیرصنعت‌ها (مثلاً Property &amp; Casualty Insurance زیر Insurance) |

### `domains`
| ستون | نوع | توضیح |
|---|---|---|
| id | uuid PK | |
| slug | text UNIQUE | |
| name_en / name_fa | text NOT NULL | |
| apqc_category_code | text NULL | مثل `9.0` — ارجاع غیرالزامی به APQC Category |
| is_cross_functional | boolean | آیا این Domain معمولاً چند Department را قطع می‌کند |

### `functions`
| ستون | نوع | توضیح |
|---|---|---|
| id | uuid PK | |
| domain_id | uuid FK→domains NOT NULL | |
| slug, name_en, name_fa | | |
| apqc_process_group_code | text NULL | مثل `9.1` |
INDEX (`domain_id`)

### `process_types`
| ستون | نوع | توضیح |
|---|---|---|
| id | uuid PK | |
| slug | text UNIQUE | `approval`, `incident`, `onboarding`, … (نگاه کنید به [۰۵](05-process-taxonomy.md)) |
| name_en, name_fa | | |
| description | text | |

### `processes` (هسته‌ی Process Catalog — Taxonomy، نه اجرا)
| ستون | نوع | توضیح |
|---|---|---|
| id | uuid PK | |
| slug | text UNIQUE | `purchase-requisition` |
| canonical_name_en | text NOT NULL | |
| canonical_name_fa | text NOT NULL | |
| description_en, description_fa | text | |
| domain_id | uuid FK→domains NOT NULL | |
| function_id | uuid FK→functions NULL | |
| process_type_id | uuid FK→process_types NOT NULL | |
| parent_process_id | uuid FK→processes NULL | برای Sub-process (خودارجاع) |
| apqc_process_code | text NULL | مثل `9.1.1` |
| trigger_type | enum(`manual`,`scheduled`,`event`,`api`) | |
| complexity | enum(`simple`,`moderate`,`complex`) | |
| status | enum(`draft`,`active`,`deprecated`) | |
| version | integer DEFAULT 1 | نسخه‌ی خودِ تعریف Taxonomy (نه Workflow — این دو مستقل‌اند) |
| source_confidence | enum(`high`,`medium`,`low`) | طبق قانون کاربر: بین Fact/Practice/Recommendation تفکیک قائل شو |
| source_reference | text NULL | لینک/نام منبعی که این Process از آن استخراج شده |
INDEX (`domain_id`), (`process_type_id`), (`parent_process_id`) · UNIQUE(`slug`)

### `process_synonyms`
| id PK | process_id FK→processes | synonym_en text | synonym_fa text NULL | source text NULL |
UNIQUE(`process_id`,`synonym_en`)

### `process_tags` / تگ چندبه‌چند
`process_tags(id, slug, name_en, name_fa)` + `process_tag_links(process_id FK, tag_id FK)` — PK مرکب `(process_id, tag_id)`

### `process_industries` (چندبه‌چند: یک Process می‌تواند در چند صنعت کاربرد داشته باشد)
`process_industries(process_id FK, industry_id FK, relevance enum(core,common,rare))` — PK مرکب

## گروه ۲ — Workflow Engine (اجرا)

نگاه کنید به [۱۵-versioning](15-versioning.md) برای `workflow_templates`/`workflow_versions`/`workflow_instances` کامل. فیلد کلیدی `workflow_versions.graph` (jsonb) ساختارش:
```json
{
  "nodes": [{ "id": "n1", "type": "approval", "config": {...}, "position": {...} }],
  "edges": [{ "id": "e1", "from": "n1", "to": "n2", "condition": null }]
}
```

### `work_items`
| ستون | نوع |
|---|---|
| id | uuid PK |
| instance_id | uuid FK→workflow_instances NOT NULL |
| node_id | text NOT NULL — ارجاع به `id` داخل `graph.nodes`، نه FK پایگاه‌داده‌ای |
| type | enum(`task`,`approval`,`form`,`event_wait`) |
| status | enum(`pending`,`in_progress`,`completed`,`skipped`,`cancelled`,`escalated`) |
| assigned_to_user_id | uuid FK NULL |
| assigned_to_role_id | uuid FK NULL |
| assigned_to_queue text NULL |
| due_at | timestamptz NULL |
| completed_at | timestamptz NULL |
| result | jsonb NULL — خروجی (تصمیم Approval، داده‌ی Form) |
INDEX (`instance_id`), (`assigned_to_user_id`,`status`), (`due_at`) — این آخری برای اسکن SLA حیاتی است

### `process_variables`
`id PK, instance_id FK, key text, value jsonb, updated_at` — UNIQUE(`instance_id`,`key`)

### `assignments` (تاریخچه‌ی تخصیص/Reassign/Delegate — جدا از وضعیت فعلی روی work_item)
`id PK, work_item_id FK, assigned_to_user_id FK, assigned_by_user_id FK, reason enum(initial,reassign,delegate,escalate,round_robin), created_at`

## گروه ۳ — Forms

### `form_templates` / `form_versions` / `form_fields`
همان الگوی پروژه‌ی فعلی (`form_templates`→`form_fields`) با یک تغییر: بین Template و Field یک لایه‌ی `form_versions` اضافه می‌شود تا طبق [۱۵-versioning](15-versioning.md) نسخه‌بندی مستقل داشته باشد. `form_fields.form_version_id` (نه مستقیم `form_template_id`).

## گروه ۴ — Rules (نگاه کنید به [۱۴-rule-engine](14-rule-engine.md) برای جزئیات)

### `business_rules` / `business_rule_versions`
`business_rule_versions.hit_policy enum(unique,any,priority,first,rule_order,output_order,collect_sum,collect_min,collect_max,collect_count)` — طبق DMN تأییدشده در Research
### `business_rule_conditions` (ردیف‌های Decision Table)
`id, rule_version_id FK, row_order int, input_conditions jsonb, output_values jsonb`

## گروه ۵ — Roles / Assignment (نگاه کنید به [۱۳](13-role-assignment-model.md))

`roles`, `departments` از پروژه‌ی موجود استفاده می‌شوند (`org_members`, `roles`, `role_permissions` از قبل وجود دارند — این سند آن‌ها را بازتعریف نمی‌کند، فقط Work Item Assignment را به آن‌ها وصل می‌کند).

## گروه ۶ — SLA (نگاه کنید به [۱۲](12-sla-and-escalation.md))

`slas`, `sla_targets`, `schedules`, `schedule_periods`, `schedule_holidays`, `escalation_rules`, `escalation_levels`

## گروه ۷ — Document / KPI / Metric

`documents(id, slug, name_en, name_fa, category)`, `process_documents(process_id FK, document_id FK, is_required boolean)`, `process_kpis(id, process_id FK, name_en, name_fa, unit, target_value numeric NULL)`, `process_metrics` (سطح گزارش‌گیری Runtime — خارج از scope این Research، فقط جای رزرو‌شده)

---

## استانداردهای Naming (پاسخ به بخش ۲۴)

| مورد | قاعده‌ی انسانی (نمایش) | قاعده‌ی Machine-readable (شناسه) | مثال |
|---|---|---|---|
| Process | Title Case، فعل+مفعول | `kebab-case`، انگلیسی، فعل مصدری اول | نمایش: «Purchase Requisition» / شناسه: `purchase-requisition` |
| Workflow Template | نام Process + توضیح تمایز اختیاری | `{process-slug}` یا `{process-slug}--{variant}` | `purchase-requisition--high-value` |
| Workflow Version | — | عدد صحیح صعودی، همیشه کنار Template ID | `purchase-requisition v3` |
| Node (در گراف) | برچسب آزاد کاربر | `n{شمارنده}` یا UUID کوتاه، یکتا فقط در محدوده‌ی همان گراف | `n7` |
| Variable | camelCase در نمایش فنی، برچسب فارسی برای کاربر | `snake_case`، بدون فاصله، پیشوند دامنه اختیاری برای تداخل‌زدایی | `requester_manager_id` |
| Form | نام Form Template | `kebab-case` | `expense-claim-form` |
| Rule/Decision | نام تصمیم، نه شرط | `kebab-case`، پسوند نسخه در URL نه در نام | `approval-threshold-by-amount` |
| Event | فعل گذشته (چیزی که رخ داده) | `PascalCase.PastTense` (سبک Domain Event) | `LeaveRequestApproved` |
| Action (اقدام خودکار) | فعل امری | `snake_case`، فعل امری | `send_notification`, `create_task` |
| Status | صفت/حالت کوتاه | `snake_case`، از یک واژه‌نامه‌ی ثابت در سطح کل محصول (نگاه کنید به Universal Core در [۱۷](17-product-recommendations.md)) | `pending_approval`, `in_progress` |
| Role | اسم شغلی/مسئولیت، نه شخص | `kebab-case` | `department-head`, `process-owner` |

**قاعده‌ی سراسری:** انگلیسی همیشه Canonical Identifier است (طبق بخش ۲۷ کاربر)؛ فارسی فقط برای `name_fa`/`description_fa`، هرگز در `slug`/`id`/نام کد. این یعنی جابه‌جایی زبان نمایش هرگز شناسه‌ی پایگاه‌داده را نمی‌شکند.

---
**اسناد مرتبط:** [۰۷-Node Catalog](07-workflow-node-catalog.md) · [۱۲-SLA](12-sla-and-escalation.md) · [۱۴-Rule Engine](14-rule-engine.md) · [۱۵-Versioning](15-versioning.md)
