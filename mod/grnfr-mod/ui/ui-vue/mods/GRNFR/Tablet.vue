<template>
  <!-- Tablette du garage : s'ouvre seulement devant SON garage (touche O), jamais depuis le menu principal.
       Écran d'accueil à applications, comme une vraie tablette ; chaque application remplace l'écran. -->
  <div v-if="net.tablet.open" class="tbw" @focusin="focus($event, true)" @focusout="focus($event, false)">
    <div class="device">
      <div class="screen">
        <div class="status">
          <span class="clock">{{ clock }}</span>
          <span class="place">{{ net.tablet.name || L('Garage', 'Garage') }}</span>
          <span class="bal">{{ net.username }} · <b>{{ money(profile.balance) }}</b></span>
          <button type="button" class="x" :title="L('Fermer', 'Close')" @click="ui('tablet.close')">✕</button>
        </div>

        <div v-if="app" class="apphead">
          <button type="button" class="back" @click="go(null)">‹ {{ L('Accueil', 'Home') }}</button>
          <span class="apptitle">{{ appName(app) }}</span>
        </div>
        <p v-if="net.error" class="err">{{ net.error }}</p>
        <p v-if="msg" class="ok">{{ msg }}</p>

        <!-- ACCUEIL -->
        <div v-if="!app" class="home">
          <button v-for="a in apps" :key="a.id" type="button" class="icon" @click="go(a.id)">
            <span class="ic" :style="{ background: a.color }"><svg viewBox="0 0 24 24"><path :d="a.path" /></svg></span>
            <span class="lbl">{{ appName(a.id) }}</span>
            <span v-if="a.id === 'trades' && incoming" class="badge">{{ incoming }}</span>
          </button>
        </div>

        <!-- GARAGE -->
        <main v-else-if="app === 'garage'">
          <p class="mut">{{ L('Places utilisées', 'Slots used') }} : {{ vehicles.length }}/{{ profile.garage_slots || 0 }}</p>
          <p v-if="!vehicles.length" class="empty">{{ L('Aucun véhicule. Passez par la Concession.', 'No vehicle. Visit the Dealership.') }}</p>
          <div class="grid">
            <div v-for="v in vehicles" :key="v.id" class="tile">
              <div class="tname">{{ v.nickname || v.model_key }}</div>
              <div class="mut">{{ v.model_key }}<template v-if="v.config_key"> · {{ v.config_key }}</template></div>
              <div class="price">{{ money(v.value) }}</div>
              <div class="tags"><span v-if="v.listed" class="tag">{{ L('En vente', 'Listed') }}</span><span v-if="out(v)" class="tag on">{{ L('Sorti', 'Out') }}</span></div>
              <div class="acts">
                <button v-if="!out(v)" type="button" class="btn" @click="ui('garage.spawn', { id: v.id, model_key: v.model_key, config_key: v.config_key, nickname: v.nickname })">{{ L('Sortir', 'Take out') }}</button>
                <button v-else type="button" class="btn" @click="ui('garage.store', { id: v.id })">{{ L('Ranger', 'Store') }}</button>
                <template v-if="!v.listed">
                  <button type="button" class="btn dim" @click="sellDealer(v)">{{ L('Vendre au concessionnaire', 'Sell to dealer') }}</button>
                  <div class="inline"><input v-model.number="f['p' + v.id]" type="number" min="1" :placeholder="L('Prix', 'Price')" />
                    <button type="button" class="btn dim" @click="act(() => rpc('create_listing', { p_vehicle_id: v.id, p_price: f['p' + v.id], p_description: null }))">{{ L('Mettre en vente', 'List') }}</button></div>
                </template>
              </div>
            </div>
          </div>
        </main>

        <!-- JOUEURS : on choisit un joueur du serveur dans la liste, puis l'action -->
        <main v-else-if="app === 'players'" class="split">
          <aside class="plist">
            <p v-if="!net.players.length" class="empty">{{ L('Personne d\'autre sur le serveur.', 'Nobody else on the server.') }}</p>
            <button v-for="p in net.players" :key="p.username" type="button" class="pl" :class="{ on: sel === p.username }" @click="pick(p.username)">
              <span class="av">{{ p.username.slice(0, 1).toUpperCase() }}</span>
              <span><b>{{ p.username }}</b><br /><small class="mut">{{ p.level === net.game.level ? L('Sur votre carte', 'On your map') : L('Autre carte', 'Other map') }}<template v-if="p.veh"> · {{ p.veh.model }}</template></small></span>
            </button>
          </aside>
          <section v-if="sel" class="pact">
            <h3>{{ sel }}</h3>
            <div class="seg">
              <button v-for="m in ['money', 'car', 'trade']" :key="m" type="button" :class="{ on: mode === m }" @click="mode = m">{{ modeName(m) }}</button>
            </div>
            <div v-if="mode === 'money'" class="panel">
              <label>{{ L('Montant', 'Amount') }}</label>
              <div class="chips"><button v-for="a in [100, 500, 1000, 5000, 10000]" :key="a" type="button" class="chip" @click="f.amount = a">{{ money(a) }}</button></div>
              <input v-model.number="f.amount" type="number" min="1" />
              <button type="button" class="btn" :disabled="!(f.amount > 0)" @click="act(() => rpc('send_money', { p_username: sel, p_amount: f.amount }), () => { f.amount = 0 })">{{ L('Envoyer', 'Send') }} {{ money(f.amount) }}</button>
            </div>
            <div v-else-if="mode === 'car'" class="panel">
              <label>{{ L('Véhicule à donner (il devra accepter)', 'Vehicle to give (they must accept)') }}</label>
              <div class="pickrow">
                <button v-for="v in giftable" :key="v.id" type="button" class="pk" :class="{ on: f.gift === v.id }" @click="f.gift = v.id">{{ v.nickname || v.model_key }}<small>{{ money(v.value) }}</small></button>
              </div>
              <p v-if="!giftable.length" class="mut">{{ L('Aucun véhicule disponible (rangé et pas en vente).', 'No vehicle available (stored and not listed).') }}</p>
              <button type="button" class="btn" :disabled="!f.gift" @click="act(() => rpc('propose_trade', { p_username: sel, p_offered: f.gift, p_wanted: null, p_cash: 0 }), () => { f.gift = '' })">{{ L('Donner', 'Give') }}</button>
            </div>
            <div v-else class="panel">
              <label>{{ L('Je donne', 'I give') }}</label>
              <div class="pickrow">
                <button type="button" class="pk" :class="{ on: !f.offer }" @click="f.offer = ''">{{ L('Rien', 'Nothing') }}</button>
                <button v-for="v in giftable" :key="v.id" type="button" class="pk" :class="{ on: f.offer === v.id }" @click="f.offer = v.id">{{ v.nickname || v.model_key }}<small>{{ money(v.value) }}</small></button>
              </div>
              <label>{{ L('Je veux', 'I want') }}</label>
              <p v-if="theirsLoading" class="mut">…</p>
              <div v-else class="pickrow">
                <button type="button" class="pk" :class="{ on: !f.want }" @click="f.want = ''">{{ L('Rien', 'Nothing') }}</button>
                <button v-for="v in theirs" :key="v.id" type="button" class="pk" :class="{ on: f.want === v.id }" @click="f.want = v.id">{{ v.nickname || v.model_key }}<small>{{ money(v.value) }}</small></button>
              </div>
              <label>{{ L('Argent en plus de ma part (négatif = il me paie)', 'Cash from me (negative = they pay me)') }}</label>
              <input v-model.number="f.cash" type="number" />
              <button type="button" class="btn" :disabled="!f.offer && !f.want" @click="act(() => rpc('propose_trade', { p_username: sel, p_offered: f.offer || null, p_wanted: f.want || null, p_cash: f.cash || 0 }), loadTrades)">{{ L('Proposer l\'échange', 'Propose trade') }}</button>
            </div>
          </section>
          <section v-else class="pact empty">{{ L('Choisissez un joueur dans la liste.', 'Pick a player from the list.') }}</section>
        </main>

        <!-- ÉCHANGES REÇUS / ENVOYÉS -->
        <main v-else-if="app === 'trades'">
          <p v-if="!d.trades.length" class="empty">{{ L('Aucune proposition en cours.', 'No pending offer.') }}</p>
          <div v-for="x in d.trades" :key="x.id" class="tile wide">
            <div class="tname">{{ x.direction === 'in' ? L('De ', 'From ') + x.proposer : L('À ', 'To ') + x.target }}</div>
            <div class="swap">
              <span>{{ x.offered ? (x.offered.nickname || x.offered.model_key) : L('rien', 'nothing') }}</span><span class="arr">⇄</span>
              <span>{{ x.wanted ? (x.wanted.nickname || x.wanted.model_key) : L('rien', 'nothing') }}</span>
              <span v-if="x.cash_from_proposer" class="mut"> · {{ money(x.cash_from_proposer) }}</span>
            </div>
            <div class="acts">
              <template v-if="x.direction === 'in'">
                <button type="button" class="btn" @click="act(() => rpc('respond_trade', { p_trade_id: x.id, p_accept: true, p_slot: null }), loadTrades)">{{ L('Accepter', 'Accept') }}</button>
                <button type="button" class="btn dim" @click="act(() => rpc('respond_trade', { p_trade_id: x.id, p_accept: false, p_slot: null }), loadTrades)">{{ L('Refuser', 'Refuse') }}</button>
              </template>
              <button v-else type="button" class="btn dim" @click="act(() => rpc('cancel_trade', { p_trade_id: x.id }), loadTrades)">{{ L('Annuler', 'Cancel') }}</button>
            </div>
          </div>
        </main>

        <!-- CONCESSION -->
        <main v-else-if="app === 'dealer'">
          <div class="grid">
            <div v-for="c in d.catalog" :key="c.id" class="tile">
              <div class="tname">{{ c.name }}</div>
              <div class="price">{{ money(c.price) }}</div>
              <div class="acts"><button type="button" class="btn" :disabled="(profile.balance || 0) < c.price" @click="act(() => rpc('buy_vehicle', { p_catalog_id: c.id }))">{{ L('Acheter', 'Buy') }}</button></div>
            </div>
          </div>
        </main>

        <!-- ANNONCES -->
        <main v-else-if="app === 'market'">
          <p v-if="!d.market.length" class="empty">{{ L('Aucune annonce.', 'No listing.') }}</p>
          <div class="grid">
            <div v-for="l in d.market" :key="l.id" class="tile">
              <div class="tname">{{ l.nickname || l.model_key }}</div>
              <div class="mut">{{ l.model_key }} · {{ l.seller }}</div>
              <div class="price">{{ money(l.price) }}</div>
              <div v-if="l.description" class="mut">{{ l.description }}</div>
              <div class="acts">
                <button v-if="l.seller === net.username" type="button" class="btn dim" @click="act(() => rpc('cancel_listing', { p_listing_id: l.id }), loadMarket)">{{ L('Retirer', 'Withdraw') }}</button>
                <button v-else type="button" class="btn" @click="act(() => rpc('buy_listing', { p_listing_id: l.id }), loadMarket)">{{ L('Acheter', 'Buy') }}</button>
              </div>
            </div>
          </div>
        </main>

        <!-- TRAVAIL : taxi et bus (les missions arrivent ici) -->
        <main v-else-if="app === 'work'">
          <div class="tile wide">
            <div class="tname">Taxi</div>
            <div class="mut">{{ taxi.duty ? L('En service', 'On duty') : L('Hors service', 'Off duty') }}<template v-if="taxi.duty"> · {{ taxi.rides || 0 }} {{ L('courses', 'rides') }} · {{ money(taxi.earned || 0) }}</template></div>
            <div class="acts">
              <button type="button" class="btn" @click="ui('taxi.duty', { on: !taxi.duty })">{{ taxi.duty ? L('Fin de service', 'Go off duty') : L('Prendre le service', 'Go on duty') }}</button>
              <button v-if="taxi.duty" type="button" class="btn dim" @click="ui('taxi.cancel')">{{ L('Annuler la course', 'Cancel ride') }}</button>
            </div>
          </div>
          <div class="tile wide">
            <div class="tname">Bus</div>
            <div class="mut" v-if="bus.active">{{ bus.legs || 0 }} {{ L('arrêts', 'stops') }} · {{ money(bus.earned || 0) }}</div>
            <div class="acts">
              <button v-if="!bus.active" type="button" class="btn" @click="ui('bus.start')">{{ L('Commencer la ligne', 'Start the line') }}</button>
              <button v-else type="button" class="btn dim" @click="ui('bus.stop')">{{ L('Arrêter', 'Stop') }}</button>
            </div>
          </div>
        </main>

        <!-- HISTORIQUE -->
        <main v-else-if="app === 'history'">
          <table class="tb"><tr v-for="x in d.tx" :key="x.id"><td class="mut">{{ x.created_at.slice(0, 16).replace('T', ' ') }}</td><td>{{ x.ref || x.kind }}</td><td :class="x.amount < 0 ? 'bad' : 'good'">{{ x.amount > 0 ? '+' : '' }}{{ money(x.amount) }}</td></tr></table>
        </main>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted, onBeforeUnmount } from "vue"
