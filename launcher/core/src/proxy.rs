// Relais local du mod : http://127.0.0.1:30815/<chemin> -> <URL Supabase>/<chemin>, en HTTPS.
// L'interface de BeamNG n'a le droit de contacter que localhost (Content-Security-Policy connect-src) : c'est la seule
// porte de sortie. Pas un proxy ouvert : seuls /rest/v1/ et /auth/v1/ sont relayés, toujours vers l'URL compilée.
// N'écoute que sur 127.0.0.1 (jamais le réseau local). Ne journalise jamais les en-têtes (clé, jeton de session).
use std::io::Read;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde_json::json;
use tiny_http::{Header, Method, Request, Response, Server};

pub const DEFAULT_ADDR: &str = "127.0.0.1:30815";
const MAX_BODY: u64 = 1 << 20;
const MAX_RESPONSE: u64 = 8 << 20;
const FORWARDED_HEADERS: [&str; 5] = ["apikey", "authorization", "content-type", "accept", "prefer"];
// Access-Control-Allow-Private-Network : Chromium (donc l'interface de BeamNG) exige cet accord avant qu'une page
// contacte une adresse privée/locale.
const CORS: [(&str, &str); 5] = [
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Headers", "apikey, authorization, content-type, prefer, accept"),
    ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
    ("Access-Control-Allow-Private-Network", "true"),
    ("Access-Control-Max-Age", "600"),
];

#[derive(Default)]
pub struct Stats {
    pub requests: AtomicU64,
    pub errors: AtomicU64,
    pub last: Mutex<String>,
}

impl Stats {
    pub fn snapshot(&self) -> (u64, u64, String) {
        (
            self.requests.load(Ordering::Relaxed),
            self.errors.load(Ordering::Relaxed),
            self.last.lock().map(|s| s.clone()).unwrap_or_default(),
        )
    }
    fn note(&self, line: String, error: bool) {
        if error {
            self.errors.fetch_add(1, Ordering::Relaxed);
        }
        if let Ok(mut l) = self.last.lock() {
            *l = line;
        }
    }
}

pub struct Proxy {
    pub addr: SocketAddr,
    pub stats: Arc<Stats>,
}

/// Démarre le relais dans un thread. `addr` = "127.0.0.1:30815" (ou ":0" en test), `upstream` = URL Supabase.
pub fn start(addr: &str, upstream: &str, version: &str) -> Result<Proxy, String> {
    let upstream = upstream.trim().trim_end_matches('/').to_string();
    if !upstream.starts_with("https://") && !upstream.starts_with("http://127.0.0.1") {
        return Err(format!("URL du serveur invalide : « {} »", upstream));
    }
    let server = Server::http(addr).map_err(|e| format!("impossible d'écouter sur {} : {}", addr, e))?;
    let local = server.server_addr().to_ip().ok_or_else(|| "adresse d'écoute inconnue".to_string())?;
    let stats = Arc::new(Stats::default());
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(20)).build();
    let (st, ver) = (stats.clone(), version.to_string());
    thread::spawn(move || {
        for req in server.incoming_requests() {
            let (agent, upstream, st, ver) = (agent.clone(), upstream.clone(), st.clone(), ver.clone());
            thread::spawn(move || handle(req, &agent, &upstream, &st, &ver));
        }
    });
    Ok(Proxy { addr: local, stats })
}

fn header(k: &str, v: &str) -> Header {
    Header::from_bytes(k.as_bytes(), v.as_bytes()).expect("en-tête valide")
}

fn respond(req: Request, status: u16, content_type: &str, body: Vec<u8>) {
    let mut r = Response::from_data(body).with_status_code(status);
    for (k, v) in CORS {
        r.add_header(header(k, v));
    }
    r.add_header(header("Content-Type", content_type));
    let _ = req.respond(r);
}

fn error_body(message: &str, detail: &str) -> Vec<u8> {
    json!({ "message": message, "detail": detail }).to_string().into_bytes()
}

