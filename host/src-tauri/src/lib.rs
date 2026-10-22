// GRNFR Host CMP : app native (Tauri — Rust + React/TypeScript, voir host/README.md) pour un serveur
// auto-hébergé GRNFR CMP (relais WebSocket, sans limite de joueurs). Assistant de configuration au premier
// lancement, puis tableau de bord (joueurs connectés, démarrer/arrêter, expulser, mises à jour) dans la
// même fenêtre. La configuration vit dans Supabase (voir supabase.rs), pas dans un fichier local ; pas de
// compte requis.
mod commands;
mod config;
mod logger;
mod relay;
mod supabase;
mod updater;

use tauri::Manager;

use logger::log;
use relay::ServerState;

pub const VERSION: &str = "0.4.0";

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            log(&format!("=== GRNFR Host CMP v{} ===", VERSION));

            let host_id = config::load_or_create_host_id();
            log(&format!("Identifiant de ce host : {}", host_id));

            let state = ServerState::new(config::Config::default());
            app.manage(state.clone());
            app.manage(host_id);

            // Vérifie Supabase pour la config existante (premier lancement = rien trouvé -> assistant côté
            // React) sans bloquer l'ouverture de la fenêtre : le frontend affiche un état "chargement" via
            // get_status().configured == null jusqu'à ce que ceci se termine.
            let bg_state = state.clone();
            tauri::async_runtime::spawn(async move {
                match supabase::fetch_config(host_id).await {
                    Ok(Some(cfg)) => {
                        config::cache_save(&cfg);
                        bg_state.set_config(cfg);
                        bg_state.set_configured(true);
                        if let Err(e) = relay::start(bg_state.clone()).await {
                            log(&format!("Démarrage du relais impossible : {}.", e));
                        }
                    }
                    Ok(None) => {
                        bg_state.set_configured(false);
                    }
                    Err(e) => {
                        log(&format!("Supabase injoignable au démarrage ({}), cache local si possible.", e));
                        match config::cache_load() {
                            Some(cfg) => {
                                bg_state.set_config(cfg);
                                bg_state.set_configured(true);
                                if let Err(e) = relay::start(bg_state.clone()).await {
                                    log(&format!("Démarrage du relais impossible : {}.", e));
                                }
                            }
                            None => bg_state.set_configured(false),
                        }
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_status,
            commands::start_server,
            commands::stop_server,
            commands::kick_player,
            commands::save_config,
            commands::check_update,
            commands::install_update,
        ])
        .run(tauri::generate_context!())
        .expect("erreur au lancement de l'application Tauri");
}
