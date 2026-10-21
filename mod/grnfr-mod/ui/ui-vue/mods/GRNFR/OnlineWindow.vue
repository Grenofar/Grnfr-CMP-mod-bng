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
              <h4>{{ t('quick_create') }}</h4>
              <input v-model="f.pseudo" type="text" maxlength="20" :placeholder="t('username')" autocomplete="off" @input="checkPseudo" />
              <small :class="hintClass(pseudoState)">{{ pseudoHint }}</small>
              <button type="button" class="btn" :disabled="busy || pseudoState !== 'free'" @click="net_createProfile">{{ t('create_profile') }}</button>

              <div class="row">
                <button type="button" class="lnk" @click="toggleImport">{{ t('import_profile') }}</button>
              </div>
              <template v-if="showImport">
                <p v-if="!net.profiles.length" class="mut">{{ t('no_profiles_found') }}</p>
                <div v-for="p in net.profiles" :key="p.path" class="row">
                  <span>{{ p.username }}</span>
                  <button type="button" class="btn dim" @click="importProfile(p.path)">{{ t('use_this') }}</button>
                </div>
              </template>

              <button type="button" class="lnk" @click="showEmail = !showEmail">{{ t('have_email_account') }}</button>
              <template v-if="showEmail">
                <input v-model="f.email" type="email" :placeholder="t('email')" autocomplete="off" />
                <input v-model="f.password" type="password" :placeholder="t('password')" autocomplete="off" />
                <template v-if="reg">
                  <input v-model="f.username" type="text" maxlength="20" :placeholder="t('username')" autocomplete="off" @input="checkName" />
                  <small :class="hintClass(nameState)">{{ nameHint }}</small>
                </template>
                <div class="row">
                  <button v-if="!reg" type="button" class="btn" :disabled="busy" @click="net_signIn">{{ t('signin') }}</button>
                  <button v-else type="button" class="btn" :disabled="busy || nameState !== 'free'" @click="net_signUp">{{ t('signup') }}</button>
                  <button type="button" class="lnk" @click="reg = !reg; net.error = ''; net.info = ''">{{ reg ? t('have_account') : t('no_account') }}</button>
                </div>
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
            <h4>{{ t('send_money') }}</h4>
            <div class="row">
              <input v-model="f.to" :placeholder="t('adm_user')" /><input v-model.number="f.amount" type="number" min="1" :placeholder="t('amount')" />
              <button type="button" class="btn" @click="act(() => rpc('send_money', { p_username: f.to, p_amount: f.amount }), loadTx)">{{ t('send') }}</button>
            </div>
            <h4>{{ t('history') }}</h4>
            <table class="tb"><tr v-for="x in d.tx" :key="x.id"><td>{{ x.created_at.slice(0, 16).replace('T', ' ') }}</td><td>{{ x.ref || x.kind }}</td><td :class="x.amount < 0 ? 'bad' : 'good'">{{ x.amount > 0 ? '+' : '' }}{{ x.amount }}</td></tr></table>
            <button type="button" class="btn dim" @click="net_signOut">{{ t('signout') }}</button>
          </template>
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

        <!-- GARAGE : la tablette ne s'ouvre qu'à proximité de VOTRE point de garage (un par carte) -->
        <section v-else-if="tab === 'garage'">
          <p v-if="!garageNear" class="warn">{{ t('garage_far') }}{{ garageDist !== null ? ' (' + garageDist + ' m)' : '' }}</p>
          <template v-else>
          <p class="mut">{{ (me.vehicles || []).length }}/{{ profile.garage_slots }}</p>
          <p v-if="!(me.vehicles || []).length" class="mut">{{ t('garage_empty') }}</p>
          <div v-for="v in me.vehicles" :key="v.id" class="card">
            <div class="row"><b>{{ v.nickname || v.model_key }}</b><span class="mut">{{ t('slot') }} {{ v.slot + 1 }} · {{ v.model_key }} · {{ money(v.value) }}</span>
              <span v-if="v.listed" class="tag">{{ t('listed') }}</span><span v-if="net.game.spawned && net.game.spawned[v.id]" class="tag">{{ t('out_now') }}</span></div>
            <div class="row">
              <button v-if="!(net.game.spawned && net.game.spawned[v.id])" type="button" class="btn" @click="ui('garage.spawn', { id: v.id, model_key: v.model_key, config_key: v.config_key, nickname: v.nickname })">{{ t('out') }}</button>
              <button v-else type="button" class="btn" @click="ui('garage.store', { id: v.id })">{{ t('store') }}</button>
              <template v-if="!v.listed">
                <button type="button" class="btn dim" @click="act(async () => { await ui('garage.store', { id: v.id }); await rpc('sell_vehicle_to_dealer', { p_vehicle_id: v.id }) })">{{ t('sell_dealer') }}</button>
                <input v-model.number="f['p' + v.id]" type="number" min="1" :placeholder="t('price')" class="sm" />
                <button type="button" class="btn dim" @click="act(() => rpc('create_listing', { p_vehicle_id: v.id, p_price: f['p' + v.id], p_description: null }))">{{ t('list_it') }}</button>
              </template>
            </div>
          </div>
          </template>
        </section>

        <!-- CONCESSION -->
        <section v-else-if="tab === 'dealer'">
          <div v-for="c in d.catalog" :key="c.id" class="card row">
            <b>{{ c.name }}</b><span class="mut">{{ money(c.price) }}</span>
            <button type="button" class="btn" @click="act(() => rpc('buy_vehicle', { p_catalog_id: c.id }))">{{ t('buy') }}</button>
          </div>
        </section>

        <!-- ANNONCES -->
        <section v-else-if="tab === 'market'">
          <p v-if="!d.market.length" class="mut">{{ t('none') }}</p>
          <div v-for="l in d.market" :key="l.id" class="card">
            <div class="row"><b>{{ l.nickname || l.model_key }}</b><span class="mut">{{ l.model_key }} · {{ t('sold_by') }} {{ l.seller }}</span><span class="big sm">{{ money(l.price) }}</span></div>
            <div v-if="l.description" class="mut">{{ l.description }}</div>
            <button v-if="l.seller === net.username" type="button" class="btn dim" @click="act(() => rpc('cancel_listing', { p_listing_id: l.id }), loadMarket)">{{ t('cancel_listing') }} {{ t('mine') }}</button>
            <button v-else type="button" class="btn" @click="act(() => rpc('buy_listing', { p_listing_id: l.id }), loadMarket)">{{ t('buy') }}</button>
          </div>
        </section>

        <!-- ÉCHANGES -->
        <section v-else-if="tab === 'trades'">
          <div class="form">
            <div class="row"><input v-model="f.tradeUser" :placeholder="t('trade_with')" /><button type="button" class="btn dim" @click="loadTheirs">{{ t('trade_load') }}</button></div>
            <select v-model="f.offer"><option value="">{{ t('trade_offer') }} {{ t('nothing') }}</option><option v-for="v in me.vehicles" :key="v.id" :value="v.id">{{ v.nickname || v.model_key }}</option></select>
            <select v-model="f.want"><option value="">{{ t('trade_want') }} {{ t('nothing') }}</option><option v-for="v in d.theirs" :key="v.id" :value="v.id">{{ v.nickname || v.model_key }} ({{ money(v.value) }})</option></select>
            <input v-model.number="f.cash" type="number" :placeholder="t('trade_cash')" />
            <button type="button" class="btn" @click="act(() => rpc('propose_trade', { p_username: f.tradeUser, p_offered: f.offer || null, p_wanted: f.want || null, p_cash: f.cash || 0 }), loadTrades)">{{ t('trade_send') }}</button>
          </div>
          <div v-for="x in d.trades" :key="x.id" class="card">
            <div><b>{{ x.direction === 'in' ? x.proposer : x.target }}</b> <span class="mut">({{ x.direction === 'in' ? t('trade_in') : t('trade_out') }})</span></div>
            <div class="mut">{{ x.offered ? (x.offered.nickname || x.offered.model_key) : t('nothing') }} ⇄ {{ x.wanted ? (x.wanted.nickname || x.wanted.model_key) : t('nothing') }} · {{ money(x.cash_from_proposer) }}</div>
            <div class="row">
              <template v-if="x.direction === 'in'">
                <button type="button" class="btn" @click="act(() => rpc('respond_trade', { p_trade_id: x.id, p_accept: true, p_slot: null }), loadTrades)">{{ t('accept') }}</button>
                <button type="button" class="btn dim" @click="act(() => rpc('respond_trade', { p_trade_id: x.id, p_accept: false, p_slot: null }), loadTrades)">{{ t('refuse') }}</button>
              </template>
              <button v-else type="button" class="btn dim" @click="act(() => rpc('cancel_trade', { p_trade_id: x.id }), loadTrades)">{{ t('cancel') }}</button>
            </div>
          </div>
        </section>

        <!-- CLASSEMENT -->
        <section v-else-if="tab === 'board'">
          <p class="mut">{{ t('lb_wealth') }}</p>
          <table class="tb"><tr v-for="(r, i) in d.board" :key="r.username" :class="{ me: r.username === net.username }"><td>{{ i + 1 }}</td><td>{{ r.username }}</td><td>{{ money(r.wealth) }}</td></tr></table>
        </section>

        <!-- TAXI -->
        <section v-else-if="tab === 'taxi'">
          <div class="row"><b>{{ t('taxi_duty') }}</b><span :class="taxi.duty ? 'good' : 'mut'">{{ taxi.duty ? t('taxi_on') : t('taxi_off') }}</span>
            <button type="button" class="btn" @click="ui('taxi.duty', { on: !taxi.duty })">{{ taxi.duty ? t('taxi_off') : t('taxi_on') }}</button></div>
          <div v-if="taxi.duty" class="mut">{{ taxi.rides || 0 }} {{ t('rides') }} · {{ money(taxi.earned || 0) }} {{ t('earned') }}<template v-if="taxi.phase"> · {{ taxi.phase }}</template></div>
          <button v-if="taxi.duty" type="button" class="btn dim" @click="ui('taxi.cancel')">{{ t('taxi_cancel') }}</button>
          <h4>{{ t('taxi_open') }}</h4>
          <button type="button" class="btn dim" @click="loadReqs">{{ t('refresh') }}</button>
          <div v-for="r in d.reqs" :key="r.id" class="card row"><b>{{ r.passenger }}</b><span class="mut">{{ Math.round(r.route_m / 100) / 10 }} km</span><span>{{ money(r.fare) }}</span>
            <button type="button" class="btn" @click="ui('taxi.accept', r)">{{ t('take') }}</button></div>
          <h4>{{ t('taxi_dest') }}</h4>
          <select v-model="f.place" @focus="ui('places.refresh')"><option v-for="(p, i) in net.places" :key="i" :value="i">{{ p.name }} ({{ Math.round(p.d || 0) }} m)</option></select>
          <div class="row">
            <button type="button" class="btn" :disabled="!place" @click="ui('bot.call', place)">{{ t('taxi_call') }}</button>
            <button type="button" class="btn dim" :disabled="!place || !net.game.pos" @click="askTaxi">{{ t('taxi_ask') }}</button>
          </div>
          <div v-if="net.game.bot && net.game.bot.phase !== 'idle'" class="card">{{ t('taxi_bot') }} : {{ net.game.bot.phase }}<button type="button" class="btn dim" @click="ui('bot.cancel')">{{ t('cancel') }}</button></div>
          <div v-if="me.taxi" class="card">{{ t('taxi_state') }} : {{ me.taxi.status }} · {{ me.taxi.role }} · {{ money(me.taxi.fare) }}
            <button v-if="me.taxi.role === 'passenger'" type="button" class="btn dim" @click="act(() => rpc('cancel_taxi_request', { p_id: me.taxi.id }))">{{ t('taxi_cancel') }}</button></div>
        </section>

        <!-- BUS -->
        <section v-else-if="tab === 'bus'">
          <div class="row">
            <button v-if="!(net.game.bus && net.game.bus.active)" type="button" class="btn" @click="ui('bus.start')">{{ t('bus_start') }}</button>
            <button v-else type="button" class="btn dim" @click="ui('bus.stop')">{{ t('bus_stop') }}</button>
          </div>
          <div v-if="net.game.bus && net.game.bus.active" class="mut">{{ t('bus_state') }} · {{ net.game.bus.legs || 0 }} {{ t('legs') }} · {{ money(net.game.bus.earned || 0) }} {{ t('earned') }}</div>
        </section>

        <!-- RÉGLAGES (HUD, compteur FPS, langue, mods) : le même panneau que le menu principal, réutilisé ici
             pour qu'il n'y ait plus qu'une seule fenêtre GRNFR CMP au lieu de deux. -->
        <section v-else-if="tab === 'settings'" class="embed-panel">
          <GrnfrPanel />
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
  net, ui, rpc, errText, signIn, signUp, signUpAnonymous, signOut, refreshMe, usernameAvailable, chooseUsername, changeUsername,
  listServers, joinServer, leaveServer, exportProfile as netExportProfile, requestProfiles, importProfile as netImportProfile,
} from "./net.js"
import { tr } from "./onlineI18n.js"
import GrnfrPanel from "./GrnfrPanel.vue"

