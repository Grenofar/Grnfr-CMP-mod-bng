// Commandes Tauri (#[tauri::command]) : le pont entre la fenêtre React (invoke()) et l'état Rust
// (ServerState, Supabase, mise à jour). Voir host/src/api.ts côté frontend pour les wrappers typés.
use std::sync::Arc;

use serde::Serialize;
use tauri::State;
use uuid::Uuid;

use crate::config::{self, Config};
use crate::relay::{self, ClientSummary, ServerState};
use crate::supabase;
use crate::updater::{self, LatestRelease};

#[derive(Serialize)]
pub struct StatusPayload {
    configured: Option<bool>,
    running: bool,
    name: String,
    port: u16,
    has_password: bool,
    players: Vec<ClientSummary>,
}

#[tauri::command]
pub fn get_status(state: State<'_, Arc<ServerState>>) -> StatusPayload {
    let cfg = state.config();
    StatusPayload {
        configured: state.configured(),
        running: state.is_running(),
        name: cfg.name,
        port: cfg.port,
        has_password: cfg.password.is_some(),
        players: state.players(),
    }
}

#[tauri::command]
pub async fn start_server(state: State<'_, Arc<ServerState>>) -> Result<(), String> {
    relay::start(state.inner().clone()).await
}

#[tauri::command]
pub fn stop_server(state: State<'_, Arc<ServerState>>) {
    relay::stop(state.inner());
}

#[tauri::command]
pub fn kick_player(state: State<'_, Arc<ServerState>>, id: u64) -> bool {
    state.kick(id)
}

#[tauri::command]
pub async fn save_config(
    name: String,
    password: Option<String>,
    port: u16,
    state: State<'_, Arc<ServerState>>,
    host_id: State<'_, Uuid>,
) -> Result<(), String> {
    let cfg = Config { name, password, port };
    supabase::save_config(*host_id.inner(), &cfg).await?;
    config::cache_save(&cfg);
    state.set_config(cfg);
    state.set_configured(true);
    Ok(())
}

#[tauri::command]
pub async fn check_update() -> Option<LatestRelease> {
    updater::check_latest(&format!("host-v{}", crate::VERSION)).await
}

#[tauri::command]
pub async fn install_update(download_url: String, asset_name: String) -> Result<(), String> {
    updater::download_and_run_installer(&download_url, &asset_name).await
}
