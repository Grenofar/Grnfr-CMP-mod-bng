// GRNFR Online : client Supabase (HTTP) + pont vers le Lua du jeu.
// Le Lua de BeamNG ne sait pas faire de HTTPS : c'est l'interface (Chromium) qui parle à Supabase.
//   Lua --GRNFRNetReq--> ici --fetch--> Supabase --> ici --engineLua(onNetResult)--> Lua
//   Lua --GRNFRSelf (ma position)--> ici --server_sync--> ici --engineLua(onSync)--> Lua (fantômes + pseudos)
// Sans effet de bord au chargement : tout démarre dans initNet().
import { reactive } from "vue"
import { useBridge } from "@/bridge"
import cfg from "./serverConfig.js"
import { callLua, unwrapObj, unwrapList } from "./luaCall.js"

export const net = reactive({
  configured: !String(cfg.url).startsWith("__"),
  status: "out",          // out | busy | in
  username: "", email: "", me: null,
  error: "", info: "",
  open: false, lang: "fr", langChosen: true,
  quickOpen: false,       // petite fenêtre rapide (touche J) : chat, joueurs, drag
  dragCount: null,        // compte à rebours de départ d'une course de drag (3,2,1, puis 0 = TOP), null = masqué
  game: {},               // état poussé par le Lua (GRNFROnline) : taxi, bus, véhicules sortis, destination
  places: [],
  server: null,           // { id, name, max_players } si on est dans un serveur de jeu
  players: [],            // les autres joueurs du serveur (pseudo, carte, position...)
  syncErr: "",
  modVersion: null,       // version du mod installé (Lua, événement GRNFRStatic)
  updateAvailable: null,  // version plus récente publiée sur le site (null si à jour ou non vérifié)
  profiles: [],           // profils trouvés sur cette machine (settings/grnfr/profiles/*.grnfrprofile.json)
  exportedPath: "",       // chemin du dernier profil exporté (pour l'afficher au joueur)
  lastNetworkDetail: "",  // raison brute du dernier échec réseau (fetch) : DNS, TLS, pare-feu, CORS... pour diagnostiquer
})

const KEY = "grnfr_auth"
let auth = null          // { access, refresh, exp }
let sessionToken = null  // anti-partage : invalidé si une autre connexion a lieu avec le même compte
let started = false
let bridge = null
let syncBusy = false, lastPos = null, lastHb = 0, rejoining = false
let lastConvoy = null // dernière position des 2 voitures de trafic, envoyée par Lua si je suis l'hôte du serveur
let offs = []

// ------------------------------------------------------------------ stockage du jeton (jamais dans les logs)
function saveAuth() { try { auth ? localStorage.setItem(KEY, JSON.stringify(auth)) : localStorage.removeItem(KEY) } catch (e) { /* ignoré */ } }
function loadAuth() { try { const a = JSON.parse(localStorage.getItem(KEY) || "null"); if (a && a.refresh) auth = a } catch (e) { /* ignoré */ } }

// ------------------------------------------------------------------ HTTP
class NetError extends Error { constructor(code, status, detail) { super(code); this.code = code; this.status = status; this.detail = detail } }

const sleep = ms => new Promise(r => setTimeout(r, ms))

async function http(path, body, token, method = "POST") {
  if (!net.configured) throw new NetError("not_configured", 0)
  let res, lastErr = null
  // Beaucoup de "Failed to fetch" viennent d'un antivirus/pare-feu qui bloque le PREMIER contact du
  // processus BeamNG vers un hôte inconnu puis laisse passer la suite une fois la connexion inspectée —
  // 2 nouvelles tentatives (0,5s puis 1,5s) absorbent silencieusement ce cas sans rien demander au joueur.
  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await sleep(500 * attempt)
    try {
      res = await fetch(cfg.url + path, {
        method,
        headers: { apikey: cfg.anonKey, "Content-Type": "application/json", Authorization: "Bearer " + (token || cfg.anonKey) },
        body: body === undefined ? undefined : JSON.stringify(body),
      })
      lastErr = null
      break
    } catch (e) { lastErr = e }
  }
  if (lastErr) {
    // fetch() ne donne jamais plus de détail que "Failed to fetch", que la cause soit DNS, pare-feu, TLS
    // ou CORS — c'est volontaire côté navigateur (anti-fingerprinting). Pour distinguer un blocage réseau
    // total d'un souci plus spécifique (CORS/preflight/en-têtes, potentiellement réparable sans rien
    // demander au joueur), on retente une requête minimale SANS les en-têtes personnalisés (apikey,
    // Authorization) : si elle passe, le problème vient des en-têtes/du preflight, pas du réseau en entier.
    let probe = "sonde impossible"
    try { await fetch(cfg.url + "/rest/v1/", { method: "GET" }); probe = "une requête nue (sans en-têtes) passe : probablement CORS/preflight, pas un blocage réseau total" }
    catch (e2) { probe = "même une requête nue échoue : blocage réseau complet (pare-feu/DNS/antivirus)" }
    net.lastNetworkDetail = ((lastErr.message || lastErr.name) || String(lastErr)) + " — " + probe
    throw new NetError("network", 0, net.lastNetworkDetail)
  }
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
    anonymous_provider_disabled: "Création de profil indisponible (connexions anonymes désactivées sur le serveur).",
    session_replaced: "Votre profil a été utilisé ailleurs : vous avez été déconnecté ici.",
    bad_profile: "Fichier de profil invalide ou illisible.",
    username_change_cooldown: "Vous avez déjà changé de pseudo récemment : réessayez plus tard.",
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
    anonymous_provider_disabled: "Cannot create a profile (anonymous sign-ins are disabled on the server).",
    session_replaced: "Your profile was used somewhere else: you were disconnected here.",
    bad_profile: "Invalid or unreadable profile file.",
    username_change_cooldown: "You already changed your username recently: try again later.",
  },
}
export function errText(e) {
  const code = e?.code || e?.message || String(e)
  const base = (ERR[net.lang] || ERR.fr)[code] || ((net.lang === "en" ? "Error: " : "Erreur : ") + code)
  // Même logique que hintFor() dans OnlineWindow.vue pour la vérif de pseudo en direct : montrer la cause
  // brute à chaque fois qu'on affiche une erreur "network", pas seulement à cet endroit-là.
  return code === "network" && net.lastNetworkDetail ? `${base} (${net.lastNetworkDetail})` : base
}

