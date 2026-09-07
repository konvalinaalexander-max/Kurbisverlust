import type { ReactNode } from 'react'

/**
 * Bilanzzeile: Zahl, Balken, Erklärung — die Zeilen der Karte „Geht die
 * Rechnung auf?" (Messungen). Das Kaskadenbild, das hier einmal stand, ist
 * mit dem Überblick der Runde E gegangen: die Hauptursachen stehen jetzt als
 * gestapelte Balken je Sorte, Schlag oder Charge (Stapelbalken.tsx).
 */
/** Eine Zeile der Bilanz: Zahl, Balken, Erklärung — untereinander lesbar. */
export function Bilanzzeile({ titel, kg, eingang, farbe, erklaerung }: {
  titel: string; kg: number; eingang: number; farbe: string; erklaerung?: ReactNode
}) {
  const anteil = eingang > 0 ? Math.max(kg, 0) / eingang : 0
  return (
    <div style={{ marginBottom: '.8rem' }}>
      <div className="reihe" style={{ justifyContent: 'space-between', gap: '.6rem', marginBottom: '.2rem' }}>
        <span style={{ fontSize: '.9rem', fontWeight: 560 }}>{titel}</span>
        <strong style={{ fontVariantNumeric: 'tabular-nums' }}>{(kg / 1000).toFixed(1)} t</strong>
      </div>
      <div style={{ background: 'var(--flaeche-2)', height: 10, borderRadius: 5 }}>
        <div style={{ width: `${Math.min(anteil * 100, 100)}%`, height: 10,
                      background: farbe, borderRadius: 5 }} />
      </div>
      {erklaerung && (
        <p className="leise" style={{ margin: '.25rem 0 0', fontSize: '.82rem' }}>{erklaerung}</p>
      )}
    </div>
  )
}
