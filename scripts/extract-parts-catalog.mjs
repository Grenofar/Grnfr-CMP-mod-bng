// Extrait un catalogue RÉEL de pièces (vraies pièces jbeam du jeu, vrais prix) à partir d'une installation
// BeamNG.drive locale — PAS exécuté au build normal (nécessite le jeu installé), à relancer à la main quand le
// catalogue doit être régénéré (nouveau véhicule, mise à jour du jeu qui change des pièces...).
//
// Usage : BEAMNG_PATH="F:\\SteamLibrary\\steamapps\\common\\BeamNG.drive" node scripts/extract-parts-catalog.mjs
//
// Pour chaque véhicule de dealership_catalog (model_key de base), lit content/vehicles/<model>.zip, parse TOUS
// ses .jbeam (format JSON5-like : commentaires //, virgules traînantes — nettoyés avant JSON.parse, imparfait
// mais suffisant pour les fichiers officiels du jeu), repère la pièce "main" (slotType "main"), puis parcourt
// son arbre de slots (slots/slots2) pour lister, par emplacement réel, toutes les pièces compatibles (allowTypes)
// trouvées dans le zip, avec leur vrai nom et leur vrai prix (information.value). Écrit :
//   - ui/ui-vue/mods/GRNFR/partsCatalog.json (livré avec le mod, pour l'affichage)
//   - maintenance/parts_catalog_seed.sql (à coller/appliquer côté serveur : table vehicle_parts_catalog)
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import AdmZip from "adm-zip"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const BEAMNG = process.env.BEAMNG_PATH
if (!BEAMNG) { console.error("Donnez BEAMNG_PATH (dossier d'installation de BeamNG.drive)."); process.exit(1) }

// Véhicules de base du concessionnaire (0001_grnfr_online.sql) : ce sont ceux dont les joueurs peuvent acheter
// une config, donc les seuls dont la personnalisation a un sens pour l'instant.
const MODELS = [
  "covet", "pessima", "sunburst2", "vivace", "miramar", "pickup",
  "etk800", "bastion", "barstow", "moonhawk", "bolide", "scintilla", "fullsize", "citybus",
]

// Emplacements qu'on garde (les autres - décalcomanies, plaques, intérieur... - n'intéressent pas le joueur ici).
// Les slotType du jeu sont presque toujours préfixés par le modèle (ex. "barstow_engine_V8", pas "engine") :
// on reconnaît donc un emplacement "intéressant" par MOT-CLÉ contenu dans son nom, pas par égalité exacte.
// Jantes/pneus exclus volontairement : leur "nom" dans les fichiers du jeu est presque toujours une clé de
// traduction générique ("ui.vehicleconfig.generic.wheelNameNoColor", sans texte récupérable ici) ET ils
// représentent à eux seuls la grosse majorité des lignes (une bonne centaine par véhicule) — à revoir avec un
// vrai système de traduction, pas dans cette passe.
const KEEP_KEYWORDS = [
  "engine", "exhaust", "turbo", "supercharg", "intake", "transmission", "differential",
  "brake", "suspension", "shock", "spring",
  "bumper", "hood", "spoiler", "grille", "mirror", "rollcage", "n2o", "nitrous",
  "mod", "trunk_load", "cargobox", "cargo",
]
// Certains noms sont littéralement une clé de traduction ("ui.vehicleconfig.<...>.<texte>") : quand le dernier
// segment contient le vrai texte lisible (espace ou mot capitalisé, faute de traduction fournie pour ce cas),
// on le récupère ; sinon (ex. "wheelNameNoColor") il n'y a rien à en tirer, on renvoie null.
function cleanLocKey(s) {
  const m = /^ui\.[\w.]+\.([^.]+)$/.exec(s)
  if (!m) return s
  const last = m[1]
  return /\s/.test(last) ? last : null // un espace = vrai texte intégré à la clé ; sinon identifiant de code
}
function isInteresting(slotType) {
  const t = String(slotType || "").toLowerCase()
  return KEEP_KEYWORDS.some(k => t.includes(k))
}

