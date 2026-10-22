// Logique de l'app, indépendante de Tauri (src-tauri/src/lib.rs ne fait qu'exposer ces méthodes en commandes) :
// état du relais, réglages, détection sur la machine, état / installation du mod, lancement du jeu.
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;

use serde::Serialize;

use crate::detect;
use crate::launch::{self, LaunchMode};
use crate::modsync::{self, InstallReport, ModStatus};
use crate::proxy::{self, Proxy};
use crate::settings::{self, Settings};

pub struct ServerInfo {
    pub url: Option<String>,
    pub anon_key: Option<String>,
}

pub struct Launcher {
    settings_path: PathBuf,
    settings: Mutex<Settings>,
    relay: Result<Proxy, String>,
    server: ServerInfo,
    version: String,
}

#[derive(Serialize, Debug)]
pub struct Status {
    pub version: String,
    pub server_configured: bool,
    pub relay_ok: bool,
    pub relay_addr: String,
    pub relay_error: Option<String>,
    pub requests: u64,
    pub errors: u64,
    pub last: String,
}

#[derive(Serialize, Debug, Default, PartialEq)]
pub struct Detected {
    pub beamng: Option<String>,
    pub beammp: Option<String>,
    pub mods_dir: Option<String>,
}

#[derive(Serialize, Debug)]
pub struct LaunchReport {
    pub mode: LaunchMode,
    /// Installation du mod faite juste avant (si réglage actif et mod pas à jour).
    pub installed: Option<InstallReport>,
    /// Problème non bloquant (mise à jour du mod impossible...) : le jeu est quand même lancé.
    pub warning: Option<String>,
}

fn s(p: PathBuf) -> String {
    p.display().to_string()
}

impl Launcher {
    pub fn new(settings_path: PathBuf, server: ServerInfo, version: &str, relay_addr: &str) -> Launcher {
        let relay = match server.url.as_deref().filter(|u| !u.is_empty()) {
            None => Err("Cette version du launcher a été compilée sans l'adresse du serveur GRNFR CMP.".to_string()),
            Some(url) => proxy::start(relay_addr, url, version).map_err(|e| {
                if e.contains("in use") || e.contains("utilis") || e.contains("10048") {
                    format!("{} — le launcher est peut-être déjà ouvert.", e)
                } else {
                    e
                }
            }),
        };
        let settings = settings::load(&settings_path);
        Launcher { settings_path, settings: Mutex::new(settings), relay, server, version: version.to_string() }
    }

    pub fn status(&self) -> Status {
        let (requests, errors, last) = self.relay.as_ref().map(|p| p.stats.snapshot()).unwrap_or_default();
        Status {
            version: self.version.clone(),
            server_configured: self.server.url.is_some() && self.server.anon_key.is_some(),
            relay_ok: self.relay.is_ok(),
            relay_addr: self.relay.as_ref().map(|p| p.addr.to_string()).unwrap_or_default(),
            relay_error: self.relay.as_ref().err().cloned(),
            requests,
            errors,
            last,
        }
    }

    pub fn settings(&self) -> Settings {
        self.settings.lock().map(|s| s.clone()).unwrap_or_default()
    }

    pub fn save_settings(&self, s: Settings) -> Result<(), String> {
        settings::save(&self.settings_path, &s)?;
        if let Ok(mut cur) = self.settings.lock() {
            *cur = s;
        }
        Ok(())
    }

    /// Ce qu'on trouve sur cette machine (sans toucher aux réglages).
    pub fn detect(&self) -> Detected {
        detect_with(&SystemPaths::from_env())
    }

    fn mods_dir(&self) -> Result<PathBuf, String> {
        let st = self.settings();
        st.mods_dir
            .filter(|d| !d.trim().is_empty())
            .map(PathBuf::from)
            .or_else(|| self.detect().mods_dir.map(PathBuf::from))
            .ok_or_else(|| "Dossier mods de BeamNG introuvable : lancez BeamNG une fois, ou indiquez-le dans les réglages.".to_string())
    }

    fn server(&self) -> Result<(&str, &str), String> {
        match (self.server.url.as_deref(), self.server.anon_key.as_deref()) {
            (Some(u), Some(k)) if !u.is_empty() && !k.is_empty() => Ok((u, k)),
            _ => Err("Launcher compilé sans l'adresse du serveur : impossible de vérifier le mod.".to_string()),
        }
    }

