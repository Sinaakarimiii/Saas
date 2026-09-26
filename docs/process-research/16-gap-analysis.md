# ۱۶ — Process Completeness Analysis و بازبینی نهایی کیفیت

## جدول Coverage (محاسبه‌شده از `processes.json`، نه حدس)

شمارش واقعی از فایل Seed (۵۱ Process کاتالوگ‌شده، اجرا‌شده با اسکریپت مستقیم روی JSON):

| Domain (APQC Category) | تعداد Process کاتالوگ‌شده | Coverage نسبت به ۱۳ Category | یادداشت |
|---|---|---|---|
| Human Capital (7.0) | 10 | عمیق | پرمستندترین Domain در کل Research (Workday/BambooHR/SuccessFactors/Concur) |
| Information Technology (8.0) | 8 | عمیق | ITSM (ServiceNow/ITIL) بسیار عمیق‌تر از خودِ APQC Category 8.0 (نگاه کنید [۰۵](05-process-taxonomy.md)) |
| Financial Resources (9.0) | 7 | متوسط-عمیق | AP/AR/Close پوشش داده شد؛ Tax/Treasury/Investor Relations پوشش نشد |
| Supply Chain & Procurement (4.0) | 7 | متوسط-عمیق | Procurement قوی؛ Manufacturing/Distribution فیزیکی پوشش نشد (چون این محصول برای خدمات/اداری طراحی شده، نه تولید) |
| Marketing & Sales (3.0) | 4 | کم-متوسط | فقط CRM-محور (Salesforce/HubSpot)؛ Campaign Management/Brand عملاً پوشش نشد |
| Customer Service (6.0) | 4 | کم-متوسط | یک مورد (Complaint Handling) با منبع ضعیف |
| Risk, Compliance & Resiliency (11.0) | 4 | کم | Legal/Compliance پوشش شد؛ Quality Management و Security به‌عنوان Domain مستقل پوشش نشد (فقط IT Security زیر Category 8.0 آمد) |
| Asset Management (10.0) | 4 | کم | CMMS عمومی؛ Real Estate/Capital Asset پوشش نشد |
| Business Capabilities (13.0) | 3 | کم | فقط Document Management؛ Knowledge Management و Project Management **صفر Process مستند دارند** |
| Vision & Strategy (1.0) | 0 | **صفر** | Research اصلاً به این Category نرسید — طبیعت این Category (تدوین استراتژی سطح‌بالا) کمتر شبیه یک Workflow اجراشدنی است، بیشتر یک فعالیت مدیریتی تک‌باره |
| Product & Service Development (2.0) | 0 | **صفر** | همان دلیل — نیاز به Research مستقل در آینده اگر محصول به سمت PLM/NPD رفت |
| Service Delivery (5.0) | 0 | **صفر** | همپوشان با IT/Customer Service شد، مستقلاً بررسی نشد |
| External Relationships (12.0) | 0 | **صفر** | Research به این Category نرسید (روابط عمومی/سرمایه‌گذار — کم‌کاربرد برای MVP این محصول) |

**نتیجه‌ی صادقانه (طبق قانون کاربر «Coverage را با منطق محاسبه کن، نه حدس»):** از ۱۳ Category، **۴ مورد صفر Process** دارند. این عمداً پر نشد چون منابع Vendor معتبر برای آن‌ها در بازه‌ی این Research پیدا نشد — طبق قانون صریح کاربر («اگر منبعی نیست، حدس نزن») بهتر است این خلأ صادقانه گزارش شود تا اینکه با Processهای ساختگی پر شود.

## توزیع اطمینان منبع (Source Confidence)

از ۵۱ Process: **۲۰ High، ۲۱ Medium، ۱۰ Low**. یعنی ~۲۰٪ کاتالوگ روی منابع کم‌عمق (عمدتاً الگوی عمومی «Generic Request Fulfillment» به‌جای مستندسازی مستقیم Vendor) بنا شده — این‌ها در `processes.json` با `source_confidence: "low"` صریحاً علامت‌گذاری شدند تا تیم توسعه بداند کدام Processها نیاز به بازبینی/Validation بیشتر قبل از اتکای کامل دارند: Goods Receipt، Payment Request، Facility Access Request، Asset Inspection، Customer Complaint Handling، NDA Request، IT Asset Request، Document Publishing/Archival، Contract Approval (Sales)، Overtime Approval.

## مقایسه‌ی Fact در برابر Industry Practice در برابر Recommendation (طبق قانون ۱۸ کاربر)

| نوع | نمونه | چگونه مشخص شده |
|---|---|---|
| **Fact** | «APQC دقیقاً ۱۳ Category سطح‌یک دارد» | استخراج مستقیم از PDF رسمی APQC، اطمینان High |
| **Industry Practice** | «الگوی Approval معمولاً از Submit→Review→Approve→Execute→Close است» | مشاهده‌شده در چند Vendor مستقل (Concur/NetSuite/Salesforce)، اطمینان High-Medium |
| **Recommendation** | «Node Approval باید از Task جدا باشد» یا «Hit Policy پیش‌فرض Unique باشد» | قضاوت طراحی این Research بر مبنای شواهد، نه یک Fact مستقیم — در متن هرجا این نوع جمله آمد با عبارت «تصمیم پیشنهادی» علامت‌گذاری شد |

