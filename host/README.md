# GRNFR CMP Host

Serveur auto-hébergé pour GRNFR Online : un relais WebSocket **sans limite de joueurs**, avec un nom et un
mot de passe facultatif, configuré par un assistant (terminal au premier lancement, puis une page web React
à tout moment). Écrit en Rust (`host/`), interface de configuration en React (`host/ui/`).

## ⚠️ À lire avant d'utiliser ce dossier

Ce code a été écrit **sans pouvoir être compilé ni testé** : l'environnement qui l'a produit n'a ni `cargo`
ni `rustc` installés. Ce n'est pas le cas du reste du mod (SQL, Lua, JS), qui a pu être vérifié au moins
partiellement — voir le README à la racine. Concrètement :
- Le code Rust (`host/src/`) suit des schémas très standards et stables (`tokio` + `tokio-tungstenite` pour
  le relais WebSocket, un parseur HTTP/1.1 fait main pour l'assistant web), mais **n'a jamais compilé**.
  La première chose à faire est `cargo build` et corriger ce qui ne passe pas.
- L'interface React (`host/ui/`), elle, a été **construite et vérifiée** dans cette session (`npm install`
  && `npm run build` ont réussi) — c'est la partie la plus fiable de ce dossier.
- **Ce host n'est PAS encore relié au mod BeamNG.** `mod/grnfr-mod/ui/ui-vue/mods/GRNFR/net.js` ne sait
  parler qu'à Supabase aujourd'hui. Brancher le mod sur ce relais (en plus de, ou à la place de, Supabase)
  est un travail à part, non commencé.
- Le relais ne fait que **transporter** les messages d'un client vers tous les autres, sans les comprendre
  (pas de physique, pas de vérification d'argent ou de position : ça reste le rôle de Supabase pour tout ce
  qui touche à l'argent). Il convient pour voir les autres joueurs (façon fantômes), pas pour une économie
  partagée fiable.

## Construire

```
cd host/ui
npm install
npm run build          # fabrique host/ui/dist/ (index.html, app.js, app.css)

cd ..
cargo build --release  # host/src/httpd.rs embarque les fichiers de host/ui/dist/ : à construire D'ABORD
```

Le binaire est `host/target/release/grnfr-host` (ou `.exe` sous Windows).

## Utiliser

```
./grnfr-host
```

- **Premier lancement** : assistant en ligne de commande (nom du serveur, mot de passe ou pas, port
  d'écoute — 30814 par défaut). Écrit `grnfr-host.cfg` dans le dossier courant.
- **Lancements suivants** : la configuration existante est reprise telle quelle.
- **Modifier la configuration** : ouvrez `http://127.0.0.1:<port+1>` dans un navigateur (l'assistant web,
  React, n'écoute que sur votre propre machine — pas depuis l'extérieur). Un redémarrage du programme est
  nécessaire pour qu'un nouveau port ou mot de passe soit pris en compte par le relais.
- **Mise à jour** : à chaque lancement, le programme essaie de lire `public/host-version.json` (voir plus
  bas) via `curl` et affiche un message si une version plus récente existe. Il ne se remplace jamais
  lui-même : le téléchargement et le remplacement du binaire restent manuels (trop spécifique à chaque
  système pour être fiable sans pouvoir le tester ici).
- **Aucune limite de joueurs** : contrairement aux serveurs créés dans Supabase (4 joueurs maximum), ce
  relais accepte autant de connexions que votre machine et votre réseau le permettent.
- **Mot de passe** : s'il y en a un, chaque client doit l'envoyer dans son premier message
  (`{"type":"hello","username":"...","password":"..."}`) ; sinon la connexion est refusée
  (`{"type":"error","error":"bad_password"}`). Sans mot de passe, n'importe qui connaissant l'adresse et le
  port peut rejoindre.
- **Accès depuis l'extérieur** : si vos joueurs ne sont pas sur le même réseau local, ouvrez le port choisi
  (TCP, WebSocket) sur votre routeur/pare-feu vers la machine qui fait tourner `grnfr-host`.

## Publier le fichier de version (`public/host-version.json`)

`host/src/update.rs` lit un petit JSON `{ "version": "x.y.z" }` à une URL fixée dans le code
(`UPDATE_URL`, actuellement un espace réservé `https://example.invalid/...`). Une fois le site déployé sur
Vercel, remplacez cette constante par l'URL réelle (`https://votre-site.example/host-version.json`) et
mettez à jour `public/host-version.json` à chaque nouvelle release du host.

## Fichiers

- `src/config.rs` — configuration (nom, mot de passe, port), assistant terminal, format texte simple
  (`clef=valeur`) volontairement choisi pour ne pas ajouter de dépendance (pas de crate TOML/YAML).
- `src/relay.rs` — le relais WebSocket lui-même (une connexion = un client, diffusion à tous les autres).
- `src/httpd.rs` — serveur HTTP minimal (fait main, sans framework) pour l'assistant web ; sert
  `host/ui/dist/` (construit par Vite) et une petite API `GET`/`POST /api/config`.
- `src/update.rs` — vérification de version via `curl` (pas de dépendance HTTP/TLS supplémentaire).
- `ui/` — l'assistant web (React + Vite). Noms de fichiers de build fixes (`app.js`, `app.css`, pas de hash)
  pour que `httpd.rs` puisse les inclure à la compilation avec des chemins stables.