import { net, ui, rpc, errText, refreshMe } from "./net.js"

const L = (fr, en) => (net.lang === "en" ? en : fr)
const money = n => (Number(n) < 0 ? "-$" : "$") + Math.abs(Number(n || 0)).toLocaleString(net.lang === "en" ? "en-US" : "fr-FR")
const apps = [
  { id: "garage", color: "#ff6600", path: "M3 11l9-7 9 7M5 10v10h14V10M9 20v-6h6v6" },
  { id: "players", color: "#3b82f6", path: "M9 11a4 4 0 100-8 4 4 0 000 8zM2 21c0-4 3-6 7-6s7 2 7 6M17 11a3 3 0 100-6M22 21c0-3-2-5-5-5" },
  { id: "trades", color: "#a855f7", path: "M4 7h13M13 3l4 4-4 4M20 17H7M11 21l-4-4 4-4" },
  { id: "dealer", color: "#22c55e", path: "M6 7h12l-1 13H7L6 7zM9 7V5a3 3 0 016 0v2" },
  { id: "market", color: "#eab308", path: "M4 4h10l6 6-10 10-6-6V4zM8.5 8.5h.01" },
  { id: "work", color: "#ef4444", path: "M4 8h16v11H4zM9 8V5h6v3M4 13h16" },
  { id: "history", color: "#64748b", path: "M12 7v5l3 2M21 12a9 9 0 11-3-6.7M21 4v5h-5" },
]
const NAMES = {
  garage: ["Garage", "Garage"], players: ["Joueurs", "Players"], trades: ["Échanges", "Trades"], dealer: ["Concession", "Dealership"],
  market: ["Annonces", "Listings"], work: ["Travail", "Work"], history: ["Historique", "History"],
}
const appName = id => L(...NAMES[id])
const modeName = m => ({ money: L("Argent", "Money"), car: L("Donner une voiture", "Give a car"), trade: L("Échange", "Trade") })[m]

