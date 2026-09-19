import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const win = process.platform === 'win32';
const localHugo = path.join(root, '.tools/hugo', win ? 'hugo.exe' : 'hugo');
const env = { ...process.env };
const originalPath = process.env.PATH ?? process.env.Path ?? '';
for (const key of Object.keys(env)) if (key.toLowerCase() === 'path') delete env[key];
env.PATH = [path.dirname(process.execPath), path.join(root, '.tools/go/bin'), path.join(root, 'node_modules/.bin'), originalPath].join(path.delimiter);
env.GOPATH = path.join(root, '.cache/go');
env.GOMODCACHE = path.join(root, '.cache/go/pkg/mod');
env.GOCACHE = path.join(root, '.cache/go-build');
env.HUGO_CACHEDIR = path.join(root, '.cache/hugo');
if (win) {
  const gitConfigCount = Number(env.GIT_CONFIG_COUNT ?? 0);
  env[`GIT_CONFIG_KEY_${gitConfigCount}`] = 'http.sslBackend';
  env[`GIT_CONFIG_VALUE_${gitConfigCount}`] = 'schannel';
  env.GIT_CONFIG_COUNT = String(gitConfigCount + 1);
}
for (const dir of [env.GOPATH, env.GOCACHE, env.HUGO_CACHEDIR]) mkdirSync(dir, { recursive: true });
const result = spawnSync(existsSync(localHugo) ? localHugo : 'hugo', process.argv.slice(2), { cwd: root, env, stdio: 'inherit' });
if (result.error) console.error(result.error.message);
process.exit(result.status ?? 1);
