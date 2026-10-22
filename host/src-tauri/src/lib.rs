// GRNFR Host CMP : app native (Tauri — Rust + React/TypeScript, voir host/README.md) pour des serveurs
// auto-hébergés GRNFR CMP (relais WebSocket, sans limite de joueurs). Plusieurs serveurs par installation,
// chacun démarrable/arrêtable indépendamment — plusieurs peuvent tourner EN MÊME TEMPS. La liste vit dans
// Supabase (voir supabase.rs), pas dans un fichier local ; pas de compte requis. Les mises à jour passent
// par le plugin officiel tauri-plugin-updater (signé), pas par du code maison — voir host/README.md.
mod commands;
mod config;
mod logger;
mod relay;
mod supabase;

use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use tauri::Manager;

use logger::log;
use relay::HostState;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_process::init())
        .setup(|app| {
            // L'updater s'enregistre ici (pas chaîné sur Builder comme process) : c'est le patron officiel
            // (voir https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/updater/README.md),
            // nécessaire pour pouvoir l'exclure proprement sur mobile si ce projet en avait un jour.
            #[cfg(desktop)]
            app.handle().plugin(tauri_plugin_updater::Builder::new().build())?;

            log(&format!("=== GRNFR Host CMP v{} ===", VERSION));

            let host_id = config::load_or_create_host_id();
            log(&format!("Identifiant de cette installation : {}", host_id));

            let state = HostState::new(host_id);
            app.manage(state.clone());
            app.manage(AtomicBool::new(false)); // "loaded" : la liste initiale a-t-elle fini de se charger ?

            // Charge la liste des serveurs depuis Supabase (ou le cache local si hors ligne) sans bloquer
            // l'ouverture de la fenêtre : list_servers() renvoie None côté frontend tant que ceci n'a pas
            // fini (affiche un état "chargement"), puis la vraie liste (vide = assistant de création).
            let bg_state = state.clone();
            let app_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let servers = match supabase::list_servers(host_id).await {
                    Ok(list) => {
                        let pairs: Vec<(uuid::Uuid, config::Config)> = list.iter().map(|r| (r.id, r.config.clone())).collect();
                        config::cache_save(&pairs);
                        list.into_iter().map(|r| (r.id, r.config)).collect::<Vec<_>>()
                    }
                    Err(e) => {
                        log(&format!("Supabase injoignable au démarrage ({}), cache local si possible.", e));
                        config::cache_load().unwrap_or_default()
                    }
                };

                for (id, cfg) in servers {
                    let instance = bg_state.ensure(id, cfg);
                    if let Err(e) = relay::start(instance).await {
                        log(&format!("Démarrage automatique du serveur {} impossible : {}.", id, e));
                    }
                }

                if let Some(loaded) = app_handle.try_state::<AtomicBool>() {
                    loaded.store(true, std::sync::atomic::Ordering::Relaxed);
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_servers,
            commands::create_server,
            commands::update_server,
            commands::delete_server,
            commands::start_server,
            commands::stop_server,
            commands::kick_player,
            commands::live_servers,
            commands::level_roads,
        ])
        .run(tauri::generate_context!())
        .expect("erreur au lancement de l'application Tauri");
}
