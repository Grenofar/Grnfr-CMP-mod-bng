<template>
  <!-- Fenêtre GRNFR Online (touche O). Monté dans <body> par index.js, comme le HUD. -->
  <div v-if="net.open" class="onw" @focusin="focus($event, true)" @focusout="focus($event, false)">
    <div class="win">
      <header>
        <span class="title">{{ t('title') }}</span>
        <span v-if="logged" class="who">{{ net.username }} · {{ money(profile.balance) }}</span>
        <button type="button" class="hb" @click="ui('window.close')">✕ {{ t('close') }}</button>
      </header>
      <nav>
        <button v-for="x in tabs" :key="x" type="button" :class="{ on: tab === x }" @click="tab = x">{{ t('t_' + x) }}</button>
      </nav>
      <div v-if="logged && net.server" class="bar">
        🟢 {{ net.server.name }} — {{ net.players.length + 1 }}/{{ net.server.max_players }} :
        <b>{{ net.username }}</b><span v-for="p in net.players" :key="p.username">, {{ p.username }}</span>
        <span v-if="net.syncErr" class="warn"> · {{ t('srv_sync_bad') }}{{ net.syncErr }}</span>
      </div>
      <main>
        <p v-if="net.error" class="err">{{ net.error }}</p>
        <p v-if="net.info || msg" class="ok">{{ net.info || msg }}</p>

        <!-- COMPTE -->
        <section v-if="tab === 'account'">
          <p v-if="!net.configured" class="err">{{ t('conf_server') }}</p>
          <template v-else-if="!logged">
            <div class="form">
              <input v-model="f.email" type="email" :placeholder="t('email')" autocomplete="off" />
              <input v-model="f.password" type="password" :placeholder="t('password')" autocomplete="off" />
              <template v-if="reg">
                <input v-model="f.username" type="text" maxlength="20" :placeholder="t('username')" autocomplete="off" @input="checkName" />
                <small :class="nameState === 'free' ? 'good' : 'bad'">{{ nameHint }}</small>
              </template>
              <div class="row">
                <button v-if="!reg" type="button" class="btn" :disabled="busy" @click="net_signIn">{{ t('signin') }}</button>
                <button v-else type="button" class="btn" :disabled="busy || nameState !== 'free'" @click="net_signUp">{{ t('signup') }}</button>
                <button type="button" class="lnk" @click="reg = !reg; net.error = ''; net.info = ''">{{ reg ? t('have_account') : t('no_account') }}</button>
              </div>
            </div>
          </template>
          <template v-else>
            <div class="cards">
              <div class="card"><label>{{ t('balance') }}</label><div class="big">{{ money(profile.balance) }}</div></div>
              <div class="card"><label>{{ t('username') }}</label><div class="big sm">{{ net.username }}</div></div>
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
            <small :class="nameState === 'free' ? 'good' : 'bad'">{{ nameHint }}</small>
            <button type="button" class="btn" :disabled="nameState !== 'free'" @click="pickName">{{ t('choose') }}</button>
          </div>
          <div v-for="s in d.servers" :key="s.id" class="card srv" :class="{ me: net.server && net.server.id === s.id }">
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

        <!-- GARAGE -->
        <section v-else-if="tab === 'garage'">
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
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted, onBeforeUnmount } from "vue"
import { net, ui, rpc, errText, signIn, signUp, signOut, refreshMe, usernameAvailable, chooseUsername, listServers, joinServer, leaveServer } from "./net.js"
import { tr } from "./onlineI18n.js"

const t = k => tr(net.lang, k)
const tab = ref("account")
const reg = ref(false), busy = ref(false), msg = ref(""), needPseudo = ref(false)
const nameState = ref(""), f = reactive({ email: "", password: "", username: "", place: 0, offer: "", want: "", cash: 0 })
const d = reactive({ tx: [], servers: [], catalog: [], market: [], trades: [], theirs: [], board: [], reqs: [] })

const logged = computed(() => net.status === "in")
const me = computed(() => net.me || {})
const profile = computed(() => net.me?.profile || {})
const taxi = computed(() => net.game.taxi || {})
const place = computed(() => net.places[f.place] || null)
const tabs = computed(() => ["account", "servers", "garage", "dealer", "market", "trades", "board", "taxi", "bus"].concat(profile.value.is_admin ? ["admin"] : []))
const money = n => "$" + Number(n || 0).toLocaleString(net.lang === "en" ? "en-US" : "fr-FR")
const nameHint = computed(() => nameState.value === "free" ? t("free") : nameState.value === "taken" ? t("taken") : nameState.value === "bad" ? t("badname") : nameState.value === "wait" ? t("checking") : t("badname"))

