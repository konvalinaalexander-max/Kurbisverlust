/**
 * Reiter Perigon (0126) — wo Perigon etwas anderes sagt als Erntejournal und
 * Halle, Fall für Fall nachvollziehbar und mitverfolgt.
 *
 * Der Betrieb, 24. Oktober: „mach einen neuen Reiter und behandle dort die
 * Ungereimtheiten mit viel Detail, mit viel Rückverfolgbarkeit, so dass man
 * es nachvollziehen kann — was sind die Fehler —, dass man sie anklicken und
 * dann auch mitverfolgen kann … nicht nur die gerade genannten, sondern alle
 * Perigon-Auffälligkeiten, die bisher bei Artikel oben waren." Und: „alles,
 * was du im PDF hast, dort in den Reiter — das mit 1719 etc."
 *
 * Fünf Teile, wie der Bericht vom 23. Oktober:
 *  Übersicht    — was offen ist, was zu tun ist (nach dem Ort, an dem es
 *                 behoben wird), die Lage in Zahlen, je Art, die Dateien;
 *  Je Sorte     — Fall für Fall: alle Chargen einer Sorte mit dem Weg der
 *                 Ware (herein, Halle, hinaus, noch da), was nicht passt, die
 *                 Sachen mit Stand, Vorschlag und Was tun;
 *  Perigon-Zeilen — jede Position, die nicht stimmt, nach Art, mit Filter;
 *                 ein Klick zeigt die Zeile der Datei, die Rechnung und den
 *                 Verlauf des Falls;
 *  Verlauf      — was vermerkt ist, was nicht mehr in den Daten steht;
 *  So prüft die App — die Spalten, jede Prüfung, was die App bewusst nicht tut.
 */
