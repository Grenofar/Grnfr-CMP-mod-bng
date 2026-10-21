// GRNFR Host CMP : serveur auto-hébergé pour GRNFR CMP (relais WebSocket, sans limite de joueurs),
// avec un assistant de configuration (terminal au premier lancement, puis page web React à tout moment).
// Compile proprement sur Windows/Linux/macOS via la CI (.github/workflows/host-release.yml) ; voir
// host/README.md pour ce qui n'a jamais été vérifié au-delà de la compilation (comportement en vrai usage).
mod config;
mod httpd;
mod relay;
mod update;

use relay::ServerState;

const VERSION: &str = "0.2.0";

#[tokio::main]
async fn main() {
    println!("=== GRNFR Host CMP v{} ===", VERSION);
    let cfg = config::load_or_wizard();
    update::check_for_update(VERSION);

    let http_port = cfg.port.saturating_add(1);
    let state = ServerState::new(cfg);
    // Démarré tout de suite (comme avant) ; le tableau de bord web peut ensuite l'arrêter/le relancer
    // (par ex. après avoir changé le port) sans fermer ce programme.
    if let Err(e) = relay::start(state.clone()).await {
        eprintln!("Démarrage du relais impossible : {}.", e);
    }

    httpd::run(http_port, state).await;
}
