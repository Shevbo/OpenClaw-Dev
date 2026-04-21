#!/usr/bin/env node
/**
 * Сохранение и чтение файлов под корнем $HOME (только 127.0.0.1).
 * POST /save — записать; POST /read — прочитать; POST /mkdir — каталог (+ .keep).
 * Корень: WORKSPACE_ROOT (по умолчанию $HOME)
 * Токен: ~/.openclaw/.workspace-api-token (chmod 600)
 */
import http from "http";
import fs from "fs/promises";
import path from "path";
import { existsSync } from "fs";

const PORT = Number(process.env.WORKSPACE_API_PORT || 38471);
const HOME = process.env.HOME || "/home/shevbo";
const ROOT = path.resolve(process.env.WORKSPACE_ROOT || HOME);
const TOKEN_PATH = path.join(HOME, ".openclaw/.workspace-api-token");

/** Запрет записи в типичные секреты */
function isDeniedRel(rel) {
  const n = rel.replace(/\\/g, "/");
  return /^(?:\.ssh\/|\.gnupg\/)/.test(n);
}

async function loadToken() {
  if (!existsSync(TOKEN_PATH)) return "";
  try {
    return (await fs.readFile(TOKEN_PATH, "utf8")).trim();
  } catch {
    return "";
  }
}

function safeRel(rel) {
  if (typeof rel !== "string" || rel.includes("\0")) throw new Error("invalid path");
  if (isDeniedRel(rel)) throw new Error("path refused");
  const root = path.resolve(ROOT);
  const resolved = path.resolve(root, rel);
  if (!resolved.startsWith(root + path.sep) && resolved !== root) throw new Error("path traversal");
  return resolved;
}

async function handleSave(req, res) {
  let body = "";
  for await (const ch of req) body += ch;
  let data;
  try {
    data = JSON.parse(body);
  } catch {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "invalid json" }));
    return;
  }
  const { relativePath, content, encoding } = data;
  if (typeof relativePath !== "string" || typeof content !== "string") {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "relativePath and content required" }));
    return;
  }
  let target;
  try {
    target = safeRel(relativePath);
  } catch (e) {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: String(e.message) }));
    return;
  }
  await fs.mkdir(path.dirname(target), { recursive: true });
  if (encoding === "base64") {
    let buf;
    try {
      buf = Buffer.from(content, "base64");
    } catch {
      res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ ok: false, error: "invalid base64" }));
      return;
    }
    await fs.writeFile(target, buf);
  } else {
    await fs.writeFile(target, content, "utf8");
  }
  res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify({ ok: true }));
}

const MAX_READ_BYTES = 25 * 1024 * 1024;

async function handleRead(req, res) {
  let body = "";
  for await (const ch of req) body += ch;
  let data;
  try {
    data = JSON.parse(body);
  } catch {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "invalid json" }));
    return;
  }
  const { relativePath } = data;
  if (typeof relativePath !== "string") {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "relativePath required" }));
    return;
  }
  let target;
  try {
    target = safeRel(relativePath);
  } catch (e) {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: String(e.message) }));
    return;
  }
  let st;
  try {
    st = await fs.stat(target);
  } catch {
    res.writeHead(404, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "not found" }));
    return;
  }
  if (!st.isFile()) {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "not a file" }));
    return;
  }
  if (st.size > MAX_READ_BYTES) {
    res.writeHead(413, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "file too large" }));
    return;
  }
  const buf = await fs.readFile(target);
  let out = {};
  if (buf.indexOf(0) >= 0) {
    out = { ok: true, content: buf.toString("base64"), encoding: "base64" };
  } else {
    out = { ok: true, content: buf.toString("utf8") };
  }
  res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(out));
}

/** Создать каталог; добавляется пустой `.keep`, чтобы путь попал в дерево (find по файлам). */
async function handleMkdir(req, res) {
  let body = "";
  for await (const ch of req) body += ch;
  let data;
  try {
    data = JSON.parse(body);
  } catch {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "invalid json" }));
    return;
  }
  const { relativePath } = data;
  if (typeof relativePath !== "string" || !relativePath.trim()) {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "relativePath required" }));
    return;
  }
  let target;
  try {
    target = safeRel(relativePath.replace(/\/+$/, ""));
  } catch (e) {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: String(e.message) }));
    return;
  }
  await fs.mkdir(target, { recursive: true });
  const keep = path.join(target, ".keep");
  try {
    await fs.writeFile(keep, "", "utf8");
  } catch (e) {
    res.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: String(e.message) }));
    return;
  }
  res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify({ ok: true, keepRelative: path.relative(ROOT, keep).replace(/\\/g, "/") }));
}

const server = http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, X-Api-Token");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  let expected;
  try {
    expected = await loadToken();
  } catch {
    expected = "";
  }
  if (!expected) {
    res.writeHead(503, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "token file missing" }));
    return;
  }

  const u = new URL(req.url || "/", "http://127.0.0.1");
  const auth = req.headers["x-api-token"] || "";
  if (auth !== expected) {
    res.writeHead(401, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "unauthorized" }));
    return;
  }

  if (req.method === "POST" && (u.pathname === "/save" || u.pathname === "/")) {
    await handleSave(req, res);
    return;
  }

  if (req.method === "POST" && u.pathname === "/read") {
    await handleRead(req, res);
    return;
  }

  if (req.method === "POST" && u.pathname === "/mkdir") {
    await handleMkdir(req, res);
    return;
  }

  res.writeHead(404, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify({ ok: false, error: "not found" }));
});

server.listen(PORT, "127.0.0.1", () => {
  console.error(`workspace-api listening on 127.0.0.1:${PORT} root=${ROOT}`);
});
