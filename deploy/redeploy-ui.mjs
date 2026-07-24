#!/usr/bin/env node
// =============================================================================
// redeploy-ui.mjs — Painel web local para rodar ./redeploy.sh de forma visual,
// acompanhando a saída ao vivo (streaming SSE). Sem dependências externas.
//
//   node redeploy-ui.mjs            # sobe em http://127.0.0.1:7878
//   PORT=9000 node redeploy-ui.mjs  # outra porta
//   HOST=0.0.0.0 node redeploy-ui.mjs  # expõe na rede (CUIDADO: permite
//                                        # que qualquer um na rede rode deploys)
//
// Só executa ./redeploy.sh com argumentos validados (flags de uma allowlist +
// nomes de apps descobertos). spawn sem shell => sem injeção de comando.
// =============================================================================
import http from "node:http";
import { spawn } from "node:child_process";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const APP_DIR = path.dirname(fileURLToPath(import.meta.url)); // deploy/
const PROJECTS_ROOT = path.dirname(APP_DIR);                  // LifeBusinessSuit/ (onde ficam os apps)
const SCRIPT = path.join(APP_DIR, "redeploy.sh");
const HTML = path.join(APP_DIR, "redeploy-ui.html");
const PORT = Number(process.env.PORT) || 7878;
const HOST = process.env.HOST || "127.0.0.1";
const ALLOWED_FLAGS = new Set(["--no-build", "--down", "--pull", "--prune"]);

if (!existsSync(SCRIPT)) { console.error("✗ redeploy.sh não encontrado em " + ROOT); process.exit(1); }
if (!existsSync(HTML))   { console.error("✗ redeploy-ui.html não encontrado em " + ROOT); process.exit(1); }

function discoverApps() {
  return readdirSync(PROJECTS_ROOT, { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(path.join(PROJECTS_ROOT, d.name, "docker-compose.yml")))
    .map((d) => d.name)
    .sort();
}

function json(res, obj, code = 200) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { "content-type": "application/json; charset=utf-8" });
  res.end(body);
}

let current = null; // processo em execução (singleton)

function sse(res) {
  res.writeHead(200, {
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-cache, no-transform",
    connection: "keep-alive",
    "x-accel-buffering": "no",
  });
  res.write(": conectado\n\n");
  return {
    line: (line) => res.write("data: " + JSON.stringify({ line }) + "\n\n"),
    event: (name, obj) => res.write("event: " + name + "\ndata: " + JSON.stringify(obj) + "\n\n"),
  };
}

function killTree(child) {
  if (!child || child.killed) return;
  try { process.kill(-child.pid, "SIGTERM"); } catch { try { child.kill("SIGTERM"); } catch {} }
  setTimeout(() => { try { process.kill(-child.pid, "SIGKILL"); } catch {} }, 4000);
}

function runHandler(req, res, url) {
  const out = sse(res);

  if (current) { out.event("fatal", { message: "Já existe um redeploy em andamento." }); return res.end(); }

  const apps = discoverApps();
  const lower = new Map(apps.map((a) => [a.toLowerCase(), a]));

  const wantAll = url.searchParams.get("all") === "1";
  const rawApps = (url.searchParams.get("apps") || "").split(",").map((s) => s.trim()).filter(Boolean);
  const rawFlags = (url.searchParams.get("flags") || "").split(",").map((s) => s.trim()).filter(Boolean);

  // validação estrita
  const flags = [];
  for (const f of rawFlags) {
    if (!ALLOWED_FLAGS.has(f)) { out.event("fatal", { message: "Flag não permitida: " + f }); return res.end(); }
    if (!flags.includes(f)) flags.push(f);
  }
  const targets = [];
  if (!wantAll) {
    for (const a of rawApps) {
      const canon = lower.get(a.toLowerCase());
      if (!canon) { out.event("fatal", { message: "App desconhecido: " + a }); return res.end(); }
      if (!targets.includes(canon)) targets.push(canon);
    }
    if (targets.length === 0) { out.event("fatal", { message: "Nenhum app selecionado." }); return res.end(); }
  }

  const argv = [SCRIPT, ...flags, ...targets];
  const child = spawn("bash", argv, {
    cwd: PROJECTS_ROOT,
    detached: true, // grupo próprio => matável em árvore
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, TERM: "dumb", NO_COLOR: "1" },
  });
  current = child;

  let buf = "";
  const onData = (chunk) => {
    buf += chunk.toString("utf8");
    const parts = buf.split("\n");
    buf = parts.pop();
    for (const l of parts) out.line(l);
  };
  child.stdout.on("data", onData);
  child.stderr.on("data", onData);

  child.on("close", (code, signal) => {
    if (buf.length) { out.line(buf); buf = ""; }
    out.event("end", { code: code == null ? (signal ? 137 : 1) : code, signal });
    current = null;
    res.end();
  });
  child.on("error", (err) => {
    out.event("fatal", { message: "Falha ao iniciar: " + err.message });
    current = null;
    res.end();
  });

  req.on("close", () => { if (current === child) { killTree(child); } });
}

function psHandler(res) {
  const p = spawn("docker", ["ps", "-a", "--format", "{{.Names}}\t{{.Status}}"]);
  let out = "", err = "";
  p.stdout.on("data", (d) => (out += d));
  p.stderr.on("data", (d) => (err += d));
  p.on("close", (code) => {
    if (code !== 0) return json(res, { containers: [], error: err.trim() || "docker ps falhou" });
    const containers = out.split("\n").map((l) => l.trim()).filter(Boolean).map((l) => {
      const [name, ...rest] = l.split("\t");
      return { name, status: rest.join("\t") };
    });
    json(res, { containers });
  });
  p.on("error", (e) => json(res, { containers: [], error: e.message }));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://" + (req.headers.host || HOST));
  if (req.method === "GET" && url.pathname === "/") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    return res.end(readFileSync(HTML));
  }
  if (req.method === "GET" && url.pathname === "/api/apps") {
    return json(res, { apps: discoverApps(), script: SCRIPT, port: PORT });
  }
  if (req.method === "GET" && url.pathname === "/api/ps") return psHandler(res);
  if (req.method === "GET" && url.pathname === "/api/run") return runHandler(req, res, url);
  if (req.method === "POST" && url.pathname === "/api/stop") {
    if (current) killTree(current);
    return json(res, { stopped: !!current });
  }
  res.writeHead(404); res.end("not found");
});

server.listen(PORT, HOST, () => {
  const shown = HOST === "0.0.0.0" ? "0.0.0.0 (rede)" : HOST;
  console.log("▶ Redeploy UI: http://" + (HOST === "0.0.0.0" ? "<este-host>" : HOST) + ":" + PORT + "   (bind " + shown + ")");
  console.log("  Apps:", discoverApps().join(", "));
  console.log("  Ctrl+C para encerrar.");
});
