import { execFileSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const workdir = resolve(process.argv[2] ?? '');
if (!process.argv[2]) throw new Error('Provide the isolated Supabase workdir.');
if (process.argv[3] && process.argv[3] !== '--secondary') throw new Error('Only --secondary is supported.');
const secondary = process.argv[3] === '--secondary';
if (process.argv[4] && (process.argv[4] !== '--invite' || !secondary)) {
  throw new Error('Use --invite only with --secondary.');
}
const testInvite = process.argv[4] === '--invite';
const config = readFileSync(join(workdir, 'supabase', 'config.toml'), 'utf8');
if (!/^project_id = "org_platform_validation_[a-z0-9_]+"$/m.test(config)) {
  throw new Error('Only an org_platform_validation_* project is allowed.');
}
const status = JSON.parse(execFileSync('supabase', ['status', '--workdir', workdir, '--output', 'json'], {
  encoding: 'utf8', env: { ...process.env, SUPABASE_TELEMETRY_DISABLED: '1' }, stdio: ['ignore', 'pipe', 'pipe'],
}));
const api = new URL(status.API_URL);
const db = new URL(status.DB_URL);
if (api.hostname !== '127.0.0.1' || api.port !== (secondary ? '56321' : '55321')
    || db.hostname !== '127.0.0.1' || db.port !== (secondary ? '56322' : '55322')) {
  throw new Error('Refusing to run against an unexpected endpoint.');
}
const options = { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } };
const admin = createClient(status.API_URL, status.SERVICE_ROLE_KEY, options);
const client = () => createClient(status.API_URL, status.ANON_KEY, options);
function ok(response, label) {
  if (response.error || !response.data) throw new Error(`${label}: ${response.error?.code ?? 'no data'} ${response.error?.message ?? ''}`);
  return response.data;
}
function denied(response, label) {
  if (!response.error) throw new Error(`${label}: unexpectedly allowed`);
}
function noEffect(response, label) {
  if (response.error || response.data !== null) {
    throw new Error(`${label}: expected an error-free update of zero rows`);
  }
}
const run = randomUUID().slice(0, 8);
async function user(label) {
  const email = `${label}-${run}@example.test`;
  const password = randomBytes(24).toString('base64url');
  const created = ok(await admin.auth.admin.createUser({ email, password, email_confirm: true }), `create ${label}`);
  const signed = client();
  ok(await signed.auth.signInWithPassword({ email, password }), `sign in ${label}`);
  return { id: created.user.id, client: signed };
}
const owner = await user('security-owner');
const member = await user('security-member');
const creator = await user('security-creator');
const manager = await user('security-manager');
const invitee = await user('security-invitee');
const other = await user('security-other');
const org = ok(await owner.client.rpc('create_organization', { p_name: `Security ${run}` }), 'org');
const otherOrg = ok(await other.client.rpc('create_organization', { p_name: `Other ${run}` }), 'other org');
const otherRole = ok(await other.client.from('roles').select('id').eq('org_id', otherOrg.id).eq('is_system', true).single(), 'other role');
const role = ok(await admin.from('roles').insert({ org_id: org.id, name: `Record ${run}` }).select('id').single(), 'member role');
const ownerRole = ok(await owner.client.from('roles').select('id').eq('org_id', org.id).eq('is_system', true).single(), 'owner role');
const managerRole = ok(await owner.client.from('roles').insert({ org_id: org.id, name: `Manager ${run}` }).select('id').single(), 'manager role');
const approvedRole = ok(await owner.client.from('roles').insert({ org_id: org.id, name: `Approved ${run}` }).select('id').single(), 'approved role');
ok(await owner.client.from('roles').update({ manager_invitable: true }).eq('id', approvedRole.id).select('id').single(), 'approve invitation role');
ok(await owner.client.from('role_permissions').insert({ role_id: managerRole.id, permission_key: 'org.manage_members' }).select('role_id').single(), 'manager permission');
const managerMembership = ok(await owner.client.from('org_members').insert({ org_id: org.id, user_id: manager.id, role_id: managerRole.id, invited_by: owner.id }).select('id').single(), 'manager membership');
ok(await owner.client.from('org_members').select('id, roles(name), profiles(email)').eq('id', managerMembership.id).single(), 'membership embedding');
denied(await manager.client.from('org_members').insert({ org_id: org.id, user_id: invitee.id, role_id: ownerRole.id, invited_by: manager.id }), 'manager owner grant');
denied(await manager.client.from('org_members').insert({ org_id: org.id, user_id: invitee.id, role_id: role.id, invited_by: manager.id }), 'manager unapproved role');
const inviteeMembership = ok(await manager.client.from('org_members').insert({ org_id: org.id, user_id: invitee.id, role_id: approvedRole.id, invited_by: manager.id }).select('id').single(), 'manager approved role');
denied(await manager.client.from('org_members').update({ role_id: ownerRole.id }).eq('id', managerMembership.id), 'manager self elevation');
denied(await manager.client.from('roles').update({ manager_invitable: true }).eq('id', managerRole.id).select('id').single(), 'manager approves role');
denied(await manager.client.rpc('set_role_permissions', { p_role_id: managerRole.id, p_permissions: [{ key: 'org.manage_roles', scope: null }] }), 'manager role permission escalation');
ok(await manager.client.from('org_members').update({ manager_id: managerMembership.id }).eq('id', inviteeMembership.id).select('id').single(), 'manager changes supervisor');
const ownerMembership = ok(await owner.client.from('org_members').select('id').eq('org_id', org.id).eq('user_id', owner.id).single(), 'owner membership');
denied(await owner.client.from('org_members').update({ role_id: approvedRole.id }).eq('id', ownerMembership.id), 'last-owner demotion');
const createOnlyRole = ok(await admin.from('roles').insert({ org_id: org.id, name: `Create Only ${run}` }).select('id').single(), 'create-only role');
ok(await admin.from('role_permissions').insert({ role_id: createOnlyRole.id, permission_key: 'ticket.create' }).select('role_id').single(), 'create-only permission');
ok(await admin.from('org_members').insert({ org_id: org.id, user_id: creator.id, role_id: createOnlyRole.id }).select('id').single(), 'create-only membership');
ok(await admin.from('role_permissions').insert({ role_id: role.id, permission_key: 'attendance.record' }).select('role_id').single(), 'record permission');
ok(await admin.from('role_permissions').insert([
  { role_id: role.id, permission_key: 'ticket.create', scope: null },
  { role_id: role.id, permission_key: 'ticket.view', scope: 'own' },
  { role_id: role.id, permission_key: 'ticket.edit', scope: 'own' },
]).select('role_id'), 'ticket permissions');
const membership = ok(await admin.from('org_members').insert({ org_id: org.id, user_id: member.id, role_id: role.id }).select('id').single(), 'membership');
denied(await owner.client.from('org_members').update({ role_id: otherRole.id }).eq('id', membership.id), 'cross-org role');
const form = ok(await owner.client.from('form_templates').insert({ org_id: org.id, name: `Form ${run}`, created_by: owner.id }).select('id').single(), 'form');
const otherForm = ok(await other.client.from('form_templates').insert({ org_id: otherOrg.id, name: `Other Form ${run}`, created_by: other.id }).select('id').single(), 'other form');
denied(await owner.client.from('tickets').insert({ org_id: org.id, form_template_id: otherForm.id, created_by: owner.id }), 'cross-org ticket form');
const ticket = ok(await owner.client.from('tickets').insert({ org_id: org.id, form_template_id: form.id, created_by: owner.id }).select('id').single(), 'ticket');
const secondForm = ok(await owner.client.from('form_templates').insert({ org_id: org.id, name: `Second Form ${run}`, created_by: owner.id }).select('id').single(), 'second form');
const unrelatedField = ok(await owner.client.from('form_fields').insert({ form_template_id: secondForm.id, key: `unrelated_${run}`, label: 'Unrelated', field_type: 'text' }).select('id').single(), 'unrelated field');
denied(await owner.client.from('ticket_field_values').insert({ ticket_id: ticket.id, form_field_id: unrelatedField.id, value: 'incorrect' }), 'unrelated field insert');
const properField = ok(await owner.client.from('form_fields').insert({ form_template_id: form.id, key: `proper_${run}`, label: 'Proper', field_type: 'text' }).select('id').single(), 'proper field');
const createdOnly = ok(await creator.client.rpc('create_ticket', {
  p_org_id: org.id, p_form_template_id: form.id, p_title: 'Initial values',
  p_field_values: [{ form_field_id: properField.id, value: 'initial' }],
}), 'create-only initial values');
denied(await creator.client.from('ticket_field_values').insert({ ticket_id: ticket.id, form_field_id: properField.id, value: 'forgery' }), 'create-only existing ticket');
denied(await creator.client.from('ticket_field_values').update({ value: 'forgery' }).eq('ticket_id', createdOnly.id).eq('form_field_id', properField.id).select('id').single(), 'create-only later edit');
denied(await creator.client.rpc('update_ticket_status', { p_ticket_id: randomUUID(), p_status: 'closed' }), 'missing-ticket RPC');
const changedStatus = await owner.client.rpc('update_ticket_status', { p_ticket_id: ticket.id, p_status: 'closed' });
if (changedStatus.error) throw new Error(`valid ticket status: ${changedStatus.error.code}`);
const closedTicket = ok(await owner.client.from('tickets').select('status').eq('id', ticket.id).single(), 'closed ticket');
if (closedTicket.status !== 'closed') throw new Error('Valid status mutation had no effect.');
const value = ok(await owner.client.from('ticket_field_values').insert({ ticket_id: ticket.id, form_field_id: properField.id, value: 'valid' }).select('id').single(), 'proper value');
denied(await owner.client.from('ticket_field_values').update({ form_field_id: unrelatedField.id }).eq('id', value.id), 'unrelated field update');
denied(await owner.client.from('tickets').update({ form_template_id: secondForm.id }).eq('id', ticket.id), 'form reparent');
const fileField = ok(await owner.client.from('form_fields').insert({ form_template_id: form.id, key: `file_${run}`, label: 'Attachment', field_type: 'file' }).select('id').single(), 'file field');
const ownerPath = `${org.id}/${fileField.id}/${randomUUID()}-owner.txt`;
ok(await owner.client.storage.from('ticket-attachments').upload(ownerPath, new Blob(['owner attachment'], { type: 'text/plain' })), 'owner upload');
ok(await owner.client.from('ticket_field_values').insert({ ticket_id: ticket.id, form_field_id: fileField.id, value: { storage_path: ownerPath, file_name: 'owner.txt' } }).select('id').single(), 'owner attachment reference');
ok(await owner.client.storage.from('ticket-attachments').createSignedUrl(ownerPath, 60), 'owner signed URL');
denied(await member.client.storage.from('ticket-attachments').createSignedUrl(ownerPath, 60), 'colleague signed URL');
denied(await member.client.storage.from('ticket-attachments').download(ownerPath), 'colleague download');
const memberTicket = ok(await member.client.from('tickets').insert({ org_id: org.id, form_template_id: form.id, created_by: member.id }).select('id').single(), 'member ticket');
denied(await member.client.from('ticket_field_values').insert({ ticket_id: memberTicket.id, form_field_id: fileField.id, value: { storage_path: ownerPath } }), 'known-path laundering');
const memberPath = `${org.id}/${fileField.id}/${randomUUID()}-member.txt`;
ok(await member.client.storage.from('ticket-attachments').upload(memberPath, new Blob(['member attachment'], { type: 'text/plain' })), 'member upload');
ok(await member.client.from('ticket_field_values').insert({ ticket_id: memberTicket.id, form_field_id: fileField.id, value: { storage_path: memberPath } }).select('id').single(), 'member attachment reference');
ok(await member.client.storage.from('ticket-attachments').createSignedUrl(memberPath, 60), 'own signed URL');
ok(await owner.client.storage.from('ticket-attachments').createSignedUrl(memberPath, 60), 'all-scope signed URL');
const validAudit = ok(await owner.client.from('audit_log').select('id, actor_id').eq('record_id', ticket.id).eq('table_name', 'tickets').eq('action', 'insert').is('field_name', null).single(), 'valid ticket audit');
if (validAudit.actor_id !== owner.id) throw new Error('Valid audit actor mismatch.');
denied(await member.client.from('audit_log').insert({ org_id: org.id, actor_id: other.id, table_name: 'org_members', record_id: randomUUID() }), 'forged audit');
const nonTicketAudit = ok(await admin.from('audit_log').insert({ org_id: org.id, actor_id: owner.id, table_name: 'org_members', record_id: membership.id }).select('id').single(), 'trusted audit fixture');
const memberAudit = ok(await member.client.from('audit_log').select('id').eq('id', nonTicketAudit.id), 'member audit select');
if (memberAudit.length !== 0) throw new Error('Member could read general audit.');
const ownerAudit = ok(await owner.client.from('audit_log').select('id').eq('id', nonTicketAudit.id), 'owner audit select');
if (ownerAudit.length !== 1) throw new Error('Owner cannot read general audit.');
const type = ok(await member.client.from('attendance_event_types').select('id').eq('org_id', org.id).eq('kind', 'clock_in').single(), 'event type');
const otherType = ok(await other.client.from('attendance_event_types').select('id').eq('org_id', otherOrg.id).eq('kind', 'clock_in').single(), 'other event type');
denied(await member.client.from('attendance_logs').insert({ org_id: org.id, member_id: membership.id, event_type_id: otherType.id, created_by: member.id }), 'cross-org attendance type');
const log = ok(await member.client.from('attendance_logs').insert({ org_id: org.id, member_id: membership.id, event_type_id: type.id, created_by: member.id }).select('id, occurred_at').single(), 'attendance insert');
denied(await member.client.from('attendance_logs').update({ occurred_at: '2000-01-01T00:00:00Z', voided_at: new Date().toISOString() }).eq('id', log.id), 'historical update');
const unchanged = ok(await member.client.from('attendance_logs').select('occurred_at, voided_at').eq('id', log.id).single(), 'unchanged attendance');
if (unchanged.occurred_at !== log.occurred_at || unchanged.voided_at !== null) throw new Error('Attendance history changed.');
ok(await member.client.from('attendance_logs').update({ voided_at: '2000-01-01T00:00:00Z', voided_by: other.id }).eq('id', log.id).select('id').single(), 'valid void');
const voided = ok(await member.client.from('attendance_logs').select('voided_at, voided_by').eq('id', log.id).single(), 'void state');
if (voided.voided_by !== member.id || voided.voided_at.startsWith('2000')) throw new Error('Void actor/time was client-controlled.');
denied(await member.client.from('attendance_logs').update({ voided_at: new Date().toISOString() }).eq('id', log.id), 'second void');
noEffect(await member.client.from('attendance_logs').update({ voided_at: new Date().toISOString() }).eq('id', log.id).eq('org_id', org.id).is('voided_at', null).select('id').maybeSingle(), 'void action on an already voided log');
noEffect(await owner.client.from('org_members').update({ manager_id: null }).eq('id', randomUUID()).eq('org_id', org.id).select('id').maybeSingle(), 'member action on missing row');
const shiftTemplate = ok(await owner.client.from('shift_templates').insert({ org_id: org.id, name: `Shift ${run}`, start_time: '09:00', end_time: '17:00' }).select('id').single(), 'valid shift template');
const assignment = ok(await owner.client.from('shift_assignments').insert({ org_id: org.id, member_id: ownerMembership.id, shift_template_id: shiftTemplate.id, title: 'Test shift', work_date: '2026-09-20', start_time: '09:00', end_time: '17:00', created_by: owner.id }).select('id').single(), 'valid assignment');
ok(await owner.client.from('shift_templates').update({ deleted_at: new Date().toISOString() }).eq('id', shiftTemplate.id).eq('org_id', org.id).is('deleted_at', null).select('id').single(), 'valid template removal');
noEffect(await owner.client.from('shift_templates').update({ deleted_at: new Date().toISOString() }).eq('id', shiftTemplate.id).eq('org_id', org.id).is('deleted_at', null).select('id').maybeSingle(), 'repeated template removal');
ok(await owner.client.from('shift_assignments').update({ deleted_at: new Date().toISOString() }).eq('id', assignment.id).eq('org_id', org.id).is('deleted_at', null).select('id').single(), 'valid assignment removal');
noEffect(await owner.client.from('shift_assignments').update({ deleted_at: new Date().toISOString() }).eq('id', assignment.id).eq('org_id', org.id).is('deleted_at', null).select('id').maybeSingle(), 'repeated assignment removal');
const leaveType = ok(await owner.client.from('leave_types').insert({ org_id: org.id, name: `Leave ${run}`, unit: 'day' }).select('id').single(), 'valid leave type');
const leave = ok(await owner.client.from('leave_requests').insert({ org_id: org.id, member_id: ownerMembership.id, leave_type_id: leaveType.id, starts_at: '2026-09-22T05:30:00Z', ends_at: '2026-09-23T05:30:00Z', created_by: owner.id }).select('id').single(), 'valid leave request');
ok(await owner.client.from('leave_requests').update({ status: 'approved', reviewed_by: owner.id, reviewed_at: new Date().toISOString() }).eq('id', leave.id).eq('org_id', org.id).select('id').single(), 'valid leave review');
noEffect(await owner.client.from('leave_requests').update({ status: 'approved' }).eq('id', randomUUID()).eq('org_id', org.id).select('id').maybeSingle(), 'leave action on missing row');

