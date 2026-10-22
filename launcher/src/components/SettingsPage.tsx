import { useEffect, useState } from "react"
import { api, Settings, Status } from "../api"
import ModeChooser from "./ModeChooser"
import PathField from "./PathField"
import UpdateCard from "./UpdateCard"

// Page Paramètres : emplacements (avec détection automatique), lancement par défaut, mise à jour du mod, mise à
// jour du launcher, infos de connexion. Rien n'est enregistré avant « Enregistrer ».
export default function SettingsPage({ settings, onSaved }: { settings: Settings; onSaved: (s: Settings) => void }) {
  const [draft, setDraft] = useState<Settings>(settings)
  const [detecting, setDetecting] = useState(false)
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null)
  const [status, setStatus] = useState<Status | null>(null)

  useEffect(() => { setDraft(settings) }, [settings])
  useEffect(() => { api.status().then(setStatus).catch(() => {}) }, [])

  const dirty = JSON.stringify(draft) !== JSON.stringify(settings)

  async function detect() {
    setDetecting(true); setMsg(null)
    try {
      const d = await api.detect()
      const found = [d.beamng && "BeamNG", d.beammp && "BeamMP Launcher", d.mods_dir && "dossier mods"].filter(Boolean)
      setDraft({ ...draft, beamng_exe: d.beamng || draft.beamng_exe, beammp_exe: d.beammp || draft.beammp_exe, mods_dir: d.mods_dir || draft.mods_dir })
      setMsg({ ok: found.length > 0, text: found.length ? `Trouvé : ${found.join(", ")}. Pensez à enregistrer.` : "Rien trouvé automatiquement : indiquez les emplacements avec « Parcourir »." })
    } catch (e) { setMsg({ ok: false, text: String(e) }) } finally { setDetecting(false) }
  }

  async function save() {
    setMsg(null)
    try {
      await api.saveSettings(draft)
      onSaved(draft)
      setMsg({ ok: true, text: "Paramètres enregistrés." })
    } catch (e) { setMsg({ ok: false, text: String(e) }) }
  }

  return (
    <div>
      <h1>Paramètres</h1>

      <div className="card">
        <div className="row between">
          <label>Emplacements</label>
          <button className="btn dim sm" onClick={detect} disabled={detecting}>{detecting ? "Recherche…" : "Détecter automatiquement"}</button>
        </div>
        <PathField label="BeamNG.drive (exécutable)" value={draft.beamng_exe} onChange={v => setDraft({ ...draft, beamng_exe: v })}
          help="Utile pour le lancement direct. Inutile si vous lancez par Steam." optional />
        <PathField label="BeamMP Launcher" value={draft.beammp_exe} onChange={v => setDraft({ ...draft, beammp_exe: v })}
          help="Seulement si vous jouez avec BeamMP." optional />
        <PathField label="Dossier mods de BeamNG" value={draft.mods_dir} onChange={v => setDraft({ ...draft, mods_dir: v })} directory
          help="Le mod GRNFR CMP y est installé et mis à jour." />
      </div>

      <div className="card">
        <label>Lancement par défaut</label>
        <ModeChooser value={draft.mode} onChange={mode => setDraft({ ...draft, mode })} beammpFound={!!draft.beammp_exe} />
        <label className="row">
          <input type="checkbox" checked={draft.auto_update_mod} onChange={e => setDraft({ ...draft, auto_update_mod: e.target.checked })} />
          Installer / mettre à jour le mod GRNFR CMP automatiquement avant chaque lancement
        </label>
      </div>

      <div className="row between save-bar">
        <span>{msg && <span className={msg.ok ? "good" : "err"}>{msg.text}</span>}</span>
        <div className="row">
          {dirty && <button className="btn dim" onClick={() => { setDraft(settings); setMsg(null) }}>Annuler</button>}
          <button className="btn" onClick={save} disabled={!dirty}>Enregistrer</button>
        </div>
      </div>

      <UpdateCard />

      {status && (
        <div className="card">
          <label>Connexion du mod</label>
          <p className="mut small">
            Le mod se connecte au serveur GRNFR CMP en passant par ce launcher, à l'adresse locale <code>{status.relay_addr || "—"}</code>.
            {" "}{status.relay_ok ? "Active." : `Inactive : ${status.relay_error}`}
            {" "}{status.requests} requête(s) depuis l'ouverture{status.errors ? `, dont ${status.errors} en erreur` : ""}.
          </p>
        </div>
      )}
    </div>
  )
}
