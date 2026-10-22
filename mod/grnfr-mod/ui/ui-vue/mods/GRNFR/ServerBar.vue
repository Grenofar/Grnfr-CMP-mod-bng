<template>
  <!-- Bandeau en haut de l'écran, en jeu seulement : serveur actuel et joueurs présents / places. -->
  <div v-if="shown" class="sbar">
    <span class="dot" />
    <span class="name">{{ net.server.name }}</span>
    <span class="sep" />
    <span class="count">{{ count }}/{{ net.server.max_players }}</span>
    <span class="lbl">{{ net.lang === 'en' ? 'players' : 'joueurs' }}</span>
  </div>
</template>

<script setup>
import { computed } from "vue"
import { net } from "./net.js"

// Affiché dès qu'on est dans un serveur ET sur une carte (pas au menu principal).
const shown = computed(() => net.status === "in" && !!net.server && !!net.game.level && net.game.level !== "unknown")
const count = computed(() => (net.players?.length || 0) + 1) // les autres + moi
</script>

<style lang="scss" scoped>
.sbar { position: fixed; top: 8px; left: 50%; transform: translateX(-50%); z-index: 2147482000; display: flex; align-items: center; gap: 8px;
  padding: 4px 16px; color: #fff; background: rgba(10, 10, 10, 0.78); border: 1px solid #ff6600; border-radius: 14px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.5); font: 600 13px/1.2 "Overpass", "Segoe UI", sans-serif; white-space: nowrap;
  pointer-events: none; user-select: none; }
.dot { width: 8px; height: 8px; border-radius: 50%; background: #4ade80; box-shadow: 0 0 6px #4ade80; }
.name { color: #ff6600; }
.sep { width: 1px; height: 14px; background: rgba(255, 102, 0, 0.5); }
.count { font-variant-numeric: tabular-nums; }
.lbl { font-weight: 400; color: rgba(255, 255, 255, 0.7); }
</style>
