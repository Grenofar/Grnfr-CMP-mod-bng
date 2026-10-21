<template>
  <div class="grnfr" :class="'acc-' + (st.settings?.accent || 'orange')">
    <nav class="tabs">
      <button type="button" v-for="id in tabIds" :key="id" :class="{ on: tab === id }" @click="tab = id">
        <svg viewBox="0 0 24 24"><path :d="icons[id]" /></svg><span>{{ t('tab_' + id) }}</span>
      </button>
    </nav>

    <section v-if="tab === 'dashboard'">
      <div class="head"><b>GRNFR Mod</b><span class="ver">v{{ st.version }}</span></div>
      <p class="tagline">{{ t('subtitle') }}</p>
      <p class="note">{{ t('desc') }}</p>
      <p v-if="isGame" class="note">{{ t('game_settings_hint') }}</p>
      <div class="grid">
        <div class="card"><label>{{ t('dash_fps') }}</label><div class="big">{{ fmt(perf.fps) }}</div></div>
        <div class="card"><label>{{ t('dash_avg') }}</label><div class="big">{{ fmt(perf.avg) }}</div></div>
        <div class="card wide"><label>{{ t('dash_mode') }}</label><div class="val">{{ modeLabel }}</div></div>
      </div>
      <p v-if="!perf.valid" class="note">{{ t('dash_note') }}</p>
    </section>

    <section v-if="tab === 'performance'" class="perfsec">
      <div class="grid">
        <div class="card"><label>{{ t('perf_inst') }}</label><div class="big">{{ fmt(perf.fps) }}</div></div>
        <div class="card"><label>{{ t('perf_avg') }}</label><div class="big">{{ fmt(perf.avg) }}</div></div>
      </div>
      <div class="card wide graph"><FpsGraph :hist="perf.hist" :window="graphWindow" :labels="graphLabels" /></div>
      <p class="note">{{ t('graph_hint') }}</p>
    </section>

    <section v-if="tab === 'optim'">
      <h3>{{ t('opt_title') }}</h3>
      <div class="row tg" @click="setSetting('antiStutter', !st.settings.antiStutter)">
        <span>{{ t('antistutter') }} <em class="badge">{{ t('badge_dev') }}</em></span><i class="sw" :class="{ on: st.settings.antiStutter }"></i>
      </div>
      <p class="note">{{ t('antistutter_note') }}</p>
      <div class="row tg" @click="setSetting('traffic', !st.settings.traffic)">
        <span>{{ t('traffic') }} <em class="badge">{{ t('badge_dev') }}</em></span><i class="sw" :class="{ on: st.settings.traffic }"></i>
      </div>
      <div class="row" :class="{ dim: !st.settings.traffic }">
        <span>{{ t('traffic_min') }}</span>
        <div class="limit">
          <input type="range" min="10" max="300" step="1" v-model.number="minDraft" @change="commitMin" />
          <input type="number" class="numbox" min="10" max="300" step="1" v-model.number="minDraft" @change="commitMin" @keyup.enter="commitMin" />
        </div>
      </div>
      <p class="note">{{ t('traffic_note') }}</p>
      <p v-if="trafficText" class="note" :class="trafficClass">{{ trafficText }}</p>
    </section>

    <section v-if="tab === 'settings'">
      <p v-if="!st.connected" class="note bad">{{ t('no_lua') }}</p>
      <p v-if="!st.connected" class="note">Lua calls: {{ luaStats.ok }} ok / {{ luaStats.fail }} failed{{ luaStats.last ? ' - last error: ' + luaStats.last : '' }}</p>
      <h3>{{ t('s_lang') }}</h3>
      <div class="row">
        <span>{{ t('lang_label') }}</span>
        <div class="seg">
          <button type="button" v-for="o in languages" :key="o[0]" :class="{ on: lang === o[0] }" @click="setSetting('lang', o[0])">{{ o[1] }}</button>
        </div>
      </div>

      <h3>{{ t('s_hud') }}</h3>
      <div v-for="k in hudToggles" :key="k" class="row tg" @click="setSetting(k, !st.settings[k])">
        <span>{{ t(k) }}</span><i class="sw" :class="{ on: st.settings[k] }"></i>
      </div>
      <div class="row">
        <span>{{ t('hud_pos') }}</span>
        <div class="seg">
          <button type="button" v-for="v in positions" :key="v" :class="{ on: st.settings.hudPos === v }" @click="setSetting('hudPos', v)">{{ t('pos_' + v) }}</button>
        </div>
      </div>
      <div class="row">
        <span>{{ t('refresh_rate') }}</span>
        <div class="seg">
          <button type="button" v-for="r in rates" :key="r" :class="{ on: st.settings.refreshRate === r }" @click="setSetting('refreshRate', r)">{{ r === 0 ? t('refresh_auto') : r + ' Hz' }}</button>
        </div>
      </div>
      <div class="row">
        <span>{{ t('accent') }}</span>
        <div class="seg">
          <button type="button" v-for="a in accents" :key="a" :class="{ on: st.settings.accent === a }" @click="setSetting('accent', a)">{{ a }}</button>
        </div>
      </div>
      <div class="row">
        <span>{{ t('hud_opacity') }}</span>
        <input type="range" min="0.5" max="1" step="0.05" :value="st.settings.opacity"
          @input="touch(); st.settings.opacity = Number($event.target.value)" @change="setSetting('opacity', Number($event.target.value))" />
      </div>

      <h3>{{ t('s_key') }}</h3>
      <div class="row"><span>{{ t('hud_key') }}</span><b class="kb">{{ st.keyLabel || 'K' }}</b></div>
      <p class="note">{{ t('key_note') }}</p>

      <h3>{{ t('s_fps') }}</h3>
      <div class="row tg" @click="setSetting('fpsOverlay', !st.settings.fpsOverlay)">
        <span>{{ t('fpsOverlay') }}</span><i class="sw" :class="{ on: st.settings.fpsOverlay }"></i>
      </div>
      <p class="note">{{ t('fps_note') }}</p>
      <div class="row">
        <span>{{ t('fps_pos') }}</span>
        <div class="seg">
          <button type="button" v-for="v in positions" :key="v" :class="{ on: st.settings.fpsPos === v }" @click="setSetting('fpsPos', v)">{{ t('pos_' + v) }}</button>
        </div>
      </div>
      <div class="row">
        <span>{{ t('fps_size') }}</span>
        <div class="seg">
          <button type="button" v-for="v in sizes" :key="v" :class="{ on: st.settings.fpsSize === v }" @click="setSetting('fpsSize', v)">{{ t('size_' + v) }}</button>
        </div>
      </div>
      <div class="row">
        <span>{{ t('fps_color') }}</span>
        <div class="colors">
          <button type="button" v-for="c in palette" :key="c" class="swatch" :class="{ on: st.settings.fpsColor === c }" :style="{ background: c }" @click="setSetting('fpsColor', c)"></button>
          <input type="color" :value="st.settings.fpsColor"
            @input="touch(); st.settings.fpsColor = $event.target.value" @change="setSetting('fpsColor', $event.target.value)" />
        </div>
      </div>
      <div class="row">
        <span>{{ t('fps_opacity') }}</span>
        <input type="range" min="0.3" max="1" step="0.05" :value="st.settings.fpsOpacity"
          @input="touch(); st.settings.fpsOpacity = Number($event.target.value)" @change="setSetting('fpsOpacity', Number($event.target.value))" />
      </div>
      <div class="row tg" @click="setSetting('fpsBg', !st.settings.fpsBg)">
        <span>{{ t('fpsBg') }}</span><i class="sw" :class="{ on: st.settings.fpsBg }"></i>
      </div>
      <div class="preview">
        <label>{{ t('preview') }}</label>
        <span class="demo" :class="st.settings.fpsSize" :style="previewStyle"><b>{{ perf.valid ? Math.round(perf.avg) : 60 }}</b><small>FPS</small></span>
      </div>

      <BngButton class="reset" @click="callLua('resetSettings')">{{ t('reset') }}</BngButton>
    </section>

    <section v-if="tab === 'mods'">
      <div class="card wide">
        <span class="badge">{{ t('badge_dev') }}</span>
        <div class="val">Mod Manager</div>
        <p class="note">{{ t('mm_note') }}</p>
      </div>
    </section>

    <!-- Premier lancement : choix de la langue (mémorisé ensuite) -->
    <div v-if="needsLang" class="welcome">
      <div class="w-box">
        <div class="w-title">GRNFR Mod</div>
        <p class="w-sub">{{ STRINGS.fr.subtitle }}<br /><span>{{ STRINGS.en.subtitle }}</span></p>
        <p class="note">{{ STRINGS.fr.desc }}</p>
        <p class="note">{{ STRINGS.en.desc }}</p>
        <div class="w-choose">Choisissez votre langue · Choose your language</div>
        <div class="w-btns">
          <button type="button" @click="chooseLang('fr')">Français</button>
          <button type="button" @click="chooseLang('en')">English</button>
        </div>
        <p class="note">Modifiable plus tard dans Paramètres · You can change it later in Settings</p>
      </div>
    </div>
  </div>
