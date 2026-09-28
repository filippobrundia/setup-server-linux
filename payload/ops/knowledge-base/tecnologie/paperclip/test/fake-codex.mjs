#!/usr/bin/env node
// Finto "codex" per il collaudo del runner reale: NON contatta modelli. Salva ambiente e argomenti dei processi
// (analizzati dall'esterno), fotografa i file, prova filesystem, rete, residui di esecuzioni precedenti e i permessi
// ottenibili attraverso il ponte. Non conosce i valori sentinella.
import fs from "node:fs"; import net from "node:net"; import { execFileSync } from "node:child_process";
const args = process.argv.slice(2);
// ENVTEST_DOCS: documentazione montata in sola lettura; ENVTEST_FORBIDDEN: percorsi che NON devono esistere nel runner.
const DOCS = process.env.ENVTEST_DOCS || "/docs";
const FORBIDDEN = (process.env.ENVTEST_FORBIDDEN || "/run/secrets,/paperclip,/srv/ops,/var/run/docker.sock").split(",");
if (args.includes("--version")) { console.log("codex-cli 0.155.1"); process.exit(0); }
const id = process.env.PAPERCLIP_RUN_ID || String(Date.now());
const dir = "/tmp/envtest"; fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(`${dir}/env-${id}.txt`, Object.entries(process.env).map(([k, v]) => `${k}=${v}`).join("\n"));
let cmd = ""; for (const p of fs.readdirSync("/proc").filter((x) => /^\d+$/.test(x))) { try { cmd += `${p}: ` + fs.readFileSync(`/proc/${p}/cmdline`, "utf8").replace(/\0/g, " ") + "\n"; } catch {} }
fs.writeFileSync(`${dir}/cmdline-${id}.txt`, cmd);
try { execFileSync("tar", ["-cf", `${dir}/snapshot-${id}.tar`, "--exclude=/tmp/envtest", "--exclude=/tmp/runner-audit.log", "--ignore-failed-read", "/work", "/tmp", "/home/agent"], { stdio: "ignore" }); } catch {}
const canWrite = (p) => { try { fs.writeFileSync(p, "x"); fs.rmSync(p); return true; } catch { return false; } };
const exists = (p) => { try { fs.accessSync(p); return true; } catch { return false; } };
const runsDir = "/work/.paperclip-runtime/runs";
// tentativo di LEGGERE il login di un'altra esecuzione (deve essere impossibile: cartelle già rimosse)
let otherAuthReadable = false;
try { for (const r of fs.readdirSync(runsDir)) { if (r === id) continue;
  const f = execFileSync("sh", ["-c", `find ${runsDir}/${r} -name auth.json 2>/dev/null | head -1`]).toString().trim();
  if (f) { fs.readFileSync(f); otherAuthReadable = true; } } } catch {}
// gateway della rete (verso l'host): porte dei servizi del server
let gw = null; try { const line = fs.readFileSync("/proc/net/route", "utf8").split("\n").find((l) => l.split("\t")[1] === "00000000");
  if (line) { const h = line.split("\t")[2]; gw = [3, 2, 1, 0].map((i) => parseInt(h.substr(i * 2, 2), 16)).join("."); } } catch {}
const otherRuns = exists(runsDir) ? fs.readdirSync(runsDir).filter((r) => r !== id) : [];
let otherAuth = 0; try { otherAuth = execFileSync("sh", ["-c", `find /work /tmp /home/agent -name auth.json 2>/dev/null | grep -v '/runs/${id}/' | wc -l`]).toString().trim(); } catch {}
const api = async (method, p, body) => {
  if (!process.env.PAPERCLIP_API_URL) return "nessun ponte";
  try {
    const r = await fetch(`${process.env.PAPERCLIP_API_URL.replace(/\/$/, "")}/api${p}`, { method,
      headers: { Authorization: `Bearer ${process.env.PAPERCLIP_API_KEY}`, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30000) });
    return r.status;
  } catch (e) { return `errore: ${e.message}`; }
};
const cid = process.env.PAPERCLIP_COMPANY_ID;
const reach = (host, port) => new Promise((ok) => { const s = net.connect({ host, port, timeout: 3000 }, () => { s.destroy(); ok(true); }); s.on("error", () => ok(false)); s.on("timeout", () => { s.destroy(); ok(false); }); });
const report = {
  run: id,
  bridge: { me: await api("GET", "/agents/me"),
            createCompany: await api("POST", "/companies", { name: "ProvaNonAutorizzata" }),
            disableHireApproval: await api("PATCH", `/companies/${cid}`, { requireBoardApprovalForNewAgents: false }),
            directCreateAgent: await api("POST", `/companies/${cid}/agents`, { name: "Intruso", adapterType: "process" }) },
  write: { docs: canWrite(`${DOCS}/prova`), rootfs: canWrite("/usr/local/prova"), etc: canWrite("/etc/prova"), work: canWrite("/work/prova"), tmp: canWrite("/tmp/prova") },
  docs: exists(DOCS) ? fs.readdirSync(DOCS).sort() : [],
  paths: Object.fromEntries(FORBIDDEN.map((p) => [p, exists(p)])),
  network: { db: await reach("db", 5432), paperclip3100: await reach("paperclip", 3100), internet: await reach("1.1.1.1", 443) },
  otherRunsPresent: otherRuns.length, otherAuthJson: Number(otherAuth), otherAuthReadable,
  hostGateway: gw ? Object.fromEntries(await Promise.all([22, 80, 443, 445, 3100, 5432, 8123].map(async (port) => [port, await reach(gw, port)]))) : "nessun gateway",
  containerEnvKeys: (() => { try { return fs.readFileSync("/proc/1/environ", "utf8").split("\0").filter(Boolean).map((e) => e.split("=")[0]).sort(); } catch { return "illeggibile"; } })(),
  mode: process.env.ENVTEST_MODE || "ok",
  uid: process.getuid(),
};
fs.writeFileSync(`${dir}/report-${id}.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ type: "envtest.report", run: id }));
if (process.env.ENVTEST_MODE === "fail") process.exit(1);
if (process.env.ENVTEST_MODE === "sleep") await new Promise((r) => setTimeout(r, Number(process.env.ENVTEST_SLEEP || 60) * 1000));
process.exit(0);
