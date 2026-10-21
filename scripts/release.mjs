// Publie une release du mod sur Supabase (bucket Storage "releases" public + table mod_releases).
// Usage :
//   SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/release.mjs ["notes de version"]
// La clé service_role ne doit JAMAIS être commitée, ni mise dans le mod ou le site : elle vient uniquement
// de l'environnement local (variable d'environnement, ou .env non suivi par git) et ne sert qu'ici.
// Refuse si la version (lue dans mod_info/grnfr/info.json) existe déjà : changez VERSION dans grnfr.lua ET
// la version dans mod_info/grnfr/info.json avant de publier une nouvelle release.
import fs from "node:fs"
import path from "node:path"
import crypto from "node:crypto"
import { execFileSync } from "node:child_process"
import { fileURLToPath } from "node:url"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const URL_ = (process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "")
const ANON = (process.env.SUPABASE_ANON_KEY || "").trim()
const SERVICE = (process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim()
const NOTES = process.argv[2] || null

function fail(msg) { console.error("\n[release] ERREUR : " + msg + "\n"); process.exit(1) }

if (!URL_ || !ANON) fail("SUPABASE_URL et SUPABASE_ANON_KEY sont requis (comme pour scripts/build.mjs).")
if (!SERVICE) fail("SUPABASE_SERVICE_ROLE_KEY est requis (clé service_role : Project Settings > API, LOCALE uniquement, jamais commitée).")
try {
  const payload = JSON.parse(Buffer.from(SERVICE.split(".")[1], "base64url").toString("utf8"))
  if (payload.role !== "service_role") fail("SUPABASE_SERVICE_ROLE_KEY ne contient pas un rôle service_role.")
} catch (e) {
  fail("SUPABASE_SERVICE_ROLE_KEY ne ressemble pas à un jeton Supabase valide (nouveau format sb_secret_... non géré par ce script).")
}

const infoPath = path.join(ROOT, "mod", "grnfr-mod", "mod_info", "grnfr", "info.json")
const info = JSON.parse(fs.readFileSync(infoPath, "utf8"))
const version = String(info.version || "")
if (!/^\d+\.\d+\.\d+$/.test(version)) fail("Version invalide dans " + path.relative(ROOT, infoPath) + " : " + JSON.stringify(info.version))

async function rest(pathname, { method = "GET", body, headers = {} } = {}) {
  const res = await fetch(URL_ + pathname, {
    method,
    headers: { apikey: SERVICE, Authorization: "Bearer " + SERVICE, ...headers },
    body,
  })
  let data = null
  try { data = await res.json() } catch (e) { /* corps vide ou binaire : ignoré */ }
  if (!res.ok) {
    const msg = (data && (data.message || data.error || data.msg)) || ("http_" + res.status)
    throw new Error(String(msg))
  }
  return data
}

async function main() {
  console.log("[release] vérification : la version " + version + " n'existe pas déjà...")
  const existing = await rest("/rest/v1/mod_releases?version=eq." + encodeURIComponent(version) + "&select=version")
  if (Array.isArray(existing) && existing.length > 0) {
    fail("La version " + version + " a déjà été publiée. Changez VERSION dans lua/ge/extensions/grnfr.lua ET la version dans " + path.relative(ROOT, infoPath) + ".")
  }

  console.log("[release] build du mod v" + version + "...")
  execFileSync(process.execPath, [path.join(ROOT, "scripts", "build.mjs")], { stdio: "inherit", env: process.env })

  const zipPath = path.join(ROOT, "public", "downloads", "grnfr-online.zip")
  const zip = fs.readFileSync(zipPath)
  const sha256 = crypto.createHash("sha256").update(zip).digest("hex")
  const fileName = `grnfr-online-v${version}.zip`

  console.log("[release] envoi de " + fileName + " (" + (zip.length / 1024).toFixed(0) + " Ko) vers le bucket Storage...")
  await rest("/storage/v1/object/releases/" + encodeURIComponent(fileName), {
    method: "POST", body: zip, headers: { "Content-Type": "application/zip", "x-upsert": "false" },
  })

  console.log("[release] enregistrement dans mod_releases...")
  await rest("/rest/v1/mod_releases", {
    method: "POST",
    headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ version, notes: NOTES, file_path: fileName, size: zip.length, sha256 }),
  })

  console.log("[release] v" + version + " publiée : " + fileName + " (sha256 " + sha256.slice(0, 12) + "...)")
}

main().catch(e => fail(e.message || String(e)))
