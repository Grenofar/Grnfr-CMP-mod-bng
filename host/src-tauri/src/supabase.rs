// Configuration du host stockée dans Supabase (table `hosts`, fonctions `host_config_get`/`host_config_set`
// — voir supabase/migrations/0011_host_config.sql). Pas de compte : l'identifiant aléatoire généré en local
// (config::load_or_create_host_id) sert à la fois de clé et de secret.
//
// SUPABASE_URL et SUPABASE_ANON_KEY sont fixés À LA COMPILATION (variables d'environnement passées par la
// CI, voir .github/workflows/host-release.yml) — jamais lus depuis un fichier .env à l'exécution. L'anon
// key est faite pour être publique (même principe que dans le mod/site : protégée par les grants RPC, pas
// par le secret) ; aucune clé service_role n'est jamais embarquée ici.
use uuid::Uuid;

use crate::config::Config;

const SUPABASE_URL: Option<&str> = option_env!("SUPABASE_URL");
const SUPABASE_ANON_KEY: Option<&str> = option_env!("SUPABASE_ANON_KEY");

fn creds() -> Result<(&'static str, &'static str), String> {
    match (SUPABASE_URL, SUPABASE_ANON_KEY) {
        (Some(u), Some(k)) if !u.is_empty() && !k.is_empty() => Ok((u, k)),
        _ => Err("ce binaire n'a pas été compilé avec les identifiants Supabase (SUPABASE_URL/SUPABASE_ANON_KEY manquants)".into()),
    }
}

async fn rpc(name: &str, body: serde_json::Value) -> Result<serde_json::Value, String> {
    let (url, key) = creds()?;
    let endpoint = format!("{}/rest/v1/rpc/{}", url, name);
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(8))
        .build()
        .map_err(|e| e.to_string())?;
    let resp = client
        .post(&endpoint)
        .header("apikey", key)
        .header("Authorization", format!("Bearer {}", key))
        .header("Content-Type", "application/json")
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        let status = resp.status().as_u16();
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("http_{} {}", status, text));
    }
    resp.json::<serde_json::Value>().await.map_err(|e| e.to_string())
}

// None = pas d'erreur réseau, mais pas encore de config enregistrée pour cet host_id (premier lancement).
pub async fn fetch_config(host_id: Uuid) -> Result<Option<Config>, String> {
    let v = rpc("host_config_get", serde_json::json!({ "p_host_id": host_id })).await?;
    if v.is_null() {
        return Ok(None);
    }
    Ok(Some(Config {
        name: v.get("name").and_then(|x| x.as_str()).unwrap_or("Serveur GRNFR").to_string(),
        password: v.get("password").and_then(|x| x.as_str()).filter(|s| !s.is_empty()).map(|s| s.to_string()),
        port: v.get("port").and_then(|x| x.as_u64()).unwrap_or(crate::config::DEFAULT_PORT as u64) as u16,
    }))
}

pub async fn save_config(host_id: Uuid, cfg: &Config) -> Result<(), String> {
    rpc(
        "host_config_set",
        serde_json::json!({
            "p_host_id": host_id,
            "p_name": cfg.name,
            "p_password": cfg.password.clone().unwrap_or_default(),
            "p_port": cfg.port,
        }),
    )
    .await?;
    Ok(())
}