fn handle(mut req: Request, agent: &ureq::Agent, upstream: &str, st: &Stats, version: &str) {
    let method = req.method().clone();
    let url = req.url().to_string();
    let path = url.split('?').next().unwrap_or("").to_string();
    match method {
        Method::Options => return respond(req, 204, "text/plain", Vec::new()),
        Method::Get if path == "/health" => {
            let body = json!({ "ok": true, "app": "grnfr-cmp-launcher", "version": version }).to_string();
            return respond(req, 200, "application/json", body.into_bytes());
        }
        Method::Get | Method::Post => {}
        _ => return respond(req, 405, "application/json", error_body("launcher_bad_method", method.as_str())),
    }
    if !(path.starts_with("/rest/v1/") || path.starts_with("/auth/v1/")) || path.contains("..") {
        return respond(req, 404, "application/json", error_body("launcher_bad_path", &path));
    }
    st.requests.fetch_add(1, Ordering::Relaxed);

    let mut body = Vec::new();
    if let Err(e) = req.as_reader().take(MAX_BODY + 1).read_to_end(&mut body) {
        st.note(format!("{} {} -> requête illisible", method, path), true);
        return respond(req, 400, "application/json", error_body("launcher_bad_request", &e.to_string()));
    }
    if body.len() as u64 > MAX_BODY {
        return respond(req, 413, "application/json", error_body("launcher_too_large", ""));
    }

    let is_get = method == Method::Get;
    let mut up = agent.request(if is_get { "GET" } else { "POST" }, &format!("{}{}", upstream, url));
    for h in req.headers() {
        let name = h.field.as_str().as_str().to_ascii_lowercase();
        if FORWARDED_HEADERS.contains(&name.as_str()) {
            up = up.set(&name, h.value.as_str());
        }
    }
    let result = if is_get { up.call() } else { up.send_bytes(&body) };
    let resp = match result {
        Ok(r) => r,
        Err(ureq::Error::Status(_, r)) => r,
        Err(e) => {
            st.note(format!("{} {} -> serveur injoignable : {}", method, path, e), true);
            return respond(req, 502, "application/json", error_body("launcher_upstream", &e.to_string()));
        }
    };
    let status = resp.status();
    let content_type = resp.header("content-type").unwrap_or("application/json").to_string();
    let mut out = Vec::new();
    if let Err(e) = resp.into_reader().take(MAX_RESPONSE).read_to_end(&mut out) {
        st.note(format!("{} {} -> réponse coupée : {}", method, path, e), true);
        return respond(req, 502, "application/json", error_body("launcher_upstream", &e.to_string()));
    }
    st.note(format!("{} {} -> {}", method, path, status), status >= 500);
    respond(req, status, &content_type, out);
}

#[cfg(test)]
mod tests {
    use super::*;

    // Faux Supabase : renvoie en JSON ce qu'il a reçu (méthode, URL, en-têtes utiles, corps), avec le statut
    // demandé par l'en-tête x-status (pour vérifier que les erreurs 4xx sont relayées telles quelles).
    fn fake_upstream() -> String {
        let server = Server::http("127.0.0.1:0").unwrap();
        let addr = server.server_addr().to_ip().unwrap();
        thread::spawn(move || {
            for mut req in server.incoming_requests() {
                let mut body = String::new();
                req.as_reader().read_to_string(&mut body).unwrap();
                let get = |n: &'static str| req.headers().iter().find(|h| h.field.equiv(n)).map(|h| h.value.as_str().to_string());
                let status: u16 = req.url().split("status=").nth(1).and_then(|s| s.get(..3)).and_then(|s| s.parse().ok()).unwrap_or(200);
                let echo = json!({ "method": req.method().as_str(), "url": req.url(), "apikey": get("apikey"),
                    "authorization": get("authorization"), "xstatus": get("x-status"), "body": body });
                let _ = req.respond(Response::from_string(echo.to_string()).with_status_code(status)
                    .with_header(header("Content-Type", "application/json")));
            }
        });
        format!("http://127.0.0.1:{}", addr.port())
    }

