// GRNFR CMP : un seul bouton dans le menu principal + son propre onglet "GRNFR CMP" dans le menu pause
// (registerModTab, pas imbriqué dans l'onglet générique "Mods" du jeu).
// Un seul point d'entrée : le bouton ouvre directement la fenêtre GRNFR CMP (OnlineWindow, la même qu'avec
// la touche O), qui a maintenant son propre onglet Réglages (GrnfrPanel, embarqué).
import { useBridge } from "@/bridge"
import { createApp } from "vue"
import FpsOverlay from "./FpsOverlay.vue"
import OnlineWindow from "./OnlineWindow.vue"
import QuickPanel from "./QuickPanel.vue"
import ServerBar from "./ServerBar.vue"
import Tablet from "./Tablet.vue"
import { initNet, stopNet, ui } from "./net.js"
import { startPerfStore, stopPerfStore } from "./perfStore.js"

const { events, lua } = useBridge()
const PAUSE_BUTTON_ID = "grnfr-mods-button"
const PAUSE_TAB_ID = "grnfr"
let overlayApp = null
let overlayEl = null
let onlineApp = null
let onlineEl = null
let quickApp = null
let quickEl = null
let barApp = null
let barEl = null
let tabApp = null
let tabEl = null

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
  startPerfStore() // historique FPS partagé (compteur, menu pause, onglet Réglages)
  // Compteur FPS : monté directement dans <body>, indépendant des slots
  overlayEl = document.createElement("div")
  overlayEl.id = "grnfr-fps-overlay-root"
  document.body.appendChild(overlayEl)
  overlayApp = createApp(FpsOverlay)
  overlayApp.mount(overlayEl)
  // GRNFR Online (touche O) : fenêtre de compte / serveurs / garage / marché / taxi / bus
  onlineEl = document.createElement("div")
  onlineEl.id = "grnfr-online-root"
  document.body.appendChild(onlineEl)
  onlineApp = createApp(OnlineWindow)
  onlineApp.mount(onlineEl)
  // Téléphone (touche K) : chat de serveur, joueurs, taxi, repère, argent, échange, courses de drag
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
  // Tablette du garage (touche O devant son garage) : garage, joueurs, échanges, concession, annonces, travail
  tabEl = document.createElement("div")
  tabEl.id = "grnfr-tablet-root"
  document.body.appendChild(tabEl)
  tabApp = createApp(Tablet)
  tabApp.mount(tabEl)
  initNet().catch(e => console.error("[GRNFR] online", e))
  // Son propre onglet dans le menu pause (pas imbriqué dans l'onglet générique "Mods" du jeu) : demandé
  // explicitement par l'utilisateur (« quand on appuie sur Échap, que ça soit GRNFR CMP et plus "Mod" ») --
  // registerModTab (API publique du jeu, lua/ge/extensions/ui/pause/actions.lua) crée un vrai onglet à son nom.
  try {
    await lua.extensions.ui_pause_actions.registerModTab({ id: PAUSE_TAB_ID, label: "GRNFR CMP", icon: "wrench" })
    await lua.extensions.ui_pause_actions.registerModButton({
      id: PAUSE_BUTTON_ID,
      tabId: PAUSE_TAB_ID,
      label: "GRNFR CMP",
      icon: "wrench",
      componentName: "/ui/ui-vue/mods/GRNFR/GrnfrPanel.vue",
    })
  } catch (e) {
    console.error("[GRNFR] onglet de pause non enregistré", e)
  }
}

export async function onUnload() {
  events.off("MainMenuButtons", addGrnfrButton)
  stopPerfStore()
  overlayApp?.unmount()
  overlayEl?.remove()
  stopNet()
  onlineApp?.unmount()
  onlineEl?.remove()
  quickApp?.unmount()
  quickEl?.remove()
  barApp?.unmount()
  barEl?.remove()
  tabApp?.unmount()
  tabEl?.remove()
  overlayApp = overlayEl = onlineApp = onlineEl = quickApp = quickEl = barApp = barEl = tabApp = tabEl = null
  try { await lua.extensions.ui_pause_actions.unregisterModButton(PAUSE_BUTTON_ID) } catch (e) { /* ignoré */ }
  try { await lua.extensions.ui_pause_actions.unregisterModTab(PAUSE_TAB_ID) } catch (e) { /* ignoré */ }
}
