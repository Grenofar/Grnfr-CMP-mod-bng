# GRNFR Mod

Shows your FPS and current game mode in an in-game HUD, with a settings window (main menu / pause menu), an in-game window and an optional always-visible FPS counter.
It also adds two experimental options: **Adaptive traffic** and **Chase** (two modes).

## How to use
| I want to... | Do this |
|---|---|
| Open or close the small HUD (in a map) | Press **K** (change it in Options > Controls > "GRNFR Mod") |
| Open the in-game window (Gameplay, Adaptive traffic, Anti-stutter) | Small HUD > **Option** button (press K to close it) |
| Change settings (HUD, FPS counter, language) | Main menu > **GRNFR Mod**, or Pause menu > **Mods** tab > GRNFR Mod |
| Start a chase (free roam only) | In-game window > **Gameplay** tab: **"the police chase you"** or **"you are the police"**, then a **3-2-1-GO** countdown starts by itself |

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
The FPS HUD, chase and traffic features send nothing over the network. **GRNFR Online** (below) does, only once you sign in.

## GRNFR Online (press **O**)
Needs an internet connection and a free account on the GRNFR server. Free roam only (disabled in the game's career, scenarios and missions).

| Tab | What it does |
|---|---|
| Account | Sign up (**a unique username is mandatory**), money, send money, history |
| Servers | Join one of the game servers (**4 players maximum**). You see the other players of your server, on the same map, with their username above their vehicle |
| Garage | 4 slots per player: take a vehicle out, put it back, sell it to the dealer or list it for sale |
| Dealership / Listings / Trades | Buy new, buy from other players, propose swaps (with optional cash) |
| Leaderboard | Wealth = money + value of vehicles |
| Taxi / Bus | Drive passengers (AI or other players), run a bus line, or call an AI taxi |

**What is sent to the server** (only while signed in): e-mail, username, money, garage, the map you are on and your position; on a game server also the model and position/speed of your vehicle, so others can see it. Session logs are never sent. Money is decided and checked by the server, never by your PC.

**Honest limits**: other players appear as simplified "ghost" vehicles that follow the positions received a few times per second (no shared physics, no collisions between players). For real multiplayer driving, BeamMP can be used alongside.

## Notes
- Adaptive traffic, Anti-stutter and Police chase are experimental and rely on game features that may differ between game versions.
- Chase: you start it from the in-game window, which closes by itself while the small HUD appears. The game pauses, a 3-2-1-GO countdown runs, both cars stay still until GO, then both start moving.
  - "The police chase you": an AI police car matching your car's performance appears next to you and chases you.
  - "You are the police": an AI suspect with the same power as your car appears in front of you and runs away. Catch it!

---

## Roadmap

Done in 1.1: shared economy, taxi, taxi calls, dealership and private sales, AI taxis, game servers with visible players. Still to do: a full separate career, shared bots, passenger-proximity checks under BeamMP.

## Contributing / feedback
If something does not work, attach the latest session log (see above) to your report. Suggestions for the roadmap are welcome.
