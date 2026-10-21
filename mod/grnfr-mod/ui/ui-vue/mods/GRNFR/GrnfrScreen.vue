<template>
  <!-- Monté dans le menu principal (slot) ; la fenêtre est téléportée dans <body> -->
  <Teleport to="body">
    <div v-if="state.open" class="grnfr-screen" id="grnfr-screen-root" @click.self="close">
      <div class="window">
        <header>
          <span class="title">GRNFR Mod</span>
          <BngButton @click="close">Retour</BngButton>
        </header>
        <GrnfrPanel class="body lg" />
      </div>
    </div>
  </Teleport>
</template>

<script>
const modInfo = {
  uiSlots: ["mainmenu.top"],
}
</script>

<script setup>
import { watch, onBeforeUnmount } from "vue"
import { BngButton } from "@/common/components/base"
import GrnfrPanel from "./GrnfrPanel.vue"
import { getState } from "./state.js"

const state = getState()

// La fenêtre ne s'ouvre JAMAIS toute seule : uniquement quand on clique sur « GRNFR Mod » dans le menu principal.
function close() { state.open = false }
function onKey(e) { if (e.key === "Escape") close() }

// Masque l'interface de BeamNG (boutons, menus) mais garde les grandes images/vidéos de fond (diaporama).
// Heuristique, non vérifiée sur la structure réelle de l'UI : tout est restauré à la fermeture.
const HIDE_ATTR = "data-grnfr-hide"
let hideStyle = null
function hideBehind() {
  try {
    if (!hideStyle) {
      hideStyle = document.createElement("style")
      hideStyle.textContent = `[${HIDE_ATTR}]{visibility:hidden !important;}`
      document.head.appendChild(hideStyle)
    }
    const W = window.innerWidth, H = window.innerHeight
    const all = Array.from(document.body.querySelectorAll("*"))
    const keep = new Set()
    for (const el of all) {
      if (el.closest("#grnfr-screen-root, #grnfr-fps-overlay-root")) { keep.add(el); continue }
      const tag = el.tagName
      if (tag === "STYLE" || tag === "SCRIPT") continue
      const r = el.getBoundingClientRect()
      if (r.width < W * 0.8 || r.height < H * 0.8) continue
      const media = tag === "IMG" || tag === "VIDEO" || tag === "CANVAS"
      if (media || getComputedStyle(el).backgroundImage !== "none") {
        keep.add(el)
        for (let a = el.parentElement; a && a !== document.body; a = a.parentElement) keep.add(a)
      }
    }
    for (const el of all) {
      if (!keep.has(el) && el.tagName !== "STYLE" && el.tagName !== "SCRIPT") el.setAttribute(HIDE_ATTR, "")
    }
  } catch (e) { console.error("[GRNFR] masquage de l'interface impossible", e) }
}
function showBehind() {
  try { document.querySelectorAll("[" + HIDE_ATTR + "]").forEach(el => el.removeAttribute(HIDE_ATTR)) } catch (e) { /* ignoré */ }
}

watch(() => state.open, open => {
  if (open) { window.addEventListener("keydown", onKey); hideBehind() }
  else { window.removeEventListener("keydown", onKey); showBehind() }
}, { immediate: true })

onBeforeUnmount(() => {
  window.removeEventListener("keydown", onKey)
  showBehind()
  state.open = false
})
</script>

<style lang="scss" scoped>
.grnfr-screen {
  position: fixed; inset: 0; z-index: 2147483000; display: flex; align-items: center; justify-content: center;
  background: transparent; pointer-events: auto;
}
.window {
  display: flex; flex-direction: column; width: min(1640px, 96vw); height: min(940px, 94vh);
  background: rgba(10, 10, 10, 0.7); border: 1px solid #ff6600; border-radius: 6px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.7); overflow: hidden; pointer-events: auto;
  :deep(*) { pointer-events: auto; }
}
header {
  display: flex; align-items: center; justify-content: space-between; padding: 10px 18px;
  background: rgba(0, 0, 0, 0.5); border-bottom: 2px solid #ff6600; color: #fff;
  font: 600 24px "Overpass", "Segoe UI", sans-serif;
  .title { color: #ff6600; }
}
.window .body { flex: 1; width: 100% !important; height: auto !important; min-height: 0; max-width: none !important; }
</style>
