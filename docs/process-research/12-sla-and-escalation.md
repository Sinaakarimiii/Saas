# ۱۲ — مدل SLA و Escalation

## یافته‌ی کلیدی: سه معماری متفاوت و معتبر برای Escalation

Research سه پیاده‌سازی واقعی و متفاوت پیدا کرد — این یعنی «یک استاندارد واحد» وجود ندارد و باید آگاهانه انتخاب کرد:

| رویکرد | پیاده‌سازی واقعی | مزیت | عیب |
|---|---|---|---|
| **الف) Escalation داخل خودِ تعریف SLA** | ServiceNow — Escalation به SLA/Workflow متصل است | یکجا قابل مدیریت با SLA | کمتر قابل‌استفاده‌ی مجدد بین چند SLA |
| **ب) Escalation به‌عنوان لایه‌ی Automation جدا، بر مبنای «ساعت تا/از نقض SLA»** | Zendesk — Trigger مستقیماً به Breach واکنش نمی‌دهد، فقط Automation زمان‌محور | قابل‌استفاده‌ی مجدد در چند SLA، مستقل تغییر می‌کند | یک لایه‌ی اضافه برای پیکربندی |
| **ج) Escalation به‌عنوان Timer+Event درون خودِ گراف Workflow** | BPMN/Camunda — Timer Boundary Event غیرقطع‌کننده + Escalation Throw/Catch | کاملاً قابل‌مشاهده در دیاگرام فرایند، منطق نزدیک محل استفاده | برای هر Workflow جدا تعریف می‌شود، کمتر Reusable در سطح سازمان |

**تصمیم برای این محصول:** ترکیب (ب) + (ج). `escalation_rules` به‌عنوان Entity مستقل و قابل‌استفاده‌ی مجدد در سطح Organization تعریف می‌شود (مثل رویکرد Zendesk)، اما هر `work_item` که SLA دارد، در گراف Workflow با یک `Timer`/`Escalation` Node (نگاه کنید [۰۷](07-workflow-node-catalog.md)) به همان Rule ارجاع می‌دهد (مثل رویکرد BPMN) — یعنی منطق Escalation یک‌بار تعریف و در چند Workflow ارجاع داده می‌شود، اما در دیاگرام هر Workflow قابل‌مشاهده است.

## مدل داده (تأییدشده از ServiceNow + Zendesk، هر دو Schedule را از SLA جدا می‌کنند)

```
schedules                    -- تقویم کاری، مستقل و Reusable
  id, org_id, name, timezone
schedule_periods              -- بازه‌ی ساعت کاری هر روز هفته
  id, schedule_id FK, weekday int(0-6), start_time, end_time
schedule_holidays             -- روزهای تعطیل تمام‌روز (بدون تعطیلی نیمه‌روز — طبق محدودیت مشاهده‌شده در Zendesk)
  id, schedule_id FK, date, name
  -- نکته‌ی مهم Integration: این جدول باید با ماژول تقویم/تعطیلات موجود پروژه (holidays.ts, calendar_events) یکی شود، نه موازی

slas                          -- تعریف/Template، نه نمونه‌ی اجراشده
  id, org_id, name_en, name_fa
  applies_to enum(work_item_type, process_id, …)   -- به چه چیزی وصل می‌شود
  schedule_id FK → schedules
  start_condition, pause_condition, stop_condition  -- عبارت شرطی (نه Hardcode)
sla_targets                   -- چند هدف روی یک SLA (شبیه Zendesk: چند متریک)
  id, sla_id FK, metric enum(first_response, resolution, …), duration_minutes, priority_level

-- نمونه‌ی Runtime (نه Template):
work_item_slas                -- اتصال SLA به یک work_item واقعی
  id, work_item_id FK, sla_id FK, target_id FK
  started_at, paused_at, resumed_at, due_at, breached_at, stopped_at

escalation_rules              -- Reusable، مستقل از یک SLA خاص
  id, org_id, name_en, name_fa, applies_to
escalation_levels
  id, escalation_rule_id FK, level int, trigger_after_minutes int (نسبت به due_at)
  action enum(notify, reassign, reassign_and_notify, change_priority)
  target_role_id FK NULL, target_user_id FK NULL
```

## چرا Pause/Resume یک شرط جدا از Stop است

طبق Research ServiceNow (`start_condition`/`pause_condition`/`stop_condition`/`reset_condition` هرکدام مستقل روی SLA Definition): یک درخواست می‌تواند «منتظر پاسخ مشتری» باشد بدون آنکه SLA لغو شود — ساعت متوقف می‌شود اما تاریخچه باقی می‌ماند. اگر Pause را با Stop قاطی کنیم، گزارش «چقدر واقعاً طول کشید» غیرقابل‌اعتماد می‌شود. Pause/Resume باید Timestamp جداگانه ثبت کند (`paused_at`, `resumed_at` می‌تواند چند بار تکرار شود — در MVP یک‌بار کافی است، برای Enterprise باید آرایه/جدول جدا شود).

## Business Hours در برابر Calendar Hours

هر `sla_targets.duration_minutes` باید مشخص کند نسبت به کدام محاسبه می‌شود:
- **Calendar hours** — زمان واقعی، بدون توجه به ساعت کاری/تعطیلات
- **Business hours** — فقط زمانی که داخل `schedule_periods` و خارج از `schedule_holidays` است

این تمایز مستقیماً از Zendesk گرفته شده (هر Target می‌تواند Business یا Calendar باشد، نه کل SLA یکجا).

## اتصال به ماژول تقویم/شیفت موجود پروژه (پاسخ صریح به بخش ۱۶ کاربر)

پروژه‌ی `org_platform` از قبل `holidays.ts`، `calendar_events`، و شیفت‌ها را دارد. **`schedules` نباید تقویم تعطیلات ایران را دوباره بسازد** — باید `schedule_holidays` را از همان منبع (`calendar_events`/`holidays.ts`) Sync یا مستقیماً Query کند. این دقیقاً یکی از موارد Cross-Module Integration که در [۱۱-integration-model](11-integration-model.md) به‌طور کامل توضیح داده شده.

---
**اسناد مرتبط:** [۰۷-Node Catalog](07-workflow-node-catalog.md) · [۰۹-Data Model](09-data-model.md) · [۱۱-Integration Model](11-integration-model.md)