const app = ref(null), msg = ref(""), sel = ref(null), mode = ref("money")
const f = reactive({ amount: 0, gift: "", offer: "", want: "", cash: 0 })
const d = reactive({ trades: [], catalog: [], market: [], tx: [] })
const theirs = ref([]), theirsLoading = ref(false)
const profile = computed(() => net.me?.profile || {})
const vehicles = computed(() => net.me?.vehicles || [])
const out = v => !!(net.game.spawned && net.game.spawned[v.id])
const giftable = computed(() => vehicles.value.filter(v => !v.listed && !out(v)))
const taxi = computed(() => net.game.taxi || {})
const bus = computed(() => net.game.bus || {})
const incoming = computed(() => d.trades.filter(x => x.direction === "in").length)

const clock = ref("")
function tick() { clock.value = new Date().toLocaleTimeString(net.lang === "en" ? "en-US" : "fr-FR", { hour: "2-digit", minute: "2-digit" }) }

function focus(e, on) { const tg = e.target?.tagName; if (tg === "INPUT" || tg === "SELECT" || tg === "TEXTAREA") ui("typing", { on }) }

async function act(fn, after) {
  net.error = ""; msg.value = ""
  try { await fn(); msg.value = L("C'est fait.", "Done."); await refreshMe(); if (after) await after() } catch (e) { net.error = errText(e) }
}
const safe = async fn => { try { await fn() } catch (e) { net.error = errText(e) } }
const loadTrades = () => safe(async () => { d.trades = await rpc("get_trades") })
const loadMarket = () => safe(async () => { d.market = await rpc("get_market", { p_limit: 50, p_offset: 0 }) })
async function sellDealer(v) { await act(async () => { if (out(v)) await ui("garage.store", { id: v.id }); await rpc("sell_vehicle_to_dealer", { p_vehicle_id: v.id }) }) }