// ------------------------------------------------------------------ compte
export async function usernameAvailable(name) {
  try { return (await rpcPublic("username_available", { p_username: name })) === true } catch (e) { return null }
}

async function afterLogin() {
  await refreshMe()
  net.status = "in"
  try { sessionToken = await rpc("start_session") } catch (e) { sessionToken = null } // anti-partage : best-effort
  await ui("auth", { loggedIn: true, username: net.username })
}

export async function refreshMe() {
  const me = await rpc("get_me")
  net.me = me
  net.username = me?.profile?.username || net.username
  return me
}

// Création de profil : pas d'e-mail ni de mot de passe, juste un pseudo. Connexion anonyme Supabase (à activer :
// Authentication > Providers > Anonymous Sign-Ins), puis choix du pseudo (set_username). Ce qui prouve que
// c'est vous ensuite, c'est le jeton de session gardé ici (voir exportProfile/importProfile) : à exporter
// avant de changer de PC, sinon la progression reste associée à cette seule machine.
export async function signUpAnonymous(username) {
  net.error = ""; net.info = ""
  username = (username || "").trim()
  if (!/^[A-Za-z0-9_]{3,20}$/.test(username)) { net.error = errText({ code: "username_invalid" }); return false }
  net.status = "busy"
  try {
    const free = await usernameAvailable(username)
    if (free === false) { net.status = "out"; net.error = errText({ code: "username_taken" }); return false }
    const d = await http("/auth/v1/signup", {})
    if (!d || !d.access_token) { net.status = "out"; net.error = errText({ code: "anon_failed" }); return false }
    setSession(d)
    await afterLogin()
    const ok = await chooseUsername(username)
    return ok
  } catch (e) { net.status = "out"; net.error = errText(e); return false }
}

export async function chooseUsername(name) {
  net.error = ""
  name = (name || "").trim()
  try { await rpc("set_username", { p_username: name }); await refreshMe(); await ui("auth", { loggedIn: true, username: net.username }); return true }
  catch (e) { net.error = errText(e); return false }
}

// Renommage d'un pseudo déjà confirmé (contrairement à set_username, utilisable une fois le compte créé).
export async function changeUsername(name) {
  net.error = ""; net.info = ""
  name = (name || "").trim()
  if (!/^[A-Za-z0-9_]{3,20}$/.test(name)) { net.error = errText({ code: "username_invalid" }); return false }
  try {
    await rpc("change_username", { p_username: name })
    await refreshMe()
    await ui("auth", { loggedIn: true, username: net.username })
    return true
  } catch (e) { net.error = errText(e); return false }
}

export async function signOut() {
  try { if (net.server) await rpc("leave_server") } catch (e) { /* ignoré */ }
  setServerLocal(null)
  auth = null; saveAuth(); sessionToken = null
  net.status = "out"; net.me = null; net.username = ""
  await ui("auth", { loggedIn: false })
}

// Déconnexion forcée : une autre connexion a eu lieu avec le même profil (voir session_replaced). On ne
// prévient pas le serveur (il a déjà sa nouvelle session) : juste un nettoyage local + message clair.
function forceSignOutReplaced() {
  setServerLocal(null)
  auth = null; saveAuth(); sessionToken = null
  net.status = "out"; net.me = null; net.username = ""
  net.error = errText({ code: "session_replaced" })
  ui("auth", { loggedIn: false })
}

