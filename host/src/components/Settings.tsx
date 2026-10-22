import { useState } from "react"
import { api, Status } from "../api"

export default function Settings({ status, onChanged }: { status: Status; onChanged: () => void }) {
  const [name, setName] = useState(status.name)
  const [hasPassword, setHasPassword] = useState(status.has_password)
  const [password, setPassword] = useState("")
  const [port, setPort] = useState(String(status.port))
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const [savedMsg, setSavedMsg] = useState("")

  async function save(e: React.FormEvent) {
    e.preventDefault()
    setError("")
    setSavedMsg("")
    const portNum = Number(port)
    if (!Number.isInteger(portNum) || portNum <= 0 || portNum > 65535) {
      setError("Port invalide.")
      return
    }
    if (hasPassword && !password.trim()) {
      setError("Entrez un mot de passe (ou décochez la case pour ne pas en utiliser).")
      return
    }
    setBusy(true)
    try {
      await api.saveConfig(name.trim() || "Serveur GRNFR", hasPassword ? password.trim() : null, portNum)
      setSavedMsg(
        status.running
          ? "Enregistré. Cliquez Arrêter puis Démarrer (Tableau de bord) pour appliquer le port/mot de passe."
          : "Enregistré."
      )
      onChanged()
    } catch (err) {
      setError("Enregistrement impossible (Supabase) : " + String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div>
      <h1>Paramètres du serveur</h1>
      <form className="card" onSubmit={save}>
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
            Mot de passe {status.has_password && <span className="mut small">(ressaisissez-le : il n'est jamais préaffiché)</span>}
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} />
          </label>
        )}

        <label>
          Port d'écoute (WebSocket)
          <input value={port} onChange={e => setPort(e.target.value)} inputMode="numeric" />
        </label>

        {error && <p className="err">{error}</p>}
        {savedMsg && <p className="ok">{savedMsg}</p>}
        <button type="submit" className="btn" disabled={busy}>
          {busy ? "Enregistrement…" : "Enregistrer"}
        </button>
      </form>
    </div>
  )
}
