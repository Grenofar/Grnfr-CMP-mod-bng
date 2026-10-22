import { useState } from "react"

export interface ServerFormValues { name: string; password: string | null; port: number }

// Formulaire réutilisé pour créer OU modifier un serveur. En édition, le mot de passe n'est jamais
// pré-rempli (jamais renvoyé en clair par défaut) : le laisser vide en décochant "protégé" le retire, le
// laisser vide en le gardant coché le redemande (pas d'ambiguïté "garder l'actuel" vs "effacer").
export default function ServerForm({
  initial, submitLabel, busy, onSubmit,
}: {
  initial?: { name: string; hasPassword: boolean; port: number }
  submitLabel: string
  busy: boolean
  onSubmit: (values: ServerFormValues) => void
}) {
  const [name, setName] = useState(initial?.name ?? "Serveur GRNFR")
  const [hasPassword, setHasPassword] = useState(initial?.hasPassword ?? false)
  const [password, setPassword] = useState("")
  const [port, setPort] = useState(String(initial?.port ?? 30814))
  const [error, setError] = useState("")

  function submit(e: React.FormEvent) {
    e.preventDefault()
    setError("")
    const portNum = Number(port)
    if (!Number.isInteger(portNum) || portNum <= 0 || portNum > 65535) {
      setError("Port invalide (nombre entre 1 et 65535 attendu).")
      return
    }
    if (hasPassword && !password.trim()) {
      setError("Entrez un mot de passe (ou décochez la case pour ne pas en utiliser).")
      return
    }
    onSubmit({ name: name.trim() || "Serveur GRNFR", password: hasPassword ? password.trim() : null, port: portNum })
  }

  return (
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
          Mot de passe {initial && <span className="mut small">(toujours à ressaisir : jamais préaffiché)</span>}
          <input type="password" value={password} onChange={e => setPassword(e.target.value)} />
        </label>
      )}

      <label>
        Port d'écoute (WebSocket) — valeur par défaut : 30814
        <input value={port} onChange={e => setPort(e.target.value)} inputMode="numeric" />
      </label>

      {error && <p className="err">{error}</p>}
      <button type="submit" className="btn" disabled={busy}>{busy ? "…" : submitLabel}</button>
    </form>
  )
}
