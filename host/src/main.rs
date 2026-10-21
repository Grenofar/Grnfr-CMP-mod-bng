// GRNFR Host CMP : serveur auto-hébergé pour GRNFR CMP (relais WebSocket, sans limite de joueurs), piloté
// entièrement par un tableau de bord web (React) qui s'ouvre tout seul au démarrage — plus de console
// Windows ni d'assistant en ligne de commande (voir host/README.md).
// Compile proprement sur Windows/Linux/macOS via la CI (.github/workflows/host-release.yml) ; voir
// host/README.md pour ce qui n'a jamais été vérifié au-delà de la compilation (comportement en vrai usage).
#![windows_subsystem = "windows"] // Windows : pas de fenêtre console (sans effet sur Linux/macOS).

mod config;
mod httpd;
mod logger;
mod relay;
mod update;

use std::process::Command;

use logger::log;
use relay::ServerState;

const VERSION: &str = "0.2.1";

#[tokio::main]
async fn main() {
    log(&format!("=== GRNFR Host CMP v{} ===", VERSION));
    let cfg = config::load_or_wizard();
    update::check_for_update(VERSION);

    let http_port = cfg.port.saturating_add(1);
    let state = ServerState::new(cfg);
    // Démarré tout de suite (comme avant) ; le tableau de bord web peut ensuite l'arrêter/le relancer
    // (par ex. après avoir changé le port) sans fermer ce programme.
    if let Err(e) = relay::start(state.clone()).await {
        log(&format!("Démarrage du relais impossible : {}.", e));
    }

    open_dashboard(http_port);
    httpd::run(http_port, state).await;
}

// Pas de console pour afficher l'adresse du tableau de bord (voir windows_subsystem ci-dessus) : on ouvre
// directement le navigateur par défaut dessus, sur chaque OS. Un échec ici n'empêche pas le programme de
// continuer (l'adresse reste visible dans grnfr-host.log).
fn open_dashboard(http_port: u16) {
    let url = format!("http://127.0.0.1:{}", http_port);
    log(&format!("Tableau de bord : {}", url));
    tokio::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_millis(400)).await;
        let result = if cfg!(target_os = "windows") {
            Command::new("cmd").args(["/C", "start", "", url.as_str()]).spawn()
        } else if cfg!(target_os = "macos") {
            Command::new("open").arg(&url).spawn()
        } else {
            Command::new("xdg-open").arg(&url).spawn()
        };
        if let Err(e) = result {
            log(&format!("Impossible d'ouvrir le navigateur automatiquement ({}) : ouvrez {} vous-même.", e, url));
        }
    });
}
