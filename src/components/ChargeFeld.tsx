import { useSprache } from '../sprache/SprachProvider'
import { chargeText } from '../lib/db'
import type { Charge } from '../lib/typen'

/**
 * Chargennummer eintippen statt aus einer Liste wählen (AB-06) — das geht
 * schneller und ist mit hundert Chargen überhaupt erst bedienbar. Die
 * bekannten Chargen stehen als Vorschlag dahinter; getippt wird die Nummer.
 * Eine unbekannte Nummer wird sichtbar gemeldet, nicht still angelegt.
 *
 * Ein Baustein für beide Stellen, an denen eine Charge gefragt wird — neue
 * Arbeit und Lagerkontrolle. Vorher hatte die Kontrolle noch eine Liste, und
 * dieselbe Frage sah an zwei Orten verschieden aus.
 */
export function ChargeFeld({ id, chargen, wert, setzen, ohneLabel = false }: {
  id: string; chargen: Charge[]; wert: number | ''; setzen: (nr: number | '') => void
  /** Im Assistenten steht die Frage schon als Überschrift. */
  ohneLabel?: boolean
}) {
  const { t } = useSprache()
  const bekannt = wert !== '' && chargen.some(c => c.nr === wert)
  return (
    <div className="feld">
      {!ohneLabel && <label htmlFor={id}>{t('charge')}</label>}
      <input id={id} type="number" inputMode="numeric" list={`${id}-liste`}
             aria-label={ohneLabel ? t('charge') : undefined}
             value={wert} style={{ fontSize: ohneLabel ? '1.5rem' : '1.2rem' }} autoFocus={ohneLabel}
             placeholder={t('chargeTippen')}
             onChange={e => setzen(e.target.value === '' ? '' : Number(e.target.value))} />
      <datalist id={`${id}-liste`}>
        {chargen.map(c => <option key={c.nr} value={c.nr}>{chargeText(c)}</option>)}
      </datalist>
      {wert !== '' && !bekannt && (
        <p className="leise" style={{ marginTop: '.3rem', marginBottom: 0, color: 'var(--rot)' }}>
          {t('chargeUnbekannt')}
        </p>
      )}
      {bekannt && (
        <p className="leise" style={{ marginTop: '.3rem', marginBottom: 0 }}>
          {chargeText(chargen.find(c => c.nr === wert))}
        </p>
      )}
    </div>
  )
}
