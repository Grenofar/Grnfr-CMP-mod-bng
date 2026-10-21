// Configuration du host : nom, mot de passe (facultatif), port. Pas de nombre de joueurs maximum.
//
// Format de fichier volontairement simple ("clef=valeur", une par ligne) plutôt qu'un format standard
// (TOML/YAML) : ça évite une dépendance de plus dans un projet qui n'a déjà pas pu être compilé pour être
// vérifié (voir host/README.md). Le fichier peut aussi être réécrit par l'assistant web (voir server::http).
use std::fs;
use std::io::{self, Write};
use std::path::Path;

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

fn prompt(label: &str, default: &str) -> String {
    print!("{} [{}] : ", label, default);
    let _ = io::stdout().flush();
    let mut line = String::new();
    if io::stdin().read_line(&mut line).is_err() {
        return default.to_string();
    }
    let line = line.trim();
    if line.is_empty() { default.to_string() } else { line.to_string() }
}

fn prompt_yes_no(label: &str, default_yes: bool) -> bool {
    let d = if default_yes { "o" } else { "n" };
    let ans = prompt(&format!("{} (o/n)", label), d).to_lowercase();
    ans.starts_with('o') || ans.starts_with('y')
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
        "# Config GRNFR Host — modifiable à la main, ou via l'assistant web (voir README).\nname={}\npassword={}\nport={}\n",
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

// Premier lancement : assistant en ligne de commande. Si un fichier de config existe déjà, il est réutilisé
// tel quel (l'assistant web permet de le modifier ensuite sans repasser par le terminal).
pub fn load_or_wizard() -> Config {
    if let Some(cfg) = load() {
        println!("Configuration existante trouvée dans {} : \"{}\" (port {}).", CONFIG_PATH, cfg.name, cfg.port);
        return cfg;
    }
    println!("=== GRNFR CMP Host : premier lancement — assistant de configuration ===");
    let name = prompt("Nom du serveur", &Config::default().name);
    let has_password = prompt_yes_no("Protéger le serveur par un mot de passe ?", false);
    let password = if has_password {
        let p = prompt("Mot de passe", "");
        if p.is_empty() { None } else { Some(p) }
    } else {
        None
    };
    let port_str = prompt("Port d'écoute (WebSocket)", &DEFAULT_PORT.to_string());
    let port: u16 = port_str.parse().unwrap_or(DEFAULT_PORT);
    let cfg = Config { name, password, port };
    if let Err(e) = save(&cfg) {
        eprintln!("Avertissement : configuration non enregistrée ({}). Elle sera redemandée au prochain lancement.", e);
    } else {
        println!("Configuration enregistrée dans {}.", CONFIG_PATH);
    }
    cfg
}