</template>

<script>
const modInfo = {}
</script>

<script setup>
import { ref, reactive, computed, watch, onMounted, onBeforeUnmount } from "vue"
import { useBridge } from "@/bridge"
import { BngButton } from "@/common/components/base"
import { callLua, unwrapObj, stats as luaStats } from "./luaCall.js"
import { STRINGS, translate, hasKey } from "./i18n.js"
import FpsGraph from "./FpsGraph.vue"
import { getPerf } from "./perfStore.js"

const { events } = useBridge()

// Deux versions de la même interface :
//  - « menu » (menu principal + onglet Mods du menu pause) : tableau de bord, performances, RÉGLAGES, mods. Pas d'optimisation.
//  - « game » (grande fenêtre en partie, ouverte par le bouton Option du HUD) : tableau de bord, performances,
//    optimisation (trafic adaptatif, anti-stutter). Aucun réglage.
const props = defineProps({ variant: { type: String, default: "menu" } })
const isGame = computed(() => props.variant === "game")
const tabIds = computed(() => isGame.value
  ? ["dashboard", "performance", "optim"]
  : ["dashboard", "performance", "settings", "mods"])
const icons = {
  dashboard: "M3 3h8v8H3zM13 3h8v5h-8zM13 10h8v11h-8zM3 13h8v8H3z",
  performance: "M3 17l5-6 4 4 8-10",
  optim: "M13 2L4 14h7l-1 8 9-12h-7z",
  settings: "M4 7h10M18 7h2M4 17h2M10 17h10M14 4v6M6 14v6",
  mods: "M12 3l8 4v10l-8 4-8-4V7z",
}
const hudToggles = ["hudEnabled", "showFps", "showAvg", "showMode", "showGraph", "compact"]
const positions = ["top-right", "top-left", "bottom-right", "bottom-left"]
const sizes = ["small", "medium", "large"]
const languages = [["fr", "Français"], ["en", "English"]]
const palette = ["#ff6600", "#ffffff", "#4ade80", "#35c6e8", "#f5b942", "#a78bfa"]
const rates = [0, 1, 2, 4, 10]
const accents = ["orange", "cyan", "green", "amber", "violet"]
const HIST = 120

