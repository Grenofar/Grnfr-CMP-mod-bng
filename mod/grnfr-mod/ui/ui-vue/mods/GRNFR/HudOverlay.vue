<template>
  <!-- Petit HUD (touche K) : même style que la fenêtre GRNFR. Monté dans <body>, sans app « HUD Apps ». -->
  <div v-if="shown && open && !big" class="ghud" :class="['acc-' + accent, 'pos-' + (s.hudPos || 'top-left'), { compact: s.compact }]" :style="{ opacity: s.opacity }">
    <header>
      <span class="title">GRNFR CPM</span>
      <span class="hbtns">
        <button type="button" class="hb" title="GRNFR CPM" @click="callLua('ui', 'window.open', '{}')">Online</button>
        <button type="button" class="hb" title="Chat / joueurs / drag (J)" @click="callLua('ui', 'quick.open', '{}')">Chat</button>
        <button type="button" class="hb opt" @click="openBig">{{ t('hud_option') }}</button>
      </span>
    </header>
    <div class="body">
      <div class="grid">
        <div v-if="s.showFps" class="card"><label>FPS</label><div class="big">{{ fmt(perf.fps) }}</div></div>
        <div v-if="s.showAvg" class="card"><label>{{ t('dash_avg') }}</label><div class="big">{{ fmt(perf.avg) }}</div></div>
        <div v-if="s.showMode" class="card wide"><label>{{ t('dash_mode') }}</label><div class="val">{{ modeLabel }}</div></div>
      </div>
      <p v-if="!perf.valid" class="diag">{{ t('diag_wait') }} · ticks {{ perf.nTicks }} · hooks {{ perf.hooks }} · Lua {{ stats.ok }}/{{ stats.fail }}</p>
      <div v-if="s.showGraph" class="card graph"><FpsGraph :hist="perf.hist" :window="90" :labels="graphLabels" /></div>
    </div>
  </div>

  <!-- Grande fenêtre (bouton Option) : même taille que la fenêtre du menu. K pour la fermer. -->
  <Teleport to="body">
    <div v-if="session && big" class="gwin">
      <div class="window">
        <header class="wh">
          <span class="wt">GRNFR CPM</span>
          <span class="wk">{{ keyLabel || 'K' }} : {{ t('hud_close') }}</span>
          <BngButton @click="closeBig">{{ t('hud_close') }}</BngButton>
        </header>
        <GrnfrPanel variant="game" class="body lg" />
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount } from "vue"
import { useBridge } from "@/bridge"
import { BngButton } from "@/common/components/base"
import { callLua, unwrapObj, stats } from "./luaCall.js"
import { translate, hasKey } from "./i18n.js"
import { getPerf } from "./perfStore.js"
import FpsGraph from "./FpsGraph.vue"
import GrnfrPanel from "./GrnfrPanel.vue"

const { events } = useBridge()
const DEFAULTS = {
  hudEnabled: true, hudPos: "top-left", showFps: true, showAvg: true, showMode: true, showGraph: true, compact: false,
  accent: "orange", opacity: 1, lang: "fr",
}
const session = ref(false)
const open = ref(false)
const big = ref(false)
const angular = ref(false)
const keyLabel = ref(null)
const mode = reactive({ label: "—", ids: [], raw: null })
const s = reactive({ ...DEFAULTS })
const perf = getPerf() // historique FPS partagé avec la grande fenêtre

const accent = computed(() => s.accent || "orange")
const t = key => translate(s.lang || "fr", key)
const shown = computed(() => session.value && s.hudEnabled && !angular.value)
const fmt = n => (perf.valid ? Math.round(n) : "—")
const graphLabels = computed(() => ({ avg: t("avg_1s"), inst: t("perf_inst"), empty: t("graph_empty") }))
const modeLabel = computed(() => {
  const raw = mode.ids
  const ids = Array.isArray(raw) ? raw : raw && typeof raw === "object" ? Object.values(raw) : []
  if (!ids.length) return mode.label
  return ids.map(id => (hasKey("mode_" + id) ? t("mode_" + id) : mode.raw || id)).join(" · ")
})

function openBig() { big.value = true; open.value = false; callLua("openBig") }
function closeBig() { big.value = false; callLua("closeBig") }

let lastEvt = 0
let lastLuaBig = null, lastLuaHud = null

