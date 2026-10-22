# GRNFR Host CMP

Serveur auto-hébergé pour GRNFR CMP : un relais WebSocket **sans limite de joueurs**, avec un nom et un mot
de passe facultatif. **App native Tauri — Rust (backend, relais + Supabase) + React/TypeScript (interface),
dans une seule fenêtre.** Même principe que des apps comme Ollama en desktop : un petit backend Rust et une
interface web rendue dans la fenêtre native de l'OS (pas un onglet de navigateur séparé, pas de serveur HTTP
local à ouvrir soi-même).

Assistant de configuration au premier lancement (nom, mot de passe facultatif, port — 30814 par défaut),
puis tableau de bord à sidebar dans la même fenêtre :
- **Tableau de bord** : statut (en ligne/arrêté), démarrer/arrêter le relais, bannière de mise à jour.
- **Joueurs** : qui est connecté (pseudo, adresse, depuis combien de temps), bouton Expulser.
- **Paramètres** : nom / mot de passe / port, enregistrés dans Supabase.

La configuration est stockée dans **Supabase** (pas de fichier local, pas de compte joueur requis — voir
plus bas), pour pouvoir la retrouver si vous changez de machine.

## ⚠️ À lire avant d'utiliser ce dossier

Ce code a été écrit **sans pouvoir être compilé ni testé localement** : l'environnement qui l'a produit n'a
ni `cargo` ni la chaîne de compilation Tauri installés. `.github/workflows/host-release.yml` le compile
réellement sur Windows, Linux et macOS à chaque tag `host-v*` (GitHub Actions, via `tauri-apps/tauri-action`)
et publie les installeurs en Release GitHub. Ce qui reste vrai malgré ça :
- Le frontend (React/TypeScript, `host/src/`) a été **construit et vérifié dans cette session** : `tsc`
  (vérification de types) et `vite build` passent sans erreur, et chaque écran (assistant, tableau de bord,
  joueurs, paramètres) a été affiché dans un navigateur avec des données simulées — rendu correct.
- Le **backend Rust** (`host/src-tauri/`), lui, n'a jamais pu être compilé localement : seule la réussite de
  la compilation CI est garantie, jamais le comportement réel (la fenêtre s'ouvre-t-elle vraiment ? le
  relais ? la lecture/écriture dans Supabase ? le téléchargement de mise à jour ?).
- **Ce host n'est PAS encore relié au mod BeamNG.** `mod/grnfr-mod/ui/ui-vue/mods/GRNFR/net.js` ne sait
  parler qu'à Supabase aujourd'hui. Brancher le mod sur ce relais (en plus de, ou à la place de, Supabase)
  est un travail à part, non commencé.
- Le relais ne fait que **transporter** les messages d'un client vers tous les autres, sans les comprendre
  (pas de physique, pas de vérification d'argent ou de position : ça reste le rôle de Supabase pour tout ce
  qui touche à l'argent). Il convient pour voir les autres joueurs (façon fantômes), pas pour une économie
  partagée fiable.
- **Mise à jour** : le bouton "Télécharger et installer" télécharge l'installeur natif de l'OS courant (NSIS
  sur Windows, .dmg sur macOS, .AppImage sur Linux) et le lance — contrairement à l'ancienne version (un
  seul binaire portable), un installeur Tauri ne peut pas se remplacer tout seul en place : l'utilisateur
  termine l'installation lui-même via l'assistant natif de son OS.

## Configuration dans Supabase

