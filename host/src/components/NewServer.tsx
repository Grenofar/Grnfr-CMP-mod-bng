import { useState } from "react"
import { api } from "../api"
import ServerForm, { ServerFormValues } from "./ServerForm"

export default function NewServer({ firstRun, onCreated }: { firstRun?: boolean; onCreated: (id: string) => void }) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")

  async function submit(values: ServerFormValues) {
    setBusy(true)
    setError("")
    try {
      const server = await api.createServer(values.name, values.password, values.port)
      onCreated(server.id)
    } catch (err) {
      setError("Création impossible (Supabase) : " + String(err))
      setBusy(false)
    }
  }

  const form = (
    <div className="card">
      <ServerForm submitLabel={firstRun ? "Créer et démarrer" : "Créer le serveur"} busy={busy} onSubmit={submit} />
      {error && <p className="err">{error}</p>}
    </div>
  )

  if (firstRun) {
    return (
      <div className="setup">
        <div className="setup-card">
          <h1>GRNFR Host CMP</h1>
          <p className="mut">Premier lancement — créez votre premier serveur. Vous pourrez en ajouter d'autres ensuite, et les faire tourner en même temps.</p>
          {form}
        </div>
      </div>
    )
  }

  return (
    <div>
      <h1>Nouveau serveur</h1>
      {form}
    </div>
  )
}
