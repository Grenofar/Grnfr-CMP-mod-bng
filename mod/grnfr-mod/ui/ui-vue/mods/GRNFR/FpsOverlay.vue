<template>
  <div v-if="visible" class="fps" :class="[pos, size]" :style="boxStyle">
    <span class="num">{{ shown }}</span><span class="unit">FPS</span>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from "vue"
import { useBridge } from "@/bridge"
import { callLua, unwrapObj } from "./luaCall.js"

const { events } = useBridge()
const session = ref(false)
const settings = ref(null)
const shown = ref("—")
let last = 0

const visible = computed(() => session.value && !!settings.value?.fpsOverlay)
const pos = computed(() => settings.value?.fpsPos || "top-right")
const size = computed(() => settings.value?.fpsSize || "medium")
const boxStyle = computed(() => ({
  color: settings.value?.fpsColor || "#ff6600",
  opacity: settings.value?.fpsOpacity ?? 0.9,
  background: settings.value?.fpsBg === false ? "transparent" : "rgba(0, 0, 0, 0.45)",
}))

function onStatic(d) {
  d = unwrapObj(d)
  if (!d) return
  session.value = !!d.session
  if (d.settings) settings.value = d.settings
  if (!d.session) shown.value = "—"
}
function onTick(d) {
  d = unwrapObj(d)
  if (!d || !d.valid) return
  const now = performance.now()
  if (now - last < 900) return // moyenne affichée une fois par seconde
  last = now
  shown.value = Math.round(Number(d.avg) || 0)
}

onMounted(() => {
  events.on("GRNFRStatic", onStatic)
  events.on("GRNFRTick", onTick)
  callLua("requestState", "overlay")
})
onBeforeUnmount(() => {
  events.off("GRNFRStatic", onStatic)
  events.off("GRNFRTick", onTick)
  callLua("uiClosed", "overlay")
})
</script>

<style lang="scss" scoped>
.fps {
  position: fixed; z-index: 2147482000; pointer-events: none; user-select: none;
  display: flex; align-items: baseline; gap: 5px; padding: 3px 9px; border-radius: 4px;
  font-family: "Overpass", "Segoe UI", sans-serif; font-weight: 700; font-variant-numeric: tabular-nums;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.8);
  &.top-right { top: 12px; right: 12px; } &.top-left { top: 12px; left: 12px; }
  &.bottom-right { bottom: 12px; right: 12px; } &.bottom-left { bottom: 12px; left: 12px; }
  &.small { font-size: 14px; } &.medium { font-size: 20px; } &.large { font-size: 30px; }
  .unit { font-size: 0.55em; font-weight: 400; opacity: 0.8; }
}
</style>
