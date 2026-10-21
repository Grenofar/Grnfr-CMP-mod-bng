# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

GRNFR Online: a BeamNG.drive mod for a shared career-style multiplayer economy, backed by Supabase, distributed through a Vercel site. A separate, unrelated self-hosted server program (Rust + React) lives in `host/`. Comments in the code are in French; session logs the mod writes for players are in English.

Four independent pieces:
- `mod/grnfr-mod/` — the BeamNG mod (Lua game logic + Vue UI). Its contents (not the folder itself) must sit at the root of the distributed zip.
- `supabase/migrations/` — the entire backend: Postgres schema, RLS, and all game/money logic as SQL functions. Run strictly in numeric order (`0001_grnfr_online.sql` through the latest).
- `public/` + `scripts/build.mjs` — the Vercel site (vanilla JS, no framework) and the mod zip builder.
- `host/` — a standalone Rust WebSocket relay + React setup wizard for self-hosted servers (no player cap, optional password). Architecturally separate from the rest; `net.js` does not talk to it (yet).

## Commands

```bash
# Build the mod zip + site config (requires SUPABASE_URL / SUPABASE_ANON_KEY in env)
node scripts/build.mjs
# Local test build without a server (never ship this): GRNFR_ALLOW_UNLINKED=1 node scripts/build.mjs

# Publish a release to Supabase Storage (requires SUPABASE_SERVICE_ROLE_KEY, local only, never commit it)
npm run release -- "release notes"

# Client network tests (fakes Supabase + the Lua bridge)
node tests/net_test.mjs

# SQL tests, against a real local Postgres (not available in every environment — check before assuming psql exists)
PGHOST=/tmp PGPORT=54329 PGUSER=postgres supabase/tests/run.sh

# Lua: syntax check, then a simulated run against a fake BeamNG API (needs texlua — not always available)
texlua scripts/check-lua.lua $(find mod/grnfr-mod/lua mod/grnfr-mod/scripts -name '*.lua')
texlua tests/lua_sim.lua

# host/ — React wizard builds with plain npm/vite; the Rust side needs cargo (not always available)
cd host/ui && npm install && npm run build   # must run before `cargo build`: httpd.rs embeds dist/ via include_str!
cd host && cargo build --release
```

No single-test runners exist for `tests.sql` or `lua_sim.lua` — they're linear scripts that `raise exception`/assert on the first failure, so narrow down by commenting out the sections after the one you're debugging.

## Architecture

**Lua does game logic, JS does HTTP.** BeamNG's Lua can't make HTTPS calls, so every extension module under `mod/grnfr-mod/lua/ge/extensions/grnfr/` sends requests to `ui/ui-vue/mods/GRNFR/net.js` and gets results back via engine events (`GRNFRNetReq` → `onNetResult`). `grnfr_online.call(fn, args, cb)` (`online.lua`) is a **generic RPC bridge**: any Supabase RPC can be invoked through it without adding new event plumbing — this is how `garage.lua`, `chat.lua`, and `drag.lua` talk to the backend. `grnfr.lua`'s `M.ui(name, json)` is the single whitelisted entry point for UI → Lua calls (`ROUTES` table).

**Everything server-scoped derives the caller's current server from `server_members`, not from a client-supplied ID.** RPCs like `send_chat_message`, `claim_garage_spot`, `propose_drag_race` all do `select server_id from server_members where user_id = v_me` internally — the client never passes a server UUID for these. Keep following this pattern for new server-scoped features.

**Money is server-only.** Every balance change goes through `private.add_money` (security-definer SQL), and the invariant `balance = sum(transactions)` is checked in `supabase/tests/tests.sql` after every feature group. Clients have zero write grants on tables — only RPC execute grants, applied via explicit `revoke all ... grant execute ... to authenticated` at the end of each migration.

**Position-based anti-cheat is intentionally "limited, not foolproof"** — see `too_fast`/`too_short`/`drag_max_speed_mps` checks: plausibility bounds on claimed travel time vs. distance, not real server-side simulation. New gameplay RPCs that take a time or distance from the client should follow the same pattern rather than trusting the client outright.

**Host election / handover needs no explicit state.** The shared-traffic "host" (`convoy.lua`, `0003_convoy.sql`) is just "the `server_members` row with the oldest `joined_at` still present" — recomputed on every `server_sync` call, so failover is automatic when the host leaves. Garage spots (`0006_garage_spots.sql`) and one-active-race-per-server (`0007_drag_races.sql`, partial unique index) use similar recompute-don't-store patterns.

**Session versioning**: `VERSION` in `grnfr.lua` and `version` in `mod_info/grnfr/info.json` must match, and must be bumped before `npm run release` (which refuses to re-publish an existing version).

**Hypothesis APIs**: BeamNG API calls whose exact behavior is unverified (ghost  ongoing physics, `ai.setMode('traffic')`, `input.event('parkingbrake'/'clutch', ...)` for the drag-race launch lock, `core_groundMarkers`, etc.) are always wrapped in `pcall` and documented as unverified in comments — this is deliberate, not an oversight; keep the pattern for new game-API calls instead of assuming they work.

**Testing-environment caveat**: `psql`, `texlua`, and `cargo`/`rustc` are not guaranteed to be present in the environment Claude Code runs in. Check for the tool before assuming a test suite can be executed, and say so explicitly if it can't — don't claim something passed without having actually run it.