async function pick(name) {
  sel.value = name; f.gift = ""; f.offer = ""; f.want = ""; f.cash = 0; msg.value = ""; net.error = ""
  theirsLoading.value = true
  try { theirs.value = await rpc("get_player_garage", { p_username: name }) } catch (e) { theirs.value = [] }
  theirsLoading.value = false
}
// le joueur choisi a quitté le serveur : on le désélectionne
watch(() => net.players.map(p => p.username).join(), () => { if (sel.value && !net.players.some(p => p.username === sel.value)) sel.value = null })

function go(id) {
  app.value = id; msg.value = ""; net.error = ""
  if (id === "trades" || id === "players") loadTrades()
  else if (id === "dealer") safe(async () => { d.catalog = await rpc("get_catalog") })
  else if (id === "market") loadMarket()
  else if (id === "history") safe(async () => { d.tx = await rpc("get_my_transactions", { p_limit: 40 }) })
  if (id === "garage" || id === "players") refreshMe().catch(() => {})
}
watch(() => net.tablet.open, o => { if (o) { go(null); loadTrades(); refreshMe().catch(() => {}) } })

let timer = null
onMounted(() => { tick(); timer = setInterval(tick, 10000) })
onBeforeUnmount(() => clearInterval(timer))
</script>

<style lang="scss" scoped>
.tbw { position: fixed; inset: 0; z-index: 2147482500; display: flex; align-items: center; justify-content: center; background: rgba(0, 0, 0, 0.35); pointer-events: auto; }
.device { --ac: #ff6600; width: 1120px; max-width: 96vw; height: 720px; max-height: 92vh; padding: 16px; border-radius: 34px; background: linear-gradient(145deg, #1c1c1f, #0b0b0d);
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.85), inset 0 0 0 2px #2a2a2e, inset 0 0 0 5px #111; * { box-sizing: border-box; } }
.screen { height: 100%; display: flex; flex-direction: column; border-radius: 20px; overflow: hidden; color: #f2f2f2; font: 14px/1.35 "Overpass", "Segoe UI", sans-serif;
  background: radial-gradient(circle at 20% 0%, #2b2118 0%, #121214 55%, #0c0c0e 100%); }
.status { display: flex; align-items: center; gap: 14px; padding: 8px 18px; font-size: 13px; background: rgba(0, 0, 0, 0.35);
  .clock { font-weight: 700; } .place { flex: 1; text-align: center; color: var(--ac); font-weight: 700; letter-spacing: 0.03em; } .bal b { color: #4ade80; }
  .x { width: 28px; height: 28px; border-radius: 50%; border: 0; color: #fff; background: rgba(255, 255, 255, 0.1); cursor: pointer; &:hover { background: #ef4444; } } }
.apphead { display: flex; align-items: center; gap: 14px; padding: 10px 18px; border-bottom: 1px solid rgba(255, 255, 255, 0.07);
  .back { border: 0; background: none; color: var(--ac); font: 600 15px inherit; cursor: pointer; padding: 4px 0; }
  .apptitle { font: 700 18px "Overpass", sans-serif; } }
.home { flex: 1; display: grid; grid-template-columns: repeat(4, 150px); grid-auto-rows: 150px; gap: 26px; justify-content: center; align-content: center; }
.icon { position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; border: 0; background: none; color: #fff; cursor: pointer; border-radius: 18px;
  transition: transform 0.15s ease, background 0.15s ease; &:hover { transform: translateY(-3px); background: rgba(255, 255, 255, 0.05); }
  .ic { width: 78px; height: 78px; border-radius: 22px; display: flex; align-items: center; justify-content: center; box-shadow: 0 8px 22px rgba(0, 0, 0, 0.45); }
  svg { width: 40px; height: 40px; fill: none; stroke: #fff; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
  .lbl { font-weight: 600; } .badge { position: absolute; top: 14px; right: 30px; min-width: 22px; height: 22px; padding: 0 6px; border-radius: 11px; background: #ef4444; font: 700 12px/22px sans-serif; } }
main { flex: 1; overflow-y: auto; padding: 16px 20px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 14px; }
.tile { display: flex; flex-direction: column; gap: 4px; padding: 14px; border-radius: 14px; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.08);
  &.wide { margin-bottom: 12px; } .tname { font: 700 16px "Overpass", sans-serif; } .price { font: 800 20px "Overpass", sans-serif; color: var(--ac); }
  .tags { display: flex; gap: 6px; min-height: 4px; } .acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; } .inline { display: flex; gap: 6px; width: 100%; input { flex: 1; } } }
.tag { padding: 1px 8px; font-size: 11px; border-radius: 10px; background: rgba(255, 102, 0, 0.2); color: var(--ac); &.on { background: rgba(74, 222, 128, 0.2); color: #4ade80; } }
.swap { display: flex; align-items: center; gap: 8px; .arr { color: var(--ac); font-size: 18px; } }
.split { display: flex; gap: 16px; padding: 0; overflow: hidden; }
.plist { width: 280px; flex: none; overflow-y: auto; padding: 14px; border-right: 1px solid rgba(255, 255, 255, 0.07); }
.pl { width: 100%; display: flex; align-items: center; gap: 10px; padding: 10px; margin-bottom: 6px; border: 1px solid transparent; border-radius: 12px; background: rgba(255, 255, 255, 0.04);
  color: #fff; font: inherit; text-align: left; cursor: pointer; &:hover { background: rgba(255, 255, 255, 0.08); } &.on { border-color: var(--ac); background: rgba(255, 102, 0, 0.12); }
  .av { width: 36px; height: 36px; flex: none; border-radius: 50%; display: flex; align-items: center; justify-content: center; background: #3b82f6; font-weight: 800; } }
.pact { flex: 1; overflow-y: auto; padding: 14px 20px 14px 0; h3 { margin: 0 0 10px; font: 700 22px "Overpass", sans-serif; } &.empty { display: flex; align-items: center; justify-content: center; } }
.seg { display: inline-flex; padding: 3px; margin-bottom: 14px; border-radius: 10px; background: rgba(255, 255, 255, 0.06);
  button { border: 0; padding: 7px 14px; border-radius: 8px; background: none; color: rgba(255, 255, 255, 0.7); font: 600 13px inherit; cursor: pointer; &.on { background: var(--ac); color: #fff; } } }
.panel { display: flex; flex-direction: column; gap: 8px; max-width: 560px; label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: rgba(255, 255, 255, 0.6); margin-top: 6px; } }
.chips, .pickrow { display: flex; flex-wrap: wrap; gap: 6px; }
.chip, .pk { padding: 6px 12px; border-radius: 10px; border: 1px solid rgba(255, 255, 255, 0.12); background: rgba(255, 255, 255, 0.05); color: #fff; font: 600 13px inherit; cursor: pointer;
  display: flex; flex-direction: column; align-items: flex-start; small { font-weight: 400; color: rgba(255, 255, 255, 0.6); } &.on, &:hover { border-color: var(--ac); background: rgba(255, 102, 0, 0.15); } }
input { padding: 8px 10px; color: #fff; background: rgba(0, 0, 0, 0.45); border: 1px solid rgba(255, 255, 255, 0.15); border-radius: 10px; font: inherit; &:focus { outline: none; border-color: var(--ac); } }
.btn { align-self: flex-start; padding: 8px 16px; color: #fff; font: 600 13px "Overpass", sans-serif; cursor: pointer; background: var(--ac); border: 0; border-radius: 10px; transition: filter 0.15s, transform 0.15s;
  &:hover:not(:disabled) { filter: brightness(1.12); transform: translateY(-1px); } &:disabled { opacity: 0.4; cursor: default; } &.dim { background: rgba(255, 255, 255, 0.1); } }
.tb { width: 100%; border-collapse: collapse; td { padding: 6px 8px; border-bottom: 1px solid rgba(255, 255, 255, 0.06); } td:last-child { text-align: right; font-weight: 700; } }
.empty { color: rgba(255, 255, 255, 0.55); text-align: center; padding: 30px 0; }
.err { margin: 8px 20px 0; color: #ff6b6b; } .ok { margin: 8px 20px 0; color: #4ade80; } .good { color: #4ade80; } .bad { color: #ff6b6b; } .mut { color: rgba(255, 255, 255, 0.6); }
</style>
