import { useEffect, useState } from "react"

// Assistant web de configuration du GRNFR Host CPM : nom, mot de passe (facultatif), port. Pas de nombre de
// joueurs maximum (volontaire : voir le message plus bas). Lit/écrit la config via la petite API intégrée au
// binaire Rust (host/src/httpd.rs) : GET /api/config et POST /api/config.
export default function App() {
  const [cfg, setCfg] = useState({ name: "", password: "", hasPassword: false, port: 30814 })
  const [status, setStatus] = useState("")
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState("")

  useEffect(() => {
    fetch("/api/config")
      .then(r => r.json())
      .then(d => setCfg({ name: d.name || "", password: d.password || "", hasPassword: !!d.password, port: d.port || 30814 }))
      .catch(() => setError("Impossible de lire la configuration actuelle (le serveur répond-il bien sur ce port ?)."))
      .finally(() => setLoaded(true))
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
      setStatus("Enregistré. Redémarrez le programme pour appliquer les changements (port / mot de passe).")
    } catch (err) {
      setStatus("")
      setError("Erreur à l'enregistrement : " + err.message)
    }
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
      <h1>GRNFR Host CPM</h1>
      <p className="sub">Serveur auto-hébergé pour GRNFR CPM — aucune limite de joueurs.</p>
      {error && <p className="error">{error}</p>}
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
          Port d'écoute (WebSocket)
          <input type="number" min={1} max={65535} value={cfg.port} onChange={e => setCfg({ ...cfg, port: e.target.value })} />
        </label>

        <button type="submit">Enregistrer</button>
        {status && <p className="status">{status}</p>}
        <p className="note">
          Sans mot de passe, n'importe qui connaissant votre adresse peut rejoindre. Pensez à ouvrir ce port sur
          votre routeur/pare-feu si vos joueurs ne sont pas sur le même réseau local.
        </p>
      </form>
    </div>
  )
}