// jbeam n'est pas du JSON strict : commentaires // et /* */, virgules traînantes, ET virgules MANQUANTES entre
// deux membres d'un objet (rencontré dans de vrais fichiers du jeu, ex. barstow.jbeam : "}" suivi directement
// de "\"glowMap\":{" sans virgule). Le parseur JSON.parse standard rejette tout ça. Petit parseur maison où la
// virgule est un simple séparateur OPTIONNEL (ignoré s'il est là, pas exigé s'il n'y est pas) : gère les deux
// cas d'un coup, sans avoir à deviner où rajouter une virgule par regex.
function parseJbeam(src) {
  let i = 0
  const n = src.length
  function skipWs() {
    for (;;) {
      while (i < n && /\s/.test(src[i])) i++
      if (src[i] === "/" && src[i + 1] === "/") { while (i < n && src[i] !== "\n") i++; continue }
      if (src[i] === "/" && src[i + 1] === "*") { i += 2; while (i < n && !(src[i] === "*" && src[i + 1] === "/")) i++; i += 2; continue }
      break
    }
  }
  function parseString() {
    i++ // "
    let s = ""
    while (i < n && src[i] !== '"') {
      if (src[i] === "\\") { s += JSON.parse('"' + src[i] + src[i + 1] + '"'); i += 2; continue }
      s += src[i]; i++
    }
    i++ // "
    return s
  }
  function parseLiteralOrNumber() {
    let s = ""
    while (i < n && !/[\s,\]}:]/.test(src[i])) s += src[i++]
    if (s === "true") return true
    if (s === "false") return false
    if (s === "null") return null
    const num = Number(s)
    if (s !== "" && !Number.isNaN(num)) return num
    return s // repli : texte non quoté (rare), rendu tel quel
  }
  function parseValue() {
    skipWs()
    if (src[i] === "{") return parseObject()
    if (src[i] === "[") return parseArray()
    if (src[i] === '"') return parseString()
    return parseLiteralOrNumber()
  }
  function parseObject() {
    i++ // {
    const obj = {}
    for (;;) {
      skipWs()
      if (src[i] === "}") { i++; return obj }
      if (src[i] === ",") { i++; continue } // virgule traînante / superflue
      const key = src[i] === '"' ? parseString() : parseLiteralOrNumber()
      skipWs()
      if (src[i] === ":") i++
      const val = parseValue()
      obj[key] = val
      skipWs()
      if (src[i] === ",") i++ // optionnelle : on continue la boucle qu'elle soit là ou pas
    }
  }
  function parseArray() {
    i++ // [
    const arr = []
    for (;;) {
      skipWs()
      if (src[i] === "]") { i++; return arr }
      if (src[i] === ",") { i++; continue }
      arr.push(parseValue())
      skipWs()
      if (src[i] === ",") i++
    }
  }
  skipWs()
  return parseValue()
}

function partName(info) {
  if (!info) return null
  const n = info.name
  if (typeof n === "string") return n.startsWith("ui.") ? cleanLocKey(n) : n
  if (n && typeof n === "object") {
    // { txt: "ui.vehicleconfig...BRAND BRAND", ctx: { brand1: "...Gavril", brand2: "...Barstow" } } : on
    // reconstruit juste à partir des valeurs de ctx (pas de vraie table de traduction ici).
    const ctx = n.ctx || {}
    let txt = String(n.txt || "")
    txt = txt.replace(/BRAND(\d*)/g, (_, i) => {
      const key = "brand" + (i || "1")
      const v = ctx[key]
      if (!v) return ""
      return String(v).split(".").pop()
    }).trim()
    return txt || null
  }
  return null
}

function loadVehicleParts(zipPath, model) {
  const zip = new AdmZip(zipPath)
  const parts = {} // partKey -> { slotType, information, slots }
  for (const entry of zip.getEntries()) {
    if (entry.isDirectory || !entry.entryName.endsWith(".jbeam")) continue
    if (!entry.entryName.startsWith(`vehicles/${model}/`)) continue
    let data
    try { data = parseJbeam(entry.getData().toString("utf8")) } catch (e) { continue } // fichier non standard : ignoré
    if (typeof data !== "object" || !data) continue
    for (const [key, def] of Object.entries(data)) {
      if (!def || typeof def !== "object" || Array.isArray(def)) continue
      const slotType = def.slotType
      if (!slotType) continue
      const slots = def.slots2 || def.slots || []
      parts[key] = { slotType, information: def.information, slots, file: entry.entryName }
    }
  }
  return parts
}

// slots2 : [["name","allowTypes","denyTypes","default","description",{flags}], [row...], ...] (1re ligne = en-têtes)
function slotRows(slots) {
  if (!Array.isArray(slots) || slots.length < 2) return []
  const header = slots[0]
  const iName = header.indexOf("name"), iAllow = header.indexOf("allowTypes"), iDefault = header.indexOf("default")
  if (iName < 0) return []
  return slots.slice(1).filter(r => Array.isArray(r) && typeof r[iName] === "string").map(r => ({
    name: r[iName], allowTypes: Array.isArray(r[iAllow]) ? r[iAllow] : [],
    optional: iDefault >= 0 && (r[iDefault] === "" || r[iDefault] == null),
  }))
}

