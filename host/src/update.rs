// Vérifie la dernière version disponible en appelant `curl` (déjà présent sur la plupart des systèmes :
// évite d'ajouter une dépendance HTTP/TLS que cette session n'a pas pu vérifier à la compilation — voir
// host/README.md). Si curl est absent ou que le réseau/site ne répond pas, la vérification est simplement
// ignorée : le programme continue de démarrer normalement.
//
// "Automatique" veut dire ici : vérifié automatiquement à chaque lancement, avec une marche à suivre
// affichée si une nouvelle version existe. Remplacer soi-même le binaire en cours d'exécution n'est PAS
// tenté (trop spécifique à la plate-forme pour être fiable sans pouvoir le tester).
use std::process::Command;

// À adapter à votre déploiement : un petit fichier JSON {"version":"x.y.z"} publié sur le site GRNFR (voir
// public/host-version.json à la racine du dépôt, à servir tel quel par Vercel).
const UPDATE_URL: &str = "https://example.invalid/host-version.json";

pub fn check_for_update(current: &str) {
    let output = Command::new("curl").args(["-fsSL", "--max-time", "5", UPDATE_URL]).output();
    let body = match output {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
        _ => {
            println!("Vérification de mise à jour ignorée (curl indisponible, ou site de mise à jour injoignable).");
            return;
        }
    };
    let latest = serde_json::from_str::<serde_json::Value>(&body)
        .ok()
        .and_then(|v| v.get("version").and_then(|x| x.as_str()).map(|s| s.to_string()));
    match latest {
        Some(v) if v != current => {
            println!("=== Mise à jour disponible : v{} (vous avez v{}) — voir le site GRNFR pour la télécharger ===", v, current);
        }
        Some(_) => println!("GRNFR Host CPM : à jour (v{}).", current),
        None => println!("Vérification de mise à jour : réponse inattendue du site."),
    }
}
