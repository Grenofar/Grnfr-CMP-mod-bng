// Secours : si aucune mesure n'arrive de Lua pendant 1,5 s, l'UI appelle grnfr.uiPoll() à chaque image
// (Lua mesure alors la durée avec un chronomètre). Lua répond 'hooks' si ses hooks de rendu fonctionnent : le secours s'arrête alors.
import { callLua } from "./luaCall.js"

export function createFallback() {
  let last = performance.now(), timer = null, raf = 0, running = false, busy = false, disabled = false
  async function step() {
    if (!running) return
    if (!busy) {
      busy = true
      const r = await callLua("uiPoll")
      busy = false
      if (r === "hooks") { disabled = true; stop() }
    }
    if (running) raf = requestAnimationFrame(step)
  }
  function start() {
    if (running || disabled || window.__grnfrPollOwner) return
    window.__grnfrPollOwner = true; running = true; step()
  }
  function stop() {
    if (running) window.__grnfrPollOwner = false
    running = false; cancelAnimationFrame(raf)
  }
  return {
    // à appeler à chaque tick reçu (les ticks issus du secours lui-même, d.poll, ne comptent pas)
    tick(d) { if (d && d.poll) return; last = performance.now(); stop() },
    watch() { if (timer) return; last = performance.now(); timer = setInterval(() => { if (performance.now() - last > 1500) start() }, 1000) },
    unwatch() { clearInterval(timer); timer = null; stop() },
  }
}
