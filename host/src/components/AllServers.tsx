import { useState } from "react"
import { api, ServerStatus } from "../api"
import UpdateBanner from "./UpdateBanner"

// Vue "Tableau de bord" : tous les serveurs de cette installation, avec démarrage/arrêt rapide. Plusieurs
// peuvent tourner en même temps, chacun sur son propre port.
export default function AllServers({ servers, onSelect, onNew, onChanged }: {
  servers: ServerStatus[]
  onSelect: (id: string) => void
  onNew: () => void
  onChanged: () => void
}) {
  const [busyId, setBusyId] = useState<string | null>(null)

  async function toggle(s: ServerStatus) {
    setBusyId(s.id)
    try {
      if (s.running) await api.stopServer(s.id)
      else await api.startServer(s.id)
      onChanged()
    } finally {
      setBusyId(null)
    }
  }

  const runningCount = servers.filter(s => s.running).length
  const totalPlayers = servers.reduce((n, s) => n + s.players.length, 0)

  return (
    <div>
      <h1>Tableau de bord</h1>

      <UpdateBanner runningCount={runningCount} />

      <div className="card">
        <div className="row">
          <div><label>Serveurs</label><div className="big">{servers.length}</div></div>
          <div style={{ marginLeft: 32 }}><label>En ligne</label><div className="big">{runningCount}</div></div>
          <div style={{ marginLeft: 32 }}><label>Joueurs connectés</label><div className="big">{totalPlayers}</div></div>
        </div>
      </div>

      {!servers.length && <p className="mut">Aucun serveur pour l'instant.</p>}

      {servers.map(s => (
        <div key={s.id} className="card server-card" onClick={() => onSelect(s.id)}>
          <div className="row between">
            <div>
              <span className={s.running ? "dot on" : "dot off"} />
              <b>{s.name}</b>
              <span className="mut"> · port {s.port}{s.has_password ? " · protégé" : ""} · {s.players.length} joueur{s.players.length > 1 ? "s" : ""}</span>
            </div>
            <button
              className={s.running ? "btn dim sm" : "btn sm"}
              disabled={busyId === s.id}
              onClick={e => { e.stopPropagation(); toggle(s) }}
            >
              {busyId === s.id ? "…" : s.running ? "Arrêter" : "Démarrer"}
            </button>
          </div>
        </div>
      ))}

      <button type="button" className="btn dim" onClick={onNew}>+ Nouveau serveur</button>
    </div>
  )
}
