import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText } from '../lib/db'
import { pruefsumme } from '../lib/csv'
import { xlsxLesen, type Blatt } from '../lib/xlsx'
import {
  abgleichen, artikelSchluessel, befund, chargeAufloeser, istKuerbis, kopfLesen,
  lieferungenBauen, quelleVorschlag, zaehltAlsKuerbis, zeilenLesen, zeilenSchluessel,
  type Abgleich, type ArtikelBefund, type AusgangZeile, type Befund, type Bekannt, type ChargeKurz, type Lieferung,
} from '../lib/warenausgang'
import { datum, kg, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Kennzahl, Marke } from '../components/Bausteine'

/**
 * Warenausgang einlesen: die Excel-Auswertung „Abgleich Rückverfolgbarkeit"
 * aus dem Perigon, je Firma eine Datei, immer die ganze. Der Browser liest
 * und rechnet, zeigt den Befund und den Abgleich mit dem, was schon da ist —
 * und schreibt erst, wenn der Betriebsleiter es sagt. Dann alles in einem
 * Aufruf (ausgang_uebernehmen, 0055), damit die Datenbank nachprüfen kann,
 * dass jedes Kilo genau einmal angekommen ist (v_ausgang_pruef).
 *
 * Entscheidungen (docs/WARENAUSGANG_BEFUND.md, 7. September): nur Zeilen ab
 * dem 1. Juli 2026, Journal L (interne Umbuchung) nicht, alles andere zählt.
 */

/** Ab wann der Warenausgang zählt — die Saison 2026 (Sommer). Ältere Zeilen
 *  stehen im Befund, werden aber weder gespeichert noch zu Lieferungen. */
export const ZEITRAUM_AB = '2026-07-01'
/** Journal L: interne Umbuchung zwischen den Firmen, keine Ware, die die Halle verlässt. */
export const JOURNAL_INTERN = 'L'

interface Quelle { code: string; name: string; dateiname_muster: string | null }
interface Lage { quelle: string; name: string; zeilen: number; von: string | null; bis: string | null; zuletzt_geladen: string | null; lieferungen: number; kg: number; artikel_offen: number }
interface Bestaetigung { ist_kuerbis: boolean; sorte: string | null }
interface Pruefzeile { pos_id: number; datum: string; artikel: string; kunde: string; kg_datei: number; kg_lieferung: number; abweichung_kg: number }

interface Datei {
  name: string
  summe: string
  blatt: Blatt | null
  /** Der Code der Quelle — bestätigt der Betriebsleiter; '' heisst: noch offen. */
  quelle: string
  quelleName: string
  status: 'bereit' | 'laeuft' | 'fertig' | 'fehler'
  meldung?: string
  ergebnis?: { zeilen_neu: number; zeilen_geaendert: number; lieferungen_neu: number; lieferungen_aktualisiert: number; uebergangen: { extern_id: string; kg?: number; datum?: string; kunde?: string; grund: string }[] }
  pruef?: Pruefzeile[]
}

/** Alle Zeilen einer Tabelle, seitenweise — PostgREST gibt sonst höchstens tausend. */
async function alleZeilen<T>(tabelle: string, spalten: string, filter?: [string, string]): Promise<T[]> {
  const seite = 1000
  const alle: T[] = []
  for (let von = 0; ; von += seite) {
    let q = supabase.from(tabelle).select(spalten).range(von, von + seite - 1)
    if (filter) q = q.eq(filter[0], filter[1])
    const { data, error } = await q
    if (error) throw error
    const rows = (data ?? []) as T[]
    alle.push(...rows)
    if (rows.length < seite) return alle
  }
}

/** Die Zeilen einer Datei, gelesen mit dem bestätigten Quellen-Code. */
function zeilenVon(blatt: Blatt | null, quelle: string): AusgangZeile[] {
  if (!blatt || !quelle) return []
  return zeilenLesen(blatt, quelle).zeilen
}

