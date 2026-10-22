// GRNFR CMP : un seul bouton dans le menu principal + une carte dans l'onglet "Mods" du menu pause.
// Un seul point d'entrée : le bouton ouvre directement la fenêtre GRNFR CMP (OnlineWindow, la même qu'avec
// la touche O), qui a maintenant son propre onglet Réglages (GrnfrPanel, embarqué).
import { useBridge } from "@/bridge"
import { createApp } from "vue"
import FpsOverlay from "./FpsOverlay.vue"
import HudOverlay from "./HudOverlay.vue"
import OnlineWindow from "./OnlineWindow.vue"
import QuickPanel from "./QuickPanel.vue"
import ServerBar from "./ServerBar.vue"
import { initNet, stopNet, ui } from "./net.js"
import { startPerfStore, stopPerfStore } from "./perfStore.js"

const { events, lua } = useBridge()
const PAUSE_BUTTON_ID = "grnfr-mods-button"
let overlayApp = null
let overlayEl = null
let hudApp = null
let hudEl = null
let onlineApp = null
let onlineEl = null
let quickApp = null
let quickEl = null
let barApp = null
let barEl = null

function addGrnfrButton(addButton) {
  // Un seul bouton : ouvre la fenêtre GRNFR CMP (comptes, serveurs, garage... et réglages). Fonctionne depuis
  // le menu principal, avant même de charger une carte. La fenêtre choisit elle-même un onglet de départ
  // raisonnable (langue si jamais choisie, sinon compte si pas connecté, sinon serveurs).
  addButton({
    title: "GRNFR CMP",
    iconId: "wrench",
    action: () => { ui("window.open") },
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
  // Fenêtre rapide (touche J) : chat de serveur, joueurs, repère, argent, échange, courses de drag
  quickEl = document.createElement("div")
  quickEl.id = "grnfr-quick-root"
  document.body.appendChild(quickEl)
  quickApp = createApp(QuickPanel)
  quickApp.mount(quickEl)
  // Bandeau du serveur (haut de l'écran) : nom du serveur et joueurs présents / places
  barEl = document.createElement("div")
  barEl.id = "grnfr-serverbar-root"
  document.body.appendChild(barEl)
  barApp = createApp(ServerBar)
  barApp.mount(barEl)
  initNet().catch(e => console.error("[GRNFR] online", e))
  try {
    await lua.extensions.ui_pause_actions.registerModButton({
      id: PAUSE_BUTTON_ID,
      tabId: "mods",
      label: "GRNFR CMP",
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
  overlayApp?.unmount()
  overlayEl?.remove()
  hudApp?.unmount()
  hudEl?.remove()
  stopNet()
  onlineApp?.unmount()
  onlineEl?.remove()
  quickApp?.unmount()
  quickEl?.remove()
  barApp?.unmount()
  barEl?.remove()
  overlayApp = overlayEl = hudApp = hudEl = onlineApp = onlineEl = quickApp = quickEl = barApp = barEl = null
  try { await lua.extensions.ui_pause_actions.unregisterModButton(PAUSE_BUTTON_ID) } catch (e) { /* ignoré */ }
}
