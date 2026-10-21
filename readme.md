# GRNFR Online — mod BeamNG « carrière multijoueur » + Supabase + site Vercel

Mod BeamNG.drive (dossier `mod/`) relié à un backend **Supabase** (`supabase/`) et distribué par un site **Vercel** (`public/` + `scripts/build.mjs`).

Fonctions : argent donné par un admin, classement des fortunes, garage de 4 places, annonces et échanges entre joueurs, taxi (PNJ, courses entre joueurs, taxi IA), bus, **serveurs de jeu de 4 joueurs max où l'on voit les autres joueurs avec leur pseudo**, pseudo obligatoire et unique.

## Mise en place (une seule fois)

### 1. Supabase
1. Créez un projet sur supabase.com.
2. **SQL Editor** → collez et lancez, dans cet ordre : `supabase/migrations/0001_grnfr_online.sql` puis `supabase/migrations/0002_game_servers.sql`.
3. **Authentication → Providers → Email** : désactivez **« Confirm email »** (sinon l'inscription depuis le jeu demande d'abord de cliquer un lien reçu par e-mail ; le mod le gère mais c'est moins fluide).
4. **Project Settings → API** : notez l'**URL** du projet et la clé **anon public** (jamais la clé `service_role`).
5. Pour vous nommer admin, une fois votre compte créé : `update public.profiles set is_admin = true where username = 'VotrePseudo';`
6. Trois serveurs de jeu (« Serveur 1 à 3 », 4 joueurs max) sont créés ; l'admin peut en ajouter depuis le site ou le jeu.

### 2. Vercel
1. Mettez ce dossier dans un dépôt Git (GitHub) et importez-le dans Vercel (aucun framework : `vercel.json` suffit).
2. **Settings → Environment Variables** : `SUPABASE_URL` et `SUPABASE_ANON_KEY` (voir `.env.example`).
3. Déployez. Le build (`node scripts/build.mjs`, aucune dépendance) écrit l'URL et la clé dans le mod et fabrique `/downloads/grnfr-online.zip`. Il refuse de continuer si la clé est une `service_role`.
4. Le site propose : téléchargement + classement public (`/`), compte, garage, annonces, serveurs, historique (`/account.html`), administration (`/admin.html`).

### 3. Les joueurs
Copier le zip **sans le dézipper** dans le dossier `mods` de BeamNG, activer « GRNFR Mod », lancer une carte en jeu libre, touche **O** → Compte (créer un compte avec un pseudo unique) → Serveurs → Rejoindre.

## Serveurs de jeu : comment ça marche, et ses limites
- Un joueur ne peut être que sur **un** serveur à la fois, **4 maximum** (limite appliquée côté base sous verrou : pas de dépassement même si 2 joueurs arrivent en même temps). Une place est libérée après 30 s sans signal.
- **Pseudo obligatoire et unique** (insensible à la casse, 3–20 lettres/chiffres/_) : vérifié à l'inscription (en direct dans le jeu et sur le site), refusé par la base sinon, et `join_server` refuse tout compte sans pseudo choisi (`username_required`). Les anciens comptes au pseudo généré doivent en choisir un (`set_username`).
- Chaque joueur envoie ~3 fois/s la position, la rotation, la vitesse et le modèle de son véhicule (ou de son personnage à pied) via `server_sync` ; il reçoit en retour les autres joueurs du serveur. Le mod fait apparaître un **véhicule « fantôme »** par joueur distant, le déplace en lissant, et affiche son **pseudo** au-dessus.
- **Ce n'est pas du vrai multijoueur** : pas de physique partagée ni de collisions entre joueurs, un léger retard est normal (réseau + 3 mises à jour/s). Pour de la conduite réellement synchronisée, il faut BeamMP en plus ; le mod fonctionne aussi dessous.
- L'argent reste 100 % côté serveur : le client n'a aucun droit d'écriture sur les tables, seulement des fonctions RPC qui vérifient tout.

## ⚠️ Ce qui est testé et ce qui ne l'est pas
| Partie | Statut |
|---|---|
| SQL (schéma, RPC, droits, serveurs, pseudos) | **Testé** sur Postgres 16 avec un faux Supabase : 56 vérifications (`supabase/tests/run.sh`), dont l'invariant « solde = somme du journal » |
| Client réseau `net.js` | **Testé** avec un faux Supabase (`node tests/net_test.mjs`) : inscription refusée si pseudo pris, serveur plein, reprise de place, pont Lua |
| Lua (taxi, bus, taxi IA, fantômes) | **Simulé** avec une fausse API BeamNG (`texlua tests/lua_sim.lua`) |
| Interface Vue | **Compile** (templates + SCSS vérifiés), jamais affichée dans le vrai jeu |
| Build du zip | **Testé** (`unzip -t`, placeholders remplacés, garde-fou service_role) |
| **Le mod dans BeamNG, le site Vercel déployé, un vrai projet Supabase** | **Jamais essayés** |

Les noms d'API BeamNG utilisés pour les fantômes (`setPositionRotation`, `setGhostEnabled`, `debugDrawer:drawTextAdvanced`, `partConfig`…) sont des hypothèses : la première session en jeu fera sortir des corrections (journal : `settings/grnfr/logs/`). Anti-triche des missions : la position vient du client, un tricheur est **limité** par le plafond horaire (`npc_income_cap_per_hour`), pas empêché.

## Tests
```
PGHOST=/tmp PGPORT=54329 PGUSER=postgres supabase/tests/run.sh      # SQL
texlua scripts/check-lua.lua $(find mod/lua mod/scripts -name '*.lua')
texlua tests/lua_sim.lua                                            # Lua simulé
node tests/net_test.mjs                                             # client réseau
node scripts/build.mjs                                              # build du zip (variables SUPABASE_* à définir)
```

## Architecture (pour reprendre le code)
- **Lua = logique de jeu, JS = transport HTTP** (le Lua de BeamNG ne fait pas de HTTPS). `online.lua` ↔ `net.js` via les événements `GRNFRNetReq` / `onNetResult`.
- `ghosts.lua` : envoie l'état du joueur (`GRNFRSelf`), reçoit les autres (`onSync`), gère fantômes et pseudos. `net.js` : jeton Supabase, `server_sync`, `heartbeat`, rejoin automatique.
- `grnfr.lua` : `M.ui(nom, json)` = liste blanche des appels interface → jeu (`ROUTES`, dont `server.state`) ; touche **O** = `grnfr_online_toggle`.
- Toute règle d'argent = fonction SQL `security definer` + test dans `supabase/tests/tests.sql`. Ne jamais mettre la clé `service_role` dans le mod ni sur le site.

## Reste à faire / idées
- Option `taxi_require_passenger_near` (passager proche du chauffeur, utile sous BeamMP).
- Couleur du véhicule sur les fantômes, déconnexions plus fines, réglage de la cadence selon la latence.
- Limiter les courses de taxi entre joueurs à un même serveur de jeu (actuellement par carte).
