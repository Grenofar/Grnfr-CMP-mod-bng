// Commandes Tauri (#[tauri::command]) : le pont entre la fenêtre React (invoke()) et l'état Rust (liste des
// serveurs, relais, Supabase). Les mises à jour ne passent pas par ici : le frontend appelle directement
// @tauri-apps/plugin-updater (voir host/src/components/UpdateBanner.tsx), qui a ses propres commandes
// internes enregistrées par le plugin.
use std::sync::Arc;

use serde::Serialize;
use tauri::State;
use uuid::Uuid;

use crate::config::{self, Config};
use crate::relay::{self, ClientSummary, HostState};
use crate::supabase;

#[derive(Serialize)]
pub struct ServerStatus {
    id: Uuid,
    name: String,
    port: u16,
    has_password: bool,
    running: bool,
    players: Vec<ClientSummary>,
}

fn status_of(instance: &Arc<relay::ServerInstance>) -> ServerStatus {
    let cfg = instance.config();
    ServerStatus {
        id: instance.id,
        name: cfg.name,
        port: cfg.port,
        has_password: cfg.password.is_some(),
        running: instance.is_running(),
        players: instance.players(),
    }
}

// None = la liste n'a pas encore pu être chargée depuis Supabase (toujours en cours au démarrage).
#[tauri::command]
pub fn list_servers(state: State<'_, Arc<HostState>>, loaded: State<'_, std::sync::atomic::AtomicBool>) -> Option<Vec<ServerStatus>> {
    if !loaded.load(std::sync::atomic::Ordering::Relaxed) {
        return None;
    }
    Some(state.all().iter().map(status_of).collect())
}

#[tauri::command]
pub async fn create_server(
    name: String,
    password: Option<String>,
    port: u16,
    state: State<'_, Arc<HostState>>,
) -> Result<ServerStatus, String> {
    let cfg = Config { name, password, port };
    let id = supabase::upsert_server(state.host_id, None, &cfg).await?;
    let instance = state.ensure(id, cfg);
    persist_cache(&state);
    relay::start(instance.clone()).await?;
    Ok(status_of(&instance))
}

#[tauri::command]
pub async fn update_server(
    id: Uuid,
    name: String,
    password: Option<String>,
    port: u16,
    state: State<'_, Arc<HostState>>,
) -> Result<(), String> {
    let cfg = Config { name, password, port };
    supabase::upsert_server(state.host_id, Some(id), &cfg).await?;
    if let Some(instance) = state.get(id) {
        instance.set_config(cfg);
    }
    persist_cache(&state);
    Ok(())
}

#[tauri::command]
pub async fn delete_server(id: Uuid, state: State<'_, Arc<HostState>>) -> Result<(), String> {
    supabase::delete_server(state.host_id, id).await?;
    if let Some(instance) = state.remove(id) {
        relay::stop(&instance);
    }
    persist_cache(&state);
    Ok(())
}

#[tauri::command]
pub async fn start_server(id: Uuid, state: State<'_, Arc<HostState>>) -> Result<(), String> {
    let instance = state.get(id).ok_or("not_found")?;
    relay::start(instance).await
}

#[tauri::command]
pub fn stop_server(id: Uuid, state: State<'_, Arc<HostState>>) -> Result<(), String> {
    let instance = state.get(id).ok_or("not_found")?;
    relay::stop(&instance);
    Ok(())
}

#[tauri::command]
pub fn kick_player(id: Uuid, client_id: u64, state: State<'_, Arc<HostState>>) -> Result<bool, String> {
    let instance = state.get(id).ok_or("not_found")?;
    Ok(instance.kick(client_id))
}

fn persist_cache(state: &Arc<HostState>) {
    let servers: Vec<(Uuid, Config)> = state.all().iter().map(|i| (i.id, i.config())).collect();
    config::cache_save(&servers);
}
