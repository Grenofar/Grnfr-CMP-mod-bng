// Façons de lancer le jeu. Steam : URL steam:// (Steam gère tout, chemin inutile). Direct : l'exécutable de BeamNG.
// BeamMP : BeamMP Launcher, qui démarre lui-même BeamNG avec le multijoueur BeamMP.
// `plan` ne fait que décrire la commande (testable) ; l'app Tauri l'exécute.
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::detect::BEAMNG_STEAM_APPID;
use crate::settings::Settings;

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LaunchMode {
    Steam,
    Direct,
    Beammp,
}

#[derive(Debug, PartialEq)]
pub struct LaunchCmd {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub cwd: Option<PathBuf>,
}

fn existing_exe(path: &Option<String>, what: &str) -> Result<PathBuf, String> {
    let p = path.as_deref().filter(|s| !s.trim().is_empty()).ok_or_else(|| format!("Chemin de {} non renseigné.", what))?;
    let p = PathBuf::from(p.trim());
    if !p.is_file() {
        return Err(format!("{} introuvable : {}", what, p.display()));
    }
    Ok(p)
}

fn dir_of(p: &Path) -> Option<PathBuf> {
    p.parent().map(|d| d.to_path_buf())
}

pub fn plan(mode: LaunchMode, s: &Settings, windows: bool) -> Result<LaunchCmd, String> {
    match mode {
        LaunchMode::Steam => {
            let url = format!("steam://rungameid/{}", BEAMNG_STEAM_APPID);
            Ok(if windows {
                // `start "" <url>` : le premier argument entre guillemets est le titre de fenêtre, obligatoire.
                LaunchCmd { program: "cmd".into(), args: vec!["/C".into(), "start".into(), "".into(), url], cwd: None }
            } else {
                LaunchCmd { program: "xdg-open".into(), args: vec![url], cwd: None }
            })
        }
        LaunchMode::Direct => {
            let exe = existing_exe(&s.beamng_exe, "BeamNG.drive")?;
            Ok(LaunchCmd { cwd: dir_of(&exe), program: exe, args: vec![] })
        }
        LaunchMode::Beammp => {
            let exe = existing_exe(&s.beammp_exe, "BeamMP Launcher")?;
            Ok(LaunchCmd { cwd: dir_of(&exe), program: exe, args: vec![] })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn steam_ne_demande_aucun_chemin() {
        let c = plan(LaunchMode::Steam, &Settings::default(), true).unwrap();
        assert_eq!(c.program, PathBuf::from("cmd"));
        assert_eq!(c.args, vec!["/C", "start", "", "steam://rungameid/284160"]);
        assert_eq!(plan(LaunchMode::Steam, &Settings::default(), false).unwrap().program, PathBuf::from("xdg-open"));
    }

    #[test]
    fn direct_et_beammp_verifient_le_chemin() {
        let t = tempfile::tempdir().unwrap();
        let exe = t.path().join("BeamMP-Launcher.exe");
        let mut s = Settings::default();
        assert!(plan(LaunchMode::Beammp, &s, true).unwrap_err().contains("non renseigné"));
        s.beammp_exe = Some(exe.display().to_string());
        assert!(plan(LaunchMode::Beammp, &s, true).unwrap_err().contains("introuvable"));
        std::fs::write(&exe, "").unwrap();
        let c = plan(LaunchMode::Beammp, &s, true).unwrap();
        assert_eq!(c.program, exe);
        assert_eq!(c.cwd.as_deref(), Some(t.path()));
        assert!(plan(LaunchMode::Direct, &s, true).is_err());
    }

    #[test]
    fn noms_de_mode_en_json() {
        assert_eq!(serde_json::to_string(&LaunchMode::Beammp).unwrap(), r#""beammp""#);
    }
}
