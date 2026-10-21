// GRNFR Online : client Supabase (HTTP) + pont vers le Lua du jeu.
// Le Lua de BeamNG ne sait pas faire de HTTPS : c'est l'interface (Chromium) qui parle à Supabase.
//   Lua --GRNFRNetReq--> ici --fetch--> Supabase --> ici --engineLua(onNetResult)--> Lua
//   Lua --GRNFRSelf (ma position)--> ici --server_sync--> ici --engineLua(onSync)--> Lua (fantômes + pseudos)
// Sans effet de bord au chargement : tout démarre dans initNet().
import { reactive } from "vue"
import { useBridge } from "@/bridge"
import cfg from "./serverConfig.js"
import { callLua, unwrapObj } from "./luaCall.js"

export const net = reactive({
  configured: !String(cfg.url).startsWith("__"),
  status: "out",          // out | busy | in
  username: "", email: "", me: null,
  error: "", info: "",
  open: false, lang: "fr",
  game: {},               // état poussé par le Lua (GRNFROnline) : taxi, bus, véhicules sortis, destination
  places: [],
  server: null,           // { id, name, max_players } si on est dans un serveur de jeu
  players: [],            // les autres joueurs du serveur (pseudo, carte, position...)
  syncErr: "",
})

const KEY = "grnfr_auth"
let auth = null          // { access, refresh, exp }
let started = false
let bridge = null
let syncBusy = false, lastPos = null, lastHb = 0, rejoining = false
let offs = []

// ------------------------------------------------------------------ stockage du jeton (jamais dans les logs)
function saveAuth() { try { auth ? localStorage.setItem(KEY, JSON.stringify(auth)) : localStorage.removeItem(KEY) } catch (e) { /* ignoré */ } }
function loadAuth() { try { const a = JSON.parse(localStorage.getItem(KEY) || "null"); if (a && a.refresh) auth = a } catch (e) { /* ignoré */ } }

// ------------------------------------------------------------------ HTTP
class NetError extends Error { constructor(code, status) { super(code); this.code = code; this.status = status } }

