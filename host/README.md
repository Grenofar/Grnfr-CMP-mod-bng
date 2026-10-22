# GRNFR Host CMP

Serveur auto-hébergé pour GRNFR CMP : un relais WebSocket **sans limite de joueurs**, avec un nom et un mot
de passe facultatif, et **plusieurs serveurs par installation, lançables en même temps** (chacun son port).
**App native Tauri — Rust (backend, relais + Supabase) + React/TypeScript (interface), dans une seule
fenêtre.** Même principe que des apps comme Ollama en desktop : un petit backend Rust et une interface web
rendue dans la fenêtre native de l'OS (pas un onglet de navigateur séparé, pas de serveur HTTP local à ouvrir
soi-même).

Assistant de création au premier lancement (nom, mot de passe facultatif, port — 30814 par défaut), puis
tableau de bord à sidebar dans la même fenêtre :
- **Sidebar** : "Tableau de bord" + un item par serveur créé (pastille verte/rouge = en ligne/arrêté) +
  "Nouveau serveur".
- **Tableau de bord** : tous les serveurs en un coup d'œil, démarrage/arrêt rapide, bannière de mise à jour.
- **Détail d'un serveur** (en cliquant dessus) : sous-onglets Aperçu (statut, démarrer/arrêter), Joueurs
  (pseudo, adresse, depuis combien de temps, bouton Expulser), Paramètres (nom/mot de passe/port, bouton
  Supprimer ce serveur).

La configuration de chaque serveur est stockée dans **Supabase** (pas de fichier local, pas de compte joueur
requis — voir plus bas), pour pouvoir la retrouver si vous changez de machine.

## ⚠️ À lire avant d'utiliser ce dossier

Ce code a été écrit **sans pouvoir être compilé ni testé localement** : l'environnement qui l'a produit n'a
ni `cargo` ni la chaîne de compilation Tauri installés. `.github/workflows/host-release.yml` le compile
réellement sur Windows, Linux et macOS à chaque tag `host-v*` (GitHub Actions, via `tauri-apps/tauri-action`)
et publie les installeurs en Release GitHub. Ce qui reste vrai malgré ça :
- Le frontend (React/TypeScript, `host/src/`) a été **construit et vérifié dans cette session** : `tsc`
  (vérification de types) et `vite build` passent sans erreur, et chaque écran (assistant premier lancement,
  tableau de bord avec plusieurs serveurs, détail d'un serveur et ses 3 sous-onglets, création d'un nouveau
  serveur) a été affiché dans un navigateur avec des données simulées — rendu correct.
- Le **backend Rust** (`host/src-tauri/`), lui, n'a jamais pu être compilé localement : seule la réussite de
  la compilation CI est garantie, jamais le comportement réel (la fenêtre s'ouvre-t-elle vraiment ? le
  relais, sur plusieurs ports à la fois ? la lecture/écriture dans Supabase ? la mise à jour signée ?).
- **Ce host n'est PAS encore relié au mod BeamNG.** `mod/grnfr-mod/ui/ui-vue/mods/GRNFR/net.js` ne sait
  parler qu'à Supabase aujourd'hui. Brancher le mod sur ce relais (en plus de, ou à la place de, Supabase)
  est un travail à part, non commencé.
