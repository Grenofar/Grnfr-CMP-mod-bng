<template>
  <!-- Petite fenêtre rapide (touche J par défaut) : chat de serveur, liste des joueurs, repère, argent,
       échange, courses de drag. Contrairement à la fenêtre GRNFR Online (touche O), elle ne prend pas tout
       l'écran et ne cache rien du jeu derrière : juste un panneau ancré dans un coin. -->
  <div v-if="net.quickOpen" class="qpanel" @focusin="focus($event, true)" @focusout="focus($event, false)">
    <header>
      <span class="title">{{ t('q_title') }}</span>
      <button type="button" class="hb" @click="ui('quick.close')">{{ t('q_off') }}</button>
    </header>
    <main>
      <p v-if="net.error" class="err">{{ net.error }}</p>
      <p v-if="!net.server" class="mut">{{ t('q_need_server') }}</p>
      <template v-else>
        <section class="players">
          <h4>{{ t('q_players') }}</h4>
          <p v-if="!net.players.length" class="mut">{{ t('srv_empty') }}</p>
          <div v-for="p in net.players" :key="p.username" class="prow">
            <div class="line"><b>{{ p.username }}</b>
              <div class="pactions">
                <button type="button" class="mini" @click="toggleTrack(p.username)">{{ tracking === p.username ? t('q_untrack') : t('q_track') }}</button>
                <button type="button" class="mini" @click="openGive(p.username)">{{ t('q_give') }}</button>
                <button type="button" class="mini" @click="openTrade(p.username)">{{ t('q_trade') }}</button>
              </div>
            </div>
            <div v-if="giveTarget === p.username" class="row">
              <input v-model.number="giveAmount" type="number" min="1" :placeholder="t('q_give_amount')" class="sm" />
              <button type="button" class="mini" @click="sendGive(p.username)">{{ t('q_give_send') }}</button>
            </div>
            <div v-if="tradeTarget === p.username" class="trade">
              <p v-if="tradeLoading" class="mut">{{ t('q_trade_loading') }}</p>
              <template v-else>
                <select v-model="tradeOffer">
                  <option value="">{{ t('q_trade_pick_offer') }}</option>
                  <option v-for="v in myVehicles" :key="v.id" :value="v.id">{{ v.nickname || v.model_key }}</option>
                </select>
                <select v-model="tradeWant">
                  <option value="">{{ t('q_trade_pick_want') }}</option>
                  <option v-for="v in theirVehicles" :key="v.id" :value="v.id">{{ v.nickname || v.model_key }}</option>
                </select>
                <input v-model.number="tradeCash" type="number" :placeholder="t('q_trade_cash')" class="sm" />
                <button type="button" class="mini" @click="sendTrade(p.username)">{{ t('q_trade_send') }}</button>
              </template>
            </div>
          </div>
        </section>

        <section class="drag">
          <h4>{{ t('q_drag') }}</h4>
          <template v-if="!race">
            <p class="mut">{{ t('drag_none') }}</p>
            <div class="row">
              <button type="button" class="mini" @click="ui('drag.markStart')">{{ hasStart ? t('drag_start_marked') : t('drag_mark_start') }}</button>
              <button type="button" class="mini" @click="ui('drag.markFinish')">{{ hasFinish ? t('drag_finish_marked') : t('drag_mark_finish') }}</button>
            </div>
            <p v-if="!hasStart || !hasFinish" class="mut">{{ t('drag_need_mark') }}</p>
            <button type="button" class="mini" :disabled="!hasStart || !hasFinish" @click="ui('drag.propose')">{{ t('drag_propose') }}</button>
          </template>
          <template v-else>
            <p class="mut">{{ t('drag_pot') }} : {{ money(race.pot) }} — {{ t('drag_host') }} {{ race.host }}</p>
            <div v-for="e in race.entries" :key="e.username" class="prow line">
              <b>{{ e.username }}</b>
              <span class="mut">{{ money(e.stake) }} · {{ e.disqualified ? t('drag_dnf') : (e.finish_ms != null ? (e.finish_ms / 1000).toFixed(2) + ' s' : '…') }}</span>
            </div>
            <template v-if="race.status === 'betting'">
              <div v-if="!mine" class="row stakes">
                <button type="button" class="mini" v-for="s in stakes" :key="s" @click="joinStake(s)">{{ money(s) }}</button>
                <input v-model.number="customStake" type="number" min="1" :placeholder="t('drag_stake_custom')" class="sm" />
                <button type="button" class="mini" @click="joinStake(customStake)">{{ t('drag_join') }}</button>
              </div>
              <p v-else class="ok">{{ t('drag_you_in') }}</p>
              <div class="row">
                <button type="button" class="mini dim" @click="ui('drag.leave')">{{ t('drag_leave') }}</button>
                <button v-if="race.is_host" type="button" class="mini" @click="ui('drag.start')">{{ t('drag_start_race') }}</button>
              </div>
            </template>
            <template v-else-if="race.status === 'running'">
              <button v-if="race.is_host" type="button" class="mini dim" @click="ui('drag.forceFinish')">{{ t('drag_force_finish') }}</button>
            </template>
            <template v-else-if="race.status === 'finished'">
              <p class="ok">{{ t('drag_winner') }} : {{ race.winner }} ({{ money(race.pot) }})</p>
            </template>
          </template>
        </section>

        <section class="chat">
          <h4>{{ t('q_chat') }}</h4>
          <div class="log" ref="logEl">
            <div v-for="m in messages" :key="m.id" class="msg"><b>{{ m.username }}</b> {{ m.text }}</div>
          </div>
          <div class="row">
            <input v-model="chatText" :placeholder="t('q_chat_placeholder')" maxlength="200" @keyup.enter="sendChat" />
            <button type="button" class="mini" @click="sendChat">{{ t('q_send_chat') }}</button>
          </div>
        </section>
      </template>
    </main>
  </div>

  <!-- Compte à rebours de départ d'une course de drag : 3-2-1-TOP, même esprit que l'ancien compte à rebours. -->
  <Teleport to="body">
    <Transition name="cd-fade">
      <div v-if="net.dragCount !== null" class="dcwrap">
        <div class="dcplate" :class="{ go: net.dragCount === 0 }">
          <div class="dcnum">{{ net.dragCount === 0 ? 'TOP !' : net.dragCount }}</div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { ref, computed, watch, nextTick } from "vue"
