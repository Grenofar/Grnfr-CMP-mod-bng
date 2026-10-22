import { useState } from "react"
import { api, Status } from "../api"

export default function Players({ status, onChanged }: { status: Status; onChanged: () => void }) {
  const [busyId, setBusyId] = useState<number | null>(null)

  async function kick(id: number, username: string) {
    if (!window.confirm(`Expulser ${username} ?`)) return
    setBusyId(id)
    try {
      await api.kickPlayer(id)
      onChanged()
    } finally {
      setBusyId(null)
    }
  }

  function since(secs: number): string {
    if (secs < 60) return `${secs}s`
    if (secs < 3600) return `${Math.floor(secs / 60)} min`
    return `${Math.floor(secs / 3600)} h ${Math.floor((secs % 3600) / 60)} min`
  }

  return (
    <div>
      <h1>Joueurs ({status.players.length})</h1>
      {!status.running && <p className="mut">Le serveur est arrêté — personne ne peut se connecter.</p>}
      {status.running && !status.players.length && <p className="mut">Personne pour le moment.</p>}
      {!!status.players.length && (
        <table className="tb">
          <thead>
            <tr><th>Pseudo</th><th>Adresse</th><th>Depuis</th><th></th></tr>
          </thead>
          <tbody>
            {status.players.map(p => (
              <tr key={p.id}>
                <td>{p.username}</td>
                <td className="mut">{p.peer}</td>
                <td className="mut">{since(p.joined_secs)}</td>
                <td>
                  <button className="btn dim sm" onClick={() => kick(p.id, p.username)} disabled={busyId === p.id}>
                    Expulser
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