import { Fragment, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Link, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { datum, kg, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Segmente } from '../components/Bausteine'
import { ZChevron, ZWarnung } from '../components/Zeichen'
import { useAuswertung, type Auswertung, type ChargeSpur, type PerigonBefund, type PerigonStand, type PerigonVerlauf, type VermerkStand } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { ART_NAME, spurText, ungereimtheiten, type Schwere, type Ungereimtheit } from '../auswertung/ungereimt'
import {
  ART_FOLGE, FILTER_LEER, PERIGON_ART, STAND_NAME, WO_NAME, aufgaben, betroffen, fallTitel, filtern, istOffen, jeSorte,
  lageInZahlen, nachArt, sacheWo, schnappschussText, spaltenZeichen, standVon, type Aufgabe, type Eintrag, type Filter, type SorteFall, type StandFilter,
} from '../auswertung/perigon'
import { Sache, sacheAnker } from '../auswertung/Ungereimtheiten'
import { OhneChargeListe } from '../auswertung/OhneCharge'
import { StandMarke, VerlaufKontext, useVerlauf } from '../auswertung/Verfolgen'
import { LieferungFenster } from '../betrieb/LieferungFenster'

type Teil = 'uebersicht' | 'sorten' | 'zeilen' | 'verlauf' | 'pruefung'
const TEILE: [Teil, string][] = [
  ['uebersicht', 'Übersicht'],
  ['sorten', 'Je Sorte'],
  ['zeilen', 'Perigon-Zeilen'],
  ['verlauf', 'Verlauf'],
  ['pruefung', 'So prüft die App'],
]

interface ChargeKurz { nr: number; sorte: string; schlag: string; perigon_nr: number | null }

export default function Perigon() {
  const { teil } = useParams()
  const navigate = useNavigate()
  const aktiv = (TEILE.find(([t]) => t === teil)?.[0] ?? 'uebersicht') as Teil
  const a = useAuswertung()
  const { daten, laedt, fehler, fortschritt } = a
  const wissen = useVerlauf()
  const [stand, setStand] = useState<PerigonStand[] | null>(null)
  const [chargen, setChargen] = useState<ChargeKurz[]>([])
  const [offen, setOffen] = useState<PerigonBefund | null>(null)

  useEffect(() => {
    let lebt = true
    void (async () => {
      const [s, c] = await Promise.all([
        supabase.from('v_perigon_stand').select('*').order('quelle'),
        supabase.from('charge').select('nr, sorte, schlag, perigon_nr').order('nr'),
      ])
      if (!lebt) return
      setStand(s.error ? [] : ((s.data ?? []) as PerigonStand[]))
      setChargen(c.error ? [] : ((c.data ?? []) as ChargeKurz[]))
    })()
    return () => { lebt = false }
  }, [])

  const kopf = daten
    ? <Reiterkopf titel="Perigon" stand={daten.stand} heute={daten.heute} neuRechnen={() => void a.neuRechnen()} laeuft={laedt}
                  zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
    : <div className="seitenkopf"><div><h1>Perigon</h1></div></div>
  if (laedt && !daten) return <>{kopf}<Rechnet fortschritt={fortschritt} /></>
  if (fehler) return <>{kopf}<Hinweis art="warnung">{fehler}</Hinweis></>
  if (!daten) return kopf
  if (!daten.vollstaendig) return <>{kopf}<Rechnet fortschritt={fortschritt} /></>

  return (
    <VerlaufKontext.Provider value={wissen}>
      {kopf}
      <Probleme liste={daten.probleme} />
      {wissen.fehler && <Hinweis art="warnung">Der Stand der Fälle liess sich nicht laden: {wissen.fehler}</Hinweis>}
      <Inhalt daten={daten} stand={stand} chargen={chargen} aktiv={aktiv} verlauf={wissen.verlauf}
              gehe={(t, q) => navigate(`/perigon/${t}${q ? `?${q}` : ''}`)} oeffnen={setOffen} />
      {offen && <LieferungFenster quelle={offen.quelle} posId={offen.pos_id} fall={offen} schliessen={() => setOffen(null)} />}
    </VerlaufKontext.Provider>
  )
}

function Inhalt({ daten, stand, chargen, aktiv, verlauf, gehe, oeffnen }: {
  daten: Auswertung; stand: PerigonStand[] | null; chargen: ChargeKurz[]; aktiv: Teil
  verlauf: Map<string, PerigonVerlauf>; gehe: (t: Teil, q?: string) => void; oeffnen: (f: PerigonBefund) => void
}) {
  // Die Sachen je Charge (v_ungereimtheit) — ohne die Perigon-Zeilen: die stehen hier je Position.
  const sachen = useMemo(() => ungereimtheiten(daten.ungereimt), [daten.ungereimt])
  const faelle = daten.perigon
  const spur = useMemo(() => new Map(daten.spur.map(s => [s.charge_nr, s])), [daten.spur])
  const sorten = useMemo(() => jeSorte(daten.spur, sachen, faelle, chargen), [daten.spur, sachen, faelle, chargen])
  const zahlen = useMemo(() => {
    const st = (s: string) => standVon(verlauf, s)
    const alle = [...faelle.map(f => ({ s: f.schluessel, schwere: f.schwere, kg: betroffen(f) })),
                  ...sachen.map(u => ({ s: u.schluessel, schwere: u.schwere, kg: u.kg }))]
    const offenAlle = alle.filter(x => istOffen(x.schwere, st(x.s)))
    return {
      offen: offenAlle.length, offenKg: offenAlle.reduce((a, x) => a + (x.kg ?? 0), 0), rot: offenAlle.filter(x => x.schwere === 'rot').length,
      abklaerung: alle.filter(x => st(x.s) === 'in_abklaerung').length,
      wartet: alle.filter(x => st(x.s) === 'erledigt').length,
      behoben: [...verlauf.values()].filter(v => v.weg_seit != null).length,
    }
  }, [faelle, sachen, verlauf])
  const bis = stand?.reduce<string | null>((m, s) => (s.bis && (!m || s.bis > m) ? s.bis : m), null) ?? null

  return (
    <>
      {/* Runde BA: die Frage des Reiters, die Antwort zuoberst. */}
      <section className="antwort perigon-antwort" id="perigon-antwort">
        <p className="perigon-frage">Wo sagt Perigon etwas anderes als Erntejournal und Halle — und was ist davon schon geklärt?</p>
        <div className="spalten">
          <Kennzahl titel="Offen" wert={zahl(zahlen.offen)} ton={zahlen.rot > 0 ? 'rot' : undefined}
                    unter={zahlen.offen > 0
                      ? <>betrifft {tonnen(zahlen.offenKg)}<Herkunft art="gerechnet" text="aus Datei und Lieferscheinen gemessen, „mehr verkauft als möglich“ mit dem gerechneten Verlust" />{zahlen.rot > 0 ? ` · ${zahlen.rot} davon gross (ab 500 kg)` : ''}</>
                      : 'nichts offen'} />
          <Kennzahl titel="In Abklärung" wert={zahl(zahlen.abklaerung)} unter="gemeldet, Antwort ausstehend" />
          <Kennzahl titel="Erledigt, noch in den Daten" wert={zahl(zahlen.wartet)} unter="verschwindet mit dem nächsten Einlesen" />
          <Kennzahl titel="Nicht mehr in den Daten" wert={zahl(zahlen.behoben)} unter="seit dem ersten Merken behoben" />
          <Kennzahl titel="Lieferscheine bis" wert={bis ? datum(bis) : '—'} unter={stand ? `${stand.length} ${stand.length === 1 ? 'Datei' : 'Dateien'} eingelesen` : ''} />
        </div>
      </section>
      <nav className="navleiste unter" aria-label="Perigon">
        {TEILE.map(([t, name]) => (
          <a key={t} href={`/perigon/${t}`} className={aktiv === t ? 'aktiv' : ''} id={`perigon-teil-${t}`}
             onClick={e => { e.preventDefault(); gehe(t) }}>
            {name}
            {t === 'sorten' && sorten.length > 0 && <span className="reiter-zahl">{sorten.length}</span>}
            {t === 'zeilen' && <span className="reiter-zahl">{faelle.filter(f => istOffen(f.schwere, standVon(verlauf, f.schluessel))).length}</span>}
          </a>
        ))}
      </nav>
      <div className="wechsel" key={aktiv}>
        {aktiv === 'uebersicht' && <Uebersicht daten={daten} faelle={faelle} sachen={sachen} stand={stand} verlauf={verlauf} gehe={gehe} oeffnen={oeffnen} />}
        {aktiv === 'sorten' && <JeSorte sorten={sorten} spur={spur} verlauf={verlauf} gehe={gehe} oeffnen={oeffnen} />}
        {aktiv === 'zeilen' && <Zeilen faelle={faelle} stand={stand} verlauf={verlauf} oeffnen={oeffnen} />}
        {aktiv === 'verlauf' && <Verlauf faelle={faelle} sachen={sachen} verlauf={verlauf} gehe={gehe} oeffnen={oeffnen} />}
        {aktiv === 'pruefung' && <SoPrueft />}
      </div>
    </>
  )
}

const RANG: Record<Schwere, number> = { rot: 0, gelb: 1, info: 2 }
const Punkt = ({ s }: { s: Schwere }) => <span className={`punkt s-${s}`} aria-hidden="true" />

/* ---------- Übersicht ---------------------------------------------------- */

function Uebersicht({ daten, faelle, sachen, stand, verlauf, gehe, oeffnen }: {
  daten: Auswertung; faelle: PerigonBefund[]; sachen: Ungereimtheit[]; stand: PerigonStand[] | null
  verlauf: Map<string, PerigonVerlauf>; gehe: (t: Teil, q?: string) => void; oeffnen: (f: PerigonBefund) => void
}) {
  const tun = useMemo(() => aufgaben(faelle, sachen, verlauf), [faelle, sachen, verlauf])
  const lage = useMemo(() => lageInZahlen(daten.spur, sachen), [daten.spur, sachen])
  const arten = useMemo(() => nachArt(faelle, verlauf), [faelle, verlauf])
  const jeCharge = useMemo(() => {
    const m = new Map<string, Ungereimtheit[]>()
    for (const u of sachen) m.set(u.art, [...(m.get(u.art) ?? []), u])
    return [...m.entries()].sort((a, b) => RANG[schwerste(a[1])] - RANG[schwerste(b[1])] || (summeKg(b[1]) - summeKg(a[1])))
  }, [sachen])
  const sorteVon = (u: Ungereimtheit) => u.sorte ?? daten.spur.find(s => s.charge_nr === u.charge_nr)?.sorte ?? ''
  const eintragOeffnen = (e: Eintrag) => {
    if (e.fall) oeffnen(e.fall)
    else if (e.sache) gehe('sorten', `sorte=${encodeURIComponent(sorteVon(e.sache))}#${sacheAnker(e.sache.schluessel)}`)
  }
  return (
    <>
      <Karte titel="Was zu tun ist — das Grösste zuerst" id="perigon-tun">
        {tun.length === 0 ? <p className="leise">Nichts offen. Was vermerkt ist, steht unter Verlauf.</p> : (
          <div className="perigon-tun">
            {tun.map(t => <AufgabeBlock key={t.wo} a={t} oeffnen={eintragOeffnen} mehr={() => t.wo === 'halle' || t.wo === 'journal' ? gehe('sorten') : gehe('zeilen')} />)}
          </div>
        )}
        <Erklaerung titel="Wie diese Liste entsteht">
          <p>Jeder offene Fall steht einmal, beim Ort, an dem er behoben wird: in Perigon (dann die Datei neu einlesen), in der Halle
          (nachzählen), im Erntejournal, im Chargenregister, bei der Firma — oder nirgends, weil die App es beim nächsten Rechnen selbst
          nachholt. Offen ist ein Fall, solange niemand „erledigt" oder „kein Fehler" vermerkt hat; was nur Auskunft ist (die App hat
          umgebucht, eine Nummer kommt von selbst), zählt nicht. Ein Klick auf einen Fall zeigt die Perigon-Zeile, eine Sache je Charge die Sorte.</p>
        </Erklaerung>
      </Karte>

      <Karte titel="Die Lage in Zahlen" id="perigon-lage">
        <div className="spalten">
          <Kennzahl titel="Herein · Erntejournal" wert={tonnen(lage.hereinKg)} unter={`${zahl(lage.chargenMitEingang)} Chargen · ${zahl(lage.hereinPaletten)} Paletten und Paloxe`} />
          <Kennzahl titel="Hinaus · Perigon" wert={tonnen(lage.hinausKg)} unter={`${zahl(lage.lieferscheine)} Lieferscheine auf ${zahl(lage.chargenMitLieferschein)} Chargen`} />
          <Kennzahl titel="Hinaus ohne Charge" wert={tonnen(lage.ohneChargeKg ?? 0)} unter="auf die Chargen der Sorte verteilt" />
          <Kennzahl titel="Laut App noch im Lager" wert={lage.nochPaletten == null ? '—' : `≈ ${zahl(lage.nochPaletten)} Paletten`} unter="gerechnet, nicht gezählt" />
        </div>
      </Karte>

      <Karte titel="Was in Perigon selbst schiefläuft — je Art" id="perigon-arten">
        {arten.length === 0 ? <p className="leise">In den eingelesenen Perigon-Zeilen fällt nichts auf.</p> : (
          <div className="rollbar">
            <table className="dicht perigon-arten-tabelle">
              <thead><tr><th>Art</th><th className="zahl">offen</th><th className="zahl">Fälle</th><th className="zahl">Masse in der Datei</th><th>behebt</th></tr></thead>
              <tbody>{arten.map(g => (
                <tr key={g.art} className="klickbar" onClick={() => gehe('zeilen', `art=${g.art}&stand=alle`)} title="die Fälle dieser Art zeigen">
                  <td><Punkt s={g.schwere} />{g.info.name}<span className="zelle-unter leise">{g.info.heisst}</span></td>
                  <td className="zahl">{zahl(g.offen)}</td><td className="zahl">{zahl(g.faelle.length)}</td>
                  <td className="zahl">{g.kg == null ? 'unbekannt' : kg(g.kg, 0)}</td>
                  <td><span className="wo-marke">{WO_NAME[g.info.wo].kurz}</span></td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
      </Karte>

      <Karte titel="Wo Perigon und Lager nicht zusammenpassen — je Charge" id="perigon-je-charge">
        <p className="leise oben-0">Die Kilo der Lieferscheine und des Journals sind gemessen; was bei „mehr verkauft als möglich" fehlt, ist mit dem
          gerechneten Verlust der Charge bestimmt.</p>
        {jeCharge.length === 0 ? <p className="leise">Jede Charge geht auf: was hinausging, passt zu dem, was hereinkam.</p> : (
          <div className="rollbar">
            <table className="dicht">
              <thead><tr><th>Art</th><th className="zahl">Stellen</th><th className="zahl">betrifft</th><th>Chargen</th><th>behebt</th></tr></thead>
              <tbody>{jeCharge.map(([art, liste]) => (
                <tr key={art} className="klickbar" onClick={() => gehe('sorten')} title="Fall für Fall je Sorte zeigen">
                  <td><Punkt s={schwerste(liste)} />{ART_NAME[art] ?? art}</td>
                  <td className="zahl">{zahl(liste.length)}</td>
                  <td className="zahl">{liste.some(u => u.kg != null) ? kg(summeKg(liste), 0) : '—'}</td>
                  <td>{[...new Set(liste.map(u => u.charge_nr ?? u.sorte).filter(Boolean))].slice(0, 8).join(', ')}</td>
                  <td><span className="wo-marke">{WO_NAME[sacheWo(liste[0])].kurz}</span></td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
      </Karte>

      <DateienKarte stand={stand} />
    </>
  )
}

const schwerste = (l: { schwere: Schwere }[]): Schwere => (l.some(x => x.schwere === 'rot') ? 'rot' : l.some(x => x.schwere === 'gelb') ? 'gelb' : 'info')
const summeKg = (l: { kg: number | null }[]) => l.reduce((a, x) => a + Math.abs(x.kg ?? 0), 0)

function AufgabeBlock({ a, oeffnen, mehr }: { a: Aufgabe; oeffnen: (e: Eintrag) => void; mehr: () => void }) {
  const ZEIGEN = 6
  return (
    <section className="perigon-aufgabe" id={`tun-${a.wo}`}>
      <h3>{WO_NAME[a.wo].lang} <span className="leise">· {a.eintraege.length} {a.eintraege.length === 1 ? 'Fall' : 'Fälle'}{a.kg ? ` · ${tonnen(a.kg)}` : ''}</span></h3>
      <ol>
        {a.eintraege.slice(0, ZEIGEN).map(e => (
          <li key={e.schluessel}>
            <button type="button" className="link" onClick={() => oeffnen(e)}><Punkt s={e.schwere} />{e.titel}</button>
            {e.kg != null && <span className="leise"> · {kg(e.kg, 0)}</span>}
          </li>
        ))}
      </ol>
      {a.eintraege.length > ZEIGEN && <button type="button" className="link" onClick={mehr}>… und {a.eintraege.length - ZEIGEN} weitere</button>}
    </section>
  )
}

function DateienKarte({ stand }: { stand: PerigonStand[] | null }) {
  if (stand === null) return null
  const ohneRoh = stand.reduce((a, s) => a + s.ohne_roh, 0)
  return (
    <Karte titel="Die Perigon-Dateien" id="perigon-dateien">
      {stand.length === 0 ? <p className="leise">Noch keine Perigon-Datei eingelesen — unter <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link>.</p> : (
        <div className="rollbar">
          <table className="dicht">
            <thead><tr><th>Firma</th><th className="zahl">Zeilen</th><th className="zahl">Positionen</th><th>Lieferscheine</th><th>zuletzt eingelesen</th>
              <th className="zahl">ohne Charge</th><th className="zahl">Fälle offen</th></tr></thead>
            <tbody>{stand.map(s => (
              <tr key={s.quelle}>
                <td>{s.name}</td><td className="zahl">{zahl(s.zeilen)}</td><td className="zahl">{zahl(s.positionen)}</td>
                <td className="nowrap">{s.von ? `${datum(s.von)} – ${datum(s.bis)}` : '—'}</td>
                <td>{s.zuletzt_geladen ? zeitpunkt(s.zuletzt_geladen) : '—'}{s.letzte_datei && <span className="zelle-unter leise">{s.letzte_datei}{s.letzte_bis ? `, bis ${datum(s.letzte_bis)}` : ''}</span>}</td>
                <td className="zahl">{tonnen(s.kg_ohne_charge ?? 0)}</td>
                <td className="zahl">{zahl(s.faelle)}</td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      )}
      {ohneRoh > 0 && (
        <Hinweis art="info">{zahl(ohneRoh)} {ohneRoh === 1 ? 'Position hat' : 'Positionen haben'} ihre ganze Zeile noch nicht in der App. Die Datei
          unter <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link> neu einlesen, dann zeigt jedes Fenster die Zeile wie im Excel.</Hinweis>
      )}
    </Karte>
  )
}

/* ---------- Je Sorte: Fall für Fall -------------------------------------- */

function JeSorte({ sorten, spur, verlauf, gehe, oeffnen }: {
  sorten: SorteFall[]; spur: Map<number, ChargeSpur>; verlauf: Map<string, PerigonVerlauf>
  gehe: (t: Teil, q?: string) => void; oeffnen: (f: PerigonBefund) => void
}) {
  const [such] = useSearchParams()
  const { hash } = useLocation()
  const ziel = such.get('sorte')
  // Aus der Übersicht oder dem Verlauf: zur Sorte, oder gleich zur Sache darin
  useEffect(() => {
    const anker = hash.slice(1) || (ziel ? `sorte-${slug(ziel)}` : '')
    if (!anker) return
    const t = window.setTimeout(() => document.getElementById(anker)?.scrollIntoView({ block: 'start', behavior: 'smooth' }), 80)
    return () => window.clearTimeout(t)
  }, [ziel, hash])
  if (sorten.length === 0) return <Karte><p className="leise">In keiner Sorte passt etwas nicht — Perigon und Lager gehen auf.</p></Karte>
  return (
    <>
      <p className="leise perigon-einleitung">Je Sorte, in der etwas nicht passt, alle ihre Chargen: was laut Erntejournal hereinkam, was in der Halle
        geschah, was laut Perigon hinausging und was laut App noch da ist. Erst das Bild über die ganze Sorte zeigt, wo zu viel unter einer
        Nummer hinausgeht und wo nie etwas hinausging. Darunter jede Sache mit Stand, Vorschlag und was zu tun ist. Das Schwerste zuerst.</p>
      {sorten.map(s => <SorteKarte key={s.sorte} s={s} spur={spur} verlauf={verlauf} hervor={ziel === s.sorte} gehe={gehe} oeffnen={oeffnen} />)}
    </>
  )
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-')

function SorteKarte({ s, spur, verlauf, hervor, gehe, oeffnen }: {
  s: SorteFall; spur: Map<number, ChargeSpur>; verlauf: Map<string, PerigonVerlauf>; hervor: boolean
  gehe: (t: Teil, q?: string) => void; oeffnen: (f: PerigonBefund) => void
}) {
  const [ohneAuf, setOhneAuf] = useState(false)
  const marken = (nr: number) => {
    const m: { text: string; s: Schwere }[] = []
    for (const u of s.sachen) {
      if (u.charge_nr !== nr && u.von_charge_nr !== nr) continue
      const name = u.art === 'ueberzaehlung' ? `${tonnen(u.kg)} zu viel` : u.art === 'vor_eingang' ? `vor dem Eingang ${tonnen(u.kg)}`
        : u.art === 'umgebucht' ? (u.charge_nr === nr ? 'Paletten hierher umgebucht' : 'Paletten weg umgebucht')
        : u.art === 'vorschlag' ? (u.charge_nr === nr ? 'Paletten wohl hierher' : 'Paletten wohl anderswo') : ART_NAME[u.art] ?? u.art
      m.push({ text: name, s: u.schwere })
    }
    if (s.nieGeliefert.includes(nr)) m.push({ text: 'nie ein Lieferschein', s: 'gelb' })
    const z = s.zeilen.filter(f => f.charge_nr === nr && f.schwere !== 'info')
    if (z.length) m.push({ text: `${z.length} Perigon-${z.length === 1 ? 'Zeile' : 'Zeilen'}`, s: schwerste(z) })
    return m
  }
  const ohne = s.sachen.find(u => u.art === 'ohne_charge')
  const offenZeilen = s.zeilen.filter(f => istOffen(f.schwere, standVon(verlauf, f.schluessel)))
  return (
    <Karte id={`sorte-${slug(s.sorte)}`} className={`sorte-fall s-${s.schwere}${hervor ? ' hervor' : ''}`}
           titel={<><Punkt s={s.schwere} />{s.sorte}{s.kg > 0 && <span className="leise"> · betrifft {tonnen(s.kg)}</span>}</>}>
      <p className="leise oben-0 sorte-herkunft">Herein und hinaus sind gemessen (Erntejournal, Lieferscheine); „zu viel" und „noch da" sind gerechnet — mit dem Verlust, den die App für die Charge annimmt.</p>
      {s.bild.length > 0 && <ul className="sorte-bild">{s.bild.map((b, i) => <li key={i}>{b}</li>)}</ul>}
      {s.aehnlich.map((h, i) => <p key={i} className="hinweis-zeile"><ZWarnung size={14} /> {h}</p>)}
      <div className="rollbar">
        <table className="spur-tabelle sorte-tabelle ohne-haftkopf">
          <caption>Der Weg der Ware, alle Chargen {s.sorte}</caption>
          <thead><tr><th scope="col">Charge</th><th scope="col">Herein · Erntejournal</th><th scope="col">In der Halle</th>
            <th scope="col">Hinaus · Perigon</th><th scope="col">Laut App noch da</th><th scope="col">Was nicht passt</th></tr></thead>
          <tbody>{s.chargen.map(c => {
            const t = spurText(c)
            const m = marken(c.charge_nr)
            const zelle = (titel: string, x: string[], leer = false) => (
              <td className={leer ? 'spur-leer' : undefined} data-titel={titel}><div>{x.map((y, i) => <div key={i} className={i === 0 ? undefined : 'leise'}>{y}</div>)}</div></td>)
            return (
              <tr key={c.charge_nr} className={m.length ? `mit-befund s-${schwerste(m.map(x => ({ schwere: x.s })))}` : undefined}>
                <th scope="row"><Link to={`/chargen?charge=${c.charge_nr}`} title="die Charge unter Chargen öffnen">{c.charge_nr}</Link>
                  <span className="zelle-unter leise">{c.schlag}</span></th>
                {zelle('Herein', t.herein, t.ohneEingang)}{zelle('In der Halle', t.bearbeitet)}{zelle('Hinaus', t.hinaus)}{zelle('Noch da', [t.noch])}
                <td data-titel="Was nicht passt">{m.length ? m.map((x, i) => <span key={i} className={`sorte-marke s-${x.s}`}>{x.text}</span>) : <span className="leise">—</span>}</td>
              </tr>
            )
          })}</tbody>
        </table>
      </div>
      {s.sachen.length > 0 && (
        <div className="sorte-sachen">
          <h3>Was es heisst und was zu tun ist</h3>
          {[...s.sachen].sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || (b.kg ?? 0) - (a.kg ?? 0))
            .map(u => <Sache key={u.schluessel} u={u} spur={spur} verfolgen ohneWeg />)}
        </div>
      )}
      <div className="ungereimt-aktion">
        {s.zeilen.length > 0 && <button type="button" className="klein" onClick={() => gehe('zeilen', `sorte=${encodeURIComponent(s.sorte)}&stand=alle`)}>
          {s.zeilen.length} Perigon-{s.zeilen.length === 1 ? 'Zeile' : 'Zeilen'} {s.sorte} zeigen{offenZeilen.length ? ` (${offenZeilen.length} offen)` : ''}</button>}
        {ohne && <button type="button" className="klein" aria-expanded={ohneAuf} onClick={() => setOhneAuf(x => !x)}>
          {ohneAuf ? 'Lieferscheine ohne Charge zu' : `${ohne.zeilen.length || ''} Lieferscheine ohne Charge zeigen`.replace(/^ /, '')}</button>}
        {s.zeilen.length === 0 && s.sachen.length === 0 && <span className="leise">—</span>}
      </div>
      {ohneAuf && <OhneChargeListe sorte={s.sorte} />}
      {s.zeilen.filter(f => f.schwere === 'rot').slice(0, 3).map(f => (
        <p key={f.schluessel} className="leise unten-0"><button type="button" className="link" onClick={() => oeffnen(f)}>{fallTitel(f)}</button></p>
      ))}
    </Karte>
  )
}

/* ---------- Perigon-Zeilen ----------------------------------------------- */

function Zeilen({ faelle, stand, verlauf, oeffnen }: {
  faelle: PerigonBefund[]; stand: PerigonStand[] | null; verlauf: Map<string, PerigonVerlauf>; oeffnen: (f: PerigonBefund) => void
}) {
  const [such, setSuch] = useSearchParams()
  const filter: Filter = {
    ...FILTER_LEER,
    art: such.get('art') ?? '', quelle: such.get('quelle') ?? '', sorte: such.get('sorte') ?? '', suche: such.get('suche') ?? '',
    stand: (['offen', 'abklaerung', 'erledigt', 'alle'].includes(such.get('stand') ?? '') ? such.get('stand') : 'offen') as StandFilter,
    charge: such.get('charge') ? Number(such.get('charge')) : null,
  }
  const setze = (k: string, v: string) => {
    const neu = new URLSearchParams(such)
    if (v) neu.set(k, v); else neu.delete(k)
    setSuch(neu, { replace: true })
  }
  const liste = useMemo(() => filtern(faelle, verlauf, filter),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [faelle, verlauf, filter.art, filter.quelle, filter.sorte, filter.suche, filter.stand, filter.charge])
  const gruppen = useMemo(() => nachArt(liste, verlauf), [liste, verlauf])
  const [zu, setZu] = useState<Set<string>>(new Set())
  const quellen = stand ?? []
  const sortenListe = [...new Set(faelle.map(f => f.sorte).filter((x): x is string => !!x))].sort((a, b) => a.localeCompare(b, 'de'))
  const zahlJeArt = (art: string) => faelle.filter(f => f.art === art).length
  return (
    <>
      <div className="perigon-filter" id="perigon-filter">
        <Segmente<StandFilter> wahl={filter.stand} setzen={v => setze('stand', v === 'offen' ? '' : v)} id="perigon-stand"
                               teile={[['offen', 'offen', 'filter-offen'], ['abklaerung', 'in Abklärung', 'filter-abklaerung'], ['erledigt', 'erledigt', 'filter-erledigt'], ['alle', 'alle', 'filter-alle']]} />
        <select aria-label="Art" value={filter.art} onChange={e => setze('art', e.target.value)}>
          <option value="">alle Arten</option>
          {ART_FOLGE.filter(a => zahlJeArt(a) > 0).map(a => <option key={a} value={a}>{PERIGON_ART[a].name} ({zahlJeArt(a)})</option>)}
        </select>
        {quellen.length > 1 && (
          <select aria-label="Firma" value={filter.quelle} onChange={e => setze('quelle', e.target.value)}>
            <option value="">alle Firmen</option>
            {quellen.map(q => <option key={q.quelle} value={q.quelle}>{q.name}</option>)}
          </select>
        )}
        <select aria-label="Sorte" value={filter.sorte} onChange={e => setze('sorte', e.target.value)}>
          <option value="">alle Sorten</option>
          {sortenListe.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
        <input type="search" aria-label="Suchen" placeholder="Charge, Kunde, Artikel, Position …" value={filter.suche} onChange={e => setze('suche', e.target.value)} />
        {filter.charge != null && <button type="button" className="klein" onClick={() => setze('charge', '')}>Charge {filter.charge} ✕</button>}
      </div>
      {gruppen.length === 0 && <Karte><p className="leise">Keine Fälle{filter.stand === 'offen' ? ' offen' : ''} mit dieser Wahl.{filter.stand === 'offen' ? ' „alle" zeigt auch, was erledigt ist.' : ''}</p></Karte>}
      {gruppen.map(g => {
        const auf = !zu.has(g.art)
        return (
          <section key={g.art} className={`perigon-art s-${g.schwere}`} id={`art-${g.art}`}>
            <button type="button" className="perigon-art-kopf" aria-expanded={auf}
                    onClick={() => setZu(z => { const n = new Set(z); if (n.has(g.art)) n.delete(g.art); else n.add(g.art); return n })}>
              <span className="chevron" aria-hidden="true" style={{ transform: auf ? 'rotate(90deg)' : undefined }}><ZChevron size={16} /></span>
              <Punkt s={g.schwere} />
              <strong>{g.info.name}</strong>
              <span className="leise"> · {g.faelle.length} {g.faelle.length === 1 ? 'Fall' : 'Fälle'}{g.kg != null ? ` · ${kg(g.kg, 0)}` : ''}</span>
              <span className="wo-marke">{WO_NAME[g.info.wo].kurz}</span>
            </button>
            {auf && (
              <div className="perigon-art-inhalt">
                <dl className="perigon-art-erklaerung">
                  <dt>Was das heisst</dt><dd>{g.info.heisst}</dd>
                  <dt>In der Datei</dt><dd>{g.info.datei}</dd>
                  <dt>Was die App daraus macht</dt><dd>{g.info.app}</dd>
                  <dt>Was tun</dt><dd>{g.info.tun}</dd>
                </dl>
                <div className="rollbar">
                  <table className="dicht umbruch perigon-zeilen-tabelle ohne-haftkopf">
                    <thead><tr><th>Geliefert</th><th>Position</th><th>Kunde</th><th>Artikel</th><th>Charge</th><th className="zahl">Masse in der Datei</th><th>Was nicht stimmt</th><th>Stand</th></tr></thead>
                    <tbody>{g.faelle.map(f => {
                      const v = verlauf.get(f.schluessel)
                      return (
                        <tr key={f.schluessel} className="klickbar" tabIndex={0} onClick={() => oeffnen(f)}
                            onKeyDown={e => { if (e.key === 'Enter') oeffnen(f) }} title="die Zeile der Perigon-Datei, die Rechnung und den Verlauf zeigen">
                          <td className="nowrap" data-titel="Geliefert">{datum(f.datum)}</td>
                          <td className="nowrap" data-titel="Position">{f.pos_id}<span className="zelle-unter leise">{quellen.find(q => q.quelle === f.quelle)?.name ?? f.quelle}</span></td>
                          <td data-titel="Kunde">{f.kunde ?? <span className="leise">—</span>}</td>
                          <td data-titel="Artikel">{f.artikel}{f.sorte && <span className="zelle-unter leise">{f.sorte}</span>}</td>
                          <td data-titel="Charge">{f.nummer ?? f.nummern ?? <span className="leise">keine</span>}{f.charge_nr != null && String(f.charge_nr) !== (f.nummer ?? f.nummern) && <span className="zelle-unter leise">→ {f.charge_nr}</span>}</td>
                          <td className="zahl" data-titel="Masse in der Datei">{f.kg == null ? 'unbekannt' : kg(betroffen(f), 0)}{f.kg_position != null && f.art !== 'menge_null' && f.art !== 'keine_nummer' && <span className="zelle-unter leise">von {kg(f.kg_position, 0)}</span>}</td>
                          <td className="perigon-satz" data-titel="Was nicht stimmt">{f.satz}</td>
                          <td data-titel="Stand"><StandMarke stand={v?.stand ?? 'offen'} />{v?.n_vermerke ? <span className="zelle-unter leise">{v.n_vermerke} {v.n_vermerke === 1 ? 'Vermerk' : 'Vermerke'}</span> : null}</td>
                        </tr>
                      )
                    })}</tbody>
                  </table>
                </div>
              </div>
            )}
          </section>
        )
      })}
    </>
  )
}

/* ---------- Verlauf ------------------------------------------------------ */

interface VermerkZeile { id: number; schluessel: string; stand: VermerkStand; notiz: string | null; ts: string; schnappschuss: Record<string, unknown> | null; profil?: { name: string } | null }

function Verlauf({ faelle, sachen, verlauf, gehe, oeffnen }: {
  faelle: PerigonBefund[]; sachen: Ungereimtheit[]; verlauf: Map<string, PerigonVerlauf>
  gehe: (t: Teil, q?: string) => void; oeffnen: (f: PerigonBefund) => void
}) {
  const [vermerke, setVermerke] = useState<VermerkZeile[] | null>(null)
  useEffect(() => {
    let lebt = true
    void (async () => {
      const r = await supabase.from('perigon_vermerk').select('id, schluessel, stand, notiz, ts, schnappschuss, profil(name)')
        .order('ts', { ascending: false }).order('id', { ascending: false }).limit(500)
      if (lebt) setVermerke(r.error ? [] : ((r.data ?? []) as unknown as VermerkZeile[]))
    })()
    return () => { lebt = false }
  }, [verlauf])
  const fallVon = new Map(faelle.map(f => [f.schluessel, f]))
  const sacheVon = new Map(sachen.map(u => [u.schluessel, u]))
  const titel = (schluessel: string, s: Record<string, unknown> | null): ReactNode => {
    const f = fallVon.get(schluessel)
    if (f) return <button type="button" className="link" onClick={() => oeffnen(f)}>{fallTitel(f)}</button>
    const u = sacheVon.get(schluessel)
    if (u) return <button type="button" className="link" onClick={() => gehe('sorten', `#${sacheAnker(u.schluessel)}`)}>{u.titel}</button>
    return <span>{schnappschussText(s ?? verlauf.get(schluessel)?.schnappschuss)} <span className="leise">(nicht mehr in den Daten)</span></span>
  }
  const weg = [...verlauf.values()].filter(v => v.weg_seit != null).sort((a, b) => (b.weg_seit ?? '').localeCompare(a.weg_seit ?? ''))
  const wartet = [...verlauf.values()].filter(v => v.stand === 'erledigt' && v.weg_seit == null && (fallVon.has(v.schluessel) || sacheVon.has(v.schluessel)))
  return (
    <>
      <Karte titel="Was vermerkt ist" id="perigon-vermerke">
        {vermerke === null ? null : vermerke.length === 0
          ? <p className="leise">Noch nichts vermerkt. Unter jedem Fall hält der Betriebsleiter fest, wie es steht — offen, in Abklärung, erledigt
              oder kein Fehler —, mit einer Notiz. Hier steht dann alles in der Folge, in der es geschah.</p>
          : (
            <div className="rollbar">
              <table className="dicht umbruch">
                <thead><tr><th>Wann</th><th>Wer</th><th>Stand</th><th>Notiz</th><th>Fall</th></tr></thead>
                <tbody>{vermerke.map(v => (
                  <tr key={v.id}>
                    <td className="nowrap">{zeitpunkt(v.ts)}</td><td>{v.profil?.name ?? '—'}</td><td><StandMarke stand={v.stand} /></td>
                    <td>{v.notiz ?? <span className="leise">—</span>}</td><td>{titel(v.schluessel, v.schnappschuss)}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}
      </Karte>
      {wartet.length > 0 && (
        <Karte titel="Erledigt vermerkt, aber noch in den Daten" id="perigon-wartet">
          <p className="leise oben-0">In Perigon berichtigt — die App sieht es erst, wenn die Datei neu eingelesen und neu gerechnet ist.</p>
          <ul>{wartet.map(v => <li key={v.schluessel}>{titel(v.schluessel, v.schnappschuss)}{v.vermerk_ts && <span className="leise"> · vermerkt {zeitpunkt(v.vermerk_ts)}</span>}</li>)}</ul>
        </Karte>
      )}
      <Karte titel="Nicht mehr in den Daten" id="perigon-weg">
        {weg.length === 0
          ? <p className="leise">Noch kein Fall verschwunden. Nach jedem Rechnen merkt sich die App, welche Fälle sie sieht; was danach nicht mehr da ist —
              weil Perigon berichtigt und die Datei neu eingelesen wurde —, steht hier, mit dem Tag, an dem sie es zuletzt sah.</p>
          : (
            <div className="rollbar">
              <table className="dicht umbruch">
                <thead><tr><th>Fall</th><th>zuerst gesehen</th><th>nicht mehr seit</th><th>Stand</th></tr></thead>
                <tbody>{weg.map(v => (
                  <tr key={v.schluessel}>
                    <td>{schnappschussText(v.schnappschuss)}{typeof v.schnappschuss?.satz === 'string' && <span className="zelle-unter leise">{v.schnappschuss.satz}</span>}</td>
                    <td className="nowrap">{v.erst_gesehen ? datum(v.erst_gesehen) : '—'}</td>
                    <td className="nowrap">{v.weg_seit ? zeitpunkt(v.weg_seit) : '—'}</td>
                    <td><StandMarke stand={v.stand} />{v.notiz && <span className="zelle-unter leise">{v.notiz}</span>}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}
      </Karte>
    </>
  )
}

/* ---------- So prüft die App --------------------------------------------- */

const SPALTEN_ERKLAERT: [string, string][] = [
  ['AuftragsLieferDatum', 'das Lieferdatum — gegen das Eingangsdatum der Charge im Erntejournal'],
  ['AuftragsLieferant', 'der Kunde'],
  ['AuftragsArtikel', 'der Artikel — daraus Artikelgruppe, Grösse und (ohne Preisgruppe) das Label'],
  ['AuftragsPrsGrpBez', 'die Preisgruppe: D… Demeter, K… und CH-K Knospe'],
  ['AuftragsArtikelMenge', 'die Menge der ganzen Position — auf jeder ihrer Zeilen dieselbe'],
  ['AufPosBatchQuantity Charge', 'die Menge, die diese Zeile ihrer Charge zuteilt'],
  ['AuftragsArtikelEinheit', 'die Einheit: kg oder Stück'],
  ['AuftragsChargeManuell', 'die Chargennummer — unsere vierstellige oder die sechsstellige Perigon-Nummer der Firma'],
  ['LiefProdAdrName', 'der Produzent — über ihn findet die App eine Charge, wenn die Nummer unbekannt ist'],
  ['LiefPrsGrpName', 'das Lieferlabel der Charge (D, K, CH-K)'],
  ['AufPosId', 'die Position — die Kennung, mit der man die Zeile in der Datei findet'],
  ['GewichtProArtikel', 'das Gewicht je Artikel; bei kg-Artikeln mit 0 ist die Menge das Kilo, bei Stück ohne Gewicht bleibt die Masse unbekannt'],
]

const SACHEN_ERKLAERT: [string, string][] = [
  ['ohne_eingang', 'Eine Charge hat Lieferscheine, aber im Erntejournal keine einzige Palette. Die App nennt die Chargen, von denen die Ware wohl kam (derselbe Artikel, noch Paletten da, höchstens die Hälfte verkauft).'],
  ['ueberzaehlung', 'Was unter einer Nummer hinausging, braucht mit dem gerechneten Verlust mehr Eingangsware, als hereinkam (ab 100 kg und 3 %). Auch hier: die Chargen, von denen es wohl kam, und was zu zählen ist.'],
  ['vor_eingang', 'Lieferscheine einer Charge, die älter sind als ihre erste Palette im Journal.'],
  ['ohne_charge', 'Lieferscheine ohne Charge, je Sorte: wie viel, und auf welche Chargen die App sie nach Menge verteilt.'],
  ['vorschlag', 'Die Zettel einer Arbeit passen aufs Kilo zu Paletten einer anderen Charge, aber der Beleg reicht nicht (weniger als 2 Zettel, unter 80 %, oder es geht um die Sorte): ein Vorschlag, nichts gebucht.'],
  ['umgebucht', 'Der Beleg reicht (mindestens 2 Zettel, 80 %, aufs Kilo, ±3 Tage): die Paletten zählen bei der Charge der Arbeit, mit Grund, zurücknehmbar; im Journal bleibt die alte Charge stehen.'],
  ['nachgeordnet', 'Eine unbekannte Nummer, über den Produzenten (Spalte X) eindeutig einer Charge zugeordnet — bei jedem Rechnen neu, bis die Nummer im Register steht.'],
  ['stammdaten', 'Was im Chargenregister selbst nicht stimmt: eine Perigon-Nummer an zwei Chargen, eine Charge ohne Perigon-Nummer, ein Schlag unter zwei Namen.'],
]

function SoPrueft() {
  return (
    <>
      <Karte titel="Woher die Zahlen kommen" id="perigon-woher">
        <div className="weg-der-ware-schema">
          <div><strong>Herein · Erntejournal</strong><span>jede Palette mit Datum, Brutto, Kisten, Gebinde und Chargennummer</span></div>
          <div aria-hidden="true">→</div>
          <div><strong>In der Halle · App</strong><span>Arbeiten auf einer Charge, mit Zetteln je Palette; Wägungen, Palox</span></div>
          <div aria-hidden="true">→</div>
          <div><strong>Hinaus · Perigon</strong><span>Lieferschein, Artikel, Menge; die Chargennummer und die Menge je Charge</span></div>
        </div>
        <p>Die App sieht nicht in die Halle. Sie rechnet je Charge, was dort stehen müsste: herein laut Erntejournal, hinaus laut Perigon, dazwischen
        die Arbeiten und die Messungen. Die drei Listen hängen nur über die Chargennummer zusammen. Steht in Perigon die falsche Nummer — oder gar
        keine —, stimmt das Lager an zwei Stellen nicht: bei der einen Charge zieht die App Ware ab, die nie von dort kam; bei der anderen bleibt
        Ware auf dem Papier stehen, die längst verkauft ist.</p>
        <p>Jede Firma schickt ihre Perigon-Datei („Abgleich Rückverfolgbarkeit"). In der Chargenspalte steht entweder unsere vierstellige Nummer oder die
        sechsstellige Perigon-Nummer der Firma; die App übersetzt mit dem Chargenregister (Betrieb → Stammdaten → Chargen, Spalte Perigon-Nr.). Eine
        Position steht je Charge einmal da — dreimal, wenn drei Chargen —, mit der Menge der Position auf jeder Zeile und der Menge je Charge daneben.</p>
      </Karte>

      <Karte titel="Die Spalten, auf die es ankommt" id="perigon-spalten">
        <div className="rollbar">
          <table className="dicht umbruch">
            <thead><tr><th>Spalte</th><th>in der Datei</th><th>was die App daraus nimmt</th></tr></thead>
            <tbody>{SPALTEN_ERKLAERT.map(([name, was]) => (
              <tr key={name}><td className="nowrap"><strong>{spaltenZeichen(name) ?? '—'}</strong></td><td className="nowrap">{name}</td><td>{was}</td></tr>
            ))}</tbody>
          </table>
        </div>
        <p className="leise">Eine Zeile in der Datei finden: Excel öffnen, Ctrl+F, die Position (AufPosId) eingeben. Im Fenster jedes Falls steht sie.</p>
      </Karte>

      <Karte titel="Jede Prüfung einer Perigon-Zeile" id="perigon-pruefungen">
        {ART_FOLGE.map(a => {
          const i = PERIGON_ART[a]
          return (
            <section key={a} className="perigon-pruefung-art" id={`pruefung-${a}`}>
              <h3>{i.name} <span className="wo-marke">{WO_NAME[i.wo].kurz}</span></h3>
              <dl className="perigon-art-erklaerung">
                <dt>Was das heisst</dt><dd>{i.heisst}</dd>
                <dt>In der Datei</dt><dd>{i.datei}</dd>
                <dt>Was die App daraus macht</dt><dd>{i.app}</dd>
                <dt>Was tun</dt><dd>{i.tun}</dd>
              </dl>
            </section>
          )
        })}
      </Karte>

      <Karte titel="Jede Prüfung je Charge" id="perigon-pruefungen-charge">
        <dl className="perigon-art-erklaerung">
          {SACHEN_ERKLAERT.map(([art, was]) => <Fragment key={art}><dt>{ART_NAME[art] ?? art}</dt><dd>{was}</dd></Fragment>)}
        </dl>
      </Karte>

      <Karte titel="Was die App bewusst nicht tut" id="perigon-nicht">
        <ul>
          <li><strong>Nicht raten.</strong> Eine Überzählung wird nicht der Schwester-Charge abgezogen; ohne Zettel ist „wohl von dort" eine Vermutung, und so steht sie da.</li>
          <li><strong>Nicht löschen.</strong> Die Charge des Journals bleibt an jeder Palette; eine Umbuchung lässt sich zurücknehmen; ein Vermerk bleibt stehen.</li>
          <li><strong>Einen Vorschlag nicht buchen.</strong> Was die Sorte betrifft, entscheidet, wer zählt.</li>
          <li><strong>Perigon nicht korrigieren.</strong> Die App schreibt nie in Perigon. Was dort falsch steht, bleibt falsch, bis es dort jemand ändert — die App sagt nur, wo.</li>
          <li><strong>Keine Kilo erfinden.</strong> Stück ohne Gewicht sind unbekannt, nie 0; eine Position ohne Menge zählt nirgends.</li>
        </ul>
      </Karte>

      <Karte titel="Wie das Mitverfolgen geht" id="perigon-mitverfolgen">
        <p>Jeder Fall hat einen Schlüssel, der von Rechnen zu Rechnen gleich bleibt: die Art, die Firma, die Position und — bei einer Chargenzeile — die
        Nummer. An ihm hängen zwei Spuren:</p>
        <ul>
          <li><strong>Was der Betriebsleiter festhält</strong> — {(['offen', 'in_abklaerung', 'erledigt', 'kein_fehler'] as VermerkStand[]).map(s => STAND_NAME[s]).join(', ')} —,
            mit einer Notiz, wer und wann. Nur anhängen, nie ändern: der Verlauf ist die Spur.</li>
          <li><strong>Was die App von selbst weiss</strong> — nach jedem fertigen Rechnen, welche Fälle sie sieht: seit wann, und seit wann nicht mehr. Ist ein Fall nach
            dem Neu-Einlesen weg, steht er unter Verlauf → „Nicht mehr in den Daten", mit dem, was er war.</li>
        </ul>
        <p className="leise">„Erledigt" heisst: in Perigon berichtigt. Bis die Datei neu eingelesen ist, steht der Fall noch in den Daten — unter Verlauf als „wartet aufs Einlesen".
          „Kein Fehler" heisst: stimmt so (etwa ein Mix, der wirklich aus einer Charge ist); der Fall zählt dann nicht mehr als offen.</p>
      </Karte>
    </>
  )
}
