// Détection de BeamNG.drive (bibliothèques Steam), de BeamMP Launcher et du dossier utilisateur de BeamNG (mods).
// Fonctions pures sur des chemins fournis par l'appelant (testables sous Linux) ; les emplacements Windows réels
// (registre, %APPDATA%...) sont rassemblés par `windows_candidates`.
use std::fs;
use std::path::{Path, PathBuf};

pub const BEAMNG_STEAM_APPID: &str = "284160";

/// Sortie de `reg query HKCU\Software\Valve\Steam /v SteamPath` -> dossier Steam.
pub fn parse_reg_steam_path(output: &str) -> Option<PathBuf> {
    output.lines().find_map(|l| {
        let l = l.trim();
        if !l.to_ascii_lowercase().starts_with("steampath") {
            return None;
        }
        l.split("REG_SZ").nth(1).map(|p| PathBuf::from(p.trim().replace('/', "\\"))).filter(|p| !p.as_os_str().is_empty())
    })
}

/// Contenu de steamapps/libraryfolders.vdf -> dossiers de bibliothèque ("path" "F:\\SteamLibrary").
pub fn parse_library_folders(vdf: &str) -> Vec<PathBuf> {
    vdf.lines()
        .filter_map(|l| {
            let parts: Vec<&str> = l.split('"').collect();
            // ligne : \t\t"path"\t\t"F:\\SteamLibrary" -> ["\t\t", "path", "\t\t", "F:\\\\SteamLibrary", ""]
            if parts.len() >= 4 && parts[1].eq_ignore_ascii_case("path") {
                Some(PathBuf::from(parts[3].replace("\\\\", "\\")))
            } else {
                None
            }
        })
        .collect()
}

/// Exécutable de BeamNG dans son dossier d'installation (racine puis Bin64).
pub fn beamng_exe_in(install_dir: &Path) -> Option<PathBuf> {
    ["BeamNG.drive.exe", "Bin64/BeamNG.drive.x64.exe"].iter().map(|c| install_dir.join(c)).find(|p| p.is_file())
}

/// Cherche BeamNG dans toutes les bibliothèques de ces dossiers Steam.
pub fn find_beamng(steam_roots: &[PathBuf]) -> Option<PathBuf> {
    let mut libs: Vec<PathBuf> = Vec::new();
    for root in steam_roots {
        libs.push(root.clone());
        if let Ok(vdf) = fs::read_to_string(root.join("steamapps").join("libraryfolders.vdf")) {
            libs.extend(parse_library_folders(&vdf));
        }
    }
    libs.iter().find_map(|lib| beamng_exe_in(&lib.join("steamapps").join("common").join("BeamNG.drive")))
}

/// Dossier "mods" de l'utilisateur. BeamNG 0.40 : %LOCALAPPDATA%\BeamNG\BeamNG.drive\current ; versions plus
/// anciennes : %LOCALAPPDATA%\BeamNG.drive\<version> (on prend la plus récente).
pub fn find_mods_dir(local_appdata: &Path) -> Option<PathBuf> {
    let current = local_appdata.join("BeamNG").join("BeamNG.drive").join("current");
    if current.is_dir() {
        return Some(current.join("mods"));
    }
    let old = local_appdata.join("BeamNG.drive");
    let mut versions: Vec<PathBuf> = fs::read_dir(&old).ok()?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.is_dir() && p.file_name().and_then(|n| n.to_str()).map_or(false, |n| n.chars().next().map_or(false, |c| c.is_ascii_digit())))
        .collect();
    versions.sort_by(|a, b| version_key(a).cmp(&version_key(b)));
    versions.pop().map(|v| v.join("mods"))
}

fn version_key(p: &Path) -> Vec<u32> {
    p.file_name().and_then(|n| n.to_str()).unwrap_or("").split('.').map(|x| x.parse().unwrap_or(0)).collect()
}

