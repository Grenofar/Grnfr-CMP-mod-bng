import { useCallback, useEffect, useRef, useState } from "react"
import { check } from "@tauri-apps/plugin-updater"
import { api, ModStatus, Settings } from "./api"
import Wizard from "./components/Wizard"
import Home from "./components/Home"
import SettingsPage from "./components/SettingsPage"
import ToastStack, { ToastItem } from "./components/Toast"

type Page = "home" | "settings"

// Mod : revérifié périodiquement (pas seulement à l'ouverture) pour que la notification arrive même si le
// launcher est resté ouvert pendant qu'une nouvelle version était publiée.
const MOD_RECHECK_MS = 5 * 60 * 1000

export default function App() {
  const [settings, setSettings] = useState<Settings | null>(null)
  const [page, setPage] = useState<Page>("home")
  const [updateVersion, setUpdateVersion] = useState<string | null>(null)
  const [mod, setMod] = useState<ModStatus | null>(null)
  const [modError, setModError] = useState("")
  const [modBusy, setModBusy] = useState(false)
  const [error, setError] = useState("")
  const [toasts, setToasts] = useState<ToastItem[]>([])

  // Pour ne notifier qu'une fois par nouvelle version détectée (pas à chaque vérification périodique).
  const notifiedLauncher = useRef<string | null>(null)
  const notifiedMod = useRef<string | null>(null)
  const toastId = useRef(0)

  const pushToast = useCallback((text: string, actionLabel?: string, onAction?: () => void) => {
    const id = ++toastId.current
    setToasts(ts => [...ts, { id, text, actionLabel, onAction }])
    setTimeout(() => setToasts(ts => ts.filter(t => t.id !== id)), 12000)
  }, [])
  const dismissToast = useCallback((id: number) => setToasts(ts => ts.filter(t => t.id !== id)), [])

  const checkMod = useCallback(async () => {
    setModBusy(true); setModError("")
    try {
      const m = await api.modStatus()
      setMod(m)
      if (!m.up_to_date && m.latest && notifiedMod.current !== m.latest.version) {
        notifiedMod.current = m.latest.version
        pushToast(`Nouvelle version du mod disponible : v${m.latest.version}`, "Voir", () => setPage("home"))
      }
    } catch (e) { setModError(String(e)) } finally { setModBusy(false) }
  }, [pushToast])

  useEffect(() => {
    api.settings().then(setSettings).catch(e => setError(String(e)))
    check().then(u => {
      if (u) {
        setUpdateVersion(u.version)
        if (notifiedLauncher.current !== u.version) {
          notifiedLauncher.current = u.version
          pushToast(`Nouvelle version du launcher disponible : v${u.version}`, "Voir", () => setPage("settings"))
        }
      }
    }).catch(() => {})
  }, [pushToast])

  useEffect(() => {
    if (!settings) return
    checkMod()
    const t = setInterval(checkMod, MOD_RECHECK_MS)
    return () => clearInterval(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings?.mods_dir])

  async function installMod() {
    setModBusy(true); setModError("")
    try {
      const r = await api.installMod()
      if (r.failed.length) setModError("Anciennes versions non supprimées (fermez BeamNG puis réessayez) : " + r.failed.map(p => p.split(/[\\/]/).pop() || p).join(", "))
      setMod(await api.modStatus())
    } catch (e) { setModError(String(e)) } finally { setModBusy(false) }
  }

  if (!settings) {
    return <div className="loading">{error ? <p className="err">{error}</p> : <p className="mut">Chargement…</p>}</div>
  }
  if (!settings.wizard_done) {
    return (
      <main className="single">
        <div className="main-content"><Wizard initial={settings} onDone={setSettings} /></div>
        <ToastStack toasts={toasts} onDismiss={dismissToast} />
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
          ? <Home settings={settings} onSettings={setSettings} mod={mod} modError={modError} modBusy={modBusy} onCheckMod={checkMod} onInstallMod={installMod} />
          : <SettingsPage settings={settings} onSaved={setSettings} />}
      </div>
      <ToastStack toasts={toasts} onDismiss={dismissToast} />
    </main>
  )
}
