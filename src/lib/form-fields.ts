export const FIELD_TYPES = [
  "text",
  "textarea",
  "number",
  "date_jalali",
  "select",
  "boolean",
  "file",
] as const;

export type FieldType = (typeof FIELD_TYPES)[number];

export const FIELD_TYPE_LABELS: Record<FieldType, string> = {
  text: "متن کوتاه",
  textarea: "متن بلند",
  number: "عدد",
  date_jalali: "تاریخ شمسی",
  select: "انتخابی",
  boolean: "بله/خیر",
  file: "آپلود فایل",
};

export type TextFormat = "free" | "email" | "mobile" | "national_id";
export type NumberFormat = "free" | "integer" | "fixed_digits" | "mobile";
export type DateConstraint = "none" | "past_only" | "future_only";
export type SelectionMode = "single" | "multiple";

export type FieldOptions = {
  repeatable?: boolean;
  helpText?: string;
  placeholder?: string;
  // text
  textFormat?: TextFormat;
  minLength?: number;
  maxLength?: number;
  // number
  numberFormat?: NumberFormat;
  digitCount?: number;
  min?: number;
  max?: number;
  // date_jalali
  dateConstraint?: DateConstraint;
  // select
  choices?: string[];
  selectionMode?: SelectionMode;
  // file
  allowedExtensions?: string[];
  maxSizeMB?: number;
};

export const TEXT_FORMAT_LABELS: Record<TextFormat, string> = {
  free: "آزاد",
  email: "ایمیل",
  mobile: "شماره موبایل",
  national_id: "کد ملی",
};

export const NUMBER_FORMAT_LABELS: Record<NumberFormat, string> = {
  free: "آزاد",
  integer: "عدد صحیح",
  fixed_digits: "تعداد رقم ثابت",
  mobile: "شماره موبایل",
};

export const DATE_CONSTRAINT_LABELS: Record<DateConstraint, string> = {
  none: "بدون محدودیت",
  past_only: "فقط گذشته",
  future_only: "فقط آینده",
};

// Same mobile pattern as signup/page.tsx and set-password/page.tsx, kept
// here so every place that renders/validates a "mobile" text or number
// field agrees with the one used at account signup.
export const MOBILE_PATTERN = /^(0|\+98|0098)?9\d{9}$/;
export const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export const NATIONAL_ID_PATTERN = /^\d{10}$/;

export function textFormatPattern(format: TextFormat | undefined): RegExp | null {
  switch (format) {
    case "email":
      return EMAIL_PATTERN;
    case "mobile":
      return MOBILE_PATTERN;
    case "national_id":
      return NATIONAL_ID_PATTERN;
    default:
      return null;
  }
}

export function textFormatErrorMessage(format: TextFormat | undefined): string {
  switch (format) {
    case "email":
      return "ایمیل معتبر نیست";
    case "mobile":
      return "شماره موبایل معتبر نیست (مثلاً 09121234567)";
    case "national_id":
      return "کد ملی باید ۱۰ رقم باشد";
    default:
      return "مقدار وارد شده معتبر نیست";
  }
}
