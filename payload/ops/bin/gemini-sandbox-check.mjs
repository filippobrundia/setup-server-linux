#!/usr/bin/env node
// Test del motore Gemini installato, senza credenziali o chiamate al modello.
import { readdirSync, readFileSync, realpathSync, existsSync, unlinkSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
const bin = process.argv[2];
const workspace = process.argv[3] || '/srv/ops';
if (!bin) throw new Error('Percorso Gemini richiesto');
const bundle = dirname(realpathSync(bin));
const moduleFile = readdirSync(bundle).find(name => name.startsWith('chunk-') && name.endsWith('.js') && /\n  createSandboxManager[,\n]/.test(readFileSync(join(bundle, name), 'utf8')));
if (!moduleFile) throw new Error('API sandbox Gemini non disponibile: aggiornamento da verificare');
const { createSandboxManager } = await import(pathToFileURL(join(bundle, moduleFile)));
const manager = createSandboxManager({ enabled: true }, {
  workspace,
  modeConfig: { readonly: false, network: false, approvedTools: [], allowOverrides: false },
  forbiddenPaths: async () => [],
});
if (manager.constructor.name === 'NoopSandboxManager') throw new Error('Sandbox disattivata');
async function run(command, args) {
  const prepared = await manager.prepareCommand({ command, args, cwd: workspace, env: process.env });
  try {
    return spawnSync(prepared.program, prepared.args, { cwd: prepared.cwd || workspace, env: prepared.env, encoding: 'utf8', timeout: 30000 });
  } finally { prepared.cleanup?.(); }
}
const host = await run('sh', ['-c', 'test -r AGENTS.md && systemctl is-active ssh && journalctl -n 1 --no-pager']);
if (host.status !== 0) throw new Error(`Lettura server fallita: ${host.stderr}`);
console.log(host.stdout.trim());
const outside = join(process.env.HOME, `.ops-gemini-probe-${process.pid}`);
if (existsSync(outside)) throw new Error('File prova preesistente');
const denied = await run('touch', [outside]);
if (existsSync(outside)) { unlinkSync(outside); throw new Error('Scrittura fuori workspace consentita'); }
if (denied.status === 0 || !/Read-only|Permission denied|Operation not permitted/i.test(denied.stderr)) throw new Error(`Rifiuto non dimostrato: ${denied.stderr}`);
const inside = join(workspace, `.gemini-probe-${process.pid}`);
try {
  const allowed = await run('touch', [inside]);
  if (allowed.status !== 0 || !existsSync(inside)) throw new Error(`Scrittura workspace fallita: ${allowed.stderr}`);
} finally { if (existsSync(inside)) unlinkSync(inside); }
console.log('OK: sandbox nativa Gemini, server reale leggibile, workspace scrivibile, home protetta');
