import { useEffect, useState } from "react"
import { check, Update } from "@tauri-apps/plugin-updater"
import { relaunch } from "@tauri-apps/plugin-process"

// Mise à jour réelle (signée, voir host/README.md) : télécharge et installe tout seul, sans passer par
// l'installeur affiché à l'utilisateur comme avant — @tauri-apps/plugin-updater s'en charge entièrement.
// Sur Windows, l'app se ferme automatiquement pendant l'installation (limitation de l'installeur Windows) ;
// relaunch() la relance ensuite (sans effet si déjà fermée par Windows, c'est le comportement attendu).
export default function UpdateBanner() {
  const [update, setUpdate] = useState<Update | null>(null)
  const [progress, setProgress] = useState<{ downloaded: number; total: number } | null>(null)
  const [installing, setInstalling] = useState(false)
  const [error, setError] = useState("")

  useEffect(() => {
    check().then(setUpdate).catch(() => {})
  }, [])

  if (!update) return null

  async function install() {
    if (!update) return
    setInstalling(true)
    setError("")
    try {
      let downloaded = 0
      let total = 0
      await update.downloadAndInstall(event => {
        if (event.event === "Started") { total = event.data.contentLength || 0; setProgress({ downloaded: 0, total }) }
        else if (event.event === "Progress") { downloaded += event.data.chunkLength; setProgress({ downloaded, total }) }
      })
      await relaunch()
    } catch (err) {
      setError(String(err))
      setInstalling(false)
    }
  }

  return (
    <div className="card update-banner">
      <div className="row between">
        <span>Nouvelle version disponible : <b>{update.version}</b></span>
        <button className="btn" onClick={install} disabled={installing}>
          {installing ? "Installation…" : "Télécharger et installer"}
        </button>
      </div>
      {progress && progress.total > 0 && (
        <div className="progress-bar"><div className="progress-fill" style={{ width: `${Math.min(100, (progress.downloaded / progress.total) * 100)}%` }} /></div>
      )}
      {error && <p className="err">{error}</p>}
      {update.body && <p className="mut small">{update.body}</p>}
      <p className="mut small">L'installation est automatique (signée) ; l'app redémarre toute seule à la fin.</p>
    </div>
  )
}