// pendant la saisie dans un champ texte, les touches ne doivent pas piloter la voiture
function focus(e, on) { const tg = e.target?.tagName; if (tg === "INPUT" || tg === "SELECT" || tg === "TEXTAREA") ui("typing", { on }) }

let nameTimer = null
function checkName() {
  clearTimeout(nameTimer)
  const n = f.username
  if (!/^[A-Za-z0-9_]{3,20}$/.test(n)) { nameState.value = "bad"; return }
  nameState.value = "wait"
  nameTimer = setTimeout(async () => { const ok = await usernameAvailable(n); if (n === f.username) nameState.value = ok === null ? "" : ok ? "free" : "taken" }, 350)
}

async function wrap(fn) { busy.value = true; try { await fn() } finally { busy.value = false } }
const net_signIn = () => wrap(() => signIn(f.email, f.password))
const net_signUp = () => wrap(() => signUp(f.email, f.password, f.username))
const net_signOut = () => signOut()

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
.win { --ac: #ff6600; width: 760px; max-width: 96vw; height: 560px; max-height: 92vh; display: flex; flex-direction: column; background: rgba(10, 10, 10, 0.95); border: 1px solid var(--ac); border-radius: 6px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.7); color: #fff; font: 14px/1.35 "Overpass", "Segoe UI", sans-serif; * { box-sizing: border-box; } }
header { display: flex; align-items: center; gap: 12px; padding: 6px 12px; background: rgba(0, 0, 0, 0.5); border-bottom: 2px solid var(--ac); .title { font: 600 18px "Overpass", sans-serif; color: var(--ac); } .who { flex: 1; text-align: right; color: rgba(255, 255, 255, 0.8); } }
nav { display: flex; flex-wrap: wrap; gap: 4px; padding: 6px 10px; border-bottom: 1px solid rgba(255, 102, 0, 0.3);
  button { padding: 3px 10px; color: #fff; cursor: pointer; background: rgba(0, 0, 0, 0.5); border: 1px solid rgba(255, 102, 0, 0.4); border-radius: 4px; &.on, &:hover { background: var(--ac); } } }
.bar { padding: 4px 12px; font-size: 12px; background: rgba(74, 222, 128, 0.1); border-bottom: 1px solid rgba(74, 222, 128, 0.3); }
main { flex: 1; overflow-y: auto; padding: 10px 14px; }
h4 { margin: 12px 0 6px; color: var(--ac); font-size: 13px; text-transform: uppercase; letter-spacing: 0.05em; }
.row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin: 4px 0; }
.form { display: flex; flex-direction: column; gap: 6px; max-width: 420px; }
.cards { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.card { background: rgba(0, 0, 0, 0.45); border: 1px solid rgba(255, 102, 0, 0.35); border-radius: 4px; padding: 8px 10px; margin: 6px 0; &.me { border-color: #4ade80; } label { color: rgba(255, 255, 255, 0.6); font-size: 11px; text-transform: uppercase; } }
.big { font-size: 26px; font-weight: 700; color: var(--ac); &.sm { font-size: 16px; } }
.cnt { margin-left: auto; font-weight: 700; color: var(--ac); }
.tb { width: 100%; border-collapse: collapse; td { padding: 2px 8px; border-bottom: 1px solid rgba(255, 255, 255, 0.08); } tr.me td { color: #4ade80; } }
.tag { padding: 0 6px; font-size: 11px; border: 1px solid var(--ac); border-radius: 8px; }
input, select { padding: 5px 8px; color: #fff; background: rgba(0, 0, 0, 0.6); border: 1px solid rgba(255, 102, 0, 0.5); border-radius: 4px; font: inherit; &.sm { width: 90px; } }
.btn, .hb { padding: 4px 12px; color: #fff; font: 600 13px "Overpass", sans-serif; cursor: pointer; background: rgba(255, 102, 0, 0.25); border: 1px solid var(--ac); border-radius: 4px; &:hover:not(:disabled) { background: var(--ac); } &:disabled { opacity: 0.4; cursor: default; } &.dim { background: rgba(0, 0, 0, 0.5); } }
.hb { margin-left: auto; }
.lnk { color: rgba(255, 255, 255, 0.7); background: none; border: none; text-decoration: underline; cursor: pointer; }
.err { color: #ff6b6b; margin: 0 0 6px; } .ok, .good { color: #4ade80; } .bad { color: #ff6b6b; } .warn { color: #f5b942; } .mut { color: rgba(255, 255, 255, 0.6); }
small { font-size: 12px; }
</style>
