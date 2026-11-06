import { build } from 'esbuild';
import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';

await rm('dist', { recursive: true, force: true });
await mkdir('dist/tern', { recursive: true });
for (const file of ['plugin.toml', 'host.luau', 'beads.css', 'icons.json', 'ICONS-LICENSE']) {
  await cp('integrations/tern/' + file, 'dist/tern/' + file);
}
await cp('LICENSE', 'dist/tern/LICENSE');
const { version } = JSON.parse(await readFile('package.json', 'utf8'));
const manifest = await readFile('dist/tern/plugin.toml', 'utf8');
await writeFile('dist/tern/plugin.toml', manifest.replace(/^version = "[^"]+"$/m, 'version = "' + version + '"'));
await build({ entryPoints: ['src/tern/bridge.ts'], outfile: 'dist/tern/bridge.mjs', bundle: true, platform: 'node', target: 'node24', format: 'esm', logLevel: 'info' });
console.log('Built Beads for Tern ' + version);
