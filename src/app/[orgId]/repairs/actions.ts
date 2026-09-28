"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { z } from "zod";

type ActionResult = { error: string; caseId?: never } | { caseId: string; error?: never };

const uuid = z.uuid();
const createSchema = z.object({
  orgId: uuid,
  deviceModel: z.string().trim().min(1).max(160),
  rawIdentifier: z.string().trim().max(120),
  customerName: z.string().trim().min(1).max(160),
  issue: z.string().trim().min(1).max(2000),
  priority: z.enum(["normal", "high", "urgent"]),
  source: z.enum(["phone", "chat", "walk_in", "agency", "post", "internal", "other"]),
  idempotencyKey: uuid,
});

const receiptSchema = z.object({
  orgId: uuid,
  caseId: uuid,
  expectedVersion: z.number().int().positive(),
  idempotencyKey: uuid,
  method: z.enum(["walk_in", "post", "courier", "agency", "internal"]),
  location: z.string().trim().min(1).max(200),
  custodian: z.string().trim().min(1).max(160),
  items: z.string().trim().max(1000),
  verifiedImei: z.union([z.literal(""), z.string().regex(/^\d{15}$/)]),
  imeiEvidence: z.string().trim().max(500),
  duplicateReason: z.string().trim().max(500),
  duplicateReference: z.string().trim().max(120),
}).superRefine((value, ctx) => {
  if (Boolean(value.verifiedImei) !== Boolean(value.imeiEvidence)) {
    ctx.addIssue({ code: "custom", message: "برای تأیید IMEI، شناسه و عکس برچسب هر دو لازم‌اند." });
  }
  if (Boolean(value.duplicateReason) !== Boolean(value.duplicateReference)) {
    ctx.addIssue({ code: "custom", message: "برای استثنا، علت و مرجع تأیید هر دو لازم‌اند." });
  }
});

const transitionSchema = z.object({
  orgId: uuid,
  caseId: uuid,
  expectedVersion: z.number().int().positive(),
  transitionCode: z.enum(["T01", "T02", "T03", "T04", "T05", "T08", "T09", "T10", "T11"]),
  idempotencyKey: uuid,
});

const repairCompletionSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  protocolCode: z.literal("repair_functional_v1"),
  workDescription: z.string().trim().max(2000),
  workReference: z.string().trim().max(240),
}).superRefine((value, ctx) => {
  if (Boolean(value.workDescription) !== Boolean(value.workReference))
    ctx.addIssue({ code: "custom", message: "شرح اقدام و مرجع آن باید با هم ثبت شوند." });
});

const replacementExecutionSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  executionReference: z.string().trim().min(1).max(160),
  evidenceReference: z.string().trim().min(1).max(500),
});

