// Chiamate dirette del runner all API di Paperclip (http://paperclip:3100) senza credenziali o con token falsi: attese tutte negate. Argomento: id di un azienda.
const B = "http://paperclip:3100/api"; const CID = process.argv[2];
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const fake = `${b64({ alg: "HS256" })}.${b64({ sub: "fittizio" })}.FITTIZIO`;   // token falso costruito a runtime
const calls = [
  ["GET", "/health", null, null], ["GET", "/companies", null, null], ["GET", "/companies", fake, null],
  ["GET", `/companies/${CID}/agents`, null, null], ["GET", `/companies/${CID}/agents`, fake, null],
  ["GET", `/companies/${CID}/secrets`, fake, null], ["GET", "/agents/me", fake, null], ["GET", "/agents/me", "FITTIZIO-token-ponte", null],
  ["POST", "/companies", fake, { name: "Intruso" }], ["PATCH", `/companies/${CID}`, fake, { requireBoardApprovalForNewAgents: false }],
  ["POST", `/companies/${CID}/agents`, fake, { name: "Intruso", adapterType: "process" }],
  ["GET", "/instance/settings/experimental", null, null],
];
for (const [m, p, tok, body] of calls) {
  const h = { "Content-Type": "application/json" }; if (tok) h.Authorization = `Bearer ${tok}`;
  let st; try { const r = await fetch(B + p, { method: m, headers: h, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(10000) }); st = r.status; } catch (e) { st = "errore " + e.message; }
  console.log(`${String(st).padEnd(6)} ${m.padEnd(5)} ${p.replace(CID, "<azienda>")} ${tok ? "(token falso)" : "(senza credenziali)"}`);
}
