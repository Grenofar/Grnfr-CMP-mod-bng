// Vérifie la dernière release GitHub (host-vX.Y.Z) et peut télécharger + installer le nouveau binaire à la
// place du binaire en cours d'exécution.
//
// ⚠️ Jamais testé en conditions réelles sur AUCUN OS : impossible à vérifier sans pouvoir exécuter le
// binaire dans cette session (voir host/README.md) — seule la compilation est garantie par la CI. Le
// remplacement repose sur un comportement connu mais non garanti partout : renommer un exécutable EN COURS
// D'EXÉCUTION est autorisé par Windows/Linux/macOS (contrairement à le supprimer ou l'écraser en place) ;
// c'est pour ça que l'ancien binaire est renommé en .bak (gardé, pas supprimé) avant que le nouveau prenne
// sa place — en cas d'échec, on peut toujours relancer .bak à la main.
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::logger::log;

const RELEASES_API: &str = "https://api.github.com/repos/Grenofar/Grnfr-CMP-mod-bng/releases/latest";

#[cfg(target_os = "windows")]
const ASSET_NAME: &str = "grnfr-host-windows.exe";
#[cfg(target_os = "macos")]
const ASSET_NAME: &str = "grnfr-host-macos";
#[cfg(all(unix, not(target_os = "macos")))]
const ASSET_NAME: &str = "grnfr-host-linux";

#[derive(Clone)]
pub struct LatestRelease {
    pub tag: String,
    pub download_url: String,
}

// current_tag : "host-vX.Y.Z" (même format que les tags Git qui déclenchent la CI).
pub fn check_latest(current_tag: &str) -> Option<LatestRelease> {
    let client = reqwest::blocking::Client::builder()
        .user_agent("grnfr-host")
        .timeout(Duration::from_secs(8))
        .build()
        .ok()?;
    let resp = client.get(RELEASES_API).send().ok()?;
    if !resp.status().is_success() {
        return None;
    }
    let v: serde_json::Value = resp.json().ok()?;
    let tag = v.get("tag_name").and_then(|x| x.as_str())?.to_string();
    if tag == current_tag {
        return None;
    }
    let assets = v.get("assets").and_then(|a| a.as_array())?;
    let asset = assets.iter().find(|a| a.get("name").and_then(|n| n.as_str()) == Some(ASSET_NAME))?;
    let download_url = asset.get("browser_download_url").and_then(|u| u.as_str())?.to_string();
    Some(LatestRelease { tag, download_url })
}

fn sibling(exe: &Path, suffix: &str) -> PathBuf {
    let name = exe.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    exe.with_file_name(format!("{}.{}", name, suffix))
}

pub fn download_and_install(download_url: &str) -> Result<(), String> {
    let current = std::env::current_exe().map_err(|e| e.to_string())?;
    let new_path = sibling(&current, "new");
    let bak_path = sibling(&current, "bak");

    log(&format!("Mise à jour : téléchargement de {}...", download_url));
    let bytes = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .map_err(|e| e.to_string())?
        .get(download_url)
        .send()
        .map_err(|e| e.to_string())?
        .bytes()
        .map_err(|e| e.to_string())?;
    {
        let mut f = fs::File::create(&new_path).map_err(|e| e.to_string())?;
        f.write_all(&bytes).map_err(|e| e.to_string())?;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&new_path, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    }

    let _ = fs::remove_file(&bak_path); // sauvegarde d'une mise à jour précédente, si elle est restée
    fs::rename(&current, &bak_path).map_err(|e| format!("impossible de mettre l'ancien binaire de côté : {}", e))?;
    fs::rename(&new_path, &current).map_err(|e| format!("impossible d'installer le nouveau binaire : {}", e))?;
    log("Mise à jour installée, relance...");
    std::process::Command::new(&current).spawn().map_err(|e| e.to_string())?;
    std::process::exit(0);
}
