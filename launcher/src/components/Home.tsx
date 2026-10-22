import { useCallback, useEffect, useState } from "react"
import { api, ModStatus, Settings, Status } from "../api"
import ModeChooser from "./ModeChooser"
import PathField from "./PathField"
import UpdateCard from "./UpdateCard"

const fileName = (p: string) => p.split(/[\\/]/).pop() || p

export default function Home({ settings, onSettings, onWizard }: {
  settings: Settings
  onSettings: (s: Settings) => void
  onWizard: () => void
}) {
  const [status, setStatus] = useState<Status | null>(null)
  const [mod, setMod] = useState<ModStatus | null>(null)
  const [modError, setModError] = useState("")
  const [modBusy, setModBusy] = useState(false)
  const [launching, setLaunching] = useState(false)
  const [launchMsg, setLaunchMsg] = useState<{ ok: boolean; text: string } | null>(null)
  const [showSettings, setShowSettings] = useState(false)
  const [draft, setDraft] = useState<Settings>(settings)

  useEffect(() => {
    const poll = () => api.status().then(setStatus).catch(() => {})
    poll()
    const t = setInterval(poll, 2000)
    return () => clearInterval(t)
  }, [])

  const checkMod = useCallback(async () => {
    setModBusy(true); setModError("")
    try { setMod(await api.modStatus()) } catch (e) { setModError(String(e)) } finally { setModBusy(false) }
  }, [])
  useEffect(() => { checkMod() }, [checkMod, settings.mods_dir])

  async function installMod() {
    setModBusy(true); setModError("")
    try {
      const r = await api.installMod()
      if (r.failed.length) setModError("Anciennes versions non supprimées (fermez BeamNG puis réessayez) : " + r.failed.map(fileName).join(", "))
      setMod(await api.modStatus())
    } catch (e) { setModError(String(e)) } finally { setModBusy(false) }
  }

  async function save(next: Settings) {
    await api.saveSettings(next)
    onSettings(next)
  }

  async function launch() {
    setLaunching(true); setLaunchMsg(null)
    try {
      const r = await api.launch()
      const parts = ["BeamNG est en cours de lancement. Laissez le launcher ouvert pendant que vous jouez."]
      if (r.installed) parts.unshift(`Mod GRNFR CMP mis à jour en v${r.installed.version}.`)
      setLaunchMsg({ ok: !r.warning, text: [...parts, r.warning || ""].filter(Boolean).join(" ") })
      checkMod()
    } catch (e) { setLaunchMsg({ ok: false, text: String(e) }) } finally { setLaunching(false) }
  }

  const relayOk = status?.relay_ok
  return (
    <div className="home">
      <div className="row between">
        <h1>GRNFR CMP Launcher</h1>
        <span className="mut small">v{__APP_VERSION__}</span>
      </div>

      <div className={relayOk ? "card relay ok" : "card relay ko"}>
        <div className="row between">
          <div>
            <label>Connexion du mod au serveur</label>
            {status === null ? <span className="mut">…</span> : relayOk
              ? <span>🟢 Active — le mod GRNFR CMP peut se connecter.</span>
              : <span>🔴 Inactive : {status.relay_error}</span>}
          </div>
          {status && relayOk && <span className="mut small">{status.requests} requête(s){status.errors ? `, ${status.errors} erreur(s)` : ""}</span>}
        </div>
        {status?.last && <p className="mut small">Dernière : {status.last}</p>}
      </div>

      <div className="card">
        <label>Lancer le jeu</label>
        <ModeChooser value={settings.mode} onChange={mode => save({ ...settings, mode })} beammpFound={!!settings.beammp_exe} />
        <button className="btn launch-btn" onClick={launch} disabled={launching}>
          {launching ? "Lancement…" : settings.mode === "beammp" ? "Lancer BeamNG avec BeamMP" : "Lancer BeamNG"}
        </button>
        {launchMsg && <p className={launchMsg.ok ? "good" : "warn"}>{launchMsg.text}</p>}
      </div>

      <div className={mod && !mod.up_to_date ? "card update-banner" : "card"}>
        <div className="row between">
          <div>
            <label>Mod GRNFR CMP</label>
            {modBusy && !mod ? <span className="mut">Vérification…</span> : mod ? (
              <span>
                Installé : <b>{mod.installed ? "v" + mod.installed : mod.files.length ? mod.files.length + " copie(s) à nettoyer" : "aucun"}</b>
                {" · "}Dernière : <b>{mod.latest ? "v" + mod.latest.version : "aucune publiée"}</b>
                {mod.up_to_date && <span className="good"> · à jour</span>}
              </span>
            ) : null}
          </div>
          <div className="row">
            {mod && !mod.up_to_date && mod.latest && <button className="btn" onClick={installMod} disabled={modBusy}>{modBusy ? "Installation…" : "Mettre à jour le mod"}</button>}
            <button className="btn dim" onClick={checkMod} disabled={modBusy}>Vérifier</button>
          </div>
        </div>
        {mod && <p className="mut small">Dossier : {mod.mods_dir}</p>}
        {mod?.latest?.notes && !mod.up_to_date && <p className="mut small">{mod.latest.notes}</p>}
        {modError && <p className="err">{modError}</p>}
      </div>

      <UpdateCard />

      <div className="card">
        <div className="row between">
          <label>Réglages</label>
          <div className="row">
            <button className="btn dim sm" onClick={onWizard}>Relancer l'assistant</button>
            <button className="btn dim sm" onClick={() => { setDraft(settings); setShowSettings(!showSettings) }}>{showSettings ? "Fermer" : "Modifier"}</button>
          </div>
        </div>
        {showSettings && (
          <>
            <PathField label="BeamNG.drive (exécutable)" value={draft.beamng_exe} onChange={v => setDraft({ ...draft, beamng_exe: v })} optional />
            <PathField label="BeamMP Launcher" value={draft.beammp_exe} onChange={v => setDraft({ ...draft, beammp_exe: v })} optional />
            <PathField label="Dossier mods de BeamNG" value={draft.mods_dir} onChange={v => setDraft({ ...draft, mods_dir: v })} directory />
            <label className="row">
              <input type="checkbox" checked={draft.auto_update_mod} onChange={e => setDraft({ ...draft, auto_update_mod: e.target.checked })} />
              Mettre à jour le mod automatiquement avant chaque lancement
            </label>
            <div className="row between"><span /><button className="btn" onClick={() => save(draft).then(() => setShowSettings(false))}>Enregistrer</button></div>
          </>
        )}
      </div>
    </div>
  )
}
