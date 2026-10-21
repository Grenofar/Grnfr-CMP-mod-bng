import { useEffect, useRef, useState } from "react"

// Tableau de bord + assistant de configuration du GRNFR Host CMP, servis par la petite API intégrée au
// binaire Rust (host/src/httpd.rs) : GET/POST /api/config, GET /api/status, POST /api/start, POST /api/stop,
// POST /api/kick. Le port a une valeur par défaut (30814) mais reste modifiable ; un changement de port ou
// de mot de passe est repris en cliquant Arrêter puis Démarrer (pas besoin de fermer le programme).
export default function App() {
  const [cfg, setCfg] = useState({ name: "", password: "", hasPassword: false, port: 30814 })
  const [status, setStatus] = useState("")
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState("")
  const [live, setLive] = useState({ running: false, name: "", port: 30814, hasPassword: false, players: [] })
  const pollRef = useRef(null)

  async function loadStatus() {
    try {
      const r = await fetch("/api/status")
      const d = await r.json()
      setLive(d)
    } catch (e) { /* le programme est peut-être en train de redémarrer : on retentera au prochain sondage */ }
  }

  useEffect(() => {
    fetch("/api/config")
      .then(r => r.json())
      .then(d => setCfg({ name: d.name || "", password: d.password || "", hasPassword: !!d.password, port: d.port || 30814 }))
      .catch(() => setError("Impossible de lire la configuration actuelle (le serveur répond-il bien sur ce port ?)."))
      .finally(() => setLoaded(true))
    loadStatus()
    pollRef.current = setInterval(loadStatus, 3000)
    return () => clearInterval(pollRef.current)
  }, [])

  async function save(e) {
    e.preventDefault()
    setStatus("Enregistrement…")
    setError("")
    try {
      const res = await fetch("/api/config", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: cfg.name, password: cfg.hasPassword ? cfg.password : "", port: Number(cfg.port) }),
      })
      if (!res.ok) throw new Error("http_" + res.status)
      setStatus(live.running ? "Enregistré. Cliquez \"Arrêter\" puis \"Démarrer\" pour appliquer (port / mot de passe)." : "Enregistré.")
      await loadStatus()
    } catch (err) {
      setStatus("")
      setError("Erreur à l'enregistrement : " + err.message)
    }
  }

  async function startServer() {
    setError(""); setStatus("Démarrage…")
    try {
      const res = await fetch("/api/start", { method: "POST" })
      const d = await res.json()
      if (!res.ok) throw new Error(d.error || ("http_" + res.status))
      setStatus("Serveur démarré.")
    } catch (err) { setError("Démarrage impossible : " + err.message) }
    await loadStatus()
  }

  async function stopServer() {
    setError(""); setStatus("Arrêt…")
    await fetch("/api/stop", { method: "POST" })
    setStatus("Serveur arrêté.")
    await loadStatus()
  }

  async function kick(id, username) {
    if (!window.confirm(`Expulser ${username} ?`)) return
    try {
      const res = await fetch("/api/kick", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id }),
      })
      if (!res.ok) throw new Error("http_" + res.status)
    } catch (err) { setError("Expulsion impossible : " + err.message) }
    await loadStatus()
  }

  function since(secs) {
    if (secs < 60) return `${secs}s`
    if (secs < 3600) return `${Math.floor(secs / 60)} min`
    return `${Math.floor(secs / 3600)} h ${Math.floor((secs % 3600) / 60)} min`
  }

  if (!loaded) {
    return (
      <div className="wrap">
        <p className="mut">Chargement…</p>
      </div>
    )
  }

  return (
    <div className="wrap">
      <h1>GRNFR Host CMP</h1>
      <p className="sub">Serveur auto-hébergé pour GRNFR CMP — aucune limite de joueurs.</p>
      {error && <p className="error">{error}</p>}

      <div className="card">
        <div className="row between">
          <span className={live.running ? "badge on" : "badge off"}>{live.running ? "🟢 En ligne" : "🔴 Arrêté"}</span>
          <span className="mut">{live.name} · port {live.port}{live.hasPassword ? " · protégé" : ""}</span>
          {live.running
            ? <button type="button" className="btn dim" onClick={stopServer}>Arrêter le serveur</button>
            : <button type="button" className="btn" onClick={startServer}>Démarrer le serveur</button>}
        </div>
        {status && <p className="status">{status}</p>}
      </div>

      <div className="card">
        <h2>Joueurs connectés ({live.players.length})</h2>
        {!live.players.length && <p className="mut">Personne pour le moment.</p>}
        {!!live.players.length && (
          <table className="tb">
            <thead><tr><th>Pseudo</th><th>Adresse</th><th>Depuis</th><th></th></tr></thead>
            <tbody>
              {live.players.map(p => (
                <tr key={p.id}>
                  <td>{p.username}</td>
                  <td className="mut">{p.peer}</td>
                  <td className="mut">{since(p.joined_secs)}</td>
                  <td><button type="button" className="btn dim sm" onClick={() => kick(p.id, p.username)}>Expulser</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card">
        <h2>Paramètres du serveur</h2>
        <form onSubmit={save}>
          <label>
            Nom du serveur
            <input value={cfg.name} maxLength={40} onChange={e => setCfg({ ...cfg, name: e.target.value })} />
          </label>

          <label className="row">
            <input type="checkbox" checked={cfg.hasPassword} onChange={e => setCfg({ ...cfg, hasPassword: e.target.checked })} />
            Protéger le serveur par un mot de passe
          </label>
          {cfg.hasPassword && (
            <label>
              Mot de passe
              <input type="password" value={cfg.password} onChange={e => setCfg({ ...cfg, password: e.target.value })} />
            </label>
          )}

          <label>
            Port d'écoute (WebSocket) — valeur par défaut : 30814
            <input type="number" min={1} max={65535} value={cfg.port} onChange={e => setCfg({ ...cfg, port: e.target.value })} />
          </label>

          <button type="submit" className="btn">Enregistrer</button>
          <p className="note">
            Sans mot de passe, n'importe qui connaissant votre adresse peut rejoindre. Pensez à ouvrir ce port sur
            votre routeur/pare-feu si vos joueurs ne sont pas sur le même réseau local. Un changement de port ou de
            mot de passe n'est repris qu'au prochain démarrage du relais (Arrêter puis Démarrer ci-dessus).
          </p>
        </form>
      </div>
    </div>
  )
}
