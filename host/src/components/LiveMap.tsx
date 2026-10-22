import { useEffect, useMemo, useRef, useState } from "react"
import { api, LevelRoads, LiveServer, LivePlayer } from "../api"

// Carte en direct : serveurs de jeu du MOD (Serveur 1, 2, 3...) lus sur Supabase, avec la liste des joueurs et une
// carte 2D vue de dessus. La carte est dessinée ici à partir du réseau routier que le mod envoie une fois par carte
// (aucune image du jeu) ; les joueurs sont des points avec leur pseudo. Molette = zoom, glisser = déplacer.
const POLL_MS = 2000
const COLORS = ["#ff6600", "#3b82f6", "#22c55e", "#eab308", "#a855f7", "#ef4444", "#14b8a6", "#ec4899"]
const LEVEL_NAMES: Record<string, string> = {
  west_coast_usa: "West Coast, USA", italy: "Italy", utah: "Utah", east_coast_usa: "East Coast, USA",
  jungle_rock_island: "Jungle Rock Island", johnson_valley: "Johnson Valley", industrial: "Industrial Site",
  small_island: "Small Island", gridmap_v2: "Grid Map", automation_test_track: "Automation Test Track",
}
const levelName = (l?: string | null) => (l ? LEVEL_NAMES[l] || l : "—")

function since(iso?: string) {
  if (!iso) return "—"
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return `${Math.floor(s)} s`
  if (s < 3600) return `${Math.floor(s / 60)} min`
  return `${Math.floor(s / 3600)} h ${Math.floor((s % 3600) / 60)} min`
}

export default function LiveMap() {
  const [servers, setServers] = useState<LiveServer[] | null>(null)
  const [error, setError] = useState("")
  const [selId, setSelId] = useState<string | null>(null)
  const [level, setLevel] = useState<string | null>(null)
  const [focus, setFocus] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    const load = () => api.liveServers()
      .then(list => { if (alive) { setServers(list); setError("") } })
      .catch(e => { if (alive) setError(String(e)) })
    load()
    const t = setInterval(load, POLL_MS)
    return () => { alive = false; clearInterval(t) }
  }, [])

  const server = servers?.find(s => s.id === selId) || null
  // carte affichée : choisie, sinon celle où il y a le plus de joueurs, sinon West Coast
  const levels = useMemo(() => {
    const n: Record<string, number> = {}
    for (const p of server?.players || []) if (p.level && p.level !== "unknown") n[p.level] = (n[p.level] || 0) + 1
    return Object.entries(n).sort((a, b) => b[1] - a[1]).map(([l]) => l)
  }, [server])
  const shownLevel = level || levels[0] || "west_coast_usa"

  if (servers === null) return <div><h2>Carte en direct</h2>{error ? <p className="err">{error}</p> : <p className="mut">Chargement…</p>}</div>

  if (!server) {
    return (
      <div>
        <h2>Carte en direct</h2>
        <p className="mut">Les serveurs du mod GRNFR CMP et les joueurs connectés, mis à jour toutes les 2 secondes.</p>
        {error && <p className="err">{error}</p>}
        {servers.map(s => (
          <div key={s.id} className="card server-card" onClick={() => { setSelId(s.id); setLevel(null); setFocus(null) }}>
            <div className="row between">
              <div className="row"><span className={s.players.length ? "dot on" : "dot off"} /><b>{s.name}</b></div>
              <span className="big" style={{ fontSize: 20 }}>{s.players.length}/{s.max_players}</span>
            </div>
            <div className="mut small" style={{ marginTop: 6 }}>
              {s.players.length ? s.players.map(p => p.username).join(", ") : "Personne pour l'instant"}
            </div>
          </div>
        ))}
      </div>
    )
  }

  const onMap = server.players.filter(p => p.level === shownLevel)
  return (
    <div className="live">
      <div className="row between" style={{ marginBottom: 12 }}>
        <div className="row">
          <button className="btn dim sm" onClick={() => setSelId(null)}>‹ Serveurs</button>
          <h2 style={{ margin: 0 }}>{server.name}</h2>
          <span className="mut">{server.players.length}/{server.max_players} joueurs</span>
        </div>
        <div className="row">
          {(levels.length > 1 || (level && !levels.includes(level))) && (
            <select value={shownLevel} onChange={e => { setLevel(e.target.value); setFocus(null) }}>
              {Array.from(new Set([shownLevel, ...levels])).map(l => <option key={l} value={l}>{levelName(l)}</option>)}
            </select>
          )}
          <span className="mut small">Carte : <b>{levelName(shownLevel)}</b></span>
        </div>
      </div>
      {error && <p className="err">{error}</p>}
      <div className="live-body">
        <MapView level={shownLevel} players={server.players} focus={focus} />
        <aside className="live-side">
          <div className="live-stats">
            <div><span className="mut small">Joueurs</span><b>{server.players.length}/{server.max_players}</b></div>
            <div><span className="mut small">Sur cette carte</span><b>{onMap.length}</b></div>
            <div><span className="mut small">En service</span><b>{server.players.filter(p => p.duty).length}</b></div>
          </div>
          {!server.players.length && <p className="mut small">Personne sur ce serveur.</p>}
          {server.players.map((p, i) => (
            <div key={p.username} className={focus === p.username ? "live-player on" : "live-player"}
                 onClick={() => { if (p.level && p.level !== shownLevel) setLevel(p.level); setFocus(focus === p.username ? null : p.username) }}>
              <span className="live-av" style={{ background: COLORS[i % COLORS.length] }}>{p.username.slice(0, 1).toUpperCase()}</span>
              <div>
                <b>{p.username}</b>{i === 0 && <span className="live-tag">hôte</span>}{p.duty && <span className="live-tag">{p.duty}</span>}
                <div className="mut small">{levelName(p.level)} · {p.veh || "à pied"} · depuis {since(p.since)}</div>
              </div>
            </div>
          ))}
        </aside>
      </div>
    </div>
  )
}

