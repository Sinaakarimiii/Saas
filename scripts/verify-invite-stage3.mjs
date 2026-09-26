import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const workdir = resolve(process.argv[2] ?? '');
if (!process.argv[2] || process.argv[3] !== '--secondary') {
  throw new Error('Use an isolated validation workdir with --secondary.');
}
const config = readFileSync(join(workdir, 'supabase', 'config.toml'), 'utf8');
if (!/^project_id = "org_platform_validation_[a-z0-9_]+"$/m.test(config)) {
  throw new Error('Unexpected validation project.');
}
const status = JSON.parse(readFileSync(join(workdir, 'status.json'), 'utf8'));
if (status.API_URL !== 'http://127.0.0.1:56321' || !status.DB_URL.includes('127.0.0.1:56322')) {
  throw new Error('Unexpected validation endpoint.');
}

const options = { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } };
const admin = createClient(status.API_URL, status.SERVICE_ROLE_KEY, options);
const owner = createClient(status.API_URL, status.ANON_KEY, options);
const invitedClient = createClient(status.API_URL, status.ANON_KEY, options);
const suffix = randomUUID();
const ownerEmail = `invite-owner-${suffix}@example.test`;
const invitedEmail = `invite-recipient-${suffix}@example.test`;
const ownerPassword = randomBytes(24).toString('base64url');
const invitedPassword = randomBytes(24).toString('base64url');

function required(response, label) {
  if (response.error || !response.data) {
    throw new Error(`${label}: ${response.error?.code ?? 'missing data'}`);
  }
  return response.data;
}

const ownerUser = required(await admin.auth.admin.createUser({
  email: ownerEmail, password: ownerPassword, email_confirm: true,
}), 'create owner').user;
required(await owner.auth.signInWithPassword({ email: ownerEmail, password: ownerPassword }), 'owner sign-in');
const org = required(await owner.rpc('create_organization', { p_name: `Invite ${suffix}` }), 'create org');
const role = required(await owner.from('roles').insert({
  org_id: org.id, name: 'عضو آزمایشی',
}).select('id').single(), 'create role');
const invitedUser = required(await admin.auth.admin.inviteUserByEmail(invitedEmail, {
  redirectTo: 'http://127.0.0.1:3200/auth/set-password',
}), 'send controlled invite').user;
required(await owner.from('org_members').insert({
  org_id: org.id, user_id: invitedUser.id, role_id: role.id, invited_by: ownerUser.id,
}).select('id').single(), 'create membership');

const mailListResponse = await fetch('http://127.0.0.1:56324/api/v1/messages');
if (!mailListResponse.ok) throw new Error('Local Mailpit list failed');
const mailList = await mailListResponse.json();
const summary = mailList.messages?.find((message) => JSON.stringify(message.To).includes(invitedEmail));
if (!summary) throw new Error('Controlled invite was not captured by Mailpit');
const mailResponse = await fetch(`http://127.0.0.1:56324/api/v1/message/${encodeURIComponent(summary.ID)}`);
if (!mailResponse.ok) throw new Error('Local Mailpit message failed');
const mail = await mailResponse.json();
const match = mail.Text?.match(/https?:\/\/[^\s<>]+/);
if (!match) throw new Error('Invite email has no link');
const inviteLink = new URL(match[0]);
assert.equal(inviteLink.origin, status.API_URL);
assert.equal(inviteLink.pathname, '/auth/v1/verify');
assert.equal(inviteLink.searchParams.get('redirect_to'), 'http://127.0.0.1:3200/auth/set-password');

const verified = await fetch(inviteLink, { redirect: 'manual' });
if (![302, 303].includes(verified.status)) throw new Error('Invite verification did not redirect');
const redirect = new URL(verified.headers.get('location') ?? '', inviteLink);
assert.equal(redirect.origin, 'http://127.0.0.1:3200');
assert.equal(redirect.pathname, '/auth/set-password');
const fragment = new URLSearchParams(redirect.hash.slice(1));
const accessToken = fragment.get('access_token');
const refreshToken = fragment.get('refresh_token');
if (!accessToken || !refreshToken) {
  throw new Error(`Verified invite has no session: ${JSON.stringify({
    redirectPath: redirect.pathname,
    fragmentKeys: [...fragment.keys()],
    errorCode: fragment.get('error_code'),
  })}`);
}
required(await invitedClient.auth.setSession({
  access_token: accessToken, refresh_token: refreshToken,
}), 'accept invite session');
required(await invitedClient.auth.updateUser({ password: invitedPassword }), 'set password');
required(await invitedClient.from('profiles').update({
  full_name: 'عضو آزمایشی', phone: '09121234567',
}).eq('id', invitedUser.id).select('id').single(), 'complete profile');
await invitedClient.auth.signOut();
required(await invitedClient.auth.signInWithPassword({
  email: invitedEmail, password: invitedPassword,
}), 'sign in with chosen password');
const membership = required(await invitedClient.from('org_members').select('id, role_id')
  .eq('org_id', org.id).eq('user_id', invitedUser.id).single(), 'see membership');
assert.equal(membership.role_id, role.id);
console.log(JSON.stringify({ localMailCaptured: true, inviteVerified: true,
  passwordSet: true, memberSignIn: true, membershipVisible: true }));
