// GRNFR Host : relais WebSocket entre joueurs connectés au même serveur. Volontairement minimal : ce n'est
// PAS un serveur de simulation (pas de physique, pas d'arbitrage) — il relaie tel quel ce qu'un client
// envoie à tous les autres, comme le fait aujourd'hui Supabase (server_sync) pour les serveurs officiels,
// mais sans base de données ni limite de joueurs. L'intégration du mod GRNFR (net.js) avec CE relais
// (plutôt que / en complément de Supabase) n'a pas été faite dans cette session : voir host/README.md.
//
// Plusieurs serveurs par installation : HostState garde la liste de tous les ServerInstance connus (chacun
// avec son propre port/nom/mot de passe/joueurs), identifiés par l'id de leur ligne host_servers. Chacun
// peut être démarré/arrêté indépendamment — plusieurs peuvent tourner EN MÊME TEMPS, chacun sur son port.
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use serde_json::Value;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tokio_tungstenite::tungstenite::Message;
use uuid::Uuid;

use crate::config::Config;
use crate::logger::log;

type Tx = mpsc::UnboundedSender<Message>;

struct ClientInfo {
    username: String,
    peer: String,
    joined_at: Instant,
    tx: Tx,
}

#[derive(Serialize, Clone)]
pub struct ClientSummary {
    pub id: u64,
    pub username: String,
    pub peer: String,
    pub joined_secs: u64,
}

struct Shared {
    clients: Mutex<HashMap<u64, ClientInfo>>,
    next_id: Mutex<u64>,
}

// Un serveur configuré (une ligne host_servers), démarré ou non.
pub struct ServerInstance {
    pub id: Uuid,
    shared: Arc<Shared>,
    listener_task: Mutex<Option<JoinHandle<()>>>,
    running: Mutex<bool>,
    cfg: Mutex<Config>,
}

impl ServerInstance {
    pub fn new(id: Uuid, cfg: Config) -> Arc<Self> {
        Arc::new(ServerInstance {
            id,
            shared: Arc::new(Shared { clients: Mutex::new(HashMap::new()), next_id: Mutex::new(1) }),
            listener_task: Mutex::new(None),
            running: Mutex::new(false),
            cfg: Mutex::new(cfg),
        })
    }

    pub fn is_running(&self) -> bool { *self.running.lock().unwrap() }
    pub fn config(&self) -> Config { self.cfg.lock().unwrap().clone() }
    pub fn set_config(&self, cfg: Config) { *self.cfg.lock().unwrap() = cfg; }

    pub fn players(&self) -> Vec<ClientSummary> {
        let clients = self.shared.clients.lock().unwrap();
        let mut out: Vec<ClientSummary> = clients
            .iter()
            .map(|(id, c)| ClientSummary {
                id: *id,
                username: c.username.clone(),
                peer: c.peer.clone(),
                joined_secs: c.joined_at.elapsed().as_secs(),
            })
            .collect();
        out.sort_by_key(|c| c.id);
        out
    }

    // Expulsion : signale la fermeture au client puis le retire tout de suite de la liste (le socket se
    // fermera de son côté dans l'instant qui suit, sans qu'on ait besoin de l'attendre ici).
    pub fn kick(&self, client_id: u64) -> bool {
        let mut clients = self.shared.clients.lock().unwrap();
        if let Some(info) = clients.remove(&client_id) {
            let _ = info.tx.send(Message::Text(r#"{"type":"kicked"}"#.to_string()));
            let _ = info.tx.send(Message::Close(None));
            true
        } else {
            false
        }
    }
}

// Tous les serveurs connus de cette installation (host_id), qu'ils soient démarrés ou non.
pub struct HostState {
    pub host_id: Uuid,
    servers: Mutex<HashMap<Uuid, Arc<ServerInstance>>>,
}

impl HostState {
    pub fn new(host_id: Uuid) -> Arc<Self> {
        Arc::new(HostState { host_id, servers: Mutex::new(HashMap::new()) })
    }

    // Enregistre un serveur connu (venant de Supabase) sans le démarrer — no-op si déjà présent.
    pub fn ensure(&self, id: Uuid, cfg: Config) -> Arc<ServerInstance> {
        let mut servers = self.servers.lock().unwrap();
        servers.entry(id).or_insert_with(|| ServerInstance::new(id, cfg)).clone()
    }

    pub fn get(&self, id: Uuid) -> Option<Arc<ServerInstance>> {
        self.servers.lock().unwrap().get(&id).cloned()
    }

    pub fn remove(&self, id: Uuid) -> Option<Arc<ServerInstance>> {
        self.servers.lock().unwrap().remove(&id)
    }

    pub fn all(&self) -> Vec<Arc<ServerInstance>> {
        let servers = self.servers.lock().unwrap();
        let mut out: Vec<_> = servers.values().cloned().collect();
        out.sort_by_key(|s| s.id);
        out
    }
}

// Démarre le relais de CE serveur avec sa config actuelle. Sans effet si déjà démarré (il faut d'abord
// stop() pour reprendre un port différent).
pub async fn start(instance: Arc<ServerInstance>) -> Result<(), String> {
    if instance.is_running() {
        return Err("already_running".into());
    }
    let cfg = instance.config();
    let addr = format!("0.0.0.0:{}", cfg.port);
    let listener = TcpListener::bind(&addr).await.map_err(|e| e.to_string())?;
    log(&format!(
        "Serveur \"{}\" en écoute sur le port {} ({} mot de passe). Aucune limite de joueurs.",
        cfg.name,
        cfg.port,
        if cfg.password.is_some() { "avec" } else { "sans" }
    ));
    let shared = instance.shared.clone();
    let handle = tokio::spawn(accept_loop(listener, shared, cfg));
    *instance.listener_task.lock().unwrap() = Some(handle);
    *instance.running.lock().unwrap() = true;
    Ok(())
}

// Arrête d'accepter de nouvelles connexions sur CE serveur et expulse tout le monde. Les autres serveurs de
// la même installation ne sont pas affectés. Le port est libéré immédiatement (nécessaire pour pouvoir
// relancer avec un port différent sans redémarrer le programme).
pub fn stop(instance: &Arc<ServerInstance>) {
    if let Some(h) = instance.listener_task.lock().unwrap().take() {
        h.abort();
    }
    let mut clients = instance.shared.clients.lock().unwrap();
    for (_, info) in clients.drain() {
        let _ = info.tx.send(Message::Close(None));
    }
    *instance.running.lock().unwrap() = false;
}

async fn accept_loop(listener: TcpListener, shared: Arc<Shared>, cfg: Config) {
    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(v) => v,
            Err(e) => {
                log(&format!("Connexion refusée : {}.", e));
                continue;
            }
        };
        let shared = shared.clone();
        let cfg = cfg.clone();
        tokio::spawn(async move {
            let peer_s = peer.to_string();
            if let Err(e) = handle_client(stream, &peer_s, shared, cfg).await {
                log(&format!("Client {} déconnecté : {}.", peer_s, e));
            }
        });
    }
}