const t = k => tr(net.lang, k)
const tab = ref("account")
const reg = ref(false), busy = ref(false), msg = ref(""), needPseudo = ref(false)
const showEmail = ref(false), showImport = ref(false)
const pseudoState = ref(""), newPseudoState = ref("")
const nameState = ref(""), f = reactive({ email: "", password: "", username: "", pseudo: "", newPseudo: "", srvSearch: "", place: 0, offer: "", want: "", cash: 0 })
const d = reactive({ tx: [], servers: [], catalog: [], market: [], trades: [], theirs: [], board: [], reqs: [] })

const logged = computed(() => net.status === "in")
const me = computed(() => net.me || {})
const profile = computed(() => net.me?.profile || {})
const taxi = computed(() => net.game.taxi || {})
const garageNear = computed(() => !!net.game.garage?.near)
const garageDist = computed(() => (typeof net.game.garage?.dist === "number" ? net.game.garage.dist : null))
const place = computed(() => net.places[f.place] || null)
const tabs = computed(() => ["account", "servers", "garage", "dealer", "market", "trades", "board", "taxi", "bus", "settings"].concat(profile.value.is_admin ? ["admin"] : []))
const icons = {
  account: "M12 8a4 4 0 100-8 4 4 0 000 8zM4 20c0-4 4-6 8-6s8 2 8 6",
  servers: "M4 4h16v4H4zM4 10h16v4H4zM4 16h16v4H4z",
  garage: "M3 11l9-7 9 7M5 10v10h14V10",
  dealer: "M6 7h12l-1 13H7L6 7zM9 7V5a3 3 0 016 0v2",
  market: "M4 4h10l6 6-10 10-6-6V4zM8.5 8.5h.01",
  trades: "M4 7h13M13 3l4 4-4 4M20 17H7M11 21l-4-4 4-4",
  board: "M4 14h4v6H4zM10 10h4v10h-4zM16 6h4v14h-4z",
  taxi: "M5 11l1.5-4.5A2 2 0 018.4 5h7.2a2 2 0 011.9 1.5L19 11M4 11h16v6H4z",
  bus: "M4 5h16v12H4zM4 17v2M20 17v2",
  settings: "M4 7h10M18 7h2M4 17h2M10 17h10M14 4v6M6 14v6",
  admin: "M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6l8-4z",
}
const money = n => "$" + Number(n || 0).toLocaleString(net.lang === "en" ? "en-US" : "fr-FR")
// États possibles : "" (rien saisi), "bad" (format invalide), "wait" (vérification en cours),
// "error" (le serveur n'a pas pu être contacté pour vérifier — PAS un problème de format), "free", "taken".
function hintFor(state) {
  if (state === "free") return t("free")
  if (state === "taken") return t("taken")
  if (state === "wait") return t("checking")
  if (state === "error") return t("checkerr")
  return t("badname")
}
const nameHint = computed(() => hintFor(nameState.value))
const pseudoHint = computed(() => hintFor(pseudoState.value))
const newPseudoHint = computed(() => hintFor(newPseudoState.value))
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
const net_signIn = () => wrap(() => signIn(f.email, f.password))
const net_signUp = () => wrap(() => signUp(f.email, f.password, f.username))
const net_signOut = () => signOut()
const net_createProfile = () => wrap(() => signUpAnonymous(f.pseudo))
const net_changePseudo = () => wrap(async () => { if (await changeUsername(f.newPseudo)) { f.newPseudo = ""; newPseudoState.value = ""; msg.value = t("ok") } })