Pas de compte joueur requis. Au premier lancement, l'app génère un identifiant aléatoire (UUID v4) et le
garde dans `grnfr-host.id`, à côté de l'exécutable. Cet identifiant sert **à la fois de clé et de secret** :
qui le connaît peut lire/écrire la config de CE host (nom, mot de passe du relais, port) via deux fonctions
Supabase (`host_config_get`/`host_config_set`, voir `supabase/migrations/0011_host_config.sql`), appelées
avec la clé anonyme (`anon`) — personne ne se connecte, il n'y a pas de mot de passe de compte. Sécurité
« limitée, pas infaillible » (même logique que l'anti-cheat du reste du projet) : perdre `grnfr-host.id`,
c'est perdre l'accès à cette config ; le faire fuiter permet à quelqu'un d'autre de la modifier, rien de
plus (pas d'argent, pas de compte joueur, pas d'accès aux autres tables).

Une copie locale (`grnfr-host.cache`) est gardée pour pouvoir démarrer même hors ligne ; toujours écrasée
par ce qui vient de Supabase dès que c'est possible. `grnfr-host.log` garde une trace de ce qui se passe
(démarrage, erreurs de port, connexions/déconnexions) — il n'y a pas de console (voir plus bas).

**Les migrations 0001 à 0011 doivent déjà être appliquées** (ce sont celles du mod/site), 0011 en particulier
pour que cette config puisse s'enregistrer.

## Construire

```
cd host
npm install
npm run tauri build
```

Ou directement avec la CLI Tauri (`npx tauri build`). Les installeurs sortent dans
`host/src-tauri/target/release/bundle/` (NSIS sous Windows, `.dmg` sous macOS, `.AppImage` sous Linux —
voir `tauri.conf.json` → `bundle.targets`). Sans `SUPABASE_URL` et `SUPABASE_ANON_KEY` définis en variables
d'environnement AU MOMENT de la compilation (`option_env!`, voir `src-tauri/src/supabase.rs`), l'app compile
quand même mais ne pourra jamais lire/écrire sa config. La CI les passe depuis des secrets du dépôt (déjà
configurés : `SUPABASE_URL`, `SUPABASE_ANON_KEY`).

Sur Linux, la compilation a besoin de paquets système (voir le `apt-get install` du workflow CI :
`libwebkit2gtk-4.1-dev`, etc.) ; rien de supplémentaire n'est requis à l'exécution sur une installation
Linux de bureau standard (webkit2gtk fait partie de la plupart des environnements de bureau).

## Développer

```
cd host
npm install
npm run tauri dev
```

Ouvre la fenêtre avec rechargement à chaud du frontend (React/Vite). Le backend Rust (relais, Supabase) est
recompilé à chaque changement dans `src-tauri/`.

## Utiliser

- **Pas de console.** Au premier lancement, l'assistant de configuration s'affiche directement dans la
  fenêtre (nom du serveur, mot de passe facultatif, port — 30814 par défaut). Une fois enregistré, le relais
  démarre et la fenêtre passe au tableau de bord.
- **Lancements suivants** : la config est relue depuis Supabase (ou le cache local si hors ligne), le relais
  démarre tout de suite, direction le tableau de bord.
- **Aucune limite de joueurs** : contrairement aux serveurs créés dans Supabase (4 joueurs maximum), ce
  relais accepte autant de connexions que votre machine et votre réseau le permettent.
- **Mot de passe** : s'il y en a un, chaque client doit l'envoyer dans son premier message
  (`{"type":"hello","username":"...","password":"..."}`) ; sinon la connexion est refusée
  (`{"type":"error","error":"bad_password"}`). Sans mot de passe, n'importe qui connaissant l'adresse et le
  port peut rejoindre.
- **Accès depuis l'extérieur** : si vos joueurs ne sont pas sur le même réseau local, ouvrez le port choisi
  (TCP, WebSocket) sur votre routeur/pare-feu vers la machine qui fait tourner l'app.

## Fichiers

- `src-tauri/src/config.rs` — struct `Config` (nom, mot de passe, port), identifiant local
  (`grnfr-host.id`) et cache hors-ligne (`grnfr-host.cache`).
- `src-tauri/src/supabase.rs` — lecture/écriture de la config dans Supabase (`host_config_get`/
  `host_config_set`), clé anon fixée à la compilation (`option_env!`).
- `src-tauri/src/relay.rs` — le relais WebSocket (une connexion = un client, diffusion à tous les autres),
  via `ServerState` : démarrage/arrêt à la demande, liste des clients connectés, expulsion.
- `src-tauri/src/commands.rs` — les commandes Tauri (`#[tauri::command]`) exposées au frontend : statut,
  démarrer/arrêter, expulser, enregistrer la config, vérifier/installer une mise à jour.
- `src-tauri/src/updater.rs` — vérifie la dernière release GitHub, télécharge l'installeur correspondant à
  l'OS courant et le lance.
- `src-tauri/src/logger.rs` — écrit dans `grnfr-host.log` ce qu'une console aurait affiché (il n'y en a pas).
- `src-tauri/src/lib.rs` / `main.rs` — démarrage : vérifie Supabase pour une config existante, démarre le
  relais si trouvée, ouvre la fenêtre.
- `src/` — le frontend React/TypeScript : `App.tsx` (bascule assistant/tableau de bord selon l'état),
  `components/SetupWizard.tsx`, `components/{Overview,Players,Settings}.tsx`, `api.ts` (wrappers typés
  autour des commandes Tauri).
- `icon-src.png` — image source (1024×1024) utilisée pour générer `src-tauri/icons/` via
  `npx tauri icon icon-src.png -o src-tauri/icons` (déjà fait ; à relancer seulement si l'icône change).
