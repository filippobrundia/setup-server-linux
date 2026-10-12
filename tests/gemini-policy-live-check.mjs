import { realpathSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
// Solo parser e valutazione: nessun comando eseguito, nessuna credenziale letta.
const root = dirname(realpathSync(process.argv[2]));
const chunk = readdirSync(root).find(name => name.startsWith('chunk-') && name.endsWith('.js') && readFileSync(join(root,name),'utf8').includes('async function loadPoliciesFromToml('));
assert.ok(chunk, 'Parser della versione installata non trovato');
const {loadPoliciesFromToml, PolicyEngine} = await import(pathToFileURL(join(root,chunk)).href);
const parsed = await loadPoliciesFromToml([process.argv[3]], () => 4);
assert.equal(parsed.errors.length, 0, JSON.stringify(parsed.errors));
const engine = new PolicyEngine({rules:parsed.rules, defaultDecision:'ask_user', approvalMode:'default'});
for (const [command,want] of [['git status','allow'],['sudo apt-get update','deny'],['touch /tmp/ops-policy-prova','ask_user'],['git status && touch /tmp/ops-policy-prova','ask_user']]) {
 const result=await engine.check({name:'run_shell_command',args:{command}});
 assert.equal(result.decision,want,command);
 console.log('PASS policy:',command,'=>',result.decision);
}
console.log('GEMINI_POLICY_ENGINE_OK');
