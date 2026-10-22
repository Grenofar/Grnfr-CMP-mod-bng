import { useEffect, useState } from "react"
import { api, LatestRelease, Status } from "../api"

export default function Overview({ status, onChanged }: { status: Status; onChanged: () => void }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const [update, setUpdate] = useState<LatestRelease | null>(null)
  const [updateBusy, setUpdateBusy] = useState(false)
  const [updateError, setUpdateError] = useState("")

  useEffect(() => {
    api.checkUpdate().then(setUpdate).catch(() => {})
  }, [])

  async function toggle() {
    setBusy(true)
    setError("")
    try {
      if (status.running) await api.stopServer()
      else await api.startServer()
      onChanged()
    } catch (err) {
      setError(String(err))
    } finally {
      setBusy(false)
    }
  }

  async function startUpdate() {
    if (!update) return
    setUpdateBusy(true)
    setUpdateError("")
    try {
      await api.installUpdate(update.download_url, update.asset_name)
    } catch (err) {
      setUpdateError(String(err))
    } finally {
      setUpdateBusy(false)
    }
  }

  return (
    <div>
      <h1>Tableau de bord</h1>

      <div className="card">
        <div className="row between">
          <div>
            <div className="big">{status.name}</div>
            <div className="mut">
              port {status.port}
              {status.has_password ? " · protégé par mot de passe" : " · sans mot de passe"}
            </div>
          </div>
          <button className={status.running ? "btn dim" : "btn"} onClick={toggle} disabled={busy}>
            {busy ? "…" : status.running ? "Arrêter le serveur" : "Démarrer le serveur"}
          </button>
        </div>
        {error && <p className="err">{error}</p>}
      </div>

      <div className="card">
        <label>Joueurs connectés</label>
        <div className="big">{status.players.length}</div>
      </div>

      {update && (
        <div className="card update-banner">
          <div className="row between">
            <span>Nouvelle version disponible : <b>{update.tag}</b></span>
            <button className="btn" onClick={startUpdate} disabled={updateBusy}>
              {updateBusy ? "Téléchargement…" : "Télécharger et installer"}
            </button>
          </div>
          {updateError && <p className="err">{updateError}</p>}
          <p className="mut small">Le téléchargement lance l'installeur natif de votre OS ; terminez l'installation vous-même (l'app actuelle peut continuer à tourner pendant ce temps).</p>
        </div>
      )}

      <p className="mut small">
        Sans mot de passe, n'importe qui connaissant votre adresse peut rejoindre. Aucune limite de joueurs
        (contrairement aux serveurs Supabase, limités à 4).
      </p>
    </div>
  )
}