    pub fn mod_status(&self) -> Result<ModStatus, String> {
        let dir = self.mods_dir()?;
        let (url, key) = self.server()?;
        let latest = modsync::fetch_latest(&modsync::agent(), url, key)?;
        Ok(modsync::status(&dir, latest))
    }

    pub fn install_mod(&self) -> Result<InstallReport, String> {
        let dir = self.mods_dir()?;
        let (url, key) = self.server()?;
        let a = modsync::agent();
        let latest = modsync::fetch_latest(&a, url, key)?.ok_or_else(|| "Aucune version du mod publiée pour l'instant.".to_string())?;
        modsync::install(&a, url, &dir, &latest)
    }

    pub fn launch(&self) -> Result<LaunchReport, String> {
        let st = self.settings();
        let cmd = launch::plan(st.mode, &st, cfg!(windows))?;
        let (mut installed, mut warning) = (None, None);
        if st.auto_update_mod {
            match self.mod_status() {
                Ok(ms) if ms.up_to_date => {}
                Ok(_) => match self.install_mod() {
                    Ok(r) => {
                        if !r.failed.is_empty() {
                            warning = Some(format!("Anciennes versions du mod non supprimées (BeamNG ouvert ?) : {}", r.failed.join(", ")));
                        }
                        installed = Some(r);
                    }
                    Err(e) => warning = Some(format!("Mise à jour du mod impossible, lancement quand même : {}", e)),
                },
                Err(e) => warning = Some(format!("Vérification du mod impossible, lancement quand même : {}", e)),
            }
        }
        spawn(&cmd).map_err(|e| format!("Lancement impossible ({}) : {}", cmd.program.display(), e))?;
        Ok(LaunchReport { mode: st.mode, installed, warning })
    }
}

fn spawn(cmd: &launch::LaunchCmd) -> std::io::Result<()> {
    let mut c = Command::new(&cmd.program);
    c.args(&cmd.args);
    if let Some(d) = &cmd.cwd {
        c.current_dir(d);
    }
    #[cfg(windows)]
    {
        // Pas de fenêtre console pour `cmd /C start steam://...` (le jeu, lui, ouvre sa propre fenêtre).
        use std::os::windows::process::CommandExt;
        if cmd.program.as_os_str() == "cmd" {
            c.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
        }
    }
    c.spawn().map(|_| ())
}

/// Emplacements système utiles à la détection (variables d'environnement Windows + registre Steam).
#[derive(Default)]
pub struct SystemPaths {
    pub steam_roots: Vec<PathBuf>,
    pub appdata: Option<PathBuf>,
    pub local_appdata: Option<PathBuf>,
    pub program_files: Vec<PathBuf>,
}

impl SystemPaths {
    pub fn from_env() -> SystemPaths {
        let env = |k: &str| std::env::var_os(k).map(PathBuf::from);
        let mut steam_roots: Vec<PathBuf> = Vec::new();
        if let Some(p) = steam_from_registry() {
            steam_roots.push(p);
        }
        let program_files: Vec<PathBuf> = ["ProgramFiles(x86)", "ProgramFiles"].iter().filter_map(|k| env(k)).collect();
        for pf in &program_files {
            steam_roots.push(pf.join("Steam"));
        }
        if let Some(home) = env("HOME") {
            steam_roots.push(home.join(".steam/steam"));
            steam_roots.push(home.join(".local/share/Steam"));
        }
        SystemPaths { steam_roots, appdata: env("APPDATA"), local_appdata: env("LOCALAPPDATA"), program_files }
    }
}

fn steam_from_registry() -> Option<PathBuf> {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        let out = Command::new("reg")
            .args(["query", r"HKCU\Software\Valve\Steam", "/v", "SteamPath"])
            .creation_flags(0x0800_0000)
            .output()
            .ok()?;
        return detect::parse_reg_steam_path(&String::from_utf8_lossy(&out.stdout));
    }
    #[allow(unreachable_code)]
    None
}

