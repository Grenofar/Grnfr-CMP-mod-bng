// GRNFR Mod : bouton du menu principal + carte dans l'onglet "Mods" du menu pause.
// La fenêtre du menu principal est montée par GrnfrScreen.vue (slot "mainmenu.top") :
// aucun changement de route/d'écran, donc la souris et le clavier restent actifs.
import { useBridge } from "@/bridge"
import { createApp } from "vue"
import FpsOverlay from "./FpsOverlay.vue"
import HudOverlay from "./HudOverlay.vue"
import OnlineWindow from "./OnlineWindow.vue"
import { initNet, stopNet } from "./net.js"
import { getState } from "./state.js"
import { startPerfStore, stopPerfStore } from "./perfStore.js"

const { events, lua } = useBridge()
const PAUSE_BUTTON_ID = "grnfr-mods-button"
let overlayApp = null
let overlayEl = null
let hudApp = null
let hudEl = null
let onlineApp = null
let onlineEl = null

function addGrnfrButton(addButton) {
  addButton({
    title: "GRNFR Mod",
    iconId: "wrench",
    action: () => { getState().open = true },
  })
}

export async function onLoad() {
  events.on("MainMenuButtons", addGrnfrButton)
  startPerfStore() // historique FPS partagé (HUD, grande fenêtre, menu)
  // Compteur FPS : monté directement dans <body>, indépendant du HUD et des slots
  overlayEl = document.createElement("div")
  overlayEl.id = "grnfr-fps-overlay-root"
  document.body.appendChild(overlayEl)
  overlayApp = createApp(FpsOverlay)
  overlayApp.mount(overlayEl)
  // HUD en jeu (touche K) : monté dans <body>, ne dépend pas de l'app « HUD Apps »
  hudEl = document.createElement("div")
  hudEl.id = "grnfr-hud-root"
  document.body.appendChild(hudEl)
  hudApp = createApp(HudOverlay)
  hudApp.mount(hudEl)
  // GRNFR Online (touche O) : fenêtre de compte / serveurs / garage / marché / taxi / bus
  onlineEl = document.createElement("div")
  onlineEl.id = "grnfr-online-root"
  document.body.appendChild(onlineEl)
  onlineApp = createApp(OnlineWindow)
  onlineApp.mount(onlineEl)
  initNet().catch(e => console.error("[GRNFR] online", e))
  try {
    await lua.extensions.ui_pause_actions.registerModButton({
      id: PAUSE_BUTTON_ID,
      tabId: "mods",
      label: "GRNFR Mod",
      icon: "wrench",
      componentName: "/ui/ui-vue/mods/GRNFR/GrnfrPanel.vue",
    })
  } catch (e) {
    console.error("[GRNFR] bouton de pause non enregistré", e)
  }
}

export async function onUnload() {
  events.off("MainMenuButtons", addGrnfrButton)
  stopPerfStore()
  getState().open = false
  overlayApp?.unmount()
  overlayEl?.remove()
  hudApp?.unmount()
  hudEl?.remove()
  stopNet()
  onlineApp?.unmount()
  onlineEl?.remove()
  overlayApp = overlayEl = hudApp = hudEl = onlineApp = onlineEl = null
  try { await lua.extensions.ui_pause_actions.unregisterModButton(PAUSE_BUTTON_ID) } catch (e) { /* ignoré */ }
}