## بازبینی نهایی کیفیت (طبق درخواست صریح انتهای Prompt کاربر)

| معیار | وضعیت | یافته |
|---|---|---|
| **Completeness** | ⚠️ جزئی | ۴ Category APQC صفر Process دارند (بالا)؛ عمداً به‌جای پرکردن ساختگی خالی ماند |
| **Consistency** | ✅ | همه‌ی Processها همان Schema را دارند (`processes.json`)؛ همه‌ی Nodeها از یک واژگان ثابت ([۰۷](07-workflow-node-catalog.md)) استفاده می‌کنند |
| **Duplicates** | ✅ رفع‌شد | «Purchase Requisition/Request/Procurement Request» و «Expense Reimbursement/Claim» Merge و در `process_synonyms` ثبت شدند (نگاه کنید [۰۵](05-process-taxonomy.md)) |
| **Missing Domains** | ⚠️ مستندشده | بالا — ۴ Category خالی |
| **Missing Process Types** | ✅ بررسی‌شد | همه‌ی ۲۴ Process Type درخواستی کاربر حداقل یک نمونه‌ی مرتبط در Catalog دارند، به‌جز «Registration» که فقط به‌صورت ضمنی (بخشی از Vendor Onboarding) حاضر است، نه یک Process مستقل — قابل‌قبول چون Registration معمولاً واقعاً زیرمجموعه‌ی یک Process بزرگ‌تر است، نه مستقل |
| **Data Model Integrity** | ✅ بررسی‌شد | هر FK در [۰۹](09-data-model.md) به یک جدول تعریف‌شده اشاره می‌کند؛ هیچ Orphan Reference پیدا نشد؛ همه‌ی JSON با `python3 -m json.tool` معتبرسنجی شدند |
| **Scalability** | ✅ طراحی‌شده | جدول `graph jsonb` به‌جای نرمال‌سازی Node/Edge دقیقاً برای مقیاس معقول (چند صد Node در هر Template) انتخاب شد؛ `work_items` ایندکس روی `due_at` برای Scan مقیاس‌پذیر SLA دارد |
| **Reusability** | ✅ طراحی‌شده | `is_callable_only` + Input/Output Contract (نگاه کنید [۰۸](08-process-engine-architecture.md), [۱۰](10-process-library.md)) |
| **Versioning** | ✅ طراحی‌شده | سه‌جدولی Template/Version/Instance، مبتنی بر رفتار واقعی چهار موتور مقایسه‌شده (نگاه کنید [۱۵](15-versioning.md)) |
| **Multi-tenancy** | ⚠️ نیازمند هماهنگی صریح با پروژه‌ی موجود | همه‌ی جداول پیشنهادی `org_id` دارند، هماهنگ با الگوی RLS موجود پروژه؛ اما این Research مستقیماً RLS Policy پیشنهاد نداد چون خارج از Scope «فقط Research» بود — این باید اولین کار پیاده‌سازی باشد |
| **Internationalization** | ✅ طراحی‌شده | `name_en`/`name_fa` روی هر Entity، انگلیسی Canonical (نگاه کنید [۰۹](09-data-model.md) بخش Naming) |
| **Extensibility** | ✅ طراحی‌شده | Node Catalog/Process Type/Domain همه Data-driven هستند (جدول، نه Enum سخت در کد)، یعنی افزودن Domain/Node جدید بدون تغییر Schema ممکن است |

### اصلاحات اعمال‌شده در همین بازبینی

در حین بازبینی نهایی، این موارد اصلاح شد (نه صرفاً گزارش شد، طبق دستور صریح «مشکلات کشف‌شده را اصلاح کن»):
1. لیست ۲۰ نمونه‌ی کامل کاربر شامل «Project Change Request» بود که منبع معتبر نداشت — با «Employee Offboarding» (منبع High-confidence) جایگزین شد؛ این جایگزینی و دلیلش در [۱۰-process-library](10-process-library.md) صریحاً مستند شد تا شفاف بماند، نه پنهان.
2. «Universal Process Core» (بخش بیست‌ودوم Prompt) در ابتدا در هیچ فایلی جا نگرفته بود — به [۰۸-engine-architecture](08-process-engine-architecture.md) اضافه شد.
3. بررسی شد که آیا `workflow_nodes`/`workflow_edges` باید جدول‌های نرمال‌شده باشند (طبق لیست اولیه‌ی کاربر) یا JSON — بر اساس شواهد چهار موتور واقعی (هیچ‌کدام Node/Edge را در جدول‌های SQL جدا نرمال نمی‌کنند) به `graph jsonb` تغییر یافت؛ این تغییر و دلیلش صریحاً در [۰۹-data-model](09-data-model.md) مستند شد.

---
**اسناد مرتبط:** [۰۵-Process Taxonomy](05-process-taxonomy.md) · [۱۰-Process Library](10-process-library.md) · [۱۷-Product Recommendations](17-product-recommendations.md)
