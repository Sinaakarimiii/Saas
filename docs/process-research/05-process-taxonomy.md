# ۰۵ — Process Taxonomy (فرایندهای واقعی هر حوزه)

این سند خلاصه‌ی خوانا‌ست؛ جزئیات کامل (Trigger/Actors/Steps/Forms/SLA برای هر Process) در `data/process-library/processes.json` و نسخه‌ی کاملاً بازشده‌ی ۲۰ فرایند در `data/process-library/sample-full-processes.json` است. همه‌ی موارد زیر از منابع واقعی Vendor استخراج شدند (نه حدس) — منبع هرکدام در JSON ثبت شده.

## Process Type Taxonomy ثانویه (طبقه‌بندی بر اساس نوع، نه صنعت/دامنه)

طبق درخواست صریح کاربر، فرایندها علاوه بر Domain، بر اساس **نوع رفتاری** هم دسته‌بندی می‌شوند — این محور دوم است که به Builder اجازه می‌دهد الگوی مشترک بین Domainهای مختلف را تشخیص دهد:

| Process Type | تعریف کوتاه | نمونه از Research |
|---|---|---|
| Request | یک Actor چیزی می‌خواهد | Leave Request, Asset Request |
| Approval | تصمیم دودویی/چندگزینه‌ای روی یک درخواست | Purchase Requisition approval |
| Review | بازبینی بدون تصمیم قطعی | Contract Review (پیش از Approval نهایی) |
| Service | ارائه‌ی یک خدمت مشخص به یک متقاضی | IT Service Request Fulfillment |
| Incident | واکنش به یک اختلال غیرمنتظره | ITSM Incident Management |
| Case Management | پیگیری غیرخطی یک پرونده | Security Incident Response, Complaint Handling |
| Compliance | اطمینان از رعایت یک قاعده/قانون | Policy Exception Request |
| Audit | بررسی سیستماتیک و مستندسازی یافته | Audit Finding Remediation |
| Procurement | تحصیل کالا/خدمت از بیرون سازمان | Purchase Requisition, RFQ |
| Financial | جابه‌جایی/کنترل منابع مالی | Invoice Approval, Budget Approval |
| HR | مرتبط با چرخه‌ی عمر کارمند | Onboarding, Performance Review |
| Document | چرخه‌ی عمر یک سند | Document Approval Cycle |
| Project | فعالیت‌های محدود به یک هدف یک‌بارمصرف | Project Change Request |
| Customer Service | تعامل مستقیم با مشتری بیرونی | Refund Request, CSAT Follow-up |
| Maintenance | نگهداری دارایی فیزیکی/دیجیتال | Maintenance/Repair Request |
| Inspection | بازرسی دوره‌ای | Asset Inspection |
| Scheduling | تخصیص زمان/منبع | Shift Change/Swap |
| Onboarding | ورود یک Entity جدید (کارمند/مشتری/تأمین‌کننده) | Employee/Customer/Vendor Onboarding |
| Offboarding | خروج یک Entity | Employee Offboarding |
| Escalation | انتقال به سطح بالاتر مسئولیت | (جزء اکثر Processهای بالا، نه یک Process مستقل معمولاً) |
| Exception | انحراف از مسیر عادی | Audit Finding، Change-of-plan |
| Renewal | تمدید یک تعهد/قرارداد رو به انقضا | Contract Renewal |
| Assessment | ارزیابی کیفی/کمی | Vendor Evaluation, Performance Review |
| Registration | ثبت اولیه‌ی یک Entity در سیستم | Vendor Onboarding (بخش ثبت) |
| Fulfillment | تکمیل عملیاتی یک درخواست پذیرفته‌شده | Service Request Fulfillment |

## خلاصه‌ی فرایندهای واقعی به‌تفکیک Domain

### HR (Category 7.0)
Employee Onboarding · Employee Offboarding · Leave/Time-off Request · Recruitment (Requisition-to-Hire) · Performance Review · Training Request · Expense Reimbursement · Shift Change/Swap · Overtime Approval · Promotion/Transfer · Disciplinary Action

منابع: Workday, BambooHR, SAP SuccessFactors, SAP Concur, Oracle HCM (جزئیات کامل هرکدام در `processes.json`).

### IT Service Management (Category 8.0)
Incident Management · Problem Management · Change Management (Normal/Standard/Emergency — سه Process Type متفاوت با یک والد مشترک) · Service Request Fulfillment · Access Request/Provisioning · Asset Request · Software Request · IT Onboarding/Offboarding · Security Incident Response

منابع: ServiceNow، ITIL 4 (۳۴ Practice، ۱۷ مورد Service Management).