function exportProfile() { netExportProfile() }
function toggleImport() { showImport.value = !showImport.value; if (showImport.value) requestProfiles() }
function importProfile(path) { netImportProfile(path) }
async function switchProfile() { await signOut(); showImport.value = true; await requestProfiles() }

// Action quelconque : message d'erreur lisible, puis rafraîchissement du profil / de la liste.
async function act(fn, after) {
  net.error = ""; msg.value = ""
  try { await fn(); msg.value = t("ok"); await refreshMe(); if (after) await after() } catch (e) { net.error = errText(e) }
}
const safe = async (fn) => { try { await fn() } catch (e) { net.error = errText(e) } }
const loadTx = () => safe(async () => { d.tx = await rpc("get_my_transactions", { p_limit: 30 }) })
const loadServers = () => safe(async () => { d.servers = await listServers() })
const loadMarket = () => safe(async () => { d.market = await rpc("get_market", { p_limit: 50, p_offset: 0 }) })
const loadTrades = () => safe(async () => { d.trades = await rpc("get_trades") })
const loadReqs = () => safe(async () => { d.reqs = await rpc("get_open_taxi_requests", { p_level: net.game.level || null }) })
const loadTheirs = () => safe(async () => { d.theirs = await rpc("get_player_garage", { p_username: f.tradeUser || "" }) })