if (secondary) {
  denied(await owner.client.from('org_members').update({ role_id: ownerRole.id }).eq('id', inviteeMembership.id), 'direct owner promotion');
  denied(await owner.client.rpc('transfer_org_ownership', {
    p_org_id: org.id, p_successor_member_id: inviteeMembership.id,
    p_former_owner_role_id: ownerRole.id,
  }), 'owner role as replacement');
  const beforeTransfer = ok(await admin.from('org_members').select('role_id').eq('id', ownerMembership.id).single(), 'owner before failed transfer');
  if (beforeTransfer.role_id !== ownerRole.id) throw new Error('Failed transfer altered ownership.');
  const transferred = await owner.client.rpc('transfer_org_ownership', {
    p_org_id: org.id, p_successor_member_id: inviteeMembership.id,
    p_former_owner_role_id: approvedRole.id,
  });
  if (transferred.error) throw new Error(`valid transfer: ${transferred.error.code} ${transferred.error.message}`);
  const finalMembers = ok(await admin.from('org_members').select('id, role_id').in('id', [ownerMembership.id, inviteeMembership.id]), 'transfer outcome');
  if (finalMembers.find((m) => m.id === ownerMembership.id)?.role_id !== approvedRole.id
      || finalMembers.find((m) => m.id === inviteeMembership.id)?.role_id !== ownerRole.id) {
    throw new Error('Transfer did not atomically exchange roles.');
  }
  denied(await owner.client.rpc('transfer_org_ownership', {
    p_org_id: org.id, p_successor_member_id: managerMembership.id,
    p_former_owner_role_id: approvedRole.id,
  }), 'former owner repeats transfer');
  ok(await invitee.client.from('roles').update({ manager_invitable: true }).eq('id', managerRole.id).select('id').single(), 'new owner role management');
  const transferAudit = ok(await admin.from('audit_log').select('record_id, actor_id').eq('org_id', org.id).eq('table_name', 'org_members').eq('field_name', 'role_id').in('record_id', [ownerMembership.id, inviteeMembership.id]), 'transfer audit');
  if (transferAudit.length !== 2 || transferAudit.some((entry) => entry.actor_id !== owner.id)) {
    throw new Error('Transfer audit is incomplete or has the wrong actor.');
  }

  const raceOrg = ok(await owner.client.rpc('create_organization', { p_name: `Race ${run}` }), 'race org');
  const raceOwnerRole = ok(await owner.client.from('roles').select('id').eq('org_id', raceOrg.id).eq('is_system', true).single(), 'race owner role');
  const raceOrdinary = ok(await owner.client.from('roles').insert({ org_id: raceOrg.id, name: `Ordinary ${run}` }).select('id').single(), 'race ordinary role');
  const raceA = ok(await owner.client.from('org_members').insert({ org_id: raceOrg.id, user_id: member.id, role_id: raceOrdinary.id, invited_by: owner.id }).select('id').single(), 'race member A');
  const raceB = ok(await owner.client.from('org_members').insert({ org_id: raceOrg.id, user_id: manager.id, role_id: raceOrdinary.id, invited_by: owner.id }).select('id').single(), 'race member B');
  const concurrent = await Promise.all([
    owner.client.rpc('transfer_org_ownership', { p_org_id: raceOrg.id, p_successor_member_id: raceA.id, p_former_owner_role_id: raceOrdinary.id }),
    owner.client.rpc('transfer_org_ownership', { p_org_id: raceOrg.id, p_successor_member_id: raceB.id, p_former_owner_role_id: raceOrdinary.id }),
  ]);
  if (concurrent.filter((response) => !response.error).length !== 1) {
    throw new Error('Concurrent transfers did not produce exactly one winner.');
  }
  const raceMembers = ok(await admin.from('org_members').select('role_id').eq('org_id', raceOrg.id), 'race outcome');
  if (raceMembers.filter((m) => m.role_id === raceOwnerRole.id).length !== 1) {
    throw new Error('Concurrent transfer left an inconsistent owner count.');
  }

  if (testInvite) {
    const email = `controlled-invite-${run}@example.test`;
    const invited = ok(await admin.auth.admin.inviteUserByEmail(email, {
      redirectTo: 'http://127.0.0.1:3200/auth/set-password',
    }), 'controlled local invitation');
    ok(await manager.client.from('org_members').insert({
      org_id: org.id, user_id: invited.user.id, role_id: approvedRole.id,
      invited_by: manager.id,
    }).select('id').single(), 'invited membership under manager policy');
    const mailResponse = await fetch('http://127.0.0.1:56324/api/v1/messages');
    if (!mailResponse.ok || !JSON.stringify(await mailResponse.json()).includes(email)) {
      throw new Error('Controlled invitation was not captured by local Mailpit.');
    }
  }
}

console.log(JSON.stringify({ environment: 'isolated-local', organizations: secondary ? 3 : 2, realUserSessions: 6, roles: 'approved invitation allowed; elevation/role edit/last-owner removal denied', validAudit: 'passed', forgedAudit: 'denied', generalAudit: 'owner-only', organizationAndFormLinks: 'validated', createOnly: 'initial values allowed; later/other edits denied', attachments: 'own/all allowed; colleague direct, signed, laundering denied', attendanceHistory: 'immutable', attendanceVoid: 'server-actor-and-time, once', noEffectContracts: 'member/leave/shift/attendance/status checked', atomicOwnerTransfer: secondary ? 'valid/invalid/concurrent/audited passed' : 'not run on preview', controlledInvite: testInvite ? 'Mailpit captured; membership allowed' : 'not run' }, null, 2));
