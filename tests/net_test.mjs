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
const lcalls = [], engine = [], handlers = {}
globalThis.__t = { lcalls, engine, handlers }
fs.writeFileSync(path.join(tmp, "bridge_stub.mjs"), `export const useBridge = () => ({ events: { on: (n, f) => { globalThis.__t.handlers[n] = f }, off: () => {} }, api: { engineLua: c => globalThis.__t.engine.push(c) } })`)
fs.writeFileSync(path.join(tmp, "lua_stub.mjs"), `export const callLua = async (...a) => { globalThis.__t.lcalls.push(a) }\nexport const unwrapObj = d => d\nexport const unwrapList = d => d`)
globalThis.localStorage = { s: {}, getItem(k) { return this.s[k] ?? null }, setItem(k, v) { this.s[k] = v }, removeItem(k) { delete this.s[k] } }

// ---------- faux Supabase
const users = {}, members = {}, calls = []
const MAX = 4
let signupCalls = 0
globalThis.fetch = async (url, opt) => {
  const p = url.replace("https://fake.supabase.co", "")
  const body = opt.body ? JSON.parse(opt.body) : undefined
  const auth = opt.headers.Authorization.replace("Bearer ", "")
  const ok = (d, status = 200) => ({ ok: status < 400, status, json: async () => d })
  calls.push(p)
  if (p === "/auth/v1/signup") { signupCalls++; users[body.email] = { name: body.data.username }; return ok({ access_token: "tok_" + body.data.username, refresh_token: "ref_" + body.data.username, expires_in: 3600 }) }
  if (p.startsWith("/auth/v1/token")) { const u = users[body.email]; if (!u) return ok({ error_description: "Invalid login credentials" }, 400); return ok({ access_token: "tok_" + u.name, refresh_token: "ref_" + u.name, expires_in: 3600 }) }
  const fn = p.replace("/rest/v1/rpc/", "")
  const me = auth.startsWith("tok_") ? auth.slice(4) : null
  if (fn === "username_available") return ok(!Object.values(users).some(u => u.name.toLowerCase() === body.p_username.toLowerCase()))
  if (!me) return ok({ message: "not_authenticated" }, 401)
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

// inscription : pseudo invalide / pris refusés AVANT d'appeler signup
await net.signUp("a@x.fr", "secret1", "ab")
check(st.error.includes("invalide") && signupCalls === 0, "pseudo trop court refusé")
users["z@x.fr"] = { name: "Alice" }
await net.signUp("a@x.fr", "secret1", "alice")
check(st.error.includes("déjà pris") && signupCalls === 0 && st.status === "out", "pseudo déjà pris (sans tenir compte de la casse) refusé, aucun compte créé")
await net.signUp("a@x.fr", "secret1", "bob")
check(st.status === "in" && st.username === "bob" && signupCalls === 1, "inscription avec un pseudo libre")
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
check(!engine.join("").includes("tok_"), "le jeton n'est jamais transmis au Lua")
await net.signOut()
check(st.status === "out" && st.server === null && lcalls.some(c => c[1] === "auth" && !JSON.parse(c[2]).loggedIn), "déconnexion : quitte le serveur, prévient le Lua")
console.log("=== TESTS CLIENT OK ===")
