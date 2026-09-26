# ۰۴ — Domain Taxonomy و طراحی Cross-Functional

## پایه: ۱۳ Category سطح‌یک APQC (تأییدشده از منبع اصلی، نسخه‌ی v7.3.1، سپتامبر ۲۰۲۳)

| کد | نام (نسخه‌ی ۲۰۲۳) | name_fa | نوع |
|---|---|---|---|
| 1.0 | Develop Vision and Strategy | تدوین چشم‌انداز و استراتژی | Operating |
| 2.0 | Develop and Manage Products and Services | توسعه و مدیریت محصولات/خدمات | Operating |
| 3.0 | Market and Sell Products and Services | بازاریابی و فروش | Operating |
| 4.0 | Manage Supply Chain for Physical Products | مدیریت زنجیره‌ی تأمین محصولات فیزیکی | Operating |
| 5.0 | Deliver Services | تحویل خدمات | Operating |
| 6.0 | Manage Customer Service | مدیریت خدمات مشتری | Operating |
| 7.0 | Develop and Manage Human Capital | توسعه و مدیریت سرمایه‌ی انسانی | Management &amp; Support |
| 8.0 | Manage Information Technology (IT) | مدیریت فناوری اطلاعات | Management &amp; Support |
| 9.0 | Manage Financial Resources | مدیریت منابع مالی | Management &amp; Support |
| 10.0 | Acquire, Construct, and Manage Assets | تحصیل، ساخت و مدیریت دارایی | Management &amp; Support |
| 11.0 | Manage Enterprise Risk, Compliance, Remediation, and Resiliency | مدیریت ریسک، انطباق و تاب‌آوری | Management &amp; Support |
| 12.0 | Manage External Relationships | مدیریت روابط بیرونی | Management &amp; Support |
| 13.0 | Develop and Manage Business Capabilities | توسعه و مدیریت قابلیت‌های کسب‌وکار | Management &amp; Support |

**نکته‌ی اطمینان:** تفکیک Operating(1-8)/Management&amp;Support(9-13) در بالا با اطمینان **Medium** علامت‌گذاری شده — در متن اصلی APQC این مرز به این وضوح بیان نشده، از یک منبع ثانویه (Due Process Consulting) گرفته شده و صرفاً برای درک شهودی آورده شده، نه یک قاعده‌ی رسمی APQC.

## نگاشت به Domainهای درخواستی کاربر (بخش چهارم Prompt)

Domainهای عمومی/Cross-Industy که کاربر لیست کرده بود، همگی زیرمجموعه‌ی یکی از ۱۳ Category بالا قرار می‌گیرند — **هیچ Domain جدیدی نیاز به Category جدید نداشت**، این خودش تأییدی بر جامعیت APQC است:

| Domain (کاربر) | زیرمجموعه‌ی کدام Category |
|---|---|
| Management, Strategy | 1.0 |
| Operations | 2.0, 5.0 (بسته به نوع خروجی) |
| Sales, Marketing | 3.0 |
| Supply Chain, Procurement | 4.0 |
| Customer Service | 6.0 |
| HR | 7.0 |
| IT | 8.0 |
| Finance, Accounting | 9.0 |
| Facilities | 10.0 |
| Legal, Compliance, Quality, Security | 11.0 |
| Administration | پراکنده (9.0/13.0 بسته به فعالیت) |
| Document Management, Knowledge Management | 13.0 (نزدیک‌ترین معادل APQC؛ APQC آن را به‌عنوان Capability عمومی می‌بیند نه یک Category مستقل) |
| Project Management | پراکنده در همه‌ی Categoryها — طبق تعریف Value Stream در [۰۲](02-process-concepts.md)، بیشتر شبیه یک Value Stream عمودی است تا یک Domain افقی |

## چرا Taxonomy فقط بر اساس ساختار سازمانی کافی نیست (پاسخ صریح به هشدار کاربر)

مثال دقیقاً همان مثالی که کاربر آورد — «Purchase Request → Manager Approval → Procurement Review → Vendor Selection → PO → Delivery → Invoice Matching → Payment» — طبق Research واقعی (سند [۰۵](05-process-taxonomy.md))، این فرایند واحدهای زیر را قطع می‌کند:

```
Requester (هر دپارتمانی) → 4.0/9.0 (Procurement/Finance) → 9.0 (Finance، Invoice Matching) → 9.0 (Payment)
```

اگر Taxonomy فقط بر مبنای Department طراحی شود، این فرایند باید به یک واحد «تعلق» داشته باشد که غلط است — عملاً در Procurement زندگی می‌کند اما Approval از دپارتمان درخواست‌دهنده شروع می‌شود و در Finance تمام می‌شود. **راه‌حل معماری:**

`processes.domain_id` نشان‌دهنده‌ی «کجا Owner می‌شود» است (Home Domain)، نه «چه کسانی درگیرند». درگیری واقعی چند-دپارتمانی از طریق:
1. **`process_industries`/تگ‌ها** برای دسته‌بندی افقی اضافی
2. **خودِ گراف Workflow** (نه Taxonomy) — که واقعاً نشان می‌دهد کدام Node به کدام Actor/Role/Department تعلق دارد (دقیقاً معادل BPMN Pool/Lane، تأییدشده در Research: «Pool = participant container، Lane = زیرمجموعه‌ی نقش/دپارتمان درون یک Pool»)

**نتیجه:** Cross-Functional بودن در سطح **اجرا** (Lane در گراف Workflow) حل می‌شود، نه در سطح **Taxonomy**. Taxonomy فقط برای پیدا کردن/دسته‌بندی Process در Library است؛ واقعیت چندواحدی بودن اجرا در گراف زندگی می‌کند.

## Function (سطح دوم — Process Group)

هر Domain به چند Function تقسیم می‌شود (معادل APQC Process Group، سطح دو). نمونه برای Domain «Finance» (Category 9.0):
- Accounts Payable (≈ APQC 9.2)
- Accounts Receivable / Revenue Accounting (≈ APQC 9.3)
- Financial Planning &amp; Budgeting (≈ APQC 9.1)
- Financial Close &amp; Reporting

فهرست کامل Function per Domain در `data/process-library/domains.json` آمده (به‌همراه `functions` تلویحی در Slug هر Process، نه یک فایل جدا — طبق تصمیم در [۰۹-data-model](09-data-model.md) که Functionها را به همان جدول Process Group متصل نگه می‌دارد تا حجم فایل‌های JSON غیرضروری زیاد نشود).

---
**اسناد مرتبط:** [۰۳-Industry Taxonomy](03-industry-taxonomy.md) · [۰۵-Process Taxonomy](05-process-taxonomy.md) · `data/process-library/domains.json`
