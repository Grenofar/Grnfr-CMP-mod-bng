import { useState } from "react"
import { api, ServerStatus } from "../api"
import ServerForm, { ServerFormValues } from "./ServerForm"

type SubTab = "overview" | "players" | "settings"

export default function ServerDetail({ server, onChanged, onDeleted }: {
  server: ServerStatus
  onChanged: () => void
  onDeleted: () => void
}) {
  const [sub, setSub] = useState<SubTab>("overview")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const [status, setStatus] = useState("")
  const [busyPlayer, setBusyPlayer] = useState<number | null>(null)

  async function toggle() {
    setBusy(true)
    setError("")
    try {
      if (server.running) await api.stopServer(server.id)
      else await api.startServer(server.id)
      onChanged()
    } catch (err) {
      setError(String(err))
    } finally {
      setBusy(false)
    }
  }

  async function save(values: ServerFormValues) {
    setBusy(true)
    setError("")
    setStatus("")
    try {
      await api.updateServer(server.id, values.name, values.password, values.port)
      setStatus(server.running ? "Enregistré. Cliquez Arrêter puis Démarrer (Aperçu) pour appliquer." : "Enregistré.")
      onChanged()
    } catch (err) {
      setError("Enregistrement impossible (Supabase) : " + String(err))
    } finally {
      setBusy(false)
    }
  }

  async function remove() {
    if (!window.confirm(`Supprimer définitivement « ${server.name} » ?`)) return
    setBusy(true)
    try {
      await api.deleteServer(server.id)
      onDeleted()
    } catch (err) {
      setError(String(err))
      setBusy(false)
    }
  }

  async function kick(id: number, username: string) {
    if (!window.confirm(`Expulser ${username} ?`)) return
    setBusyPlayer(id)
    try {
      await api.kickPlayer(server.id, id)
      onChanged()
    } finally {
      setBusyPlayer(null)
    }
  }

  function since(secs: number): string {
    if (secs < 60) return `${secs}s`
    if (secs < 3600) return `${Math.floor(secs / 60)} min`
    return `${Math.floor(secs / 3600)} h ${Math.floor((secs % 3600) / 60)} min`
  }

  return (
    <div>
      <h1>{server.name}</h1>
      <div className="subtabs">
        <button className={sub === "overview" ? "on" : ""} onClick={() => setSub("overview")}>Aperçu</button>
        <button className={sub === "players" ? "on" : ""} onClick={() => setSub("players")}>Joueurs ({server.players.length})</button>
        <button className={sub === "settings" ? "on" : ""} onClick={() => setSub("settings")}>Paramètres</button>
      </div>

      {error && <p className="err">{error}</p>}
      {status && <p className="ok">{status}</p>}

      {sub === "overview" && (
        <div className="card">
          <div className="row between">
            <div>
              <span className={server.running ? "dot on" : "dot off"} />
              {server.running ? "En ligne" : "Arrêté"}
              <span className="mut"> · port {server.port}{server.has_password ? " · protégé" : ""}</span>
            </div>
            <button className={server.running ? "btn dim" : "btn"} onClick={toggle} disabled={busy}>
              {busy ? "…" : server.running ? "Arrêter le serveur" : "Démarrer le serveur"}
            </button>
          </div>
        </div>
      )}

      {sub === "players" && (
        <div>
          {!server.running && <p className="mut">Le serveur est arrêté — personne ne peut se connecter.</p>}
          {server.running && !server.players.length && <p className="mut">Personne pour le moment.</p>}
          {!!server.players.length && (
            <table className="tb">
              <thead><tr><th>Pseudo</th><th>Adresse</th><th>Depuis</th><th></th></tr></thead>
              <tbody>
                {server.players.map(p => (
                  <tr key={p.id}>
                    <td>{p.username}</td>
                    <td className="mut">{p.peer}</td>
                    <td className="mut">{since(p.joined_secs)}</td>
                    <td><button className="btn dim sm" onClick={() => kick(p.id, p.username)} disabled={busyPlayer === p.id}>Expulser</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {sub === "settings" && (
        <div>
          <div className="card">
            <ServerForm
              initial={{ name: server.name, hasPassword: server.has_password, port: server.port }}
              submitLabel="Enregistrer"
              busy={busy}
              onSubmit={save}
            />
          </div>
          <button type="button" className="btn dim" onClick={remove} disabled={busy}>Supprimer ce serveur</button>
        </div>
      )}
    </div>
  )
}
