/**
 * Einen Perigon-Fall mitverfolgen (0126). Der Betrieb, 24. Oktober: „dass man
 * sie anklicken kann und sie dann auch irgendwie mitverfolgen — das wird für
 * uns als Betrieb immer wichtiger."
 *
 * Zwei Spuren je Fall: was der Betriebsleiter festhält (perigon_vermerk —
 * offen, in Abklärung, erledigt, kein Fehler, mit Notiz, wer, wann; nur
 * anhängen, nie ändern) und was die App von selbst weiss (perigon_fall_spur —
 * seit wann sie ihn sieht, seit wann nicht mehr). Beides steht unter jedem
 * Fall; der Reiter Perigon lädt den Stand aller Fälle einmal (useVerlauf) und
 * reicht ihn über VerlaufKontext auch ins Fenster weiter, das als Portal
 * ausserhalb der Seite hängt.
 */
import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { datum, zeitpunkt } from '../lib/format'
import { useAuth } from '../auth/AuthProvider'
import { Segmente } from '../components/Bausteine'
import type { PerigonVerlauf, VermerkStand } from './daten'
import { STAND_FOLGE, STAND_NAME } from './perigon'
import { fallFortschritt, fallStand } from './faelle'

export interface VerlaufWissen {
  verlauf: Map<string, PerigonVerlauf>
  laedt: boolean
  fehler: string | null
  neuLaden: () => Promise<void>
}
export const VerlaufKontext = createContext<VerlaufWissen | null>(null)

/** Der Stand aller Fälle (v_perigon_verlauf) — frisch geladen, und nach jedem Vermerk wieder. */
export function useVerlauf(start: PerigonVerlauf[] = []): VerlaufWissen {
  const [verlauf, setVerlauf] = useState(() => new Map(start.map(v => [v.schluessel, v])))
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  const neuLaden = useCallback(async () => {
    setLaedt(true)
    const r = await supabase.from('v_perigon_verlauf').select('*')
    setLaedt(false)
    if (r.error) { setFehler(fehlerText(r.error)); return }
    setFehler(null)
    setVerlauf(new Map(((r.data ?? []) as PerigonVerlauf[]).map(v => [v.schluessel, v])))
  }, [])
  useEffect(() => { void neuLaden() }, [neuLaden])
  return { verlauf, laedt, fehler, neuLaden }
}

export function StandMarke({ stand }: { stand: VermerkStand }) {
  return <span className={`stand-marke st-${stand}`}>{STAND_NAME[stand]}</span>
}

interface Eintrag { id: number; schluessel: string; stand: VermerkStand; notiz: string | null; ts: string; wer: string | null; profil?: { name: string } | null }

/** Runde BF: was in einem Zug für mehrere Teile vermerkt wurde, steht einmal da — mit der Zahl der Teile. */
function zusammen(eintraege: Eintrag[]): (Eintrag & { teile: number })[] {
  const m = new Map<string, Eintrag & { teile: number }>()
  for (const e of eintraege) {
    const k = `${e.ts}|${e.stand}|${e.notiz ?? ''}|${e.wer ?? ''}`
    const da = m.get(k)
    if (da) da.teile += 1; else m.set(k, { ...e, teile: 1 })
  }
  return [...m.values()]
}

/**
 * Unter einem Fall: wie es steht, seit wann die App ihn sieht, alles, was
 * dazu vermerkt ist — und für den Betriebsleiter das Feld, etwas dazu
 * festzuhalten.
 *
 * Runde BF: ein Fall kann mehrere Teile haben (alles zu einer Charge, alle
 * Positionen einer Art). Dann steht der Stand des Ganzen da (erledigt erst,
 * wenn alle Teile es sind), und ein Vermerk gilt für jeden Teil — in einem
 * Zug, mit derselben Notiz.
 */
