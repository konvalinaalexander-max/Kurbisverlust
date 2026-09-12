import type { ReactNode } from 'react'
import { useSprache } from '../sprache/SprachProvider'
import { ZHaken, ZZurueck } from './Zeichen'

/**
 * Der Rahmen für „eine Frage je Bildschirm": Zurück-Knopf, Schrittanzeige,
 * die Frage gross, darunter der Inhalt, unten der eine Hauptknopf.
 *
 * Nach NN/g (Wizards): feste Reihenfolge, der aktuelle Schritt sichtbar, die
 * Länge des Wegs von Anfang an bekannt — sonst weiss niemand, wie lange das
 * noch dauert, und bricht ab. Der Inhalt kommt bei jedem Schritt von unten
 * ins Bild (`wechsel`, mit der Nummer als Schlüssel), das Alte ist weg.
 */
export function Schritt({ nummer, von, frage, warum, zurueck, weiter, weiterText, weiterMoeglich = true,
                          children }: {
  nummer: number; von: number; frage: string; warum?: string
  zurueck?: () => void
  weiter?: () => void; weiterText?: string; weiterMoeglich?: boolean
  children: ReactNode
}) {
  const { t } = useSprache()
  return (
    <>
      <div className="schritt-kopf">
        {zurueck
          ? <button type="button" className="zurueck" onClick={zurueck} aria-label={t('zurueck')}><ZZurueck size={20} />{t('zurueck')}</button>
          : <span />}
        <span className="stand">{t('schritt')} {nummer} {t('von')} {von}</span>
      </div>
      <div className="schritt-punkte" aria-hidden="true">
        {Array.from({ length: von }, (_, i) => <span key={i} className={i < nummer ? 'getan' : ''} />)}
      </div>
      <div className="wechsel" key={nummer}>
        <h1 className="frage">{frage}</h1>
        {warum && <p className="leise frage-warum">{warum}</p>}
        {children}
      </div>
      {weiter && (
        <div className="haupt-unten">
          <button type="button" className="haupt" onClick={weiter} disabled={!weiterMoeglich}>
            {weiterText ?? t('weiter')}
          </button>
        </div>
      )}
    </>
  )
}

/** Eine Wahl-Karte: Bild, Name, ein Satz. Ganze Fläche tippbar; gewählt trägt ein Häkchen. */
export function Wahl({ bild, name, erkl, gewaehlt, onClick, id }: {
  bild?: ReactNode; name: string; erkl?: string; gewaehlt?: boolean; onClick: () => void; id?: string
}) {
  return (
    <button type="button" id={id} className={gewaehlt ? 'gewaehlt' : ''} onClick={onClick} aria-pressed={gewaehlt}>
      {bild && <span className="bild" aria-hidden="true">{bild}</span>}
      <span className="text">
        <span>{name}</span>
        {erkl && <span className="erkl">{erkl}</span>}
      </span>
      {gewaehlt && <span className="haken" aria-hidden="true"><ZHaken size={15} /></span>}
    </button>
  )
}

/** Das kurze „gespeichert" nach jedem Speichern — sichtbar, ohne zu stören. */
export function Bestaetigt({ text }: { text: string | null }) {
  if (!text) return null
  return <div className="bestaetigt" role="status"><ZHaken size={16} />{text}</div>
}