function onStatic(d) {
  d = unwrapObj(d)
  if (!d) return
  lastEvt = Date.now()
  // On ne suit Lua que lorsque SON état change (touche K, retour au menu...) : un envoi périodique inchangé ne doit pas
  // fermer la fenêtre que l'utilisateur vient d'ouvrir (si Lua n'a pas reçu la demande d'ouverture, il dit « fermée »).
  const sess = !!d.session
  const lb = sess && !!d.bigOpen, lh = sess && !!d.hudOpen
  session.value = sess
  if (!sess) { open.value = false; big.value = false }
  else {
    if (lb !== lastLuaBig) { big.value = lb; if (lb) open.value = false }
    if (lh !== lastLuaHud) { open.value = lh; if (lh) big.value = false }
  }
  lastLuaBig = lb; lastLuaHud = lh
  angular.value = !!d.angular
  if ("keyLabel" in d) keyLabel.value = d.keyLabel
  mode.label = d.mode || "—"; mode.ids = d.modeIds || []; mode.raw = d.modeRaw || null
  if (d.settings) Object.assign(s, DEFAULTS, d.settings)
}
// Secours : si aucun événement n'arrive pendant 3 s, on lit l'état directement dans Lua.
let pollT = null
async function pollState() {
  if (Date.now() - lastEvt < 3000) return
  const r = await callLua("getState")
  if (r && typeof r === "object") onStatic(r)
}
onMounted(() => { events.on("GRNFRStatic", onStatic); pollT = setInterval(pollState, 2000) })
onBeforeUnmount(() => {
  if (pollT) clearInterval(pollT)
  events.off("GRNFRStatic", onStatic)
})
</script>

<style lang="scss" scoped>
.ghud {
  --card: rgba(0, 0, 0, 0.45); --line: rgba(255, 102, 0, 0.35); --tx: #fff; --mut: rgba(255, 255, 255, 0.6); --ac: #ff6600;
  &.acc-cyan { --ac: #35c6e8; } &.acc-green { --ac: #4ade80; } &.acc-amber { --ac: #f5b942; } &.acc-violet { --ac: #a78bfa; }
  position: fixed; z-index: 2147481000; width: 400px; max-width: 96vw;
  &.pos-top-left { top: 16px; left: 16px; } &.pos-top-right { top: 16px; right: 16px; }
  &.pos-bottom-left { bottom: 16px; left: 16px; } &.pos-bottom-right { bottom: 16px; right: 16px; }
  background: rgba(10, 10, 10, 0.85); border: 1px solid var(--ac); border-radius: 6px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.7);
  color: var(--tx); font: 14px/1.35 "Overpass", "Segoe UI", sans-serif; pointer-events: auto; user-select: none;
  * { box-sizing: border-box; }
  &.compact { width: 320px; font-size: 12px; .big { font-size: 24px; } }
}
header { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 6px 10px 6px 14px; background: rgba(0, 0, 0, 0.5); border-bottom: 2px solid var(--ac);
  font: 600 18px "Overpass", "Segoe UI", sans-serif; .title { color: var(--ac); } }
.hbtns { display: flex; gap: 6px; }
.hb { padding: 2px 10px; font: 600 12px "Overpass", "Segoe UI", sans-serif; color: #fff; cursor: pointer; background: rgba(0, 0, 0, 0.5); border: 1px solid var(--ac); border-radius: 4px;
  transition: background 0.15s; &:hover { background: var(--ac); } &.opt { text-transform: uppercase; letter-spacing: 0.05em; } }
.body { padding: 10px 12px 8px; }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 8px; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 4px; padding: 8px 10px; &.wide { grid-column: 1 / -1; } }
.card label { color: var(--mut); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; }
.big { font-size: 32px; font-weight: 700; color: var(--ac); font-variant-numeric: tabular-nums; }
.val { font-size: 14px; }
.diag { margin: 0 0 8px; font-size: 11px; color: var(--mut); }
.graph { height: 150px; padding: 0; margin-bottom: 4px; }

/* Grande fenêtre : mêmes dimensions que la fenêtre du menu */
.gwin { position: fixed; inset: 0; z-index: 2147483000; display: flex; align-items: center; justify-content: center; background: rgba(0, 0, 0, 0.35); pointer-events: auto; }
.window {
  display: flex; flex-direction: column; width: min(1640px, 96vw); height: min(940px, 94vh);
  background: rgba(10, 10, 10, 0.78); border: 1px solid #ff6600; border-radius: 6px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.7); overflow: hidden; pointer-events: auto;
  :deep(*) { pointer-events: auto; }
}
.wh { display: flex; align-items: center; gap: 14px; padding: 10px 18px; background: rgba(0, 0, 0, 0.5); border-bottom: 2px solid #ff6600; color: #fff;
  font: 600 24px "Overpass", "Segoe UI", sans-serif; .wt { color: #ff6600; flex: 1; } .wk { font-size: 14px; font-weight: 400; color: rgba(255, 255, 255, 0.6); } }
.window .body { flex: 1; width: 100% !important; height: auto !important; min-height: 0; max-width: none !important; padding: 0; }
</style>