**یافته‌ی مهم Cross-check:** APQC PCF در Category 8.0 این فرایندها را به‌صورت جداگانه نام‌گذاری **نمی‌کند** — فقط زیر یک Process با نام «Operate IT user support» چند Activity کلی دارد (Triage/Manage/Escalate/Resolve). این یعنی برای Domain IT، **ITIL باید منبع اصلی نام‌گذاری/ساختار باشد، نه APQC** — دقیقاً طبق قانون کاربر «از یک منبع به‌عنوان حقیقت مطلق استفاده نکن».

### Procurement / Supply Chain (Category 4.0)
Purchase Requisition (مترادف: Purchase Request, Procurement Request) · RFQ/RFP (Sourcing Event) · Vendor/Supplier Onboarding · Vendor Evaluation · Purchase Order Creation · Goods Receipt · Three-way Invoice Matching · Payment Request · Contract Renewal

منابع: SAP Ariba, Coupa, Oracle Procurement Cloud.

### Finance/Accounting (Category 9.0)
Invoice Approval/Accounts Payable · Expense Claim (همان Process با Expense Reimbursement در HR — **Duplicate شناسایی‌شده و Merge شده**، نگاه کنید بخش Deduplication پایین) · Budget Approval · Financial Close · Order-to-Cash/Accounts Receivable-Collections

منابع: NetSuite, SAP.

### Sales/CRM (Category 3.0)
Lead-to-Opportunity · Quote/Proposal Approval · Deal Desk Approval · Contract Approval (همپوشان با Legal — نگاه کنید پایین) · Customer Onboarding

منابع: Salesforce، HubSpot.

### Customer Service (Category 6.0)
Ticket Escalation · CSAT Follow-up · Refund/Return Request · Customer Complaint Handling (مستندسازی کم‌عمق — نگاه کنید [۱۶-gap-analysis](16-gap-analysis.md))

منابع: Zendesk، Salesforce Service Cloud.

### Legal/Compliance (Category 11.0)
Contract Review/Approval · NDA Request (همپوشان با Document Sign-off) · Compliance Audit Finding Remediation · Policy Exception Request

منابع: DocuSign CLM، Info-Tech Research، Section508.gov (نمونه‌ی واقعی دولت فدرال آمریکا).

### Facilities/Operations (Category 10.0)
Maintenance/Repair Request (Work Order) · Incident/Safety Report (استاندارد OSHA، با SLA رسمی: فوت=۸ ساعت، بستری/قطع‌عضو=۲۴ ساعت، سایر=۷ روز) · Facility Access Request (مستندسازی کم — الگوی Request-to-Fulfillment عمومی) · Asset Inspection (مستندسازی کم — الگوی CMMS عمومی)

### Document Management (Category 13.0)
Document Approval/Review Cycle (Sequential یا Parallel) · Digital Signature/Sign-off Workflow

منابع: SharePoint، M-Files، DocuSign.

## Deduplication و Synonym (طبق قانون بخش ۲۶ کاربر)

Research صراحتاً موارد زیر را به‌عنوان **همان مفهوم با نام‌های مختلف** شناسایی کرد — این‌ها یک `process` با چند `process_synonyms` می‌شوند، نه چند Process جدا:

| Canonical Name | Synonyms یافت‌شده |
|---|---|
| Purchase Requisition | Purchase Request, Procurement Request |
| Expense Reimbursement | Expense Claim |
| Employee Offboarding | Termination, Exit Process |
| Onboarding (عمومی) | Recruit-to-Hire زیرمجموعه‌ی Recruitment است، نه مترادف Onboarding — این دو **عمداً جدا نگه داشته شدند** چون Recruitment قبل از استخدام و Onboarding بعد از آن است |
| NDA Request | زیرمجموعه‌ی عملیاتی Document Sign-off Pattern؛ به‌عنوان Process مستقل نگه داشته شد چون Trigger/Actor خاص خودش را دارد، اما در `related_processes` به Document Approval لینک شد |
| Contract Approval (Sales) در برابر Contract Review/Approval (Legal) | این دو **Merge نشدند** — هرچند شبیه‌اند، Domain متفاوت (Sales در برابر Legal) و معمولاً Actor اول متفاوت (Deal Desk در برابر Legal Counsel) دارند؛ در `related_processes` به هم لینک شدند تا در UI به کاربر «آیا منظورتان این است؟» نشان داده شود |

---
**اسناد مرتبط:** [۰۶-Process Patterns](06-process-patterns.md) · [۱۰-Process Library](10-process-library.md) · [۱۶-Gap Analysis](16-gap-analysis.md) · `data/process-library/processes.json`
