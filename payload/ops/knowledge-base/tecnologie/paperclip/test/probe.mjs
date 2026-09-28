// Raggiungibilità TCP da dentro il runner. Argomento: JSON [[nome, host, [porte]], ...]. Stampa porte aperte o "-".
import net from "node:net"; import dns from "node:dns/promises";
const T = JSON.parse(process.argv[2]);
const reach = (h, p) => new Promise((ok) => { const s = net.connect({ host: h, port: p, timeout: 2500 }, () => { s.destroy(); ok(true); }); s.on("error", () => ok(false)); s.on("timeout", () => { s.destroy(); ok(false); }); });
for (const [name, host, ports] of T) { const open = []; for (const p of ports) if (await reach(host, p)) open.push(p); console.log(`${name}\t${open.join(",") || "-"}`); }
let r = "-"; try { await dns.lookup("api.openai.com"); r = "risolve"; } catch { r = "non risolve"; }
console.log(`DNS esterno (api.openai.com)\t${r}`);
