// GRNFR CMP Host : serveur auto-hébergé pour GRNFR Online (relais WebSocket, sans limite de joueurs),
// avec un assistant de configuration (terminal au premier lancement, puis page web React à tout moment).
// Voir host/README.md : ce module n'a pas pu être compilé ni testé dans la session qui l'a écrit.
mod config;
mod httpd;
mod relay;
mod update;

const VERSION: &str = "0.1.0";

#[tokio::main]
async fn main() {
    println!("=== GRNFR CMP Host v{} ===", VERSION);
    let cfg = config::load_or_wizard();
    update::check_for_update(VERSION);

    let http_port = cfg.port.saturating_add(1);
    let http_cfg_port = http_port;
    tokio::spawn(async move {
        httpd::run(http_cfg_port).await;
    });

    relay::run(cfg).await;
}
