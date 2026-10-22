// Petit journal fichier (grnfr-host.log, à côté de l'exécutable) : sur Windows il n'y a pas de console
// (voir main.rs), donc println!/eprintln! ne vont nulle part de visible pour l'utilisateur. Ce module
// écrit aussi dans un fichier pour qu'il reste possible de diagnostiquer un problème sans console.
use std::fs::OpenOptions;
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn log(msg: &str) {
    println!("{}", msg);
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open("grnfr-host.log") {
        let _ = writeln!(f, "[{}] {}", secs, msg);
    }
}