- Le relais ne fait que **transporter** les messages d'un client vers tous les autres, sans les comprendre
  (pas de physique, pas de vérification d'argent ou de position : ça reste le rôle de Supabase pour tout ce
  qui touche à l'argent). Il convient pour voir les autres joueurs (façon fantômes), pas pour une économie
  partagée fiable.
- **Mise à jour réelle et automatique** (`@tauri-apps/plugin-updater`, officiel, pas de code maison) :
  contrairement à une version antérieure de ce host qui téléchargeait l'installeur et le laissait à
  l'utilisateur, la mise à jour est maintenant **signée cryptographiquement** et s'installe **toute seule**
  (voir "Mises à jour signées" plus bas) — mais ça aussi, ça n'a jamais tourné en vrai.

## Plusieurs serveurs, en même temps

Chaque serveur créé obtient son propre id (ligne `host_servers` dans Supabase), son propre port, et son
propre relais WebSocket (`ServerInstance` dans `relay.rs`) — démarrer ou arrêter l'un n'affecte pas les
autres. `HostState` (aussi dans `relay.rs`) garde la liste de tous les `ServerInstance` connus de cette
installation. Au démarrage de l'app, **tous les serveurs connus sont relancés automatiquement**. Deux
serveurs sur le même port se comporteraient comme n'importe quel conflit de port TCP : le second refuse de
démarrer (erreur renvoyée à l'écran, rien de spécifique à gérer côté code).

## Configuration dans Supabase

Pas de compte joueur requis. Au premier lancement, l'app génère un identifiant aléatoire (UUID v4) et le
garde dans `grnfr-host.id`, à côté de l'exécutable — un identifiant pour **toute l'installation**, pas par
serveur. Cet identifiant sert **à la fois de clé et de secret** : qui le connaît peut lire/écrire TOUS les
serveurs de CETTE installation (nom, mot de passe du relais, port — voir
`supabase/migrations/0012_host_multi_server.sql`, fonctions `host_servers_list`/`host_server_upsert`/
`host_server_delete`), appelées avec la clé anonyme (`anon`) — personne ne se connecte, il n'y a pas de mot
de passe de compte. Sécurité « limitée, pas infaillible » (même logique que l'anti-cheat du reste du
projet) : perdre `grnfr-host.id`, c'est perdre l'accès à ces serveurs ; le faire fuiter permet à quelqu'un
d'autre de les modifier, rien de plus (pas d'argent, pas de compte joueur, pas d'accès aux autres tables).

Une copie locale (`grnfr-host.cache`, JSON) est gardée pour pouvoir démarrer même hors ligne ; toujours
écrasée par ce qui vient de Supabase dès que c'est possible. `grnfr-host.log` garde une trace de ce qui se
passe (démarrage, erreurs de port, connexions/déconnexions) — il n'y a pas de console (voir plus bas).

**Les migrations 0001 à 0012 doivent déjà être appliquées** (0001-0011 sont celles du mod/site ; 0012 ajoute
le support multi-serveur et migre automatiquement l'éventuelle config unique de 0011).

## Mises à jour signées

Le plugin officiel `tauri-plugin-updater` **exige** une signature cryptographique sur chaque mise à jour
(pas désactivable). La clé privée vit dans `.tauri-keys/grnfr-host.key` à la racine du dépôt, générée avec
`npx tauri signer generate -w ../.tauri-keys/grnfr-host.key` (depuis `host/`) — **gitignorée, jamais
commitée**. La clé publique correspondante est dans `src-tauri/tauri.conf.json` →
`plugins.updater.pubkey`. Si la clé privée est perdue, impossible de publier une mise à jour que les apps
déjà installées accepteront — gardez-en une copie de sauvegarde hors du dépôt.

La CI a besoin de `TAURI_SIGNING_PRIVATE_KEY` et `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` en secrets du dépôt
(Settings → Secrets and variables → Actions) pour signer les builds et générer `latest.json` (fait
automatiquement par `tauri-apps/tauri-action`, publié dans chaque Release GitHub). L'app vérifie les mises à
jour sur `https://github.com/Grenofar/Grnfr-CMP-mod-bng/releases/latest/download/latest.json`
(`tauri.conf.json` → `plugins.updater.endpoints`).

## Construire

```
cd host
npm install
npm run tauri build
```

Les installeurs sortent dans `host/src-tauri/target/release/bundle/` (NSIS sous Windows, `.dmg` sous macOS,
`.AppImage` sous Linux — voir `tauri.conf.json` → `bundle.targets`). Variables d'environnement nécessaires
AU MOMENT de la compilation :
- `SUPABASE_URL` / `SUPABASE_ANON_KEY` (`option_env!`, voir `src-tauri/src/supabase.rs`) — sans elles l'app
  compile quand même mais ne peut jamais lire/écrire ses serveurs.
- `TAURI_SIGNING_PRIVATE_KEY` / `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — sans elles l'app compile et tourne
  quand même, juste sans artefacts de mise à jour signés (pas de `.sig`, pas de `latest.json`).

Tous les quatre sont déjà configurés comme secrets du dépôt pour la CI.

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

- **Pas de console.** Au premier lancement, l'assistant de création de serveur s'affiche directement dans la
  fenêtre (nom, mot de passe facultatif, port — 30814 par défaut). Une fois créé, le relais démarre et la
  fenêtre passe au tableau de bord.
- **Lancements suivants** : la liste des serveurs est relue depuis Supabase (ou le cache local si hors
  ligne), tous redémarrent automatiquement, direction le tableau de bord.
- **Aucune limite de joueurs** par serveur : contrairement aux serveurs créés dans Supabase (4 joueurs
  maximum), chaque relais accepte autant de connexions que votre machine et votre réseau le permettent.
- **Mot de passe** : s'il y en a un, chaque client doit l'envoyer dans son premier message
  (`{"type":"hello","username":"...","password":"..."}`) ; sinon la connexion est refusée
  (`{"type":"error","error":"bad_password"}`). Sans mot de passe, n'importe qui connaissant l'adresse et le
  port peut rejoindre.
- **Accès depuis l'extérieur** : si vos joueurs ne sont pas sur le même réseau local, ouvrez le port choisi
  (TCP, WebSocket) sur votre routeur/pare-feu vers la machine qui fait tourner l'app — un port par serveur.

## Fichiers

- `src-tauri/src/config.rs` — struct `Config` (nom, mot de passe, port) pour UN serveur, identifiant
  d'installation local (`grnfr-host.id`) et cache hors-ligne de la liste complète (`grnfr-host.cache`).
- `src-tauri/src/supabase.rs` — liste/création/modification/suppression des serveurs dans Supabase
  (`host_servers_list`/`host_server_upsert`/`host_server_delete`), clé anon fixée à la compilation.
- `src-tauri/src/relay.rs` — `ServerInstance` (un relais WebSocket = un serveur) et `HostState` (la liste de
  tous les `ServerInstance` de cette installation) : démarrage/arrêt indépendant, clients connectés,
  expulsion.
- `src-tauri/src/commands.rs` — les commandes Tauri (`#[tauri::command]`) exposées au frontend :
  `list_servers`, `create_server`, `update_server`, `delete_server`, `start_server`, `stop_server`,
  `kick_player`. Les mises à jour ne passent pas par ici (voir plus bas).
- `src-tauri/src/logger.rs` — écrit dans `grnfr-host.log` ce qu'une console aurait affiché (il n'y en a pas).
- `src-tauri/src/lib.rs` / `main.rs` — démarrage : enregistre les plugins (`updater`, `process`), charge la
  liste des serveurs depuis Supabase, les relance tous, ouvre la fenêtre.
- `src/` — le frontend React/TypeScript : `App.tsx` (bascule assistant premier lancement / tableau de bord
  selon la liste), `components/Sidebar.tsx` (liste dynamique des serveurs), `components/AllServers.tsx`
  (tableau de bord), `components/ServerDetail.tsx` (un serveur, 3 sous-onglets),
  `components/{ServerForm,NewServer}.tsx` (création/édition), `components/UpdateBanner.tsx` (utilise
  `@tauri-apps/plugin-updater` directement, pas de commande Rust maison), `api.ts` (wrappers typés autour
  des commandes Tauri).
- `icon-src.png` — image source (1024×1024) utilisée pour générer `src-tauri/icons/` via
  `npx tauri icon icon-src.png -o src-tauri/icons` (déjà fait ; à relancer seulement si l'icône change).
- `.tauri-keys/grnfr-host.key` (racine du dépôt, gitignoré) — clé privée de signature des mises à jour.
  **Jamais commitée.**
