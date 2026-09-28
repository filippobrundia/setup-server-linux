// egress-proxy — unica uscita del runner verso Internet. Accetta solo tunnel CONNECT sulla porta 443 verso host
// esplicitamente ammessi (EGRESS_ALLOW_HOSTS) e rifiuta ogni destinazione che risolve in un indirizzo privato,
// locale, della LAN o riservato. Nessuna richiesta HTTP in chiaro. Registra solo host, porta ed esito.
import http from "node:http"; import net from "node:net"; import dns from "node:dns/promises";
const ALLOW = new Set((process.env.EGRESS_ALLOW_HOSTS || "").split(",").map((h) => h.trim().toLowerCase()).filter(Boolean));
const PORT = Number(process.env.EGRESS_PORT || 3128);
const log = (m) => console.log(`${new Date().toISOString()} ${m}`);
function isPrivate(ip) {
  if (net.isIPv6(ip)) {
    const l = ip.toLowerCase();
    if (l.startsWith("::ffff:")) return isPrivate(l.slice(7));
    return l === "::" || l === "::1" || /^f[cd]/.test(l) || /^fe[89ab]/.test(l) || l.startsWith("ff");
  }
  const [a, b] = ip.split(".").map(Number);
  return a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 192 && b === 0) ||
    (a === 198 && (b === 18 || b === 19)) || a >= 224;
}
const server = http.createServer((req, res) => { log(`NEGATO http ${req.method}`); res.writeHead(403).end(); });
server.on("connect", async (req, client, head) => {
  const deny = (why) => { log(`NEGATO ${req.url} (${why})`); client.end("HTTP/1.1 403 Forbidden\r\n\r\n"); };
  const m = /^([a-z0-9.-]+):(\d+)$/i.exec(req.url || "");
  if (!m) return deny("formato");
  const host = m[1].toLowerCase(); const port = Number(m[2]);
  if (port !== 443) return deny("porta");
  if (net.isIP(host)) return deny("indirizzo IP diretto");
  if (!ALLOW.has(host)) return deny("host non ammesso");
  let addrs; try { addrs = await dns.lookup(host, { all: true }); } catch { return deny("DNS"); }
  const target = addrs.find((a) => !isPrivate(a.address));
  if (!target || addrs.some((a) => isPrivate(a.address))) return deny("risolve in un indirizzo privato");
  const up = net.connect({ host: target.address, port, timeout: 30000 }, () => {
    client.write("HTTP/1.1 200 Connection Established\r\n\r\n"); if (head?.length) up.write(head);
    up.pipe(client); client.pipe(up); log(`AMMESSO ${host}:${port}`);
  });
  const close = () => { up.destroy(); client.destroy(); };
  up.on("error", () => { if (!client.destroyed) client.end("HTTP/1.1 502 Bad Gateway\r\n\r\n"); close(); });
  up.on("timeout", close); client.on("error", close);
});
server.listen(PORT, "0.0.0.0", () => log(`egress-proxy in ascolto su ${PORT}; ammessi: ${[...ALLOW].join(", ") || "nessuno"}`));
