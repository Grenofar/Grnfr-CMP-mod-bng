// GRNFR Host : petit serveur HTTP intégré, pour l'assistant web de configuration (React, voir host/ui/).
// Lit/écrit directement le fichier de configuration (grnfr-host.cfg) : un redémarrage du programme est
// nécessaire pour que les changements (port, mot de passe) soient repris par le relais WebSocket (relay.rs).
// Écouté uniquement sur 127.0.0.1 (pas depuis l'extérieur : l'assistant n'a pas d'authentification).
//
// Pas de framework HTTP (axum/hyper...) : un parseur HTTP/1.1 minimal à la main, pour ne pas ajouter une
// dépendance de plus que cette session n'a pas pu vérifier à la compilation (voir host/README.md).
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

use crate::config::{self, Config, DEFAULT_PORT};

const INDEX_HTML: &str = include_str!("../ui/dist/index.html");
const APP_JS: &str = include_str!("../ui/dist/app.js");
const APP_CSS: &str = include_str!("../ui/dist/app.css");

pub async fn run(port: u16) {
    let addr = format!("127.0.0.1:{}", port);
    let listener = match TcpListener::bind(&addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Assistant web indisponible sur {} : {}.", addr, e);
            return;
        }
    };
    println!("Assistant web de configuration : http://{}", addr);
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(v) => v,
            Err(_) => continue,
        };
        tokio::spawn(async move {
            if let Err(e) = handle(stream).await {
                eprintln!("Assistant web : requête échouée ({}).", e);
            }
        });
    }
}

struct Request {
    method: String,
    path: String,
    body: String,
}

fn find_double_crlf(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n")
}

async fn read_request(stream: &mut TcpStream) -> Result<Request, String> {
    let mut buf: Vec<u8> = Vec::new();
    let mut chunk = [0u8; 4096];
    let header_end;
    loop {
        let n = stream.read(&mut chunk).await.map_err(|e| e.to_string())?;
        if n == 0 {
            return Err("connexion fermée".into());
        }
        buf.extend_from_slice(&chunk[..n]);
        if let Some(pos) = find_double_crlf(&buf) {
            header_end = pos;
            break;
        }
        if buf.len() > 64 * 1024 {
            return Err("en-têtes trop grands".into());
        }
    }
    let header_text = String::from_utf8_lossy(&buf[..header_end]).to_string();
    let mut lines = header_text.lines();
    let first = lines.next().unwrap_or("");
    let mut parts = first.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("/").to_string();

    let mut content_length: usize = 0;
    for line in lines {
        if let Some((k, v)) = line.split_once(':') {
            if k.trim().eq_ignore_ascii_case("content-length") {
                content_length = v.trim().parse().unwrap_or(0);
            }
        }
    }

    let mut body_bytes = buf[header_end + 4..].to_vec();
    while body_bytes.len() < content_length {
        let n = stream.read(&mut chunk).await.map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        body_bytes.extend_from_slice(&chunk[..n]);
    }
    if body_bytes.len() > content_length {
        body_bytes.truncate(content_length);
    }
    let body = String::from_utf8_lossy(&body_bytes).to_string();
    Ok(Request { method, path, body })
}

async fn handle(mut stream: TcpStream) -> Result<(), String> {
    let req = read_request(&mut stream).await?;
    let (status, content_type, body): (&str, &str, Vec<u8>) = match (req.method.as_str(), req.path.as_str()) {
        ("GET", "/") | ("GET", "/index.html") => ("200 OK", "text/html; charset=utf-8", INDEX_HTML.as_bytes().to_vec()),
        ("GET", "/app.js") => ("200 OK", "application/javascript; charset=utf-8", APP_JS.as_bytes().to_vec()),
        ("GET", "/app.css") => ("200 OK", "text/css; charset=utf-8", APP_CSS.as_bytes().to_vec()),
        ("GET", "/api/config") => {
            let cfg = config::load().unwrap_or_default();
            let json = serde_json::json!({
                "name": cfg.name,
                "password": cfg.password.unwrap_or_default(),
                "port": cfg.port,
            });
            ("200 OK", "application/json", json.to_string().into_bytes())
        }
        ("POST", "/api/config") => match serde_json::from_str::<serde_json::Value>(&req.body) {
            Ok(v) => {
                let mut name = v.get("name").and_then(|x| x.as_str()).unwrap_or("").trim().to_string();
                if name.is_empty() {
                    name = Config::default().name;
                }
                let password = v.get("password").and_then(|x| x.as_str()).unwrap_or("").to_string();
                let port = v.get("port").and_then(|x| x.as_u64()).unwrap_or(DEFAULT_PORT as u64) as u16;
                let cfg = Config { name, password: if password.is_empty() { None } else { Some(password) }, port };
                match config::save(&cfg) {
                    Ok(_) => ("200 OK", "application/json", b"{\"ok\":true}".to_vec()),
                    Err(e) => ("500 Internal Server Error", "application/json", format!("{{\"error\":\"{}\"}}", e).into_bytes()),
                }
            }
            Err(_) => ("400 Bad Request", "application/json", b"{\"error\":\"bad_json\"}".to_vec()),
        },
        _ => ("404 Not Found", "text/plain", b"not found".to_vec()),
    };
    let header = format!(
        "HTTP/1.1 {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        status,
        content_type,
        body.len()
    );
    stream.write_all(header.as_bytes()).await.map_err(|e| e.to_string())?;
    stream.write_all(&body).await.map_err(|e| e.to_string())?;
    Ok(())
}