const tab = ref("dashboard")
// Valeurs par défaut : l'onglet Paramètres s'affiche même si Lua n'a pas (encore) répondu.
const DEFAULTS = {
  hudEnabled: true, hudPos: "top-left", showFps: true, showAvg: true, showMode: true, showGraph: true, compact: false,
  antiStutter: false, traffic: false, trafficMinFps: 60,
  refreshRate: 0, introShown: true, accent: "orange", opacity: 1, lang: "fr", langChosen: true,
  fpsOverlay: false, fpsBg: true, fpsPos: "top-right", fpsSize: "medium", fpsColor: "#ff6600", fpsOpacity: 0.9,
}
// Cache des derniers réglages reçus de Lua (mémoire de la page + localStorage) : à la réouverture, les interrupteurs
// s'affichent tout de suite dans leur dernier état au lieu de repasser par les valeurs par défaut. Lua (settings/grnfr.json) reste la référence.
function readCache() {
  try {
    if (window.__grnfrSettings) return window.__grnfrSettings
    const raw = localStorage.getItem("grnfr_settings_cache")
    return raw ? JSON.parse(raw) || {} : {}
  } catch (e) { return {} }
}
function writeCache(settings) {
  try {
    window.__grnfrSettings = { ...settings }
    localStorage.setItem("grnfr_settings_cache", JSON.stringify(settings))
  } catch (e) { /* ignoré */ }
}
const st = reactive({ version: "—", mode: "—", modeId: null, keyLabel: null, connected: false, settings: { ...DEFAULTS, ...readCache() } })
const perf = getPerf() // historique FPS partagé avec le HUD
const graphWindow = 120
let lastHist = 0

