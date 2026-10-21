# GRNFR Host CMP

Serveur auto-hébergé pour GRNFR CMP : un relais WebSocket **sans limite de joueurs**, avec un nom et un
mot de passe facultatif. **App native, écrite en Rust (egui/eframe) — pas de HTML, pas de navigateur, pas de
serveur web local.** Assistant de configuration au premier lancement, puis un tableau de bord dans la même
fenêtre. La configuration (nom, mot de passe, port) est stockée dans **Supabase**, pas dans un fichier local
— voir « Configuration dans Supabase » plus bas.

Le tableau de bord permet, sans quitter le programme :
- de voir qui est connecté (pseudo, adresse, depuis combien de temps) ;
- de démarrer / arrêter le relais ;
- d'expulser un joueur connecté ;
- de modifier nom / mot de passe / port (port 30814 par défaut) — un changement de port ou de mot de passe
  n'est repris qu'au prochain démarrage du relais (bouton Arrêter puis Démarrer), pas besoin de fermer le
  programme ;
- de télécharger et installer une mise à jour en un clic quand une nouvelle version est détectée.

## ⚠️ À lire avant d'utiliser ce dossier

Ce code a été écrit **sans pouvoir être compilé ni testé localement** : l'environnement qui l'a produit n'a
ni `cargo` ni `rustc` installés, et ne peut pas afficher de fenêtre graphique. Depuis,
`.github/workflows/host-release.yml` le compile réellement sur Windows, Linux et macOS à chaque tag
`host-v*` (GitHub Actions, qui a un vrai toolchain Rust) et publie les binaires en Release GitHub — **ça
compile sans erreur sur les 3 OS**. Ce qui reste vrai malgré ça :
- La compilation réussit, mais **personne n'a lancé le binaire et vérifié qu'il marche en pratique** (la
  fenêtre s'ouvre-t-elle vraiment ? le relais ? la lecture/écriture dans Supabase ? la mise à jour
  automatique, qui remplace le binaire en cours d'exécution — voir `src/updater.rs` ?) : seule la
  compilation est vérifiée, jamais le comportement réel.
- **Ce host n'est PAS encore relié au mod BeamNG.** `mod/grnfr-mod/ui/ui-vue/mods/GRNFR/net.js` ne sait
  parler qu'à Supabase aujourd'hui. Brancher le mod sur ce relais (en plus de, ou à la place de, Supabase)
  est un travail à part, non commencé.
- Le relais ne fait que **transporter** les messages d'un client vers tous les autres, sans les comprendre
  (pas de physique, pas de vérification d'argent ou de position : ça reste le rôle de Supabase pour tout ce
  qui touche à l'argent). Il convient pour voir les autres joueurs (façon fantômes), pas pour une économie
  partagée fiable.

## Configuration dans Supabase

Pas de compte joueur requis. Au premier lancement, l'app génère un identifiant aléatoire (UUID v4) et le
garde dans `grnfr-host.id`, à côté de l'exécutable. Cet identifiant sert **à la fois de clé et de secret** :
qui le connaît peut lire/écrire la config de CE host (nom, mot de passe du relais, port) via deux fonctions
Supabase (`host_config_get`/`host_config_set`, voir `supabase/migrations/0011_host_config.sql`), appelées
avec la clé anonyme (`anon`) — personne ne se connecte, il n'y a pas de mot de passe de compte. Sécurité
« limitée, pas infaillible » (même logique que l'anti-cheat du reste du projet) : perdre `grnfr-host.id`,
c'est perdre l'accès à cette config (il faudra en recréer une) ; le faire fuiter permet à quelqu'un d'autre
de la modifier, rien de plus (pas d'argent, pas de compte joueur, pas d'accès aux autres tables).

Une copie locale (`grnfr-host.cache`) est gardée pour pouvoir démarrer même si Supabase est injoignable au
lancement ; elle est toujours écrasée par ce qui vient de Supabase dès que c'est possible.

**La migration 0001 à 0010 doivent déjà être appliquées** (ce sont celles du mod/site) ; lancez aussi
`0011_host_config.sql` une fois dans Supabase (SQL Editor) avant d'utiliser le host.

## Construire

```
cd host
cargo build --release
```

Le binaire est `host/target/release/grnfr-host` (ou `.exe` sous Windows). Sans `SUPABASE_URL` et
`SUPABASE_ANON_KEY` définis en variables d'environnement AU MOMENT de `cargo build` (voir `src/supabase.rs`,
`option_env!`), le binaire compile quand même mais ne pourra jamais lire/écrire sa config (message d'erreur
clair dans la fenêtre). La CI (`.github/workflows/host-release.yml`) les passe depuis des secrets du dépôt —
**à ajouter vous-même** : Settings → Secrets and variables → Actions → New repository secret, deux fois
(`SUPABASE_URL`, `SUPABASE_ANON_KEY`, les mêmes valeurs que dans `.env` à la racine du projet).

Sur Linux, la fenêtre native (egui/eframe) a besoin de paquets système au moment de compiler (voir le
`apt-get install` dans le workflow) ; pas de paquet supplémentaire requis à l'exécution sur une installation
Linux de bureau standard.

## Utiliser

```
./grnfr-host
```

- **Pas de console.** Au premier lancement, une fenêtre s'ouvre directement avec l'assistant de
  configuration (nom du serveur, mot de passe facultatif, port — 30814 par défaut). Une fois enregistré
  (bouton « Enregistrer et démarrer »), le relais démarre et la fenêtre passe au tableau de bord.
- **Lancements suivants** : la config est relue depuis Supabase (ou le cache local si hors ligne), le relais
  démarre tout de suite, la fenêtre ouvre directement sur le tableau de bord.
- **Tableau de bord** : statut (en ligne/arrêté) avec boutons Démarrer/Arrêter, liste des joueurs connectés
  avec bouton Expulser par joueur, section Paramètres repliable (nom/mot de passe/port — Enregistrer envoie
  à Supabase), et une bannière si une nouvelle version est disponible.
- **Mise à jour** : au démarrage, l'app interroge l'API GitHub Releases de ce dépôt. Si une version plus
  récente existe, un bouton « Télécharger et installer » apparaît : il télécharge le binaire correspondant
  à votre OS, met l'actuel de côté (`.bak`, gardé, jamais supprimé — en cas de problème, renommez-le à la
  main pour revenir en arrière), installe le nouveau et relance le programme automatiquement. **Jamais
  testé** (voir l'avertissement en haut de ce fichier) : cette étape remplace un exécutable en cours
  d'exécution, ce qui est permis mais pas garanti identique sur les trois OS.
- **Journal** : comme il n'y a pas de console, ce qui aurait été affiché (démarrage, erreurs de port déjà
  utilisé, connexions/déconnexions, échecs réseau…) est écrit dans `grnfr-host.log` (même dossier), une
  ligne par événement. À consulter en cas de problème.
- **Aucune limite de joueurs** : contrairement aux serveurs créés dans Supabase (4 joueurs maximum), ce
  relais accepte autant de connexions que votre machine et votre réseau le permettent.
- **Mot de passe** : s'il y en a un, chaque client doit l'envoyer dans son premier message
  (`{"type":"hello","username":"...","password":"..."}`) ; sinon la connexion est refusée
  (`{"type":"error","error":"bad_password"}`). Sans mot de passe, n'importe qui connaissant l'adresse et le
  port peut rejoindre.
- **Accès depuis l'extérieur** : si vos joueurs ne sont pas sur le même réseau local, ouvrez le port choisi
  (TCP, WebSocket) sur votre routeur/pare-feu vers la machine qui fait tourner `grnfr-host`.

## Fichiers

- `src/config.rs` — struct `Config` (nom, mot de passe, port), identifiant local (`grnfr-host.id`) et cache
  hors-ligne (`grnfr-host.cache`, format texte simple `clef=valeur`).
- `src/supabase.rs` — lecture/écriture de la config dans Supabase (`host_config_get`/`host_config_set`),
  clé anon fixée à la compilation (`option_env!`).
- `src/relay.rs` — le relais WebSocket (une connexion = un client, diffusion à tous les autres), via
  `ServerState` : démarrage/arrêt à la demande, liste des clients connectés, expulsion.
- `src/gui.rs` — la fenêtre native (egui/eframe) : assistant de configuration + tableau de bord, un seul
  écran selon qu'une config a déjà été trouvée dans Supabase ou pas.
- `src/updater.rs` — vérifie la dernière release GitHub, télécharge et installe le binaire correspondant à
  l'OS courant par-dessus l'exécutable en cours d'exécution (renommé en `.bak`, jamais supprimé).
- `src/logger.rs` — écrit dans `grnfr-host.log` ce que la console aurait affiché (il n'y en a plus :
  `#![windows_subsystem = "windows"]` dans `main.rs`, sans effet sur Linux/macOS).
- `src/main.rs` — démarre un runtime tokio dédié (pour `relay.rs`) dans un thread séparé, charge la config,
  et ouvre la fenêtre native sur le thread principal (obligatoire sur macOS).
