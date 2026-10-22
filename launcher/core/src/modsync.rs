// Installation / mise à jour du mod GRNFR CMP dans le dossier mods de BeamNG : lit la dernière release publiée
// (RPC publique get_latest_release, voir supabase/migrations/0004_mod_releases.sql), télécharge le zip depuis le
// bucket public "releases", vérifie son sha256, l'installe sous mods/grnfr-online-v<version>.zip puis supprime les
// autres copies (mods/ et mods/repo/), car deux versions chargées en même temps se marchent dessus.
// Les autres mods du joueur ne sont jamais touchés (seuls les fichiers grnfr-online*.zip).
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const PREFIX: &str = "grnfr-online";
const MAX_ZIP: u64 = 64 << 20;

#[derive(Deserialize, Serialize, Clone, Debug, PartialEq)]
pub struct Release {
    pub version: String,
    pub file_path: String,
    #[serde(default)]
    pub sha256: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct ModStatus {
    pub mods_dir: String,
    /// Fichiers grnfr-online*.zip trouvés (mods/ et mods/repo/).
    pub files: Vec<String>,
    /// Version installée si une seule copie au bon nom, sinon None.
    pub installed: Option<String>,
    pub latest: Option<Release>,
    pub up_to_date: bool,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct InstallReport {
    pub version: String,
    pub path: String,
    pub removed: Vec<String>,
    /// Anciennes copies impossibles à supprimer (souvent : jeu ouvert qui tient le fichier).
    pub failed: Vec<String>,
}

pub fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new().timeout(Duration::from_secs(60)).build()
}

pub fn target_name(version: &str) -> String {
    format!("{}-v{}.zip", PREFIX, version)
}

pub fn installed_files(mods_dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for dir in [mods_dir.to_path_buf(), mods_dir.join("repo")] {
        if let Ok(entries) = fs::read_dir(&dir) {
            for e in entries.flatten() {
                let p = e.path();
                let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("").to_ascii_lowercase();
                if p.is_file() && name.starts_with(PREFIX) && name.ends_with(".zip") {
                    out.push(p);
                }
            }
        }
    }
    out.sort();
    out
}

pub fn version_of(file: &Path) -> Option<String> {
    let name = file.file_name()?.to_str()?;
    let v = name.strip_prefix(&format!("{}-v", PREFIX))?.strip_suffix(".zip")?;
    (!v.is_empty() && v.chars().all(|c| c.is_ascii_digit() || c == '.')).then(|| v.to_string())
}

fn encode_path(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' => (b as char).to_string(),
            _ => format!("%{:02X}", b),
        })
        .collect()
}

pub fn fetch_latest(agent: &ureq::Agent, url: &str, anon_key: &str) -> Result<Option<Release>, String> {
    let url = url.trim_end_matches('/');
    let resp = agent
        .post(&format!("{}/rest/v1/rpc/get_latest_release", url))
        .set("apikey", anon_key)
        .set("Authorization", &format!("Bearer {}", anon_key))
        .set("Content-Type", "application/json")
        .send_string("{}")
        .map_err(|e| format!("lecture de la dernière version impossible : {}", e))?;
    let text = resp.into_string().map_err(|e| format!("réponse illisible : {}", e))?;
    let v: serde_json::Value = serde_json::from_str(&text).map_err(|e| format!("réponse illisible : {}", e))?;
    if v.is_null() {
        return Ok(None);
    }
    serde_json::from_value(v).map(Some).map_err(|e| format!("release illisible : {}", e))
}

pub fn status(mods_dir: &Path, latest: Option<Release>) -> ModStatus {
    let files = installed_files(mods_dir);
    let installed = match files.as_slice() {
        [only] if only.parent() == Some(mods_dir) => version_of(only),
        _ => None,
    };
    let up_to_date = matches!((&installed, &latest), (Some(i), Some(l)) if *i == l.version);
    ModStatus {
        mods_dir: mods_dir.display().to_string(),
        files: files.iter().map(|f| f.display().to_string()).collect(),
        installed,
        latest,
        up_to_date,
    }
}

fn sha256_hex(data: &[u8]) -> String {
    Sha256::digest(data).iter().map(|b| format!("{:02x}", b)).collect()
}

