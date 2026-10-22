import { ServerStatus } from "../api"

export type Selection = "overview" | "new" | string // string = un id de serveur

export default function Sidebar({ servers, selected, onSelect }: {
  servers: ServerStatus[]
  selected: Selection
  onSelect: (s: Selection) => void
}) {
  const anyRunning = servers.some(s => s.running)
  return (
    <nav className="sidebar">
      <div className="sidebar-brand">
        <span className="dot" />
        <span>GRNFR Host CMP</span>
      </div>

      <div className={anyRunning ? "sidebar-status on" : "sidebar-status off"}>
        {anyRunning ? `🟢 ${servers.filter(s => s.running).length} en ligne` : "🔴 Aucun serveur en ligne"}
      </div>

      <div className="sidebar-items">
        <button className={selected === "overview" ? "sidebar-item on" : "sidebar-item"} onClick={() => onSelect("overview")}>
          <svg viewBox="0 0 24 24"><path d="M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z" /></svg>
          <span>Tableau de bord</span>
        </button>

        {servers.length > 0 && <div className="sidebar-sep" />}
        {servers.map(s => (
          <button key={s.id} className={selected === s.id ? "sidebar-item on" : "sidebar-item"} onClick={() => onSelect(s.id)}>
            <span className={s.running ? "dot on" : "dot off"} style={{ marginLeft: 2, marginRight: 8 }} />
            <span className="sidebar-item-name">{s.name}</span>
          </button>
        ))}

        <div className="sidebar-sep" />
        <button className={selected === "new" ? "sidebar-item on" : "sidebar-item"} onClick={() => onSelect("new")}>
          <svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14" /></svg>
          <span>Nouveau serveur</span>
        </button>
      </div>

      <div className="sidebar-footer mut">v{__APP_VERSION__}</div>
    </nav>
  )
}
