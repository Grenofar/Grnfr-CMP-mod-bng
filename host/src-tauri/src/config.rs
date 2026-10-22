// Configuration du host : nom, mot de passe (facultatif), port. Pas de nombre de joueurs maximum.
//
// La config vit dans Supabase (voir supabase.rs et supabase/migrations/0011_host_config.sql), pas dans un
// fichier local. Pas de compte joueur requis : au premier lancement, un identifiant aléatoire (UUID v4) est
// généré et gardé dans grnfr-host.id, à côté de l'exécutable — connaître cet identifiant suffit à lire/écrire
// CETTE config (sécurité "limitée, pas infaillible", voir le commentaire de la migration 0011). Un petit
// cache local (grnfr-host.cache) garde la dernière config connue pour pouvoir démarrer même hors ligne ;
// toujours écrasé par ce qui vient de Supabase quand c'est possible.
use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const HOST_ID_PATH: &str = "grnfr-host.id";
const CACHE_PATH: &str = "grnfr-host.cache";
pub const DEFAULT_PORT: u16 = 30814;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
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

// Identifiant stable de ce host : généré une seule fois, puis toujours relu (jamais régénéré tant que le
// fichier existe), pour toujours retrouver la même ligne dans Supabase entre deux lancements.
pub fn load_or_create_host_id() -> Uuid {
    if let Ok(s) = fs::read_to_string(HOST_ID_PATH) {
        if let Ok(id) = Uuid::parse_str(s.trim()) {
            return id;
        }
    }
    let id = Uuid::new_v4();
    let _ = fs::write(HOST_ID_PATH, id.to_string());
    id
}

pub fn cache_load() -> Option<Config> {
    if !Path::new(CACHE_PATH).exists() {
        return None;
    }
    let content = fs::read_to_string(CACHE_PATH).ok()?;
    let mut cfg = Config::default();
    for line in content.lines() {
        let line = line.trim();
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
    Some(cfg)
}

pub fn cache_save(cfg: &Config) {
    let content = format!(
        "# Copie locale de la config (voir Supabase pour la source de vérité) — utilisée si hors ligne.\nname={}\npassword={}\nport={}\n",
        cfg.name,
        cfg.password.clone().unwrap_or_default(),
        cfg.port
    );
    let _ = fs::write(CACHE_PATH, content);
}
