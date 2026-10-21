// Build Vercel : fabrique public/config.js et public/downloads/grnfr-online.zip (le mod BeamNG).
// Sans aucune dépendance : le zip est écrit à la main avec zlib (entrées en « / », deflate, CRC32).
// Variables d'environnement (Vercel > Settings > Environment Variables) :
//   SUPABASE_URL        https://xxxx.supabase.co
//   SUPABASE_ANON_KEY   la clé « anon public » (JAMAIS la clé service_role)
import fs from "node:fs"
import path from "node:path"
import zlib from "node:zlib"
import { fileURLToPath } from "node:url"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
// Le dossier du mod est mod/grnfr-mod/ : son CONTENU (lua/, ui/, mod_info/, scripts/, settings/) doit être
// à la racine du zip, sans dossier "grnfr-mod" autour (sinon BeamNG ne charge pas le mod).
const MOD = path.join(ROOT, "mod", "grnfr-mod")
const OUT = path.join(ROOT, "public")
const URL_ = (process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "")
const KEY = (process.env.SUPABASE_ANON_KEY || "").trim()

function fail(msg) { console.error("\n[build] ERREUR : " + msg + "\n"); process.exit(1) }
if (!fs.existsSync(MOD)) fail("Dossier introuvable : " + MOD)
// Le mod doit TOUJOURS être relié à un serveur Supabase : un zip construit sans URL/clé ne doit jamais être
// distribué. Pour un essai local volontairement non relié : GRNFR_ALLOW_UNLINKED=1 node scripts/build.mjs
const missing = !URL_ || !KEY
if (missing) {
  if (process.env.GRNFR_ALLOW_UNLINKED === "1") {
    console.warn("[build] ATTENTION : SUPABASE_URL / SUPABASE_ANON_KEY absentes : le mod construit ne sera relié à aucun serveur (GRNFR_ALLOW_UNLINKED=1, build de test local uniquement).")
  } else {
    fail("SUPABASE_URL et SUPABASE_ANON_KEY doivent être définies (Vercel > Settings > Environment Variables, ou dans l'environnement avant de lancer le build). Le mod livré doit toujours être relié au serveur. Pour un build de test local volontairement non relié : GRNFR_ALLOW_UNLINKED=1 node scripts/build.mjs")
  }
}
if (!missing) {
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.(co|in)$/i.test(URL_)) console.warn("[build] L'URL Supabase ne ressemble pas à https://xxxx.supabase.co : vérifiez-la.")
  // garde-fou : refuser une clé service_role (elle donnerait tous les droits à n'importe quel joueur)
  try {
    const payload = JSON.parse(Buffer.from(KEY.split(".")[1], "base64url").toString("utf8"))
    if (payload.role === "service_role") fail("SUPABASE_ANON_KEY contient la clé service_role. Utilisez la clé « anon public ».")
  } catch (e) { /* clé au nouveau format (sb_publishable_...) : pas de contrôle possible */ }
  if (/^sb_secret_/.test(KEY)) fail("SUPABASE_ANON_KEY contient une clé secrète. Utilisez la clé « anon » / « publishable ».")
}

// ------------------------------------------------------------------ config du site
fs.mkdirSync(path.join(OUT, "downloads"), { recursive: true })
fs.writeFileSync(path.join(OUT, "config.js"), "window.GRNFR_CONFIG = " + JSON.stringify({ url: URL_, anonKey: KEY }) + ";\n")

// ------------------------------------------------------------------ zip
const CRC = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0 } return t })()
function crc32(buf) { let c = 0xffffffff; for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0 }

function walk(dir, base = "") {
  const out = []
  for (const e of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const rel = base ? base + "/" + e.name : e.name
    if (e.isDirectory()) out.push(...walk(path.join(dir, e.name), rel))
    else if (rel !== "README.md" && !e.name.startsWith(".")) out.push(rel)
  }
  return out
}

const files = walk(MOD)
const parts = [], central = []
let offset = 0
const dosTime = 0x6000, dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1 // date fixe : zip reproductible
for (const rel of files) {
  let data = fs.readFileSync(path.join(MOD, rel))
  if (rel === "ui/ui-vue/mods/GRNFR/serverConfig.js") {
    let s = data.toString("utf8")
    if (!s.includes("__SUPABASE_URL__") || !s.includes("__SUPABASE_ANON_KEY__")) fail("serverConfig.js ne contient plus les deux placeholders.")
    s = s.replace("__SUPABASE_URL__", URL_ || "__SUPABASE_URL__").replace("__SUPABASE_ANON_KEY__", KEY || "__SUPABASE_ANON_KEY__")
    data = Buffer.from(s, "utf8")
  }
  const name = Buffer.from(rel, "utf8")
  const comp = zlib.deflateRawSync(data, { level: 9 })
  const useDeflate = comp.length < data.length
  const body = useDeflate ? comp : data
  const crc = crc32(data)
  const local = Buffer.alloc(30)
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(0x0800, 6) // 0x0800 = noms UTF-8
  local.writeUInt16LE(useDeflate ? 8 : 0, 8); local.writeUInt16LE(dosTime, 10); local.writeUInt16LE(dosDate, 12)
  local.writeUInt32LE(crc, 14); local.writeUInt32LE(body.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(name.length, 26)
  parts.push(local, name, body)
  const cen = Buffer.alloc(46)
  cen.writeUInt32LE(0x02014b50, 0); cen.writeUInt16LE(20, 4); cen.writeUInt16LE(20, 6); cen.writeUInt16LE(0x0800, 8)
  cen.writeUInt16LE(useDeflate ? 8 : 0, 10); cen.writeUInt16LE(dosTime, 12); cen.writeUInt16LE(dosDate, 14)
  cen.writeUInt32LE(crc, 16); cen.writeUInt32LE(body.length, 20); cen.writeUInt32LE(data.length, 24); cen.writeUInt16LE(name.length, 28)
  cen.writeUInt32LE(offset, 42)
  central.push(cen, name)
  offset += local.length + name.length + body.length
}
const cdSize = central.reduce((n, b) => n + b.length, 0)
const end = Buffer.alloc(22)
end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(files.length, 8); end.writeUInt16LE(files.length, 10); end.writeUInt32LE(cdSize, 12); end.writeUInt32LE(offset, 16)
const zip = Buffer.concat([...parts, ...central, end])
const zipPath = path.join(OUT, "downloads", "grnfr-online.zip")
fs.writeFileSync(zipPath, zip)
console.log(`[build] ${files.length} fichiers -> ${path.relative(ROOT, zipPath)} (${(zip.length / 1024).toFixed(0)} Ko)` + (missing ? " [SANS serveur]" : " [relié à " + URL_ + "]"))
