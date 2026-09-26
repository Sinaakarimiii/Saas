# ۰۶ — Process Patterns (الگوهای تکرارشونده)

منبع اصلی: تحلیل Cross-Domain در Research فرایندهای واقعی (سند [۰۵](05-process-taxonomy.md)) که صراحتاً نشان داد اکثر فرایندهای سازمانی از تعداد محدودی الگو ساخته می‌شوند — نه اینکه هر Domain الگوی خاص خودش را داشته باشد.

## الگوهای اصلی (۱۴ مورد، هرکدام با نمونه‌ی واقعی از Research)

### ۱. Simple Approval
```
Request → Review → Approval → Execution → Closure
```
نمونه‌ی واقعی: Leave Request (SAP SuccessFactors) — تک‌سطحی، یک Approver.

### ۲. Multi-Level (Sequential) Approval
```
Request → Supervisor → Manager → Director → Final Approval → Execution
```
نمونه‌ی واقعی: Concur Expense «Management Chain Routing» — بالا می‌رود تا به Approverای با سقف اختیار کافی برسد (Escalate-by-authority-limit، نه صرفاً سلسله‌مراتب ثابت).

### ۳. Parallel Approval
```
Request → {Finance, Legal, Technical} (هم‌زمان) → Merge → Final Decision
```
نمونه‌ی واقعی: Salesforce CPQ Advanced Approvals «Parallel simultaneous approvers».

### ۴. Threshold-Based Conditional Approval
```
Request → Decision(amount) → [amount > X → Director] یا [amount ≤ X → Manager] → Execution
```
نمونه‌ی واقعی: NetSuite AP — فاکتور بالای ۲۰٬۰۰۰ دلار به CFO Escalate می‌شود؛ این عملاً ترکیب Branch + Escalation Pattern است، نمونه‌ی مستقیم DMN Decision Table («if amount > X then approver = director»، نگاه کنید [۱۴](14-rule-engine.md)).

### ۵. Sequential Review-and-Rework
```
Submission → Review → (Changes Requested) → Rework → Resubmission → Review → Approval
```
نمونه‌ی واقعی: DocuSign CLM Contract Review — با Deadline و یادآوری خودکار هر دور.

### ۶. SLA / Escalation Chain
```
Request → Assignment → SLA Timer شروع → [نزدیک Breach → Reminder] → [Breach → Escalate L1] → [ادامه‌ی Breach → Escalate L2] → Resolution
```
نمونه‌ی واقعی: ServiceNow Major Incident + Zendesk «Hours since SLA breach» Automation. سه پیاده‌سازی متفاوت واقعی برای همین الگو در Research پیدا شد (نگاه کنید [۱۲](12-sla-and-escalation.md)) — این الگو مهم‌ترین الگوی غیر-Approval کل Research است.

### ۷. Exception Handling (Non-Interrupting)
```
Process (در حال اجرا) → [Exception رخ می‌دهد] → Investigation → Resolution → Resume همان Process
```
نمونه‌ی واقعی: BPMN Non-interrupting Boundary Event — کار اصلی متوقف نمی‌شود، یک مسیر موازی رسیدگی باز می‌شود.

### ۸. Conditional Branch
```
Request → Decision → Path A  یا  Path B
```
پایه‌ی فنی: BPMN Exclusive Gateway / Step Functions `Choice` / n8n `Switch` — سه پیاده‌سازی مستقل همین یک مفهوم را با واژگان متفاوت (Gateway/Choice/Switch) دارند؛ شواهد قوی که این یک الگوی جهانی‌ست، نه سلیقه‌ی یک Vendor.

### ۹. Loop (Rework Cycle)
```
Submit → Review → Rework → Review → ... → Approval  (با سقف تکرار)
```
تفاوت با #۵: اینجا تأکید روی محدودیت تکرار (جلوگیری از Infinite Loop) است، نه صرفاً یک بار برگشت.

### ۱۰. Parallel Independent Tasks (Fork/Join)
```
Process → {Task A, Task B, Task C} (مستقل از هم) → Join → Continue
```
نمونه‌ی واقعی: IT Onboarding (ServiceNow EOT) — فراهم‌سازی سخت‌افزار، ایجاد حساب، آموزش امنیتی هم‌زمان اجرا می‌شوند، بدون وابستگی به هم.

### ۱۱. Delegation / Temporary Reassignment
```
Task → Assigned User (غایب) → Delegate → Task تکمیل می‌شود توسط Delegate
```
نمونه‌ی واقعی: Salesforce Approval Processes «Delegated Approver» (نمی‌تواند دوباره Reassign کند، فقط تصمیم می‌گیرد) + jBPM Deadline-based Reassignment.

### ۱۲. Scheduled / Recurring Process
```
Date/Event رخ می‌دهد → Trigger → Work Item ساخته می‌شود → Execute → Close
```
نمونه‌ی واقعی: Contract Renewal (Oracle) — «۱ ماه قبل از انقضا» Reminder خودکار می‌سازد.

### ۱۳. Generic Request-to-Fulfillment
```
Submit Request (Form) → [Approval اختیاری] → Route to Fulfiller → Provision/Process → Notify Requester → Confirm/Close
```
پرتکرارترین الگوی یافت‌شده در کل Research — عیناً در ServiceNow Service Catalog، Facility Maintenance Work Order، Training Enrollment، NDA Request دیده شد؛ فقط Actor/Object عوض می‌شود.

### ۱۴. Generic Onboarding/Offboarding Orchestration
```
Triggering Event → Fan-out به چند Department (چک‌لیست موازی) → Provisioning → Milestone Tracking → Completion State
```
نمونه‌ی واقعی: تقریباً عین‌هم در HR Onboarding (Workday)، IT Onboarding (ServiceNow)، Customer Onboarding (HubSpot)، Vendor Onboarding (Coupa) — این الگو ترکیبی از #۱۰ (Parallel Tasks) + یک Case-level Status Machine است، نه یک Pattern کاملاً جدید؛ اما به‌قدری پرتکرار است که ارزش Template مستقل دارد.

## نکته‌ی معماری: چرا این الگوها مهم‌اند

هر الگو در بالا باید در `workflow_patterns.json` به‌عنوان یک **Template قابل درگ‌ودراپ در Builder** موجود باشد (نه فقط مستند). یعنی کاربر وقتی Node «Approval» را می‌گذارد، Builder باید پیشنهاد بدهد «می‌خواهید این را Multi-Level کنید؟» — دقیقاً چون #۱ و #۲ در عمل یک الگو با یک پارامتر (تعداد سطح) هستند، نه دو Node متفاوت.

**رابطه‌ی الگو با Node Catalog:** هر الگو ترکیبی از Nodeهای [۰۷](07-workflow-node-catalog.md) است، نه یک Node جدید. مثلاً الگوی #۶ (SLA/Escalation) = `Wait/Timer` + `Escalation` + `Approval`؛ الگوی #۱۳ = `Form` + `Approval` (اختیاری) + `Create Record` + `Send Notification`.

---
**اسناد مرتبط:** [۰۵-Process Taxonomy](05-process-taxonomy.md) · [۰۷-Node Catalog](07-workflow-node-catalog.md) · [۱۲-SLA](12-sla-and-escalation.md)
