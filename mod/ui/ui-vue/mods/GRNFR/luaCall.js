// Appel UI -> Lua. Plusieurs chemins sont essayés dans l'ordre, car le pont de BeamNG renvoie des objets intermédiaires
// (proxys) dont on ne peut pas tester le type :
//   1) lua.extensions.grnfr / lua.grnfr  (la valeur renvoyée par Lua est récupérée) ;
//   2) api.engineLua("extensions.grnfr.xxx(...)")  (appel classique, sans valeur de retour attendue) ;
//   3) chargement de l'extension puis nouvel essai du chemin 1.
// Toutes les fonctions Lua appelées renvoient une valeur (true/false/état) pour qu'un appel réussi se termine toujours.
import { reactive } from "vue"
import { useBridge } from "@/bridge"

// Compteurs d'appels UI -> Lua (diagnostic affiché dans l'interface)
export const stats = reactive({ ok: 0, fail: 0, last: "", via: "" })
const note = msg => { stats.last = String(msg).slice(0, 140) }

function withTimeout(p, ms) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("timeout")), ms)
    Promise.resolve(p).then(v => { clearTimeout(t); resolve(v) }, e => { clearTimeout(t); reject(e) })
  })
}

function lit(v) {
  if (v === null || v === undefined) return "nil"
  if (typeof v === "string") return JSON.stringify(v)
  if (typeof v === "number") return Number.isFinite(v) ? String(v) : "nil"
  if (typeof v === "boolean") return String(v)
  return "nil"
}

function viaEngineLua(bridge, fn, args) {
  const api = bridge.api ?? (typeof window !== "undefined" ? window.bngApi : undefined)
  if (api == null) throw new Error("engineLua indisponible")
  const code = "extensions.grnfr." + fn + "(" + args.map(lit).join(",") + ")"
  return new Promise((resolve, reject) => {
    let done = false
    const fin = v => { if (!done) { done = true; resolve(v) } }
    setTimeout(() => fin(undefined), 800) // la commande est partie : inutile d'attendre un résultat
    try {
      const r = api.engineLua(code, fin)
      if (r && typeof r.then === "function") r.then(fin, e => { if (!done) { done = true; reject(e) } })
    } catch (e) { if (!done) { done = true; reject(e) } }
  })
}

export async function callLua(fn, ...args) {
  let bridge
  try { bridge = useBridge() } catch (e) { stats.fail++; note("bridge: " + (e?.message || e)); return }
  const lua = bridge.lua
  const routes = [() => lua?.extensions?.grnfr, () => lua?.grnfr]
  const tryProxy = async () => {
    for (const route of routes) {
      try {
        const ext = route()
        if (ext == null) continue
        const r = await withTimeout(ext[fn](...args), 2000)
        stats.ok++; stats.via = "lua"
        return { r }
      } catch (e) { note(fn + " (lua): " + (e?.message || e)) }
    }
    return null
  }
  let res = await tryProxy()
  if (res) return res.r
  try {
    const r = await viaEngineLua(bridge, fn, args)
    stats.ok++; stats.via = "engineLua"
    return r
  } catch (e) { note(fn + " (engineLua): " + (e?.message || e)) }
  try { await lua?.extensions?.load?.("grnfr") } catch (e) { note("load: " + (e?.message || e)) }
  res = await tryProxy()
  if (res) return res.r
  stats.fail++
}

// Les données de guihooks peuvent arriver telles quelles, dans un tableau d'arguments ou dans { data }.
export function unwrapObj(d) {
  if (Array.isArray(d) && d.length && d[0] && typeof d[0] === "object" && !Array.isArray(d[0])) d = d[0]
  if (d && typeof d === "object" && !Array.isArray(d) && d.data && typeof d.data === "object" && !("settings" in d) && !("valid" in d)) d = d.data
  return d
}
export function unwrapList(d) {
  if (Array.isArray(d) && d.length === 1 && Array.isArray(d[0])) d = d[0]
  if (d && !Array.isArray(d) && Array.isArray(d.data)) d = d.data
  return d
}
