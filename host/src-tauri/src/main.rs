// Point d'entrée mince : toute la logique est dans lib.rs (c'est le patron standard généré par
// create-tauri-app — nécessaire pour que les apps mobiles Tauri puissent réutiliser la même lib).
// Pas de fenêtre console sur Windows en version release (géré par Tauri via cette ligne ci-dessous,
// sans effet sur Linux/macOS).
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    grnfr_host_lib::run();
}
