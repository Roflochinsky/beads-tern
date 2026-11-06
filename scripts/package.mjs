import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';

const { version } = JSON.parse(await readFile('package.json', 'utf8'));
const manifest = await readFile('dist/tern/plugin.toml', 'utf8');
if (!manifest.includes('version = "' + version + '"')) throw new Error('Build the current version before packaging.');
await mkdir('release', { recursive: true });
const archive = 'beads-tern-' + version + '.tar.gz';
execFileSync('tar', ['-czf', 'release/' + archive, '-C', 'dist', 'tern']);
const hash = createHash('sha256');
for await (const chunk of createReadStream('release/' + archive)) hash.update(chunk);
await writeFile('release/SHA256SUMS', hash.digest('hex') + '  ' + archive + '\n');
console.log('Packaged ' + archive + ' and SHA256SUMS');