async function http(path, body, token, method = "POST") {
  if (!net.configured) throw new NetError("not_configured", 0)
  let res
  try {
    res = await fetch(cfg.url + path, {
      method,
      headers: { apikey: cfg.anonKey, "Content-Type": "application/json", Authorization: "Bearer " + (token || cfg.anonKey) },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch (e) { throw new NetError("network", 0) }
  let data = null
  try { data = await res.json() } catch (e) { /* corps vide */ }
  if (!res.ok) {
    const code = (data && (data.message || data.msg || data.error_description || data.error)) || ("http_" + res.status)
    throw new NetError(String(code), res.status)
  }
  return data
}

function setSession(d) {
  auth = { access: d.access_token, refresh: d.refresh_token, exp: Date.now() + (d.expires_in || 3600) * 1000 }
  saveAuth()
}

async function refresh() {
  if (!auth?.refresh) throw new NetError("not_authenticated", 401)
  const d = await http("/auth/v1/token?grant_type=refresh_token", { refresh_token: auth.refresh })
  setSession(d)
}

async function token() {
  if (!auth) throw new NetError("not_authenticated", 401)
  if (auth.exp - Date.now() < 60000) await refresh()
  return auth.access
}

export async function rpc(fn, args) {
  let t = await token()
  try { return await http("/rest/v1/rpc/" + fn, args || {}, t) } catch (e) {
    if (e.status === 401 && auth?.refresh) { await refresh(); return http("/rest/v1/rpc/" + fn, args || {}, auth.access) }
    throw e
  }
}
export async function rpcPublic(fn, args) { return http("/rest/v1/rpc/" + fn, args || {}, null) }

// ------------------------------------------------------------------ pont Lua
function api() { try { bridge = bridge || useBridge() } catch (e) { return null } return bridge?.api ?? (typeof window !== "undefined" ? window.bngApi : null) }

// Texte -> littéral de chaîne Lua : \ " et tout octet non ASCII / de contrôle sont écrits en \ddd (LuaJIT ne connaît pas \u).
export function luaStr(s) {
  const bytes = new TextEncoder().encode(String(s))
  let out = '"'
  for (const b of bytes) {
    if (b === 34 || b === 92) out += "\\" + String.fromCharCode(b)
    else if (b < 32 || b > 126) out += "\\" + String(b).padStart(3, "0")
    else out += String.fromCharCode(b)
  }
  return out + '"'
}
function engineLua(code) { const a = api(); if (a) { try { a.engineLua(code) } catch (e) { /* ignoré */ } } }

function sendResult(id, ok, obj) { engineLua("extensions.grnfr_online.onNetResult(" + Number(id) + "," + (ok ? "true" : "false") + "," + luaStr(JSON.stringify(obj)) + ")") }

export const ui = (name, args) => callLua("ui", name, JSON.stringify(args || {}))

// ------------------------------------------------------------------ messages d'erreur lisibles
const ERR = {
  fr: {
    network: "Impossible de joindre le serveur (réseau).", not_configured: "Ce mod n'est pas relié à un serveur (voir le site).",
    username_taken: "Ce pseudo est déjà pris.", username_invalid: "Pseudo invalide : 3 à 20 lettres, chiffres ou _.",
    username_required: "Choisissez un pseudo avant de rejoindre un serveur.", username_already_set: "Pseudo déjà choisi.",
    server_full: "Ce serveur est complet (4 joueurs).", server_not_found: "Serveur introuvable.", not_in_server: "Vous n'êtes plus dans le serveur.",
    not_authenticated: "Connectez-vous d'abord.", forbidden: "Réservé aux administrateurs.",
    insufficient_funds: "Fonds insuffisants.", garage_full: "Garage plein.",
    invalid_login_credentials: "E-mail ou mot de passe incorrect.", "Invalid login credentials": "E-mail ou mot de passe incorrect.",
    "User already registered": "Un compte existe déjà avec cet e-mail.", email_not_confirmed: "Confirmez d'abord votre e-mail (lien reçu).",
    "Database error saving new user": "Pseudo invalide ou déjà pris.",
  },
  en: {
    network: "Cannot reach the server (network).", not_configured: "This mod is not linked to a server (see the website).",
    username_taken: "This username is already taken.", username_invalid: "Invalid username: 3 to 20 letters, digits or _.",
    username_required: "Pick a username before joining a server.", username_already_set: "Username already chosen.",
    server_full: "This server is full (4 players).", server_not_found: "Server not found.", not_in_server: "You are no longer in the server.",
    not_authenticated: "Sign in first.", forbidden: "Admins only.",
    insufficient_funds: "Not enough money.", garage_full: "Garage is full.",
    invalid_login_credentials: "Wrong e-mail or password.", "Invalid login credentials": "Wrong e-mail or password.",
    "User already registered": "An account already exists with this e-mail.", email_not_confirmed: "Confirm your e-mail first (link sent).",
    "Database error saving new user": "Invalid or already taken username.",
  },
}
export function errText(e) {
  const code = e?.code || e?.message || String(e)
  return (ERR[net.lang] || ERR.fr)[code] || ((net.lang === "en" ? "Error: " : "Erreur : ") + code)
}

// ------------------------------------------------------------------ compte
export async function usernameAvailable(name) {
  try { return (await rpcPublic("username_available", { p_username: name })) === true } catch (e) { return null }
}

async function afterLogin() {
  await refreshMe()
  net.status = "in"
  await ui("auth", { loggedIn: true, username: net.username })
}

export async function refreshMe() {
  const me = await rpc("get_me")
  net.me = me
  net.username = me?.profile?.username || net.username
  return me
}

export async function signIn(email, password) {
  net.error = ""; net.status = "busy"
  try {
    setSession(await http("/auth/v1/token?grant_type=password", { email, password }))
    net.email = email
    await afterLogin()
  } catch (e) { net.status = "out"; net.error = errText(e) }
}

// Inscription : le pseudo est OBLIGATOIRE et doit être libre (vérifié avant, puis refusé aussi par la base si besoin).
export async function signUp(email, password, username) {
  net.error = ""; net.info = ""
  if (!/^[A-Za-z0-9_]{3,20}$/.test(username || "")) { net.error = errText({ code: "username_invalid" }); return }
  net.status = "busy"
  try {
    const free = await usernameAvailable(username)
    if (free === false) { net.status = "out"; net.error = errText({ code: "username_taken" }); return }
    const d = await http("/auth/v1/signup", { email, password, data: { username } })
    if (d && d.access_token) { setSession(d); net.email = email; await afterLogin() }
    else { net.status = "out"; net.info = net.lang === "en" ? "Account created. Confirm your e-mail, then sign in." : "Compte créé. Confirmez votre e-mail, puis connectez-vous." }
  } catch (e) { net.status = "out"; net.error = errText(e) }
}

export async function chooseUsername(name) {
  net.error = ""
  try { await rpc("set_username", { p_username: name }); await refreshMe(); await ui("auth", { loggedIn: true, username: net.username }); return true }
  catch (e) { net.error = errText(e); return false }
}

export async function signOut() {
  try { if (net.server) await rpc("leave_server") } catch (e) { /* ignoré */ }
  setServerLocal(null)
  auth = null; saveAuth()
  net.status = "out"; net.me = null; net.username = ""
  await ui("auth", { loggedIn: false })
}

// ------------------------------------------------------------------ serveurs de jeu
function setServerLocal(srv) {
  net.server = srv
  if (!srv) net.players = []
  const interval = Math.max(150, Number(net.me?.config?.sync_interval_ms) || 300)
  ui("server.state", { joined: !!srv, name: srv?.name || "", intervalMs: interval })
}

export async function listServers() { return rpc("get_servers") }

export async function joinServer(id) {
  net.error = ""
  try { const srv = await rpc("join_server", { p_server: id }); setServerLocal(srv); return true }
  catch (e) { net.error = errText(e); return e.code === "username_required" ? "pseudo" : false }
}

export async function leaveServer() {
  try { await rpc("leave_server") } catch (e) { /* ignoré */ }
  setServerLocal(null)
}

// Réception de ma position (Lua) -> server_sync -> envoi des autres joueurs au Lua.
async function onSelf(d) {
  const s = unwrapObj(d)
  if (!s || !net.server || syncBusy || net.status !== "in") return
  syncBusy = true
  try {
    const r = await rpc("server_sync", { p_level: s.level || null, p_pos: s.pos || null, p_rot: s.rot || null, p_vel: s.vel || null, p_veh: s.veh || null })
    net.syncErr = ""
    net.players = r.players || []
    engineLua("extensions.grnfr_ghosts.onSync(" + luaStr(JSON.stringify({ players: net.players })) + ")")
  } catch (e) {
    if (e.code === "not_in_server" && net.server && !rejoining) { // place libérée (coupure réseau) : on tente de revenir
      rejoining = true
      try { await rpc("join_server", { p_server: net.server.id }) } catch (e2) { net.error = errText(e2); setServerLocal(null) }
      rejoining = false
    } else net.syncErr = errText(e)
  }
  syncBusy = false
}

// Battement de cœur (service taxi/bus, position) + solde, toutes les ~15 s.
async function onPos(d) {
  const p = unwrapObj(d)
  if (!p || net.status !== "in") return
  lastPos = p
  if (Date.now() - lastHb < 15000) return
  lastHb = Date.now()
  try { await rpc("heartbeat", { p_level: p.level || null, p_pos: p.pos || null, p_duty: p.duty || "none" }); await refreshMe() } catch (e) { /* prochain essai */ }
}

async function onNetReq(d) {
  const r = unwrapObj(d)
  if (!r || r.id === undefined || !/^[a-z_]{2,40}$/.test(String(r.fn))) return
  try { sendResult(r.id, true, { r: await rpc(r.fn, r.args) }) } catch (e) { sendResult(r.id, false, { e: e.code || "error" }) }
}

// ------------------------------------------------------------------ démarrage / arrêt
export async function initNet() {
  if (started) return
  started = true
  let b; try { b = useBridge() } catch (e) { started = false; return }
  const on = (name, fn) => { b.events.on(name, fn); offs.push(() => b.events.off(name, fn)) }
  on("GRNFRNetReq", onNetReq)
  on("GRNFRSelf", onSelf)
  on("GRNFRPos", onPos)
  on("GRNFROnline", d => { const g = unwrapObj(d); if (g) net.game = g })
  on("GRNFRPlaces", d => { const g = unwrapObj(d); if (g?.places) net.places = g.places })
  on("GRNFROnlineWin", d => { const g = unwrapObj(d); if (g) net.open = !!g.open })
  on("GRNFRStatic", d => { const g = unwrapObj(d); if (g?.settings?.lang) net.lang = g.settings.lang })
  loadAuth()
  if (auth) { // session précédente : on la reprend sans redemander le mot de passe
    net.status = "busy"
    try { await refresh(); await afterLogin() } catch (e) { auth = null; saveAuth(); net.status = "out" }
  }
}

export function stopNet() {
  offs.forEach(f => { try { f() } catch (e) { /* ignoré */ } })
  offs = []; started = false
}
