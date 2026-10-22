// Relais seul, sans interface : utile pour tester le mod contre le vrai relais (tests/launcher_e2e.mjs) ou dépanner.
//   UPSTREAM=https://xxx.supabase.co cargo run --example relay   (ADDR facultatif, défaut 127.0.0.1:30815)
fn main() {
    let upstream = std::env::var("UPSTREAM").expect("UPSTREAM manquant (URL Supabase)");
    let addr = std::env::var("ADDR").unwrap_or_else(|_| grnfr_launcher_core::proxy::DEFAULT_ADDR.to_string());
    let p = grnfr_launcher_core::proxy::start(&addr, &upstream, "relay-example").unwrap_or_else(|e| panic!("{}", e));
    println!("relais prêt sur {}", p.addr);
    loop {
        std::thread::sleep(std::time::Duration::from_secs(3600));
    }
}
