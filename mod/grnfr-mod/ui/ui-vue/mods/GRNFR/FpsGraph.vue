<template>
  <div class="fg" @mousemove="onMove" @mouseleave="hover = null">
    <div class="plot">
      <svg viewBox="0 0 1000 300" preserveAspectRatio="none"><polyline :points="points" /></svg>
      <i v-for="g in yGrid" :key="'y' + g.v" class="hl" :style="{ top: g.pos + '%' }"><b>{{ g.v }}</b></i>
      <i v-for="g in xGrid" :key="'x' + g.t" class="vl" :style="{ left: g.pos + '%' }"><b>{{ g.label }}</b></i>
      <template v-if="hover">
        <i class="cross" :style="{ left: hover.x + '%' }"></i>
        <i class="dot" :style="{ left: hover.x + '%', top: hover.y + '%' }"></i>
        <span class="tip" :class="{ flip: hover.x > 65 }" :style="{ left: hover.x + '%' }">
          <b>{{ hover.time }}</b>
          <span>{{ labels.avg }} : <em>{{ hover.avg }}</em></span>
          <span>{{ labels.inst }} : <em>{{ hover.fps }}</em></span>
        </span>
      </template>
      <span v-if="!shown.length" class="empty">{{ labels.empty }}</span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from "vue"

const props = defineProps({
  hist: { type: Array, default: () => [] },
  window: { type: Number, default: 120 }, // secondes affichées
  labels: { type: Object, default: () => ({ avg: "Moyenne 1 s", inst: "Instantané", empty: "…" }) },
})
const hover = ref(null)

const shown = computed(() => props.hist.slice(-props.window))
const maxV = computed(() => {
  const m = Math.max(30, ...shown.value.map(p => p.avg))
  const step = m > 200 ? 100 : m > 100 ? 50 : 25
  return Math.ceil(m / step) * step
})
const xOf = i => ((props.window - shown.value.length + i) / (props.window - 1)) * 100 // 0..100 (%)
const yPct = v => (1 - Math.min(Math.max(v / maxV.value, 0), 1)) * 100
const points = computed(() => shown.value.map((p, i) => `${(xOf(i) * 10).toFixed(1)},${(yPct(p.avg) * 3).toFixed(1)}`).join(" "))

const yGrid = computed(() => {
  const out = []
  for (let k = 0; k <= 4; k++) { const v = Math.round((maxV.value / 4) * k); out.push({ v, pos: yPct(v) }) }
  return out
})
const mmss = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`
const xGrid = computed(() => { // un trait vertical toutes les 15 s de jeu, avec l'heure de jeu
  const out = []
  shown.value.forEach((p, i) => { if (p.t % 15 === 0) out.push({ t: p.t, pos: xOf(i), label: mmss(p.t) }) })
  return out
})

function onMove(e) {
  const n = shown.value.length
  const plot = e.currentTarget.querySelector(".plot")
  if (!n || !plot) { hover.value = null; return }
  const r = plot.getBoundingClientRect()
  const off = props.window - n
  const idx = Math.round(((e.clientX - r.left) / r.width) * (props.window - 1)) - off
  if (idx < 0 || idx >= n) { hover.value = null; return }
  const p = shown.value[idx]
  hover.value = { x: xOf(idx), y: yPct(p.avg), time: mmss(p.t), avg: Math.round(p.avg), fps: Math.round(p.fps) }
}
</script>

<style lang="scss" scoped>
.fg { position: relative; width: 100%; height: 100%; padding: 6px 10px 20px 38px; cursor: crosshair; pointer-events: auto; }
.plot { position: relative; width: 100%; height: 100%; border-left: 1px solid rgba(255, 255, 255, 0.35); border-bottom: 1px solid rgba(255, 255, 255, 0.35);
  svg { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible;
    polyline { fill: none; stroke: var(--ac, #ff6600); stroke-width: 1.8; vector-effect: non-scaling-stroke; stroke-linejoin: round; } } }
.hl { position: absolute; left: 0; right: 0; height: 0; border-top: 1px dashed rgba(255, 255, 255, 0.16); pointer-events: none;
  b { position: absolute; right: 100%; margin-right: 6px; transform: translateY(-50%); font-size: 10px; font-weight: 400; color: rgba(255, 255, 255, 0.6); font-variant-numeric: tabular-nums; } }
.vl { position: absolute; top: 0; bottom: 0; width: 0; border-left: 1px dashed rgba(255, 255, 255, 0.12); pointer-events: none;
  b { position: absolute; top: 100%; margin-top: 3px; transform: translateX(-50%); font-size: 10px; font-weight: 400; color: rgba(255, 255, 255, 0.6); font-variant-numeric: tabular-nums; } }
.cross { position: absolute; top: 0; bottom: 0; width: 1px; background: rgba(255, 255, 255, 0.45); pointer-events: none; }
.dot { position: absolute; width: 10px; height: 10px; margin: -5px 0 0 -5px; border-radius: 50%; background: var(--ac, #ff6600); border: 2px solid #fff; pointer-events: none; }
.tip { position: absolute; top: 4px; transform: translateX(12px); display: flex; flex-direction: column; gap: 1px; padding: 4px 10px; border-radius: 4px; z-index: 3;
  background: rgba(0, 0, 0, 0.88); border: 1px solid var(--ac, #ff6600); font-size: 12px; white-space: nowrap; pointer-events: none; color: #fff;
  b { color: var(--ac, #ff6600); } em { font-style: normal; font-weight: 700; font-variant-numeric: tabular-nums; }
  &.flip { transform: translateX(calc(-100% - 12px)); } }
.empty { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; color: rgba(255, 255, 255, 0.5); font-size: 12px; pointer-events: none; }
</style>