pub fn install(agent: &ureq::Agent, url: &str, mods_dir: &Path, release: &Release) -> Result<InstallReport, String> {
    let url = url.trim_end_matches('/');
    fs::create_dir_all(mods_dir).map_err(|e| format!("dossier mods inaccessible ({}) : {}", mods_dir.display(), e))?;
    let target = mods_dir.join(target_name(&release.version));
    let resp = agent
        .get(&format!("{}/storage/v1/object/public/releases/{}", url, encode_path(&release.file_path)))
        .call()
        .map_err(|e| format!("téléchargement du mod impossible : {}", e))?;
    let mut data = Vec::new();
    resp.into_reader().take(MAX_ZIP + 1).read_to_end(&mut data).map_err(|e| format!("téléchargement coupé : {}", e))?;
    if data.len() as u64 > MAX_ZIP {
        return Err("fichier du mod anormalement gros, refusé".into());
    }
    if let Some(expected) = release.sha256.as_deref().filter(|s| !s.is_empty()) {
        let got = sha256_hex(&data);
        if !got.eq_ignore_ascii_case(expected) {
            return Err(format!("fichier du mod corrompu (sha256 {} au lieu de {}), rien n'a été modifié", &got[..12], &expected[..expected.len().min(12)]));
        }
    }
    let part = mods_dir.join(format!("{}.part", target_name(&release.version)));
    fs::write(&part, &data).map_err(|e| format!("écriture impossible ({}) : {}", part.display(), e))?;
    if target.exists() {
        let _ = fs::remove_file(&target);
    }
    if let Err(e) = fs::rename(&part, &target) {
        let _ = fs::remove_file(&part);
        return Err(format!("installation impossible ({}) : {} — BeamNG est-il ouvert ?", target.display(), e));
    }
    let (mut removed, mut failed) = (Vec::new(), Vec::new());
    for f in installed_files(mods_dir) {
        if f == target {
            continue;
        }
        match fs::remove_file(&f) {
            Ok(()) => removed.push(f.display().to_string()),
            Err(_) => failed.push(f.display().to_string()),
        }
    }
    Ok(InstallReport { version: release.version.clone(), path: target.display().to_string(), removed, failed })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    use tiny_http::{Response, Server};

    const ZIP: &[u8] = b"PK\x03\x04 faux zip du mod";

    fn fake_supabase(sha: &'static str) -> String {
        let server = Server::http("127.0.0.1:0").unwrap();
        let port = server.server_addr().to_ip().unwrap().port();
        thread::spawn(move || {
            for req in server.incoming_requests() {
                let url = req.url().to_string();
                let _ = if url == "/rest/v1/rpc/get_latest_release" {
                    let sha = if sha == "auto" { sha256_hex(ZIP) } else { sha.to_string() };
                    req.respond(Response::from_string(format!(r#"{{"version":"2.1.10","file_path":"grnfr-online-v2.1.10.zip","sha256":"{}","notes":"n"}}"#, sha)))
                } else if url == "/storage/v1/object/public/releases/grnfr-online-v2.1.10.zip" {
                    req.respond(Response::from_data(ZIP.to_vec()))
                } else {
                    req.respond(Response::from_string("not found").with_status_code(404))
                };
            }
        });
        format!("http://127.0.0.1:{}", port)
    }

    fn mods_with_old_copies() -> tempfile::TempDir {
        let t = tempfile::tempdir().unwrap();
        fs::create_dir_all(t.path().join("repo")).unwrap();
        fs::write(t.path().join("grnfr-online-v2.1.8.zip"), "old").unwrap();
        fs::write(t.path().join("repo/grnfr-online-v2.1.9.zip"), "old").unwrap();
        fs::write(t.path().join("autre_mod.zip"), "keep").unwrap();
        fs::write(t.path().join("repo/autre_repo.zip"), "keep").unwrap();
        t
    }

    #[test]
    fn version_lue_dans_le_nom() {
        assert_eq!(version_of(Path::new("/m/grnfr-online-v2.1.10.zip")).as_deref(), Some("2.1.10"));
        assert_eq!(version_of(Path::new("/m/grnfr-online.zip")), None);
        assert_eq!(encode_path("a b/c.zip"), "a%20b/c.zip");
    }

    #[test]
    fn installe_la_derniere_version_et_retire_les_anciennes() {
        let url = fake_supabase("auto");
        let t = mods_with_old_copies();
        let a = agent();
        let latest = fetch_latest(&a, &url, "anon").unwrap().unwrap();
        assert_eq!(latest.version, "2.1.10");
        let before = status(t.path(), Some(latest.clone()));
        assert!(!before.up_to_date && before.installed.is_none() && before.files.len() == 2);

        let r = install(&a, &url, t.path(), &latest).unwrap();
        assert_eq!(fs::read(t.path().join("grnfr-online-v2.1.10.zip")).unwrap(), ZIP);
        assert_eq!(r.removed.len(), 2);
        assert!(r.failed.is_empty());
        assert!(t.path().join("autre_mod.zip").exists() && t.path().join("repo/autre_repo.zip").exists());
        assert!(!t.path().join("grnfr-online-v2.1.10.zip.part").exists());

        let after = status(t.path(), Some(latest.clone()));
        assert_eq!(after.installed.as_deref(), Some("2.1.10"));
        assert!(after.up_to_date);
        // réinstaller par-dessus ne casse rien
        install(&a, &url, t.path(), &latest).unwrap();
        assert!(status(t.path(), Some(latest)).up_to_date);
    }

    #[test]
    fn refuse_un_fichier_corrompu_sans_rien_toucher() {
        let url = fake_supabase("deadbeef");
        let t = mods_with_old_copies();
        let a = agent();
        let latest = fetch_latest(&a, &url, "anon").unwrap().unwrap();
        let err = install(&a, &url, t.path(), &latest).unwrap_err();
        assert!(err.contains("corrompu"), "{}", err);
        assert_eq!(installed_files(t.path()).len(), 2);
        assert!(!t.path().join("grnfr-online-v2.1.10.zip").exists());
    }

    #[test]
    fn serveur_injoignable() {
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        assert!(fetch_latest(&agent(), &format!("http://127.0.0.1:{}", port), "anon").is_err());
    }
}
