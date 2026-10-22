// GRNFR CMP Launcher : couche Tauri mince. Toute la logique (relais local du mod, détection, installation du mod,
// lancement) est dans launcher/core (testée avec cargo test) ; ici on ne fait que l'exposer à l'interface React.
// Mises à jour de l'app : plugin officiel tauri-plugin-updater (signé, même clé que le host — voir launcher/README.md).
use grnfr_launcher_core::app::{Detected, LaunchReport, Launcher, ServerInfo, Status};
use grnfr_launcher_core::modsync::{InstallReport, ModStatus};
use grnfr_launcher_core::proxy::DEFAULT_ADDR;
use grnfr_launcher_core::settings::Settings;
use std::sync::Arc;
use tauri::{Manager, State};

type App = Arc<Launcher>;

// Les commandes réseau / disque tournent hors du thread de la fenêtre pour ne jamais la figer.
async fn blocking<T: Send + 'static>(f: impl FnOnce() -> Result<T, String> + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(f).await.map_err(|e| e.to_string())?
}

#[tauri::command]
fn get_status(app: State<'_, App>) -> Status {
    app.status()
}

#[tauri::command]
fn get_settings(app: State<'_, App>) -> Settings {
    app.settings()
}

#[tauri::command]
fn save_settings(app: State<'_, App>, settings: Settings) -> Result<(), String> {
    app.save_settings(settings)
}

#[tauri::command]
async fn detect(app: State<'_, App>) -> Result<Detected, String> {
    let a = app.inner().clone();
    blocking(move || Ok(a.detect())).await
}

#[tauri::command]
async fn mod_status(app: State<'_, App>) -> Result<ModStatus, String> {
    let a = app.inner().clone();
    blocking(move || a.mod_status()).await
}

#[tauri::command]
async fn install_mod(app: State<'_, App>) -> Result<InstallReport, String> {
    let a = app.inner().clone();
    blocking(move || a.install_mod()).await
}

#[tauri::command]
async fn launch(app: State<'_, App>) -> Result<LaunchReport, String> {
    let a = app.inner().clone();
    blocking(move || a.launch()).await
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            #[cfg(desktop)]
            app.handle().plugin(tauri_plugin_updater::Builder::new().build())?;
            // Adresse et clé publique du serveur embarquées à la compilation (secrets GitHub, comme pour le host).
            let server = ServerInfo {
                url: option_env!("SUPABASE_URL").map(String::from),
                anon_key: option_env!("SUPABASE_ANON_KEY").map(String::from),
            };
            let settings_path = app.path().app_config_dir()?.join("settings.json");
            let launcher = Launcher::new(settings_path, server, env!("CARGO_PKG_VERSION"), DEFAULT_ADDR);
            app.manage(Arc::new(launcher) as App);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_status, get_settings, save_settings, detect, mod_status, install_mod, launch])
        .run(tauri::generate_context!())
        .expect("erreur au lancement de GRNFR CMP Launcher");
}
