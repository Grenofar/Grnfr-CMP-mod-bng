import { useEffect, useState } from "react"
import { api, Settings } from "../api"
import PathField from "./PathField"
import ModeChooser from "./ModeChooser"

// Assistant du premier lancement (ensuite tout se règle dans Paramètres) : 1. emplacements (détectés automatiquement),
// 2. façon de lancer le jeu, 3. récapitulatif. Rien n'est enregistré avant « Terminer ».
export default function Wizard({ initial, onDone }: { initial: Settings; onDone: (s: Settings) => void }) {
  const [step, setStep] = useState(0)
  const [s, setS] = useState<Settings>(initial)
  const [detecting, setDetecting] = useState(true)
  const [error, setError] = useState("")

  useEffect(() => {
    api.detect()
      .then(d => setS(cur => ({
        ...cur,
        beamng_exe: cur.beamng_exe || d.beamng,
        beammp_exe: cur.beammp_exe || d.beammp,
        mods_dir: cur.mods_dir || d.mods_dir,
        mode: cur.wizard_done ? cur.mode : d.beammp ? "beammp" : "steam",
      })))
      .catch(e => setError(String(e)))
      .finally(() => setDetecting(false))
  }, [])

  async function finish() {
    const done = { ...s, wizard_done: true }
    try { await api.saveSettings(done); onDone(done) } catch (e) { setError(String(e)) }
  }

  const steps = ["Emplacements", "Lancement", "Terminé"]
  return (
    <div className="wizard">
      <h1>GRNFR CMP Launcher</h1>
      <p className="mut">Le launcher permet au mod GRNFR CMP de se connecter au serveur (BeamNG 0.40 l'en empêche sinon),
        garde le mod à jour et lance le jeu. Laissez-le ouvert pendant que vous jouez.</p>
      <div className="steps">
        {steps.map((t, i) => <span key={t} className={i === step ? "step on" : i < step ? "step done" : "step"}>{i + 1}. {t}</span>)}
      </div>

      {step === 0 && (
        <div className="card">
          {detecting ? <p className="mut">Recherche de BeamNG et BeamMP sur ce PC…</p> : <p className="mut small">Détecté automatiquement — corrigez si besoin.</p>}
          <PathField label="BeamNG.drive (exécutable)" value={s.beamng_exe} onChange={v => setS({ ...s, beamng_exe: v })}
            help="Utile pour le lancement direct. Inutile si vous lancez par Steam." optional />
          <PathField label="BeamMP Launcher" value={s.beammp_exe} onChange={v => setS({ ...s, beammp_exe: v })}
            help="Seulement si vous jouez avec BeamMP." optional />
          <PathField label="Dossier mods de BeamNG" value={s.mods_dir} onChange={v => setS({ ...s, mods_dir: v })} directory
            help="Le mod GRNFR CMP y est installé et mis à jour automatiquement. Lancez BeamNG une fois s'il n'est pas trouvé." />
          <div className="row between"><span /><button className="btn" disabled={detecting} onClick={() => setStep(1)}>Suivant</button></div>
        </div>
      )}

      {step === 1 && (
        <div className="card">
          <p>Comment voulez-vous lancer BeamNG ?</p>
          <ModeChooser value={s.mode} onChange={mode => setS({ ...s, mode })} beammpFound={!!s.beammp_exe} />
          <label className="row">
            <input type="checkbox" checked={s.auto_update_mod} onChange={e => setS({ ...s, auto_update_mod: e.target.checked })} />
            Installer / mettre à jour le mod GRNFR CMP automatiquement avant chaque lancement
          </label>
          <div className="row between">
            <button className="btn dim" onClick={() => setStep(0)}>Retour</button>
            <button className="btn" onClick={() => setStep(2)}>Suivant</button>
          </div>
        </div>
      )}

      {step === 2 && (
        <div className="card">
          <p><b>Tout est prêt.</b></p>
          <ul className="mut small">
            <li>Lancement : {s.mode === "steam" ? "par Steam" : s.mode === "direct" ? "BeamNG direct" : "avec BeamMP"}</li>
            <li>Mod GRNFR CMP : {s.auto_update_mod ? "mis à jour automatiquement" : "mise à jour manuelle"}</li>
            <li>Dossier mods : {s.mods_dir || "non trouvé"}</li>
          </ul>
          <div className="row between">
            <button className="btn dim" onClick={() => setStep(1)}>Retour</button>
            <button className="btn" onClick={finish}>Terminer</button>
          </div>
        </div>
      )}
      {error && <p className="err">{error}</p>}
    </div>
  )
}