export default function AusgangImport({ nachUebernahme }: { nachUebernahme: () => void }) {
  const [quellen, setQuellen] = useState<Quelle[]>([])
  const [lage, setLage] = useState<Lage[]>([])
  const [bestaetigt, setBestaetigt] = useState<Map<string, Bestaetigung>>(new Map())
  const [chargen, setChargen] = useState<ChargeKurz[]>([])
  const [sorten, setSorten] = useState<string[]>([])
  const [bekannt, setBekannt] = useState<Map<string, Bekannt[]>>(new Map())
  const [dateien, setDateien] = useState<Datei[]>([])
  const [fehler, setFehler] = useState<string | null>(null)
  const [liest, setLiest] = useState(false)

  const laden = useCallback(async () => {
    try {
      const [q, l, a, c, s] = await Promise.all([
        supabase.from('ausgang_quelle').select('code, name, dateiname_muster').eq('aktiv', true).order('name'),
        supabase.from('v_ausgang_lage').select('*'),
        alleZeilen<{ artikel_id: string; artikel: string; ist_kuerbis: boolean; sorte: string | null }>('ausgang_artikel', 'artikel_id, artikel, ist_kuerbis, sorte'),
        supabase.from('charge').select('nr, sorte, perigon_nr').order('nr'),
        supabase.from('sorte_kaliber').select('sorte').order('sorte'),
      ])
      if (q.error) throw q.error
      setQuellen((q.data ?? []) as Quelle[])
      setLage((l.data ?? []) as Lage[])
      setBestaetigt(new Map(a.map(x => [artikelSchluessel(x), { ist_kuerbis: x.ist_kuerbis, sorte: x.sorte }])))
      setChargen((c.data ?? []) as ChargeKurz[])
      setSorten(((s.data ?? []) as { sorte: string }[]).map(x => x.sorte))
    } catch (f) { setFehler(fehlerText(f)) }
  }, [])
  useEffect(() => { void laden() }, [laden])

  /** Was von dieser Quelle schon da ist — nur die Schlüssel und Fingerabdrücke. */
  async function bekanntLaden(quelle: string) {
    if (!quelle || bekannt.has(quelle)) return
    try {
      const rows = await alleZeilen<{ quelle: string; pos_id: number; charge_extern: string; lauf_nr: number; fingerabdruck: string }>(
        'ausgang_zeile', 'quelle, pos_id, charge_extern, lauf_nr, fingerabdruck', ['quelle', quelle])
      setBekannt(m => new Map(m).set(quelle, rows.map(r => ({
        schluessel: `${r.quelle}|${r.pos_id}|${r.charge_extern}|${r.lauf_nr}`, fingerabdruck: r.fingerabdruck }))))
    } catch (f) { setFehler(fehlerText(f)) }
  }

  async function dateienWaehlen(liste: FileList | null) {
    if (!liste) return
    setFehler(null); setLiest(true)
    const neu: Datei[] = []
    try {
      for (const datei of Array.from(liste)) {
        const puffer = await datei.arrayBuffer()
        const blaetter = await xlsxLesen(puffer)
        // Das erste Blatt, dessen Kopf die erwarteten Spalten trägt.
        const blatt = blaetter.find(b => kopfLesen(b.zeilen) !== null) ?? null
        const vorschlag = quelleVorschlag(datei.name)
        const nameKlein = datei.name.toLowerCase()
        const erkannt = quellen.find(q => q.dateiname_muster && nameKlein.includes(q.dateiname_muster.toLowerCase()))
          ?? quellen.find(q => q.code === vorschlag)
        const d: Datei = {
          name: datei.name, summe: await pruefsumme(puffer), blatt,
          quelle: erkannt?.code ?? vorschlag, quelleName: erkannt?.name ?? vorschlag,
          status: blatt ? 'bereit' : 'fehler',
          meldung: blatt ? undefined : 'Kein Blatt mit den erwarteten Spalten (Lieferdatum, Artikel, Menge, Charge, AufPosId …). Ist das die Auswertung „Abgleich Rückverfolgbarkeit"?',
        }
        neu.push(d)
        void bekanntLaden(d.quelle)
      }
    } catch (f) {
      setFehler(`Datei konnte nicht gelesen werden: ${fehlerText(f)}`)
    } finally { setLiest(false) }
    setDateien(d => [...d, ...neu])
  }

  function aendern(i: number, teil: Partial<Datei>) {
    setDateien(ds => ds.map((d, j) => (j === i ? { ...d, ...teil } : d)))
  }

  async function artikelSetzen(a: ArtikelBefund, istKuerbisWert: boolean, sorte: string | null) {
    const { error } = await supabase.from('ausgang_artikel')
      .upsert({ artikel_id: a.artikel_id, artikel: a.artikel, ist_kuerbis: istKuerbisWert, sorte: istKuerbisWert ? sorte : null },
              { onConflict: 'artikel_id,artikel' })
    if (error) { setFehler(fehlerText(error)); return }
    setBestaetigt(m => new Map(m).set(a.schluessel, { ist_kuerbis: istKuerbisWert, sorte: istKuerbisWert ? sorte : null }))
  }

  return (
    <>
      <Karte titel="Warenausgang einlesen">
        <p className="leise">
          Die Excel-Auswertung <strong>„Abgleich Rückverfolgbarkeit"</strong> aus dem Perigon — je Firma eine Datei,
          immer die ganze. Die App erkennt selbst, was sie schon hat, was neu ist und was im Perigon nachträglich
          korrigiert wurde, und schreibt daraus Lieferungen. Gezählt wird ab dem {datum(ZEITRAUM_AB)} (Saison 2026);
          Journal {JOURNAL_INTERN} (interne Umbuchung) bleibt draussen. Gerechnet wird im Browser, geschrieben erst auf Knopfdruck.
        </p>
        {lage.length > 0 && (
          <div className="rollbar" style={{ marginBottom: '.75rem' }}>
            <table>
              <thead><tr><th>Firma</th><th className="zahl">Zeilen</th><th>Zeitraum</th><th>Zuletzt geladen</th><th className="zahl">Lieferungen</th><th className="zahl">Masse</th><th className="zahl">Artikel offen</th></tr></thead>
              <tbody>{lage.map(l => (
                <tr key={l.quelle}>
                  <td>{l.name}</td><td className="zahl">{zahl(l.zeilen)}</td>
                  <td>{l.von ? `${datum(l.von)} – ${datum(l.bis)}` : '—'}</td>
                  <td>{l.zuletzt_geladen ? zeitpunkt(l.zuletzt_geladen) : '—'}</td>
                  <td className="zahl">{zahl(l.lieferungen)}</td><td className="zahl">{tonnen(l.kg)}</td>
                  <td className="zahl">{l.artikel_offen > 0 ? <Marke art="warnung">{l.artikel_offen}</Marke> : '0'}</td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
        <label className="knopf haupt" id="ausgang-dateien">
          {liest ? 'Liest …' : 'Excel-Dateien wählen …'}
          <input type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" multiple hidden
                 disabled={liest} onChange={e => { void dateienWaehlen(e.target.files); e.target.value = '' }} />
        </label>
        <p className="leise" style={{ margin: '.6rem 0 0' }}>
          Beide Dateien auf einmal geht; eine allein geht auch. Jede wird einzeln geprüft und einzeln übernommen.
        </p>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </Karte>

      {dateien.map((d, i) => (
        <DateiKarte key={`${d.summe}-${i}`} d={d} quellen={quellen} bekannt={bekannt.get(d.quelle) ?? null}
                    bestaetigt={bestaetigt} chargen={chargen} sorten={sorten}
                    quelleSetzen={(code, name) => { aendern(i, { quelle: code, quelleName: name }); void bekanntLaden(code) }}
                    artikelSetzen={artikelSetzen}
                    uebernehmen={async (zeilen, lieferungen, bf, ab) => {
                      aendern(i, { status: 'laeuft', meldung: undefined })
                      try {
                        const { data, error } = await supabase.rpc('ausgang_uebernehmen', {
                          p_quelle: d.quelle, p_quelle_name: d.quelleName,
                          p_datei: { dateiname: d.name, pruefsumme: d.summe, n_zeilen: bf.zeilen, n_kuerbis: bf.kuerbiszeilen,
                                     n_neu: ab.neu.length, n_geaendert: ab.geaendert.length, n_unveraendert: ab.unveraendert,
                                     von_datum: bf.von || null, bis_datum: bf.bis || null },
                          p_zeilen: zeilen.map(z => ({ ...z, quelle: undefined, zeile_nr: undefined })),
                          p_lieferungen: lieferungen,
                        })
                        if (error) throw error
                        const pruef = await supabase.from('v_ausgang_pruef').select('pos_id, datum, artikel, kunde, kg_datei, kg_lieferung, abweichung_kg').eq('quelle', d.quelle)
                        aendern(i, { status: 'fertig', ergebnis: data as Datei['ergebnis'], pruef: (pruef.data ?? []) as Pruefzeile[] })
                        setBekannt(m => { const n = new Map(m); n.delete(d.quelle); return n })
                        await laden(); nachUebernahme()
                      } catch (f) {
                        aendern(i, { status: 'fehler', meldung: fehlerText(f) })
                      }
                    }} />
      ))}
    </>
  )
}

function DateiKarte({ d, quellen, bekannt, bestaetigt, chargen, sorten, quelleSetzen, artikelSetzen, uebernehmen }: {
  d: Datei; quellen: Quelle[]; bekannt: Bekannt[] | null
  bestaetigt: Map<string, Bestaetigung>; chargen: ChargeKurz[]; sorten: string[]
  quelleSetzen: (code: string, name: string) => void
  artikelSetzen: (a: ArtikelBefund, istKuerbis: boolean, sorte: string | null) => Promise<void>
  uebernehmen: (zeilen: AusgangZeile[], lieferungen: Lieferung[], bf: Befund, ab: Abgleich) => Promise<void>
}) {
  const [neueQuelle, setNeueQuelle] = useState(false)
  const bestaetigtKarte = useMemo(() => new Map([...bestaetigt.entries()].map(([k, v]) => [k, v.ist_kuerbis])), [bestaetigt])

  // Die Zeilen mit dem bestätigten Code lesen; dann die Regeln des Betriebs anwenden.
  const alle = useMemo(() => zeilenVon(d.blatt, d.quelle), [d.blatt, d.quelle])
  const imZeitraum = useMemo(() => alle.filter(z => z.datum >= ZEITRAUM_AB), [alle])
  const relevant = useMemo(() => imZeitraum.filter(z => z.journal !== JOURNAL_INTERN), [imZeitraum])
  const intern = imZeitraum.length - relevant.length
  const kuerbis = useMemo(() => relevant.filter(z => zaehltAlsKuerbis(istKuerbis(z, bestaetigtKarte))), [relevant, bestaetigtKarte])
  const bf = useMemo(() => befund(relevant, bestaetigtKarte), [relevant, bestaetigtKarte])
  const ab = useMemo(() => bekannt ? abgleichen(kuerbis, bekannt) : null, [kuerbis, bekannt])

  // Die Sorte je Artikel: bestätigt, sonst aus den Zeilen mit eigener Charge beobachtet.
  const vorschlagSorte = useMemo(() => {
    const loese = chargeAufloeser(chargen)
    const sorteVonCharge = new Map(chargen.map(c => [c.nr, c.sorte]))
    const zaehler = new Map<string, Map<string, number>>()
    for (const z of kuerbis) {
      const nr = z.charge_extern ? loese(z.charge_extern) : null
      const sorte = nr === null ? null : sorteVonCharge.get(nr)
      if (!sorte) continue
      const k = artikelSchluessel(z)
      const m = zaehler.get(k) ?? new Map<string, number>()
      m.set(sorte, (m.get(sorte) ?? 0) + 1); zaehler.set(k, m)
    }
    return new Map([...zaehler.entries()].map(([k, m]) => {
      const [sorte, n] = [...m.entries()].sort((a, b) => b[1] - a[1])[0]
      return [k, { sorte, n }]
    }))
  }, [kuerbis, chargen])
  const sorteVon = (z: { artikel_id: string; artikel: string }) =>
    bestaetigt.get(artikelSchluessel(z))?.sorte ?? vorschlagSorte.get(artikelSchluessel(z))?.sorte ?? null
  const gebaut = useMemo(() => lieferungenBauen(kuerbis, chargeAufloeser(chargen, sorteVon), sorteVon),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [kuerbis, chargen, bestaetigt, vorschlagSorte])
  const ohneZuordnung = gebaut.lieferungen.filter(l => l.charge_nr === null && l.sorte === null)

  const offen = bf.artikel.filter(a => a.urteil.startsWith('vorschlag') && a.kg > 0)
  const status = d.status
  const zeilenZumSpeichern = kuerbis

  return (
    <Karte titel={d.name}
           aktion={<Marke art={status === 'fertig' ? 'fertig' : status === 'fehler' ? 'warnung' : 'offen'}>
             {{ bereit: 'geprüft, noch nicht übernommen', laeuft: 'übernimmt …', fertig: 'übernommen', fehler: 'Fehler' }[status]}
           </Marke>}>
      {d.meldung && status === 'fehler' && <Hinweis art="warnung">{d.meldung}</Hinweis>}
      {d.blatt && (
        <>
          {/* 1. Herkunft */}
          <div className="spalten" style={{ alignItems: 'end' }}>
            <div className="feld" style={{ margin: 0 }}>
              <label htmlFor={`q-${d.summe}`}>Firma (Quelle der Datei)</label>
              {neueQuelle || (quellen.length === 0) ? (
                <input id={`q-${d.summe}`} value={d.quelleName} disabled={status !== 'bereit'}
                       onChange={e => quelleSetzen(quelleVorschlag(e.target.value || 'neu'), e.target.value)} />
              ) : (
                <select id={`q-${d.summe}`} value={quellen.some(q => q.code === d.quelle) ? d.quelle : '__neu__'} disabled={status !== 'bereit'}
                        onChange={e => {
                          if (e.target.value === '__neu__') { setNeueQuelle(true); return }
                          const q = quellen.find(x => x.code === e.target.value)!
                          quelleSetzen(q.code, q.name)
                        }}>
                  {quellen.map(q => <option key={q.code} value={q.code}>{q.name}</option>)}
                  <option value="__neu__">{quellen.some(q => q.code === d.quelle) ? 'andere Firma …' : `neu: ${d.quelleName}`}</option>
                </select>
              )}
            </div>
            <p className="leise" style={{ margin: 0 }}>
              Die eine Angabe, die die App nicht raten darf: Positionsnummern sind nur innerhalb einer Firma eindeutig.
              {!quellen.some(q => q.code === d.quelle) && <> Wird beim Übernehmen als neue Firma <strong>{d.quelleName}</strong> angelegt.</>}
            </p>
          </div>

          {/* 2. Befund */}
          <h3 style={{ margin: '1rem 0 .4rem' }}>Was in der Datei steht</h3>
          <div className="spalten">
            <Kennzahl titel="Zeilen" wert={zahl(alle.length)} unter={<>{zahl(alle.length - imZeitraum.length)} vor dem {datum(ZEITRAUM_AB)}{intern > 0 && <> · {zahl(intern)} Journal {JOURNAL_INTERN}</>}</>} />
            <Kennzahl titel="Kürbiszeilen" wert={zahl(bf.kuerbiszeilen)} unter={`${zahl(bf.positionen)} Lieferscheinpositionen`} />
            <Kennzahl titel="Zeitraum" wert={bf.von ? `${datum(bf.von)} – ${datum(bf.bis)}` : '—'} unter="Lieferdatum" />
            <Kennzahl titel="Masse" wert={tonnen(bf.kg_position)}
                      unter={`${tonnen(gebaut.lieferungen.filter(l => l.charge_nr !== null).reduce((s, l) => s + l.kg, 0))} einer Charge zugeordnet · ${tonnen(gebaut.lieferungen.filter(l => l.charge_nr === null).reduce((s, l) => s + l.kg, 0))} ohne Chargenbezug`} />
          </div>
          {bf.chargen.length > 0 && (
            <p className="leise" style={{ margin: '.5rem 0 0' }}>
              {bf.chargen.length} Chargen genannt, die grössten: {bf.chargen.slice(0, 6).map(c => `${c.charge_extern} (${kg(c.kg, 0)})`).join(', ')}
              {bf.chargen.length > 6 && ' …'}
            </p>
          )}

          {/* 3. Abgleich */}
          <h3 style={{ margin: '1rem 0 .4rem' }}>Bis wo hat es die Daten schon?</h3>
          {ab === null ? <p className="leise">Vergleicht mit dem, was von dieser Firma schon eingelesen ist …</p> : (
            <div className="spalten">
              <Kennzahl titel="Neu" wert={zahl(ab.neu.length)} unter="Zeilen, die noch nicht da sind" />
              <Kennzahl titel="Geändert" wert={zahl(ab.geaendert.length)} unter="im Perigon nachträglich korrigiert" />
              <Kennzahl titel="Unverändert" wert={zahl(ab.unveraendert)} unter="schon da, gleich geblieben" />
              <Kennzahl titel="Verschwunden" wert={zahl(ab.verschwunden.length)} unter="in der Datenbank, nicht mehr in der Datei — bleibt stehen" />
            </div>
          )}
          {ab !== null && ab.neu.length === 0 && ab.geaendert.length === 0 && status === 'bereit' && (
            <Hinweis art="gut">Nichts Neues: alles aus dieser Datei ist schon da. Übernehmen ist erlaubt, aber ändert nichts.</Hinweis>
          )}

          {/* 4. Artikel klären */}
          {offen.length > 0 && (
            <>
              <h3 style={{ margin: '1rem 0 .4rem' }}>Artikel, die noch niemand bestätigt hat ({offen.length})</h3>
              <p className="leise" style={{ margin: '0 0 .4rem' }}>
                Die App schlägt vor, ob ein Artikel Kürbis ist, und welche Sorte — aus den Zeilen, die eine eigene Chargennummer
                tragen. Bestätigt gilt, vorgeschlagen zählt vorläufig. Einmal je Artikel, danach nur bei neuen.
              </p>
              <div className="rollbar"><table>
                <thead><tr><th>Artikel</th><th className="zahl">Zeilen</th><th className="zahl">Masse</th><th>Vorschlag</th><th>Sorte</th><th></th></tr></thead>
                <tbody>{offen.map(a => {
                  const vs = vorschlagSorte.get(a.schluessel)
                  return (
                    <ArtikelZeile key={a.schluessel} a={a} sorten={sorten} vorschlag={vs ?? null} sperren={status !== 'bereit'}
                                  setzen={(ja, sorte) => void artikelSetzen(a, ja, sorte)} />
                  )
                })}</tbody>
              </table></div>
            </>
          )}

          {/* 5. Was nicht übernommen wird */}
          {(gebaut.ruecknahmen.length > 0 || ohneZuordnung.length > 0) && (
            <>
              <h3 style={{ margin: '1rem 0 .4rem' }}>Was nicht übernommen wird</h3>
              {gebaut.ruecknahmen.length > 0 && (
                <p className="leise" style={{ margin: '0 0 .4rem' }}>
                  <strong>{gebaut.ruecknahmen.length} Rücknahmen</strong> (negative Menge — Gutschrift, zurückgekommene Ware):{' '}
                  {gebaut.ruecknahmen.map(r => `${datum(r.datum)} ${r.kunde} ${kg(r.kg, 0)}`).join('; ')}. Sie stehen hier, damit sie
                  niemand übersieht; die Bilanz kennt keine negative Lieferung — bei Bedarf von Hand als Wareneingang behandeln.
                </p>
              )}
              {ohneZuordnung.length > 0 && (
                <p className="leise" style={{ margin: 0 }}>
                  <strong>{ohneZuordnung.length} Lieferungen ohne Charge und ohne Sorte</strong> ({kg(ohneZuordnung.reduce((s, l) => s + l.kg, 0), 0)}):
                  der Artikel ist noch keiner Sorte zugeordnet. Oben bestätigen, dann kommen sie mit.
                </p>
              )}
            </>
          )}

          {/* 6. Übernehmen */}
          {status === 'bereit' && (
            <button className="haupt" id={`uebernehmen-${d.summe.slice(0, 8)}`} style={{ width: '100%', marginTop: '1rem' }}
                    disabled={ab === null || !d.quelle} onClick={() => void uebernehmen(zeilenZumSpeichern, gebaut.lieferungen, bf, ab!)}>
              {ab === null ? 'Vergleicht …' : `Übernehmen: ${zahl(zeilenZumSpeichern.length)} Kürbiszeilen, ${zahl(gebaut.lieferungen.length - ohneZuordnung.length)} Lieferungen (${tonnen(gebaut.lieferungen.filter(l => !(l.charge_nr === null && l.sorte === null)).reduce((s, l) => s + l.kg, 0))})`}
            </button>
          )}
          {status === 'laeuft' && <Hinweis art="info">Übernimmt … einen Moment.</Hinweis>}
          {status === 'fertig' && d.ergebnis && (
            <>
              <Hinweis art="gut">
                Übernommen: {d.ergebnis.zeilen_neu} Zeilen neu, {d.ergebnis.zeilen_geaendert} schon bekannt (davon Korrekturen übernommen) ·{' '}
                {d.ergebnis.lieferungen_neu} Lieferungen neu, {d.ergebnis.lieferungen_aktualisiert} aktualisiert.
                {d.ergebnis.uebergangen.length > 0 && <> {d.ergebnis.uebergangen.length} nicht übernommen (unten).</>}
              </Hinweis>
              {d.pruef && d.pruef.length === 0 && <Hinweis art="gut">Probe bestanden: jedes Kilo dieser Firma steht genau einmal als Lieferung.</Hinweis>}
              {d.pruef && d.pruef.length > 0 && (
                <Hinweis art="warnung">
                  Probe: {d.pruef.length} Positionen, deren Lieferungen nicht die Masse der Datei ergeben — meist Artikel ohne Sorte.
                  {' '}{d.pruef.slice(0, 5).map(p => `${datum(p.datum)} ${p.artikel} ${p.kunde}: Datei ${kg(p.kg_datei, 0)}, Lieferung ${kg(p.kg_lieferung, 0)}`).join('; ')}
                </Hinweis>
              )}
              {d.ergebnis.uebergangen.length > 0 && (
                <p className="leise" style={{ margin: '.4rem 0 0' }}>
                  Nicht übernommen: {d.ergebnis.uebergangen.slice(0, 8).map(u => `${u.datum ? datum(u.datum) + ' ' : ''}${u.kunde ?? ''} ${u.kg != null ? kg(u.kg, 0) : ''} — ${u.grund}`).join('; ')}
                  {d.ergebnis.uebergangen.length > 8 && ' …'}
                </p>
              )}
            </>
          )}
        </>
      )}
      {ab !== null && ab.verschwunden.length > 0 && status === 'bereit' && (
        <p className="leise" style={{ margin: '.5rem 0 0', fontSize: '.8rem' }}>
          Verschwunden (in der Datenbank, nicht mehr in der Datei): {ab.verschwunden.slice(0, 5).map(s => s.split('|').slice(1, 3).join(' / ')).join(', ')}
          {ab.verschwunden.length > 5 && ' …'}. Gelöscht wird nichts — wer eine Lieferung streichen will, tut es unten von Hand.
        </p>
      )}
    </Karte>
  )
}

function ArtikelZeile({ a, sorten, vorschlag, sperren, setzen }: {
  a: ArtikelBefund; sorten: string[]; vorschlag: { sorte: string; n: number } | null; sperren: boolean
  setzen: (ja: boolean, sorte: string | null) => void
}) {
  const [sorte, setSorte] = useState(vorschlag?.sorte ?? '')
  return (
    <tr>
      <td>{a.artikel} <span className="leise">· {a.artikel_id}</span></td>
      <td className="zahl">{zahl(a.zeilen)}</td>
      <td className="zahl">{kg(a.kg, 0)}</td>
      <td>{a.urteil === 'vorschlag_ja' ? 'Kürbis' : 'kein Kürbis'}</td>
      <td>
        <select value={sorte} onChange={e => setSorte(e.target.value)} disabled={sperren} style={{ minHeight: 36 }}>
          <option value="">— Sorte —</option>
          {sorten.map(s => <option key={s}>{s}</option>)}
        </select>
        {vorschlag && <div className="leise" style={{ fontSize: '.78rem' }}>beobachtet: {vorschlag.sorte} ({vorschlag.n} Zeilen mit Charge)</div>}
      </td>
      <td style={{ whiteSpace: 'nowrap' }}>
        <button className="klein" disabled={sperren} onClick={() => setzen(true, sorte || null)}>Kürbis</button>{' '}
        <button className="klein" disabled={sperren} onClick={() => setzen(false, null)}>kein Kürbis</button>
      </td>
    </tr>
  )
}

/** Für Prüfstand und Tests: der Schlüssel einer Zeile, wie ihn die Datenbank bildet. */
export { zeilenSchluessel }
