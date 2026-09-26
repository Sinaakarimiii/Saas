/** End-to-end evidence and diagnosis API check against the isolated local stack only. */
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";

globalThis.WebSocket = (await import("undici")).WebSocket;

const api = "http://127.0.0.1:55421";
const status = JSON.parse(readFileSync(new URL("../.local-db/status.json", import.meta.url), "utf8"));
const admin = createClient(api, status.SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const user = createClient(api, status.ANON_KEY, { auth: { persistSession: false } });
const email = `repair-evidence-${randomUUID()}@example.test`;
const password = randomUUID() + "Ab1!";
const image = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==", "base64");

function ok(result, label) {
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  return result.data;
}

const created = ok(await admin.auth.admin.createUser({ email, password, email_confirm: true }), "create user");
ok(await user.auth.signInWithPassword({ email, password }), "sign in");
const org = ok(await user.rpc("create_organization", { p_name: "Repair evidence storage check" }), "create org");
const caseResult = ok(await user.rpc("create_repair_case", {
  p_org_id: org.id, p_device_model: "Test GPS", p_raw_identifier: "490154203237518",
  p_customer_name: "Storage test", p_issue: "Evidence verification", p_priority: "normal",
  p_source: "internal", p_idempotency_key: randomUUID(),
}), "create case");
const path = `${org.id}/${caseResult.caseId}/${randomUUID()}.png`;
const receipt = { p_org_id: org.id, p_case_id: caseResult.caseId, p_expected_version: 1,
  p_method: "internal", p_location: "Test bench", p_custodian: "Test owner", p_items: "",
  p_verified_imei: "490154203237518", p_imei_evidence: path };

const missing = await user.rpc("receive_repair_device", { ...receipt, p_idempotency_key: randomUUID() });
if (!missing.error?.message.includes("IMEI_EVIDENCE_REQUIRED")) throw new Error("Missing object was accepted");

ok(await user.storage.from("repair-imei-evidence").upload(path, image, {
  contentType: "image/png", upsert: false,
}), "upload evidence");
const otherCase = ok(await user.rpc("create_repair_case", {
  p_org_id: org.id, p_device_model: "Other test GPS", p_raw_identifier: "",
  p_customer_name: "Storage test", p_issue: "Cross-case evidence check", p_priority: "normal",
  p_source: "internal", p_idempotency_key: randomUUID(),
}), "create other case");
const borrowed = await user.rpc("receive_repair_device", {
  ...receipt, p_case_id: otherCase.caseId, p_idempotency_key: randomUUID(),
});
if (!borrowed.error?.message.includes("IMEI_EVIDENCE_REQUIRED")) {
  throw new Error("Evidence from another case was accepted");
}
const accepted = ok(await user.rpc("receive_repair_device", {
  ...receipt, p_idempotency_key: randomUUID(),
}), "receive device");
if (accepted.version !== 2 || !accepted.verifiedDeviceId) throw new Error("Receipt did not verify IMEI");

const link = ok(await user.storage.from("repair-imei-evidence").createSignedUrl(path, 60), "signed URL");
const response = await fetch(link.signedUrl);
if (!response.ok || !Buffer.from(await response.arrayBuffer()).equals(image)) {
  throw new Error("Evidence bytes could not be retrieved");
}
ok(await user.rpc("transition_repair_case", { p_org_id: org.id, p_case_id: caseResult.caseId,
  p_expected_version: 2, p_transition_code: "T01", p_idempotency_key: randomUUID() }), "enter diagnosis");
const diagnosis = ok(await user.rpc("save_repair_diagnosis", { p_org_id: org.id,
  p_case_id: caseResult.caseId, p_expected_version: 3, p_idempotency_key: randomUUID(),
  p_findings: "Power circuit damaged", p_technical_condition: "needs_repair",
  p_recommended_action: "repair", p_warranty_coverage: "pending" }), "save diagnosis");
const visible = ok(await user.from("repair_diagnoses").select("id, revision, status")
  .eq("org_id", org.id).eq("case_id", caseResult.caseId).single(), "read diagnosis via RLS");
if (visible.id !== diagnosis.diagnosisId || visible.revision !== 1 || visible.status !== "draft") {
  throw new Error("Diagnosis was not visible through the Data API");
}
ok(await user.rpc("finalize_repair_diagnosis", { p_org_id: org.id, p_case_id: caseResult.caseId,
  p_diagnosis_id: diagnosis.diagnosisId, p_expected_version: 4,
  p_idempotency_key: randomUUID() }), "finalize diagnosis");
const decision = ok(await user.rpc("transition_repair_case", { p_org_id: org.id,
  p_case_id: caseResult.caseId, p_expected_version: 5, p_transition_code: "T02",
  p_idempotency_key: randomUUID() }), "enter decision");
if (decision.stage !== "decision" || decision.version !== 6) throw new Error("T02 did not advance the case");
const plan = ok(await user.rpc("save_repair_action_plan", { p_org_id: org.id,
  p_case_id: caseResult.caseId, p_expected_version: 6, p_idempotency_key: randomUUID(),
  p_route: "repair", p_scope: "Repair power circuit", p_financial_basis: "customer_paid",
  p_amount_irr: 100000, p_parts_strategy: "no_parts" }), "save action plan");
const visiblePlan = ok(await user.from("repair_action_plans").select("id, revision, amount_irr")
  .eq("org_id", org.id).eq("case_id", caseResult.caseId).single(), "read plan via RLS");
if (visiblePlan.id !== plan.planId || visiblePlan.revision !== 1 || visiblePlan.amount_irr !== 100000) {
  throw new Error("Decision plan was not visible through the Data API");
}
ok(await user.rpc("record_repair_plan_approval", { p_org_id: org.id,
  p_case_id: caseResult.caseId, p_plan_id: plan.planId, p_expected_version: 7,
  p_idempotency_key: randomUUID(), p_kind: "customer", p_decision: "approved",
  p_channel: "phone", p_subject_name: "Customer", p_subject_role: "owner",
  p_evidence_reference: "test-call-1", p_stated_at: new Date().toISOString() }), "record customer response");
const visibleApproval = ok(await user.from("repair_plan_approvals").select("id, kind, decision")
  .eq("org_id", org.id).eq("plan_id", plan.planId).single(), "read approval via RLS");
if (visibleApproval.kind !== "customer" || visibleApproval.decision !== "approved") {
  throw new Error("Customer response was not visible through the Data API");
}
console.log(`Real upload, diagnosis, decision plan, and customer approval APIs passed: ${org.id}/${caseResult.caseId}`);

ok(await admin.storage.from("repair-imei-evidence").remove([path]), "remove test image");
const cleanup = spawnSync("psql", ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1",
  "-p", "55422", "-U", "postgres", "-d", "postgres"], {
  input: `begin;
    delete from private.repair_command_receipts where org_id = '${org.id}';
    delete from public.repair_case_events where org_id = '${org.id}';
    delete from public.repair_plan_approvals where org_id = '${org.id}';
    delete from public.repair_action_plans where org_id = '${org.id}';
    delete from public.repair_diagnoses where org_id = '${org.id}';
    delete from public.tracking_codes where org_id = '${org.id}';
    delete from public.repair_cases where org_id = '${org.id}';
    delete from public.repair_devices where org_id = '${org.id}';
    delete from public.attendance_event_types where org_id = '${org.id}';
    delete from public.leave_types where org_id = '${org.id}';
    delete from public.org_members where org_id = '${org.id}';
    delete from public.role_permissions where role_id in (select id from public.roles where org_id = '${org.id}');
    delete from public.roles where org_id = '${org.id}';
    delete from public.audit_log where org_id = '${org.id}';
    delete from public.organizations where id = '${org.id}';
    commit;`,
  encoding: "utf8", env: { ...process.env, PGPASSWORD: "postgres" },
});
if (cleanup.status !== 0) throw new Error(`Fixture cleanup failed: ${cleanup.stderr.trim()}`);
ok(await admin.auth.admin.deleteUser(created.user.id), "delete test user");
console.log("Disposable organization, user, and file removed");
