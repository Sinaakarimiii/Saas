# ۱۳ — مدل Role و Assignment

## یافته‌ی کلیدی: Assignment معمولاً خاصیت Work Item است، نه یک Entity جدا — به‌جز دو استثنای مهم

طبق Research (مقایسه‌ی Camunda 8، ServiceNow، Pega، jBPM): در بیشتر موتورها Assignment یک Attribute روی خودِ Task است که هنگام فعال‌شدن Node محاسبه می‌شود (مثل `zeebe:AssignmentDefinition` روی User Task). **دو استثنای مهم که باید Entity مستقل باشند:**
1. **ServiceNow `sysrule_assignment`** — یک جدول قانون مستقل، جدا از Task، چون قوانین Assignment باید بدون لمس هر Workflow به‌صورت متمرکز قابل‌ویرایش باشند.
2. **Pega Operator Skill Ratings** — روی رکورد Operator زندگی می‌کند (نه روی Task)، چون یک مهارت باید در همه‌ی فرایندها یکسان باشد.

## روش‌های Assignment (همه‌ی موارد خواسته‌شده کاربر، تأییدشده از منابع واقعی)

| روش | تعریف | منبع تأیید |
|---|---|---|
| **Specific User** | Assignee = یک شناسه‌ی کاربر ثابت | Camunda 8 `assignee` (رشته یا FEEL Expression) |
| **Role** | هر عضو یک Role می‌تواند Claim کند (اولین نفر برنده) | Camunda 8 `candidateGroups` |
| **Department** | مثل Role، اما محدوده‌ی سازمانی به‌جای عملکردی | ترکیب Role + `org_members.department` |
| **Manager / Supervisor** | Assignee = مدیر مستقیم یک Actor مشخص (معمولاً Requester) | الگوی مدیریت سلسله‌مراتبی — Concur Management Chain Routing |
| **Requester** | Assignee = همان کسی که Instance را شروع کرده | استاندارد در همه‌ی الگوهای Rework/Resubmission |
| **Requester's Manager** | Expression پویا: مدیر مستقیم Requester | Camunda 8 FEEL Expression + پروژه‌ی موجود (`org_members.manager_id`) |
| **Process Owner** | نقشی که مالک تعریف یک Process Template است (نه لزوماً درگیر هر Instance) | Pega Case Type Owner |
| **Previous Assignee** | همان کسی که Node قبلی را انجام داده (برای زنجیره‌های پیوسته) | الگوی عمومی BPM |
| **Dynamic User** | نتیجه‌ی یک Rule/Expression در لحظه‌ی اجرا | Camunda 8 FEEL Expression روی `assignee` |
| **Team** | چند کاربر مشخص، همه Notify می‌شوند، یکی Claim می‌کند | Camunda `candidateUsers` |
| **Queue** | Work Item بدون Assignee اولیه در صف می‌ماند؛ اولین کارگر/کاربر آزاد Fetch-and-Lock می‌کند | Camunda 7 External Task Pattern (Fetch-and-Lock با Timestamp Lock ضدتداخل) |
| **Round Robin** | چرخشی بین اعضای یک گروه | ServiceNow «Round Robin Group» فیلد روی گروه |
| **Load Balancing** | بر اساس بار فعلی/در دسترس‌بودن Actor | ServiceNow Advanced Work Assignment (AWA) — «Most Majority»/«Last Assigned» + آگاهی از در‌دسترس‌بودن Agent |
| **Skill-Based** | بر اساس امتیاز مهارت (۱-۱۰) روی رکورد Actor | Pega `ToSkilledGroup` — انتخاب تصادفی از اعضای واجد حداقل امتیاز، Fallback به مدیر گروه اگر کسی Match نشود |

## Delegation (غیبت موقت — پاسخ صریح به نیاز کاربر)

دو الگوی متفاوت و هر دو معتبر:
- **الگوی Salesforce (Approval-محدود)**: یک فیلد `delegated_approver_id` روی User؛ Delegate می‌تواند تصمیم بگیرد اما **نمی‌تواند خودش دوباره Reassign کند** — جلوگیری از زنجیره‌ی بی‌پایان Delegation.
- **الگوی jBPM (Deadline-محور)**: اگر Task تا `reassignment_time` مشخص شروع/تمام نشود، خودکار به یک User/Group تعریف‌شده منتقل می‌شود.

**تصمیم محصول:** هر دو با هم پیاده‌سازی شوند: `delegations` (که از قبل در Schema پروژه با هدف دیگری وجود دارد — باید بازبینی/تطبیق شود، نه بازسازی) یک Actor را برای یک بازه‌ی زمانی به Delegate وصل می‌کند؛ موتور Assignment قبل از هر تخصیص جدید چک می‌کند آیا Assignee فعلاً Delegate فعال دارد یا نه، و طبق قانون Salesforce، خودِ Delegate اجازه‌ی Re-delegate ندارد.

## مدل داده

```
assignment_rules              -- معادل sysrule_assignment ServiceNow، مستقل از هر Workflow خاص
  id, org_id, name, applies_to_process_id FK NULL
  method enum(specific_user,role,department,manager,requester,requester_manager,
              process_owner,previous_assignee,dynamic_expression,team,queue,
              round_robin,load_balanced,skill_based)
  config jsonb        -- پارامتر خاص هر method (role_id، expression، skill نیازمند، ...)
  priority_order int  -- کدام قانون اول ارزیابی شود، طبق الگوی ServiceNow "order (lower runs first)"

skill_ratings                 -- فقط اگر skill_based استفاده شود
  id, user_id FK, skill_slug, rating int(1-10)

-- work_items.assigned_to_* از ۰۹-data-model، به‌علاوه:
assignment_queue_membership
  id, queue_slug, user_id FK, is_available boolean   -- برای Round Robin/Load Balancing
```

## قاعده‌ی طلایی طراحی

Assignment Method باید همیشه یک **Fallback** صریح داشته باشد (طبق الگوی Pega: «اگر کسی Match نشد، به مدیر گروه برو»). یک Work Item بدون Assignee قابل‌حل و بدون Fallback، یک Silent Failure است — دقیقاً نوع مشکلی که در Audit امنیتی پروژه‌ی فعلی (بخش «Silent Failures») هشدار داده شده بود.

---
**اسناد مرتبط:** [۰۷-Node Catalog](07-workflow-node-catalog.md) · [۱۲-SLA](12-sla-and-escalation.md) · [۰۹-Data Model](09-data-model.md)
