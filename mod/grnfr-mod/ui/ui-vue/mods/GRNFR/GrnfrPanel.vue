<template>
  <div class="grnfr" :class="'acc-' + (st.settings?.accent || 'orange')">
    <nav class="tabs">
      <button type="button" v-for="id in tabIds" :key="id" :class="{ on: tab === id }" @click="tab = id">
        <svg viewBox="0 0 24 24"><path :d="icons[id]" /></svg><span>{{ t('tab_' + id) }}</span>
      </button>
    </nav>

    <!-- Comment jouer : onglet de départ (menu pause/principal en particulier), demandé explicitement par
         l'utilisateur -- avant, ce panneau ne parlait que du HUD/FPS, rien sur le jeu en ligne lui-même. -->
    <section v-if="tab === 'help'">
      <div class="head"><b>GRNFR CMP</b><span class="ver">v{{ st.version }}</span></div>
      <p class="note">{{ t('help_intro') }}</p>
      <h3>{{ t('help_join') }}</h3>
      <p class="note">{{ t('help_join_txt') }}</p>
      <h3>{{ t('help_keys') }}</h3>
      <ul class="helplist">
        <li><b>O</b> — {{ t('help_key_o') }}</li>
        <li><b>K</b> — {{ t('help_key_k') }}</li>
      </ul>
      <h3>{{ t('help_launcher') }}</h3>
      <p class="note">{{ t('help_launcher_txt') }}</p>
      <p class="note">{{ t('help_more') }}</p>
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

      <h3>{{ t('opt_title') }}</h3>
      <div class="row tg" @click="setSetting('antiStutter', !st.settings.antiStutter)">
        <span>{{ t('antistutter') }} <em class="badge">{{ t('badge_dev') }}</em></span><i class="sw" :class="{ on: st.settings.antiStutter }"></i>
      </div>
      <p class="note">{{ t('antistutter_note') }}</p>

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
        <div class="w-title">GRNFR CMP</div>
        <p class="note">{{ STRINGS.fr.help_intro }}</p>
        <p class="note">{{ STRINGS.en.help_intro }}</p>
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
import { ref, reactive, computed, onMounted, onBeforeUnmount } from "vue"
import { useBridge } from "@/bridge"
import { BngButton } from "@/common/components/base"
import { callLua, unwrapObj, stats as luaStats } from "./luaCall.js"
import { STRINGS, translate } from "./i18n.js"
import { getPerf } from "./perfStore.js"

const { events } = useBridge()

const tabIds = ["help", "settings", "mods"]
const icons = {
  help: "M12 17h.01M12 8a2.5 2.5 0 112.5 2.5c-.9.9-1.5 1.5-1.5 3M12 3a9 9 0 100 18 9 9 0 000-18z",
  settings: "M4 7h10M18 7h2M4 17h2M10 17h10M14 4v6M6 14v6",
  mods: "M12 3l8 4v10l-8 4-8-4V7z",
}
const positions = ["top-right", "top-left", "bottom-right", "bottom-left"]
const sizes = ["small", "medium", "large"]
const languages = [["fr", "Français"], ["en", "English"]]
const palette = ["#ff6600", "#ffffff", "#4ade80", "#35c6e8", "#f5b942", "#a78bfa"]
const rates = [0, 1, 2, 4, 10]
const accents = ["orange", "cyan", "green", "amber", "violet"]

const tab = ref("help")
// Valeurs par défaut : l'onglet Paramètres s'affiche même si Lua n'a pas (encore) répondu.
const DEFAULTS = {
  antiStutter: false,
  refreshRate: 0, introShown: true, accent: "orange", lang: "fr", langChosen: true,
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
const st = reactive({ version: "—", connected: false, settings: { ...DEFAULTS, ...readCache() } })
const perf = getPerf() // alimente l'aperçu du compteur FPS dans l'onglet Réglages

const previewStyle = computed(() => ({
  color: st.settings?.fpsColor || "#ff6600",
  opacity: st.settings?.fpsOpacity ?? 0.9,
  background: st.settings?.fpsBg === false ? "transparent" : "rgba(0, 0, 0, 0.45)",
}))

const lang = computed(() => st.settings?.lang || "fr")
const t = key => translate(lang.value, key)
const needsLang = computed(() => st.connected && st.settings.langChosen === false)

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
// Taille 100%/100% (et plus une taille fixe en px) : ce panneau est maintenant TOUJOURS embarqué dans un
// conteneur d'une autre page (onglet Réglages de la fenêtre GRNFR CMP, onglet du menu Échap natif du jeu),
// jamais affiché seul dans sa propre fenêtre -- une taille fixe pouvait ne pas remplir ce conteneur et
// laisser apparaître son fond derrière (« noir parasite » signalé par l'utilisateur, 23/10/2026). Hypothèse
// raisonnable mais jamais vérifiée en jeu (pas de capture d'écran du bug) : à revoir si le noir persiste.
.grnfr {
  --card: rgba(0, 0, 0, 0.45); --line: rgba(255, 102, 0, 0.35); --tx: #fff; --mut: rgba(255, 255, 255, 0.6); --ac: #ff6600;
  &.acc-cyan { --ac: #35c6e8; } &.acc-green { --ac: #4ade80; } &.acc-amber { --ac: #f5b942; } &.acc-violet { --ac: #a78bfa; }
  position: relative; display: flex; width: 100%; height: 100%; min-height: 480px; overflow: hidden; background: #0a0a0a;
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
.card { background: var(--card); border: 1px solid var(--line); border-radius: 4px; padding: 8px 10px; margin-bottom: 8px;
  transition: border-color 0.15s, background 0.15s, transform 0.15s;
  &:hover { border-color: var(--ac); background: rgba(255, 102, 0, 0.1); transform: translateY(-1px); }
  &.wide { grid-column: 1 / -1; } }
.card label, .row span, .preview label { color: var(--mut); font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; }
.val { font-size: 14px; margin-top: 2px; word-break: break-word; &.na { color: var(--mut); font-style: italic; } }
.src { margin-top: 3px; font-size: 10px; color: var(--mut); }
.note { color: var(--mut); font-size: 11px; margin: 6px 0; }
.helplist { margin: 4px 0 10px; padding-left: 18px; font-size: 12px; li { margin: 4px 0; } b { color: var(--ac); } }
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
input[type="range"] { width: 140px; accent-color: var(--ac); pointer-events: auto; cursor: pointer; }
.preview { display: flex; align-items: center; justify-content: space-between; padding: 10px 4px;
  .demo { display: inline-flex; align-items: baseline; gap: 5px; padding: 3px 9px; border-radius: 4px; font-weight: 700; font-variant-numeric: tabular-nums;
    &.small { font-size: 14px; } &.medium { font-size: 20px; } &.large { font-size: 30px; } small { font-size: 0.55em; font-weight: 400; opacity: 0.8; } } }
.limit { display: flex; align-items: center; gap: 10px; }
.numbox { width: 76px; padding: 3px 6px; font: inherit; text-align: right; color: #fff; background: var(--card); border: 1px solid var(--line); border-radius: 4px; pointer-events: auto;
  &:focus { outline: none; border-color: var(--ac); } }
.row.dim { opacity: 0.5; }
.note.bad { color: #ff7a5c; }
.note.ok { color: #7be0a0; }
.btns { display: flex; gap: 8px; margin-top: 8px; }
em.badge { font-style: normal; margin-left: 6px; }
.badge { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: 0.08em; padding: 2px 7px; border-radius: 3px; border: 1px solid var(--ac); color: var(--ac); }
</style>
