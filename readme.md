# GRNFR CMP — mod BeamNG « carrière multijoueur » + Supabase + site Vercel (+ host auto-hébergé)

Mod BeamNG.drive (dossier `mod/grnfr-mod/`) relié à un backend **Supabase** (`supabase/`) et distribué par un site **Vercel** (`public/` + `scripts/build.mjs`). Un serveur auto-hébergé optionnel (`host/`, Rust + React) existe en plus, séparément — voir § Host auto-hébergé.

Fonctions : argent donné par un admin, classement des fortunes, garage personnel (une tablette par place de serveur), annonces et échanges entre joueurs, chat de serveur, repérage d'un joueur, taxi (PNJ, courses entre joueurs, taxi IA), bus, courses de drag avec mise d'argent, **serveurs de jeu de 4 joueurs max où l'on voit les autres joueurs avec leur pseudo**, **2 voitures de trafic partagées par serveur**, pseudo obligatoire et unique. Il n'y a plus de mode « chase ».

## Mise en place (une seule fois)

### 1. Supabase
1. Créez un projet sur supabase.com.
2. **SQL Editor** → collez et lancez, **dans cet ordre** : `0001_grnfr_online.sql`, `0002_game_servers.sql`, `0003_convoy.sql`, `0004_mod_releases.sql`, `0005_chat.sql`, `0006_garage_spots.sql`, `0007_drag_races.sql` (dossier `supabase/migrations/`).
3. **Authentication → Providers → Email** : désactivez **« Confirm email »**.
4. **Project Settings → API** : notez l'**URL** du projet, la clé **anon public** (jamais `service_role`), et séparément la clé **service_role** (reste sur votre poste, voir § Releases).
5. Pour vous nommer admin, une fois votre compte créé : `update public.profiles set is_admin = true where username = 'VotrePseudo';`
6. Trois serveurs de jeu (4 joueurs max chacun) sont créés ; l'admin peut en ajouter depuis le site ou le jeu.

### 2. Vercel
1. Dépôt Git → importé dans Vercel (aucun framework : `vercel.json` suffit).
2. **Settings → Environment Variables** : `SUPABASE_URL` et `SUPABASE_ANON_KEY` (voir `.env.example`). **Jamais** `SUPABASE_SERVICE_ROLE_KEY` sur Vercel.
3. Déployez. Le build (`node scripts/build.mjs`) écrit l'URL/clé dans le mod et fabrique `/downloads/grnfr-online.zip`, avec `lua/`, `ui/`, `mod_info/`, `scripts/`, `settings/` **à la racine du zip**. Refuse de continuer sans `SUPABASE_URL`/`SUPABASE_ANON_KEY`, ou avec une clé `service_role`.
4. Le site propose : téléchargement de la dernière release + historique + classement (`/`), compte, garage, annonces, serveurs, historique (`/account.html`), administration (`/admin.html`).

