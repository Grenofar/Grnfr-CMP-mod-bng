<template>
  <!-- Fenêtre GRNFR Online (touche O). Monté dans <body> par index.js, comme le HUD. -->
  <div v-if="net.open" class="onw" @focusin="focus($event, true)" @focusout="focus($event, false)">
    <div class="win">
      <header>
        <span class="title">{{ t('title') }}</span>
        <span v-if="logged" class="who">{{ net.username }} · {{ money(profile.balance) }}</span>
        <button type="button" class="hb" @click="ui('window.close')">✕ {{ t('close') }}</button>
      </header>
      <div v-if="net.updateAvailable" class="bar upd">{{ t('update_available').replace('{v}', net.updateAvailable) }}</div>
      <div v-if="logged && net.server" class="bar">
        🟢 {{ net.server.name }} — {{ net.players.length + 1 }}/{{ net.server.max_players }} :
        <b>{{ net.username }}</b><span v-for="p in net.players" :key="p.username">, {{ p.username }}</span>
        <span v-if="net.syncErr" class="warn"> · {{ t('srv_sync_bad') }}{{ net.syncErr }}</span>
      </div>
      <div class="body">
      <nav class="tabs">
        <button v-for="x in tabs" :key="x" type="button" :class="{ on: tab === x }" @click="tab = x">
          <svg viewBox="0 0 24 24"><path :d="icons[x]" /></svg><span>{{ t('t_' + x) }}</span>
        </button>
      </nav>
      <main>
        <p v-if="net.error" class="err">{{ net.error }}</p>
        <p v-if="net.info || msg" class="ok">{{ net.info || msg }}</p>

        <!-- COMPTE -->
        <section v-if="tab === 'account'">
          <p v-if="!net.configured" class="err">{{ t('conf_server') }}</p>
          <template v-else-if="!logged">
            <div class="form">
              <!-- Pas de compte au sens classique : un profil = juste un pseudo, stocké sur cette machine
                   (settings/grnfr/profiles/*.grnfrprofile.json). On choisit un profil existant, ou on en
                   crée un nouveau — jamais d'e-mail ni de mot de passe. -->
              <template v-if="net.profiles.length && !showCreate">
                <h4>{{ t('your_profiles') }}</h4>
                <div v-for="p in net.profiles" :key="p.path" class="row">
                  <span>{{ p.username }}</span>
                  <button type="button" class="btn" @click="importProfile(p.path)">{{ t('use_this') }}</button>
                </div>
                <button type="button" class="lnk" @click="showCreate = true">{{ t('create_new_instead') }}</button>
              </template>

              <template v-else>
                <h4>{{ t('quick_create') }}</h4>
                <input v-model="f.pseudo" type="text" maxlength="20" :placeholder="t('username')" autocomplete="off" @input="checkPseudo" />
                <small :class="hintClass(pseudoState)">{{ pseudoHint }}</small>
                <button type="button" class="btn" :disabled="busy || pseudoState !== 'free'" @click="net_createProfile">{{ t('create_profile') }}</button>
                <button v-if="net.profiles.length" type="button" class="lnk" @click="showCreate = false">{{ t('back_to_profiles') }}</button>
              </template>
            </div>
          </template>
          <template v-else>
            <div class="cards">
              <div class="card"><label>{{ t('balance') }}</label><div class="big">{{ money(profile.balance) }}</div></div>
              <div class="card"><label>{{ t('username') }}</label><div class="big sm">{{ net.username }}</div></div>
            </div>
            <h4>{{ t('change_pseudo') }}</h4>
            <div class="row">
              <input v-model="f.newPseudo" type="text" maxlength="20" :placeholder="t('username')" autocomplete="off" @input="checkNewPseudo" />
              <small :class="hintClass(newPseudoState)">{{ newPseudoHint }}</small>
              <button type="button" class="btn" :disabled="busy || newPseudoState !== 'free'" @click="net_changePseudo">{{ t('change_pseudo_do') }}</button>
            </div>
            <h4>{{ t('your_profile') }}</h4>
            <p class="mut">{{ t('profile_hint') }}</p>
            <div class="row">
              <button type="button" class="btn dim" @click="exportProfile">{{ t('export_profile') }}</button>
              <span v-if="net.exportedPath" class="mut">{{ t('exported_to') }} {{ net.exportedPath }}</span>
              <button type="button" class="btn dim" @click="switchProfile">{{ t('switch_profile') }}</button>
            </div>
            <h4>{{ t('history') }}</h4>
            <table class="tb"><tr v-for="x in d.tx" :key="x.id"><td>{{ x.created_at.slice(0, 16).replace('T', ' ') }}</td><td>{{ x.ref || x.kind }}</td><td :class="x.amount < 0 ? 'bad' : 'good'">{{ x.amount > 0 ? '+' : '' }}{{ x.amount }}</td></tr></table>
            <button type="button" class="btn dim" @click="net_signOut">{{ t('signout') }}</button>
          </template>
        </section>

        <!-- RÉGLAGES (HUD, compteur FPS, langue, mods) : AVANT la case "pas connecté" ci-dessous (sinon, dans
             cette chaîne v-if/v-else-if, le réglage n'était jamais atteint sans compte/profil : on retombait
             toujours sur "Connectez-vous d'abord") -- accessible sans compte ni profil, comme demandé. Quand
             aucun profil n'est encore choisi, on peut aussi en reprendre un récemment joué directement ici,
             sans passer par l'onglet Compte. -->
        <section v-else-if="tab === 'settings'" class="embed-panel">
          <div v-if="!logged && net.profiles.length" class="recent">
            <h4>{{ t('your_profiles') }}</h4>
            <div v-for="p in net.profiles" :key="p.path" class="row">
              <span>{{ p.username }}</span>
              <button type="button" class="btn dim" @click="importProfile(p.path)">{{ t('use_this') }}</button>
            </div>
          </div>
          <GrnfrPanel />
        </section>

        <p v-else-if="!logged" class="mut">{{ t('login_first') }}</p>

        <!-- SERVEURS -->
        <section v-else-if="tab === 'servers'">
          <h4>{{ t('srv_title') }}</h4>
          <p class="mut">{{ t('srv_note') }}</p>
          <div v-if="needPseudo" class="form">
            <p class="warn">{{ t('pseudo_needed') }}</p>
            <input v-model="f.username" maxlength="20" :placeholder="t('username')" @input="checkName" />
            <small :class="hintClass(nameState)">{{ nameHint }}</small>
            <button type="button" class="btn" :disabled="nameState !== 'free'" @click="pickName">{{ t('choose') }}</button>
          </div>
          <div class="row">
            <input v-model="f.srvSearch" type="text" :placeholder="t('srv_search')" autocomplete="off" />
          </div>
          <p v-if="f.srvSearch && !filteredServers.length" class="mut">{{ t('srv_search_none') }}</p>
          <div v-for="s in filteredServers" :key="s.id" class="card srv" :class="{ me: net.server && net.server.id === s.id }">
            <div class="row">
              <b>{{ s.name }}</b><span class="cnt">{{ s.count }}/{{ s.max_players }}</span>
              <button v-if="net.server && net.server.id === s.id" type="button" class="btn dim" @click="leave">{{ t('srv_leave') }}</button>
              <button v-else type="button" class="btn" :disabled="s.count >= s.max_players" @click="join(s.id)">{{ s.count >= s.max_players ? t('srv_full') : t('srv_join') }}</button>
            </div>
            <div class="mut">{{ t('srv_players') }} : {{ s.players.length ? s.players.join(', ') : t('srv_empty') }}</div>
          </div>
          <template v-if="net.server">
            <h4>{{ t('srv_others') }}</h4>
            <p v-if="!net.players.length" class="mut">{{ t('srv_empty') }}</p>
            <div v-for="p in net.players" :key="p.username" class="card">
              <b>{{ p.username }}</b>
              <span class="mut"> · {{ p.level === net.game.level ? t('srv_map') + ' ✓' : t('srv_other_map') }}<template v-if="p.veh"> · {{ p.veh.model }}</template></span>
            </div>
          </template>
          <p v-else class="mut">{{ t('srv_off') }}</p>
        </section>

        <!-- CLASSEMENT -->
        <section v-else-if="tab === 'board'">
          <p class="mut">{{ t('lb_wealth') }}</p>
          <table class="tb"><tr v-for="(r, i) in d.board" :key="r.username" :class="{ me: r.username === net.username }"><td>{{ i + 1 }}</td><td>{{ r.username }}</td><td>{{ money(r.wealth) }}</td></tr></table>
        </section>

        <!-- ADMIN -->
        <section v-else-if="tab === 'admin'">
          <h4>{{ t('adm_give') }}</h4>
          <div class="form">
            <input v-model="f.au" :placeholder="t('adm_user')" /><input v-model.number="f.aa" type="number" :placeholder="t('amount')" /><input v-model="f.ar" :placeholder="t('adm_reason')" />
            <button type="button" class="btn" @click="act(() => rpc('admin_give_money', { p_username: f.au, p_amount: f.aa, p_reason: f.ar || null }))">{{ t('adm_do') }}</button>
          </div>
          <h4>{{ t('adm_kick') }}</h4>
          <div class="row"><input v-model="f.ku" :placeholder="t('adm_user')" /><button type="button" class="btn dim" @click="act(() => rpc('admin_kick', { p_username: f.ku }))">{{ t('adm_do') }}</button></div>
          <h4>{{ t('adm_new') }}</h4>
          <div class="row"><input v-model="f.sn" :placeholder="t('adm_name')" /><button type="button" class="btn dim" @click="act(() => rpc('admin_create_server', { p_name: f.sn, p_max: 4 }))">{{ t('adm_do') }}</button></div>
        </section>
      </main>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted, onBeforeUnmount } from "vue"
import {
  net, ui, rpc, errText, signUpAnonymous, signOut, refreshMe, usernameAvailable, chooseUsername, changeUsername,
  listServers, joinServer, leaveServer, exportProfile as netExportProfile, requestProfiles, importProfile as netImportProfile,
} from "./net.js"
import { tr } from "./onlineI18n.js"
import GrnfrPanel from "./GrnfrPanel.vue"

const t = k => tr(net.lang, k)
const tab = ref("account")
const busy = ref(false), msg = ref(""), needPseudo = ref(false)
const showCreate = ref(false)
const pseudoState = ref(""), newPseudoState = ref("")
const nameState = ref(""), f = reactive({ username: "", pseudo: "", newPseudo: "", srvSearch: "", place: 0, offer: "", want: "", cash: 0 })
const d = reactive({ tx: [], servers: [], catalog: [], market: [], trades: [], theirs: [], board: [], reqs: [] })

const logged = computed(() => net.status === "in")
const me = computed(() => net.me || {})
const profile = computed(() => net.me?.profile || {})
const tabs = computed(() => ["account", "servers", "board", "settings"].concat(profile.value.is_admin ? ["admin"] : []))
const icons = {
  account: "M12 8a4 4 0 100-8 4 4 0 000 8zM4 20c0-4 4-6 8-6s8 2 8 6",
  servers: "M4 4h16v4H4zM4 10h16v4H4zM4 16h16v4H4z",
  board: "M4 14h4v6H4zM10 10h4v10h-4zM16 6h4v14h-4z",
  settings: "M4 7h10M18 7h2M4 17h2M10 17h10M14 4v6M6 14v6",
  admin: "M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6l8-4z",
}
const money = n => "$" + Number(n || 0).toLocaleString(net.lang === "en" ? "en-US" : "fr-FR")
// États possibles : "" (rien saisi), "bad" (format invalide), "wait" (vérification en cours),
// "error" (le serveur n'a pas pu être contacté pour vérifier — PAS un problème de format), "free", "taken".
// Pour "bad", on réaffiche le texte saisi tel que le code l'a reçu : si quelqu'un voit "« Rayan » : 3 à 20…"
// alors que "Rayan" est clairement valide, c'est la preuve que le mod installé n'est pas cette version.
function hintFor(state, raw) {
  if (state === "free") return t("free")
  if (state === "taken") return t("taken")
  if (state === "wait") return t("checking")
  if (state === "error") return t("checkerr") + (net.lastNetworkDetail ? ` (${net.lastNetworkDetail})` : "")
  if (state === "bad" && raw) return `« ${raw} » : ${t("badname")}`
  return t("badname")
}
const nameHint = computed(() => hintFor(nameState.value, f.username.trim()))
const pseudoHint = computed(() => hintFor(pseudoState.value, f.pseudo.trim()))
const newPseudoHint = computed(() => hintFor(newPseudoState.value, f.newPseudo.trim()))
function hintClass(state) {
  if (state === "free") return "good"
  if (state === "wait") return "mut"
  if (state === "error") return "warn"
  return "bad"
}
const filteredServers = computed(() => {
  const q = (f.srvSearch || "").trim().toLowerCase()
  if (!q) return d.servers
  return d.servers.filter(s => (s.name || "").toLowerCase().includes(q))
})

// pendant la saisie dans un champ texte, les touches ne doivent pas piloter la voiture
function focus(e, on) { const tg = e.target?.tagName; if (tg === "INPUT" || tg === "SELECT" || tg === "TEXTAREA") ui("typing", { on }) }

let nameTimer = null
function checkName() {
  clearTimeout(nameTimer)
  const n = f.username.trim()
  if (!n) { nameState.value = ""; return }
  if (!/^[A-Za-z0-9_]{3,20}$/.test(n)) { nameState.value = "bad"; return }
  nameState.value = "wait"
  nameTimer = setTimeout(async () => { const ok = await usernameAvailable(n); if (n === f.username.trim()) nameState.value = ok === null ? "error" : ok ? "free" : "taken" }, 350)
}

let pseudoTimer = null
function checkPseudo() {
  clearTimeout(pseudoTimer)
  const n = f.pseudo.trim()
  if (!n) { pseudoState.value = ""; return }
  if (!/^[A-Za-z0-9_]{3,20}$/.test(n)) { pseudoState.value = "bad"; return }
  pseudoState.value = "wait"
  pseudoTimer = setTimeout(async () => { const ok = await usernameAvailable(n); if (n === f.pseudo.trim()) pseudoState.value = ok === null ? "error" : ok ? "free" : "taken" }, 350)
}

let newPseudoTimer = null
function checkNewPseudo() {
  clearTimeout(newPseudoTimer)
  const n = f.newPseudo.trim()
  if (!n) { newPseudoState.value = ""; return }
  if (!/^[A-Za-z0-9_]{3,20}$/.test(n)) { newPseudoState.value = "bad"; return }
  newPseudoState.value = "wait"
  newPseudoTimer = setTimeout(async () => { const ok = await usernameAvailable(n); if (n === f.newPseudo.trim()) newPseudoState.value = ok === null ? "error" : ok ? "free" : "taken" }, 350)
}

async function wrap(fn) { busy.value = true; try { await fn() } finally { busy.value = false } }
const net_signOut = () => signOut()
const net_createProfile = () => wrap(() => signUpAnonymous(f.pseudo))
const net_changePseudo = () => wrap(async () => { if (await changeUsername(f.newPseudo)) { f.newPseudo = ""; newPseudoState.value = ""; msg.value = t("ok") } })

function exportProfile() { netExportProfile() }
function importProfile(path) { netImportProfile(path) }
async function switchProfile() { showCreate.value = false; await signOut(); await requestProfiles() }

// Action quelconque : message d'erreur lisible, puis rafraîchissement du profil / de la liste.
async function act(fn, after) {
  net.error = ""; msg.value = ""
  try { await fn(); msg.value = t("ok"); await refreshMe(); if (after) await after() } catch (e) { net.error = errText(e) }
}
const safe = async (fn) => { try { await fn() } catch (e) { net.error = errText(e) } }
const loadTx = () => safe(async () => { d.tx = await rpc("get_my_transactions", { p_limit: 30 }) })
const loadServers = () => safe(async () => { d.servers = await listServers() })

async function join(id) {
  const r = await joinServer(id)
  if (r === "pseudo") { needPseudo.value = true; f.username = ""; nameState.value = "" }
  await loadServers()
}
async function leave() { await leaveServer(); await loadServers() }
async function pickName() { if (await chooseUsername(f.username)) { needPseudo.value = false; msg.value = t("ok") } }

// À la première ouverture : un onglet de départ raisonnable (langue pas encore choisie -> Réglages ; pas
// connecté -> Compte), sans gêner ensuite les clics de l'utilisateur sur les autres onglets.
let autoTabDone = false
watch(() => net.open, open => {
  if (!open || autoTabDone) return
  autoTabDone = true
  if (!net.langChosen) tab.value = "settings"
  else if (!logged.value) tab.value = "account"
  if (!logged.value) requestProfiles()
})

let poll = null
function loadTab() {
  net.error = ""; msg.value = ""
  if (!logged.value) return
  const x = tab.value
  if (x === "account") loadTx(); else if (x === "servers") loadServers()
  else if (x === "board") safe(async () => { d.board = await rpc("get_leaderboard", { p_limit: 25 }) })
  if (x === "account") refreshMe().catch(() => {})
}
watch([tab, logged, () => net.open], loadTab)
onMounted(() => { poll = setInterval(() => { if (net.open && logged.value && tab.value === "servers") loadServers() }, 5000) })
onBeforeUnmount(() => clearInterval(poll))
</script>

<style lang="scss" scoped>
.onw { position: fixed; inset: 0; z-index: 2147482500; display: flex; align-items: center; justify-content: center; background: rgba(0, 0, 0, 0.45); pointer-events: auto; }
.win { --ac: #ff6600; width: 1260px; max-width: 98vw; height: 830px; max-height: 95vh; display: flex; flex-direction: column; background: rgba(10, 10, 10, 0.62); backdrop-filter: blur(6px); border: 1px solid var(--ac); border-radius: 8px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255, 102, 0, 0.15); color: #fff; font: 14px/1.35 "Overpass", "Segoe UI", sans-serif; overflow: hidden; * { box-sizing: border-box; } }
header { display: flex; align-items: center; gap: 12px; padding: 10px 16px; background: rgba(0, 0, 0, 0.3); border-bottom: 2px solid var(--ac);
  .title { font: 700 19px "Overpass", sans-serif; color: var(--ac); letter-spacing: 0.02em; } .who { flex: 1; text-align: right; color: rgba(255, 255, 255, 0.75); font-size: 13px; } }
.body { flex: 1; display: flex; min-height: 0; }
.tabs { display: flex; flex-direction: column; gap: 3px; padding: 10px; width: 190px; flex: none; border-right: 1px solid rgba(255, 102, 0, 0.3); background: rgba(0, 0, 0, 0.18); overflow-y: auto;
  button { display: flex; align-items: center; gap: 10px; background: none; border: 0; border-radius: 6px; color: rgba(255, 255, 255, 0.6); padding: 9px 10px; font: inherit; cursor: pointer; text-align: left;
    transition: background 0.15s ease, color 0.15s ease, transform 0.15s ease;
    &:hover { background: rgba(255, 102, 0, 0.16); color: #fff; transform: translateX(3px); }
    &.on { background: var(--ac); color: #fff; box-shadow: 0 2px 10px rgba(255, 102, 0, 0.4); } }
  svg { width: 17px; height: 17px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; flex: none; } }
.bar { padding: 4px 12px; font-size: 12px; background: rgba(74, 222, 128, 0.1); border-bottom: 1px solid rgba(74, 222, 128, 0.3); }
.bar.upd { background: rgba(245, 185, 66, 0.15); border-bottom: 1px solid rgba(245, 185, 66, 0.4); color: #f5b942; font-weight: 600; }
main { flex: 1; overflow-y: auto; padding: 18px 24px; }
h4 { margin: 12px 0 6px; color: var(--ac); font-size: 13px; text-transform: uppercase; letter-spacing: 0.05em; }
.row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin: 4px 0; }
.form { display: flex; flex-direction: column; gap: 6px; max-width: 420px; }
.cards { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.card { background: rgba(0, 0, 0, 0.45); border: 1px solid rgba(255, 102, 0, 0.35); border-radius: 8px; padding: 10px 12px; margin: 6px 0; box-shadow: 0 4px 14px rgba(0, 0, 0, 0.3);
  transition: border-color 0.18s ease, background 0.18s ease, transform 0.18s ease, box-shadow 0.18s ease;
  &:hover { border-color: var(--ac); background: rgba(255, 102, 0, 0.08); transform: translateY(-2px); box-shadow: 0 8px 22px rgba(0, 0, 0, 0.4); }
  &.me { border-color: #4ade80; } label { color: rgba(255, 255, 255, 0.6); font-size: 11px; text-transform: uppercase; } }
.big { font-size: 28px; font-weight: 800; color: var(--ac); &.sm { font-size: 16px; } }
.cnt { margin-left: auto; font-weight: 700; color: var(--ac); }
.tb { width: 100%; border-collapse: collapse; td { padding: 2px 8px; border-bottom: 1px solid rgba(255, 255, 255, 0.08); } tr.me td { color: #4ade80; } }
.tag { padding: 0 6px; font-size: 11px; border: 1px solid var(--ac); border-radius: 8px; }
input, select { padding: 5px 8px; color: #fff; background: rgba(0, 0, 0, 0.6); border: 1px solid rgba(255, 102, 0, 0.5); border-radius: 4px; font: inherit; &.sm { width: 90px; } }
.btn, .hb { padding: 7px 16px; color: #fff; font: 600 13px "Overpass", sans-serif; cursor: pointer; background: rgba(255, 102, 0, 0.22); border: 1px solid var(--ac); border-radius: 6px;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.35); transition: background 0.18s ease, transform 0.18s ease, box-shadow 0.18s ease;
  &:hover:not(:disabled) { background: var(--ac); transform: translateY(-1px); box-shadow: 0 6px 16px rgba(255, 102, 0, 0.4); }
  &:active:not(:disabled) { transform: translateY(0); box-shadow: 0 2px 6px rgba(0, 0, 0, 0.35); }
  &:disabled { opacity: 0.4; cursor: default; } &.dim { background: rgba(255, 255, 255, 0.06); &:hover:not(:disabled) { background: rgba(255, 255, 255, 0.12); box-shadow: 0 6px 16px rgba(0, 0, 0, 0.4); } } }
.hb { margin-left: auto; }
.lnk { color: rgba(255, 255, 255, 0.7); background: none; border: none; text-decoration: underline; cursor: pointer; }
.err { color: #ff6b6b; margin: 0 0 6px; } .ok, .good { color: #4ade80; } .bad { color: #ff6b6b; } .warn { color: #f5b942; } .mut { color: rgba(255, 255, 255, 0.6); }
small { font-size: 12px; }
.embed-panel { margin: -10px -14px; padding: 0; :deep(.grnfr) { width: 100%; height: 440px; max-width: none; } }
.embed-panel .recent { margin: 10px 14px; padding: 8px 10px; background: rgba(0, 0, 0, 0.35); border: 1px solid rgba(255, 102, 0, 0.3); border-radius: 6px; }
</style>
