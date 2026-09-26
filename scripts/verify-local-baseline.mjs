import { execFileSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const workdir = resolve(process.argv[2] ?? '');
if (!process.argv[2]) throw new Error('Provide the isolated Supabase workdir.');
const config = readFileSync(join(workdir, 'supabase', 'config.toml'), 'utf8');
if (!/^project_id = "org_platform_validation_[a-z0-9_]+"$/m.test(config)) {
  throw new Error('Only an org_platform_validation_* project is allowed.');
}
const status = JSON.parse(execFileSync('supabase', ['status', '--workdir', workdir, '--output', 'json'], {
  encoding: 'utf8', env: { ...process.env, SUPABASE_TELEMETRY_DISABLED: '1' }, stdio: ['ignore', 'pipe', 'pipe'],
}));
const api = new URL(status.API_URL);
const db = new URL(status.DB_URL);
if (api.hostname !== '127.0.0.1' || api.port !== '55321' || db.hostname !== '127.0.0.1' || db.port !== '55322') {
  throw new Error('Refusing to run against an unexpected endpoint.');
}
const options = { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } };
const admin = createClient(status.API_URL, status.SERVICE_ROLE_KEY, options);
const freshClient = () => createClient(status.API_URL, status.ANON_KEY, options);
function result({ data, error }, label) {
  if (error) throw new Error(`${label}: ${error.code ?? error.name}`);
  if (!data) throw new Error(`${label}: no data`);
  return data;
}
const run = randomUUID().slice(0, 8);
async function user(label) {
  const email = `${label}-${run}@example.test`;
  const password = randomBytes(24).toString('base64url');
  const created = result(await admin.auth.admin.createUser({ email, password, email_confirm: true }), `create ${label}`);
  const client = freshClient();
  result(await client.auth.signInWithPassword({ email, password }), `sign in ${label}`);
  return { id: created.user.id, client };
}
const ownerA = await user('owner-a');
const memberA = await user('member-a');
const ownerB = await user('owner-b');
const memberB = await user('member-b');
const orgA = result(await ownerA.client.rpc('create_organization', { p_name: `Validation A ${run}` }), 'org A');
const orgB = result(await ownerB.client.rpc('create_organization', { p_name: `Validation B ${run}` }), 'org B');
result(await admin.from('roles').select('id').eq('org_id', orgA.id).eq('is_system', true).single(), 'owner role A');
result(await admin.from('roles').select('id').eq('org_id', orgB.id).eq('is_system', true).single(), 'owner role B');
const memberRoleA = result(await admin.from('roles').insert({ org_id: orgA.id, name: `Validation Member ${run}`, is_system: false }).select('id').single(), 'member role A');
const memberRoleB = result(await admin.from('roles').insert({ org_id: orgB.id, name: `Validation Member ${run}`, is_system: false }).select('id').single(), 'member role B');
result(await admin.from('org_members').insert([
  { org_id: orgA.id, user_id: memberA.id, role_id: memberRoleA.id },
  { org_id: orgB.id, user_id: memberB.id, role_id: memberRoleB.id },
]).select('id'), 'members');
const form = result(await ownerA.client.from('form_templates').insert({ org_id: orgA.id, name: `Validation Form ${run}`, created_by: ownerA.id }).select('id').single(), 'form');
const ticket = result(await ownerA.client.from('tickets').insert({ org_id: orgA.id, form_template_id: form.id, title: `Validation Ticket ${run}`, created_by: ownerA.id }).select('id').single(), 'ticket');
const validAudit = result(await admin.from('audit_log').select('id, actor_id').eq('org_id', orgA.id).eq('table_name', 'tickets').eq('record_id', ticket.id).eq('action', 'insert').single(), 'trigger audit');
if (validAudit.actor_id !== ownerA.id) throw new Error('Trigger actor mismatch.');
const forged = await memberA.client.from('audit_log').insert({
  org_id: orgA.id, actor_id: ownerB.id, table_name: 'org_members', record_id: randomUUID(), action: 'update', note: 'validation-only forgery probe',
}).select('id').single();
const crossOrg = await memberA.client.from('audit_log').insert({
  org_id: orgB.id, actor_id: memberA.id, table_name: 'org_members', record_id: randomUUID(), action: 'update',
});
if (!crossOrg.error) throw new Error('Cross-org audit insert unexpectedly succeeded.');
const forgedPersisted = forged.error ? false : Boolean(result(await admin.from('audit_log').select('id').eq('id', forged.data.id).single(), 'forged row'));
console.log(JSON.stringify({
  environment: 'isolated-local', project: 'org_platform_validation', users: 4, organizations: 2,
  roleKinds: ['owner', 'member'], validTriggerAudit: true, crossOrgInsertDenied: true,
  directForgedAuditDenied: Boolean(forged.error) && !forgedPersisted,
}, null, 2));
if (!forged.error || forgedPersisted) throw new Error('Forged audit insert unexpectedly succeeded.');
