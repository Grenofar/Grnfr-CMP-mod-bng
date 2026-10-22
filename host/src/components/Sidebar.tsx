export type Tab = "overview" | "players" | "settings"

const ITEMS: { id: Tab; label: string; icon: string }[] = [
  { id: "overview", label: "Tableau de bord", icon: "M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z" },
  { id: "players", label: "Joueurs", icon: "M16 11c1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3 1.34 3 3 3zM8 11c1.66 0 3-1.34 3-3S9.66 5 8 5 5 6.34 5 8s1.34 3 3 3zM8 13c-2.33 0-7 1.17-7 3.5V19h9.5v-2.5C10.5 14.17 10.33 13 8 13zM16 13c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z" },
  { id: "settings", label: "Paramètres", icon: "M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.5.5 0 00.12-.64l-1.92-3.32a.5.5 0 00-.61-.22l-2.39.96a7.03 7.03 0 00-1.62-.94L14.4 2.81A.5.5 0 0013.9 2.4h-3.8a.5.5 0 00-.5.41l-.36 2.52a7.03 7.03 0 00-1.62.94l-2.39-.96a.5.5 0 00-.61.22L2.7 8.85a.5.5 0 00.12.64l2.03 1.58c-.05.3-.08.63-.08.94s.02.64.07.94L2.8 14.53a.5.5 0 00-.12.64l1.92 3.32c.14.24.42.33.61.22l2.39-.96c.5.38 1.04.7 1.62.94l.36 2.52c.05.26.27.41.5.41h3.8c.24 0 .46-.15.5-.41l.36-2.52a7.03 7.03 0 001.62-.94l2.39.96c.24.1.47 0 .61-.22l1.92-3.32a.5.5 0 00-.12-.64l-2.03-1.59zM12 15.5A3.5 3.5 0 1112 8.5a3.5 3.5 0 010 7z" },
]

export default function Sidebar({ tab, onTab, running }: { tab: Tab; onTab: (t: Tab) => void; running: boolean }) {
  return (
    <nav className="sidebar">
      <div className="sidebar-brand">
        <span className="dot" />
        <span>GRNFR Host CMP</span>
      </div>

      <div className={running ? "sidebar-status on" : "sidebar-status off"}>
        {running ? "🟢 En ligne" : "🔴 Arrêté"}
      </div>

      <div className="sidebar-items">
        {ITEMS.map(it => (
          <button key={it.id} className={tab === it.id ? "sidebar-item on" : "sidebar-item"} onClick={() => onTab(it.id)}>
            <svg viewBox="0 0 24 24"><path d={it.icon} /></svg>
            <span>{it.label}</span>
          </button>
        ))}
      </div>

      <div className="sidebar-footer mut">v{__APP_VERSION__}</div>
    </nav>
  )
}
