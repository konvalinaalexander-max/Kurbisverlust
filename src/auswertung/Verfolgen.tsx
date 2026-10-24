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

interface Eintrag { id: number; stand: VermerkStand; notiz: string | null; ts: string; wer: string | null; profil?: { name: string } | null }

/**
 * Unter einem Fall: wie es steht, seit wann die App ihn sieht, alles, was
 * dazu vermerkt ist — und für den Betriebsleiter das Feld, etwas dazu
 * festzuhalten.
 */
export function FallVerfolgen({ schluessel, schnappschuss, kompakt = false }: {
  schluessel: string; schnappschuss: Record<string, unknown>
  /** unter einer Sache in einer Liste: das Feld erst auf Knopfdruck */
  kompakt?: boolean
}) {
  const { istAdmin } = useAuth()
  const wissen = useContext(VerlaufKontext)
  const v = wissen?.verlauf.get(schluessel)
  const [eintraege, setEintraege] = useState<Eintrag[] | null>(null)
  const [wahl, setWahl] = useState<VermerkStand>(v?.stand === 'offen' || !v ? 'in_abklaerung' : v.stand)
  const [notiz, setNotiz] = useState('')
  const [laeuft, setLaeuft] = useState(false)
  const [meldung, setMeldung] = useState<string | null>(null)
  const [nr, setNr] = useState(0)
  const [formAuf, setFormAuf] = useState(!kompakt)

  useEffect(() => {
    let lebt = true
    void (async () => {
      const r = await supabase.from('perigon_vermerk').select('id, stand, notiz, ts, wer, profil(name)')
        .eq('schluessel', schluessel).order('ts', { ascending: false }).order('id', { ascending: false })
      if (!lebt) return
      setEintraege(r.error ? [] : ((r.data ?? []) as unknown as Eintrag[]))
    })()
    return () => { lebt = false }
  }, [schluessel, nr])

  const vermerken = async () => {
    setLaeuft(true); setMeldung(null)
    const r = await supabase.from('perigon_vermerk').insert({ schluessel, stand: wahl, notiz: notiz.trim() || null, schnappschuss })
    setLaeuft(false)
    if (r.error) { setMeldung(fehlerText(r.error)); return }
    setNotiz('')
    setMeldung(`Vermerkt: ${STAND_NAME[wahl]}.`)
    setNr(n => n + 1)
    await wissen?.neuLaden()
  }

  const stand = v?.stand ?? 'offen'
  return (
    <section className="verfolgen" id="fall-verfolgen" aria-label="Mitverfolgen">
      <h3>Mitverfolgen</h3>
      <p className="verfolgen-stand">
        Stand: <StandMarke stand={stand} />
        {v?.erst_gesehen && <span className="leise"> · die App sieht den Fall seit {datum(v.erst_gesehen)}</span>}
        {v?.weg_seit && <span className="leise"> · nicht mehr in den Daten seit {zeitpunkt(v.weg_seit)}</span>}
        {!v?.erst_gesehen && !v?.weg_seit && <span className="leise"> · gemerkt wird er beim nächsten Rechnen</span>}
      </p>
      {eintraege === null ? null : eintraege.length === 0
        ? <p className="leise verfolgen-leer">Noch nichts vermerkt.</p>
        : (
          <ol className="verfolgen-liste">
            {eintraege.map(e => (
              <li key={e.id}>
                <span className="nowrap leise">{zeitpunkt(e.ts)}</span>
                {e.profil?.name && <span className="leise"> · {e.profil.name}</span>}
                {' '}<StandMarke stand={e.stand} />
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
          <Segmente<VermerkStand> wahl={wahl} setzen={setWahl} id={`stand-${schluessel}`}
                                  teile={STAND_FOLGE.map(s => [s, STAND_NAME[s], `stand-${s}`] as const)} />
          <textarea value={notiz} onChange={e => setNotiz(e.target.value)} maxLength={2000} rows={2}
                    aria-label="Notiz zum Fall"
                    placeholder="Was ist geklärt? Wer wurde gefragt, was hat Perigon geändert, wann neu eingelesen …" />
          <button type="submit" className="knopf haupt klein" id="fall-vermerken" disabled={laeuft}>{laeuft ? 'Vermerkt …' : 'Vermerken'}</button>
          {meldung && <span className="hilfe">{meldung}</span>}
        </form>
      ) : <p className="leise">Vermerken kann der Betriebsleiter.</p>}
    </section>
  )
}
