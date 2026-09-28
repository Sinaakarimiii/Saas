import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getOrgContext } from "@/lib/org-context";
import { createClient } from "@/lib/supabase/server";
import { PERMISSIONS } from "@/lib/permissions";
import { formatJalaliDateTime } from "@/lib/jalali";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ReceiptForm } from "./receipt-form";
import { StageTransition } from "./stage-transition";
import { DiagnosisForm } from "./diagnosis-form";
import { DecisionPanel } from "./decision-panel";
import { ReturnAuthorizationForm } from "./return-authorization-form";
import { ReturnOutgoingCheck } from "./return-outgoing-check";
import { AssignmentPanel } from "./assignment-panel";
import { PartsPanel } from "./parts-panel";
import { RepairExecutionPanel } from "./repair-execution-panel";
import { RepairCompletionPanel } from "./repair-completion-panel";
import { RepairFunctionalTest } from "./repair-functional-test";
import { RepairOutgoingCheck } from "./repair-outgoing-check";
import { RepairPaymentPanel } from "./repair-payment-panel";
import { RepairCreditTransferPanel } from "./repair-credit-transfer-panel";
import { RepairRefundPanel } from "./repair-refund-panel";
import { QuarantinePanel } from "./quarantine-panel";
import { CustodyPanel } from "./custody-panel";
import { ReplacementStockPanel } from "./replacement-stock-panel";
import { ReplacementCustodyPanel } from "./replacement-custody-panel";
import { ReplacementExecutionPanel } from "./replacement-execution-panel";
import { ReplacementScrap } from "./replacement-scrap";
import { ReplacementWarehouseReceipt } from "./replacement-warehouse-receipt";
import { ReplacementOriginalReturn } from "./replacement-original-return";
import { DeliveryReceipt } from "./delivery-receipt";
import { DeliveryShipment } from "./delivery-shipment";
import { DeliveryIncidentPanel } from "./delivery-incident-panel";

const stages = ["پذیرش", "کارشناسی", "تصمیم", "تعمیر / تعویض", "تست", "تحویل", "بسته‌شده"] as const;
const stageIndex: Record<string, number> = {
  intake: 0, diagnosis: 1, decision: 2, repair: 3, replacement: 3,
  test: 4, delivery: 5, closed: 6,
};
const receiptNames: Record<string, string> = {
  walk_in: "حضوری", post: "پستی", courier: "پیک", agency: "نمایندگی", internal: "داخلی",
};
const conditionNames: Record<string, string> = { unknown: "نامشخص", needs_repair: "نیازمند تعمیر", healthy: "سالم / ایراد مشاهده نشد", irreparable: "غیرقابل تعمیر" };
const actionNames: Record<string, string> = { repair: "تعمیر", replacement: "تعویض", return: "عودت بدون تعمیر" };
const coverageNames: Record<string, string> = { covered: "مشمول گارانتی", not_covered: "خارج از گارانتی", pending: "در انتظار تعیین پوشش" };
const eventNames: Record<string, string> = {
  created: "پرونده ثبت شد", received: "دستگاه دریافت شد",
  imei_verified: "IMEI با برچسب تطبیق داده شد", duplicate_override: "استثنای پروندهٔ تکراری ثبت شد",
  stage_transition: "مرحلهٔ پرونده تغییر کرد",
  diagnosis_saved: "نسخهٔ تشخیص ثبت شد", diagnosis_finalized: "تشخیص نهایی شد",
  plan_saved: "نسخهٔ برنامهٔ اقدام ثبت شد", plan_approval_recorded: "پاسخ یا مصوبهٔ برنامه ثبت شد",
  return_authorized: "اطلاع‌رسانی و مجوز عودت ثبت شد",
  return_outgoing_checked: "کنترل خروج عودت ثبت شد", return_outgoing_released: "کنترل خروج عودت آزاد شد",
  functional_test_recorded: "آزمون عملکرد دستگاه ثبت شد", functional_test_released: "آزمون عملکرد دستگاه آزاد شد",
  repair_outgoing_checked: "کنترل خروج دستگاه ثبت شد", repair_outgoing_released: "کنترل خروج دستگاه آزاد شد",
  payment_recorded: "سند پرداخت ثبت شد", payment_verified: "سند پرداخت تطبیق شد",
  payment_corrected: "سند پرداخت اشتباه اصلاح شد",
  payment_credit_requested: "درخواست انتقال اعتبار ثبت شد", payment_credit_approved: "انتقال اعتبار تأیید شد",
  payment_refund_requested: "درخواست استرداد وجه ثبت شد", payment_refund_approved: "خروج وجه و استرداد تأیید شد",
  assignment_requested: "درخواست واگذاری مسئولیت ثبت شد", assignment_accepted: "واگذاری مسئولیت پذیرفته شد",
  assignment_rejected: "درخواست واگذاری رد شد", assignment_withdrawn: "درخواست واگذاری پس گرفته شد",
  part_required: "نیاز قطعه ثبت شد", part_reserved: "قطعه رزرو شد",
  part_reservation_released: "رزرو برنامهٔ قبلی آزاد شد",
  part_consumed: "مصرف قطعه ثبت شد", part_returned_quarantine: "قطعه به قرنطینه بازگشت",
  part_unused_released: "ماندهٔ رزرو قطعه آزاد شد",
  part_quarantine_resolved: "قطعهٔ قرنطینه تعیین تکلیف شد",
  custody_baseline_recorded: "موقعیت فعلی دستگاه تأیید شد",
  custody_released: "دستگاه برای انتقال داخلی خارج شد",
  custody_accepted: "دستگاه در مقصد دریافت شد",
  custody_returned: "دستگاه به مبدأ بازگشت",
  custody_discrepancy_recorded: "مغایرت پذیرش داخلی ثبت شد",
  custody_discrepancy_resolved: "مغایرت پذیرش داخلی تعیین تکلیف شد",
  delivery_received: "رسید دریافت واقعی دستگاه ثبت شد",
  delivery_dispatched: "دستگاه به حامل ارسال شد",
  delivery_incident_recorded: "مسئلهٔ حمل ثبت شد",
  delivery_incident_followed_up: "پیگیری حمل ثبت شد",
  delivery_incident_resolved: "مسئلهٔ حمل رفع شد",
  delivery_damage_returned: "دستگاه آسیب‌دیده از حمل بازگشت",
  replacement_allocated: "دستگاه جایگزین مشخص تخصیص یافت",
};

