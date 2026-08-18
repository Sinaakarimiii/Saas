-- Expand the field-type catalog (text, textarea, number, date_jalali,
-- select, boolean, file) and move `options` from a bare array (only ever
-- used by "select") to a structured object shared across all types --
-- see src/lib/form-fields.ts for the FieldOptions shape this now holds.
alter table public.form_fields drop constraint form_fields_field_type_check;
alter table public.form_fields add constraint form_fields_field_type_check
  check (field_type in ('text', 'textarea', 'number', 'date_jalali', 'select', 'boolean', 'file'));

update public.form_fields
set options = jsonb_build_object('choices', options, 'selectionMode', 'single')
where field_type = 'select' and options is not null and jsonb_typeof(options) = 'array';