/// Emplacements connus de BeamMP Launcher (installeur officiel puis installations manuelles fréquentes).
pub fn beammp_candidates(appdata: Option<&Path>, local_appdata: Option<&Path>, program_files: &[PathBuf]) -> Vec<PathBuf> {
    let mut v = Vec::new();
    for base in [appdata, local_appdata].into_iter().flatten() {
        v.push(base.join("BeamMP-Launcher").join("BeamMP-Launcher.exe"));
    }
    for pf in program_files {
        v.push(pf.join("BeamMP-Launcher").join("BeamMP-Launcher.exe"));
        v.push(pf.join("BeamMP").join("BeamMP-Launcher.exe"));
    }
    v
}

pub fn first_existing(paths: &[PathBuf]) -> Option<PathBuf> {
    paths.iter().find(|p| p.is_file()).cloned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lit_le_dossier_steam_du_registre() {
        let out = "\r\nHKEY_CURRENT_USER\\Software\\Valve\\Steam\r\n    SteamPath    REG_SZ    c:/program files (x86)/steam\r\n\r\n";
        assert_eq!(parse_reg_steam_path(out), Some(PathBuf::from("c:\\program files (x86)\\steam")));
        assert_eq!(parse_reg_steam_path("ERREUR : clé introuvable"), None);
    }

    #[test]
    fn lit_les_bibliotheques_steam() {
        let vdf = "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"C:\\\\Program Files (x86)\\\\Steam\"\n\t\t\"label\"\t\t\"\"\n\t}\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"F:\\\\SteamLibrary\"\n\t\t\"apps\"\n\t\t{\n\t\t\t\"284160\"\t\t\"12345\"\n\t\t}\n\t}\n}\n";
        assert_eq!(parse_library_folders(vdf), vec![PathBuf::from("C:\\Program Files (x86)\\Steam"), PathBuf::from("F:\\SteamLibrary")]);
    }

    #[test]
    fn trouve_beamng_dans_une_seconde_bibliotheque() {
        let t = tempfile::tempdir().unwrap();
        let steam = t.path().join("Steam");
        let lib = t.path().join("SteamLibrary");
        fs::create_dir_all(steam.join("steamapps")).unwrap();
        let game = lib.join("steamapps/common/BeamNG.drive/Bin64");
        fs::create_dir_all(&game).unwrap();
        fs::write(game.join("BeamNG.drive.x64.exe"), "").unwrap();
        fs::write(steam.join("steamapps/libraryfolders.vdf"), format!("\"libraryfolders\"\n{{\n\t\"1\"\n\t{{\n\t\t\"path\"\t\t\"{}\"\n\t}}\n}}\n", lib.display())).unwrap();
        assert_eq!(find_beamng(&[steam.clone()]), Some(game.join("BeamNG.drive.x64.exe")));
        // l'exécutable racine est préféré quand il existe
        fs::write(lib.join("steamapps/common/BeamNG.drive/BeamNG.drive.exe"), "").unwrap();
        assert_eq!(find_beamng(&[steam]), Some(lib.join("steamapps/common/BeamNG.drive/BeamNG.drive.exe")));
        assert_eq!(find_beamng(&[t.path().join("absent")]), None);
    }

    #[test]
    fn trouve_le_dossier_mods() {
        let t = tempfile::tempdir().unwrap();
        assert_eq!(find_mods_dir(t.path()), None);
        for v in ["0.30", "0.32", "0.9"] {
            fs::create_dir_all(t.path().join("BeamNG.drive").join(v)).unwrap();
        }
        assert_eq!(find_mods_dir(t.path()), Some(t.path().join("BeamNG.drive/0.32/mods")));
        fs::create_dir_all(t.path().join("BeamNG/BeamNG.drive/current")).unwrap();
        assert_eq!(find_mods_dir(t.path()), Some(t.path().join("BeamNG/BeamNG.drive/current/mods")));
    }

    #[test]
    fn trouve_beammp() {
        let t = tempfile::tempdir().unwrap();
        let c = beammp_candidates(Some(&t.path().join("Roaming")), None, &[t.path().join("PF")]);
        assert_eq!(first_existing(&c), None);
        let exe = t.path().join("PF/BeamMP-Launcher/BeamMP-Launcher.exe");
        fs::create_dir_all(exe.parent().unwrap()).unwrap();
        fs::write(&exe, "").unwrap();
        assert_eq!(first_existing(&c), Some(exe));
    }
}