pub fn detect_with(p: &SystemPaths) -> Detected {
    Detected {
        beamng: detect::find_beamng(&p.steam_roots).map(s),
        beammp: detect::first_existing(&detect::beammp_candidates(p.appdata.as_deref(), p.local_appdata.as_deref(), &p.program_files)).map(s),
        mods_dir: p.local_appdata.as_deref().and_then(detect::find_mods_dir).map(s),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::Path;

    fn launcher(dir: &Path, url: Option<&str>) -> Launcher {
        Launcher::new(dir.join("settings.json"), ServerInfo { url: url.map(String::from), anon_key: Some("anon".into()) }, "0.1.0", "127.0.0.1:0")
    }

    #[test]
    fn relais_actif_quand_le_serveur_est_configure() {
        let t = tempfile::tempdir().unwrap();
        let l = launcher(t.path(), Some("https://example.supabase.co"));
        let st = l.status();
        assert!(st.relay_ok && st.server_configured && st.relay_addr.starts_with("127.0.0.1:"));
        let l2 = launcher(t.path(), None);
        assert!(!l2.status().relay_ok && l2.status().relay_error.unwrap().contains("compilée sans"));
    }

    #[test]
    fn port_deja_pris_message_clair() {
        let t = tempfile::tempdir().unwrap();
        let busy = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = busy.local_addr().unwrap().to_string();
        let l = Launcher::new(t.path().join("s.json"), ServerInfo { url: Some("https://x.supabase.co".into()), anon_key: Some("k".into()) }, "1", &addr);
        assert!(!l.status().relay_ok);
        assert!(l.status().relay_error.unwrap().contains(&addr));
    }

    #[test]
    fn reglages_sauves_et_relus() {
        let t = tempfile::tempdir().unwrap();
        let l = launcher(t.path(), Some("https://example.supabase.co"));
        let mut s = l.settings();
        s.wizard_done = true;
        s.mode = LaunchMode::Beammp;
        l.save_settings(s.clone()).unwrap();
        assert_eq!(launcher(t.path(), Some("https://example.supabase.co")).settings(), s);
    }

    #[test]
    fn detection_complete_sur_une_fausse_machine() {
        let t = tempfile::tempdir().unwrap();
        let steam = t.path().join("PF86/Steam");
        let game = steam.join("steamapps/common/BeamNG.drive");
        fs::create_dir_all(&game).unwrap();
        fs::write(game.join("BeamNG.drive.exe"), "").unwrap();
        let mp = t.path().join("Roaming/BeamMP-Launcher/BeamMP-Launcher.exe");
        fs::create_dir_all(mp.parent().unwrap()).unwrap();
        fs::write(&mp, "").unwrap();
        fs::create_dir_all(t.path().join("Local/BeamNG/BeamNG.drive/current")).unwrap();
        let d = detect_with(&SystemPaths {
            steam_roots: vec![steam],
            appdata: Some(t.path().join("Roaming")),
            local_appdata: Some(t.path().join("Local")),
            program_files: vec![t.path().join("PF86")],
        });
        assert_eq!(d.beamng, Some(s(game.join("BeamNG.drive.exe"))));
        assert_eq!(d.beammp, Some(s(mp)));
        assert_eq!(d.mods_dir, Some(s(t.path().join("Local/BeamNG/BeamNG.drive/current/mods"))));
        assert_eq!(detect_with(&SystemPaths::default()), Detected::default());
    }

    #[cfg(unix)]
    #[test]
    fn lance_vraiment_l_executable_choisi() {
        use std::os::unix::fs::PermissionsExt;
        let t = tempfile::tempdir().unwrap();
        let marker = t.path().join("lance.txt");
        let exe = t.path().join("BeamNG.drive.exe");
        fs::write(&exe, format!("#!/bin/sh\necho ok > '{}'\n", marker.display())).unwrap();
        fs::set_permissions(&exe, fs::Permissions::from_mode(0o755)).unwrap();
        let l = launcher(t.path(), Some("https://example.supabase.co"));
        let mut st = l.settings();
        st.mode = LaunchMode::Direct;
        st.beamng_exe = Some(s(exe));
        st.auto_update_mod = false;
        l.save_settings(st).unwrap();
        let r = l.launch().unwrap();
        assert!(r.warning.is_none() && r.installed.is_none());
        for _ in 0..50 {
            if marker.exists() { break; }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert!(marker.exists(), "le programme n'a pas été lancé");
    }

    #[test]
    fn lancement_refuse_si_chemin_absent() {
        let t = tempfile::tempdir().unwrap();
        let l = launcher(t.path(), Some("https://example.supabase.co"));
        let mut st = l.settings();
        st.mode = LaunchMode::Beammp;
        l.save_settings(st).unwrap();
        assert!(l.launch().unwrap_err().contains("BeamMP Launcher"));
    }
}