// ------------------------------------------------------------------ dessin de la carte (canvas 2D)
function MapView({ level, players, focus }: { level: string; players: LivePlayer[]; focus: string | null }) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const wrap = useRef<HTMLDivElement>(null)
  const [roads, setRoads] = useState<LevelRoads | null | undefined>(undefined) // undefined = en cours, null = absente
  const view = useRef({ cx: 0, cy: 0, scale: 0.4, fitted: "" })
  const drag = useRef<{ x: number; y: number } | null>(null)
  const [, redraw] = useState(0)

  useEffect(() => {
    let alive = true
    setRoads(undefined)
    api.levelRoads(level).then(r => { if (alive) setRoads(r) }).catch(() => { if (alive) setRoads(null) })
    return () => { alive = false }
  }, [level])

  // cadrage initial : toute la carte (routes), sinon les joueurs
  useEffect(() => {
    const el = wrap.current
    if (!el || roads === undefined || view.current.fitted === level) return
    let b = roads?.bounds
    if (!b) {
      const pts = players.filter(p => p.level === level && p.x != null)
      if (!pts.length) b = { minx: -1000, miny: -1000, maxx: 1000, maxy: 1000 }
      else b = { minx: Math.min(...pts.map(p => p.x!)) - 300, maxx: Math.max(...pts.map(p => p.x!)) + 300,
                 miny: Math.min(...pts.map(p => p.y!)) - 300, maxy: Math.max(...pts.map(p => p.y!)) + 300 }
    }
    const w = el.clientWidth, h = el.clientHeight
    view.current = { cx: (b.minx + b.maxx) / 2, cy: (b.miny + b.maxy) / 2,
                     scale: Math.min(w / (b.maxx - b.minx || 1), h / (b.maxy - b.miny || 1)) * 0.92, fitted: level }
    redraw(n => n + 1)
  }, [roads, level, players])

  // suivre le joueur sélectionné
  const fp = players.find(p => p.username === focus && p.level === level)
  useEffect(() => { if (fp && fp.x != null) { view.current.cx = fp.x; view.current.cy = fp.y!; redraw(n => n + 1) } }, [fp?.x, fp?.y, focus])

  useEffect(() => {
    const c = canvas.current, el = wrap.current
    if (!c || !el) return
    const dpr = window.devicePixelRatio || 1
    const w = el.clientWidth, h = el.clientHeight
    c.width = w * dpr; c.height = h * dpr; c.style.width = w + "px"; c.style.height = h + "px"
    const g = c.getContext("2d")!
    g.setTransform(dpr, 0, 0, dpr, 0, 0)
    const { cx, cy, scale } = view.current
    const sx = (x: number) => w / 2 + (x - cx) * scale
    const sy = (y: number) => h / 2 - (y - cy) * scale // y du jeu vers le nord = haut de l'écran
    g.fillStyle = "#0e1013"; g.fillRect(0, 0, w, h)
    // grille de 500 m
    g.strokeStyle = "rgba(255,255,255,0.04)"; g.lineWidth = 1
    const step = 500, x0 = Math.floor((cx - w / 2 / scale) / step) * step, y0 = Math.floor((cy - h / 2 / scale) / step) * step
    for (let x = x0; x < cx + w / 2 / scale; x += step) { g.beginPath(); g.moveTo(sx(x), 0); g.lineTo(sx(x), h); g.stroke() }
    for (let y = y0; y < cy + h / 2 / scale; y += step) { g.beginPath(); g.moveTo(0, sy(y)); g.lineTo(w, sy(y)); g.stroke() }
    // routes
    if (roads?.roads) {
      g.strokeStyle = "#3a4048"; g.lineWidth = Math.max(1, Math.min(5, scale * 6)); g.lineCap = "round"
      g.beginPath()
      for (const [a, b, c2, d] of roads.roads) { g.moveTo(sx(a), sy(b)); g.lineTo(sx(c2), sy(d)) }
      g.stroke()
      g.strokeStyle = "#59616b"; g.lineWidth = Math.max(0.6, Math.min(2, scale * 2))
      g.beginPath()
      for (const [a, b, c2, d] of roads.roads) { g.moveTo(sx(a), sy(b)); g.lineTo(sx(c2), sy(d)) }
      g.stroke()
    }
    // joueurs
    g.font = "600 12px Segoe UI, sans-serif"; g.textAlign = "center"
    players.forEach((p, i) => {
      if (p.level !== level || p.x == null || p.y == null) return
      const x = sx(p.x), y = sy(p.y), col = COLORS[i % COLORS.length]
      g.beginPath(); g.arc(x, y, p.username === focus ? 9 : 7, 0, Math.PI * 2)
      g.fillStyle = col; g.fill(); g.lineWidth = 2; g.strokeStyle = "#fff"; g.stroke()
      const tw = g.measureText(p.username).width + 12
      g.fillStyle = "rgba(0,0,0,0.75)"; g.fillRect(x - tw / 2, y - 30, tw, 18)
      g.fillStyle = "#fff"; g.fillText(p.username, x, y - 17)
    })
    // échelle
    const m = [50, 100, 250, 500, 1000, 2000].find(v => v * scale > 70) || 2000
    g.strokeStyle = "#fff"; g.lineWidth = 2; g.beginPath(); g.moveTo(16, h - 18); g.lineTo(16 + m * scale, h - 18); g.stroke()
    g.fillStyle = "#fff"; g.textAlign = "left"; g.fillText(m >= 1000 ? `${m / 1000} km` : `${m} m`, 16, h - 24)
  })

  useEffect(() => {
    const onResize = () => redraw(n => n + 1)
    window.addEventListener("resize", onResize)
    return () => window.removeEventListener("resize", onResize)
  }, [])

  function onWheel(e: React.WheelEvent) {
    const el = wrap.current!
    const r = el.getBoundingClientRect(), mx = e.clientX - r.left - r.width / 2, my = e.clientY - r.top - r.height / 2
    const v = view.current, k = e.deltaY < 0 ? 1.2 : 1 / 1.2
    const wx = v.cx + mx / v.scale, wy = v.cy - my / v.scale // point sous la souris : il reste en place
    v.scale = Math.min(20, Math.max(0.02, v.scale * k))
    v.cx = wx - mx / v.scale; v.cy = wy + my / v.scale
    redraw(n => n + 1)
  }

  return (
    <div className="live-map" ref={wrap} onWheel={onWheel}
         onMouseDown={e => { drag.current = { x: e.clientX, y: e.clientY } }}
         onMouseMove={e => {
           if (!drag.current) return
           const v = view.current
           v.cx -= (e.clientX - drag.current.x) / v.scale; v.cy += (e.clientY - drag.current.y) / v.scale
           drag.current = { x: e.clientX, y: e.clientY }; redraw(n => n + 1)
         }}
         onMouseUp={() => { drag.current = null }} onMouseLeave={() => { drag.current = null }}>
      <canvas ref={canvas} />
      {roads === null && <div className="live-note">Les routes de cette carte n'ont pas encore été envoyées : elles le seront automatiquement dès qu'un joueur avec le mod 2.4.0 ou plus récent y joue. Les joueurs sont déjà affichés.</div>}
      <button className="btn dim sm live-fit" onClick={() => { view.current.fitted = ""; setRoads(r => (r === undefined ? r : r ? { ...r } : null)) }}>Recentrer</button>
    </div>
  )
}