import { net, ui, rpc, errText } from "./net.js"
import { tr } from "./onlineI18n.js"

const t = k => tr(net.lang, k)
const money = n => "$" + Number(n || 0).toLocaleString(net.lang === "en" ? "en-US" : "fr-FR")

function focus(e, on) { const tg = e.target?.tagName; if (tg === "INPUT" || tg === "SELECT" || tg === "TEXTAREA") ui("typing", { on }) }

// ------------------------------------------------------------------ repérer un joueur (point qui le suit)
const tracking = ref(null)
function toggleTrack(name) {
  if (tracking.value === name) { tracking.value = null; ui("track.clear") }
  else { tracking.value = name; ui("track.set", { username: name }) }
}

// ------------------------------------------------------------------ donner de l'argent
const giveTarget = ref(null), giveAmount = ref(0)
function openGive(name) { giveTarget.value = giveTarget.value === name ? null : name; giveAmount.value = 0 }
async function sendGive(name) {
  net.error = ""
  if (!giveAmount.value || giveAmount.value <= 0) return
  try { await rpc("send_money", { p_username: name, p_amount: giveAmount.value }); giveTarget.value = null }
  catch (e) { net.error = errText(e) }
}

// ------------------------------------------------------------------ échanger un véhicule
const tradeTarget = ref(null), tradeLoading = ref(false), theirVehicles = ref([])
const tradeOffer = ref(""), tradeWant = ref(""), tradeCash = ref(0)
const myVehicles = computed(() => net.me?.vehicles || [])
async function openTrade(name) {
  if (tradeTarget.value === name) { tradeTarget.value = null; return }
  net.error = ""
  tradeTarget.value = name; tradeOffer.value = ""; tradeWant.value = ""; tradeCash.value = 0
  tradeLoading.value = true
  try { theirVehicles.value = await rpc("get_player_garage", { p_username: name }) } catch (e) { net.error = errText(e) }
  tradeLoading.value = false
}
async function sendTrade(name) {
  net.error = ""
  try {
    await rpc("propose_trade", { p_username: name, p_offered: tradeOffer.value || null, p_wanted: tradeWant.value || null, p_cash: tradeCash.value || 0 })
    tradeTarget.value = null
  } catch (e) { net.error = errText(e) }
}

// ------------------------------------------------------------------ chat
const chatText = ref("")
const logEl = ref(null)
const messages = computed(() => net.game.chat?.messages || [])
function sendChat() {
  const v = chatText.value.trim()
  if (!v) return
  ui("chat.send", { text: v })
  chatText.value = ""
}
watch(messages, async () => { await nextTick(); if (logEl.value) logEl.value.scrollTop = logEl.value.scrollHeight })

