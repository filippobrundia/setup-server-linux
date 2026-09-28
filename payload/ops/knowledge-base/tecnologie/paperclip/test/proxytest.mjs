// Verifica del proxy di uscita dall'interno del runner. Parametri (variabili d'ambiente):
//   EGRESS_PROXY   host:porta del proxy (predefinito egress-proxy:3128)
//   ALLOW          host ammessi, separati da virgole (attesi 200)
//   DENY           destinazioni vietate host:porta (attese 403); predefinite: IP privati, locali, metadati, porta 80
// Ultima riga: "N/M casi conformi".
import net from "node:net";
const [PH, PP] = (process.env.EGRESS_PROXY || "egress-proxy:3128").split(":");
const allow = (process.env.ALLOW || "api.openai.com,chatgpt.com,auth.openai.com").split(",").filter(Boolean);
const deny = (process.env.DENY || "example.com:443,api.openai.com:80,192.168.1.1:443,10.0.0.1:443,172.17.0.1:443,localhost:443,169.254.169.254:443").split(",").filter(Boolean);
const ask = (line) => new Promise((ok) => { const s = net.connect(Number(PP), PH, () => s.write(line));
  let b = ""; s.on("data", (d) => { b += d; if (b.includes("\r\n")) { s.destroy(); ok(b.split("\r\n")[0].split(" ")[1]); } });
  s.on("error", (e) => ok("errore " + e.code)); setTimeout(() => { s.destroy(); ok("timeout"); }, 15000); });
const cases = [
  ...allow.map((h) => [`CONNECT ${h}:443`, `CONNECT ${h}:443 HTTP/1.1\r\nHost: ${h}:443\r\n\r\n`, "200"]),
  ...deny.map((t) => [`CONNECT ${t} (vietato)`, `CONNECT ${t} HTTP/1.1\r\n\r\n`, "403"]),
  ["GET http in chiaro", "GET http://example.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n", "403"],
];
let ok = 0;
for (const [name, line, want] of cases) { const got = await ask(line); const pass = got === want; ok += pass; console.log(`${pass ? "OK   " : "FALLITO"} ${name.padEnd(46)} atteso ${want}, ottenuto ${got}`); }
console.log(`${ok}/${cases.length} casi conformi`);
