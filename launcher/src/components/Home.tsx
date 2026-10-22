import { useEffect, useState } from "react"
import { api, ModStatus, Settings, Status } from "../api"
import ModeChooser from "./ModeChooser"

// Vérification de version du mod et notifications (toasts) : remontées dans App.tsx, pour qu'elles marchent même
// si la page Accueil n'est pas affichée. Ici, Home se contente d'afficher ce qu'on lui passe.
export default function Home({ settings, onSettings, mod, modError, modBusy, onCheckMod, onInstallMod }: {
  settings: Settings
  onSettings: (s: Settings) => void
  mod: ModStatus | null
  modError: string
  modBusy: boolean
  onCheckMod: () => void
  onInstallMod: () => void
}) {
  const [status, setStatus] = useState<Status | null>(null)
  const [launching, setLaunching] = useState(false)
  const [launchMsg, setLaunchMsg] = useState<{ ok: boolean; text: string } | null>(null)

  useEffect(() => {
    // 4 s plutôt que 2 : l'état du relais (requêtes/erreurs) ne change pas assez vite pour justifier le double
    // d'appels invoke() en arrière-plan.
    const poll = () => api.status().then(setStatus).catch(() => {})
    poll()
    const t = setInterval(poll, 4000)
    return () => clearInterval(t)
  }, [])

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
      onCheckMod()
    } catch (e) { setLaunchMsg({ ok: false, text: String(e) }) } finally { setLaunching(false) }
  }

  const relayOk = status?.relay_ok
  return (
    <div className="home">
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
            {mod && !mod.up_to_date && mod.latest && <button className="btn" onClick={onInstallMod} disabled={modBusy}>{modBusy ? "Installation…" : "Mettre à jour le mod"}</button>}
            <button className="btn dim" onClick={onCheckMod} disabled={modBusy}>Vérifier</button>
          </div>
        </div>
        {mod && <p className="mut small">Dossier : {mod.mods_dir}</p>}
        {mod?.latest?.notes && !mod.up_to_date && <p className="mut small">{mod.latest.notes}</p>}
        {modError && <p className="err">{modError}</p>}
      </div>

    </div>
  )
}
