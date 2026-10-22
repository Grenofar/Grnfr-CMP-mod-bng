import { useState } from "react"
import { api } from "../api"

// Premier lancement : aucune config trouvée dans Supabase pour cet host_id. Une fois enregistré, le relais
// démarre automatiquement (voir lib.rs::commands::save_config) et App.tsx bascule sur le tableau de bord.
export default function SetupWizard({ onDone }: { onDone: () => void }) {
  const [name, setName] = useState("Serveur GRNFR")
  const [hasPassword, setHasPassword] = useState(false)
  const [password, setPassword] = useState("")
  const [port, setPort] = useState("30814")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError("")
    const portNum = Number(port)
    if (!Number.isInteger(portNum) || portNum <= 0 || portNum > 65535) {
      setError("Port invalide (nombre entre 1 et 65535 attendu).")
      return
    }
    setBusy(true)
    try {
      await api.saveConfig(name.trim() || "Serveur GRNFR", hasPassword && password.trim() ? password.trim() : null, portNum)
      onDone()
    } catch (err) {
      setError("Enregistrement impossible (Supabase) : " + String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="setup">
      <div className="setup-card">
        <h1>GRNFR Host CMP</h1>
        <p className="mut">Premier lancement — configurez votre serveur. Tout reste modifiable ensuite depuis le tableau de bord.</p>

        <form onSubmit={submit}>
          <label>
            Nom du serveur
            <input value={name} maxLength={40} onChange={e => setName(e.target.value)} />
          </label>

          <label className="row">
            <input type="checkbox" checked={hasPassword} onChange={e => setHasPassword(e.target.checked)} />
            Protéger par un mot de passe
          </label>
          {hasPassword && (
            <label>
              Mot de passe
              <input type="password" value={password} onChange={e => setPassword(e.target.value)} />
            </label>
          )}

          <label>
            Port d'écoute (WebSocket) — valeur par défaut : 30814
            <input value={port} onChange={e => setPort(e.target.value)} inputMode="numeric" />
          </label>

          {error && <p className="err">{error}</p>}
          <button type="submit" className="btn" disabled={busy}>
            {busy ? "Enregistrement…" : "Enregistrer et démarrer"}
          </button>
        </form>
      </div>
    </div>
  )
}
