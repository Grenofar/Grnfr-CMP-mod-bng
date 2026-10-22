// Liste des serveurs de cette installation, stockée dans Supabase (table `host_servers`, fonctions
// `host_servers_list`/`host_server_upsert`/`host_server_delete` — voir
// supabase/migrations/0012_host_multi_server.sql). Pas de compte : l'identifiant aléatoire généré en local
// (config::load_or_create_host_id) sert à la fois de clé et de secret pour TOUS les serveurs de cette
// installation.
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

pub struct ServerRecord {
    pub id: Uuid,
    pub config: Config,
}

fn parse_record(v: &serde_json::Value) -> Option<ServerRecord> {
    let id = Uuid::parse_str(v.get("id")?.as_str()?).ok()?;
    let name = v.get("name").and_then(|x| x.as_str()).unwrap_or("Serveur GRNFR").to_string();
    let password = v.get("password").and_then(|x| x.as_str()).filter(|s| !s.is_empty()).map(|s| s.to_string());
    let port = v.get("port").and_then(|x| x.as_u64()).unwrap_or(crate::config::DEFAULT_PORT as u64) as u16;
    Some(ServerRecord { id, config: Config { name, password, port } })
}

pub async fn list_servers(host_id: Uuid) -> Result<Vec<ServerRecord>, String> {
    let v = rpc("host_servers_list", serde_json::json!({ "p_host_id": host_id })).await?;
    let arr = v.as_array().cloned().unwrap_or_default();
    Ok(arr.iter().filter_map(parse_record).collect())
}

// id None = crée un nouveau serveur ; id Some = modifie un serveur existant. Retourne l'id (nouveau ou
// existant).
pub async fn upsert_server(host_id: Uuid, id: Option<Uuid>, cfg: &Config) -> Result<Uuid, String> {
    let v = rpc(
        "host_server_upsert",
        serde_json::json!({
            "p_host_id": host_id,
            "p_id": id,
            "p_name": cfg.name,
            "p_password": cfg.password.clone().unwrap_or_default(),
            "p_port": cfg.port,
        }),
    )
    .await?;
    Uuid::parse_str(v.as_str().ok_or("bad_response")?).map_err(|e| e.to_string())
}

pub async fn delete_server(host_id: Uuid, id: Uuid) -> Result<(), String> {
    rpc("host_server_delete", serde_json::json!({ "p_host_id": host_id, "p_id": id })).await?;
    Ok(())
}

// ------------------------------------------------------------------ carte en direct (0013_live_map.sql)
// Serveurs de jeu du MOD (Serveur 1, 2, 3...) et joueurs présents, avec carte et position 2D. Ce ne sont pas les
// serveurs de cette installation : le mod ne passe pas (encore) par un relais host, ses joueurs sont sur Supabase.
pub async fn live_servers() -> Result<serde_json::Value, String> {
    rpc("live_servers", serde_json::json!({})).await
}

// Réseau routier d'une carte vu de dessus ({ roads: [[x1,y1,x2,y2]...], bounds }), envoyé une fois par le mod ;
// null si aucun joueur ne l'a encore envoyé.
pub async fn level_roads(level: &str) -> Result<serde_json::Value, String> {
    rpc("get_level_roads", serde_json::json!({ "p_level": level })).await
}
