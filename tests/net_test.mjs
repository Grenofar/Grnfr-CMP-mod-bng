// Test du client réseau (mod/grnfr-mod/ui/.../net.js) avec un faux Supabase et un faux pont BeamNG. Usage : node tests/net_test.mjs
import fs from "fs"
import path from "path"
import os from "os"
import assert from "assert"
import { pathToFileURL } from "url"

const SRC = path.resolve("mod/grnfr-mod/ui/ui-vue/mods/GRNFR/net.js")
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "grnfr-"))
let code = fs.readFileSync(SRC, "utf8")
code = code.replace('import { reactive } from "vue"', "const reactive = x => x")
  .replace('import { useBridge } from "@/bridge"', 'import { useBridge } from "./bridge_stub.mjs"')
  .replace('import cfg from "./serverConfig.js"', 'const cfg = { url: "https://fake.supabase.co", anonKey: "anon" }')
  .replace('import { callLua, unwrapObj, unwrapList } from "./luaCall.js"', 'import { callLua, unwrapObj, unwrapList } from "./lua_stub.mjs"')
fs.writeFileSync(path.join(tmp, "net.mjs"), code)
const lcalls = [], engine = [], handlers = {}, httpCalls = []
// Faux grnfr/http.lua : les requêtes HTTP envoyées au jeu (extensions.grnfr_http.request(...)) sont rejouées sur le
// faux Supabase ci-dessous, puis la réponse revient par l'événement GRNFRHttp, comme en jeu. Les autres appels Lua
// sont seulement enregistrés (engine).
const luaArgs = s => [...s.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(m => new TextDecoder().decode(Uint8Array.from(
  m[1].match(/\\\d{3}|\\.|[^\\]/g) || [], t => t.length === 4 && t[0] === "\\" ? Number(t.slice(1)) : t.length === 2 ? t.charCodeAt(1) : t.charCodeAt(0))))
function gameHttp(c) {
  const id = Number(c.match(/^extensions\.grnfr_http\.request\((\d+),/)[1])
  const [method, url, body, authorization] = luaArgs(c)
  httpCalls.push({ method, url, authorization })
  const u = new URL(url)
  const apikey = u.searchParams.get("apikey")
  u.searchParams.delete("apikey")
  setTimeout(async () => {
    const r = apikey !== "anon" ? { status: 401, body: '{"message":"no_apikey"}' }
      : await fakeServer(u.origin + u.pathname + u.search, { method, headers: { Authorization: authorization }, body: body || undefined })
    handlers.GRNFRHttp({ id, ...r })
  }, 0)
}
globalThis.__t = { lcalls, engine, handlers, lua: c => c.startsWith("extensions.grnfr_http.request(") ? gameHttp(c) : engine.push(c) }

// Faux relais (public/bridge.js) : un cadre dont la fenêtre reçoit {grnfr:"req"} par postMessage, interroge le faux
// Supabase et répond {grnfr:"bridge", id, status, body} au parent. Au chargement il annonce {ready:true}.
const bridgeCalls = [], winListeners = []
let frameWin = null, frameSrc = ""
const toParent = data => winListeners.forEach(f => f({ data, source: frameWin }))
globalThis.window = { addEventListener: (t, f) => { if (t === "message") winListeners.push(f) } }
globalThis.document = {
  createElement: () => ({ style: {}, setAttribute() {}, set src(v) { frameSrc = v }, contentWindow: (frameWin = { postMessage: m => {
    if (m.grnfr !== "req") return
    bridgeCalls.push(m)
    setTimeout(async () => {
      const r = await fakeServer("https://fake.supabase.co" + m.path, { method: m.method, headers: { Authorization: m.authorization }, body: m.body || undefined })
      toParent({ grnfr: "bridge", id: m.id, ...r })
    }, 0)
  } }) }),
  body: { appendChild: () => setTimeout(() => toParent({ grnfr: "bridge", ready: true, configured: true }), 0) },
}
fs.writeFileSync(path.join(tmp, "bridge_stub.mjs"), `export const useBridge = () => ({ events: { on: (n, f) => { globalThis.__t.handlers[n] = f }, off: () => {} }, api: { engineLua: c => globalThis.__t.lua(c) } })`)
fs.writeFileSync(path.join(tmp, "lua_stub.mjs"), `export const callLua = async (...a) => { globalThis.__t.lcalls.push(a) }\nexport const unwrapObj = d => d\nexport const unwrapList = d => d`)
globalThis.localStorage = { s: {}, getItem(k) { return this.s[k] ?? null }, setItem(k, v) { this.s[k] = v }, removeItem(k) { delete this.s[k] } }

// ---------- faux Supabase
const members = {}, calls = []
const sessions = {} // token -> { username } ; un profil = juste un pseudo, choisi APRÈS la connexion anonyme
const MAX = 4
let anonCalls = 0
globalThis.fetch = () => { throw new Error("fetch ne doit plus être utilisé en jeu (CSP de BeamNG 0.40)") }
async function fakeServer(url, opt) {
  const p = url.replace("https://fake.supabase.co", "")
  const body = opt.body ? JSON.parse(opt.body) : undefined
  const auth = opt.headers.Authorization.replace("Bearer ", "")
  const ok = (d, status = 200) => ({ status, body: JSON.stringify(d) })
  calls.push(p)
  if (p === "/auth/v1/signup") {
    anonCalls++
    const tok = "tok_anon" + anonCalls
    sessions[tok] = { username: null }
    return ok({ access_token: tok, refresh_token: "ref_anon" + anonCalls, expires_in: 3600 })
  }
  const fn = p.replace("/rest/v1/rpc/", "")
  const sess = sessions[auth]
  if (fn === "username_available") return ok(!Object.values(sessions).some(s => s.username && s.username.toLowerCase() === body.p_username.toLowerCase()))
  if (!sess) return ok({ message: "not_authenticated" }, 401)
  if (fn === "set_username") {
    const uname = body.p_username
    if (Object.values(sessions).some(s => s !== sess && s.username && s.username.toLowerCase() === uname.toLowerCase())) return ok({ message: "username_taken" }, 400)
    sess.username = uname
    return ok(null)
  }
  if (fn === "start_session") return ok("session-" + auth)
  const me = sess.username
  if (fn === "get_me") return ok({ profile: { username: me, balance: 25000 }, config: { sync_interval_ms: 300 }, vehicles: [] })
  if (fn === "join_server") { if (Object.keys(members).length >= MAX && !members[me]) return ok({ message: "server_full" }, 400); members[me] = {}; return ok({ id: "s1", name: "Serveur 1", max_players: MAX }) }
  if (fn === "server_sync") { if (!members[me]) return ok({ message: "not_in_server" }, 400); members[me] = body; return ok({ players: Object.keys(members).filter(n => n !== me).map(n => ({ username: n, pos: members[n].p_pos, veh: members[n].p_veh })) }) }
  if (fn === "leave_server") { delete members[me]; return ok(null, 200) }
  if (fn === "heartbeat") return ok(25000)
  return ok({ message: "unknown_fn" }, 404)
}

const net = await import(pathToFileURL(path.join(tmp, "net.mjs")))
const st = net.net
const check = (c, w) => { assert.ok(c, "ECHEC : " + w); console.log("ok   " + w) }

// luaStr : accents et guillemets échappés en \ddd
check(net.luaStr('a"b\\c\n') === '"a\\"b\\\\c\\010"', "luaStr échappe \" \\ et les retours à la ligne")
check(net.luaStr("é") === '"\\195\\169"', "luaStr écrit les accents en octets décimaux")

await net.initNet()
check(Object.keys(handlers).includes("GRNFRNetReq") && handlers.GRNFRSelf && handlers.GRNFRPos, "écouteurs d'événements du jeu installés")

// création de profil (pseudo seul, pas d'e-mail/mot de passe) : pseudo invalide refusé AVANT tout appel réseau
check(await net.signUpAnonymous("ab") === false, "pseudo trop court refusé")
check(st.error.includes("invalide") && anonCalls === 0, "aucune connexion anonyme tentée pour un pseudo invalide")
check(await net.signUpAnonymous("alice") === true && st.status === "in" && st.username === "alice", "création de profil avec un pseudo libre")
await net.signOut()
check(await net.signUpAnonymous("alice") === false && st.error.includes("pris") && st.status === "out", "pseudo déjà pris (sans tenir compte de la casse) refusé, aucun profil créé en double")
check(await net.signUpAnonymous("bob") === true && st.status === "in" && st.username === "bob", "profil suivant avec un pseudo libre")
check(lcalls.some(c => c[1] === "auth" && JSON.parse(c[2]).loggedIn && JSON.parse(c[2]).username === "bob"), "le Lua est prévenu de la connexion (pseudo bob)")

// serveur de jeu
check(await net.joinServer("s1") === true && st.server.name === "Serveur 1", "serveur rejoint")
check(lcalls.some(c => c[1] === "server.state" && JSON.parse(c[2]).joined && JSON.parse(c[2]).intervalMs === 300), "le Lua reçoit l'état du serveur et la cadence (300 ms)")
for (const n of ["carol", "dave", "erin"]) members[n] = { p_pos: { x: 1, y: 2, z: 3 }, p_veh: { model: "covet" } }
await handlers.GRNFRSelf({ level: "west_coast_usa", pos: { x: 0, y: 0, z: 0 }, rot: [0, 0, 0, 1], vel: [0, 0, 0], veh: { model: "etk800" } })
check(st.players.length === 3 && st.players.map(p => p.username).sort().join() === "carol,dave,erin", "je reçois les 3 autres joueurs avec leur pseudo")
const sent = engine.find(c => c.startsWith("extensions.grnfr_ghosts.onSync("))
check(sent && sent.includes("carol"), "la liste est transmise au Lua (extensions.grnfr_ghosts.onSync)")
// serveur plein pour un 5e joueur
for (const k of Object.keys(members)) delete members[k]
for (const n of ["p1", "p2", "p3", "p4"]) members[n] = {}
check(await net.joinServer("s1") === false && st.error.includes("complet"), "5e joueur : serveur complet")
// perte de place : tentative de retour automatique
for (const k of Object.keys(members)) delete members[k]
st.server = { id: "s1", name: "Serveur 1", max_players: 4 }
await handlers.GRNFRSelf({ level: "x", pos: { x: 0, y: 0, z: 0 } })
check(members.bob !== undefined, "place perdue (not_in_server) : retour automatique sur le serveur")
// pont réseau Lua -> Supabase -> Lua
engine.length = 0
await handlers.GRNFRNetReq({ id: 7, fn: "heartbeat", args: {} })
check(engine[0].startsWith("extensions.grnfr_online.onNetResult(7,true,") && engine[0].includes("25000"), "requête du Lua traitée et résultat renvoyé")
await handlers.GRNFRNetReq({ id: 8, fn: "boom", args: {} })
check(engine[1].includes("onNetResult(8,false,") && engine[1].includes("unknown_fn"), "erreur serveur renvoyée au Lua avec son code")
await handlers.GRNFRNetReq({ id: 9, fn: "drop table; --", args: {} })
check(engine.length === 2, "nom de fonction suspect refusé")
// jeton jamais écrit dans le texte envoyé au Lua
check(!engine.join("").includes("tok_") && httpCalls.length === 0, "le jeton n'est jamais transmis au Lua (relais disponible : aucun envoi par le Lua)")
check(frameSrc === "https://careermp.vercel.app/bridge.html", "le relais est chargé depuis le site")
check(bridgeCalls.length > 0 && bridgeCalls.every(c => /^\/(rest|auth)\/v1\//.test(c.path)), "toutes les requêtes passent par le relais, avec un chemin seulement (jamais une URL complète)")
check(bridgeCalls.some(c => c.authorization === "Bearer tok_anon2"), "le jeton de session part en en-tête Authorization")
await net.signOut()
check(st.status === "out" && st.server === null && lcalls.some(c => c[1] === "auth" && !JSON.parse(c[2]).loggedIn), "déconnexion : quitte le serveur, prévient le Lua")

// Repli : relais impossible (pas de cadre) -> envoi par le Lua (grnfr/http.lua), erreur combinant les deux causes.
delete globalThis.document
const net2 = await import(pathToFileURL(path.join(tmp, "net.mjs")) + "?sans-relais")
await net2.initNet()
check(await net2.signUpAnonymous("zoe") === true && httpCalls.some(h => h.url.startsWith("https://fake.supabase.co/") && h.url.includes("apikey=anon")), "sans relais : repli sur le Lua du jeu (clé anon en paramètre d'URL)")
const realLua = globalThis.__t.lua
globalThis.__t.lua = c => c.startsWith("extensions.grnfr_http.request(") ? handlers.GRNFRHttp({ id: Number(c.match(/\((\d+),/)[1]), status: 0, error: "ssl indisponible" }) : realLua(c)
await net2.signOut()
check(await net2.signUpAnonymous("yann") === false && /relais impossible.*Lua : ssl indisponible/.test(net2.net.error), "les deux échecs (relais et Lua) sont affichés ensemble")
console.log("=== TESTS CLIENT OK ===")
