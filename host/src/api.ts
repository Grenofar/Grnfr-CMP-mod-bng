// Wrappers typés autour des commandes Tauri (voir src-tauri/src/commands.rs). Un seul point d'entrée pour
// tous les appels invoke() : si une commande change côté Rust, c'est le seul fichier à ajuster côté front.
import { invoke } from "@tauri-apps/api/core"

export interface Player {
  id: number
  username: string
  peer: string
  joined_secs: number
}

export interface Status {
  configured: boolean | null // null = en cours de vérification (Supabase pas encore interrogé)
  running: boolean
  name: string
  port: number
  has_password: boolean
  players: Player[]
}

export interface LatestRelease {
  tag: string
  asset_name: string
  download_url: string
}

export const api = {
  getStatus: () => invoke<Status>("get_status"),
  startServer: () => invoke<void>("start_server"),
  stopServer: () => invoke<void>("stop_server"),
  kickPlayer: (id: number) => invoke<boolean>("kick_player", { id }),
  saveConfig: (name: string, password: string | null, port: number) =>
    invoke<void>("save_config", { name, password, port }),
  checkUpdate: () => invoke<LatestRelease | null>("check_update"),
  installUpdate: (downloadUrl: string, assetName: string) =>
    invoke<void>("install_update", { downloadUrl, assetName }),
}
