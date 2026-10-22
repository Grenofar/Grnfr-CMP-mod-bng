import { invoke } from "@tauri-apps/api/core"

// Miroir des types Rust de launcher/core (app.rs, settings.rs, modsync.rs, launch.rs).
export type LaunchMode = "steam" | "direct" | "beammp"

export interface Settings {
  wizard_done: boolean
  mode: LaunchMode
  beamng_exe: string | null
  beammp_exe: string | null
  mods_dir: string | null
  auto_update_mod: boolean
}

export interface Status {
  version: string
  server_configured: boolean
  relay_ok: boolean
  relay_addr: string
  relay_error: string | null
  requests: number
  errors: number
  last: string
}

export interface Detected {
  beamng: string | null
  beammp: string | null
  mods_dir: string | null
}

export interface Release {
  version: string
  file_path: string
  sha256: string | null
  notes: string | null
}

export interface ModStatus {
  mods_dir: string
  files: string[]
  installed: string | null
  latest: Release | null
  up_to_date: boolean
}

export interface InstallReport {
  version: string
  path: string
  removed: string[]
  failed: string[]
}

export interface LaunchReport {
  mode: LaunchMode
  installed: InstallReport | null
  warning: string | null
}

export const api = {
  status: () => invoke<Status>("get_status"),
  settings: () => invoke<Settings>("get_settings"),
  saveSettings: (settings: Settings) => invoke<void>("save_settings", { settings }),
  detect: () => invoke<Detected>("detect"),
  modStatus: () => invoke<ModStatus>("mod_status"),
  installMod: () => invoke<InstallReport>("install_mod"),
  launch: () => invoke<LaunchReport>("launch"),
}

export const MODES: { id: LaunchMode; label: string; help: string }[] = [
  { id: "steam", label: "BeamNG via Steam", help: "Le plus simple : Steam lance le jeu. Aucun chemin à indiquer." },
  { id: "direct", label: "BeamNG direct", help: "Lance l'exécutable de BeamNG directement (sans passer par Steam)." },
  { id: "beammp", label: "BeamNG avec BeamMP", help: "Lance BeamMP Launcher, qui démarre BeamNG avec le multijoueur BeamMP." },
]