// ------------------------------------------------------------------ course de drag
const race = computed(() => net.game.drag?.race || null)
const hasStart = computed(() => !!net.game.drag?.hasStart)
const hasFinish = computed(() => !!net.game.drag?.hasFinish)
const mine = computed(() => (race.value?.entries || []).some(e => e.mine))
const stakes = [100, 500, 1000, 5000, 10000, 30000, 50000]
const customStake = ref(0)
function joinStake(amount) {
  const n = Math.floor(Number(amount))
  if (!n || n <= 0) return
  ui("drag.join", { stake: n })
}
</script>

<style lang="scss" scoped>
.qpanel { --ac: #ff6600; position: fixed; top: 16px; right: 16px; z-index: 2147482200; width: 340px; max-height: 80vh;
  display: flex; flex-direction: column; background: rgba(10, 10, 10, 0.85); border: 1px solid var(--ac); border-radius: 6px;
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.6); color: #fff; font: 13px/1.3 "Overpass", "Segoe UI", sans-serif; pointer-events: auto;
  * { box-sizing: border-box; } }
header { display: flex; align-items: center; gap: 10px; padding: 6px 10px; background: rgba(0, 0, 0, 0.5); border-bottom: 2px solid var(--ac);
  .title { flex: 1; font: 600 15px "Overpass", sans-serif; color: var(--ac); } }
main { flex: 1; overflow-y: auto; padding: 8px 10px; }
h4 { margin: 10px 0 4px; color: var(--ac); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; &:first-child { margin-top: 0; } }
.prow { padding: 4px 0; border-bottom: 1px solid rgba(255, 102, 0, 0.15); }
.line { display: flex; align-items: center; justify-content: space-between; gap: 6px; flex-wrap: wrap; }
.pactions { display: flex; gap: 4px; }
.row { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; margin: 4px 0; }
.stakes { .mini { padding: 2px 7px; } }
.trade { display: flex; flex-direction: column; gap: 4px; margin: 4px 0; }
select, input { padding: 3px 6px; color: #fff; background: rgba(0, 0, 0, 0.6); border: 1px solid rgba(255, 102, 0, 0.5); border-radius: 4px; font: inherit; width: 100%; }
input.sm { width: 110px; }
.mini { padding: 2px 8px; color: #fff; font: 600 11px "Overpass", sans-serif; cursor: pointer; background: rgba(255, 102, 0, 0.25); border: 1px solid var(--ac); border-radius: 4px;
  &:hover:not(:disabled) { background: var(--ac); } &:disabled { opacity: 0.4; cursor: default; } &.dim { background: rgba(0, 0, 0, 0.5); } }
.hb { padding: 2px 10px; color: #fff; font: 600 12px "Overpass", sans-serif; cursor: pointer; background: rgba(0, 0, 0, 0.5); border: 1px solid var(--ac); border-radius: 4px;
  &:hover { background: var(--ac); } }
.chat .log { max-height: 120px; overflow-y: auto; display: flex; flex-direction: column; gap: 2px; margin-bottom: 4px; }
.msg { font-size: 12px; word-break: break-word; b { color: var(--ac); margin-right: 4px; } }
.err { color: #ff6b6b; margin: 0 0 6px; } .ok { color: #4ade80; } .mut { color: rgba(255, 255, 255, 0.6); }

.dcwrap { position: fixed; top: 16%; left: 0; right: 0; z-index: 2147482600; display: flex; justify-content: center; pointer-events: none; user-select: none; }
.dcplate { min-width: 220px; padding: 10px 26px; text-align: center; color: #fff; background: rgba(8, 8, 8, 0.88); border: 2px solid #ff6600; border-radius: 10px;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.7), 0 0 36px rgba(255, 102, 0, 0.35); font-family: "Overpass", "Segoe UI", sans-serif;
  &.go { box-shadow: 0 10px 40px rgba(0, 0, 0, 0.7), 0 0 70px rgba(255, 102, 0, 0.75); background: rgba(24, 10, 0, 0.9); } }
.dcnum { font-size: 72px; line-height: 1; font-weight: 800; color: #ff6600; font-variant-numeric: tabular-nums; }
.dcplate.go .dcnum { font-size: 56px; color: #fff; }
.cd-fade-enter-active, .cd-fade-leave-active { transition: opacity 0.25s; }
.cd-fade-enter-from, .cd-fade-leave-to { opacity: 0; }
</style>
