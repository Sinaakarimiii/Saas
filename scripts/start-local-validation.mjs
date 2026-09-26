import { execFileSync, spawnSync } from 'node:child_process';
import { appendFileSync, chmodSync, copyFileSync, cpSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv[2] ?? '--primary';
if (!['--primary', '--secondary', '--tertiary', '--quaternary'].includes(mode)) {
  throw new Error('Use --primary, --secondary, --tertiary, or --quaternary.');
}
const portPrefix = mode === '--primary' ? '55' : mode === '--secondary' ? '56' : mode === '--tertiary' ? '57' : '58';
const apiPort = `${portPrefix}321`;
const dbPort = `${portPrefix}322`;
const mailPort = `${portPrefix}324`;
const studioPort = `${portPrefix}323`;
const inbucketPort = `${portPrefix}325`;
const analyticsPort = `${portPrefix}327`;
const vectorPort = `${portPrefix}329`;
const root = mkdtempSync(join(tmpdir(), 'org-platform-validation-'));
chmodSync(root, 0o700);
const target = join(root, 'supabase');
mkdirSync(target, { mode: 0o700 });
cpSync(join(repository, 'supabase', 'migrations'), join(target, 'migrations'), { recursive: true });
copyFileSync(join(repository, 'supabase', 'seed.sql'), join(target, 'seed.sql'));
let config = readFileSync(join(repository, 'supabase', 'config.toml'), 'utf8');
if (!config.includes('project_id = "org_platform"')) throw new Error('Unexpected source project id.');
config = config.replace('project_id = "org_platform"', `project_id = "org_platform_validation_${Date.now().toString(36)}"`);
for (const [oldPort, newPort] of [
  ['54321', apiPort], ['54322', dbPort], ['54323', studioPort], ['54324', mailPort],
  ['54325', inbucketPort], ['54326', `${portPrefix}326`],
  ['54327', analyticsPort], ['54329', vectorPort],
  ['3000', mode === '--primary' ? '3100' : mode === '--secondary' ? '3200' : mode === '--tertiary' ? '3300' : '3400'],
  ['8083', mode === '--primary' ? '8183' : mode === '--secondary' ? '8283' : mode === '--tertiary' ? '8383' : '8483'],
]) config = config.replaceAll(oldPort, newPort);
writeFileSync(join(target, 'config.toml'), config, { mode: 0o600 });
const env = { ...process.env, SUPABASE_TELEMETRY_DISABLED: '1' };
try {
  const launched = spawnSync('supabase', ['start', '--workdir', root], {
    encoding: 'utf8', env, maxBuffer: 16 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'],
  });
  writeFileSync(join(root, 'start.log'), `${launched.stdout ?? ''}\n${launched.stderr ?? ''}`, { mode: 0o600 });
  if (launched.error || launched.status !== 0) throw new Error('Supabase start failed.');
  const status = JSON.parse(execFileSync('supabase', ['status', '--workdir', root, '--output', 'json'], {
    encoding: 'utf8', env, maxBuffer: 16 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'],
  }));
  if (status.API_URL !== `http://127.0.0.1:${apiPort}` || !status.DB_URL.includes(`127.0.0.1:${dbPort}`)) {
    throw new Error('Validation endpoint mismatch.');
  }
  writeFileSync(join(root, 'status.json'), JSON.stringify(status), { mode: 0o600 });
  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, `validation_workdir=${root}\n`);
  }
  console.log(`Validation workdir: ${root}`);
  console.log(`API: http://127.0.0.1:${apiPort}; DB: 127.0.0.1:${dbPort}; Mailpit: http://127.0.0.1:${mailPort}`);
  console.log('Credentials are in the private status.json file; do not add it to Git.');
} catch (error) {
  if (error.stdout) writeFileSync(join(root, 'start.stdout.log'), error.stdout, { mode: 0o600 });
  if (error.stderr) writeFileSync(join(root, 'start.stderr.log'), error.stderr, { mode: 0o600 });
  console.error(`Validation start failed. Private diagnostics: ${root}`);
  process.exitCode = 1;
}
