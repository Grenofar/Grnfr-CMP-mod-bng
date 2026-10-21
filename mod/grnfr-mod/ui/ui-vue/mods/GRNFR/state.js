// État partagé entre index.js (bouton) et GrnfrScreen.vue (fenêtre). Sans effet de bord au chargement.
import { reactive } from "vue"

export function getState() {
  if (!window.__grnfrState) window.__grnfrState = reactive({ open: false })
  return window.__grnfrState
}
