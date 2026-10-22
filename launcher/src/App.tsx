import { useEffect, useState } from "react"
import { check } from "@tauri-apps/plugin-updater"
import { api, Settings } from "./api"
import Wizard from "./components/Wizard"
import Home from "./components/Home"
import SettingsPage from "./components/SettingsPage"

type Page = "home" | "settings"

export default function App() {
  const [settings, setSettings] = useState<Settings | null>(null)
  const [page, setPage] = useState<Page>("home")
  const [updateVersion, setUpdateVersion] = useState<string | null>(null)
  const [error, setError] = useState("")

  useEffect(() => {
    api.settings().then(setSettings).catch(e => setError(String(e)))
    // Simple pastille sur « Paramètres » : l'installation elle-même se fait depuis la carte de mise à jour.
    check().then(u => setUpdateVersion(u ? u.version : null)).catch(() => {})
  }, [])

  if (!settings) {
    return <div className="loading">{error ? <p className="err">{error}</p> : <p className="mut">Chargement…</p>}</div>
  }
  if (!settings.wizard_done) {
    return (
      <main className="single">
        <div className="main-content"><Wizard initial={settings} onDone={setSettings} /></div>
      </main>
    )
  }
  return (
    <main className="single">
      <nav className="topbar">
        <span className="brand"><span className="dot" />GRNFR CMP Launcher</span>
        <div className="tabs">
          <button className={page === "home" ? "tab on" : "tab"} onClick={() => setPage("home")}>Accueil</button>
          <button className={page === "settings" ? "tab on" : "tab"} onClick={() => setPage("settings")}>
            Paramètres{updateVersion && <span className="badge" title={`Nouvelle version ${updateVersion}`}>1</span>}
          </button>
        </div>
        <span className="mut small">v{__APP_VERSION__}</span>
      </nav>
      <div className="main-content">
        {updateVersion && page === "home" && (
          <div className="card update-banner row between">
            <span>Nouvelle version du launcher disponible : <b>{updateVersion}</b></span>
            <button className="btn sm" onClick={() => setPage("settings")}>Voir</button>
          </div>
        )}
        {page === "home"
          ? <Home settings={settings} onSettings={setSettings} />
          : <SettingsPage settings={settings} onSaved={setSettings} />}
      </div>
    </main>
  )
}