const previewStyle = computed(() => ({
  color: st.settings?.fpsColor || "#ff6600",
  opacity: st.settings?.fpsOpacity ?? 0.9,
  background: st.settings?.fpsBg === false ? "transparent" : "rgba(0, 0, 0, 0.45)",
}))

const lang = computed(() => st.settings?.lang || "fr")
const t = key => translate(lang.value, key)
const needsLang = computed(() => !isGame.value && st.connected && st.settings.langChosen === false)
const modeLabel = computed(() => {
  const raw = st.modeIds
  const ids = Array.isArray(raw) ? raw : raw && typeof raw === "object" ? Object.values(raw) : []
  if (!ids.length) return st.mode
  return ids.map(id => (hasKey("mode_" + id) ? t("mode_" + id) : st.modeRaw || id)).join(" · ")
})

const graphLabels = computed(() => ({ avg: t("avg_1s"), inst: t("perf_inst"), empty: t("graph_empty") }))

// Trafic adaptatif : FPS minimum voulu (curseur + zone de texte synchronisés)
const minDraft = ref(60)
watch(() => st.settings?.trafficMinFps, v => { if (typeof v === "number") minDraft.value = v }, { immediate: true })
function commitMin() {
  let n = Math.round(Number(minDraft.value))
  if (!isFinite(n)) n = st.settings?.trafficMinFps || 60
  n = Math.min(300, Math.max(10, n))
  minDraft.value = n
  setSetting("trafficMinFps", n)
}
const trafficText = computed(() => {
  const tr = st.traffic
  if (!tr) return ""
  if (tr.state === "running") return t("traffic_running").replace("{a}", tr.active).replace("{p}", tr.parked).replace("{ba}", tr.baseActive).replace("{bp}", tr.baseParked)
  if (tr.state === "impossible") return t("traffic_impossible")
  if (tr.state === "unavailable") return t("traffic_unavailable")
  return ""
})
const trafficClass = computed(() => (st.traffic?.state === "running" ? "ok" : "bad"))

function chooseLang(l) {
  if (st.settings) { st.settings.lang = l; st.settings.langChosen = true }
  callLua("chooseLanguage", l)
}

const fmt = n => (perf.valid ? Math.round(n) : "—")

