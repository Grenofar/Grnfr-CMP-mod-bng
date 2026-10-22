// Réglages du launcher, en JSON dans le dossier de config de l'app. Fichier absent ou abîmé -> réglages par défaut
// (et l'assistant se relance), jamais de plantage.
use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::launch::LaunchMode;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default)]
pub struct Settings {
    pub wizard_done: bool,
    pub mode: LaunchMode,
    pub beamng_exe: Option<String>,
    pub beammp_exe: Option<String>,
    pub mods_dir: Option<String>,
    /// Installer / mettre à jour le mod GRNFR CMP automatiquement avant chaque lancement.
    pub auto_update_mod: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { wizard_done: false, mode: LaunchMode::Steam, beamng_exe: None, beammp_exe: None, mods_dir: None, auto_update_mod: true }
    }
}

pub fn load(path: &Path) -> Settings {
    fs::read_to_string(path).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
}

pub fn save(path: &Path, s: &Settings) -> Result<(), String> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let text = serde_json::to_string_pretty(s).map_err(|e| e.to_string())?;
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, text).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aller_retour_et_fichier_abime() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("sub").join("settings.json");
        assert_eq!(load(&p), Settings::default());
        let s = Settings { wizard_done: true, mode: LaunchMode::Beammp, beamng_exe: Some("C:\\B\\BeamNG.drive.exe".into()), ..Default::default() };
        save(&p, &s).unwrap();
        assert_eq!(load(&p), s);
        fs::write(&p, "{pas du json").unwrap();
        assert_eq!(load(&p), Settings::default());
        fs::write(&p, r#"{"mode":"direct"}"#).unwrap(); // champs manquants -> valeurs par défaut
        let l = load(&p);
        assert_eq!(l.mode, LaunchMode::Direct);
        assert!(l.auto_update_mod);
    }
}
