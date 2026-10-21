<template>
  <!-- Petit HUD (touche K) : même style que la fenêtre GRNFR. Monté dans <body>, sans app « HUD Apps ». -->
  <div v-if="shown && open && !big" class="ghud" :class="['acc-' + accent, 'pos-' + (s.hudPos || 'top-left'), { compact: s.compact }]" :style="{ opacity: s.opacity }">
    <header>
      <span class="title">GRNFR Mod</span>
      <span class="hbtns">
        <button v-if="chase !== 'idle'" type="button" class="hb" @click="chaseRestart">⟳ {{ t('chase_restart') }}</button>
        <button v-if="chase !== 'idle'" type="button" class="hb" :title="t('chase_stop')" @click="callLua('chaseStop')">✕</button>
        <button type="button" class="hb" title="GRNFR Online" @click="callLua('ui', 'window.open', '{}')">Online</button>
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
      <p v-if="chase === 'countdown'" class="chase">{{ t('chase_countdown') }}</p>
    </div>
  </div>

  <!-- Compte à rebours du chase : 3 - 2 - 1 - TOP (orange et noir, transition entre les chiffres) -->
  <Teleport to="body">
    <Transition name="cd-fade">
      <div v-if="cd.visible" class="cdwrap">
        <div class="cdplate" :class="{ go: cd.value === 0 }">
          <div class="cdtag">{{ cd.role === 'pursue' ? t('cd_pursue') : t('cd_flee') }}</div>
          <div class="cdstage">
            <Transition name="cd-digit" mode="out-in">
              <div :key="cd.value" class="cdnum">{{ cd.value === 0 ? t('cd_go') : cd.value }}</div>
            </Transition>
          </div>
          <div class="cdbar"><i :key="cd.value" class="cdfill" :class="{ full: cd.value === 0 }"></i></div>
        </div>
      </div>
    </Transition>
  </Teleport>

  <!-- Grande fenêtre (bouton Option) : même taille que la fenêtre du menu. K pour la fermer. -->
  <Teleport to="body">
    <div v-if="session && big" class="gwin">
      <div class="window">
        <header class="wh">
          <span class="wt">GRNFR Mod</span>
          <span class="wk">{{ keyLabel || 'K' }} : {{ t('hud_close') }}</span>
          <BngButton @click="closeBig">{{ t('hud_close') }}</BngButton>
        </header>
        <GrnfrPanel variant="game" class="body lg" @chase-started="onChaseStarted" />
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
const chase = ref("idle")
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
function chaseRestart() { callLua("chaseRestart") }

let lastEvt = 0
let lastLuaBig = null, lastLuaHud = null

// --- Compte à rebours du chase (événement GRNFRChaseCount envoyé par Lua : 3, 2, 1, puis 0 = TOP)
const cd = reactive({ visible: false, value: 3, role: "flee" })
let cdHide = null
function onCount(d) {
  d = unwrapObj(d)
  if (!d || typeof d.value !== "number") return
  if (cdHide) { clearTimeout(cdHide); cdHide = null }
  cd.value = d.value; cd.role = d.role || "flee"; cd.visible = true
  if (d.value === 0) cdHide = setTimeout(() => { cd.visible = false }, 1100) // « TOP ! » reste un instant puis disparaît
}
// Le chase démarre : la grande fenêtre disparaît et le petit HUD apparaît.
function onChaseStarted() { big.value = false; open.value = true }
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
  const cp = d.chase?.phase || "idle"
  if (cp !== "idle" && chase.value === "idle") { big.value = false; open.value = sess && s.hudEnabled !== false } // chase lancé : fenêtre fermée, HUD affiché
  if (cp === "idle" && cd.visible && cd.value !== 0) cd.visible = false // chase arrêté pendant le compte à rebours
  chase.value = cp
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
onMounted(() => { events.on("GRNFRStatic", onStatic); events.on("GRNFRChaseCount", onCount); pollT = setInterval(pollState, 2000) })
onBeforeUnmount(() => {
  if (pollT) clearInterval(pollT)
  if (cdHide) clearTimeout(cdHide)
  events.off("GRNFRStatic", onStatic); events.off("GRNFRChaseCount", onCount)
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
.chase { margin: 4px 0 0; padding: 4px 8px; font-size: 12px; border: 1px solid var(--ac); border-radius: 4px; background: rgba(255, 102, 0, 0.12); }

/* Compte à rebours du chase : plaque noire, chiffres orange, transition douce entre les chiffres */
.cdwrap { position: fixed; top: 16%; left: 0; right: 0; z-index: 2147482000; display: flex; justify-content: center; pointer-events: none; user-select: none; }
.cdplate {
  min-width: 300px; padding: 14px 34px 16px; text-align: center; color: #fff;
  background: rgba(8, 8, 8, 0.88); border: 2px solid #ff6600; border-radius: 10px;
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.8), 0 10px 40px rgba(0, 0, 0, 0.7), 0 0 36px rgba(255, 102, 0, 0.35);
  font-family: "Overpass", "Segoe UI", sans-serif;
  transition: box-shadow 0.3s, background 0.3s;
  &.go { box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.8), 0 10px 40px rgba(0, 0, 0, 0.7), 0 0 70px rgba(255, 102, 0, 0.75); background: rgba(24, 10, 0, 0.9); }
}
.cdtag { font-size: 15px; font-weight: 600; letter-spacing: 0.28em; text-transform: uppercase; color: rgba(255, 255, 255, 0.7); }
.cdstage { height: 150px; display: flex; align-items: center; justify-content: center; overflow: hidden; }
.cdnum { font-size: 128px; line-height: 1; font-weight: 800; color: #ff6600; font-variant-numeric: tabular-nums; text-shadow: 0 0 22px rgba(255, 102, 0, 0.55); }
.cdplate.go .cdnum { font-size: 96px; letter-spacing: 0.04em; color: #fff; text-shadow: 0 0 26px rgba(255, 102, 0, 0.95); }
.cdbar { height: 4px; border-radius: 2px; background: rgba(255, 255, 255, 0.12); overflow: hidden; }
.cdfill { display: block; height: 100%; width: 100%; background: #ff6600; transform-origin: left center; animation: cd-drain 1s linear forwards; &.full { animation: none; } }
@keyframes cd-drain { from { transform: scaleX(1); } to { transform: scaleX(0); } }
.cd-digit-enter-active { transition: opacity 0.22s ease-out, transform 0.22s cubic-bezier(0.2, 0.9, 0.3, 1.2); }
.cd-digit-leave-active { transition: opacity 0.16s ease-in, transform 0.16s ease-in; }
.cd-digit-enter-from { opacity: 0; transform: scale(0.55); }
.cd-digit-leave-to { opacity: 0; transform: scale(1.45); }
.cd-fade-enter-active, .cd-fade-leave-active { transition: opacity 0.25s; }
.cd-fade-enter-from, .cd-fade-leave-to { opacity: 0; }

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
