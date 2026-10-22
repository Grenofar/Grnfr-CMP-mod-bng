import { useCallback, useEffect, useState } from "react"
import { api, ServerStatus } from "./api"
import Sidebar, { Selection } from "./components/Sidebar"
import AllServers from "./components/AllServers"
import ServerDetail from "./components/ServerDetail"
import NewServer from "./components/NewServer"
import LiveMap from "./components/LiveMap"

export default function App() {
  const [servers, setServers] = useState<ServerStatus[] | null>(null)
  const [selected, setSelected] = useState<Selection>("overview")
  const [pollError, setPollError] = useState("")

  const refresh = useCallback(() => {
    api
      .listServers()
      .then(list => {
        setServers(list)
        setPollError("")
      })
      .catch(err => setPollError(String(err)))
  }, [])

  useEffect(() => {
    refresh()
    const t = setInterval(refresh, 1500)
    return () => clearInterval(t)
  }, [refresh])

  if (servers === null) {
    return (
      <div className="loading">
        <p className="mut">Connexion à Supabase…</p>
        {pollError && <p className="err">{pollError}</p>}
      </div>
    )
  }

  // Premier lancement : aucun serveur encore créé sur cette installation.
  if (servers.length === 0) {
    return <NewServer firstRun onCreated={id => { setSelected(id); refresh() }} />
  }

  const special = selected === "overview" || selected === "new" || selected === "live"
  const current = !special ? servers.find(s => s.id === selected) : undefined
  // Le serveur sélectionné a été supprimé depuis ailleurs (ou à l'instant) : retombe sur le tableau de bord.
  if (!special && !current) {
    if (selected !== "overview") setTimeout(() => setSelected("overview"), 0)
  }

  return (
    <div className="shell">
      <Sidebar servers={servers} selected={selected} onSelect={setSelected} />
      <main>
        <div className={selected === "live" ? "main-content wide" : "main-content"}>
          {selected === "overview" && (
            <AllServers servers={servers} onSelect={setSelected} onNew={() => setSelected("new")} onChanged={refresh} />
          )}
          {selected === "live" && <LiveMap />}
          {selected === "new" && <NewServer onCreated={id => { setSelected(id); refresh() }} />}
          {current && (
            <ServerDetail
              server={current}
              onChanged={refresh}
              onDeleted={() => { setSelected("overview"); refresh() }}
            />
          )}
        </div>
      </main>
    </div>
  )
}
