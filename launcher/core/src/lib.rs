// GRNFR CMP Launcher — cœur sans Tauri (testé avec `cargo test` dans launcher/core).
//
// Pourquoi ce programme existe : depuis BeamNG 0.40, un mod ne peut plus joindre un serveur extérieur en HTTPS
// (l'interface du jeu n'a le droit de contacter que localhost, le Lua du jeu n'a pas de TLS). Le launcher tourne à
// côté du jeu et relaie les requêtes du mod (http://127.0.0.1:30815) vers Supabase en HTTPS. Il sait aussi trouver
// BeamNG / BeamMP, installer la dernière version du mod et lancer le jeu.
pub mod detect;
pub mod launch;
pub mod modsync;
pub mod proxy;
pub mod settings;
