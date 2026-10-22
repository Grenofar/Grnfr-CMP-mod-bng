// Petites notifications qui apparaissent en haut à droite quelle que soit la page affichée (contrairement aux
// cartes "mise à jour" de l'accueil, qu'il faut aller regarder) : nouvelle version du launcher ou du mod détectée.
// Se referment seules après un moment, ou au clic.
export interface ToastItem {
  id: number
  text: string
  actionLabel?: string
  onAction?: () => void
}

export default function ToastStack({ toasts, onDismiss }: { toasts: ToastItem[]; onDismiss: (id: number) => void }) {
  if (!toasts.length) return null
  return (
    <div className="toast-stack">
      {toasts.map(t => (
        <div key={t.id} className="toast">
          <span>{t.text}</span>
          <div className="row nowrap" style={{ gap: 6 }}>
            {t.actionLabel && (
              <button className="btn sm" onClick={() => { t.onAction?.(); onDismiss(t.id) }}>{t.actionLabel}</button>
            )}
            <button className="btn dim sm" onClick={() => onDismiss(t.id)}>✕</button>
          </div>
        </div>
      ))}
    </div>
  )
}