export default async function RepairDetailPage({ params }: PageProps<"/[orgId]/repairs/[caseId]">) {
  const { orgId, caseId } = await params;
  const ctx = await getOrgContext(orgId);
  if (!ctx.can(PERMISSIONS.REPAIR_CASE_VIEW)) redirect(`/${orgId}/dashboard`);
  const supabase = await createClient();
  const { data: repair, error } = await supabase.from("repair_cases")
    .select("id, org_id, tracking_code, assigned_to, customer_name, device_model, raw_identifier, issue, priority, source, stage, stage_entered_at, version, custody_damage_epoch, created_at, received_at, receipt_method, receipt_items, device_location, device_custodian, verified_device_id, imei_evidence, imei_verified_at, duplicate_exception_reason, duplicate_exception_reference")
    .eq("org_id", orgId).eq("id", caseId).maybeSingle();
  if (error) throw new Error("Could not load repair case", { cause: error });
  if (!repair) notFound();
  const [{ data: activeMembers, error: membersError }, { data: assignmentRequests, error: assignmentError }] = await Promise.all([
    supabase.from("org_members").select("user_id, profiles(full_name, email)")
      .eq("org_id", orgId).eq("invitation_status", "active").is("deleted_at", null),
    supabase.from("repair_case_assignment_requests")
      .select("id, from_user_id, target_user_id, requested_by, request_reference, requested_at, status, resolution_reason, resolution_reference, resolved_at")
      .eq("org_id", orgId).eq("case_id", caseId).order("requested_at", { ascending: false }).limit(20),
  ]);
  if (membersError || assignmentError) throw new Error("Could not load case assignments", { cause: membersError ?? assignmentError });
  const assignmentMembers = (activeMembers ?? []).map((member) => ({
    id: member.user_id, label: member.profiles?.full_name || member.profiles?.email || member.user_id,
  }));
  const [{ data: custodyPosition, error: custodyPositionError }, { data: custodyTransfers, error: custodyTransferError },
    { data: custodyDiscrepancies, error: custodyDiscrepancyError }] = repair.verified_device_id
    ? await Promise.all([
      supabase.from("repair_device_custody_positions")
        .select("case_id, location, custodian_user_id, custodian_label, holder_kind, external_reference, confirmed_at")
        .eq("org_id", orgId).eq("device_id", repair.verified_device_id).maybeSingle(),
      supabase.from("repair_device_custody_transfers")
        .select("id, case_id, source_location, source_custodian_user_id, source_custodian_label, destination_location, destination_user_id, destination_label, carrier, release_reference, release_evidence, released_at, status, version, resolution_reference, resolution_evidence, resolved_at")
        .eq("org_id", orgId).eq("device_id", repair.verified_device_id)
        .order("released_at", { ascending: false }).limit(20),
      supabase.from("repair_device_custody_discrepancies")
        .select("id, transfer_id, kind, reference, evidence, responsible_user_id, due_at, recorded_at, status, version, resolution_reference, resolution_evidence, resolved_at")
        .eq("org_id", orgId).eq("device_id", repair.verified_device_id)
        .order("recorded_at", { ascending: false }).limit(20),
    ]) : [{ data: null, error: null }, { data: [], error: null }, { data: [], error: null }];
  if (custodyPositionError || custodyTransferError || custodyDiscrepancyError) throw new Error("Could not load device custody", { cause: custodyPositionError ?? custodyTransferError ?? custodyDiscrepancyError });
  const { count: openDamageCount, error: openDamageError } = repair.verified_device_id
    ? await supabase.from("repair_device_custody_discrepancies")
      .select("id", { count: "exact", head: true }).eq("org_id", orgId)
      .eq("device_id", repair.verified_device_id).eq("kind", "damage").eq("status", "open")
    : { count: 0, error: null };
  if (openDamageError) throw new Error("Could not load open damage", { cause: openDamageError });

  const [{ data: events }, { data: device }, { data: latestDiagnosis }, { data: latestPlan, error: planError }] = await Promise.all([
    supabase.from("repair_case_events").select("id, event_type, occurred_at, details").eq("org_id", orgId).eq("case_id", caseId).order("occurred_at", { ascending: false }),
    repair.verified_device_id
      ? supabase.from("repair_devices").select("imei").eq("org_id", orgId).eq("id", repair.verified_device_id).maybeSingle()
      : Promise.resolve({ data: null }),
    supabase.from("repair_diagnoses")
      .select("id, revision, status, findings, technical_condition, recommended_action, warranty_coverage, created_at, finalized_at")
      .eq("org_id", orgId).eq("case_id", caseId).order("revision", { ascending: false }).limit(1).maybeSingle(),
    supabase.from("repair_action_plans")
      .select("id, diagnosis_id, created_at, revision, route, scope, financial_basis, amount_irr, parts_strategy, replacement_model, replacement_reason, original_disposition")
      .eq("org_id", orgId).eq("case_id", caseId).order("revision", { ascending: false }).limit(1).maybeSingle(),
  ]);
  if (planError) throw new Error("Could not load repair action plan", { cause: planError });
  const paidPlanVisible = latestPlan?.financial_basis === "customer_paid"
    && ["decision", "repair", "replacement", "test", "delivery"].includes(repair.stage);
  const [{ data: paymentEvidence, error: paymentError }, { data: paymentVerifications, error: verificationError }, { data: paymentCorrections, error: correctionError }] = paidPlanVisible
    ? await Promise.all([
      supabase.from("repair_payment_evidence")
        .select("id, amount_irr, method, external_reference, evidence_reference, recorded_at")
        .eq("org_id", orgId).eq("case_id", caseId).eq("plan_id", latestPlan.id)
        .order("recorded_at", { ascending: false }),
      supabase.from("repair_payment_verifications")
        .select("payment_id, verification_reference")
        .eq("org_id", orgId).eq("case_id", caseId),
      supabase.from("repair_payment_corrections")
        .select("payment_id, reason, explanation, correction_reference, evidence_reference, corrected_at")
        .eq("org_id", orgId).eq("case_id", caseId),
    ]) : [{ data: [], error: null }, { data: [], error: null }, { data: [], error: null }];
  if (paymentError || verificationError || correctionError) throw new Error("Could not load repair payments", { cause: paymentError ?? verificationError ?? correctionError });
  const [{ data: oldPaymentEvidence, error: oldPaymentError }, { data: creditTransfers, error: creditTransferError }] = paidPlanVisible && latestPlan
    ? await Promise.all([
      supabase.from("repair_payment_evidence")
        .select("id, plan_id, amount_irr, external_reference")
        .eq("org_id", orgId).eq("case_id", caseId).neq("plan_id", latestPlan.id),
      supabase.from("repair_payment_credit_transfers")
        .select("id, source_payment_id, target_plan_id, amount_irr, request_reference, request_evidence, requested_by, requested_at, approval_reference, approved_by, approved_at")
        .eq("org_id", orgId).eq("case_id", caseId).order("requested_at", { ascending: false }),
    ]) : [{ data: [], error: null }, { data: [], error: null }];
  if (oldPaymentError || creditTransferError) throw new Error("Could not load repair credit transfers", { cause: oldPaymentError ?? creditTransferError });
  const paymentHistoryVisible = ["decision", "repair", "replacement", "test", "delivery", "closed"].includes(repair.stage);
  const [{ data: allPayments, error: allPaymentsError }, { data: allVerifications, error: allVerificationsError },
    { data: allCorrections, error: allCorrectionsError }, { data: allTransfers, error: allTransfersError },
    { data: refunds, error: refundsError }] = paymentHistoryVisible
    ? await Promise.all([
      supabase.from("repair_payment_evidence").select("id, plan_id, amount_irr, external_reference")
        .eq("org_id", orgId).eq("case_id", caseId),
      supabase.from("repair_payment_verifications").select("payment_id")
        .eq("org_id", orgId).eq("case_id", caseId),
      supabase.from("repair_payment_corrections").select("payment_id")
        .eq("org_id", orgId).eq("case_id", caseId),
      supabase.from("repair_payment_credit_transfers").select("source_payment_id, amount_irr, approved_at")
        .eq("org_id", orgId).eq("case_id", caseId),
      supabase.from("repair_payment_refunds")
        .select("id, source_payment_id, amount_irr, reason, request_reference, requested_by, requested_at, outbound_method, outbound_reference, outbound_evidence, approval_reference, approved_by, approved_at")
        .eq("org_id", orgId).eq("case_id", caseId).order("requested_at", { ascending: false }),
    ]) : [{ data: [], error: null }, { data: [], error: null }, { data: [], error: null },
      { data: [], error: null }, { data: [], error: null }];
  if (allPaymentsError || allVerificationsError || allCorrectionsError || allTransfersError || refundsError)
    throw new Error("Could not load repair refund history", { cause: allPaymentsError ?? allVerificationsError ?? allCorrectionsError ?? allTransfersError ?? refundsError });
  const { data: planApprovals, error: approvalsError } = latestPlan
    ? await supabase.from("repair_plan_approvals").select("id, kind, decision, recorded_at")
      .eq("org_id", orgId).eq("case_id", caseId).eq("plan_id", latestPlan.id)
      .order("recorded_at", { ascending: false }).order("id", { ascending: false })
    : { data: [], error: null };
  if (approvalsError) throw new Error("Could not load repair plan approvals", { cause: approvalsError });
  const { data: replacementStock, error: replacementStockError } = repair.stage === "replacement" && latestPlan?.route === "replacement"
    ? await supabase.from("repair_replacement_stock")
      .select("device_id, model, location, custodian_user_id, custodian_label, status, allocated_case_id, repair_devices(imei)")
      .eq("org_id", orgId).eq("model", latestPlan.replacement_model!)
      .or(`status.eq.available,allocated_case_id.eq.${caseId}`).order("received_at", { ascending: true })
    : { data: [], error: null };
  if (replacementStockError) throw new Error("Could not load replacement stock", { cause: replacementStockError });
  const allocatedReplacement = (replacementStock ?? []).find((item) => item.allocated_case_id === caseId) ?? null;
  const [{ data: replacementTransfers, error: replacementTransferError },
    { data: replacementDiscrepancies, error: replacementDiscrepancyError }] = allocatedReplacement
    ? await Promise.all([
      supabase.from("repair_device_custody_transfers")
        .select("id, source_location, destination_location, source_custodian_user_id, destination_user_id, status, release_reference, resolution_reference, version")
        .eq("org_id", orgId).eq("device_id", allocatedReplacement.device_id)
        .order("released_at", { ascending: false }).limit(20),
      supabase.from("repair_device_custody_discrepancies")
        .select("id, transfer_id, kind, reference, evidence, responsible_user_id, due_at, status, version, resolution_reference")
        .eq("org_id", orgId).eq("device_id", allocatedReplacement.device_id)
        .order("recorded_at", { ascending: false }).limit(20),
    ]) : [{ data: [], error: null }, { data: [], error: null }];
  if (replacementTransferError || replacementDiscrepancyError) throw new Error("Could not load replacement custody", { cause: replacementTransferError ?? replacementDiscrepancyError });
  const needsParts = latestPlan?.route === "repair" && latestPlan.parts_strategy === "requires_parts";
  const [{ data: stockParts, error: stockError }, { data: partRequirements, error: requirementError },
    { data: activeReservations, error: reservationError }] = needsParts ? await Promise.all([
    supabase.from("repair_parts").select("id, sku, name, on_hand").eq("org_id", orgId).eq("active", true).order("sku"),
    supabase.from("repair_plan_part_requirements").select("part_id, quantity").eq("org_id", orgId).eq("plan_id", latestPlan.id),
    supabase.from("repair_part_reservations").select("part_id, plan_id, quantity, consumed_quantity").eq("org_id", orgId).eq("status", "active"),
  ]) : [{ data: [] }, { data: [] }, { data: [] }];
  if (stockError || requirementError || reservationError) throw new Error("Could not load repair parts", { cause: stockError ?? requirementError ?? reservationError });
  const parts = (stockParts ?? []).map((part) => ({ ...part,
    free: part.on_hand - (activeReservations ?? []).filter((item) => item.part_id === part.id)
      .reduce((sum, item) => sum + item.quantity - item.consumed_quantity, 0),
  }));
  const requirements = (partRequirements ?? []).map((item) => ({ ...item,
    reserved: (activeReservations ?? []).some((reservation) => reservation.plan_id === latestPlan?.id
      && reservation.part_id === item.part_id && reservation.quantity === item.quantity),
  }));
  const partsReady = !needsParts || (requirements.length > 0 && requirements.every((item) => item.reserved));
  const [{ data: executionReservations, error: executionReservationError },
    { data: partMovements, error: movementError }] = ["repair", "test", "delivery"].includes(repair.stage) && needsParts ? await Promise.all([
    supabase.from("repair_part_reservations")
      .select("id, part_id, quantity, consumed_quantity, status")
      .eq("org_id", orgId).eq("case_id", caseId).eq("plan_id", latestPlan.id),
    supabase.from("repair_part_movements")
      .select("id, part_id, kind, quantity, reference, action_description, reason, source_consumption_id, recorded_at")
      .eq("org_id", orgId).eq("case_id", caseId).eq("plan_id", latestPlan.id)
      .order("recorded_at", { ascending: false }),
  ]) : [{ data: [] }, { data: [] }];
  if (executionReservationError || movementError) throw new Error("Could not load repair execution", { cause: executionReservationError ?? movementError });
  const repairPartsComplete = !needsParts || (requirements.length > 0
    && requirements.every((item) => (executionReservations ?? []).some((reservation) =>
      reservation.part_id === item.part_id && reservation.quantity === item.quantity
      && reservation.consumed_quantity === item.quantity && reservation.status === "consumed"))
    && !(executionReservations ?? []).some((reservation) => reservation.status === "active"));
  const repairCustodyBlocked = (custodyTransfers ?? []).some((transfer) => transfer.status === "in_transit")
    || (custodyDiscrepancies ?? []).some((discrepancy) => discrepancy.status === "open");
  const { data: quarantineResolutions, error: quarantineError } = ["repair", "test", "delivery"].includes(repair.stage) && needsParts
    ? await supabase.from("repair_part_quarantine_resolutions")
      .select("id, return_movement_id, outcome, quantity, inspection_note, evidence_reference, decision_reference")
      .eq("org_id", orgId).eq("case_id", caseId).eq("plan_id", latestPlan.id)
      .order("decided_at", { ascending: false })
    : { data: [], error: null };
  if (quarantineError) throw new Error("Could not load quarantine decisions", { cause: quarantineError });
  const { data: returnAuthorization, error: returnAuthorizationError } = latestPlan?.route === "return"
    ? await supabase.from("repair_return_authorizations")
      .select("id, plan_id, notification_channel, notified_person, notification_reference, notified_at, protocol_code")
      .eq("org_id", orgId).eq("case_id", caseId).eq("plan_id", latestPlan.id).maybeSingle()
    : { data: null, error: null };
  if (returnAuthorizationError) throw new Error("Could not load return authorization", { cause: returnAuthorizationError });
  const { data: repairCompletion, error: repairCompletionError } = repair.stage === "test" && latestPlan?.route === "repair"
    ? await supabase.from("repair_completions")
      .select("id, plan_id, device_id, completed_at, protocol_code")
      .eq("org_id", orgId).eq("case_id", caseId).order("completed_at", { ascending: false }).limit(1).maybeSingle()
    : { data: null, error: null };
  if (repairCompletionError) throw new Error("Could not load repair completion", { cause: repairCompletionError });
  const { data: replacementExecution, error: replacementExecutionError } = ["test", "delivery", "closed"].includes(repair.stage) && latestPlan?.route === "replacement"
    ? await supabase.from("repair_replacement_executions")
      .select("id, plan_id, original_device_id, replacement_device_id, executed_at")
      .eq("org_id", orgId).eq("case_id", caseId).order("executed_at", { ascending: false }).limit(1).maybeSingle()
    : { data: null, error: null };
  if (replacementExecutionError) throw new Error("Could not load replacement execution", { cause: replacementExecutionError });
  const [{ data: replacementTestPosition, error: replacementTestPositionError },
    { data: replacementTestStock, error: replacementTestStockError }] = replacementExecution
    ? await Promise.all([
      supabase.from("repair_device_custody_positions")
        .select("case_id, location, custodian_user_id, holder_kind, external_reference")
        .eq("org_id", orgId).eq("device_id", replacementExecution.replacement_device_id).maybeSingle(),
      supabase.from("repair_replacement_stock")
        .select("status, allocated_case_id, allocated_plan_id, location, custodian_user_id")
        .eq("org_id", orgId).eq("device_id", replacementExecution.replacement_device_id).maybeSingle(),
    ]) : [{ data: null, error: null }, { data: null, error: null }];
  if (replacementTestPositionError || replacementTestStockError)
    throw new Error("Could not load replacement stock position", { cause: replacementTestPositionError ?? replacementTestStockError });
  const { data: replacementDevice, error: replacementDeviceError } = replacementExecution
    ? await supabase.from("repair_devices").select("imei")
      .eq("org_id", orgId).eq("id", replacementExecution.replacement_device_id).maybeSingle()
    : { data: null, error: null };
  if (replacementDeviceError) throw new Error("Could not load replacement identity", { cause: replacementDeviceError });
  const [{ data: replacementTestTransfers, error: replacementTestTransferError },
    { data: replacementTestDiscrepancies, error: replacementTestDiscrepancyError }] = replacementExecution
    ? await Promise.all([
      supabase.from("repair_device_custody_transfers").select("id")
        .eq("org_id", orgId).eq("device_id", replacementExecution.replacement_device_id).eq("status", "in_transit"),
      supabase.from("repair_device_custody_discrepancies").select("id")
        .eq("org_id", orgId).eq("device_id", replacementExecution.replacement_device_id).eq("status", "open"),
    ]) : [{ data: [], error: null }, { data: [], error: null }];
  if (replacementTestTransferError || replacementTestDiscrepancyError)
    throw new Error("Could not load replacement test custody", { cause: replacementTestTransferError ?? replacementTestDiscrepancyError });
  const { data: functionalTest, error: functionalTestError } = ["test", "delivery"].includes(repair.stage) && ["repair", "replacement"].includes(latestPlan?.route ?? "")
    ? await supabase.from("repair_functional_tests")
      .select("id, revision, plan_id, completion_id, execution_id, device_id, custody_damage_epoch, passed, recorded_at, identity_status, identity_evidence, power_status, power_evidence, position_status, position_evidence, configuration_status, configuration_evidence")
      .eq("org_id", orgId).eq("case_id", caseId).order("revision", { ascending: false }).limit(1).maybeSingle()
    : { data: null, error: null };
  if (functionalTestError) throw new Error("Could not load functional test", { cause: functionalTestError });
  const { data: functionalRelease, error: functionalReleaseError } = functionalTest
    ? await supabase.from("repair_functional_test_releases").select("id")
      .eq("org_id", orgId).eq("case_id", caseId).eq("test_id", functionalTest.id).maybeSingle()
    : { data: null, error: null };
  if (functionalReleaseError) throw new Error("Could not load functional test release", { cause: functionalReleaseError });
  const currentFunctionalRelease = Boolean(functionalRelease && functionalTest?.passed && latestPlan
    && functionalTest.plan_id === latestPlan.id
    && (latestPlan.route === "repair"
      ? functionalTest.completion_id === repairCompletion?.id && functionalTest.device_id === repair.verified_device_id
      : latestPlan.route === "replacement" && functionalTest.execution_id === replacementExecution?.id
        && functionalTest.device_id === replacementExecution?.replacement_device_id)
    && functionalTest.custody_damage_epoch === repair.custody_damage_epoch
    && new Date(functionalTest.recorded_at).getTime() >= new Date(repair.stage_entered_at).getTime());
  const { data: repairOutgoingCheck, error: repairOutgoingError } = ["test", "delivery"].includes(repair.stage) && ["repair", "replacement"].includes(latestPlan?.route ?? "")
    ? await supabase.from("repair_outgoing_checks")
      .select("id, revision, protocol_code, plan_id, functional_test_id, device_id, custody_damage_epoch, recorded_at, identity_pass, identity_evidence, items_pass, items_evidence, condition_pass, condition_evidence, transport_pass, transport_evidence, intended_recipient, recipient_role, authority_reference")
      .eq("org_id", orgId).eq("case_id", caseId).order("revision", { ascending: false }).limit(1).maybeSingle()
    : { data: null, error: null };
  if (repairOutgoingError) throw new Error("Could not load repair outgoing control", { cause: repairOutgoingError });
  const { data: repairOutgoingRelease, error: repairOutgoingReleaseError } = repairOutgoingCheck
    ? await supabase.from("repair_outgoing_releases").select("id")
      .eq("org_id", orgId).eq("case_id", caseId).eq("check_id", repairOutgoingCheck.id).maybeSingle()
    : { data: null, error: null };
  if (repairOutgoingReleaseError) throw new Error("Could not load repair outgoing release", { cause: repairOutgoingReleaseError });
  const { data: outgoingCheck, error: outgoingCheckError } = ["test", "delivery"].includes(repair.stage) && latestPlan?.route === "return"
    ? await supabase.from("repair_return_outgoing_checks")
      .select("id, revision, plan_id, authorization_id, device_id, custody_damage_epoch, identity_pass, identity_evidence, items_pass, items_evidence, condition_pass, condition_evidence, transport_pass, transport_evidence, intended_recipient, recipient_role, authority_reference, created_at")
      .eq("org_id", orgId).eq("case_id", caseId).order("revision", { ascending: false }).limit(1).maybeSingle()
    : { data: null, error: null };
  if (outgoingCheckError) throw new Error("Could not load return outgoing check", { cause: outgoingCheckError });
  const { data: outgoingRelease, error: outgoingReleaseError } = outgoingCheck
    ? await supabase.from("repair_return_outgoing_releases").select("id")
      .eq("org_id", orgId).eq("case_id", caseId).eq("check_id", outgoingCheck.id).maybeSingle()
    : { data: null, error: null };
  if (outgoingReleaseError) throw new Error("Could not load return outgoing release", { cause: outgoingReleaseError });
  const { data: deliveryReceipt, error: deliveryReceiptError } = ["delivery", "closed"].includes(repair.stage)
    ? await supabase.from("repair_delivery_receipts")
      .select("id, recipient_name, receipt_reference, received_at, outgoing_check_id, repair_outgoing_check_id, device_id, method, dispatch_id")
      .eq("org_id", orgId).eq("case_id", caseId).maybeSingle()
    : { data: null, error: null };
  if (deliveryReceiptError) throw new Error("Could not load delivery receipt", { cause: deliveryReceiptError });
  const { data: originalReturn, error: originalReturnError } = ["delivery", "closed"].includes(repair.stage) && latestPlan?.route === "replacement"
    ? await supabase.from("repair_replacement_original_returns")
      .select("id, execution_id, original_device_id, recipient_name, receipt_reference, condition_note, returned_at")
      .eq("org_id", orgId).eq("case_id", caseId).maybeSingle()
    : { data: null, error: null };
  if (originalReturnError) throw new Error("Could not load original device return", { cause: originalReturnError });
  const { data: warehouseReceipt, error: warehouseReceiptError } = ["delivery", "closed"].includes(repair.stage) && latestPlan?.route === "replacement"
    ? await supabase.from("repair_replacement_warehouse_receipts")
      .select("id, execution_id, original_device_id, transfer_id, disposition, location, received_by, receipt_reference, condition_note")
      .eq("org_id", orgId).eq("case_id", caseId).maybeSingle()
    : { data: null, error: null };
  if (warehouseReceiptError) throw new Error("Could not load original warehouse receipt", { cause: warehouseReceiptError });
  const { data: scrap, error: scrapError } = ["delivery", "closed"].includes(repair.stage) && latestPlan?.route === "replacement"
    ? await supabase.from("repair_replacement_scraps").select("*").eq("org_id", orgId).eq("case_id", caseId).maybeSingle()
    : { data: null, error: null };
  if (scrapError) throw new Error("Could not load original scrap", { cause: scrapError });
  const { data: deliveryDispatch, error: deliveryDispatchError } = ["delivery", "closed"].includes(repair.stage)
    ? await supabase.from("repair_delivery_dispatches")
      .select("id, method, carrier, destination_name, destination_role, authority_reference, destination_address, tracking_code, dispatch_reference, dispatched_at, device_id, outgoing_check_id, repair_outgoing_check_id, status")
      .eq("org_id", orgId).eq("case_id", caseId).order("dispatched_at", { ascending: false }).limit(1).maybeSingle()
    : { data: null, error: null };
  if (deliveryDispatchError) throw new Error("Could not load delivery dispatch", { cause: deliveryDispatchError });
  const { data: dispatchHistory, error: dispatchHistoryError } = deliveryDispatch
    ? await supabase.from("repair_delivery_dispatches")
      .select("id, method, carrier, tracking_code, status, dispatched_at")
      .eq("org_id", orgId).eq("case_id", caseId)
      .order("dispatched_at", { ascending: false })
    : { data: [], error: null };
  if (dispatchHistoryError) throw new Error("Could not load dispatch history", { cause: dispatchHistoryError });
  const activeDispatch = deliveryDispatch?.status === "in_transit" ? deliveryDispatch : null;
  const { data: damageReturn, error: damageReturnError } = deliveryDispatch
    ? await supabase.from("repair_delivery_dispatch_returns")
      .select("return_reference, location, condition_note, received_at")
      .eq("org_id", orgId).eq("case_id", caseId).eq("dispatch_id", deliveryDispatch.id).maybeSingle()
    : { data: null, error: null };
  if (damageReturnError) throw new Error("Could not load delivery return", { cause: damageReturnError });
  const { data: deliveryIncidents, error: deliveryIncidentError } = deliveryDispatch
    ? await supabase.from("repair_delivery_incidents")
      .select("id, kind, reference, evidence, status, responsible_user_id, due_at, version, resolution_reference")
      .eq("org_id", orgId).eq("case_id", caseId).eq("dispatch_id", deliveryDispatch.id)
      .order("recorded_at", { ascending: false })
    : { data: [], error: null };
  if (deliveryIncidentError) throw new Error("Could not load delivery incidents", { cause: deliveryIncidentError });
  const { data: deliveryFollowups, error: deliveryFollowupError } = deliveryDispatch
    ? await supabase.from("repair_delivery_incident_followups")
      .select("id, reference, outcome, next_due_at, recorded_at")
      .eq("org_id", orgId).eq("case_id", caseId).order("recorded_at", { ascending: false })
    : { data: [], error: null };
  if (deliveryFollowupError) throw new Error("Could not load delivery followups", { cause: deliveryFollowupError });
  const openDeliveryIncident = (deliveryIncidents ?? []).some((item) => item.status === "open");
  const openDamage = (openDamageCount ?? 0) > 0;
  const damageNeedsRetest = Boolean(repair.stage === "delivery" && (["repair", "replacement"].includes(latestPlan?.route ?? "") ? repairOutgoingCheck : outgoingCheck)
    && repair.custody_damage_epoch > (["repair", "replacement"].includes(latestPlan?.route ?? "") ? repairOutgoingCheck : outgoingCheck)!.custody_damage_epoch);
  const damageReturned = Boolean(damageReturn) || (custodyDiscrepancies ?? []).some((item) => item.kind === "damage"
    && new Date(item.recorded_at).getTime() >= new Date(repair.stage_entered_at).getTime()
    && (custodyTransfers ?? []).some((transfer) => transfer.id === item.transfer_id && transfer.status === "returned"));
  const checkMatchesStage = repair.stage === "test"
    ? Boolean(outgoingCheck && new Date(outgoingCheck.created_at).getTime() >= new Date(repair.stage_entered_at).getTime())
    : repair.stage === "delivery" && Boolean(outgoingCheck && (events ?? []).some((event) =>
      event.event_type === "stage_transition" && event.details && typeof event.details === "object"
      && !Array.isArray(event.details) && event.details.transitionCode === "T08"
      && event.details.outgoingCheckId === outgoingCheck.id));
  const deliveryReady = Boolean(!openDamage && !openDeliveryIncident && outgoingCheck && outgoingRelease && latestPlan && returnAuthorization
    && outgoingCheck.custody_damage_epoch === repair.custody_damage_epoch
    && outgoingCheck.plan_id === latestPlan.id && outgoingCheck.authorization_id === returnAuthorization.id
    && outgoingCheck.device_id === repair.verified_device_id
    && checkMatchesStage
    && outgoingCheck.identity_pass && outgoingCheck.items_pass && outgoingCheck.condition_pass && outgoingCheck.transport_pass);
  const verifiedPaymentIds = new Set((paymentVerifications ?? []).map((item) => item.payment_id));
  const correctedPaymentIds = new Set((paymentCorrections ?? []).map((item) => item.payment_id));
  const verifiedAmount = (paymentEvidence ?? []).reduce((sum, item) =>
    sum + (verifiedPaymentIds.has(item.id) && !correctedPaymentIds.has(item.id) ? item.amount_irr : 0), 0)
    + (creditTransfers ?? []).reduce((sum, transfer) => sum + (transfer.target_plan_id === latestPlan?.id && transfer.approved_at ? transfer.amount_irr : 0), 0)
    - (refunds ?? []).reduce((sum, refund) => sum + (refund.approved_at && (paymentEvidence ?? []).some((payment) => payment.id === refund.source_payment_id) ? refund.amount_irr : 0), 0);
  const repairFinanceReady = Boolean(latestPlan && (latestPlan.financial_basis === "warranty" && latestPlan.amount_irr === 0
    || latestPlan.financial_basis === "customer_paid" && verifiedAmount === latestPlan.amount_irr));
  const repairCheckMatchesStage = repair.stage === "test"
    ? Boolean(repairOutgoingCheck && new Date(repairOutgoingCheck.recorded_at).getTime() >= new Date(repair.stage_entered_at).getTime())
    : repair.stage === "delivery" && Boolean(repairOutgoingCheck && (events ?? []).some((event) =>
      event.event_type === "stage_transition" && event.details && typeof event.details === "object"
      && !Array.isArray(event.details) && event.details.transitionCode === "T08"
      && event.details.repairOutgoingCheckId === repairOutgoingCheck.id));
  const repairDeliveryReady = Boolean(repairFinanceReady && !openDamage && !openDeliveryIncident
    && repairOutgoingCheck && repairOutgoingRelease
    && custodyPosition?.case_id === caseId
    && (repair.stage === "test" ? custodyPosition.holder_kind === "staff" : ["staff", "carrier", "recipient"].includes(custodyPosition.holder_kind))
    && repairOutgoingCheck.plan_id === latestPlan?.id && repairOutgoingCheck.device_id === repair.verified_device_id
    && repairOutgoingCheck.custody_damage_epoch === repair.custody_damage_epoch && repairCheckMatchesStage
    && repairOutgoingCheck.identity_pass && repairOutgoingCheck.items_pass
    && repairOutgoingCheck.condition_pass && repairOutgoingCheck.transport_pass);
  const replacementDeliveryReady = Boolean(["test", "delivery"].includes(repair.stage) && repairFinanceReady
    && latestPlan?.route === "replacement" && replacementExecution
    && replacementExecution.plan_id === latestPlan.id
    && replacementExecution.original_device_id === repair.verified_device_id
    && replacementTestStock?.status === "allocated"
    && replacementTestStock.allocated_case_id === caseId
    && replacementTestStock.allocated_plan_id === latestPlan.id
    && replacementTestPosition?.case_id === caseId
    && (replacementTestPosition.holder_kind === "staff"
      && replacementTestPosition.custodian_user_id === replacementTestStock.custodian_user_id
      && replacementTestPosition.location === replacementTestStock.location
      || repair.stage === "delivery" && replacementTestPosition.holder_kind === "carrier"
        && activeDispatch?.device_id === replacementExecution.replacement_device_id
        && activeDispatch.repair_outgoing_check_id === repairOutgoingCheck?.id
        && activeDispatch.dispatch_reference === replacementTestPosition.external_reference)
    && custodyPosition?.case_id === caseId && custodyPosition.holder_kind === "staff"
    && !repairCustodyBlocked && !replacementTestTransfers?.length && !replacementTestDiscrepancies?.length
    && !(assignmentRequests ?? []).some((item) => item.status === "pending")
    && !openDamage && !openDeliveryIncident && (repair.stage === "test" ? currentFunctionalRelease : Boolean(functionalRelease
      && functionalTest?.passed && functionalTest.execution_id === replacementExecution.id
      && functionalTest.custody_damage_epoch === repair.custody_damage_epoch))
    && repairOutgoingCheck && repairOutgoingRelease && (repair.stage === "test" ? repairCheckMatchesStage : (events ?? []).some((event) =>
      event.event_type === "stage_transition" && event.details && typeof event.details === "object"
      && !Array.isArray(event.details) && event.details.transitionCode === "T08"
      && event.details.replacementOutgoingCheckId === repairOutgoingCheck.id))
    && repairOutgoingCheck.protocol_code === "replacement_outgoing_v1"
    && repairOutgoingCheck.plan_id === latestPlan.id
    && repairOutgoingCheck.functional_test_id === functionalTest?.id
    && repairOutgoingCheck.device_id === replacementExecution.replacement_device_id
    && repairOutgoingCheck.custody_damage_epoch === repair.custody_damage_epoch
    && repairOutgoingCheck.identity_pass && repairOutgoingCheck.items_pass
    && repairOutgoingCheck.condition_pass && repairOutgoingCheck.transport_pass);

  const replacementIssuedReady = Boolean(repair.stage === "delivery" && latestPlan?.route === "replacement"
    && repairFinanceReady && !openDeliveryIncident && deliveryReceipt && replacementExecution
    && replacementExecution.plan_id === latestPlan.id
    && deliveryReceipt.device_id === replacementExecution.replacement_device_id
    && replacementTestStock?.status === "issued"
    && replacementTestStock.allocated_case_id === caseId && replacementTestStock.allocated_plan_id === latestPlan.id
    && replacementTestPosition?.holder_kind === "recipient"
    && !repairCustodyBlocked && !replacementTestTransfers?.length && !replacementTestDiscrepancies?.length
    && !(assignmentRequests ?? []).some((item) => item.status === "pending")
    && repairOutgoingCheck && repairOutgoingRelease && functionalTest?.passed && functionalRelease
    && functionalTest.execution_id === replacementExecution.id
    && functionalTest.custody_damage_epoch === repair.custody_damage_epoch
    && repairOutgoingCheck.custody_damage_epoch === repair.custody_damage_epoch
    && deliveryReceipt.repair_outgoing_check_id === repairOutgoingCheck.id);
  const warehousePlan = ["parts_proposed", "refurbish_proposed"].includes(latestPlan?.original_disposition ?? "");
  const currentWarehouseTransfer = (custodyTransfers ?? []).find((transfer) => transfer.case_id === caseId
    && transfer.status === "accepted" && transfer.destination_user_id === ctx.user.id
    && transfer.destination_user_id === custodyPosition?.custodian_user_id
    && transfer.destination_location === custodyPosition?.location
    && transfer.resolved_at === custodyPosition?.confirmed_at && replacementExecution
    && new Date(transfer.resolved_at ?? 0).getTime() >= new Date(replacementExecution.executed_at).getTime()) ?? null;
  const replacementCloseReady = Boolean(replacementIssuedReady && replacementExecution && (
    (originalReturn && originalReturn.execution_id === replacementExecution.id
      && originalReturn.original_device_id === repair.verified_device_id && custodyPosition?.holder_kind === "recipient")
    || (scrap && latestPlan?.original_disposition === "scrap_proposed" && scrap.approved_at
      && scrap.approved_by && scrap.approved_by !== scrap.recorded_by && scrap.execution_id === replacementExecution.id
      && scrap.original_device_id === repair.verified_device_id && custodyPosition?.holder_kind === "scrapped"
      && custodyPosition.external_reference === scrap.reference && custodyPosition.confirmed_at === scrap.recorded_at)
    || (warehouseReceipt && warehousePlan && warehouseReceipt.execution_id === replacementExecution.id
      && warehouseReceipt.original_device_id === repair.verified_device_id && custodyPosition?.holder_kind === "staff"
      && warehouseReceipt.received_by === custodyPosition.custodian_user_id && warehouseReceipt.location === custodyPosition.location
      && (custodyTransfers ?? []).some((transfer) => transfer.id === warehouseReceipt.transfer_id && transfer.status === "accepted"
        && transfer.resolved_at === custodyPosition.confirmed_at))));

  const diagnosisCurrentCycle = Boolean(latestDiagnosis && new Date(latestDiagnosis.created_at).getTime() >= new Date(repair.stage_entered_at).getTime());
  const diagnosisReady = Boolean(diagnosisCurrentCycle && latestDiagnosis?.status === "final"
    && latestDiagnosis.technical_condition !== "unknown" && latestDiagnosis.finalized_at
    && new Date(latestDiagnosis.finalized_at).getTime() >= new Date(repair.stage_entered_at).getTime());
  const currentPlan = Boolean(repair.stage === "decision" && latestPlan && latestDiagnosis
    && latestPlan.diagnosis_id === latestDiagnosis.id
    && latestDiagnosis.status === "final"
    && new Date(latestPlan.created_at).getTime() >= new Date(repair.stage_entered_at).getTime());
  const latestCustomer = planApprovals?.find((approval) => approval.kind === "customer");
  const latestReplacement = planApprovals?.find((approval) => approval.kind === "replacement");
  const basisReady = Boolean(latestPlan && latestDiagnosis && (
    (latestPlan.financial_basis === "warranty" && latestDiagnosis.warranty_coverage === "covered")
    || (latestPlan.financial_basis === "customer_paid" && latestDiagnosis.warranty_coverage === "not_covered")));
  const decisionReady = Boolean(currentPlan && latestPlan && (latestPlan.route === "return"
    ? returnAuthorization?.plan_id === latestPlan.id && returnAuthorization.protocol_code === "return_outgoing_v1"
    : basisReady
      && (latestPlan.route !== "replacement" || latestReplacement?.decision === "approved")
      && ((latestPlan.route === "repair" && latestPlan.financial_basis === "warranty")
        || latestCustomer?.decision === "approved")
      && (latestPlan.route !== "repair" || partsReady)));
  const activeStage = stageIndex[repair.stage] ?? 0;
  const bypassedAction = latestPlan?.route === "return" && activeStage >= 4;
  const evidencePath = repair.imei_evidence?.startsWith(`${orgId}/${caseId}/`) ? repair.imei_evidence : null;
  const { data: evidenceLink } = evidencePath
    ? await supabase.storage.from("repair-imei-evidence").createSignedUrl(evidencePath, 600)
    : { data: null };

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-5">
      <div>
        <Link href={`/${orgId}/repairs`} className="text-sm text-primary underline-offset-4 hover:underline">بازگشت به پرونده‌ها</Link>
        <div className="mt-3 flex flex-wrap items-start justify-between gap-3">
          <div><h1 className="text-2xl font-semibold">پروندهٔ {repair.tracking_code}</h1><p className="mt-1 text-sm text-muted-foreground">{repair.customer_name} · {repair.device_model}</p></div>
          <Badge variant="secondary">{repair.stage === "repair" ? "تعمیر" : repair.stage === "replacement" ? "تعویض" : stages[activeStage]}</Badge>
        </div>
      </div>

      <Card>
        <CardHeader><CardTitle>مسیر پرونده</CardTitle></CardHeader>
        <CardContent className="overflow-x-auto">
          <ol className="grid min-w-[34rem] grid-cols-7 gap-1" aria-label="مراحل اصلی پرونده">
            {stages.map((stage, index) => (
              <li key={stage} aria-current={index === activeStage ? "step" : undefined} className="min-w-0 text-center">
                <span className={`mx-auto mb-2 flex size-7 items-center justify-center rounded-full border text-xs tabular-nums ${index === activeStage ? "border-primary bg-primary text-primary-foreground" : index < activeStage && !(index === 3 && bypassedAction) ? "border-primary bg-primary/15 text-primary" : "border-border text-muted-foreground"}`}>{index === 3 && bypassedAction ? "—" : index + 1}</span>
                <span className={`block text-[11px] leading-snug sm:text-xs ${index === activeStage ? "font-semibold text-foreground" : "text-muted-foreground"}`}>{index === 3 && bypassedAction ? "اقدام نیاز نبود" : index === 3 && repair.stage === "repair" ? "تعمیر" : index === 3 && repair.stage === "replacement" ? "تعویض" : stage}</span>
              </li>
            ))}
          </ol>
          <p className="mt-3 text-center text-xs text-muted-foreground">پس از تصمیم، مسیر تعمیر، تعویض یا عودت بدون تعمیر انتخاب می‌شود؛ عودت مستقیماً به کنترل خروج می‌رود.</p>
          {repair.stage === "closed" && <p className="mt-3 text-center text-sm">پرونده بسته شده است.</p>}
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card><CardHeader><CardTitle>درخواست اولیه</CardTitle></CardHeader><CardContent className="grid gap-3 text-sm">
          <div><p className="text-muted-foreground">شرح ایراد</p><p className="whitespace-pre-wrap">{repair.issue}</p></div>
          <div><p className="text-muted-foreground">شناسهٔ اعلام‌شده</p><p dir="ltr" className="text-right tabular-nums">{repair.raw_identifier || "ثبت نشده"}</p></div>
          <div><p className="text-muted-foreground">زمان ثبت</p><p>{formatJalaliDateTime(repair.created_at)}</p></div>
        </CardContent></Card>

        <Card><CardHeader><CardTitle>دستگاه و تحویل‌گیرنده</CardTitle></CardHeader><CardContent className="grid gap-3 text-sm">
          {repair.received_at ? <>
            <div><p className="text-muted-foreground">دریافت فیزیکی</p><p>{formatJalaliDateTime(repair.received_at)} · {receiptNames[repair.receipt_method ?? ""] ?? repair.receipt_method}</p></div>
            <div><p className="text-muted-foreground">محل تأییدشدهٔ دستگاه</p><p>{custodyPosition?.location ?? repair.device_location}</p></div>
            <div><p className="text-muted-foreground">نگهدارندهٔ فیزیکی</p><p>{custodyPosition?.custodian_label ?? repair.device_custodian}</p></div>
            <div><p className="text-muted-foreground">IMEI تأییدشده</p><p dir="ltr" className="text-right tabular-nums">{device?.imei ?? "هنوز تأیید نشده"}</p></div>
            {repair.imei_evidence && <div><p className="text-muted-foreground">عکس برچسب دستگاه</p>{evidenceLink?.signedUrl ? <a href={evidenceLink.signedUrl} target="_blank" rel="noopener noreferrer" className="text-primary underline underline-offset-4">مشاهدهٔ مدرک</a> : <p className="text-muted-foreground">مرجع قدیمی؛ فایل قابل مشاهده نیست</p>}</div>}
            {repair.duplicate_exception_reference && <div><p className="text-muted-foreground">استثنای پروندهٔ تکراری</p><p>{repair.duplicate_exception_reason} · {repair.duplicate_exception_reference}</p></div>}
          </> : <p className="text-muted-foreground">دریافت فیزیکی دستگاه هنوز ثبت نشده است. وضعیت محل و مسئول نگهداری پس از دریافت مشخص می‌شود.</p>}
        </CardContent></Card>
      </div>

      <AssignmentPanel orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        currentUserId={ctx.user.id} assignedTo={repair.assigned_to}
        members={assignmentMembers} requests={assignmentRequests ?? []}
        canAssign={ctx.can(PERMISSIONS.REPAIR_CASE_ASSIGN)}
        canAccept={ctx.can(PERMISSIONS.REPAIR_ASSIGNMENT_ACCEPT)}
        canReject={ctx.can(PERMISSIONS.REPAIR_ASSIGNMENT_REJECT)}
        canWithdraw={ctx.can(PERMISSIONS.REPAIR_ASSIGNMENT_WITHDRAW)}
        closed={repair.stage === "closed"} />

      {repair.received_at && <CustodyPanel orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        deviceId={repair.verified_device_id} receiptLocation={repair.device_location}
        currentUserId={ctx.user.id} members={assignmentMembers} position={custodyPosition}
        transfers={custodyTransfers ?? []} discrepancies={custodyDiscrepancies ?? []}
        canBaseline={ctx.can(PERMISSIONS.REPAIR_CUSTODY_BASELINE)}
        canRelease={ctx.can(PERMISSIONS.REPAIR_CUSTODY_RELEASE) && !(repair.stage === "delivery" && latestPlan?.route === "repair")}
        canAccept={ctx.can(PERMISSIONS.REPAIR_CUSTODY_ACCEPT)}
        canReturn={ctx.can(PERMISSIONS.REPAIR_CUSTODY_RETURN)}
        canRecordDiscrepancy={ctx.can(PERMISSIONS.REPAIR_CUSTODY_DISCREPANCY_RECORD)}
        canResolveDiscrepancy={ctx.can(PERMISSIONS.REPAIR_CUSTODY_DISCREPANCY_RESOLVE)}
        closed={repair.stage === "closed"} />}

      {!repair.received_at && ctx.can(PERMISSIONS.REPAIR_CASE_RECEIVE) && (
        <ReceiptForm orgId={orgId} caseId={caseId} expectedVersion={repair.version} canOverride={ctx.can(PERMISSIONS.REPAIR_CASE_DUPLICATE_OVERRIDE)} />
      )}

      {repair.stage === "diagnosis" && <DiagnosisForm key={latestDiagnosis?.id ?? "new"}
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        latest={latestDiagnosis} currentCycle={diagnosisCurrentCycle}
        canRecord={ctx.can(PERMISSIONS.REPAIR_DIAGNOSIS_RECORD)}
        canFinalize={ctx.can(PERMISSIONS.REPAIR_DIAGNOSIS_FINALIZE)} />}
      {repair.stage === "decision" && latestDiagnosis && <Card><CardHeader><CardTitle>تشخیص مبنای تصمیم · نسخهٔ {latestDiagnosis.revision}</CardTitle></CardHeader><CardContent className="grid gap-3 text-sm"><p className="whitespace-pre-wrap">{latestDiagnosis.findings}</p><p className="text-muted-foreground">وضعیت فنی: {conditionNames[latestDiagnosis.technical_condition]} · پیشنهاد: {actionNames[latestDiagnosis.recommended_action]} · پوشش: {coverageNames[latestDiagnosis.warranty_coverage]}</p></CardContent></Card>}
      {repair.stage === "decision" && latestDiagnosis && ["repair", "replacement", "return"].includes(latestDiagnosis.recommended_action) && <DecisionPanel key={latestPlan?.id ?? "new"}
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        route={latestDiagnosis.recommended_action as "repair" | "replacement" | "return"}
        diagnosisCoverage={latestDiagnosis.warranty_coverage}
        latest={latestPlan} approvals={planApprovals ?? []}
        canRecord={ctx.can(PERMISSIONS.REPAIR_PLAN_RECORD)}
        canRecordCustomer={ctx.can(PERMISSIONS.REPAIR_CUSTOMER_APPROVAL_RECORD)}
        canApproveReplacement={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_APPROVE)} />}
      {paidPlanVisible && latestPlan && <RepairPaymentPanel key={latestPlan.id}
        orgId={orgId} caseId={caseId} expectedVersion={repair.version} planAmount={latestPlan.amount_irr}
        payments={paymentEvidence ?? []} verifications={paymentVerifications ?? []} corrections={paymentCorrections ?? []}
        approvedCreditAmount={(creditTransfers ?? []).reduce((sum, transfer) => sum + (transfer.target_plan_id === latestPlan.id && transfer.approved_at ? transfer.amount_irr : 0), 0)}
        approvedRefundAmount={(refunds ?? []).reduce((sum, refund) => sum + (refund.approved_at && (paymentEvidence ?? []).some((payment) => payment.id === refund.source_payment_id) ? refund.amount_irr : 0), 0)}
        refundedPaymentIds={(refunds ?? []).filter((refund) => refund.approved_at).map((refund) => refund.source_payment_id)}
        canRecord={repair.stage !== "delivery" && ctx.can(PERMISSIONS.REPAIR_PAYMENT_RECORD)}
        canVerify={repair.stage !== "delivery" && ctx.can(PERMISSIONS.REPAIR_PAYMENT_VERIFY)}
        canCorrect={repair.stage !== "delivery" && ctx.can(PERMISSIONS.REPAIR_PAYMENT_CORRECT)} />}
      {paidPlanVisible && latestPlan && repair.stage !== "delivery" && <RepairCreditTransferPanel
        orgId={orgId} caseId={caseId} currentUserId={ctx.user.id} expectedVersion={repair.version}
        planId={latestPlan.id} planAmount={latestPlan.amount_irr}
        oldPayments={oldPaymentEvidence ?? []} verifications={paymentVerifications ?? []}
        corrections={paymentCorrections ?? []} transfers={creditTransfers ?? []} refunds={refunds ?? []}
        canRequest={ctx.can(PERMISSIONS.REPAIR_PAYMENT_CREDIT_REQUEST)}
        canApprove={ctx.can(PERMISSIONS.REPAIR_PAYMENT_CREDIT_APPROVE)} />}
      {paymentHistoryVisible && <RepairRefundPanel orgId={orgId} caseId={caseId}
        currentUserId={ctx.user.id} expectedVersion={repair.version} payments={allPayments ?? []}
        verifications={allVerifications ?? []} corrections={allCorrections ?? []}
        transfers={allTransfers ?? []} refunds={refunds ?? []}
        canRequest={ctx.can(PERMISSIONS.REPAIR_PAYMENT_REFUND_REQUEST)}
        canApprove={ctx.can(PERMISSIONS.REPAIR_PAYMENT_REFUND_APPROVE)} />}
      {repair.stage === "decision" && needsParts && latestPlan && <PartsPanel
        key={latestPlan.id} orgId={orgId} caseId={caseId} planId={latestPlan.id}
        expectedVersion={repair.version} parts={parts} requirements={requirements}
        canReceive={ctx.can(PERMISSIONS.REPAIR_PART_RECEIVE)}
        canRequire={ctx.can(PERMISSIONS.REPAIR_PART_REQUIRE)}
        canReserve={ctx.can(PERMISSIONS.REPAIR_PART_RESERVE)} />}
      {repair.stage === "repair" && needsParts && latestPlan && <RepairExecutionPanel
        orgId={orgId} caseId={caseId} planId={latestPlan.id} expectedVersion={repair.version}
        parts={parts} reservations={executionReservations ?? []} movements={partMovements ?? []}
        canConsume={ctx.can(PERMISSIONS.REPAIR_PART_CONSUME)}
        canRelease={ctx.can(PERMISSIONS.REPAIR_PART_RELEASE)}
        canReturn={ctx.can(PERMISSIONS.REPAIR_PART_RETURN)} />}
      {repair.stage === "repair" && latestPlan?.route === "repair" && <RepairCompletionPanel
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        canComplete={ctx.can(PERMISSIONS.REPAIR_COMPLETE) && ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_TEST_FROM_REPAIR)}
        verified={Boolean(repair.verified_device_id)} needsParts={Boolean(needsParts)}
        partsComplete={repairPartsComplete} custodyBlocked={repairCustodyBlocked} />}
      {repair.stage === "replacement" && latestPlan?.route === "replacement" && <ReplacementStockPanel
        orgId={orgId} caseId={caseId} planId={latestPlan.id} model={latestPlan.replacement_model!}
        expectedVersion={repair.version} members={assignmentMembers}
        stock={(replacementStock ?? []).filter((item) => item.status === "available")}
        allocated={allocatedReplacement}
        canReceive={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_STOCK_RECEIVE)}
        canAllocate={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_STOCK_ALLOCATE)} />}
      {repair.stage === "replacement" && allocatedReplacement && <ReplacementCustodyPanel
        orgId={orgId} caseId={caseId} deviceId={allocatedReplacement.device_id}
        imei={allocatedReplacement.repair_devices?.imei ?? ""} expectedVersion={repair.version}
        currentUserId={ctx.user.id} location={allocatedReplacement.location}
        custodianUserId={allocatedReplacement.custodian_user_id} members={assignmentMembers}
        transfers={replacementTransfers ?? []} discrepancies={replacementDiscrepancies ?? []}
        canRelease={ctx.can(PERMISSIONS.REPAIR_CUSTODY_RELEASE)}
        canAccept={ctx.can(PERMISSIONS.REPAIR_CUSTODY_ACCEPT)}
        canReturn={ctx.can(PERMISSIONS.REPAIR_CUSTODY_RETURN)}
        canRecordDiscrepancy={ctx.can(PERMISSIONS.REPAIR_CUSTODY_DISCREPANCY_RECORD)}
        canResolveDiscrepancy={ctx.can(PERMISSIONS.REPAIR_CUSTODY_DISCREPANCY_RESOLVE)} />}
      {repair.stage === "replacement" && latestPlan?.route === "replacement" && <ReplacementExecutionPanel
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        allocatedImei={allocatedReplacement?.repair_devices?.imei ?? null}
        originalBaselineReady={custodyPosition?.case_id === caseId && custodyPosition.holder_kind === "staff"}
        canExecute={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_EXECUTE)
          && ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_TEST_FROM_REPLACEMENT)}
        custodyBlocked={Boolean((custodyTransfers ?? []).some((item) => item.status === "in_transit")
          || (custodyDiscrepancies ?? []).some((item) => item.status === "open")
          || (replacementTransfers ?? []).some((item) => item.status === "in_transit")
          || (replacementDiscrepancies ?? []).some((item) => item.status === "open"))} />}
      {["repair", "test", "delivery"].includes(repair.stage) && needsParts && (partMovements ?? []).some((item) => item.kind === "return_quarantine") && <QuarantinePanel
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        parts={parts} returns={(partMovements ?? []).filter((item) => item.kind === "return_quarantine")}
        resolutions={quarantineResolutions ?? []}
        canRestock={ctx.can(PERMISSIONS.REPAIR_PART_QUARANTINE_RESTOCK)}
        canReject={ctx.can(PERMISSIONS.REPAIR_PART_QUARANTINE_REJECT)} />}
      {repair.stage === "decision" && latestPlan?.route === "return" && <ReturnAuthorizationForm
        key={latestPlan.id} orgId={orgId} caseId={caseId} planId={latestPlan.id}
        planRevision={latestPlan.revision} expectedVersion={repair.version}
        canAuthorize={ctx.can(PERMISSIONS.REPAIR_RETURN_AUTHORIZE)} authorization={returnAuthorization} />}

      {repair.stage === "test" && latestPlan?.route === "return" && returnAuthorization && <ReturnOutgoingCheck
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        planId={latestPlan.id} authorizationId={returnAuthorization.id}
        deviceId={repair.verified_device_id} stageEnteredAt={repair.stage_entered_at}
        latest={outgoingCheck} released={Boolean(outgoingRelease)} damageEpoch={repair.custody_damage_epoch} openDamage={openDamage}
        canRecord={ctx.can(PERMISSIONS.REPAIR_RETURN_QC_RECORD)}
        canRelease={ctx.can(PERMISSIONS.REPAIR_QUALITY_RELEASE)} />}
      {repair.stage === "test" && latestPlan?.route === "repair" && <RepairFunctionalTest
        orgId={orgId} caseId={caseId} expectedVersion={repair.version} planId={latestPlan.id}
        completionId={repairCompletion?.id ?? null} deviceId={repair.verified_device_id}
        damageEpoch={repair.custody_damage_epoch} stageEnteredAt={repair.stage_entered_at}
        latest={functionalTest} released={Boolean(functionalRelease)} custodyBlocked={repairCustodyBlocked}
        canRecord={ctx.can(PERMISSIONS.REPAIR_FUNCTIONAL_TEST_RECORD)}
        canRelease={ctx.can(PERMISSIONS.REPAIR_QUALITY_RELEASE)} />}
      {repair.stage === "test" && latestPlan?.route === "replacement" && <RepairFunctionalTest
        orgId={orgId} caseId={caseId} expectedVersion={repair.version} planId={latestPlan.id}
        completionId={null} executionId={replacementExecution?.id ?? null} route="replacement"
        deviceId={replacementExecution?.replacement_device_id ?? null}
        damageEpoch={repair.custody_damage_epoch} stageEnteredAt={repair.stage_entered_at}
        latest={functionalTest} released={Boolean(functionalRelease)}
        custodyBlocked={Boolean(replacementTestTransfers?.length || replacementTestDiscrepancies?.length)}
        canRecord={ctx.can(PERMISSIONS.REPAIR_FUNCTIONAL_TEST_RECORD)}
        canRelease={ctx.can(PERMISSIONS.REPAIR_QUALITY_RELEASE)} />}
      {repair.stage === "test" && latestPlan?.route === "repair" && <RepairOutgoingCheck
        orgId={orgId} caseId={caseId} expectedVersion={repair.version} planId={latestPlan.id}
        testId={functionalTest?.id ?? null} deviceId={repair.verified_device_id}
        damageEpoch={repair.custody_damage_epoch} stageEnteredAt={repair.stage_entered_at}
        latest={repairOutgoingCheck} released={Boolean(repairOutgoingRelease)}
        functionalReleased={currentFunctionalRelease} custodyBlocked={repairCustodyBlocked}
        canRecord={ctx.can(PERMISSIONS.REPAIR_OUTGOING_QC_RECORD)}
        canRelease={ctx.can(PERMISSIONS.REPAIR_QUALITY_RELEASE)} />}
      {repair.stage === "test" && latestPlan?.route === "replacement" && <RepairOutgoingCheck
        orgId={orgId} caseId={caseId} expectedVersion={repair.version} planId={latestPlan.id}
        route="replacement" testId={functionalTest?.id ?? null}
        deviceId={replacementExecution?.replacement_device_id ?? null}
        damageEpoch={repair.custody_damage_epoch} stageEnteredAt={repair.stage_entered_at}
        latest={repairOutgoingCheck} released={Boolean(repairOutgoingRelease)}
        functionalReleased={currentFunctionalRelease}
        custodyBlocked={Boolean(repairCustodyBlocked || replacementTestTransfers?.length || replacementTestDiscrepancies?.length)}
        canRecord={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_OUTGOING_QC_RECORD)}
        canRelease={ctx.can(PERMISSIONS.REPAIR_QUALITY_RELEASE)} />}

      {repair.stage === "delivery" && latestPlan?.route === "replacement" && repairOutgoingCheck && <>
        {!activeDispatch && <DeliveryReceipt orgId={orgId} caseId={caseId} expectedVersion={repair.version}
          intendedRecipient={repairOutgoingCheck.intended_recipient}
          recipientRole={repairOutgoingCheck.recipient_role as "owner" | "authorized_representative" | "colleague"}
          authorityReference={repairOutgoingCheck.authority_reference} receipt={deliveryReceipt}
          canRecord={ctx.can(PERMISSIONS.REPAIR_DELIVERY_RECEIVE)}
          ready={replacementDeliveryReady} deviceIdentifier={replacementDevice?.imei} route="replacement" />}
        {(activeDispatch || !deliveryReceipt) && <DeliveryShipment
          key={activeDispatch?.id ?? "replacement-dispatch"}
          orgId={orgId} caseId={caseId} expectedVersion={repair.version}
          intendedRecipient={repairOutgoingCheck.intended_recipient} dispatch={activeDispatch}
          deviceIdentifier={replacementDevice?.imei}
          received={Boolean(deliveryReceipt)} incidentOpen={openDeliveryIncident}
          canDispatch={ctx.can(PERMISSIONS.REPAIR_DELIVERY_DISPATCH) && replacementTestPosition?.custodian_user_id === ctx.user.id}
          canConfirm={ctx.can(PERMISSIONS.REPAIR_DELIVERY_CONFIRM_RECEIPT)} ready={replacementDeliveryReady} />}
        {latestPlan.original_disposition === "scrap_proposed" ? <ReplacementScrap key={scrap?.id ?? "scrap-record"}
          orgId={orgId} caseId={caseId} expectedVersion={repair.version} currentUserId={ctx.user.id} deviceIdentifier={device?.imei}
          recordedByLabel={assignmentMembers.find((member) => member.id === scrap?.recorded_by)?.label}
          approvedByLabel={assignmentMembers.find((member) => member.id === scrap?.approved_by)?.label}
          canRecord={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_SCRAP_RECORD) && custodyPosition?.custodian_user_id === ctx.user.id}
          canApprove={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_SCRAP_APPROVE)} ready={replacementIssuedReady} scrap={scrap} /> :
        warehousePlan ? <ReplacementWarehouseReceipt orgId={orgId} caseId={caseId} expectedVersion={repair.version}
          disposition={latestPlan.original_disposition ?? ""} canRecord={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_WAREHOUSE_RECEIVE)}
          ready={replacementIssuedReady} transfer={currentWarehouseTransfer} receipt={warehouseReceipt} /> :
        <ReplacementOriginalReturn orgId={orgId} caseId={caseId} expectedVersion={repair.version}
          disposition={latestPlan.original_disposition ?? ""} recipientName={repairOutgoingCheck.intended_recipient}
          canRecord={ctx.can(PERMISSIONS.REPAIR_REPLACEMENT_ORIGINAL_RETURN)}
          ready={replacementIssuedReady} returned={originalReturn} />}
      </>}

      {repair.stage === "delivery" && latestPlan?.route === "return" && outgoingCheck && !activeDispatch && <DeliveryReceipt
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        intendedRecipient={outgoingCheck.intended_recipient}
        recipientRole={outgoingCheck.recipient_role as "owner" | "authorized_representative" | "colleague"}
        authorityReference={outgoingCheck.authority_reference}
        receipt={deliveryReceipt} canRecord={ctx.can(PERMISSIONS.REPAIR_DELIVERY_RECEIVE)}
        ready={deliveryReady && latestPlan.financial_basis === "none" && latestPlan.amount_irr === 0} />}
      {repair.stage === "delivery" && latestPlan?.route === "repair" && repairOutgoingCheck && !activeDispatch && <DeliveryReceipt
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        intendedRecipient={repairOutgoingCheck.intended_recipient}
        recipientRole={repairOutgoingCheck.recipient_role as "owner" | "authorized_representative" | "colleague"}
        authorityReference={repairOutgoingCheck.authority_reference}
        receipt={deliveryReceipt} canRecord={ctx.can(PERMISSIONS.REPAIR_DELIVERY_RECEIVE)}
        ready={repairDeliveryReady} route="repair" />}
      {repair.stage === "delivery" && latestPlan?.route === "return" && outgoingCheck && (activeDispatch || !deliveryReceipt) && <DeliveryShipment
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        intendedRecipient={outgoingCheck.intended_recipient} dispatch={activeDispatch}
        received={Boolean(deliveryReceipt)} incidentOpen={openDeliveryIncident} canDispatch={ctx.can(PERMISSIONS.REPAIR_DELIVERY_DISPATCH)}
        canConfirm={ctx.can(PERMISSIONS.REPAIR_DELIVERY_CONFIRM_RECEIPT)}
        ready={deliveryReady && latestPlan.financial_basis === "none" && latestPlan.amount_irr === 0} />}
      {repair.stage === "delivery" && latestPlan?.route === "repair" && repairOutgoingCheck && (activeDispatch || !deliveryReceipt) && <DeliveryShipment
        orgId={orgId} caseId={caseId} expectedVersion={repair.version}
        intendedRecipient={repairOutgoingCheck.intended_recipient} dispatch={activeDispatch}
        received={Boolean(deliveryReceipt)} incidentOpen={openDeliveryIncident}
        canDispatch={ctx.can(PERMISSIONS.REPAIR_DELIVERY_DISPATCH)}
        canConfirm={ctx.can(PERMISSIONS.REPAIR_DELIVERY_CONFIRM_RECEIPT)}
        ready={repairDeliveryReady} />}
      {repair.stage === "delivery" && (dispatchHistory ?? []).length > 1 && <Card>
        <CardHeader><CardTitle>سابقهٔ ارسال‌ها</CardTitle></CardHeader>
        <CardContent className="grid gap-2 text-sm">{(dispatchHistory ?? []).map((item) =>
          <div key={item.id} className="rounded-lg border border-border/60 p-3">
            {item.method === "post" ? "پست" : "پیک"} · {item.carrier} · {item.tracking_code} ·
            {item.status === "returned" ? " بازگشت فیزیکی ثبت شد" : deliveryReceipt?.dispatch_id === item.id ? " دریافت مقصد تأیید شد" : " در مسیر تحویل"}
          </div>)}</CardContent>
      </Card>}
      {repair.stage === "delivery" && deliveryDispatch && <div id="delivery-incidents" className="scroll-mt-6"><DeliveryIncidentPanel
        orgId={orgId} caseId={caseId} dispatchId={deliveryDispatch.id} expectedVersion={repair.version}
        received={Boolean(deliveryReceipt)} incidents={deliveryIncidents ?? []} followups={deliveryFollowups ?? []}
        dispatchStatus={deliveryDispatch.status} damageReturn={damageReturn}
        members={assignmentMembers} canRecord={ctx.can(PERMISSIONS.REPAIR_DELIVERY_INCIDENT_RECORD)}
        canFollowup={ctx.can(PERMISSIONS.REPAIR_DELIVERY_INCIDENT_FOLLOWUP)}
        canResolve={ctx.can(PERMISSIONS.REPAIR_DELIVERY_INCIDENT_RESOLVE)}
        canReturn={ctx.can(PERMISSIONS.REPAIR_DELIVERY_RETURN_RECEIVE)} /></div>}
      {repair.stage === "closed" && deliveryReceipt && <Card><CardHeader><CardTitle>رسید تحویل نهایی</CardTitle></CardHeader>
        <CardContent className="text-sm">دستگاه به {deliveryReceipt.recipient_name} {deliveryReceipt.method === "in_person" ? "حضوری" : "در مقصد"} تحویل شد؛ مرجع دریافت: {deliveryReceipt.receipt_reference}.</CardContent></Card>}

      {repair.stage === "closed" && scrap && <ReplacementScrap orgId={orgId} caseId={caseId}
        expectedVersion={repair.version} currentUserId={ctx.user.id} deviceIdentifier={device?.imei}
        recordedByLabel={assignmentMembers.find((member) => member.id === scrap.recorded_by)?.label}
        approvedByLabel={assignmentMembers.find((member) => member.id === scrap.approved_by)?.label}
        canRecord={false} canApprove={false} ready={false} scrap={scrap} />}
      {repair.stage === "closed" && warehouseReceipt && <ReplacementWarehouseReceipt orgId={orgId} caseId={caseId}
        expectedVersion={repair.version} disposition={latestPlan?.original_disposition ?? ""}
        canRecord={false} ready={false} transfer={null} receipt={warehouseReceipt} />}
      {repair.stage === "closed" && latestPlan?.route === "replacement" && originalReturn && <ReplacementOriginalReturn
        orgId={orgId} caseId={caseId} expectedVersion={repair.version} disposition="return_to_customer"
        recipientName={originalReturn.recipient_name} canRecord={false} ready={false} returned={originalReturn} />}

      <StageTransition orgId={orgId} caseId={caseId} trackingCode={repair.tracking_code}
        stage={repair.stage} expectedVersion={repair.version}
        canAdvance={ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_DIAGNOSIS)}
        canAdvanceDecision={ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_DECISION) && ctx.can(PERMISSIONS.REPAIR_DIAGNOSIS_FINALIZE)}
        canAdvanceRepair={ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_REPAIR)}
        canAdvanceReplacement={ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_REPLACEMENT)}
        canAdvanceReturn={ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_RETURN_TEST)}
        canAdvanceDelivery={ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_DELIVERY)}
        canRetestAfterDamage={ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_RETEST_AFTER_DAMAGE)}
        canClose={ctx.can(PERMISSIONS.REPAIR_CASE_CLOSE)}
        handoverReady={latestPlan?.route === "replacement" ? replacementCloseReady : Boolean(deliveryReceipt && deliveryReceipt.device_id === repair.verified_device_id
          && (latestPlan?.route === "repair"
            ? repairOutgoingCheck && deliveryReceipt.repair_outgoing_check_id === repairOutgoingCheck.id
              && (deliveryReceipt.method === "in_person" ? !activeDispatch
                : activeDispatch && deliveryReceipt.dispatch_id === activeDispatch.id
                  && activeDispatch.repair_outgoing_check_id === repairOutgoingCheck.id)
            : outgoingCheck && deliveryReceipt.outgoing_check_id === outgoingCheck.id
              && (deliveryReceipt.method === "in_person" ? !activeDispatch
                : activeDispatch && deliveryReceipt.dispatch_id === activeDispatch.id
                  && activeDispatch.outgoing_check_id === outgoingCheck.id)))}
        damageNeedsRetest={damageNeedsRetest} damageReturned={damageReturned}
        deliveryReady={latestPlan?.route === "repair" ? repairDeliveryReady : latestPlan?.route === "replacement" ? (repair.stage === "test" ? replacementDeliveryReady : replacementCloseReady) : deliveryReady}
        deliveryRoute={latestPlan?.route === "repair" ? "repair" : latestPlan?.route === "replacement" ? "replacement" : latestPlan?.route === "return" ? "return" : null}
        canReturn={ctx.can(PERMISSIONS.REPAIR_TRANSITION_TO_INTAKE)}
        diagnosisReady={diagnosisReady} decisionReady={decisionReady}
        decisionRoute={latestPlan?.route === "repair" || latestPlan?.route === "replacement" || latestPlan?.route === "return"
          ? latestPlan.route : null}
        intakeReady={Boolean(repair.received_at && repair.device_location?.trim() && repair.device_custodian?.trim()
          && (repair.verified_device_id || repair.raw_identifier?.trim()))} />

      <Card><CardHeader><CardTitle>تاریخچه</CardTitle></CardHeader><CardContent className="grid gap-3">
        {(events ?? []).map((event) => (
          <div key={event.id} className="flex flex-wrap items-baseline justify-between gap-2 border-b border-border/60 pb-3 text-sm last:border-0 last:pb-0">
            <span>{event.event_type === "stage_transition"
              ? event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T01"
                ? "ارجاع از پذیرش به کارشناسی" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T02"
                  ? "ارجاع از کارشناسی به تصمیم" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T03"
                    ? "ارجاع از تصمیم به تعمیر" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T04"
                      ? "ارجاع از تصمیم به تعویض" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T05"
                      ? "ارجاع عودت به کنترل خروج" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T06"
                        ? "تکمیل تعمیر و ارجاع به آزمون" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T07"
                          ? "اجرای تعویض و ارجاع دستگاه جایگزین به آزمون" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T08"
                          ? "ارجاع کنترل خروج به تحویل" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T09"
                            ? "تحویل تأیید و پرونده بسته شد" : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.transitionCode === "T11"
                            ? "بازگشت از تحویل به تست پس از آسیب" : "بازگشت از کارشناسی به پذیرش"
              : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.scrapId
                ? event.details.operation === "replacement.scrap.approve" ? "مدرک اجرای اسقاط توسط فرد دوم تأیید شد" : "اجرای اسقاط دستگاه اولیه ثبت شد"
              : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.warehouseReceiptId
                ? event.details.disposition === "parts_received" ? "دستگاه اولیه برای داغی / قطعات در انبار دریافت شد" : "دستگاه اولیه برای بازسازی در انبار دریافت شد"
                : event.details && typeof event.details === "object" && !Array.isArray(event.details) && event.details.originalReturnId
                  ? "دستگاه اولیه به گیرنده عودت شد" : eventNames[event.event_type] ?? event.event_type}</span>
            <time className="text-xs text-muted-foreground">{formatJalaliDateTime(event.occurred_at)}</time>
          </div>
        ))}
      </CardContent></Card>
    </div>
  );
}