function buildCatalog(model, parts) {
  const main = Object.values(parts).find(p => p.slotType === "main")
  if (!main) return null
  const bySlotType = {}
  for (const [key, p] of Object.entries(parts)) {
    (bySlotType[p.slotType] = bySlotType[p.slotType] || []).push({ key, ...p })
  }
  const out = []
  const seen = new Set()
  const queue = slotRows(main.slots)
  while (queue.length) {
    const s = queue.shift()
    if (seen.has(s.name)) continue
    seen.add(s.name)
    const allowed = s.allowTypes.filter(isInteresting)
    if (allowed.length === 0) {
      // pas un emplacement qu'on garde pour l'UI, mais on explore quand même ses pièces par défaut au cas où
      // elles exposent elles-mêmes d'autres emplacements intéressants (ex: la carrosserie expose le moteur).
      for (const t of s.allowTypes) {
        for (const p of bySlotType[t] || []) for (const child of slotRows(p.slots)) queue.push(child)
      }
      continue
    }
    const isCargo = /trunk_load|cargo/i.test(s.name)
    const options = []
    for (const t of allowed) {
      for (const p of bySlotType[t] || []) {
        const name = partName(p.information) || p.key
        const price = Number(p.information && p.information.value)
        // "4x Cargo Load Box M" / "2x Cargo Load Box L + 2x Cargo Box M" -> capacité = somme des "Nx".
        const cargoUnits = isCargo ? [...String(name).matchAll(/(\d+)\s*x/gi)].reduce((a, m) => a + Number(m[1]), 0) || 1 : null
        options.push({ part: p.key, name, price: Number.isFinite(price) ? Math.round(price) : null, cargoUnits })
        for (const child of slotRows(p.slots)) queue.push(child)
      }
    }
    // >1 option : plusieurs pièces possibles pour cet emplacement. Emplacement "optionnel" (rien par défaut,
    // comme la caisse à colis ou l'attelage) : même avec une seule pièce trouvée, le choix "rien / cette pièce"
    // reste réel (géré par remove_vehicle_part côté serveur, voir 0015).
    if (options.length > 1 || (options.length === 1 && s.optional)) out.push({ slot: s.name, options, optional: s.optional })
  }
  return out.length ? out : null
}

const catalog = {}
const sqlRows = []
for (const model of MODELS) {
  const zipPath = path.join(BEAMNG, "content", "vehicles", `${model}.zip`)
  if (!fs.existsSync(zipPath)) { console.warn(`! ${model} : zip introuvable (${zipPath})`); continue }
  let parts
  try { parts = loadVehicleParts(zipPath, model) } catch (e) { console.warn(`! ${model} : ${e.message}`); continue }
  const slots = buildCatalog(model, parts)
  if (!slots) { console.warn(`! ${model} : aucune pièce "main" / aucun emplacement retenu`); continue }
  catalog[model] = { slots }
  let n = 0
  for (const s of slots) for (const o of s.options) {
    n++
    sqlRows.push(`  ('${model}', '${s.slot.replace(/'/g, "''")}', '${o.part.replace(/'/g, "''")}', '${(o.name || o.part).replace(/'/g, "''")}', ${o.price ?? "null"}, ${o.cargoUnits ?? "null"})`)
  }
  console.log(`${model} : ${slots.length} emplacement(s), ${n} pièce(s)`)
}

fs.writeFileSync(path.join(ROOT, "mod/grnfr-mod/ui/ui-vue/mods/GRNFR/partsCatalog.json"), JSON.stringify(catalog, null, 2))
const sql = `-- Généré par scripts/extract-parts-catalog.mjs à partir des vrais fichiers .jbeam du jeu (BEAMNG_PATH).
-- À COLLER DANS supabase/migrations/<numéro>_vehicle_parts_catalog.sql APRÈS la création de la table (voir le
-- schéma dans ce même fichier de migration), ou réappliquer seul si le catalogue change plus tard.
insert into public.vehicle_parts_catalog (model_key, slot, part_key, name, price, cargo_units) values
${sqlRows.join(",\n")}
on conflict (model_key, slot, part_key) do update set name = excluded.name, price = excluded.price, cargo_units = excluded.cargo_units;
`
fs.writeFileSync(path.join(ROOT, "supabase/maintenance/parts_catalog_seed.sql"), sql)
console.log(`\nÉcrit : mod/grnfr-mod/ui/ui-vue/mods/GRNFR/partsCatalog.json, supabase/maintenance/parts_catalog_seed.sql (${sqlRows.length} lignes)`)
