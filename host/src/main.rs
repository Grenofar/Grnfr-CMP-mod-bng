// GRNFR Host CMP : serveur auto-hébergé pour GRNFR CMP (relais WebSocket, sans limite de joueurs),
// avec un assistant de configuration (terminal au premier lancement, puis page web React à tout moment).
// Compile proprement sur Windows/Linux/macOS via la CI (.github/workflows/host-release.yml) ; voir
// host/README.md pour ce qui n'a jamais été vérifié au-delà de la compilation (comportement en vrai usage).
mod config;
mod httpd;
mod relay;
mod update;

const VERSION: &str = "0.1.1";

#[tokio::main]
async fn main() {
    println!("=== GRNFR Host CMP v{} ===", VERSION);
    let cfg = config::load_or_wizard();
    update::check_for_update(VERSION);

    let http_port = cfg.port.saturating_add(1);
    let http_cfg_port = http_port;
    tokio::spawn(async move {
        httpd::run(http_cfg_port).await;
    });

    relay::run(cfg).await;
}
