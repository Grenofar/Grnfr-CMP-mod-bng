// Configuration du host : nom, mot de passe (facultatif), port. Pas de nombre de joueurs maximum.
//
// Plus d'assistant en ligne de commande (il demandait une console, que le binaire Windows n'ouvre plus
// depuis v0.2.0 — voir main.rs) : au premier lancement, les valeurs par défaut sont enregistrées tout de
// suite, et tout se règle depuis le tableau de bord web (voir httpd.rs) à l'adresse affichée dans le log.
//
// Format de fichier volontairement simple ("clef=valeur", une par ligne) plutôt qu'un format standard
// (TOML/YAML) : ça évite une dépendance de plus dans un projet qui n'a déjà pas pu être compilé pour être
// vérifié (voir host/README.md).
use std::fs;
use std::io;
use std::path::Path;

use crate::logger::log;

pub const CONFIG_PATH: &str = "grnfr-host.cfg";
pub const DEFAULT_PORT: u16 = 30814;

#[derive(Clone, Debug)]
pub struct Config {
    pub name: String,
    pub password: Option<String>,
    pub port: u16,
}

impl Default for Config {
    fn default() -> Self {
        Config { name: "Serveur GRNFR".to_string(), password: None, port: DEFAULT_PORT }
    }
}

pub fn parse(content: &str) -> Config {
    let mut cfg = Config::default();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        if let Some((k, v)) = line.split_once('=') {
            let v = v.trim();
            match k.trim() {
                "name" => cfg.name = v.to_string(),
                "password" => cfg.password = if v.is_empty() { None } else { Some(v.to_string()) },
                "port" => { if let Ok(p) = v.parse::<u16>() { cfg.port = p; } }
                _ => {}
            }
        }
    }
    cfg
}

pub fn to_string(cfg: &Config) -> String {
    format!(
        "# Config GRNFR Host CMP — modifiable à la main, ou via le tableau de bord web (voir README).\nname={}\npassword={}\nport={}\n",
        cfg.name,
        cfg.password.clone().unwrap_or_default(),
        cfg.port
    )
}

pub fn save(cfg: &Config) -> io::Result<()> {
    fs::write(CONFIG_PATH, to_string(cfg))
}

pub fn load() -> Option<Config> {
    if !Path::new(CONFIG_PATH).exists() {
        return None;
    }
    fs::read_to_string(CONFIG_PATH).ok().map(|s| parse(&s))
}

// Premier lancement : valeurs par défaut, enregistrées tout de suite (modifiables depuis le tableau de bord
// web — voir httpd.rs — sans jamais avoir besoin d'un terminal).
pub fn load_or_wizard() -> Config {
    if let Some(cfg) = load() {
        log(&format!("Configuration existante trouvée dans {} : \"{}\" (port {}).", CONFIG_PATH, cfg.name, cfg.port));
        return cfg;
    }
    let cfg = Config::default();
    if let Err(e) = save(&cfg) {
        log(&format!("Avertissement : configuration non enregistrée ({}). Valeurs par défaut utilisées pour cette fois.", e));
    } else {
        log(&format!("Première exécution : configuration par défaut enregistrée dans {} (port {}). Modifiable depuis le tableau de bord web.", CONFIG_PATH, cfg.port));
    }
    cfg
}
