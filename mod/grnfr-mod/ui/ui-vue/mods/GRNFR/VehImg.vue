<template>
  <!-- Image d'aperçu d'un véhicule (chemin donné par le jeu, ex. /vehicles/pickup/d15.jpg) ; silhouette si absente. -->
  <div class="vimg" :class="{ big }">
    <img v-if="info.preview && !failed" :src="info.preview" alt="" @error="failed = true" />
    <svg v-else viewBox="0 0 64 32"><path d="M6 22h52M10 22l4-8h20l8 6h12a4 4 0 014 4v2H6v-4zM16 26a3 3 0 106 0M44 26a3 3 0 106 0" /></svg>
  </div>
</template>

<script setup>
import { ref, watch } from "vue"
const props = defineProps({ info: { type: Object, default: () => ({}) }, big: Boolean })
const failed = ref(false)
watch(() => props.info.preview, () => { failed.value = false })
</script>

<style lang="scss" scoped>
.vimg { aspect-ratio: 16 / 9; display: flex; align-items: center; justify-content: center; background: linear-gradient(160deg, rgba(255, 255, 255, 0.07), rgba(0, 0, 0, 0.3)); overflow: hidden;
  img { width: 100%; height: 100%; object-fit: cover; display: block; }
  svg { width: 46%; fill: none; stroke: rgba(255, 255, 255, 0.35); stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }
  &.big { width: 300px; flex: none; border-radius: 12px; } }
</style>
