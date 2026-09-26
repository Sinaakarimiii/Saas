import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { delimiter, dirname, join, resolve } from 'node:path';

const workdir = resolve(process.argv[2] ?? '');
const divider = process.argv.indexOf('--');
if (!process.argv[2] || divider < 0 || !process.argv[divider + 1]) {
  throw new Error('Usage: node scripts/with-local-env.mjs <validation-workdir> [--secondary] -- <command> [args...]');
}
const secondary = process.argv[3] === '--secondary';
if (!((divider === 3 && !secondary) || (divider === 4 && secondary))) {
  throw new Error('Only --secondary is supported before the command.');
}
const config = readFileSync(join(workdir, 'supabase', 'config.toml'), 'utf8');
if (!/^project_id = "org_platform_validation_[a-z0-9_]+"$/m.test(config)) {
  throw new Error('Only an org_platform_validation_* project is allowed.');
}
const status = JSON.parse(readFileSync(join(workdir, 'status.json'), 'utf8'));
const apiPort = secondary ? '56321' : '55321';
const dbPort = secondary ? '56322' : '55322';
if (status.API_URL !== `http://127.0.0.1:${apiPort}` || !status.DB_URL.includes(`127.0.0.1:${dbPort}`)) {
  throw new Error('Validation endpoint mismatch.');
}
const env = {
  ...process.env,
  PATH: `${dirname(process.execPath)}${delimiter}${process.env.PATH ?? ''}`,
  NEXT_PUBLIC_SUPABASE_URL: status.API_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: status.ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY: status.SERVICE_ROLE_KEY,
  NEXT_PUBLIC_SITE_URL: secondary ? 'http://127.0.0.1:3200' : 'http://127.0.0.1:3100',
  NEXT_TELEMETRY_DISABLED: '1',
};
const child = spawnSync(process.argv[divider + 1], process.argv.slice(divider + 2), {
  cwd: process.cwd(), env, stdio: 'inherit',
});
if (child.error) throw child.error;
process.exitCode = child.status ?? 1;
