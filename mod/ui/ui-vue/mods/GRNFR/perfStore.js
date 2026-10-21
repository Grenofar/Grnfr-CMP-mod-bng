// Mesures FPS partagées par le HUD, la grande fenêtre et la fenêtre du menu : une seule écoute des ticks Lua,
// un historique d'un point par seconde de jeu (moyenne 1 s + FPS instantanés), conservé quand une fenêtre se ferme.
import { reactive } from "vue"
import { useBridge } from "@/bridge"
import { unwrapObj } from "./luaCall.js"
import { createFallback } from "./fpsFallback.js"

export const HIST_MAX = 300 // 5 minutes de jeu

export function getPerf() {
  if (!window.__grnfrPerf) {
    window.__grnfrPerf = reactive({ valid: false, fps: 0, avg: 0, hooks: 0, nTicks: 0, hist: [] })
  }
  return window.__grnfrPerf
}

let started = false
let t0 = 0, lastSec = -1
let handlers = null
const fb = createFallback()

function reset(p) { p.hist.splice(0, p.hist.length); p.valid = false; t0 = 0; lastSec = -1 }

export function startPerfStore() {
  if (started) return
  started = true
  const { events } = useBridge()
  const p = getPerf()
  handlers = {
    tick(d) {
      d = unwrapObj(d)
      if (!d) return
      fb.tick(d)
      p.nTicks++
      if (typeof d.hooks === "number") p.hooks = d.hooks
      p.valid = !!d.valid
      p.fps = Number(d.fps) || 0
      p.avg = Number(d.avg) || 0
      if (!d.valid) return
      const now = performance.now()
      if (!t0) t0 = now
      const sec = Math.floor((now - t0) / 1000)
      if (sec !== lastSec) { // un point par seconde de jeu
        lastSec = sec
        p.hist.push({ t: sec, avg: p.avg, fps: p.fps })
        if (p.hist.length > HIST_MAX) p.hist.shift()
      }
    },
    static(d) {
      d = unwrapObj(d)
      if (!d) return
      if (typeof d.hooks === "number") p.hooks = d.hooks
      if (d.session === false) reset(p) // retour au menu : nouvelle session, nouvel historique
    },
  }
  events.on("GRNFRTick", handlers.tick)
  events.on("GRNFRStatic", handlers.static)
  fb.watch()
}

export function stopPerfStore() {
  if (!started) return
  started = false
  try {
    const { events } = useBridge()
    events.off("GRNFRTick", handlers.tick)
    events.off("GRNFRStatic", handlers.static)
  } catch (e) { /* ignoré */ }
  fb.unwatch()
  handlers = null
}