### 3. Releases du mod (`npm run release`)
`index.html` affiche la **dernière release publiée sur Supabase Storage** (repli sur le zip statique si aucune release n'existe encore).
```
SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE_KEY=... npm run release -- "Notes de version"
```
Change `VERSION` dans `grnfr.lua` **et** `version` dans `mod_info/grnfr/info.json` avant de publier (refuse sinon : version déjà prise). Dans le jeu, la fenêtre GRNFR CMP affiche un bandeau « mise à jour disponible » en comparant à `get_latest_release()`.

### 4. Les joueurs
Copier le zip **sans le dézipper** dans le dossier `mods` de BeamNG, activer « GRNFR CMP », lancer une carte en jeu libre.
- **Menu principal → bouton « GRNFR CMP »** : un seul bouton, qui ouvre la fenêtre complète (compte, serveurs — une case par serveur avec nom et joueurs connectés —, garage, réglages...), même sans carte chargée.
- **Touche O** : fenêtre complète (compte, serveurs, garage, marché, taxi, bus).
- **Touche J** : petite fenêtre rapide (chat, joueurs, courses de drag) — voir ci-dessous.

## Serveurs de jeu : comment ça marche, et ses limites
- Un joueur n'est que sur **un** serveur à la fois, **4 maximum** (verrouillé côté base). Place libérée après 30 s sans signal.
- **Pseudo obligatoire et unique** (3–20 lettres/chiffres/_, insensible à la casse) : vérifié à l'inscription, refusé par la base sinon ; `join_server` refuse tout compte sans pseudo confirmé.
- Chaque joueur envoie ~3 fois/s sa position/rotation/vitesse/véhicule via `server_sync` et reçoit celles des autres ; un **fantôme** par joueur distant, avec son **pseudo** au-dessus (`ghosts.lua`).
- **Trafic partagé (2 voitures)** : le membre présent depuis le plus longtemps sur le serveur (« hôte », recalculé à chaque synchronisation, aucune élection explicite) fait rouler 2 voitures IA et envoie leur position ; les autres les voient en fantômes, sans collision. Hôte parti → relais automatique au suivant par ancienneté (`convoy.lua`, `0003_convoy.sql`).
- **Garage personnel (une tablette par place de serveur)** : chaque serveur a autant de garages que de places (4), attribués au fil des besoins et mémorisés côté base (`garage_spots`, `0006_garage_spots.sql`) — le garage reste au même endroit tant que son propriétaire reste sur le serveur, et une place abandonnée (propriétaire parti) est récupérée par quelqu'un d'autre. L'onglet Garage ne s'ouvre qu'à proximité de **votre** garage (~10 m, marqueur au sol visible à 150 m) ; les garages des autres sont visibles mais jamais utilisables par vous (`garage.lua`).
- **Chat de serveur** (`0005_chat.sql`, `chat.lua`) : messages entre membres du même serveur uniquement, historique de 2 h, affiché dans la fenêtre rapide (touche J).
- **Repérer un joueur** (`track.lua`) : dans la fenêtre rapide, bouton « Suivre » sur un joueur → un point au sol suit sa position (mise à jour à chaque synchronisation, ~2-3 fois/s). N'importe qui peut suivre n'importe qui du même serveur (positions déjà visibles via les fantômes).
- **Donner de l'argent / échanger un véhicule** depuis la fenêtre rapide : raccourcis vers les mêmes fonctions RPC que la fenêtre complète (`send_money`, `propose_trade`) — rien de nouveau côté argent.
- **Courses de drag** (`0007_drag_races.sql`, `drag.lua`) : un joueur marque un départ et une arrivée (position actuelle) et propose la course (une seule à la fois par serveur) ; les autres misent un montant (presets 100 à 50 000, ou libre — débité immédiatement, remboursé en cas de désistement ou d'annulation) ; l'hôte lance (2 joueurs mini) ; **anti faux départ** : chaque voiture est bloquée (frein de parking + embrayage, voir note plus bas) pendant le 3-2-1, relâchée au TOP ; chacun signale son temps en franchissant l'arrivée ; le plus rapide empoche tout le pot. Temps physiquement impossibles refusés (`drag_max_speed_mps`), comme pour le taxi — **limité, pas infaillible**.
- **Ce n'est pas du vrai multijoueur** : pas de physique partagée ni de collisions (joueurs ou trafic). Pour une conduite synchronisée, BeamMP en plus ; le mod fonctionne aussi dessous.
- L'argent reste 100 % côté serveur (fonctions RPC `security definer`, jamais d'écriture directe cliente).

## Host auto-hébergé (`host/`, séparé du reste)
Un programme Rust (`host/`) + une petite page de configuration React (`host/ui/`) pour héberger **son propre
serveur**, sans limite de joueurs, avec un nom et un mot de passe facultatif. **Indépendant de Supabase** et
**pas encore relié au mod** (`net.js` ne lui parle pas aujourd'hui) : voir `host/README.md` pour le détail,
l'état d'avancement réel et comment le construire. Son relais WebSocket transporte des messages sans les
comprendre (pas de physique, pas d'argent) ; ce n'est pas un remplacement de la partie Supabase du mod.

## ⚠️ Ce qui est testé et ce qui ne l'est pas
| Partie | Statut |
|---|---|
| SQL (schéma, RPC, droits, serveurs, trafic partagé, releases, chat, garages, drag, profils portables) | **Testé** sur Postgres 16 avec un faux Supabase (`supabase/tests/run.sh`) la dernière fois qu'un Postgres était disponible ; les vérifications ajoutées depuis (chat, garages, drag, 0008 profils/anti-partage) ont été écrites avec le même soin mais **jamais exécutées, aucun Postgres dans cette session** — à relancer avant de livrer. L'endpoint de connexion anonyme a été testé en direct contre le vrai projet Supabase (réponse `anonymous_provider_disabled` confirmée : il manque juste l'activer dans le tableau de bord) |
| Client réseau `net.js` | **Testé** (`node tests/net_test.mjs`, 18 vérifications). Deux bugs de chemin pré-existants corrigés (le test ne s'exécutait pas du tout avant) |
| `scripts/build.mjs` (racine du zip, garde-fous) | **Testé** (`unzip -l`, échec sans variables, échec avec une clé `service_role`) |
| Lua (taxi, bus, taxi IA, fantômes) | **Simulé** (`texlua tests/lua_sim.lua`) la dernière fois qu'un interpréteur Lua était disponible ; **non ré-exécuté dans cette session** |
| `garage.lua`, `convoy.lua`, `chat.lua`, `track.lua`, `drag.lua`, `profile.lua` (tout le nouveau Lua social/drag/profil) | **Jamais exécutés, ni simulés, ni en jeu.** Mêmes précautions que le reste (`pcall` partout), mais sans aucune vérification automatisée pour l'instant |
| `QuickPanel.vue`, fusion `OnlineWindow.vue`/`GrnfrPanel.vue` (un seul bouton, onglet Réglages embarqué, compte pseudo seul) | **Syntaxe JS vérifiée** (`node --check` sur chaque `<script setup>`), zip reconstruit sans erreur. **Jamais affichée dans le vrai jeu** : la mise en page de l'onglet Réglages embarqué (dimensions fixes de `GrnfrPanel` forcées à s'adapter) n'a pas pu être vue en vrai |
| Site (`public/`) : habillage visuel (arrière-plan animé CSS) | **Vérifié dans un navigateur** (serveur statique local), rendu correct. Pas de vraie image BeamNG (aucune disponible légitimement ici) : juste des lueurs CSS dans les couleurs du mod |
| **`host/` (Rust + React)** | **Compile réellement** sur Windows/Linux/macOS via `.github/workflows/host-release.yml` (GitHub Actions, un vrai toolchain Rust) ; binaires publiés en Release GitHub. Mais **jamais exécuté** : aucune vérification du comportement réel (assistant, relais, assistant web), seulement de la compilation. Voir `host/README.md` |
| **Le mod dans BeamNG, le site Vercel déployé, un vrai projet Supabase, `npm run release` contre un vrai bucket Storage, `grnfr-host` lancé et utilisé en conditions réelles** | **Jamais essayés** |

Les noms d'API BeamNG pour les fantômes, le trafic partagé et le blocage anti faux départ (`setPositionRotation`, `setGhostEnabled`, `ai.setMode('traffic')`, `input.event('parkingbrake'/'clutch', ...)`…) sont des hypothèses : la première session en jeu fera sortir des corrections (journal : `settings/grnfr/logs/`).

## Tests
```
PGHOST=/tmp PGPORT=54329 PGUSER=postgres supabase/tests/run.sh      # SQL (7 migrations, voir ci-dessus)
texlua scripts/check-lua.lua $(find mod/grnfr-mod/lua mod/grnfr-mod/scripts -name '*.lua')
texlua tests/lua_sim.lua                                            # Lua simulé
node tests/net_test.mjs                                             # client réseau
node scripts/build.mjs                                              # build du zip (variables SUPABASE_* à définir)
npm run release -- "notes"                                           # publie une release (SUPABASE_SERVICE_ROLE_KEY requis)

cd host/ui && npm install && npm run build && cd ..                 # assistant web du host (vérifié dans cette session)
cd host && cargo build --release                                   # host lui-même (compile via CI ; jamais exécuté)
```

## Architecture (pour reprendre le code)
- **Lua = logique de jeu, JS = transport HTTP** (BeamNG ne fait pas de HTTPS côté Lua). `online.lua` ↔ `net.js` via `GRNFRNetReq`/`onNetResult` ; `grnfr_online.call(fn, args, cb)` est le pont RPC générique réutilisé par `garage.lua`, `chat.lua` et `drag.lua` (aucune plomberie réseau supplémentaire nécessaire pour ces trois-là).
- `ghosts.lua` : position des joueurs (`GRNFRSelf`/`onSync`), et prévient `track.lua` à chaque réception pour le repérage. `convoy.lua` : même principe pour les 2 voitures de trafic (`GRNFRConvoySelf`), bascule hôte/invité décidée par `server_sync` (`is_host`). `garage.lua` : garage attribué par `claim_garage_spot`/`get_server_garage_spots`. `chat.lua` : `send_chat_message`/`get_chat_messages`, sondé toutes les 2 s. `drag.lua` : `propose_drag_race` → `join_drag_race` → `start_drag_race` → `report_drag_finish`, verrouillage frein+embrayage pendant le compte à rebours.
- `grnfr.lua` : `M.ui(nom, json)` = liste blanche des appels interface → jeu (`ROUTES`) ; touche **O** = fenêtre complète (`grnfr_online_toggle`, `OnlineWindow.vue` — aussi ouverte par l'unique bouton du menu principal), touche **J** = fenêtre rapide (`grnfr_quick_toggle`, `QuickPanel.vue`). Les réglages (HUD, FPS, langue, mods) sont un onglet de `OnlineWindow.vue` (`GrnfrPanel.vue` embarqué) : il n'y a plus de fenêtre séparée pour ça depuis le menu principal.
- Toute règle d'argent = fonction SQL `security definer` + test dans `supabase/tests/tests.sql`, invariant « solde = somme du journal » revérifié après chaque nouveau groupe de fonctionnalités. Clé `service_role` : jamais dans le mod ni le site, seulement dans l'environnement local de `scripts/release.mjs`.
- `host/` est un programme à part (Rust + React), sans dépendance au reste du dépôt ; voir `host/README.md`.

## Reste à faire / idées
- Relier `net.js` au relais `host/` (en plus de, ou à la place de, Supabase) : non commencé.
- Lancer `grnfr-host` pour de vrai et vérifier qu'il marche (compilé par CI, jamais exécuté).
- Même bouton unique dans le menu pause (aujourd'hui, le menu pause garde l'ancien onglet Mods > GrnfrPanel seul, sans compte/serveurs).
- Habillage visuel du site : pas d'image BeamNG réelle utilisée (aucune disponible légitimement ici) — juste des lueurs animées en CSS dans les couleurs du mod. À remplacer par de vraies captures si vous en avez le droit.
- Limiter les courses de taxi entre joueurs à un même serveur de jeu (actuellement par carte) ; option `taxi_require_passenger_near`.
- Couleur du véhicule sur les fantômes, réglage de la cadence selon la latence.
- Première session en jeu : vérifier toutes les hypothèses d'API listées ci-dessus, en particulier le verrouillage anti faux départ des courses de drag et `ai.setMode('traffic')`.
