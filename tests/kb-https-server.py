#!/usr/bin/env python3
"""Server Git HTTPS di prova (solo test in container): git http-backend dietro TLS con certificato autofirmato.
/pubblico/... senza credenziali; /privato/... solo con autenticazione Basic e password = contenuto di TOKEN_FILE
(token FITTIZIO, cambiabile durante la prova per simulare revoca e sostituzione); altri percorsi: 404.
Registra metodo, percorso e presenza dell'intestazione Authorization (mai il suo valore) in LOG_FILE."""
import base64, os, ssl, subprocess, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT, CERT, KEY, TOKEN_FILE, LOG_FILE, PORT = sys.argv[1:7]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _body(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            out = b""
            while True:
                n = int(self.rfile.readline().strip().split(b";")[0], 16)
                if n == 0:
                    self.rfile.readline()
                    return out
                out += self.rfile.read(n)
                self.rfile.readline()
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def _handle(self):
        path, _, query = self.path.partition("?")
        auth = self.headers.get("Authorization")
        with open(LOG_FILE, "a") as f:
            f.write(f"{self.command} {self.path} auth={'si' if auth else 'no'}\n")
        if not (path.startswith("/pubblico/") or path.startswith("/privato/")):
            self.send_response(404); self.end_headers(); return
        if path.startswith("/privato/"):
            ok = False
            if auth and auth.startswith("Basic "):
                try:
                    _, _, pw = base64.b64decode(auth[6:]).decode().partition(":")
                    ok = pw == open(TOKEN_FILE).read().strip()
                except Exception:
                    ok = False
            if not ok:
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="kb"')
                self.send_header("Content-Length", "0")
                self.end_headers(); return
        body = self._body() if self.command == "POST" else b""
        env = dict(os.environ, GIT_PROJECT_ROOT=ROOT, GIT_HTTP_EXPORT_ALL="1", PATH_INFO=path, QUERY_STRING=query,
                   REQUEST_METHOD=self.command, CONTENT_TYPE=self.headers.get("Content-Type", ""),
                   CONTENT_LENGTH=str(len(body)), REMOTE_ADDR="127.0.0.1", REMOTE_USER="prova")
        if self.headers.get("Content-Encoding"):
            env["HTTP_CONTENT_ENCODING"] = self.headers["Content-Encoding"]
        if self.headers.get("Git-Protocol"):
            env["GIT_PROTOCOL"] = self.headers["Git-Protocol"]
        out = subprocess.run(["git", "http-backend"], input=body, env=env, capture_output=True).stdout
        head, _, rest = out.partition(b"\r\n\r\n")
        if not rest and b"\n\n" in out:
            head, _, rest = out.partition(b"\n\n")
        status, headers = 200, []
        for line in head.decode(errors="replace").splitlines():
            k, _, v = line.partition(":")
            if k.lower() == "status":
                status = int(v.strip().split()[0])
            elif k:
                headers.append((k, v.strip()))
        self.send_response(status)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(rest)))
        self.end_headers()
        self.wfile.write(rest)

    do_GET = do_POST = _handle

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT, KEY)
srv = ThreadingHTTPServer(("127.0.0.1", int(PORT)), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