// ------------------------------------------------------------------ profil portable (export/import)
// Le fichier exporté contient le jeton de connexion actuel : c'est tout ce qu'il faut pour redevenir "vous"
// sur une autre machine (voir profile.lua). Rien d'économique n'est dupliqué : l'argent et le garage restent
// décidés par le serveur, lus à nouveau au prochain login, où qu'il ait lieu.
export function exportProfile() {
  if (!auth?.refresh || !net.username) return
  ui("profile.export", { username: net.username, refresh: auth.refresh })
}
export function requestProfiles() { ui("profile.list") }
export async function importProfile(path) {
  net.error = ""
  ui("profile.import", { path })
}
function onProfileImport(d) {
  const g = unwrapObj(d)
  const data = g && g.data
  if (!data || !data.refresh) { net.error = errText({ code: "bad_profile" }); return }
  auth = { access: null, refresh: data.refresh, exp: 0 } // force un rafraîchissement immédiat
  saveAuth()
  net.status = "busy"
  refresh().then(afterLogin).catch(e => { net.status = "out"; net.error = errText(e) })
}

// ------------------------------------------------------------------ serveurs de jeu
function setServerLocal(srv) {
  net.server = srv
  if (!srv) { net.players = []; lastConvoy = null }
  const interval = Math.max(150, Number(net.me?.config?.sync_interval_ms) || 300)
  ui("server.state", { joined: !!srv, name: srv?.name || "", intervalMs: interval })
}

// ------------------------------------------------------------------ mise à jour du mod
// Compare la version du mod (Lua) à la dernière release publiée sur le site. Vérifié une seule fois par
// lancement : le joueur recopie lui-même le zip dans son dossier mods, BeamNG n'installe rien tout seul.
let updateChecked = false
function newerVersion(a, b) {
  const pa = String(a).split(".").map(Number), pb = String(b).split(".").map(Number)
  for (let i = 0; i < 3; i++) { if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0) }
  return false
}
async function checkUpdate() {
  if (updateChecked || !net.configured || !net.modVersion) return
  updateChecked = true
  try {
    const latest = await rpcPublic("get_latest_release", {})
    if (latest && newerVersion(latest.version, net.modVersion)) net.updateAvailable = latest.version
  } catch (e) { /* pas d'inquiétude : on retentera au prochain lancement */ }
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

// Position des 2 voitures de trafic partagé, envoyée par Lua uniquement si je suis l'hôte du serveur (voir convoy.lua).
function onConvoySelf(d) {
  const c = unwrapList(d)
  if (Array.isArray(c)) lastConvoy = c
}

// Réception de ma position (Lua) -> server_sync -> envoi des autres joueurs (et du trafic partagé) au Lua.
async function onSelf(d) {
  const s = unwrapObj(d)
  if (!s || !net.server || syncBusy || net.status !== "in") return
  syncBusy = true
  try {
    const r = await rpc("server_sync", { p_level: s.level || null, p_pos: s.pos || null, p_rot: s.rot || null, p_vel: s.vel || null, p_veh: s.veh || null, p_convoy: lastConvoy, p_session: sessionToken })
    net.syncErr = ""
    net.players = r.players || []
    engineLua("extensions.grnfr_ghosts.onSync(" + luaStr(JSON.stringify({ players: net.players })) + ")")
    engineLua("extensions.grnfr_convoy.onSync(" + luaStr(JSON.stringify({ isHost: r.is_host === true, convoy: r.convoy || null })) + ")")
  } catch (e) {
    if (e.code === "session_replaced") { forceSignOutReplaced() }
    else if (e.code === "not_in_server" && net.server && !rejoining) { // place libérée (coupure réseau) : on tente de revenir
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
  try { await rpc("heartbeat", { p_level: p.level || null, p_pos: p.pos || null, p_duty: p.duty || "none", p_session: sessionToken }); await refreshMe() }
  catch (e) { if (e.code === "session_replaced") forceSignOutReplaced() }
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
  on("GRNFRConvoySelf", onConvoySelf)
  on("GRNFRPos", onPos)
  on("GRNFROnline", d => { const g = unwrapObj(d); if (g) net.game = g })
  on("GRNFRPlaces", d => { const g = unwrapObj(d); if (g?.places) net.places = g.places })
  on("GRNFROnlineWin", d => { const g = unwrapObj(d); if (g) net.open = !!g.open })
  on("GRNFRQuickWin", d => { const g = unwrapObj(d); if (g) net.quickOpen = !!g.open })
  on("GRNFRProfileExport", d => { const g = unwrapObj(d); if (g?.ok) net.exportedPath = g.path || "" })
  on("GRNFRProfileList", d => { const g = unwrapObj(d); if (g) net.profiles = g.list || [] })
  on("GRNFRProfileImport", onProfileImport)
  on("GRNFRDragCount", d => {
    const g = unwrapObj(d)
    if (!g || typeof g.value !== "number") return
    net.dragCount = g.value
    if (g.value === 0) setTimeout(() => { net.dragCount = null }, 1200)
  })
  on("GRNFRStatic", d => {
    const g = unwrapObj(d)
    if (g?.settings?.lang) net.lang = g.settings.lang
    if (g?.settings && "langChosen" in g.settings) net.langChosen = g.settings.langChosen !== false
    if (g?.version && g.version !== net.modVersion) { net.modVersion = g.version; checkUpdate() }
  })
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
