// Vérifie la dernière release GitHub (host-vX.Y.Z) et peut télécharger l'installeur correspondant à l'OS
// courant puis le lancer (l'utilisateur termine l'installation via l'assistant natif de son OS : NSIS sur
// Windows, .dmg sur macOS, .AppImage sur Linux — ce ne sont plus de simples binaires portables depuis le
// passage à Tauri, donc plus d'auto-remplacement silencieux en place comme avant : chaque OS a son propre
// mécanisme d'installation, pas un seul fichier à renommer).
//
// ⚠️ Jamais testé en conditions réelles sur AUCUN OS : impossible à vérifier sans pouvoir exécuter
// l'application dans cette session (voir host/README.md) — seule la compilation est garantie par la CI.
use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use serde::Serialize;

use crate::logger::log;

const RELEASES_API: &str = "https://api.github.com/repos/Grenofar/Grnfr-CMP-mod-bng/releases/latest";

// Les noms exacts des fichiers embarquent la version (ex. "GRNFR Host CMP_0.4.0_x64-setup.exe") : on
// reconnaît donc l'actif à télécharger par son EXTENSION plutôt que par un nom fixe.
#[cfg(target_os = "windows")]
fn matches_asset(name: &str) -> bool { name.ends_with(".exe") }
#[cfg(target_os = "macos")]
fn matches_asset(name: &str) -> bool { name.ends_with(".dmg") }
#[cfg(all(unix, not(target_os = "macos")))]
fn matches_asset(name: &str) -> bool { name.ends_with(".AppImage") }

#[derive(Serialize, Clone)]
pub struct LatestRelease {
    pub tag: String,
    pub asset_name: String,
    pub download_url: String,
}

// current_tag : "host-vX.Y.Z" (même format que les tags Git qui déclenchent la CI).
pub async fn check_latest(current_tag: &str) -> Option<LatestRelease> {
    let client = reqwest::Client::builder()
        .user_agent("grnfr-host")
        .timeout(Duration::from_secs(8))
        .build()
        .ok()?;
    let resp = client.get(RELEASES_API).send().await.ok()?;
    if !resp.status().is_success() {
        return None;
    }
    let v: serde_json::Value = resp.json().await.ok()?;
    let tag = v.get("tag_name").and_then(|x| x.as_str())?.to_string();
    if tag == current_tag {
        return None;
    }
    let assets = v.get("assets").and_then(|a| a.as_array())?;
    let asset = assets.iter().find(|a| a.get("name").and_then(|n| n.as_str()).map(matches_asset).unwrap_or(false))?;
    let asset_name = asset.get("name").and_then(|n| n.as_str())?.to_string();
    let download_url = asset.get("browser_download_url").and_then(|u| u.as_str())?.to_string();
    Some(LatestRelease { tag, asset_name, download_url })
}

// Télécharge l'installeur dans un dossier temporaire puis le lance (l'utilisateur termine l'installation
// lui-même : fenêtre NSIS sur Windows, Finder/.dmg sur macOS, l'AppImage se relance directement sur Linux).
pub async fn download_and_run_installer(download_url: &str, asset_name: &str) -> Result<(), String> {
    log(&format!("Mise à jour : téléchargement de {}...", download_url));
    let bytes = reqwest::Client::builder()
        .timeout(Duration::from_secs(180))
        .build()
        .map_err(|e| e.to_string())?
        .get(download_url)
        .send()
        .await
        .map_err(|e| e.to_string())?
        .bytes()
        .await
        .map_err(|e| e.to_string())?;

    let dest: PathBuf = std::env::temp_dir().join(asset_name);
    fs::write(&dest, &bytes).map_err(|e| e.to_string())?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&dest, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    }

    log(&format!("Installeur téléchargé dans {} — lancement...", dest.display()));
    open_path(&dest)?;
    Ok(())
}

#[cfg(target_os = "windows")]
fn open_path(p: &std::path::Path) -> Result<(), String> {
    std::process::Command::new("cmd").args(["/C", "start", "", &p.to_string_lossy()]).spawn().map_err(|e| e.to_string())?;
    Ok(())
}
#[cfg(target_os = "macos")]
fn open_path(p: &std::path::Path) -> Result<(), String> {
    std::process::Command::new("open").arg(p).spawn().map_err(|e| e.to_string())?;
    Ok(())
}
#[cfg(all(unix, not(target_os = "macos")))]
fn open_path(p: &std::path::Path) -> Result<(), String> {
    std::process::Command::new(p).spawn().map_err(|e| e.to_string())?;
    Ok(())
}
