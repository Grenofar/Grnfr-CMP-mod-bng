# GRNFR Host CMP

Serveur auto-hébergé pour GRNFR CMP : un relais WebSocket **sans limite de joueurs**, avec un nom et un
mot de passe facultatif, configuré par un assistant (terminal au premier lancement, puis un tableau de bord
web React à tout moment). Écrit en Rust (`host/`), interface en React (`host/ui/`).

Le tableau de bord web (`http://127.0.0.1:<port+1>`) permet, sans quitter le programme :
- de voir qui est connecté (pseudo, adresse, depuis combien de temps) ;
- de démarrer / arrêter le relais ;
- d'expulser un joueur connecté ;
- de modifier nom / mot de passe / port (port 30814 par défaut) — un changement de port ou de mot de passe
  n'est repris qu'au prochain démarrage du relais (bouton Arrêter puis Démarrer), pas besoin de fermer le
  programme.

## ⚠️ À lire avant d'utiliser ce dossier

Ce code a été écrit **sans pouvoir être compilé ni testé localement** : l'environnement qui l'a produit n'a
ni `cargo` ni `rustc` installés. Depuis, `.github/workflows/host-release.yml` le compile réellement sur
Windows, Linux et macOS à chaque tag `host-v*` (GitHub Actions, qui a un vrai toolchain Rust) et publie les
binaires en Release GitHub — **ça compile sans erreur sur les 3 OS**. Ce qui reste vrai malgré ça :
- La compilation réussit, mais **personne n'a lancé le binaire et vérifié qu'il marche en pratique**
  (assistant, relais WebSocket, assistant web) : seule la compilation est vérifiée, pas le comportement.
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
- **Tableau de bord** : ouvrez `http://127.0.0.1:<port+1>` dans un navigateur (il n'écoute que sur votre
  propre machine — pas depuis l'extérieur). Vous y voyez qui est connecté, pouvez démarrer/arrêter le relais,
  expulser un joueur, et changer nom/mot de passe/port (repris en cliquant Arrêter puis Démarrer, sans
  fermer le programme).
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
- `src/relay.rs` — le relais WebSocket (une connexion = un client, diffusion à tous les autres), via
  `ServerState` : démarrage/arrêt à la demande, liste des clients connectés, expulsion — partagé avec
  `httpd.rs` pour le tableau de bord.
- `src/httpd.rs` — serveur HTTP minimal (fait main, sans framework) pour le tableau de bord web ; sert
  `host/ui/dist/` (construit par Vite) et une petite API : `GET`/`POST /api/config`, `GET /api/status`,
  `POST /api/start`, `POST /api/stop`, `POST /api/kick`.
- `src/update.rs` — vérification de version via `curl` (pas de dépendance HTTP/TLS supplémentaire).
- `ui/` — l'assistant web (React + Vite). Noms de fichiers de build fixes (`app.js`, `app.css`, pas de hash)
  pour que `httpd.rs` puisse les inclure à la compilation avec des chemins stables.