    fn proxy(upstream: &str) -> String {
        let p = start("127.0.0.1:0", upstream, "9.9.9").unwrap();
        format!("http://127.0.0.1:{}", p.addr.port())
    }

    fn call(req: ureq::Request, body: Option<&str>) -> (u16, String, Option<String>) {
        let r = match body { Some(b) => req.send_string(b), None => req.call() };
        let r = match r { Ok(r) => r, Err(ureq::Error::Status(_, r)) => r, Err(e) => panic!("{}", e) };
        let pna = r.header("access-control-allow-private-network").map(|s| s.to_string());
        (r.status(), r.into_string().unwrap(), pna)
    }

    #[test]
    fn relaie_une_rpc_avec_cle_jeton_requete_et_corps() {
        let p = proxy(&fake_upstream());
        let (status, body, pna) = call(
            ureq::post(&format!("{}/rest/v1/rpc/get_me?select=x", p))
                .set("apikey", "anon").set("Authorization", "Bearer tok").set("Content-Type", "application/json"),
            Some(r#"{"a":1}"#),
        );
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(status, 200);
        assert_eq!(v["method"], "POST");
        assert_eq!(v["url"], "/rest/v1/rpc/get_me?select=x");
        assert_eq!(v["apikey"], "anon");
        assert_eq!(v["authorization"], "Bearer tok");
        assert_eq!(v["body"], r#"{"a":1}"#);
        assert_eq!(pna.as_deref(), Some("true"));
    }

    #[test]
    fn relaie_les_erreurs_du_serveur_telles_quelles() {
        let p = proxy(&fake_upstream());
        let (status, body, _) = call(ureq::get(&format!("{}/auth/v1/user?status=401", p)), None);
        assert_eq!(status, 401);
        assert!(body.contains(r#""method":"GET""#));
    }

    #[test]
    fn ne_relaie_que_les_en_tetes_utiles() {
        let p = proxy(&fake_upstream());
        let (_, body, _) = call(ureq::get(&format!("{}/auth/v1/user", p)).set("x-status", "401"), None);
        assert!(body.contains(r#""xstatus":null"#));
    }

    #[test]
    fn refuse_tout_autre_chemin_et_ne_sort_pas_du_serveur() {
        let p = proxy(&fake_upstream());
        for path in ["/storage/v1/object/x", "/", "/rest/v1/../x", "/etc/passwd"] {
            let (status, body, _) = call(ureq::get(&format!("{}{}", p, path)), None);
            assert_eq!(status, 404, "{}", path);
            assert!(body.contains("launcher_bad_path"), "{}", path);
        }
    }

    #[test]
    fn repond_au_preflight_cors_et_a_la_sante() {
        let p = proxy(&fake_upstream());
        let (status, _, pna) = call(ureq::request("OPTIONS", &format!("{}/rest/v1/rpc/x", p)), None);
        assert_eq!(status, 204);
        assert_eq!(pna.as_deref(), Some("true"));
        let (status, body, _) = call(ureq::get(&format!("{}/health", p)), None);
        assert_eq!(status, 200);
        assert!(body.contains(r#""version":"9.9.9""#));
    }

    #[test]
    fn serveur_injoignable_donne_502_explicite() {
        // Port réservé puis libéré : rien n'y écoute.
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let p = start("127.0.0.1:0", &format!("http://127.0.0.1:{}", port), "1").unwrap();
        let (status, body, _) = call(ureq::get(&format!("http://127.0.0.1:{}/rest/v1/x", p.addr.port())), None);
        assert_eq!(status, 502);
        assert!(body.contains("launcher_upstream"));
        assert_eq!(p.stats.snapshot().1, 1);
    }

    #[test]
    fn refuse_une_url_de_serveur_non_https() {
        assert!(start("127.0.0.1:0", "http://evil.example", "1").is_err());
    }
}