async fn handle_client(stream: TcpStream, peer: &str, shared: Arc<Shared>, cfg: Config) -> Result<(), String> {
    let ws_stream = tokio_tungstenite::accept_async(stream).await.map_err(|e| e.to_string())?;
    let (mut write, mut read) = ws_stream.split();

    // Premier message attendu : {"type":"hello","username":"...","password":"..."}
    let hello_text = match read.next().await {
        Some(Ok(Message::Text(t))) => t,
        Some(Ok(_)) => return Err("premier message inattendu (pas du texte)".into()),
        Some(Err(e)) => return Err(e.to_string()),
        None => return Err("fermé avant le message de bienvenue".into()),
    };
    let hello: Value = serde_json::from_str(&hello_text).map_err(|e| e.to_string())?;
    let username = hello.get("username").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    if username.is_empty() {
        let _ = write.send(Message::Text(r#"{"type":"error","error":"username_required"}"#.to_string())).await;
        return Err("pseudo manquant".into());
    }
    if let Some(expected) = &cfg.password {
        let given = hello.get("password").and_then(|v| v.as_str()).unwrap_or("");
        if given != expected {
            let _ = write.send(Message::Text(r#"{"type":"error","error":"bad_password"}"#.to_string())).await;
            return Err("mot de passe incorrect".into());
        }
    }

    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
    let id = {
        let mut n = shared.next_id.lock().unwrap();
        let id = *n;
        *n += 1;
        id
    };
    {
        let mut clients = shared.clients.lock().unwrap();
        clients.insert(id, ClientInfo { username: username.clone(), peer: peer.to_string(), joined_at: Instant::now(), tx });
    }
    log(&format!("{} a rejoint depuis {}.", username, peer));
    broadcast(&shared, id, &format!(r#"{{"type":"join","username":"{}"}}"#, username));

    // Tâche d'écriture : relaie vers CE client ce que les autres (ou lui-même, ignoré côté lecture) envoient.
    let write_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if write.send(msg).await.is_err() {
                break;
            }
        }
    });

    // Boucle de lecture : relaie aux autres ce que ce client envoie, sans l'interpréter (position, chat...
    // c'est le mod qui décide du format ; ce relais ne fait que transporter).
    while let Some(msg) = read.next().await {
        match msg {
            Ok(Message::Text(text)) => broadcast(&shared, id, &text),
            Ok(Message::Close(_)) => break,
            Err(_) => break,
            _ => {}
        }
    }

    write_task.abort();
    {
        let mut clients = shared.clients.lock().unwrap();
        clients.remove(&id);
    }
    log(&format!("{} est parti.", username));
    broadcast(&shared, id, &format!(r#"{{"type":"leave","username":"{}"}}"#, username));
    Ok(())
}

fn broadcast(shared: &Arc<Shared>, from_id: u64, text: &str) {
    let clients = shared.clients.lock().unwrap();
    for (id, info) in clients.iter() {
        if *id != from_id {
            let _ = info.tx.send(Message::Text(text.to_string()));
        }
    }
}
