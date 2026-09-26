# ۱۴ — Rule Engine (جدا از Workflow)

## اصل تفکیک (تأییدشده از استاندارد DMN + پیاده‌سازی واقعی)

طبق Research مستقیم DMN (استاندارد OMG که با BPMN جفت می‌شود) و پیاده‌سازی Camunda: یک Business Rule Task در گراف Workflow **فقط یک ارجاع** به یک Decision نگه می‌دارد (`decisionId` + `resultVariable` + `bindingType`)، نه خودِ منطق. این یعنی Rule Engine باید یک زیرسیستم کاملاً مستقل باشد که Workflow آن را «صدا می‌زند»، نه بخشی از گراف.

```xml
<!-- نمونه‌ی واقعی Camunda 8، تأییدشده از مستندات رسمی -->
<bpmn:businessRuleTask id="determine-approver">
  <bpmn:extensionElements>
    <zeebe:calledDecision decisionId="approval_threshold" resultVariable="approverRole" bindingType="latest" />
  </bpmn:extensionElements>
</bpmn:businessRuleTask>
```

## ساختار Decision Table (تأییدشده از DMN)

هر Decision Table سه بخش دارد:
- **Input clauses** — ستون‌های شرط (چند ستون، ترکیب ضمنی AND بین ستون‌ها در هر ردیف)
- **Output clauses** — ستون‌های نتیجه
- **Rules** — ردیف‌ها، هرکدام یک نگاشت شرط→نتیجه

### Hit Policy (تأییدشده، ۷ نوع طبق DMN 1.3)

| کد | نام | معنی | کاربرد نمونه |
|---|---|---|---|
| **U** | Unique | فقط یک ردیف مجاز به Match است؛ همپوشانی خطای طراحی است | آستانه‌ی مبلغ با بازه‌های غیرهم‌پوشان |
| **A** | Any | چند ردیف می‌توانند Match کنند اما باید همه یک خروجی یکسان بدهند | قوانین افزونه‌ی هم‌جهت |
| **P** | Priority | چند Match مجاز؛ خروجی بر اساس اولویت از پیش تعریف‌شده در لیست مقادیر انتخاب می‌شود | وقتی چند قانون هم‌زمان صادق‌اند ولی یکی مهم‌تر است |
| **F** | First | اولین ردیف Match در ترتیب جدول برنده است | قوانین Fallback زنجیره‌ای |
| **R** | Rule Order | همه‌ی خروجی‌های Match‌شده، به ترتیب ردیف جدول برگردانده می‌شوند | جمع‌آوری چند اقدام هم‌زمان |
| **O** | Output Order | همه‌ی خروجی‌ها، به ترتیب اولویت خروجی برگردانده می‌شوند | مشابه R با اولویت‌بندی خروجی |
| **C** | Collect (+SUM/MIN/MAX/COUNT) | همه‌ی خروجی‌ها جمع‌آوری/تجمیع می‌شوند | محاسبه‌ی مجموع تخفیف از چند قانون |

**پیش‌فرض پیشنهادی محصول:** `Unique` — چون بیشتر موارد کسب‌وکاری واقعی (آستانه‌ی مبلغ، تخصیص بر اساس دپارتمان) طبیعتاً بازه‌های غیرهم‌پوشان‌اند و `Unique` زودترین محل تشخیص خطای طراحی (همپوشانی ناخواسته) است.

## نمونه‌ی عملی: دو مثال دقیقاً خواسته‌شده در Prompt کاربر

**«اگر مبلغ > ۱۰۰٬۰۰۰٬۰۰۰ ریال، تأیید مدیر ارشد لازم است»**
```json
{
  "rule_slug": "approval-threshold-by-amount",
  "hit_policy": "unique",
  "inputs": [{ "variable": "amount", "type": "number" }],
  "outputs": [{ "variable": "required_approver_role", "type": "string" }],
  "rules": [
    { "conditions": { "amount": "> 100000000" }, "outputs": { "required_approver_role": "director" } },
    { "conditions": { "amount": "<= 100000000" }, "outputs": { "required_approver_role": "manager" } }
  ]
}
```

**«اگر دپارتمان = IT، به مدیر IT تخصیص بده»** (شکل ساده‌ی Condition Builder، طبق الگوی مشاهده‌شده در Salesforce Flow/ServiceNow Business Rules — فیلد/عملگر/مقدار)
```json
{
  "rule_slug": "assignment-by-department",
  "hit_policy": "first",
  "inputs": [{ "variable": "department", "type": "string" }],
  "outputs": [{ "variable": "assign_to_role", "type": "string" }],
  "rules": [
    { "conditions": { "department": "= IT" }, "outputs": { "assign_to_role": "it-manager" } },
    { "conditions": { "department": "= Finance" }, "outputs": { "assign_to_role": "finance-manager" } }
  ]
}
```

## Condition Builder (لایه‌ی UI برای کاربر غیرتوسعه‌دهنده)

طبق Research (Salesforce Flow Decision element؛ Medium Confidence روی نام دقیق فیلدها، اما شکل مفهومی با اطمینان بالا تأیید شد)، هر شرط یک ردیف با این شکل است:
```json
{
  "conditionLogic": "and",
  "conditions": [
    { "field": "department", "operator": "equals", "value": "IT" },
    { "field": "amount", "operator": "greater_than", "value": 100000000 }
  ]
}
```
عملگرهای حداقلی لازم: `equals`, `not_equals`, `greater_than`, `less_than`, `greater_or_equal`, `less_or_equal`, `contains`, `is_empty`, `is_not_empty`, `in_list`. گروه‌بندی با `and`/`or`/`custom` (فرمول آزاد برای کاربر پیشرفته، دقیقاً الگوی Salesforce).

## چرا Drools/Salience اینجا استفاده نمی‌شود

Research موتور Drools را هم بررسی کرد (Salience برای اولویت، Agenda Group برای دسته‌بندی اجرای قوانین). این مدل برای **سیستم‌های با صدها قانون مستقل و متقاطع** مناسب است (مثل موتور تشخیص کلاهبرداری). برای این محصول — که هر Decision معمولاً به یک تصمیم مشخص محدود است (آستانه‌ی تأیید، تخصیص) — مدل **DMN Decision Table با Hit Policy** ساده‌تر، قابل‌نمایش بصری (جدول، نه قانون متنی)، و برای کاربر غیرفنی قابل فهم‌تر است. Drools/Salience را به‌عنوان الگوی مرجع برای فاز Enterprise (اگر روزی نیاز به قوانین متقاطع پیچیده شد) نگه می‌داریم، نه برای MVP.

## اتصال به Data Model

`business_rules` → `business_rule_versions` (هرکدام `hit_policy` + آرایه‌ی `business_rule_conditions`) — نسخه‌بندی مستقل، دقیقاً مثل Workflow (نگاه کنید [۱۵-versioning](15-versioning.md)) تا تغییر یک آستانه نیازی به انتشار نسخه‌ی جدید کل Workflow نداشته باشد وقتی Binding از نوع `latest` است.

---
**اسناد مرتبط:** [۰۷-Node Catalog](07-workflow-node-catalog.md) (Decision/Condition Node) · [۰۹-Data Model](09-data-model.md) · [۱۵-Versioning](15-versioning.md)
