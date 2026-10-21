// GRNFR Host CMP : app native (egui/eframe — pas de HTML, pas de serveur web local) pour un serveur
// auto-hébergé GRNFR CMP (relais WebSocket, sans limite de joueurs). Assistant de configuration au premier
// lancement, puis tableau de bord (joueurs connectés, démarrer/arrêter, expulser, mises à jour) — tout dans
// la même fenêtre native (voir gui.rs). La configuration est stockée dans Supabase, pas dans un fichier
// local (voir supabase.rs et supabase/migrations/0011_host_config.sql) ; pas de compte requis.
// Compile proprement sur Windows/Linux/macOS via la CI (.github/workflows/host-release.yml) ; voir
// host/README.md pour ce qui n'a jamais été vérifié au-delà de la compilation (comportement en vrai usage).
#![windows_subsystem = "windows"] // Windows : pas de fenêtre console (sans effet sur Linux/macOS).

mod config;
mod gui;
mod logger;
mod relay;
mod supabase;
mod updater;

use eframe::egui;
use logger::log;
use relay::ServerState;

pub const VERSION: &str = "0.3.0";

fn main() {
    log(&format!("=== GRNFR Host CMP v{} ===", VERSION));

    // Le relais WebSocket (async, tokio) tourne sur un runtime dédié, dans un thread séparé : la fenêtre
    // native (egui) a besoin du thread principal pour elle-même (obligatoire sur macOS).
    let rt = tokio::runtime::Builder::new_multi_thread().enable_all().build().expect("impossible de créer le runtime tokio");
    let handle = rt.handle().clone();
    std::thread::spawn(move || {
        rt.block_on(std::future::pending::<()>());
    });

    let host_id = config::load_or_create_host_id();
    log(&format!("Identifiant de ce host : {}", host_id));

    let (loaded_cfg, configured) = match supabase::fetch_config(host_id) {
        Ok(Some(cfg)) => {
            config::cache_save(&cfg);
            (cfg, true)
        }
        Ok(None) => (config::Config::default(), false), // premier lancement : rien enregistré encore dans Supabase
        Err(e) => {
            log(&format!("Supabase injoignable au démarrage ({}), utilisation du cache local si disponible.", e));
            match config::cache_load() {
                Some(cfg) => (cfg, true),
                None => (config::Config::default(), false),
            }
        }
    };

    let state = ServerState::new(loaded_cfg.clone());
    if configured {
        if let Err(e) = handle.block_on(relay::start(state.clone())) {
            log(&format!("Démarrage du relais impossible : {}.", e));
        }
    }

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([540.0, 680.0]),
        ..Default::default()
    };
    let current_tag = format!("host-v{}", VERSION);
    let result = eframe::run_native(
        "GRNFR Host CMP",
        options,
        Box::new(move |_cc| Box::new(gui::HostApp::new(state, handle, host_id, loaded_cfg, configured, current_tag))),
    );
    if let Err(e) = result {
        log(&format!("Impossible d'ouvrir la fenêtre : {}.", e));
    }
}
