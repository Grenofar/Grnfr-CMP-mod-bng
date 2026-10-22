import { useEffect, useState } from "react"
import { api, Settings } from "./api"
import Wizard from "./components/Wizard"
import Home from "./components/Home"

export default function App() {
  const [settings, setSettings] = useState<Settings | null>(null)
  const [wizard, setWizard] = useState(false)
  const [error, setError] = useState("")

  useEffect(() => {
    api.settings().then(s => { setSettings(s); setWizard(!s.wizard_done) }).catch(e => setError(String(e)))
  }, [])

  if (!settings) {
    return <div className="loading">{error ? <p className="err">{error}</p> : <p className="mut">Chargement…</p>}</div>
  }
  return (
    <main className="single">
      <div className="main-content">
        {wizard
          ? <Wizard initial={settings} onDone={s => { setSettings(s); setWizard(false) }} />
          : <Home settings={settings} onSettings={setSettings} onWizard={() => setWizard(true)} />}
      </div>
    </main>
  )
}