let lastEdit = 0
const touch = () => { lastEdit = Date.now() }
function setSetting(key, value) {
  touch()
  if (st.settings) { st.settings[key] = value; writeCache(st.settings) } // retour visuel immédiat + cache
  callLua("setSetting", key, value).then(refresh)
}
function act(fn, ...args) { callLua(fn, ...args).then(refresh) }
// Lecture directe de l'état dans Lua (valeur de retour de l'appel) : ne dépend pas des événements.
async function refresh() {
  const r = await callLua("getState")
  if (!r || typeof r !== "object") return
  onStatic(r)
}
function onStatic(d) {
  d = unwrapObj(d)
  if (!d) return
  st.lastUpdate = Date.now()
  if (d.settings) {
    st.connected = true
    if (Date.now() - lastEdit < 2000) { d = { ...d }; delete d.settings } // ne pas écraser un réglage en cours de modification
    else { d = { ...d, settings: { ...DEFAULTS, ...d.settings } }; writeCache(d.settings) }
  }
  Object.assign(st, d)
}
let pollTimer = null
onMounted(() => {
  events.on("GRNFRStatic", onStatic)
  callLua("requestState", "panel").then(r => { if (r && typeof r === "object") onStatic(r) })
  refresh()
  pollTimer = setInterval(refresh, 1500) // mode de jeu et réglages toujours à jour, même si un événement est manqué
})
onBeforeUnmount(() => {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
  events.off("GRNFRStatic", onStatic)
  callLua("uiClosed", "panel")
})
</script>

