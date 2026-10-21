# GRNFR CMP

Shows your FPS and current game mode in an in-game HUD, plus an optional always-visible FPS counter.
It also adds one experimental option: **Adaptive traffic**. The rest of the mod is **GRNFR CMP** (Career MultiPlayer): a shared career-style multiplayer economy (see below).

**One button, one window.** The main menu has a single **GRNFR CMP** button. It opens the same window as the in-game **O** key: account, servers, garage, dealership, listings, trades, leaderboard, taxi, bus, and a **Réglages/Settings** tab (HUD, FPS counter, language — this used to be a separate window, not anymore).

## How to use
| I want to... | Do this |
|---|---|
| Open or close the small HUD (in a map) | Press **K** (change it in Options > Controls > "GRNFR CMP") |
| Open the in-game window (Adaptive traffic, Anti-stutter) | Small HUD > **Option** button (press K to close it) |
| Change settings (HUD, FPS counter, language) | **GRNFR CMP** window > **Réglages/Settings** tab (main menu button, or **O** in-game), or Pause menu > **Mods** tab > GRNFR CMP |
| Join a game server, even from the main menu | Main menu > **GRNFR CMP** button > **Servers** tab: one card per server (name, players connected) |
| Open the quick window (chat, players, drag races) | Press **J** (change it in Options > Controls > "GRNFR CMP") — a small panel, does not hide the game like the full window does |

English and French are available (choose on first launch, change any time in Settings).

## Your settings
All settings are saved to disk automatically in `settings/grnfr.json` (inside your BeamNG user folder).
They are kept between maps and game restarts. Delete that file to go back to the defaults.

## Session logs (if something does not work)
Every time you play a map, the mod writes a short, plain-English diary of what happened to:

`<BeamNG user folder>/settings/grnfr/logs/`

One text file per session, named by date and time. The 10 newest are kept. Lines starting with `WARNING` or `PROBLEM`
are the ones that matter. If you report a bug, please attach the latest file.

The logs contain **no personal data**: no user name, no folder paths and no PC hardware information. The logs never leave your PC.
The FPS HUD and adaptive traffic feature send nothing over the network. **GRNFR CMP** (below) does, only once you sign in.

## GRNFR CMP (press **O**, or the main menu button)
Needs an internet connection. Free roam only (disabled in the game's career, scenarios and missions) — the window itself can also be opened from the main menu, before loading any map.

**Creating a profile is just a username.** No e-mail, no password to remember: pick a username and you're in. What actually proves it's you afterward is a small file kept on this PC — "Export my profile" in the Account tab writes it to your BeamNG settings folder; copy that file to another PC (USB drive, etc.) and "Import a profile" there to continue with the same progress. If the same profile is ever used from two places at once, the older connection is kicked — that's the signal of a shared/resold profile. An old-style e-mail account still works (there's a link for it), but it's no longer the default.

| Tab | What it does |
|---|---|
| Account | Create a profile (username only) or import one, money, send money, history, export/import your profile |
| Servers | Join one of the game servers (**4 players maximum**). You see the other players of your server, on the same map, with their username above their vehicle, plus 2 shared traffic cars (see below) |
| Garage | Your personal garage tablet: one garage per server slot (4 max, same as player count), only opens near **your own** (marked "GARAGE" on the ground within 150 m, usable within about 10 m). Take a vehicle out, put it back, sell it to the dealer or list it for sale |
| Dealership / Listings / Trades | Buy new, buy from other players, propose swaps (with optional cash) |
| Leaderboard | Wealth = money + value of vehicles |
| Taxi / Bus | Drive passengers (AI or other players), run a bus line, or call an AI taxi |
| Réglages/Settings | HUD, FPS counter, language — the same settings panel as the main menu, as a tab here |

**What is sent to the server** (only while signed in): username, money, garage, the map you are on and your position; on a game server also the model and position/speed of your vehicle, so others can see it. Session logs are never sent. Money is decided and checked by the server, never by your PC.

**Honest limits**: other players (and the 2 shared traffic cars) appear as simplified "ghost" vehicles that follow the positions received a few times per second (no shared physics, no collisions between players or with the shared traffic). For real multiplayer driving, BeamMP can be used alongside.

## Shared traffic (2 cars per server)
Whoever has been connected to the server the longest ("host", recomputed automatically on every sync — no election step) drives 2 AI traffic cars and sends their position like their own. Everyone else on the server sees them as ghosts, without collision. If the host leaves, the next-longest-connected player takes over and spawns their own 2 cars at the next sync.

## Quick window (press **J**)
A small panel — unlike the full GRNFR CMP window, it does not take over the screen or hide the game.
- **Chat**: text messages with everyone on your current server.
- **Players**: for each one, Track (a point on the ground follows them, refreshed every couple of seconds),
  Give money, and Trade (pick one of your vehicles and/or one of theirs, propose the swap).
- **Drag races**: mark a start and a finish (your current position, twice), propose the race (only one at a
  time per server). Others stake an amount (preset buttons from 100 to 50,000, or a custom amount — taken
  from their balance immediately, refunded if they back out or the race is cancelled). The host starts once
  2+ people are in. No false start: every car is locked (parking brake + clutch) during the 3-2-1 countdown
  and released on GO. Cross the finish line to record your time; the fastest wins the whole pot. Times that
  would require an impossible average speed are rejected (same idea as the taxi fare check) — a limit, not a
  guarantee.

## Notes
- Adaptive traffic and Anti-stutter are experimental and rely on game features that may differ between game versions.
- The garage spot, the shared traffic driving mode (`ai.setMode('traffic')`), the garage tablet's ground marker and the
  drag race car lock (`input.event('parkingbrake'/'clutch', ...)`) are new and have not been checked in a real game
  session yet — see the root `README.md` for the full "tested / not tested" table.
- Profile export/import writes/reads plain files under `settings/grnfr/profiles/` (`FS:findFiles`/`jsonReadFile`/
  `jsonWriteFile`, the same calls already used for session logs) — also unverified in a real game session.

---

## Roadmap

Done in 2.0: a single main-menu button (servers, garage, settings — all in one window), a personal garage tablet gated by proximity (one per server slot), shared traffic (2 AI cars, host handover), server chat, player tracking, quick money/trade shortcuts, drag races with betting, username-only profiles with portable export/import and anti-sharing, a fixed mod zip (correct root, always linked to a server) and a release pipeline (Supabase Storage + in-game update notice). The "Chase" mode has been removed. A separate, optional self-hosted server program (Rust + a small React setup page, no player limit) is being built alongside the mod but is not connected to it yet — see the root `README.md` ("Host auto-hébergé"). Still to do: a full separate career, passenger-proximity checks under BeamMP, the same one-button experience in the pause menu.

## Contributing / feedback
If something does not work, attach the latest session log (see above) to your report. Suggestions for the roadmap are welcome.
