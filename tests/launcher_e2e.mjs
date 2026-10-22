// Test de bout en bout : vrai net.js (mod) -> VRAI relais Rust de GRNFR CMP Launcher (launcher/core, lancé avec
// `cargo run --example relay`) -> faux Supabase HTTP local. Vérifie que les deux moitiés se comprennent (chemins,
// en-têtes apikey/Authorization, corps, codes d'erreur relayés). Nécessite cargo. Usage : node tests/launcher_e2e.mjs
import fs from "fs"
import path from "path"
import os from "os"
import http from "http"
import assert from "assert"
import { spawn, execFileSync } from "child_process"
import { pathToFileURL } from "url"

// LuaJIT lancé SANS bloquer Node : le faux Supabase tourne dans ce même processus et doit pouvoir répondre.
const runLua = mode => new Promise((resolve, reject) => {
  const p = spawn("luajit", ["tests/lua_http_e2e.lua", mode], { stdio: ["ignore", "inherit", "inherit"] })
  p.on("exit", code => code === 0 ? resolve() : reject(new Error("test Lua (" + mode + ") en échec : code " + code)))
})
const check = (c, w) => { assert.ok(c, "ECHEC : " + w); console.log("ok   " + w) }

// ---------- faux Supabase (HTTP local) : signup anonyme, pseudo, get_me ; refuse sans apikey
const sessions = {}
let n = 0
const upstream = http.createServer((req, res) => {
  let raw = ""
  req.on("data", c => (raw += c))
  req.on("end", () => {
    const send = (d, status = 200) => { res.writeHead(status, { "Content-Type": "application/json" }); res.end(JSON.stringify(d)) }
    if (req.headers.apikey !== "anon") return send({ message: "no_apikey" }, 401)
    const tok = (req.headers.authorization || "").replace("Bearer ", "")
    const body = raw ? JSON.parse(raw) : {}
    if (req.url === "/auth/v1/signup") { const t = "tok" + ++n; sessions[t] = { username: null }; return send({ access_token: t, refresh_token: "r" + n, expires_in: 3600 }) }
    if (req.url === "/rest/v1/rpc/username_available") return send(!Object.values(sessions).some(s => s.username === body.p_username))
    const s = sessions[tok]
    if (!s) return send({ message: "not_authenticated" }, 401)
    if (req.url === "/rest/v1/rpc/set_username") { s.username = body.p_username; return send(null) }
    if (req.url === "/rest/v1/rpc/start_session") return send("sess")
    if (req.url === "/rest/v1/rpc/get_me") return send({ profile: { username: s.username, balance: 25000 }, config: {} })
    send({ message: "unknown_fn" }, 404)
  })
})
await new Promise(r => upstream.listen(0, "127.0.0.1", r))
const upPort = upstream.address().port

// ---------- vrai relais Rust sur le port du launcher
const relay = spawn("cargo", ["run", "-q", "--example", "relay"], {
  cwd: path.resolve("launcher/core"),
  env: { ...process.env, UPSTREAM: "http://127.0.0.1:" + upPort, ADDR: "127.0.0.1:30815" },
  stdio: ["ignore", "pipe", "inherit"],
})
await new Promise((resolve, reject) => {
  relay.stdout.on("data", d => { if (String(d).includes("relais prêt")) resolve() })
  relay.on("exit", c => reject(new Error("relais arrêté : " + c)))
})

try {
  // ---------- vrai net.js, avec le fetch réel de Node (comme l'interface du jeu vers localhost)
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "grnfr-e2e-"))
  let code = fs.readFileSync("mod/grnfr-mod/ui/ui-vue/mods/GRNFR/net.js", "utf8")
  code = code.replace('import { reactive } from "vue"', "const reactive = x => x")
    .replace('import { useBridge } from "@/bridge"', 'const useBridge = () => ({ events: { on() {}, off() {} }, api: { engineLua() {} } }) // pas de Lua ici : le chemin Lua est testé à part (lua_http_e2e.lua)')
    .replace('import cfg from "./serverConfig.js"', 'const cfg = { url: "https://ne-doit-pas-etre-appele.invalid", anonKey: "anon" }')
    .replace('import { callLua, unwrapObj, unwrapList } from "./luaCall.js"', "const callLua = async () => {}, unwrapObj = d => d, unwrapList = d => d")
  fs.writeFileSync(path.join(tmp, "net.mjs"), code)
  globalThis.localStorage = { s: {}, getItem(k) { return this.s[k] ?? null }, setItem(k, v) { this.s[k] = v }, removeItem(k) { delete this.s[k] } }
  const net = await import(pathToFileURL(path.join(tmp, "net.mjs")))
  await net.initNet()

  check(await net.signUpAnonymous("alice") === true, "création de profil à travers le vrai relais : " + (net.net.error || "ok"))
  check(net.net.username === "alice" && net.net.me.profile.balance === 25000, "pseudo et solde relus via le relais")
  check(await net.usernameAvailable("alice") === false && await net.usernameAvailable("bob") === true, "vérification de pseudo en direct via le relais")
  let e = null
  try { await net.rpc("fonction_inconnue", {}) } catch (x) { e = x }
  check(e && e.code === "unknown_fn" && e.status === 404, "erreur du serveur relayée avec son code et son statut")

  // Second chemin du mod : le VRAI grnfr/http.lua dans LuaJIT + LuaSocket (si installés), vers le même relais.
  let lua = true
  try { execFileSync("luajit", ["-e", "require('socket')"], { stdio: "ignore" }) } catch (x) { lua = false; console.log("--   luajit + LuaSocket absents : test Lua sauté") }
  if (lua) await runLua("up")

  relay.kill()
  await new Promise(r => relay.on("exit", r))
  if (lua) await runLua("down")
  check(await net.signUpAnonymous("carol") === false && net.net.error.includes("Impossible de joindre GRNFR CMP Launcher"), "relais arrêté : message « launcher injoignable » : " + net.net.error)
  console.log("=== BOUT EN BOUT OK ===")
} finally {
  relay.kill()
  upstream.close()
}
