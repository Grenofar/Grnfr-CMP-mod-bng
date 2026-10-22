import { useCallback, useEffect, useState } from "react"
import { api, Status } from "./api"
import Sidebar, { Tab } from "./components/Sidebar"
import SetupWizard from "./components/SetupWizard"
import Overview from "./components/Overview"
import Players from "./components/Players"
import Settings from "./components/Settings"

export default function App() {
  const [status, setStatus] = useState<Status | null>(null)
  const [tab, setTab] = useState<Tab>("overview")
  const [pollError, setPollError] = useState("")

  const refresh = useCallback(() => {
    api
      .getStatus()
      .then(s => {
        setStatus(s)
        setPollError("")
      })
      .catch(err => setPollError(String(err)))
  }, [])

  useEffect(() => {
    refresh()
    const t = setInterval(refresh, 1500)
    return () => clearInterval(t)
  }, [refresh])

  if (!status) {
    return (
      <div className="loading">
        <p className="mut">Chargement…</p>
        {pollError && <p className="err">{pollError}</p>}
      </div>
    )
  }

  // configured === null : encore en train de vérifier Supabase au démarrage.
  if (status.configured === null) {
    return (
      <div className="loading">
        <p className="mut">Connexion à Supabase…</p>
      </div>
    )
  }

  if (status.configured === false) {
    return <SetupWizard onDone={refresh} />
  }

  return (
    <div className="shell">
      <Sidebar tab={tab} onTab={setTab} running={status.running} />
      <main>
        {!status.running && status.configured && (
          <div className="banner">
            Le serveur est arrêté. Ouvrez « Tableau de bord » pour le démarrer.
          </div>
        )}
        <div className="main-content">
          {tab === "overview" && <Overview status={status} onChanged={refresh} />}
          {tab === "players" && <Players status={status} onChanged={refresh} />}
          {tab === "settings" && <Settings status={status} onChanged={refresh} />}
        </div>
      </main>
    </div>
  )
}