async function join(id) {
  const r = await joinServer(id)
  if (r === "pseudo") { needPseudo.value = true; f.username = ""; nameState.value = "" }
  await loadServers()
}
async function leave() { await leaveServer(); await loadServers() }
async function pickName() { if (await chooseUsername(f.username)) { needPseudo.value = false; msg.value = t("ok") } }
async function askTaxi() {
  const p = place.value
  await act(() => rpc("request_taxi", { p_level: net.game.level || null, p_pickup: net.game.pos, p_dropoff: { x: p.x, y: p.y, z: p.z, name: p.name }, p_distance_m: null }))
}

// À la première ouverture : un onglet de départ raisonnable (langue pas encore choisie -> Réglages ; pas
// connecté -> Compte), sans gêner ensuite les clics de l'utilisateur sur les autres onglets.
let autoTabDone = false
watch(() => net.open, open => {
  if (!open || autoTabDone) return
  autoTabDone = true
  if (!net.langChosen) tab.value = "settings"
  else if (!logged.value) tab.value = "account"
})

let poll = null
function loadTab() {
  net.error = ""; msg.value = ""
  if (!logged.value) return
  const x = tab.value
  if (x === "account") loadTx(); else if (x === "servers") loadServers()
  else if (x === "dealer") safe(async () => { d.catalog = await rpc("get_catalog") })
  else if (x === "market") loadMarket(); else if (x === "trades") loadTrades()
  else if (x === "board") safe(async () => { d.board = await rpc("get_leaderboard", { p_limit: 25 }) })
  else if (x === "taxi") { ui("places.refresh"); loadReqs() }
  if (x === "garage" || x === "trades" || x === "account") refreshMe().catch(() => {})
}
watch([tab, logged, () => net.open], loadTab)
onMounted(() => { poll = setInterval(() => { if (net.open && logged.value && tab.value === "servers") loadServers() }, 5000) })
onBeforeUnmount(() => clearInterval(poll))
</script>

<style lang="scss" scoped>
.onw { position: fixed; inset: 0; z-index: 2147482500; display: flex; align-items: center; justify-content: center; background: rgba(0, 0, 0, 0.45); pointer-events: auto; }
.win { --ac: #ff6600; width: 1180px; max-width: 97vw; height: 780px; max-height: 94vh; display: flex; flex-direction: column; background: rgba(10, 10, 10, 0.62); backdrop-filter: blur(6px); border: 1px solid var(--ac); border-radius: 8px;
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
</style>