export async function executeRepairReplacementForTestAction(raw: unknown): Promise<ActionResult> {
  const parsed = replacementExecutionSchema.safeParse(raw);
  if (!parsed.success) return { error: "مرجع اجرا و شاهد تعویض را کامل کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_REPLACEMENT_EXECUTE);
  if (!supabase) return { error: "مجوز اجرای تعویض را ندارید." };
  const { data, error } = await supabase.rpc("execute_repair_replacement_for_test", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey, p_execution_reference: input.executionReference,
    p_evidence_reference: input.evidenceReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ ثبت تعویض معتبر نبود. وضعیت پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function completeRepairForTestAction(raw: unknown): Promise<ActionResult> {
  const parsed = repairCompletionSchema.safeParse(raw);
  if (!parsed.success) return { error: "پروتکل و اطلاعات اقدام تعمیر را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_COMPLETE);
  if (!supabase) return { error: "مجوز تکمیل تعمیر را ندارید." };
  const { data, error } = await supabase.rpc("complete_repair_for_test", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey, p_protocol_code: input.protocolCode,
    p_work_description: input.workDescription || null, p_work_reference: input.workReference || null,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ ثبت تعمیر معتبر نبود. وضعیت پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

const functionalTestSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  route: z.enum(["repair", "replacement"]).default("repair"),
  identityStatus: z.enum(["pass", "fail"]), identityEvidence: z.string().trim().min(1).max(500),
  powerStatus: z.enum(["pass", "fail"]), powerEvidence: z.string().trim().min(1).max(500),
  positionStatus: z.enum(["pass", "fail", "not_applicable"]), positionEvidence: z.string().trim().min(1).max(500),
  configurationStatus: z.enum(["pass", "fail", "not_applicable"]), configurationEvidence: z.string().trim().min(1).max(500),
});
const functionalTestReleaseSchema = z.object({
  orgId: uuid, caseId: uuid, testId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});

const repairOutgoingSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  route: z.enum(["repair", "replacement"]).default("repair"),
  identityPass: z.boolean(), identityEvidence: z.string().trim().min(1).max(500),
  itemsPass: z.boolean(), itemsEvidence: z.string().trim().min(1).max(500),
  conditionPass: z.boolean(), conditionEvidence: z.string().trim().min(1).max(500),
  transportPass: z.boolean(), transportEvidence: z.string().trim().min(1).max(500),
  intendedRecipient: z.string().trim().min(1).max(160),
  recipientRole: z.enum(["owner", "authorized_representative", "colleague"]),
  authorityReference: z.string().trim().max(240),
}).superRefine((value, ctx) => {
  if (value.recipientRole !== "owner" && !value.authorityReference)
    ctx.addIssue({ code: "custom", message: "مرجع اختیار گیرنده لازم است." });
});
const repairOutgoingReleaseSchema = z.object({
  orgId: uuid, caseId: uuid, checkId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});

export async function recordRepairOutgoingCheckAction(raw: unknown): Promise<ActionResult> {
  const parsed = repairOutgoingSchema.safeParse(raw);
  if (!parsed.success) return { error: "نتیجه و شاهد چهار کنترل و اطلاعات گیرنده را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, input.route === "replacement"
    ? PERMISSIONS.REPAIR_REPLACEMENT_OUTGOING_QC_RECORD : PERMISSIONS.REPAIR_OUTGOING_QC_RECORD);
  if (!supabase) return { error: "مجوز ثبت کنترل خروج را ندارید." };
  const { data, error } = await supabase.rpc(input.route === "replacement"
    ? "record_replacement_outgoing_check" : "record_repair_outgoing_check", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey,
    p_identity_pass: input.identityPass, p_identity_evidence: input.identityEvidence,
    p_items_pass: input.itemsPass, p_items_evidence: input.itemsEvidence,
    p_condition_pass: input.conditionPass, p_condition_evidence: input.conditionEvidence,
    p_transport_pass: input.transportPass, p_transport_evidence: input.transportEvidence,
    p_intended_recipient: input.intendedRecipient, p_recipient_role: input.recipientRole,
    p_authority_reference: input.recipientRole === "owner" ? null : input.authorityReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ کنترل خروج معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function releaseRepairOutgoingCheckAction(raw: unknown): Promise<ActionResult> {
  const parsed = repairOutgoingReleaseSchema.safeParse(raw);
  if (!parsed.success) return { error: "درخواست آزادسازی کنترل خروج معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_QUALITY_RELEASE);
  if (!supabase) return { error: "مجوز مستقل آزادسازی کیفیت را ندارید." };
  const { data, error } = await supabase.rpc("release_repair_outgoing_check", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_check_id: input.checkId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ آزادسازی کنترل خروج معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

const paymentEvidenceSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  amountIrr: z.number().int().positive().safe(), method: z.enum(["card", "bank_transfer", "cash"]),
  externalReference: z.string().trim().min(1).max(160),
  evidenceReference: z.string().trim().min(1).max(500),
});
const paymentVerifySchema = z.object({
  orgId: uuid, caseId: uuid, paymentId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  verificationReference: z.string().trim().min(1).max(160),
});
const paymentCorrectionSchema = z.object({
  orgId: uuid, caseId: uuid, paymentId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  reason: z.enum(["duplicate", "not_received", "incorrect_details"]),
  explanation: z.string().trim().min(5).max(1000),
  correctionReference: z.string().trim().min(1).max(160),
  evidenceReference: z.string().trim().min(1).max(500),
});
const creditRequestSchema = z.object({
  orgId: uuid, caseId: uuid, sourcePaymentId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  amountIrr: z.number().int().positive().safe(), requestReference: z.string().trim().min(1).max(160),
  requestEvidence: z.string().trim().min(1).max(500),
});
const creditApprovalSchema = z.object({
  orgId: uuid, caseId: uuid, transferId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  approvalReference: z.string().trim().min(1).max(160),
});
const refundRequestSchema = z.object({
  orgId: uuid, caseId: uuid, sourcePaymentId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  amountIrr: z.number().int().positive().safe(), reason: z.string().trim().min(5).max(1000),
  requestReference: z.string().trim().min(1).max(160),
});
const refundApprovalSchema = z.object({
  orgId: uuid, caseId: uuid, refundId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  outboundMethod: z.enum(["bank_transfer", "card_reversal", "cash"]),
  outboundReference: z.string().trim().min(1).max(160),
  outboundEvidence: z.string().trim().min(1).max(500),
  approvalReference: z.string().trim().min(1).max(160),
});

export async function requestRepairPaymentRefundAction(raw: unknown): Promise<ActionResult> {
  const parsed = refundRequestSchema.safeParse(raw);
  if (!parsed.success) return { error: "مبلغ، علت و مرجع درخواست استرداد را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PAYMENT_REFUND_REQUEST);
  if (!supabase) return { error: "مجوز درخواست استرداد وجه را ندارید." };
  const { data, error } = await supabase.rpc("request_repair_payment_refund", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_source_payment_id: input.sourcePaymentId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_amount_irr: input.amountIrr, p_reason: input.reason, p_request_reference: input.requestReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ درخواست استرداد معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function approveRepairPaymentRefundAction(raw: unknown): Promise<ActionResult> {
  const parsed = refundApprovalSchema.safeParse(raw);
  if (!parsed.success) return { error: "روش خروج وجه، رسید و مرجع تأیید را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PAYMENT_REFUND_APPROVE);
  if (!supabase) return { error: "مجوز تأیید استرداد وجه را ندارید." };
  const { data, error } = await supabase.rpc("approve_repair_payment_refund", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_refund_id: input.refundId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_outbound_method: input.outboundMethod, p_outbound_reference: input.outboundReference,
    p_outbound_evidence: input.outboundEvidence, p_approval_reference: input.approvalReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ تأیید استرداد معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function requestRepairPaymentCreditTransferAction(raw: unknown): Promise<ActionResult> {
  const parsed = creditRequestSchema.safeParse(raw);
  if (!parsed.success) return { error: "مبلغ و مراجع درخواست انتقال اعتبار را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PAYMENT_CREDIT_REQUEST);
  if (!supabase) return { error: "مجوز درخواست انتقال اعتبار را ندارید." };
  const { data, error } = await supabase.rpc("request_repair_payment_credit_transfer", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_source_payment_id: input.sourcePaymentId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_amount_irr: input.amountIrr, p_request_reference: input.requestReference,
    p_request_evidence: input.requestEvidence,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ انتقال اعتبار معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function approveRepairPaymentCreditTransferAction(raw: unknown): Promise<ActionResult> {
  const parsed = creditApprovalSchema.safeParse(raw);
  if (!parsed.success) return { error: "مرجع تأیید انتقال اعتبار را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PAYMENT_CREDIT_APPROVE);
  if (!supabase) return { error: "مجوز تأیید انتقال اعتبار را ندارید." };
  const { data, error } = await supabase.rpc("approve_repair_payment_credit_transfer", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_transfer_id: input.transferId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_approval_reference: input.approvalReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ تأیید انتقال اعتبار معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function recordRepairPaymentEvidenceAction(raw: unknown): Promise<ActionResult> {
  const parsed = paymentEvidenceSchema.safeParse(raw);
  if (!parsed.success) return { error: "مبلغ، روش پرداخت و مراجع سند را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PAYMENT_RECORD);
  if (!supabase) return { error: "مجوز ثبت سند پرداخت را ندارید." };
  const { data, error } = await supabase.rpc("record_repair_payment_evidence", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey, p_amount_irr: input.amountIrr, p_method: input.method,
    p_external_reference: input.externalReference, p_evidence_reference: input.evidenceReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ ثبت سند معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function verifyRepairPaymentEvidenceAction(raw: unknown): Promise<ActionResult> {
  const parsed = paymentVerifySchema.safeParse(raw);
  if (!parsed.success) return { error: "مرجع تطبیق پرداخت را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PAYMENT_VERIFY);
  if (!supabase) return { error: "مجوز مستقل تطبیق پرداخت را ندارید." };
  const { data, error } = await supabase.rpc("verify_repair_payment_evidence", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_payment_id: input.paymentId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_verification_reference: input.verificationReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ تطبیق سند معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function correctRepairPaymentEvidenceAction(raw: unknown): Promise<ActionResult> {
  const parsed = paymentCorrectionSchema.safeParse(raw);
  if (!parsed.success) return { error: "دلیل، شرح و مراجع اصلاح سند را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PAYMENT_CORRECT);
  if (!supabase) return { error: "مجوز مستقل اصلاح سند پرداخت را ندارید." };
  const { data, error } = await supabase.rpc("correct_repair_payment_evidence", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_payment_id: input.paymentId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_reason: input.reason, p_explanation: input.explanation,
    p_correction_reference: input.correctionReference, p_evidence_reference: input.evidenceReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ اصلاح سند معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function recordRepairFunctionalTestAction(raw: unknown): Promise<ActionResult> {
  const parsed = functionalTestSchema.safeParse(raw);
  if (!parsed.success) return { error: "برای هر کنترل نتیجه و شاهد یا علت نامرتبط بودن را ثبت کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_FUNCTIONAL_TEST_RECORD);
  if (!supabase) return { error: "مجوز ثبت تست عملکردی را ندارید." };
  const { data, error } = await supabase.rpc(input.route === "replacement"
    ? "record_repair_replacement_functional_test" : "record_repair_functional_test", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey,
    p_identity_status: input.identityStatus, p_identity_evidence: input.identityEvidence,
    p_power_status: input.powerStatus, p_power_evidence: input.powerEvidence,
    p_position_status: input.positionStatus, p_position_evidence: input.positionEvidence,
    p_configuration_status: input.configurationStatus, p_configuration_evidence: input.configurationEvidence,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ ثبت تست معتبر نبود. وضعیت پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function releaseRepairFunctionalTestAction(raw: unknown): Promise<ActionResult> {
  const parsed = functionalTestReleaseSchema.safeParse(raw);
  if (!parsed.success) return { error: "درخواست آزادسازی تست معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_QUALITY_RELEASE);
  if (!supabase) return { error: "مجوز مستقل آزادسازی کیفیت را ندارید." };
  const { data, error } = await supabase.rpc("release_repair_functional_test", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_test_id: input.testId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ آزادسازی تست معتبر نبود. وضعیت پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

const deliveryReceiptSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  recipientName: z.string().trim().min(1).max(160),
  recipientRole: z.enum(["owner", "authorized_representative", "colleague"]),
  authorityReference: z.string().trim().max(240),
  receiptReference: z.string().trim().min(1).max(160),
  receiptEvidence: z.string().trim().min(1).max(240),
}).superRefine((value, ctx) => {
  if (value.recipientRole !== "owner" && !value.authorityReference) {
    ctx.addIssue({ code: "custom", message: "مرجع اختیار گیرنده لازم است." });
  }
});

const deliveryDispatchSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  method: z.enum(["post", "courier"]),
  carrier: z.string().trim().min(1).max(160),
  destinationAddress: z.string().trim().min(1).max(300),
  trackingCode: z.string().trim().min(1).max(240),
  dispatchReference: z.string().trim().min(1).max(160),
  dispatchEvidence: z.string().trim().min(1).max(240),
});
const remoteReceiptSchema = deliveryReceiptSchema.extend({ dispatchId: uuid });
const deliveryIncidentSchema = z.object({
  orgId: uuid, caseId: uuid, dispatchId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  kind: z.enum(["lost", "damage", "delivery_discrepancy"]), reference: z.string().trim().min(1).max(160),
  evidence: z.string().trim().min(1).max(240), responsibleUserId: uuid, dueAt: z.iso.datetime({ offset: true }),
});
const incidentFollowupSchema = z.object({
  orgId: uuid, caseId: uuid, incidentId: uuid, expectedVersion: z.number().int().positive(),
  expectedIncidentVersion: z.number().int().positive(), idempotencyKey: uuid,
  reference: z.string().trim().min(1).max(160), outcome: z.string().trim().min(1).max(1000),
  responsibleUserId: uuid, dueAt: z.iso.datetime({ offset: true }),
});
const incidentResolutionSchema = z.object({
  orgId: uuid, caseId: uuid, incidentId: uuid, expectedVersion: z.number().int().positive(),
  expectedIncidentVersion: z.number().int().positive(), idempotencyKey: uuid,
  resolutionReference: z.string().trim().min(1).max(160), resolutionEvidence: z.string().trim().min(1).max(240),
});

const deliveryDamageReturnSchema = z.object({
  orgId: uuid, caseId: uuid, dispatchId: uuid, incidentId: uuid,
  expectedVersion: z.number().int().positive(), expectedIncidentVersion: z.number().int().positive(),
  idempotencyKey: uuid, location: z.string().trim().min(1).max(200),
  conditionNote: z.string().trim().min(1).max(1000),
  returnReference: z.string().trim().min(1).max(160),
  returnEvidence: z.string().trim().min(1).max(240),
});

const diagnosisSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  findings: z.string().trim().min(1).max(3000),
  technicalCondition: z.enum(["unknown", "needs_repair", "healthy", "irreparable"]),
  recommendedAction: z.enum(["repair", "replacement", "return"]),
  warrantyCoverage: z.enum(["covered", "not_covered", "pending"]),
});

const finalizeDiagnosisSchema = z.object({
  orgId: uuid, caseId: uuid, diagnosisId: uuid,
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});

const planSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  route: z.enum(["repair", "replacement", "return"]),
  scope: z.string().trim().min(1).max(3000),
  financialBasis: z.enum(["warranty", "customer_paid", "none"]),
  amountIrr: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
  partsStrategy: z.enum(["no_parts", "requires_parts"]).nullable(),
  replacementModel: z.string().trim().max(160),
  replacementReason: z.enum(["irreparable", "uneconomical", "policy", "other"]).nullable(),
  originalDisposition: z.enum(["return_to_customer", "scrap_proposed", "refurbish_proposed", "parts_proposed"]).nullable(),
});

const partReceiptSchema = z.object({ orgId: uuid, sku: z.string().trim().min(1).max(64),
  name: z.string().trim().min(1).max(160), quantity: z.number().int().positive(),
  evidenceReference: z.string().trim().min(1).max(240), idempotencyKey: uuid });
const partRequirementSchema = z.object({ orgId: uuid, caseId: uuid, planId: uuid,
  partId: uuid, quantity: z.number().int().positive(), expectedVersion: z.number().int().positive(), idempotencyKey: uuid });
const partReservationSchema = partRequirementSchema.omit({ quantity: true });
const partMovementBase = z.object({ orgId: uuid, caseId: uuid,
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  reference: z.string().trim().min(1).max(240) });
const consumePartSchema = partMovementBase.extend({ planId: uuid, partId: uuid,
  quantity: z.number().int().positive(), actionDescription: z.string().trim().min(1).max(2000) });
const releasePartSchema = partMovementBase.extend({ planId: uuid, partId: uuid,
  reason: z.string().trim().min(1).max(500) });
const returnPartSchema = partMovementBase.extend({ consumptionId: uuid,
  quantity: z.number().int().positive(), reason: z.string().trim().min(1).max(500) });
const quarantineResolutionSchema = z.object({
  orgId: uuid, caseId: uuid, returnMovementId: uuid,
  outcome: z.enum(["released_to_stock", "rejected_hold"]),
  quantity: z.number().int().positive(),
  inspectionNote: z.string().trim().min(1).max(1000),
  evidenceReference: z.string().trim().min(1).max(240),
  decisionReference: z.string().trim().min(1).max(240),
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});

const planApprovalSchema = z.object({
  orgId: uuid, caseId: uuid, planId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  kind: z.enum(["customer", "replacement"]), decision: z.enum(["approved", "rejected"]),
  channel: z.enum(["phone", "message", "chat", "in_person", "agency", "other"]).nullable(),
  subjectName: z.string().trim().max(160),
  subjectRole: z.enum(["owner", "authorized_representative"]).nullable(),
  evidenceReference: z.string().trim().max(240),
  authorityReference: z.string().trim().max(240),
  statedAt: z.iso.datetime({ offset: true }).nullable(),
});

const returnAuthorizationSchema = z.object({
  orgId: uuid, caseId: uuid, planId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  notificationChannel: z.enum(["phone", "message", "chat", "in_person", "agency", "other"]),
  notifiedPerson: z.string().trim().min(1).max(160),
  notificationReference: z.string().trim().min(1).max(240),
  notifiedAt: z.iso.datetime({ offset: true }),
});

function mapDatabaseError(message: string): string {
  if (message.includes("FUNCTIONAL_RELEASE_REQUIRED")) return "ابتدا آخرین آزمون عملکرد موفقِ همین دستگاه را مستقل آزاد کنید.";
  if (message.includes("REPAIR_OUTGOING_NOT_RELEASABLE")) return "فقط آخرین کنترل خروج موفقِ همین تست، دستگاه و نوبت قابل آزادسازی است.";
  if (message.includes("INVALID_REPAIR_OUTGOING_CHECK")) return "نتیجه‌ها، شواهد و اطلاعات گیرنده را بررسی کنید.";
  if (message.includes("PAYMENT_EXCEEDS_PLAN")) return "جمع پرداخت‌های تطبیق‌شده از مبلغ برنامه بیشتر می‌شود.";
  if (message.includes("PAYMENT_HAS_CREDIT_TRANSFER")) return "این رسید به برنامهٔ جدید منتقل شده و دیگر قابل اصلاح سند نیست.";
  if (message.includes("PAYMENT_HAS_REFUND")) return "از این رسید وجه مسترد شده و دیگر قابل اصلاح سند نیست.";
  if (message.includes("REFUND_EXCEEDS_AVAILABLE")) return "مبلغ استرداد از ماندهٔ آزاد رسید بیشتر است.";
  if (message.includes("REFUND_SOURCE_NOT_ELIGIBLE")) return "برای استرداد، رسید باید تطبیق‌شده و اصلاح‌نشده باشد.";
  if (message.includes("REFUND_APPROVAL_NOT_ALLOWED")) return "تأیید استرداد باید توسط فرد دیگری و برای رسید معتبر انجام شود.";
  if (message.includes("PENDING_REFUND_REQUIRED")) return "درخواست استرداد دیگر در انتظار تأیید نیست.";
  if (message.includes("INVALID_REFUND_")) return "مبلغ، علت، رسید خروج وجه و مراجع استرداد را بررسی کنید.";
  if (message.includes("CREDIT_AMOUNT_EXCEEDS_AVAILABLE") || message.includes("CREDIT_SOURCE_EXHAUSTED")) return "مبلغ انتقال از ماندهٔ آزاد رسید قبلی بیشتر است.";
  if (message.includes("CREDIT_EXCEEDS_PLAN")) return "این انتقال از ماندهٔ برنامهٔ جدید بیشتر می‌شود.";
  if (message.includes("CREDIT_APPROVAL_NOT_ALLOWED")) return "تأیید باید توسط فرد دیگری و برای برنامهٔ جاری انجام شود؛ وضعیت رسید را بررسی کنید.";
  if (message.includes("ELIGIBLE_OLD_PAYMENT_REQUIRED")) return "رسید قبلی باید تطبیق‌شده، اصلاح‌نشده و متعلق به نسخهٔ قدیمی‌تر باشد.";
  if (message.includes("PENDING_CREDIT_TRANSFER_REQUIRED")) return "درخواست انتقال دیگر در انتظار تأیید نیست.";
  if (message.includes("INVALID_CREDIT_")) return "مبلغ و مراجع انتقال اعتبار را بررسی کنید.";
  if (message.includes("CURRENT_PAYMENT_REQUIRED")) return "این سند متعلق به نسخهٔ فعلی برنامهٔ پرداختی نیست.";
  if (message.includes("CURRENT_PAID_PLAN_REQUIRED")) return "برای ثبت سند، برنامهٔ پرداختی معتبر در مرحلهٔ فعلی لازم است.";
  if (message.includes("PAYMENT_ALREADY_VERIFIED")) return "این سند قبلاً تطبیق شده است.";
  if (message.includes("PAYMENT_ALREADY_CORRECTED")) return "این سند قبلاً اصلاح و از محاسبه خارج شده است.";
  if (message.includes("INVALID_PAYMENT_CORRECTION")) return "دلیل، شرح و مراجع اصلاح را بررسی کنید.";
  if (message.includes("INVALID_PAYMENT_")) return "مبلغ و مراجع سند یا تطبیق را بررسی کنید.";
  if (message.includes("ACTIVE_REPAIR_CASE_EXISTS")) return "برای این IMEI پروندهٔ باز وجود دارد. پروندهٔ موجود را بررسی کنید؛ استثنا به مجوز، علت و مرجع تأیید نیاز دارد.";
  if (message.includes("CASE_VERSION_CONFLICT")) return "پرونده تغییر کرده است. صفحه را تازه کنید و دوباره بررسی کنید.";
  if (message.includes("INTAKE_INCOMPLETE")) return "برای ارجاع به کارشناسی، دریافت فیزیکی، محل و مسئول دستگاه و یک شناسهٔ قابل پیگیری لازم است.";
  if (message.includes("TRANSITION_NOT_ALLOWED")) return "این جابه‌جایی از مرحلهٔ فعلی مجاز نیست. صفحه را تازه کنید.";
  if (message.includes("FINAL_DIAGNOSIS_REQUIRED")) return "برای ورود به تصمیم، آخرین نسخهٔ تشخیص در همین نوبت کارشناسی باید نهایی شده باشد.";
  if (message.includes("DIAGNOSIS_REVISION_CONFLICT")) return "نسخهٔ تشخیص تغییر کرده یا به نوبت قبلی کارشناسی تعلق دارد. صفحه را تازه کنید.";
  if (message.includes("DIAGNOSIS_CONDITION_UNRESOLVED")) return "برای نهایی‌سازی، وضعیت فنی دستگاه باید مشخص باشد.";
  if (message.includes("DIAGNOSIS_STAGE_REQUIRED")) return "ثبت تشخیص فقط در مرحلهٔ کارشناسی مجاز است.";
  if (message.includes("INVALID_DIAGNOSIS_INPUT")) return "یافته‌ها و گزینه‌های تشخیص را بررسی کنید.";
  if (message.includes("PLAN_DIAGNOSIS_MISMATCH")) return "مسیر پیشنهادی باید با آخرین تشخیص نهایی هماهنگ باشد.";
  if (message.includes("DECISION_STAGE_REQUIRED")) return "ثبت تصمیم فقط در مرحلهٔ تصمیم و هماهنگی مجاز است.";
  if (message.includes("INVALID_PLAN_INPUT")) return "مسیر، مبلغ، مبنای مالی و اطلاعات برنامه را بررسی کنید.";
  if (message.includes("INVALID_APPROVAL_INPUT")) return "شخص پاسخ‌دهنده، روش، زمان و مرجع تأیید را کامل و بررسی کنید.";
  if (message.includes("PLAN_REVISION_CONFLICT")) return "نسخهٔ برنامه عوض شده است. پاسخ یا مصوبه باید برای آخرین نسخه ثبت شود.";
  if (message.includes("REPLACEMENT_PLAN_REQUIRED")) return "مصوبهٔ تعویض فقط برای برنامهٔ تعویض ثبت می‌شود.";
  if (message.includes("CURRENT_PLAN_REQUIRED")) return "برای این انتقال، آخرین نسخهٔ برنامه باید با تشخیص نهایی همین نوبت هماهنگ باشد.";
  if (message.includes("FINANCIAL_BASIS_UNRESOLVED")) return "پوشش گارانتی و مبنای مالی برنامه با هم هماهنگ نیستند.";
  if (message.includes("CUSTOMER_APPROVAL_REQUIRED")) return "رضایت مشتری برای آخرین نسخهٔ برنامه ثبت نشده یا رد شده است.";
  if (message.includes("REPLACEMENT_APPROVAL_REQUIRED")) return "مصوبهٔ مستقل تعویض برای آخرین نسخه ثبت نشده یا رد شده است.";
  if (message.includes("REPLACEMENT_IMEI_EXISTS")) return "این IMEI قبلاً در سازمان ثبت شده است.";
  if (message.includes("REPLACEMENT_STOCK_NOT_ORIGINAL")) return "این دستگاه در موجودی جایگزین ثبت شده و نمی‌تواند دستگاه اصلی پرونده باشد.";
  if (message.includes("REPLACEMENT_STOCK_UNAVAILABLE")) return "دستگاه جایگزین دیگر آزاد نیست یا مدل آن با برنامه یکسان نیست.";
  if (message.includes("REPLACEMENT_ALREADY_ALLOCATED")) return "برای این پرونده دستگاه جایگزین تخصیص داده شده است.";
  if (message.includes("REPLACEMENT_EXECUTION_REQUIRED")) return "اجرای واقعی تعویض دستگاه مشخص هنوز ثبت نشده است.";
  if (message.includes("REPLACEMENT_STAGE_REQUIRED")) return "تخصیص یا اجرای تعویض فقط در مرحلهٔ تعویض مجاز است.";
  if (message.includes("INVALID_REPLACEMENT_")) return "شناسه، مدل، محل، نگهدارنده یا مرجع را بررسی کنید.";
  if (message.includes("PARTS_READINESS_REQUIRED")) return "تعمیر نیازمند قطعه تا ثبت کنترل تأمین و موجودی قابل ارجاع نیست.";
  if (message.includes("PART_WORK_INCOMPLETE")) return "همهٔ قطعات برنامه باید مصرف شده و رزروهای باز بسته شوند.";
  if (message.includes("REPAIR_WORK_REQUIRED")) return "برای تعمیر بدون قطعه، شرح اقدام و مرجع آن لازم است.";
  if (message.includes("REPAIR_COMPLETION_REQUIRED")) return "تکمیل تعمیر برای همین برنامه و دستگاه در نوبت فعلی معتبر نیست.";
  if (message.includes("INVALID_FUNCTIONAL_TEST")) return "برای هر چهار کنترل تست، نتیجه و شاهد معتبر ثبت کنید.";
  if (message.includes("FUNCTIONAL_TEST_NOT_RELEASABLE")) return "فقط آخرین تست موفقِ همین دستگاه، برنامه و نوبت بدون آسیب تازه قابل آزادسازی است.";
  if (message.includes("INVALID_REPAIR_COMPLETION")) return "پروتکل، شرح اقدام و مرجع تعمیر را بررسی کنید.";
  if (message.includes("DEVICE_CUSTODY_UNRESOLVED")) return "موقعیت فیزیکی هر دستگاه را تأیید و انتقال یا مغایرت باز را تعیین تکلیف کنید.";
  if (message.includes("PART_STOCK_INSUFFICIENT")) return "موجودی آزاد این قطعه برای رزرو کافی نیست.";
  if (message.includes("PART_REQUIREMENT_REQUIRED")) return "ابتدا نیاز این قطعه را در برنامه ثبت کنید.";
  if (message.includes("PART_RESERVATION_INSUFFICIENT")) return "ماندهٔ رزرو این قطعه برای مصرف کافی نیست یا قبلاً آزاد شده است.";
  if (message.includes("PART_CONSUMPTION_REQUIRED")) return "حوالهٔ مصرف معتبر برای این پرونده پیدا نشد.";
  if (message.includes("PART_RETURN_EXCEEDS_CONSUMPTION")) return "مقدار بازگشت از ماندهٔ قابل بازگشت این حواله بیشتر است.";
  if (message.includes("PART_QUARANTINE_RETURN_REQUIRED")) return "بازگشت قرنطینهٔ معتبر برای این پرونده پیدا نشد.";
  if (message.includes("QUARANTINE_QUANTITY_EXCEEDED")) return "مقدار تعیین‌تکلیف از ماندهٔ قرنطینه بیشتر است.";
  if (message.includes("QUARANTINE_STAGE_REQUIRED")) return "تعیین تکلیف قطعه فقط در مراحل اجرایی پرونده مجاز است.";
  if (message.includes("INVALID_QUARANTINE_RESOLUTION")) return "نتیجهٔ بررسی، تعداد، شرح و مراجع مدرک را بررسی کنید.";
  if (message.includes("REPAIR_STAGE_REQUIRED")) return "ثبت مصرف و بازگشت قطعه فقط در مرحلهٔ تعمیر مجاز است.";
  if (message.includes("INVALID_PART_MOVEMENT")) return "تعداد، شرح اقدام، علت یا مرجع سند قطعه را بررسی کنید.";
  if (message.includes("PART_CATALOG_CONFLICT")) return "شناسه، نام یا وضعیت قطعه با فهرست موجودی سازگار نیست.";
  if (message.includes("INVALID_PART_INPUT")) return "اطلاعات قطعه یا مرجع ورود را بررسی کنید.";
  if (message.includes("RETURN_AUTHORIZATION_REQUIRED")) return "اطلاع‌رسانی و مجوز عودت برای آخرین نسخهٔ برنامه ثبت نشده است.";
  if (message.includes("INVALID_RETURN_AUTHORIZATION")) return "روش، شخص، زمان و مرجع اطلاع‌رسانی عودت را بررسی کنید.";
  if (message.includes("INVALID_RETURN_QC")) return "برای هر چهار کنترل، نتیجه و مرجع شواهد را ثبت کنید و گیرندهٔ موردنظر را مشخص کنید.";
  if (message.includes("TEST_STAGE_REQUIRED")) return "کنترل خروج فقط در مرحلهٔ تست ثبت و آزاد می‌شود.";
  if (message.includes("VERIFIED_DEVICE_REQUIRED")) return "برای کنترل خروج، IMEI دستگاه باید با برچسب و مدرک تأیید شده باشد.";
  if (message.includes("RETURN_QC_REQUIRED")) return "آخرین کنترل خروج عودت باید برای همین دستگاه و برنامه، کامل و موفق باشد.";
  if (message.includes("REPAIR_PAYMENT_UNSETTLED")) return "مبلغ برنامهٔ تعمیر هنوز به‌طور کامل با مدارک مستقل تأیید نشده است.";
  if (message.includes("REPLACEMENT_PAYMENT_UNSETTLED")) return "مبلغ برنامهٔ تعویض پس از انتقال اعتبار و استرداد وجه هنوز تسویه نشده است.";
  if (message.includes("REPLACEMENT_FINANCIAL_BASIS_UNRESOLVED")) return "مبنای مالی برنامهٔ تعویض برای تحویل کامل نیست.";
  if (message.includes("REPLACEMENT_DELIVERY_STAGE_REQUIRED")) return "ارجاع دستگاه جایگزین به تحویل فقط از مرحلهٔ تست مجاز است.";
  if (message.includes("REPLACEMENT_OUTGOING_RELEASE_REQUIRED")) return "آخرین تست و کنترل خروج دستگاه جایگزین باید موفق و مستقل آزاد شده باشند.";
  if (message.includes("REPAIR_FINANCIAL_BASIS_UNRESOLVED")) return "مبنای مالی برنامهٔ تعمیر برای تحویل معتبر نیست.";
  if (message.includes("REPAIR_OUTGOING_RELEASE_REQUIRED")) return "آخرین تست و کنترل خروج تعمیر باید موفق و مستقل آزاد شده باشند.";
  if (message.includes("REPAIR_DELIVERY_TRANSITION_REQUIRED")) return "ابتدا انتقال معتبر پرونده از تست به تحویل را ثبت کنید.";
  if (message.includes("REPAIR_DELIVERY_STAGE_REQUIRED")) return "این اقدام در مرحلهٔ فعلی پروندهٔ تعمیر مجاز نیست.";
  if (message.includes("QUALITY_RELEASE_REQUIRED")) return "آخرین کنترل خروج هنوز با مجوز مستقل کیفیت آزاد نشده است.";
  if (message.includes("CUSTODY_DAMAGE_RETURN_REQUIRED")) return "بازگشت به تست فقط پس از ثبت رسید بازگشت فیزیکی دستگاه آسیب‌دیده ممکن است.";
  if (message.includes("CUSTODY_DAMAGE_REVIEW_REQUIRED")) return "آسیب‌دیدگی دستگاه باید تعیین تکلیف شود و کنترل خروج و آزادسازی کیفیت تازه ثبت شود.";
  if (message.includes("DELIVERY_STAGE_REQUIRED")) return "ثبت تحویل فقط در مرحلهٔ تحویل مجاز است.";
  if (message.includes("RETURN_ZERO_COST_REQUIRED")) return "این مسیر تحویل فقط برای عودت بدون هزینه است؛ بخش مالی مسیرهای دیگر هنوز تکمیل نشده است.";
  if (message.includes("DELIVERY_QC_REQUIRED")) return "کنترل خروج و آزادسازی کیفیتِ آخرین نسخه برای بستن پرونده لازم است.";
  if (message.includes("DELIVERY_BLOCKERS_OPEN")) return "درخواست واگذاری، انتقال داخلی یا مغایرت باز مانع تحویل و بستن است.";
  if (message.includes("DELIVERY_INCIDENT_OPEN")) return "مسئلهٔ حمل باز است؛ دریافت مقصد و بستن پرونده تا تعیین تکلیف آن مجاز نیست.";
  if (message.includes("DELIVERY_INCIDENT_NOT_OPEN")) return "مسئلهٔ حمل دیگر باز نیست. صفحه را تازه کنید.";
  if (message.includes("DELIVERY_INCIDENT_VERSION_CONFLICT")) return "مسئلهٔ حمل تغییر کرده است. صفحه را تازه کنید.";
  if (message.includes("DELIVERY_DISPATCH_NOT_OPEN")) return "ارسال فعال برای این پرونده پیدا نشد یا دریافت مقصد قبلاً ثبت شده است.";
  if (message.includes("DELIVERY_MEMBER_INACTIVE")) return "مسئول پیگیری باید عضو فعال سازمان باشد.";
  if (message.includes("DELIVERY_DAMAGE_RETURN_NOT_ALLOWED")) return "بازگشت این ارسال مجاز نیست؛ وضعیت ارسال، مسئله و رسید مقصد را بررسی کنید.";
  if (message.includes("DELIVERY_INDEPENDENT_RETURN_REQUIRED")) return "مرجع و مدرک بازگشت باید مستقل از ارسال و ثبت آسیب باشند.";
  if (message.includes("DELIVERY_CUSTODY_BASELINE_REQUIRED")) return "ابتدا موقعیت و مسئول اولیهٔ دستگاه را ثبت کنید.";
  if (message.includes("INVALID_DELIVERY_DAMAGE_RETURN")) return "محل، شرح وضعیت، مرجع و مدرک بازگشت را کامل کنید.";
  if (message.includes("DELIVERY_DAMAGE_RETURN_REQUIRED")) return "آسیب حمل فقط پس از ثبت بازگشت فیزیکی دستگاه برای بازبینی تعیین تکلیف می‌شود.";
  if (message.includes("INVALID_DELIVERY_FOLLOWUP")) return "مرجع، نتیجهٔ پیگیری، مسئول و موعد معتبر را ثبت کنید.";
  if (message.includes("INVALID_DELIVERY_INCIDENT_RESOLUTION")) return "مرجع و مدرک رفع مسئله را بررسی کنید.";
  if (message.includes("INVALID_DELIVERY_INCIDENT")) return "نوع مسئله، مرجع، مدرک، مسئول و موعد را بررسی کنید.";
  if (message.includes("DELIVERY_RECIPIENT_MISMATCH")) return "گیرنده باید با آخرین کنترل خروج یکسان باشد.";
  if (message.includes("DELIVERY_CUSTODIAN_REQUIRED")) return "رسید تحویل را فقط نگهدارندهٔ تأییدشدهٔ دستگاه ثبت می‌کند.";
  if (message.includes("DELIVERY_RECEIPT_REQUIRED")) return "برای بستن پرونده، رسید دریافت واقعیِ همین دستگاه لازم است.";
  if (message.includes("DELIVERY_ALREADY_RECEIVED")) return "رسید تحویل قبلاً ثبت شده است.";
  if (message.includes("DELIVERY_ALREADY_DISPATCHED")) return "حوالهٔ ارسال قبلاً ثبت شده است.";
  if (message.includes("DELIVERY_DISPATCH_MISMATCH")) return "رسید باید به همان ارسال، دستگاه و گیرندهٔ مقصد مربوط باشد.";
  if (message.includes("DELIVERY_INDEPENDENT_RECEIPT_REQUIRED")) return "مرجع و مدرک دریافت مقصد باید مستقل از مدرک خروج باشند.";
  if (message.includes("INVALID_DELIVERY_DISPATCH")) return "روش حمل، حامل، نشانی مقصد، کد رهگیری و مدرک خروج را بررسی کنید.";
  if (message.includes("DELIVERY_DEVICE_ALREADY_RELEASED")) return "دستگاه از مسیر تحویل خارج شده و انتقال داخلی تازه برای همین پرونده مجاز نیست.";
  if (message.includes("REPAIR_DELIVERY_TRANSFER_BLOCKED")) return "جابجایی داخلی دستگاه تعمیرشده باید پیش از ارجاع به تحویل انجام شود.";
  if (message.includes("INVALID_DELIVERY_RECEIPT")) return "گیرنده، اختیار، مرجع و مدرک مستقل دریافت را بررسی کنید.";
  if (message.includes("QUALITY_ALREADY_RELEASED")) return "این نسخهٔ کنترل خروج قبلاً آزاد شده است.";
  if (message.includes("ASSIGNMENT_TARGET_INACTIVE")) return "عضو مقصد فعال نیست یا از سازمان خارج شده است.";
  if (message.includes("CUSTODY_BASELINE_LOCATION_MISMATCH")) return "محل مبنا باید با محل ثبت‌شده در دریافت دستگاه یکسان باشد.";
  if (message.includes("CUSTODY_BASELINE_EXISTS")) return "مبنای محل دستگاه قبلاً تأیید شده است. صفحه را تازه کنید.";
  if (message.includes("CUSTODY_BASELINE_REQUIRED")) return "ابتدا محل و نگهدارندهٔ فعلی دستگاه را با مدرک تأیید کنید.";
  if (message.includes("CUSTODY_MEMBER_INACTIVE")) return "نگهدارنده یا گیرندهٔ انتخاب‌شده عضو فعال سازمان نیست.";
  if (message.includes("CUSTODY_SOURCE_MISMATCH")) return "خروج باید به نام نگهدارندهٔ تأییدشدهٔ فعلی ثبت شود.";
  if (message.includes("CUSTODY_SAME_DESTINATION")) return "مقصد و گیرنده با موقعیت فعلی یکسان‌اند.";
  if (message.includes("CUSTODY_TRANSFER_OPEN")) return "برای این دستگاه حوالهٔ باز وجود دارد؛ ابتدا دریافت یا بازگشت آن را ثبت کنید.";
  if (message.includes("CUSTODY_TRANSFER_NOT_OPEN")) return "حواله دیگر باز نیست یا به این دستگاه و پرونده تعلق ندارد.";
  if (message.includes("CUSTODY_ACTOR_MISMATCH")) return "رسید مقصد را فقط گیرنده و بازگشت را فقط نگهدارندهٔ مبدأ ثبت می‌کند.";
  if (message.includes("CUSTODY_SOURCE_CHANGED")) return "موقعیت مبدأ پس از خروج تغییر کرده است. پرونده را تازه کنید.";
  if (message.includes("CUSTODY_DISCREPANCY_OPEN")) return "مغایرت این حواله باز است؛ پیش از پذیرش مقصد باید تعیین تکلیف شود.";
  if (message.includes("CUSTODY_DISCREPANCY_RETURN_REQUIRED")) return "آسیب‌دیدگی فقط پس از ثبت رسید بازگشت واقعی به مبدأ تعیین تکلیف می‌شود.";
  if (message.includes("CUSTODY_DISCREPANCY_NOT_OPEN")) return "مغایرت دیگر باز نیست یا به این پرونده تعلق ندارد.";
  if (message.includes("CUSTODY_TRANSFER_VERSION_CONFLICT") || message.includes("CUSTODY_DISCREPANCY_VERSION_CONFLICT")) return "حواله یا مغایرت تغییر کرده است. صفحه را تازه کنید.";
  if (message.includes("INVALID_CUSTODY_DISCREPANCY")) return "نوع مغایرت، مسئول، موعد و مراجع مدرک را بررسی کنید.";
  if (message.includes("INVALID_CUSTODY_")) return "محل، شخص، حامل یا مراجع مدرک را بررسی کنید.";
  if (message.includes("ASSIGNMENT_PENDING")) return "برای این پرونده یک درخواست واگذاری باز وجود دارد.";
  if (message.includes("ASSIGNMENT_NOT_PENDING")) return "درخواست دیگر باز نیست یا مسئول فعلی تغییر کرده است.";
  if (message.includes("ASSIGNMENT_ACTOR_MISMATCH")) return "این پاسخ فقط توسط گیرندهٔ درخواست یا ارسال‌کنندهٔ مجاز ثبت می‌شود.";
  if (message.includes("INVALID_ASSIGNMENT_RESOLUTION")) return "برای رد یا پس‌گرفتن، علت و مرجع یکتا را وارد کنید.";
  if (message.includes("INVALID_ASSIGNMENT")) return "عضو مقصد و مرجع درخواست را بررسی کنید؛ پروندهٔ بسته یا واگذاری به مسئول فعلی مجاز نیست.";
  if (message.includes("RETURN_ALREADY_AUTHORIZED")) return "مجوز عودت برای این نسخه قبلاً ثبت شده است.";
  if (message.includes("RECEIPT_ALREADY_RECORDED")) return "دریافت این دستگاه قبلاً ثبت شده است.";
  if (message.includes("IDENTITY_CORRECTION_REQUIRED")) return "IMEI روی برچسب با شناسهٔ اولیه متفاوت است. ابتدا اصلاح اطلاعات را در فرایند مستقل ثبت کنید.";
  if (message.includes("IMEI_EVIDENCE_REQUIRED")) return "عکس معتبر برچسب، متعلق به همین پرونده و بارگذار، یافت نشد. دوباره بارگذاری کنید.";
  if (message.includes("DUPLICATE_OVERRIDE_NOT_APPLICABLE")) return "برای این دستگاه پروندهٔ باز دیگری پیدا نشد؛ اطلاعات استثنا را حذف کنید.";
  if (message.includes("PERMISSION_DENIED")) return "مجوز این عملیات را ندارید.";
  if (message.includes("IDEMPOTENCY_KEY_REUSED")) return "اطلاعات پس از ارسال تغییر کرده است. صفحه را تازه کنید و دوباره ثبت کنید.";
  return "عملیات ثبت نشد. اطلاعات را بررسی کنید و دوباره تلاش کنید.";
}

async function authorized(orgId: string, permission: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data: allowed } = await supabase.rpc("has_permission", {
    p_org_id: orgId,
    p_permission_key: permission,
  });
  return allowed ? supabase : null;
}

export async function receiveRepairPartAction(raw: unknown): Promise<{ error?: string }> {
  const parsed = partReceiptSchema.safeParse(raw);
  if (!parsed.success) return { error: "شناسه، نام، تعداد و مرجع ورود قطعه را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PART_RECEIVE);
  if (!supabase) return { error: "مجوز ثبت ورود قطعه را ندارید." };
  const { error } = await supabase.rpc("receive_repair_part", {
    p_org_id: input.orgId, p_sku: input.sku, p_name: input.name,
    p_quantity: input.quantity, p_evidence_reference: input.evidenceReference,
    p_idempotency_key: input.idempotencyKey });
  if (error) return { error: mapDatabaseError(error.message) };
  revalidatePath(`/${input.orgId}/repairs`);
  return {};
}

export async function requireRepairPartAction(raw: unknown): Promise<{ error?: string }> {
  const parsed = partRequirementSchema.safeParse(raw);
  if (!parsed.success) return { error: "قطعه و تعداد موردنیاز را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PART_REQUIRE);
  if (!supabase) return { error: "مجوز تعیین قطعهٔ برنامه را ندارید." };
  const { error } = await supabase.rpc("require_repair_part", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_plan_id: input.planId,
    p_part_id: input.partId, p_quantity: input.quantity,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey });
  if (error) return { error: mapDatabaseError(error.message) };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return {};
}

export async function reserveRepairPartAction(raw: unknown): Promise<{ error?: string }> {
  const parsed = partReservationSchema.safeParse(raw);
  if (!parsed.success) return { error: "درخواست رزرو قطعه معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PART_RESERVE);
  if (!supabase) return { error: "مجوز رزرو قطعه را ندارید." };
  const { error } = await supabase.rpc("reserve_repair_part", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_plan_id: input.planId,
    p_part_id: input.partId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey });
  if (error) return { error: mapDatabaseError(error.message) };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return {};
}

export async function consumeRepairPartAction(raw: unknown): Promise<{ error?: string }> {
  const parsed = consumePartSchema.safeParse(raw);
  if (!parsed.success) return { error: "تعداد، شرح اقدام و مرجع حوالهٔ مصرف را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PART_CONSUME);
  if (!supabase) return { error: "مجوز ثبت مصرف قطعه را ندارید." };
  const { error } = await supabase.rpc("consume_repair_part", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_plan_id: input.planId,
    p_part_id: input.partId, p_quantity: input.quantity,
    p_action_description: input.actionDescription, p_reference: input.reference,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey });
  if (error) return { error: mapDatabaseError(error.message) };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return {};
}

export async function releaseUnusedRepairPartAction(raw: unknown): Promise<{ error?: string }> {
  const parsed = releasePartSchema.safeParse(raw);
  if (!parsed.success) return { error: "علت و مرجع آزادسازی را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PART_RELEASE);
  if (!supabase) return { error: "مجوز آزادسازی قطعه را ندارید." };
  const { error } = await supabase.rpc("release_unused_repair_part", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_plan_id: input.planId,
    p_part_id: input.partId, p_reason: input.reason, p_reference: input.reference,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey });
  if (error) return { error: mapDatabaseError(error.message) };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return {};
}

export async function returnConsumedRepairPartAction(raw: unknown): Promise<{ error?: string }> {
  const parsed = returnPartSchema.safeParse(raw);
  if (!parsed.success) return { error: "تعداد، علت و مرجع بازگشت را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PART_RETURN);
  if (!supabase) return { error: "مجوز ثبت بازگشت قطعه را ندارید." };
  const { error } = await supabase.rpc("return_consumed_repair_part", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_consumption_id: input.consumptionId,
    p_quantity: input.quantity, p_reason: input.reason, p_reference: input.reference,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey });
  if (error) return { error: mapDatabaseError(error.message) };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return {};
}

export async function resolveRepairPartQuarantineAction(raw: unknown): Promise<{ error?: string }> {
  const parsed = quarantineResolutionSchema.safeParse(raw);
  if (!parsed.success) return { error: "نتیجه، تعداد، شرح بررسی و مراجع آن را کامل کنید." };
  const input = parsed.data;
  const permission = input.outcome === "released_to_stock"
    ? PERMISSIONS.REPAIR_PART_QUARANTINE_RESTOCK : PERMISSIONS.REPAIR_PART_QUARANTINE_REJECT;
  const supabase = await authorized(input.orgId, permission);
  if (!supabase) return { error: "مجوز این نوع تعیین تکلیف قطعه را ندارید." };
  const { error } = await supabase.rpc("resolve_repair_part_quarantine", {
    p_org_id: input.orgId, p_case_id: input.caseId,
    p_return_movement_id: input.returnMovementId, p_outcome: input.outcome,
    p_quantity: input.quantity, p_inspection_note: input.inspectionNote,
    p_evidence_reference: input.evidenceReference, p_decision_reference: input.decisionReference,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return {};
}

export async function createRepairCaseAction(raw: unknown): Promise<ActionResult> {
  const parsed = createSchema.safeParse(raw);
  if (!parsed.success) return { error: "مدل دستگاه، نام مشتری، شرح ایراد و گزینه‌های لازم را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_CASE_CREATE);
  if (!supabase) return { error: "مجوز ثبت پرونده را ندارید." };
  const { data, error } = await supabase.rpc("create_repair_case", {
    p_org_id: input.orgId,
    p_device_model: input.deviceModel,
    p_raw_identifier: input.rawIdentifier || null,
    p_customer_name: input.customerName,
    p_issue: input.issue,
    p_priority: input.priority,
    p_source: input.source,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ ثبت پرونده معتبر نبود. پیش از ارسال دوباره، فهرست پرونده‌ها را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs`);
  return { caseId: data.caseId };
}

export async function receiveRepairDeviceAction(raw: unknown): Promise<ActionResult> {
  const parsed = receiptSchema.safeParse(raw);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "اطلاعات دریافت دستگاه را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_CASE_RECEIVE);
  if (!supabase) return { error: "مجوز دریافت دستگاه را ندارید." };
  const { data, error } = await supabase.rpc("receive_repair_device", {
    p_org_id: input.orgId,
    p_case_id: input.caseId,
    p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey,
    p_method: input.method,
    p_location: input.location,
    p_custodian: input.custodian,
    p_items: input.items,
    p_verified_imei: input.verifiedImei || null,
    p_imei_evidence: input.imeiEvidence || null,
    p_duplicate_reason: input.duplicateReason || null,
    p_duplicate_reference: input.duplicateReference || null,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ دریافت معتبر نبود. پیش از ارسال دوباره، وضعیت پرونده را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function transitionRepairCaseAction(raw: unknown): Promise<ActionResult> {
  const parsed = transitionSchema.safeParse(raw);
  if (!parsed.success) return { error: "درخواست تغییر مرحله معتبر نیست." };
  const input = parsed.data;
  const permission = input.transitionCode === "T01"
    ? PERMISSIONS.REPAIR_TRANSITION_TO_DIAGNOSIS
    : input.transitionCode === "T02" ? PERMISSIONS.REPAIR_TRANSITION_TO_DECISION
    : input.transitionCode === "T03" ? PERMISSIONS.REPAIR_TRANSITION_TO_REPAIR
    : input.transitionCode === "T04" ? PERMISSIONS.REPAIR_TRANSITION_TO_REPLACEMENT
    : input.transitionCode === "T05" ? PERMISSIONS.REPAIR_TRANSITION_TO_RETURN_TEST
    : input.transitionCode === "T08" ? PERMISSIONS.REPAIR_TRANSITION_TO_DELIVERY
    : input.transitionCode === "T11" ? PERMISSIONS.REPAIR_TRANSITION_TO_RETEST_AFTER_DAMAGE
    : input.transitionCode === "T09" ? PERMISSIONS.REPAIR_CASE_CLOSE
    : PERMISSIONS.REPAIR_TRANSITION_TO_INTAKE;
  const supabase = await authorized(input.orgId, permission);
  if (!supabase) return { error: "مجوز این جابه‌جایی را ندارید." };
  const { data: deliveryPlan } = input.transitionCode === "T08" || input.transitionCode === "T09"
    ? await supabase.from("repair_action_plans").select("route")
      .eq("org_id", input.orgId).eq("case_id", input.caseId)
      .order("revision", { ascending: false }).limit(1).maybeSingle()
    : { data: null };
  const repairedDelivery = deliveryPlan?.route === "repair";
  const replacementDelivery = deliveryPlan?.route === "replacement";
  const { data, error } = input.transitionCode === "T09" && repairedDelivery
    ? await supabase.rpc("close_repaired_case", {
      p_org_id: input.orgId, p_case_id: input.caseId,
      p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    })
    : input.transitionCode === "T08" && repairedDelivery
    ? await supabase.rpc("advance_repaired_case_to_delivery", {
      p_org_id: input.orgId, p_case_id: input.caseId,
      p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    })
    : input.transitionCode === "T08" && replacementDelivery
    ? await supabase.rpc("advance_replacement_case_to_delivery", {
      p_org_id: input.orgId, p_case_id: input.caseId,
      p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    })
    : input.transitionCode === "T09"
    ? await supabase.rpc("close_repair_return_case", {
      p_org_id: input.orgId, p_case_id: input.caseId,
      p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    })
    : input.transitionCode === "T11"
    ? await supabase.rpc("return_repair_case_to_test_after_damage", {
      p_org_id: input.orgId, p_case_id: input.caseId,
      p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    })
    : await supabase.rpc("transition_repair_case", {
      p_org_id: input.orgId, p_case_id: input.caseId,
      p_expected_version: input.expectedVersion,
      p_transition_code: input.transitionCode,
      p_idempotency_key: input.idempotencyKey,
    });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ تغییر مرحله معتبر نبود. وضعیت پرونده را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function recordRepairDeliveryReceiptAction(raw: unknown): Promise<ActionResult> {
  const parsed = deliveryReceiptSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات رسید تحویل معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DELIVERY_RECEIVE);
  if (!supabase) return { error: "مجوز ثبت رسید تحویل را ندارید." };
  const { data: deliveryPlan } = await supabase.from("repair_action_plans").select("route")
    .eq("org_id", input.orgId).eq("case_id", input.caseId)
    .order("revision", { ascending: false }).limit(1).maybeSingle();
  const { data, error } = await supabase.rpc(deliveryPlan?.route === "repair"
    ? "record_repaired_delivery_receipt" : "record_repair_delivery_receipt", {
    p_org_id: input.orgId, p_case_id: input.caseId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_recipient_name: input.recipientName, p_recipient_role: input.recipientRole,
    p_authority_reference: input.recipientRole === "owner" ? null : input.authorityReference,
    p_receipt_reference: input.receiptReference, p_receipt_evidence: input.receiptEvidence,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ رسید معتبر نبود. وضعیت پرونده را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function recordRepairDeliveryDispatchAction(raw: unknown): Promise<ActionResult> {
  const parsed = deliveryDispatchSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات حوالهٔ ارسال معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DELIVERY_DISPATCH);
  if (!supabase) return { error: "مجوز ثبت خروج پستی یا پیک را ندارید." };
  const { data: deliveryPlan } = await supabase.from("repair_action_plans").select("route")
    .eq("org_id", input.orgId).eq("case_id", input.caseId)
    .order("revision", { ascending: false }).limit(1).maybeSingle();
  const { data, error } = await supabase.rpc(deliveryPlan?.route === "repair"
    ? "record_repaired_delivery_dispatch" : "record_repair_delivery_dispatch", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey, p_method: input.method, p_carrier: input.carrier,
    p_destination_address: input.destinationAddress, p_tracking_code: input.trackingCode,
    p_dispatch_reference: input.dispatchReference, p_dispatch_evidence: input.dispatchEvidence,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ ارسال معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function confirmRepairDeliveryReceiptAction(raw: unknown): Promise<ActionResult> {
  const parsed = remoteReceiptSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات رسید مقصد معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DELIVERY_CONFIRM_RECEIPT);
  if (!supabase) return { error: "مجوز تأیید دریافت مقصد را ندارید." };
  const { data: deliveryPlan } = await supabase.from("repair_action_plans").select("route")
    .eq("org_id", input.orgId).eq("case_id", input.caseId)
    .order("revision", { ascending: false }).limit(1).maybeSingle();
  const { data, error } = await supabase.rpc(deliveryPlan?.route === "repair"
    ? "confirm_repaired_delivery_receipt" : "confirm_repair_delivery_receipt", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_dispatch_id: input.dispatchId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_recipient_name: input.recipientName, p_recipient_role: input.recipientRole,
    p_authority_reference: input.recipientRole === "owner" ? null : input.authorityReference,
    p_receipt_reference: input.receiptReference, p_receipt_evidence: input.receiptEvidence,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ رسید مقصد معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function recordRepairDeliveryIncidentAction(raw: unknown): Promise<ActionResult> {
  const parsed = deliveryIncidentSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات مسئلهٔ حمل معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DELIVERY_INCIDENT_RECORD);
  if (!supabase) return { error: "مجوز ثبت مسئلهٔ حمل را ندارید." };
  const { data, error } = await supabase.rpc("record_repair_delivery_incident", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_dispatch_id: input.dispatchId,
    p_kind: input.kind, p_reference: input.reference, p_evidence: input.evidence,
    p_responsible_user_id: input.responsibleUserId, p_due_at: input.dueAt,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ ثبت مسئله معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function followupRepairDeliveryIncidentAction(raw: unknown): Promise<ActionResult> {
  const parsed = incidentFollowupSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات پیگیری معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DELIVERY_INCIDENT_FOLLOWUP);
  if (!supabase) return { error: "مجوز پیگیری مسئلهٔ حمل را ندارید." };
  const { data, error } = await supabase.rpc("followup_repair_delivery_incident", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_incident_id: input.incidentId,
    p_expected_version: input.expectedVersion, p_expected_incident_version: input.expectedIncidentVersion,
    p_reference: input.reference, p_outcome: input.outcome,
    p_responsible_user_id: input.responsibleUserId, p_due_at: input.dueAt,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ پیگیری معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function resolveRepairDeliveryIncidentAction(raw: unknown): Promise<ActionResult> {
  const parsed = incidentResolutionSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات رفع مسئله معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DELIVERY_INCIDENT_RESOLVE);
  if (!supabase) return { error: "مجوز رفع مسئلهٔ حمل را ندارید." };
  const { data, error } = await supabase.rpc("resolve_repair_delivery_incident", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_incident_id: input.incidentId,
    p_expected_version: input.expectedVersion, p_expected_incident_version: input.expectedIncidentVersion,
    p_resolution_reference: input.resolutionReference, p_resolution_evidence: input.resolutionEvidence,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ رفع مسئله معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function receiveRepairDeliveryDamageReturnAction(raw: unknown): Promise<ActionResult> {
  const parsed = deliveryDamageReturnSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات بازگشت فیزیکی معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DELIVERY_RETURN_RECEIVE);
  if (!supabase) return { error: "مجوز ثبت بازگشت فیزیکی از حمل را ندارید." };
  const { data, error } = await supabase.rpc("receive_repair_delivery_damage_return", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_dispatch_id: input.dispatchId,
    p_incident_id: input.incidentId, p_expected_version: input.expectedVersion,
    p_expected_incident_version: input.expectedIncidentVersion, p_idempotency_key: input.idempotencyKey,
    p_location: input.location, p_condition_note: input.conditionNote,
    p_return_reference: input.returnReference, p_return_evidence: input.returnEvidence,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ بازگشت معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function saveRepairDiagnosisAction(raw: unknown): Promise<ActionResult> {
  const parsed = diagnosisSchema.safeParse(raw);
  if (!parsed.success) return { error: "یافته‌ها و گزینه‌های تشخیص را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DIAGNOSIS_RECORD);
  if (!supabase) return { error: "مجوز ثبت تشخیص را ندارید." };
  const { data, error } = await supabase.rpc("save_repair_diagnosis", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey, p_findings: input.findings,
    p_technical_condition: input.technicalCondition,
    p_recommended_action: input.recommendedAction, p_warranty_coverage: input.warrantyCoverage,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ ثبت تشخیص معتبر نبود. وضعیت پرونده را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function finalizeRepairDiagnosisAction(raw: unknown): Promise<ActionResult> {
  const parsed = finalizeDiagnosisSchema.safeParse(raw);
  if (!parsed.success) return { error: "درخواست نهایی‌سازی معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_DIAGNOSIS_FINALIZE);
  if (!supabase) return { error: "مجوز نهایی‌سازی تشخیص را ندارید." };
  const { data, error } = await supabase.rpc("finalize_repair_diagnosis", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_diagnosis_id: input.diagnosisId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ نهایی‌سازی معتبر نبود. وضعیت پرونده را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function saveRepairActionPlanAction(raw: unknown): Promise<ActionResult> {
  const parsed = planSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات برنامهٔ اقدام را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_PLAN_RECORD);
  if (!supabase) return { error: "مجوز ثبت برنامهٔ اقدام را ندارید." };
  const { data, error } = await supabase.rpc("save_repair_action_plan", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey, p_route: input.route, p_scope: input.scope,
    p_financial_basis: input.financialBasis, p_amount_irr: input.amountIrr,
    p_parts_strategy: input.route === "repair" ? input.partsStrategy : null,
    p_replacement_model: input.route === "replacement" ? input.replacementModel : null,
    p_replacement_reason: input.route === "replacement" ? input.replacementReason : null,
    p_original_disposition: input.route === "replacement" ? input.originalDisposition : null,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ ثبت برنامه معتبر نبود. وضعیت پرونده را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function recordRepairPlanApprovalAction(raw: unknown): Promise<ActionResult> {
  const parsed = planApprovalSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات پاسخ یا مصوبه را بررسی کنید." };
  const input = parsed.data;
  const permission = input.kind === "customer"
    ? PERMISSIONS.REPAIR_CUSTOMER_APPROVAL_RECORD : PERMISSIONS.REPAIR_REPLACEMENT_APPROVE;
  const supabase = await authorized(input.orgId, permission);
  if (!supabase) return { error: "مجوز ثبت این تأیید را ندارید." };
  const { data, error } = await supabase.rpc("record_repair_plan_approval", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_plan_id: input.planId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_kind: input.kind, p_decision: input.decision,
    p_channel: input.kind === "customer" ? input.channel : null,
    p_subject_name: input.kind === "customer" ? input.subjectName : null,
    p_subject_role: input.kind === "customer" ? input.subjectRole : null,
    p_evidence_reference: input.kind === "customer" ? input.evidenceReference : null,
    p_authority_reference: input.kind === "customer" ? input.authorityReference || null : null,
    p_stated_at: input.kind === "customer" ? input.statedAt : null,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ ثبت تأیید معتبر نبود. وضعیت پرونده را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function recordRepairReturnAuthorizationAction(raw: unknown): Promise<ActionResult> {
  const parsed = returnAuthorizationSchema.safeParse(raw);
  if (!parsed.success) return { error: "اطلاعات اطلاع‌رسانی و مجوز عودت را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_RETURN_AUTHORIZE);
  if (!supabase) return { error: "مجوز عودت بدون تعمیر را ندارید." };
  const { data, error } = await supabase.rpc("record_repair_return_authorization", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_plan_id: input.planId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_notification_channel: input.notificationChannel,
    p_notified_person: input.notifiedPerson,
    p_notification_reference: input.notificationReference,
    p_notified_at: input.notifiedAt,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string") {
    return { error: "پاسخ ثبت مجوز عودت معتبر نبود. وضعیت پرونده را بررسی کنید." };
  }
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

const outgoingQcSchema = z.object({
  orgId: uuid, caseId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
  identityPass: z.boolean(), identityEvidence: z.string().trim().min(1).max(500),
  itemsPass: z.boolean(), itemsEvidence: z.string().trim().min(1).max(500),
  conditionPass: z.boolean(), conditionEvidence: z.string().trim().min(1).max(500),
  transportPass: z.boolean(), transportEvidence: z.string().trim().min(1).max(500),
  intendedRecipient: z.string().trim().min(1).max(160),
  recipientRole: z.enum(["owner", "authorized_representative", "colleague"]),
  authorityReference: z.string().trim().max(240),
}).superRefine((value, ctx) => {
  if (value.recipientRole !== "owner" && !value.authorityReference) {
    ctx.addIssue({ code: "custom", message: "برای نماینده یا همکار، مرجع اختیار تحویل را وارد کنید." });
  }
});

const outgoingReleaseSchema = z.object({
  orgId: uuid, caseId: uuid, checkId: uuid, expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});

export async function recordRepairReturnOutgoingCheckAction(raw: unknown): Promise<ActionResult> {
  const parsed = outgoingQcSchema.safeParse(raw);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "اطلاعات کنترل خروج را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_RETURN_QC_RECORD);
  if (!supabase) return { error: "مجوز ثبت کنترل خروج را ندارید." };
  const { data, error } = await supabase.rpc("record_repair_return_outgoing_check", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey,
    p_identity_pass: input.identityPass, p_identity_evidence: input.identityEvidence,
    p_items_pass: input.itemsPass, p_items_evidence: input.itemsEvidence,
    p_condition_pass: input.conditionPass, p_condition_evidence: input.conditionEvidence,
    p_transport_pass: input.transportPass, p_transport_evidence: input.transportEvidence,
    p_intended_recipient: input.intendedRecipient, p_recipient_role: input.recipientRole,
    p_authority_reference: input.recipientRole === "owner" ? null : input.authorityReference,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ کنترل خروج معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function releaseRepairReturnOutgoingCheckAction(raw: unknown): Promise<ActionResult> {
  const parsed = outgoingReleaseSchema.safeParse(raw);
  if (!parsed.success) return { error: "درخواست آزادسازی معتبر نیست." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_QUALITY_RELEASE);
  if (!supabase) return { error: "مجوز آزادسازی کیفیت را ندارید." };
  const { data, error } = await supabase.rpc("release_repair_return_outgoing_check", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_check_id: input.checkId,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ آزادسازی معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

const assignmentRequestSchema = z.object({
  orgId: uuid, caseId: uuid, targetUserId: uuid, requestReference: z.string().trim().min(1).max(160),
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});
const assignmentResolutionSchema = z.object({
  orgId: uuid, caseId: uuid, requestId: uuid,
  decision: z.enum(["accepted", "rejected", "withdrawn"]),
  reason: z.string().trim().max(500), resolutionReference: z.string().trim().max(160),
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
}).superRefine((value, ctx) => {
  if (value.decision !== "accepted" && (!value.reason || !value.resolutionReference)) {
    ctx.addIssue({ code: "custom", message: "علت و مرجع رد یا پس‌گرفتن را وارد کنید." });
  }
});

export async function requestRepairCaseAssignmentAction(raw: unknown): Promise<ActionResult> {
  const parsed = assignmentRequestSchema.safeParse(raw);
  if (!parsed.success) return { error: "عضو مقصد و مرجع درخواست را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_CASE_ASSIGN);
  if (!supabase) return { error: "مجوز درخواست واگذاری را ندارید." };
  const { data, error } = await supabase.rpc("request_repair_case_assignment", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_target_user_id: input.targetUserId,
    p_request_reference: input.requestReference, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ واگذاری معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function resolveRepairCaseAssignmentAction(raw: unknown): Promise<ActionResult> {
  const parsed = assignmentResolutionSchema.safeParse(raw);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "پاسخ واگذاری معتبر نیست." };
  const input = parsed.data;
  const permission = input.decision === "accepted" ? PERMISSIONS.REPAIR_ASSIGNMENT_ACCEPT
    : input.decision === "rejected" ? PERMISSIONS.REPAIR_ASSIGNMENT_REJECT
    : PERMISSIONS.REPAIR_ASSIGNMENT_WITHDRAW;
  const supabase = await authorized(input.orgId, permission);
  if (!supabase) return { error: "مجوز این پاسخ را ندارید." };
  const { data, error } = await supabase.rpc("resolve_repair_case_assignment", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_request_id: input.requestId,
    p_decision: input.decision, p_reason: input.decision === "accepted" ? null : input.reason,
    p_resolution_reference: input.decision === "accepted" ? null : input.resolutionReference,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ واگذاری معتبر نبود. وضعیت پرونده را بررسی کنید." };
  revalidatePath(`/${input.orgId}/repairs`);
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

const custodyBaselineSchema = z.object({ orgId: uuid, caseId: uuid,
  location: z.string().trim().min(1).max(200), custodianUserId: uuid,
  evidence: z.string().trim().min(1).max(240),
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});
const custodyReleaseSchema = z.object({ orgId: uuid, caseId: uuid,
  destinationLocation: z.string().trim().min(1).max(200), destinationUserId: uuid,
  carrier: z.string().trim().min(1).max(160), releaseReference: z.string().trim().min(1).max(160),
  releaseEvidence: z.string().trim().min(1).max(240),
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});
const custodyResolutionSchema = z.object({ orgId: uuid, caseId: uuid, transferId: uuid,
  outcome: z.enum(["accepted", "returned"]), reference: z.string().trim().min(1).max(160),
  evidence: z.string().trim().min(1).max(240),
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});

export async function recordRepairDeviceCustodyBaselineAction(raw: unknown): Promise<ActionResult> {
  const parsed = custodyBaselineSchema.safeParse(raw);
  if (!parsed.success) return { error: "محل، نگهدارنده و مدرک مبنا را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_CUSTODY_BASELINE);
  if (!supabase) return { error: "مجوز ثبت مبنای نگهداری را ندارید." };
  const { data, error } = await supabase.rpc("record_repair_device_custody_baseline", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_location: input.location,
    p_custodian_user_id: input.custodianUserId, p_evidence: input.evidence,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ ثبت مبنا معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function releaseRepairDeviceCustodyAction(raw: unknown): Promise<ActionResult> {
  const parsed = custodyReleaseSchema.safeParse(raw);
  if (!parsed.success) return { error: "مقصد، حامل و مرجع حواله را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_CUSTODY_RELEASE);
  if (!supabase) return { error: "مجوز خروج داخلی دستگاه را ندارید." };
  const { data, error } = await supabase.rpc("release_repair_device_custody", {
    p_org_id: input.orgId, p_case_id: input.caseId,
    p_destination_location: input.destinationLocation, p_destination_user_id: input.destinationUserId,
    p_carrier: input.carrier, p_release_reference: input.releaseReference,
    p_release_evidence: input.releaseEvidence, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ خروج معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  revalidatePath(`/${input.orgId}/repairs`);
  return { caseId: data.caseId };
}

export async function resolveRepairDeviceCustodyAction(raw: unknown): Promise<ActionResult> {
  const parsed = custodyResolutionSchema.safeParse(raw);
  if (!parsed.success) return { error: "مرجع و مدرک دریافت یا بازگشت را بررسی کنید." };
  const input = parsed.data;
  const permission = input.outcome === "accepted" ? PERMISSIONS.REPAIR_CUSTODY_ACCEPT : PERMISSIONS.REPAIR_CUSTODY_RETURN;
  const supabase = await authorized(input.orgId, permission);
  if (!supabase) return { error: "مجوز ثبت این رسید را ندارید." };
  const { data, error } = await supabase.rpc("resolve_repair_device_custody", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_transfer_id: input.transferId,
    p_outcome: input.outcome, p_reference: input.reference, p_evidence: input.evidence,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ رسید معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  revalidatePath(`/${input.orgId}/repairs`);
  return { caseId: data.caseId };
}

export async function releaseRepairReplacementCustodyAction(raw: unknown): Promise<ActionResult> {
  const parsed = custodyReleaseSchema.extend({ deviceId: uuid }).safeParse(raw);
  if (!parsed.success) return { error: "مقصد، حامل و مرجع حواله را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_CUSTODY_RELEASE);
  if (!supabase) return { error: "مجوز خروج داخلی دستگاه را ندارید." };
  const { data, error } = await supabase.rpc("release_repair_replacement_custody", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_device_id: input.deviceId,
    p_destination_location: input.destinationLocation, p_destination_user_id: input.destinationUserId,
    p_carrier: input.carrier, p_release_reference: input.releaseReference,
    p_release_evidence: input.releaseEvidence, p_expected_version: input.expectedVersion,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ خروج معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

export async function resolveRepairReplacementCustodyAction(raw: unknown): Promise<ActionResult> {
  const parsed = custodyResolutionSchema.safeParse(raw);
  if (!parsed.success) return { error: "مرجع و مدرک دریافت یا بازگشت را بررسی کنید." };
  const input = parsed.data;
  const permission = input.outcome === "accepted" ? PERMISSIONS.REPAIR_CUSTODY_ACCEPT : PERMISSIONS.REPAIR_CUSTODY_RETURN;
  const supabase = await authorized(input.orgId, permission);
  if (!supabase) return { error: "مجوز ثبت این رسید را ندارید." };
  const { data, error } = await supabase.rpc("resolve_repair_replacement_custody", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_transfer_id: input.transferId,
    p_outcome: input.outcome, p_reference: input.reference, p_evidence: input.evidence,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ رسید معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}

const custodyDiscrepancySchema = z.object({ orgId: uuid, caseId: uuid, transferId: uuid,
  kind: z.enum(["identity_mismatch", "destination_mismatch", "damage"]),
  reference: z.string().trim().min(1).max(160), evidence: z.string().trim().min(1).max(240),
  responsibleUserId: uuid, dueAt: z.iso.datetime({ offset: true }),
  expectedVersion: z.number().int().positive(), expectedTransferVersion: z.number().int().positive(),
  idempotencyKey: uuid,
});
const custodyDiscrepancyResolutionSchema = z.object({ orgId: uuid, caseId: uuid, discrepancyId: uuid,
  reference: z.string().trim().min(1).max(160), evidence: z.string().trim().min(1).max(240),
  expectedVersion: z.number().int().positive(), expectedTransferVersion: z.number().int().positive(),
  expectedDiscrepancyVersion: z.number().int().positive(), idempotencyKey: uuid,
});

export async function recordRepairCustodyDiscrepancyAction(raw: unknown): Promise<ActionResult> {
  const parsed = custodyDiscrepancySchema.safeParse(raw);
  if (!parsed.success) return { error: "نوع مغایرت، مسئول، موعد و مدرک را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_CUSTODY_DISCREPANCY_RECORD);
  if (!supabase) return { error: "مجوز ثبت مغایرت پذیرش را ندارید." };
  const { data, error } = await supabase.rpc("record_repair_custody_discrepancy", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_transfer_id: input.transferId,
    p_kind: input.kind, p_reference: input.reference, p_evidence: input.evidence,
    p_responsible_user_id: input.responsibleUserId, p_due_at: input.dueAt,
    p_expected_version: input.expectedVersion, p_expected_transfer_version: input.expectedTransferVersion,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ ثبت مغایرت معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  revalidatePath(`/${input.orgId}/repairs`);
  return { caseId: data.caseId };
}

export async function resolveRepairCustodyDiscrepancyAction(raw: unknown): Promise<ActionResult> {
  const parsed = custodyDiscrepancyResolutionSchema.safeParse(raw);
  if (!parsed.success) return { error: "مرجع و مدرک رفع مغایرت را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_CUSTODY_DISCREPANCY_RESOLVE);
  if (!supabase) return { error: "مجوز رفع مغایرت پذیرش را ندارید." };
  const { data, error } = await supabase.rpc("resolve_repair_custody_discrepancy", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_discrepancy_id: input.discrepancyId,
    p_reference: input.reference, p_evidence: input.evidence,
    p_expected_version: input.expectedVersion, p_expected_transfer_version: input.expectedTransferVersion,
    p_expected_discrepancy_version: input.expectedDiscrepancyVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ رفع مغایرت معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  revalidatePath(`/${input.orgId}/repairs`);
  return { caseId: data.caseId };
}

const replacementStockSchema = z.object({
  orgId: uuid, caseId: uuid, imei: z.string().regex(/^\d{15}$/),
  model: z.string().trim().min(1).max(160), location: z.string().trim().min(1).max(200),
  custodianUserId: uuid, evidence: z.string().trim().min(1).max(240),
  receiptReference: z.string().trim().min(1).max(160), idempotencyKey: uuid,
});
const replacementAllocationSchema = z.object({
  orgId: uuid, caseId: uuid, deviceId: uuid, planId: uuid,
  allocationReference: z.string().trim().min(1).max(160),
  expectedVersion: z.number().int().positive(), idempotencyKey: uuid,
});

export async function receiveRepairReplacementStockAction(raw: unknown): Promise<ActionResult> {
  const parsed = replacementStockSchema.safeParse(raw);
  if (!parsed.success) return { error: "شناسه، مدل، محل و مدرک دستگاه جایگزین را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_REPLACEMENT_STOCK_RECEIVE);
  if (!supabase) return { error: "مجوز دریافت دستگاه جایگزین را ندارید." };
  const { error } = await supabase.rpc("receive_repair_replacement_stock", {
    p_org_id: input.orgId, p_imei: input.imei, p_model: input.model,
    p_location: input.location, p_custodian_user_id: input.custodianUserId,
    p_evidence: input.evidence, p_receipt_reference: input.receiptReference,
    p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: input.caseId };
}

export async function allocateRepairReplacementDeviceAction(raw: unknown): Promise<ActionResult> {
  const parsed = replacementAllocationSchema.safeParse(raw);
  if (!parsed.success) return { error: "دستگاه و مرجع تخصیص را بررسی کنید." };
  const input = parsed.data;
  const supabase = await authorized(input.orgId, PERMISSIONS.REPAIR_REPLACEMENT_STOCK_ALLOCATE);
  if (!supabase) return { error: "مجوز تخصیص دستگاه جایگزین را ندارید." };
  const { data, error } = await supabase.rpc("allocate_repair_replacement_device", {
    p_org_id: input.orgId, p_case_id: input.caseId, p_device_id: input.deviceId,
    p_plan_id: input.planId, p_allocation_reference: input.allocationReference,
    p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
  });
  if (error) return { error: mapDatabaseError(error.message) };
  if (!data || typeof data !== "object" || Array.isArray(data) || typeof data.caseId !== "string")
    return { error: "پاسخ تخصیص معتبر نبود. پرونده را تازه کنید." };
  revalidatePath(`/${input.orgId}/repairs/${input.caseId}`);
  return { caseId: data.caseId };
}
