// Wrappers typés autour des commandes Tauri (voir src-tauri/src/commands.rs). Un seul point d'entrée pour
// tous les appels invoke() : si une commande change côté Rust, c'est le seul fichier à ajuster côté front.
// Les mises à jour ne passent PAS par ici : voir components/UpdateBanner.tsx (@tauri-apps/plugin-updater).
import { invoke } from "@tauri-apps/api/core"

export interface Player {
  id: number
  username: string
  peer: string
  joined_secs: number
}

export interface ServerStatus {
  id: string
  name: string
  port: number
  has_password: boolean
  running: boolean
  players: Player[]
}

export const api = {
  // null = liste pas encore chargée (toujours en train de contacter Supabase au démarrage)
  listServers: () => invoke<ServerStatus[] | null>("list_servers"),
  createServer: (name: string, password: string | null, port: number) =>
    invoke<ServerStatus>("create_server", { name, password, port }),
  updateServer: (id: string, name: string, password: string | null, port: number) =>
    invoke<void>("update_server", { id, name, password, port }),
  deleteServer: (id: string) => invoke<void>("delete_server", { id }),
  startServer: (id: string) => invoke<void>("start_server", { id }),
  stopServer: (id: string) => invoke<void>("stop_server", { id }),
  kickPlayer: (id: string, clientId: number) => invoke<boolean>("kick_player", { id, clientId }),
}
