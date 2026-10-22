// Configuration d'UN serveur : nom, mot de passe (facultatif), port. Pas de nombre de joueurs maximum.
// Une installation peut avoir plusieurs serveurs (voir relay::HostState) ; chacun a sa propre Config.
//
// La liste des serveurs vit dans Supabase (voir supabase.rs et
// supabase/migrations/0012_host_multi_server.sql), pas dans un fichier local. Pas de compte joueur requis :
// au premier lancement, un identifiant aléatoire (UUID v4) est généré et gardé dans grnfr-host.id, à côté de
// l'exécutable — connaître cet identifiant suffit à lire/écrire TOUS les serveurs de CETTE installation
// (sécurité "limitée, pas infaillible", voir le commentaire de la migration 0012). Un petit cache local
// (grnfr-host.cache, JSON) garde la dernière liste connue pour pouvoir démarrer même hors ligne ; toujours
// écrasé par ce qui vient de Supabase quand c'est possible.
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

// Identifiant stable de cette installation : généré une seule fois, puis toujours relu (jamais régénéré
// tant que le fichier existe), pour toujours retrouver les mêmes serveurs dans Supabase entre deux
// lancements.
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

#[derive(Serialize, Deserialize)]
struct CachedServer {
    id: Uuid,
    #[serde(flatten)]
    config: Config,
}

pub fn cache_load() -> Option<Vec<(Uuid, Config)>> {
    if !Path::new(CACHE_PATH).exists() {
        return None;
    }
    let content = fs::read_to_string(CACHE_PATH).ok()?;
    let list: Vec<CachedServer> = serde_json::from_str(&content).ok()?;
    Some(list.into_iter().map(|c| (c.id, c.config)).collect())
}

pub fn cache_save(servers: &[(Uuid, Config)]) {
    let list: Vec<CachedServer> = servers.iter().map(|(id, cfg)| CachedServer { id: *id, config: cfg.clone() }).collect();
    if let Ok(json) = serde_json::to_string_pretty(&list) {
        let _ = fs::write(CACHE_PATH, json);
    }
}
