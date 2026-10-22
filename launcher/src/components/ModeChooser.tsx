import { LaunchMode, MODES } from "../api"

export default function ModeChooser({ value, onChange, beammpFound }: {
  value: LaunchMode
  onChange: (m: LaunchMode) => void
  beammpFound: boolean
}) {
  return (
    <div className="modes">
      {MODES.map(m => (
        <button key={m.id} type="button" className={value === m.id ? "mode on" : "mode"} onClick={() => onChange(m.id)}>
          <b>{m.label}</b>
          <span className="mut small">{m.help}</span>
          {m.id === "beammp" && !beammpFound && <span className="warn small">BeamMP Launcher non trouvé : indiquez son emplacement.</span>}
        </button>
      ))}
    </div>
  )
}