export function FallVerfolgen({ schluessel, schnappschuss, kompakt = false, titel = 'Mitverfolgen' }: {
  schluessel: string | string[]
  schnappschuss: Record<string, unknown> | ((schluessel: string) => Record<string, unknown>)
  /** unter einer Sache in einer Liste: das Feld erst auf Knopfdruck */
  kompakt?: boolean
  titel?: string
}) {
  const { istAdmin } = useAuth()
  const wissen = useContext(VerlaufKontext)
  const teile = Array.isArray(schluessel) ? schluessel : [schluessel]
  const kennung = teile.join('|')
  const vs = teile.map(s => wissen?.verlauf.get(s)).filter((v): v is PerigonVerlauf => v != null)
  const stand = fallStand({ teile }, wissen?.verlauf ?? new Map())
  const fortschritt = fallFortschritt({ teile }, wissen?.verlauf ?? new Map())
  const erst = vs.map(v => v.erst_gesehen).filter((x): x is string => !!x).sort()[0] ?? null
  const weg = vs.length > 0 && vs.length === teile.length && vs.every(v => v.weg_seit) ? vs.map(v => v.weg_seit!).sort().reverse()[0] : null
  const [eintraege, setEintraege] = useState<Eintrag[] | null>(null)
  const [wahl, setWahl] = useState<VermerkStand>(stand === 'offen' ? 'in_abklaerung' : stand)
  const [notiz, setNotiz] = useState('')
  const [laeuft, setLaeuft] = useState(false)
  const [meldung, setMeldung] = useState<string | null>(null)
  const [nr, setNr] = useState(0)
  const [formAuf, setFormAuf] = useState(!kompakt)

  useEffect(() => {
    let lebt = true
    setEintraege(null)
    void (async () => {
      const r = await supabase.from('perigon_vermerk').select('id, schluessel, stand, notiz, ts, wer, profil(name)')
        .in('schluessel', teile).order('ts', { ascending: false }).order('id', { ascending: false })
      if (!lebt) return
      setEintraege(r.error ? [] : ((r.data ?? []) as unknown as Eintrag[]))
    })()
    return () => { lebt = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kennung, nr])

  const vermerken = async () => {
    setLaeuft(true); setMeldung(null)
    const zeilen = teile.map(s => ({ schluessel: s, stand: wahl, notiz: notiz.trim() || null,
                                     schnappschuss: typeof schnappschuss === 'function' ? schnappschuss(s) : schnappschuss }))
    const r = await supabase.from('perigon_vermerk').insert(zeilen.length === 1 ? zeilen[0] : zeilen)
    setLaeuft(false)
    if (r.error) { setMeldung(fehlerText(r.error)); return }
    setNotiz('')
    setMeldung(`Vermerkt: ${STAND_NAME[wahl]}${teile.length > 1 ? ` — für alle ${teile.length} Teile` : ''}.`)
    setNr(n => n + 1)
    await wissen?.neuLaden()
  }

  const liste = eintraege === null ? null : teile.length > 1 ? zusammen(eintraege) : eintraege.map(e => ({ ...e, teile: 1 }))
  return (
    <section className="verfolgen" id="fall-verfolgen" aria-label={titel}>
      <h3>{titel}</h3>
      <p className="verfolgen-stand">
        Stand: <StandMarke stand={stand} />
        {teile.length > 1 && fortschritt.fertig > 0 && fortschritt.fertig < fortschritt.von && <span className="leise"> · {fortschritt.fertig} von {fortschritt.von} Teilen erledigt</span>}
        {erst && <span className="leise"> · die App sieht den Fall seit {datum(erst)}</span>}
        {weg && <span className="leise"> · nicht mehr in den Daten seit {zeitpunkt(weg)}</span>}
        {!erst && !weg && <span className="leise"> · gemerkt wird er beim nächsten Rechnen</span>}
      </p>
      {liste === null ? null : liste.length === 0
        ? <p className="leise verfolgen-leer">Noch nichts vermerkt.</p>
        : (
          <ol className="verfolgen-liste">
            {liste.map(e => (
              <li key={e.id}>
                <span className="nowrap leise">{zeitpunkt(e.ts)}</span>
                {e.profil?.name && <span className="leise"> · {e.profil.name}</span>}
                {' '}<StandMarke stand={e.stand} />
                {teile.length > 1 && <span className="leise"> {e.teile === teile.length ? '(alle Teile)' : `(${e.teile} von ${teile.length} Teilen)`}</span>}
                {e.notiz && <span className="verfolgen-notiz"> {e.notiz}</span>}
              </li>
            ))}
          </ol>
        )}
      {istAdmin && !formAuf && (
        <button type="button" className="klein" onClick={() => setFormAuf(true)}>Vermerken …</button>
      )}
      {istAdmin ? formAuf && (
        <form className="verfolgen-form" onSubmit={e => { e.preventDefault(); void vermerken() }}>
          <Segmente<VermerkStand> wahl={wahl} setzen={setWahl} id={`stand-${teile[0]}`}
                                  teile={STAND_FOLGE.map(s => [s, STAND_NAME[s], `stand-${s}`] as const)} />
          <textarea value={notiz} onChange={e => setNotiz(e.target.value)} maxLength={2000} rows={2}
                    aria-label="Notiz zum Fall"
                    placeholder="Was ist besprochen, was entschieden? Wer wurde gefragt, was hat Perigon geändert …" />
          <button type="submit" className="knopf haupt klein" id="fall-vermerken" disabled={laeuft}>
            {laeuft ? 'Vermerkt …' : teile.length > 1 ? `Für alle ${teile.length} vermerken` : 'Vermerken'}</button>
          {meldung && <span className="hilfe">{meldung}</span>}
        </form>
      ) : <p className="leise">Vermerken kann der Betriebsleiter.</p>}
    </section>
  )
}