<style lang="scss" scoped>
.grnfr {
  --card: rgba(0, 0, 0, 0.45); --line: rgba(255, 102, 0, 0.35); --tx: #fff; --mut: rgba(255, 255, 255, 0.6); --ac: #ff6600;
  &.acc-cyan { --ac: #35c6e8; } &.acc-green { --ac: #4ade80; } &.acc-amber { --ac: #f5b942; } &.acc-violet { --ac: #a78bfa; }
  position: relative; display: flex; width: 760px; height: 480px; max-width: 100%; overflow: hidden; background: #0a0a0a;
  color: var(--tx); font: 14px/1.35 "Overpass", "Segoe UI", sans-serif;
  pointer-events: auto;
  * { box-sizing: border-box; }
}
.tabs {
  display: flex; flex-direction: column; gap: 2px; padding: 8px; width: 140px; flex: none;
  border-right: 1px solid var(--line); background: #000;
  button { display: flex; align-items: center; gap: 8px; background: none; border: 0; border-radius: 4px;
    color: var(--mut); padding: 8px; font: inherit; cursor: pointer; pointer-events: auto;
    transition: background 0.15s, color 0.15s, transform 0.15s;
    &:hover { background: rgba(255, 102, 0, 0.18); color: var(--tx); transform: translateX(2px); }
    &.on { background: var(--ac); color: #fff; transform: none; } }
  svg { width: 16px; height: 16px; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; flex: none; }
}
section { flex: 1; padding: 12px 16px; overflow-y: auto; min-width: 0; }
h3 { margin: 14px 0 4px; padding-bottom: 4px; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: var(--ac); border-bottom: 1px solid var(--line); &:first-child { margin-top: 0; } }
.tagline { margin: 0 0 4px; color: var(--ac); font-weight: 600; }
.welcome { position: absolute; inset: 0; z-index: 5; display: flex; align-items: center; justify-content: center; padding: 16px; overflow-y: auto;
  background: #0a0a0a;
  .w-box { max-width: 520px; text-align: center; }
  .w-title { font-size: 28px; font-weight: 700; color: var(--ac); letter-spacing: 0.04em; }
  .w-sub { margin: 4px 0 10px; font-weight: 600; span { color: var(--mut); font-weight: 400; } }
  .w-choose { margin: 14px 0 8px; font-weight: 600; }
  .w-btns { display: flex; justify-content: center; gap: 12px; margin-bottom: 8px;
    button { min-width: 140px; padding: 10px 18px; font: 600 16px "Overpass", "Segoe UI", sans-serif; color: #fff; cursor: pointer; pointer-events: auto;
      background: rgba(0, 0, 0, 0.5); border: 1px solid var(--ac); border-radius: 4px; transition: background 0.15s, transform 0.15s;
      &:hover { background: var(--ac); transform: translateY(-2px); } } } }
.head { display: flex; justify-content: space-between; margin-bottom: 10px; }
.ver { color: var(--mut); }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 8px; .card { margin: 0; } }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 4px; padding: 8px 10px; margin-bottom: 8px;
  transition: border-color 0.15s, background 0.15s, transform 0.15s;
  &:hover { border-color: var(--ac); background: rgba(255, 102, 0, 0.1); transform: translateY(-1px); }
  &.wide { grid-column: 1 / -1; } }
.card label, .row span, .preview label { color: var(--mut); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; }
.big { font-size: 26px; font-weight: 700; color: var(--ac); font-variant-numeric: tabular-nums; }
.val { font-size: 14px; margin-top: 2px; word-break: break-word; &.na { color: var(--mut); font-style: italic; } }
.src { margin-top: 3px; font-size: 10px; color: var(--mut); }
.note { color: var(--mut); font-size: 11px; margin: 6px 0; }
.reset { width: 100%; margin-top: 14px; }
.row { display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 8px 4px; border-bottom: 1px solid var(--line);
  transition: background 0.15s;
  &:hover { background: rgba(255, 255, 255, 0.04); }
  &.tg { cursor: pointer; pointer-events: auto; &:hover { background: rgba(255, 102, 0, 0.1); span { color: var(--tx); } } }
  &.sub { padding-left: 18px; &.dim { opacity: 0.45; } } }
.sw { width: 30px; height: 16px; border-radius: 9px; background: rgba(255, 255, 255, 0.2); position: relative; flex: none; transition: background 0.2s;
  &:after { content: ""; position: absolute; top: 2px; left: 2px; width: 12px; height: 12px; border-radius: 50%; background: #ccc; transition: transform 0.2s; }
  &.on { background: var(--ac); &:after { transform: translateX(14px); background: #fff; } } }
.seg { display: flex; border: 1px solid var(--line); border-radius: 4px; overflow: hidden;
  button { background: none; border: 0; color: var(--mut); padding: 3px 9px; font: inherit; cursor: pointer; pointer-events: auto; transition: background 0.15s, color 0.15s;
    &:hover { background: rgba(255, 102, 0, 0.2); color: var(--tx); } &.on { background: var(--ac); color: #fff; } } }
.colors { display: flex; align-items: center; gap: 6px; }
.swatch { width: 20px; height: 20px; border-radius: 50%; border: 2px solid rgba(255, 255, 255, 0.25); cursor: pointer; padding: 0; pointer-events: auto; transition: transform 0.15s, border-color 0.15s;
  &:hover { transform: scale(1.2); border-color: #fff; } &.on { border-color: #fff; box-shadow: 0 0 0 2px var(--ac); } }
input[type="color"] { width: 28px; height: 22px; padding: 0; border: 1px solid var(--line); border-radius: 4px; background: none; cursor: pointer; pointer-events: auto; }
.graph svg { width: 100%; height: 56px; margin-top: 6px; polyline { fill: none; stroke: var(--ac); stroke-width: 1.5; vector-effect: non-scaling-stroke; } }
input[type="range"] { width: 140px; accent-color: var(--ac); pointer-events: auto; cursor: pointer; }
.preview { display: flex; align-items: center; justify-content: space-between; padding: 10px 4px;
  .demo { display: inline-flex; align-items: baseline; gap: 5px; padding: 3px 9px; border-radius: 4px; font-weight: 700; font-variant-numeric: tabular-nums;
    &.small { font-size: 14px; } &.medium { font-size: 20px; } &.large { font-size: 30px; } small { font-size: 0.55em; font-weight: 400; opacity: 0.8; } } }
.perfsec { display: flex; flex-direction: column; }
.graph { position: relative; flex: 1; min-height: 170px; padding: 0 !important; margin-bottom: 8px; overflow: visible;
  svg { position: absolute; inset: 0; width: 100%; height: 100% !important; margin: 0 !important; }
  .hline { position: absolute; top: 0; bottom: 0; width: 1px; background: rgba(255, 255, 255, 0.35); pointer-events: none; }
  .hdot { position: absolute; width: 10px; height: 10px; margin: -5px 0 0 -5px; border-radius: 50%; background: var(--ac); border: 2px solid #fff; pointer-events: none; }
  .htip { position: absolute; top: 6px; transform: translateX(10px); padding: 3px 9px; border-radius: 4px; background: rgba(0, 0, 0, 0.85); border: 1px solid var(--ac);
    font-weight: 700; font-variant-numeric: tabular-nums; white-space: nowrap; pointer-events: none; &.flip { transform: translateX(calc(-100% - 10px)); } } }
.kb { min-width: 90px; padding: 3px 10px; text-align: center; border: 1px solid var(--line); border-radius: 4px; background: var(--card); font-variant-numeric: tabular-nums;
  &.listening { border-color: var(--ac); color: var(--ac); } }
.limit { display: flex; align-items: center; gap: 10px; }
.numbox { width: 76px; padding: 3px 6px; font: inherit; text-align: right; color: #fff; background: var(--card); border: 1px solid var(--line); border-radius: 4px; pointer-events: auto;
  &:focus { outline: none; border-color: var(--ac); } }
.row.dim { opacity: 0.5; }
.note.bad { color: #ff7a5c; }
.note.ok { color: #7be0a0; }
.btns { display: flex; gap: 8px; margin-top: 8px; }
em.badge { font-style: normal; margin-left: 6px; }
.badge { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: 0.08em; padding: 2px 7px; border-radius: 3px; border: 1px solid var(--ac); color: var(--ac); }
/* Variante agrandie (fenêtre du menu principal) */
.grnfr.lg { font-size: 18px; background: transparent;
  .tabs { background: rgba(0, 0, 0, 0.45); width: 210px; padding: 12px; gap: 4px; button { gap: 12px; padding: 13px 12px; font-size: 18px; } svg { width: 22px; height: 22px; } }
  section { padding: 22px 30px; }
  h3 { font-size: 15px; margin: 22px 0 6px; }
  .head { font-size: 24px; margin-bottom: 14px; }
  .tagline { font-size: 19px; }
  .grid { gap: 14px; margin-bottom: 14px; }
  .card { padding: 14px 18px; margin-bottom: 14px; border-radius: 6px; }
  .card label, .row span, .preview label { font-size: 14px; }
  .big { font-size: 44px; }
  .val { font-size: 19px; }
  .src { font-size: 13px; }
  .note { font-size: 14px; margin: 10px 0; }
  .row { padding: 12px 6px; gap: 14px; }
  .row.sub { padding-left: 26px; }
  .sw { width: 44px; height: 24px; border-radius: 12px; &:after { width: 18px; height: 18px; top: 3px; left: 3px; } &.on:after { transform: translateX(20px); } }
  .seg button { padding: 6px 14px; font-size: 16px; }
  .swatch { width: 28px; height: 28px; }
  input[type="color"] { width: 40px; height: 30px; }
  input[type="range"] { width: 220px; }
  .graph { min-height: 220px; }
  .kb { min-width: 150px; padding: 6px 14px; }
  .numbox { width: 100px; padding: 6px 8px; font-size: 17px; }
  .preview .demo { padding: 5px 14px; }
  .badge { font-size: 13px; padding: 3px 9px; }
  .welcome { background: rgba(10, 10, 10, 0.85); .w-title { font-size: 44px; } .w-box { max-width: 760px; } .w-btns button { font-size: 20px; padding: 14px 26px; min-width: 190px; } }
}
</style>
