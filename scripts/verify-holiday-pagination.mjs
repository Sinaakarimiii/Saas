import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { fetchHolidayDates } from '../src/lib/holiday-dates.ts';

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

const options = { auth: { autoRefreshToken: false, persistSession: false } };
const admin = createClient(status.API_URL, status.SERVICE_ROLE_KEY, options);
const member = createClient(status.API_URL, status.ANON_KEY, options);
const email = `holiday-check-${randomUUID()}@example.test`;
const password = randomBytes(24).toString('base64url');
const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
if (created.error) throw created.error;
const signed = await member.auth.signInWithPassword({ email, password });
if (signed.error) throw signed.error;

const count = await member.from('calendar_events')
  .select('id', { count: 'exact', head: true }).eq('is_holiday', true);
if (count.error) throw count.error;
const dates = await fetchHolidayDates(member);
assert.equal(dates.length, count.count);
assert.ok(dates.length > 1000, 'fixture must exercise more than one API page');
assert.ok(dates.every((date, index) => index === 0 || dates[index - 1] <= date));
console.log(JSON.stringify({ holidayRows: dates.length, pagesBeyondDefaultLimit: true }));
