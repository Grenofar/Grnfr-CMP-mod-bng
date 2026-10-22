import { useEffect, useRef, useState } from "react"
import { check, Update } from "@tauri-apps/plugin-updater"
import { relaunch } from "@tauri-apps/plugin-process"

// Mise à jour réelle (signée, voir host/README.md) : @tauri-apps/plugin-updater lit latest.json sur la dernière
// GitHub Release, télécharge l'installeur, vérifie sa signature et le lance. Sur Windows, l'installeur ferme l'app
// (donc coupe les serveurs) pendant l'installation ; relaunch() la relance ensuite.
// Carte toujours visible (version, état, bouton) : avant, elle n'apparaissait qu'en présence d'une mise à jour et
// avalait les erreurs, si bien qu'on ne pouvait pas savoir si la vérification marchait.
const RECHECK_MS = 6 * 60 * 60 * 1000

type State =
  | { kind: "checking" }
  | { kind: "uptodate"; at: Date }
  | { kind: "available"; update: Update }
  | { kind: "installing"; update: Update; downloaded: number; total: number }
  | { kind: "error"; message: string }

export default function UpdateBanner({ runningCount }: { runningCount: number }) {
  const [state, setState] = useState<State>({ kind: "checking" })
  const installingRef = useRef(false)
  installingRef.current = state.kind === "installing"

  async function verify() {
    if (installingRef.current) return
    setState({ kind: "checking" })
    try {
      const update = await check()
      setState(update ? { kind: "available", update } : { kind: "uptodate", at: new Date() })
    } catch (err) {
      setState({ kind: "error", message: String(err) })
    }
  }

  useEffect(() => {
    verify()
    const t = setInterval(verify, RECHECK_MS)
    return () => clearInterval(t)
  }, [])

  async function install(update: Update) {
    let downloaded = 0
    let total = 0
    setState({ kind: "installing", update, downloaded, total })
    try {
      await update.downloadAndInstall(event => {
        if (event.event === "Started") total = event.data.contentLength || 0
        else if (event.event === "Progress") downloaded += event.data.chunkLength
        setState({ kind: "installing", update, downloaded, total })
      })
      await relaunch()
    } catch (err) {
      setState({ kind: "error", message: String(err) })
    }
  }

  const highlight = state.kind === "available" || state.kind === "installing"
  return (
    <div className={highlight ? "card update-banner" : "card"}>
      <div className="row between">
        <div>
          <label>Mise à jour</label>
          <div>
            Version installée : <b>{__APP_VERSION__}</b>
            {state.kind === "checking" && <span className="mut"> · vérification…</span>}
            {state.kind === "uptodate" && <span className="mut"> · à jour (vérifié à {state.at.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })})</span>}
            {(state.kind === "available" || state.kind === "installing") && <> · nouvelle version : <b>{state.update.version}</b></>}
          </div>
        </div>
        <div className="row">
          {state.kind === "available" && <button className="btn" onClick={() => install(state.update)}>Installer la mise à jour</button>}
          {state.kind === "installing" && <button className="btn" disabled>Installation…</button>}
          {state.kind !== "installing" && (
            <button className="btn dim" onClick={verify} disabled={state.kind === "checking"}>Vérifier les mises à jour</button>
          )}
        </div>
      </div>
      {state.kind === "installing" && state.total > 0 && (
        <div className="progress-bar"><div className="progress-fill" style={{ width: `${Math.min(100, (state.downloaded / state.total) * 100)}%` }} /></div>
      )}
      {state.kind === "available" && state.update.body && <p className="mut small">{state.update.body}</p>}
      {state.kind === "available" && runningCount > 0 && (
        <p className="mut small">⚠ {runningCount} serveur(s) en ligne : ils seront coupés pendant l'installation, puis l'app redémarre toute seule.</p>
      )}
      {state.kind === "error" && <p className="err">Vérification impossible : {state.message}</p>}
    </div>
  )
}
