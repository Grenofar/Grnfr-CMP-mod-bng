import { open } from "@tauri-apps/plugin-dialog"

// Champ chemin + bouton « Parcourir » (sélecteur de fichier ou de dossier natif).
export default function PathField({ label, value, onChange, directory, help, optional }: {
  label: string
  value: string | null
  onChange: (v: string | null) => void
  directory?: boolean
  help?: string
  optional?: boolean
}) {
  async function browse() {
    const picked = await open(directory
      ? { directory: true, multiple: false }
      : { multiple: false, filters: [{ name: "Programme", extensions: ["exe"] }, { name: "Tous les fichiers", extensions: ["*"] }] })
    if (typeof picked === "string") onChange(picked)
  }
  return (
    <label>
      <span>{label}{optional && <span className="mut"> (facultatif)</span>}</span>
      <div className="row nowrap">
        <input className="grow" value={value || ""} placeholder={directory ? "Dossier non trouvé" : "Non trouvé"} onChange={e => onChange(e.target.value.trim() || null)} />
        <button type="button" className="btn dim" onClick={browse}>Parcourir…</button>
      </div>
      {help && <span className="mut small">{help}</span>}
    </label>
  )
}
