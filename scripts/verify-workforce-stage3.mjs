import { execFileSync } from "node:child_process";
import { randomBytes, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { createClient } from "@supabase/supabase-js";

const workdir = resolve(process.argv[2] ?? "");
if (!process.argv[2]) throw new Error("Provide the isolated Supabase workdir.");
const config = readFileSync(join(workdir, "supabase", "config.toml"), "utf8");
if (!/^project_id = "org_platform_validation_[a-z0-9_]+"$/m.test(config)) {
  throw new Error("Only an isolated org_platform_validation_* project is allowed.");
}
const status = JSON.parse(execFileSync("supabase", ["status", "--workdir", workdir, "--output", "json"], {
  encoding: "utf8", env: { ...process.env, SUPABASE_TELEMETRY_DISABLED: "1" }, stdio: ["ignore", "pipe", "pipe"],
}));
if (new URL(status.API_URL).host !== "127.0.0.1:57321" || new URL(status.DB_URL).host !== "127.0.0.1:57322") {
  throw new Error("Refusing to run outside the tertiary isolated validation stack.");
}
const options = { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } };
const admin = createClient(status.API_URL, status.SERVICE_ROLE_KEY, options);
const client = () => createClient(status.API_URL, status.ANON_KEY, options);
const run = randomUUID().slice(0, 8);
function ok(response, label) {
  if (response.error || response.data == null) throw new Error(`${label}: ${response.error?.code ?? "no data"} ${response.error?.message ?? ""}`);
  return response.data;
}
function denied(response, label) {
  if (!response.error) throw new Error(`${label}: unexpectedly allowed`);
}
async function user(label) {
  const email = `${label}-${run}@example.test`;
  const password = randomBytes(24).toString("base64url");
  const created = ok(await admin.auth.admin.createUser({ email, password, email_confirm: true }), `create ${label}`);
  const signed = client();
  ok(await signed.auth.signInWithPassword({ email, password }), `sign in ${label}`);
  return { id: created.user.id, client: signed };
}
async function saveRole(actor, orgId, roleId, name, rank, permissions, label) {
  return ok(await actor.rpc("save_role", {
    p_org_id: orgId, p_role_id: roleId, p_name: name, p_management_rank: rank, p_permissions: permissions,
  }), label);
}

const owner = await user("stage3-owner");
const manager = await user("stage3-manager");
const worker = await user("stage3-worker");
const outsider = await user("stage3-outsider");
const org = ok(await owner.client.rpc("create_organization", { p_name: `Stage3 ${run}` }), "create organization");
const otherOrg = ok(await outsider.client.rpc("create_organization", { p_name: `Other ${run}` }), "create other organization");

const managerRole = await saveRole(owner.client, org.id, null, `Role manager ${run}`, 60, [
  { key: "org.manage_roles", scope: null }, { key: "shift.manage", scope: "team" }, { key: "ticket.view", scope: "own" },
], "create manager role");
const workerRole = await saveRole(owner.client, org.id, null, `Worker ${run}`, 10, [
  { key: "ticket.view", scope: "own" },
], "create worker role");
const managerMembership = ok(await owner.client.from("org_members").insert({
  org_id: org.id, user_id: manager.id, role_id: managerRole, invited_by: owner.id,
}).select("id").single(), "create manager membership");
const workerMembership = ok(await owner.client.from("org_members").insert({
  org_id: org.id, user_id: worker.id, role_id: workerRole, manager_id: managerMembership.id, invited_by: owner.id,
}).select("id").single(), "create worker membership");

denied(await manager.client.from("role_permissions").insert({
  role_id: workerRole, permission_key: "attendance.record",
}), "direct role permission write");
denied(await manager.client.rpc("set_role_permissions", {
  p_role_id: managerRole, p_permissions: [{ key: "org.manage_roles", scope: null }],
}), "manager edits peer role");
denied(await manager.client.rpc("save_role", {
  p_org_id: org.id, p_role_id: workerRole, p_name: `Worker ${run}`, p_management_rank: 10,
  p_permissions: [{ key: "attendance.record", scope: null }],
}), "permission ceiling");
ok(await manager.client.rpc("save_role", {
  p_org_id: org.id, p_role_id: workerRole, p_name: `Worker ${run}`, p_management_rank: 10,
  p_permissions: [{ key: "ticket.view", scope: "own" }],
}), "manager edits lower role within ceiling");
denied(await manager.client.from("roles").update({ manager_invitable: true }).eq("id", workerRole).select("id").single(), "manager invitation approval");

ok(await manager.client.from("org_members").update({ work_mode: "fixed" }).eq("id", workerMembership.id).select("id").single(), "team manager changes work mode");
ok(await manager.client.from("fixed_work_schedules").insert({
  org_id: org.id, member_id: workerMembership.id, weekday: 1, start_time: "09:00", end_time: "17:00",
}).select("id").single(), "team manager fixed schedule");
denied(await manager.client.from("shift_patterns").insert({
  org_id: org.id, shift_template_id: randomUUID(), valid_from: "2026-09-22", weekdays: [1], created_by: manager.id,
}), "team manager organization-wide pattern");

const template = ok(await owner.client.from("shift_templates").insert({
  org_id: org.id, name: `Template ${run}`, start_time: "09:00", end_time: "17:00",
}).select("id").single(), "create template");
const pattern = ok(await owner.client.from("shift_patterns").insert({
  org_id: org.id, shift_template_id: template.id, valid_from: "2026-09-22", weekdays: [1], created_by: owner.id,
}).select("id").single(), "create pattern");
const outsiderRole = ok(await admin.from("roles").select("id").eq("org_id", otherOrg.id).eq("system_key", "owner").single(), "other owner role");
const outsiderMembership = ok(await admin.from("org_members").select("id").eq("org_id", otherOrg.id).eq("user_id", outsider.id).single(), "other membership");
denied(await admin.from("shift_pattern_members").insert({
  org_id: org.id, pattern_id: pattern.id, member_id: outsiderMembership.id,
}), "cross-organization pattern member");
if (!outsiderRole.id) throw new Error("fixture role missing");

console.log(JSON.stringify({ environment: "isolated-local", roleDelegation: "ceiling enforced", directPermissionWrites: "denied", shiftTeamScope: "enforced", workMode: "team manager allowed", crossOrganizationPatterns: "denied" }, null, 2));
