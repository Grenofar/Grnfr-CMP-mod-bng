// GRNFR Host : relais WebSocket entre joueurs connectés au même host. Volontairement minimal : ce n'est PAS
// un serveur de simulation (pas de physique, pas d'arbitrage) — il relaie tel quel ce qu'un client envoie à
// tous les autres, comme le fait aujourd'hui Supabase (server_sync) pour les serveurs officiels, mais sans
// base de données ni limite de joueurs. L'intégration du mod GRNFR (net.js) avec CE relais (plutôt que /
// en complément de Supabase) n'a pas été faite dans cette session : voir host/README.md.
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;

use crate::config::Config;

type Tx = mpsc::UnboundedSender<Message>;

struct Shared {
    clients: Mutex<HashMap<u64, (String, Tx)>>,
    next_id: Mutex<u64>,
}

pub async fn run(cfg: Config) {
    let shared = Arc::new(Shared { clients: Mutex::new(HashMap::new()), next_id: Mutex::new(1) });
    let addr = format!("0.0.0.0:{}", cfg.port);
    let listener = match TcpListener::bind(&addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Impossible d'écouter sur {} : {}.", addr, e);
            return;
        }
    };
    println!(
        "Serveur \"{}\" en écoute sur le port {} ({} mot de passe). Aucune limite de joueurs.",
        cfg.name,
        cfg.port,
        if cfg.password.is_some() { "avec" } else { "sans" }
    );

    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(v) => v,
            Err(e) => {
                eprintln!("Connexion refusée : {}.", e);
                continue;
            }
        };
        let shared = shared.clone();
        let cfg = cfg.clone();
        tokio::spawn(async move {
            let peer_s = peer.to_string();
            if let Err(e) = handle_client(stream, &peer_s, shared, cfg).await {
                eprintln!("Client {} déconnecté : {}.", peer_s, e);
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
        clients.insert(id, (username.clone(), tx));
    }
    println!("{} a rejoint depuis {}.", username, peer);
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
    println!("{} est parti.", username);
    broadcast(&shared, id, &format!(r#"{{"type":"leave","username":"{}"}}"#, username));
    Ok(())
}

fn broadcast(shared: &Arc<Shared>, from_id: u64, text: &str) {
    let clients = shared.clients.lock().unwrap();
    for (id, (_, tx)) in clients.iter() {
        if *id != from_id {
            let _ = tx.send(Message::Text(text.to_string()));
        }
    }
}
