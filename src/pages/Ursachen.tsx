import { Fragment, useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { chargenNachFeld } from '../lib/felder'
import { Aufklapp, Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Leer, Segmente } from '../components/Bausteine'
import { Anteilsbalken, Linien, type Anteilszeile, type Punkt, type Reihe, type Zone } from '../components/Diagramm'
import { lagerstaende, prognoseBei, useAuswertung, wohinVon,
         type Auswertung, type AusgangKennzahl, type Bestand, type Lagerstand, type MargeWiegung, type Schema, type Schimmelpunkt, type SortenK, type Wohin } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { ZChevron } from '../components/Zeichen'
import { ArbeitFenster, type Messung } from '../betrieb/ArbeitFenster'
import { ChargeFenster } from '../betrieb/ChargeFenster'
import { MessungFenster, type PunktInfo } from '../betrieb/MessungFenster'

const TAG = 86400000

/** Sorten und Chargen bekommen eine eigene Palette — nicht die der Ströme,
 *  sonst sähe „Tiana" aus wie „Verdunstung" (DESIGN_RUNDE_R § 1.2). */
const REIHENFARBEN = Array.from({ length: 10 }, (_, i) => `var(--reihe-${i + 1})`)

/** Der Filter dieser Seite: alles, eine Sorte oder eine Charge — kein Schlag. */
interface Filter { gruppe: 'gesamt' | 'sorte' | 'charge'; schluessel: string }

/** Welche Achse ein Messbild zeigt: der Kalender oder die Lagerdauer. */
type Achse = 'kalender' | 'liegt'

/**
 * Ursachen — der zweite Reiter. Alles darin ist **bis heute**; keine Zeile
 * schaut in die Zukunft (das tut Lagermanagement).
 *
 *   „was ist tatsächlich passiert - warum hab ich weniger als eingelagert?
 *    … und auch da - spannend wäre dann zu sehen - wann hat fäulnis
 *    besonders zugelegt - welche sorte welche charge - z.b. plötzlich ab
 *    dezember - dieser kürbis wurde faul - fast vollständig auf einen schlag"
 *
 * Vier Blöcke: wohin der Kürbis ging, das Faule, die Verdunstung, die
 * verschenkte Marge. Die zwei Messbilder haben zwei Achsen — den Kalender
 * („ab wann ging es los") und die Lagerdauer („nach wie vielen Wochen").
 */
export default function Ursachen() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const [params, setParams] = useSearchParams()
  const filter: Filter = params.get('charge') ? { gruppe: 'charge', schluessel: params.get('charge')! }
    : params.get('sorte') ? { gruppe: 'sorte', schluessel: params.get('sorte')! }
    : { gruppe: 'gesamt', schluessel: '' }
  const setzen = (wert: string) => {
    const [g, k] = wert.split('|')
    const neu = new URLSearchParams(params)
    neu.delete('sorte'); neu.delete('charge')
    if (g && k) neu.set(g, k)
    setParams(neu, { replace: true })
  }

  /** Runde W: die Arbeit hinter einem Punkt oder einer Wägung, als Fenster über
   *  der Seite. Runde Z: mit der Messung voran, von der aus geklickt wurde —
   *  und wenn der Punkt keine Arbeit hat (Kontrollwägung), die Messung allein;
   *  dazu die Charge als Fenster. */
  const [fenster, setFenster] = useState<{ auftragId: number; messung?: Messung } | null>(null)
  const [punkt, setPunkt] = useState<PunktInfo | null>(null)
  const [chargeFenster, setChargeFenster] = useState<number | null>(null)
  const punktOeffnen = (p: Punkt, titel: string) => {
    const zeilen = (p.text ?? '').split(' · ')
    if (p.auftragId != null) setFenster({ auftragId: p.auftragId, messung: { titel, name: p.name ?? '', zeilen } })
    else setPunkt({ titel, name: p.name ?? '', zeilen, chargeNr: p.chargeNr })
  }
  const chargen = useMemo(() => daten ? chargenIm(daten.bestand, filter) : [], [daten, filter])
  const staende = useMemo(() => daten ? lagerstaende(chargen, daten.naechste) : [], [chargen, daten])

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  // Runde AJ: die zweite Welle der Ergebnisse (dieser Reiter braucht sie) kommt nach dem Lagermanagement.
  if (daten && !daten.vollstaendig) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null

  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort((a, b) => a.localeCompare(b, 'de'))
  const chargenListe = [...daten.bestand].sort((a, b) => a.charge_nr - b.charge_nr)
  const name = filter.gruppe === 'gesamt' ? 'Alle Chargen'
    : filter.gruppe === 'charge' ? `Charge ${filter.schluessel} · ${chargen[0]?.sorte ?? ''}` : filter.schluessel

  return (
    <>
      <Reiterkopf titel="Ursachen"
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt}
                  zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
      <Probleme liste={daten.probleme} />

      <div className="filterleiste haftend">
        <label htmlFor="uf">Ansicht</label>
        <select id="uf" value={filter.gruppe === 'gesamt' ? '' : `${filter.gruppe}|${filter.schluessel}`}
                onChange={e => setzen(e.target.value)}>
          <option value="">alle Chargen</option>
          <optgroup label="Sorte">{sorten.map(s => <option key={s} value={`sorte|${s}`}>{s}</option>)}</optgroup>
          {/* Runde AD: nach Feld, darin Sorte, dann die Nummer — wie im Lagermanagement. */}
          {chargenNachFeld(chargenListe).map(f => (
            <optgroup key={f.feld} label={f.feld}>
              {f.chargen.map(c => <option key={c.charge_nr} value={`charge|${c.charge_nr}`}>{c.sorte} ({c.charge_nr})</option>)}
            </optgroup>
          ))}
        </select>
        {filter.gruppe !== 'gesamt' && <span className="aktiv-filter">{name}</span>}
        <span>{chargen.length} {chargen.length === 1 ? 'Charge' : 'Chargen'} · {staende.length} mit Ware im Haus</span>
        {filter.gruppe !== 'gesamt' && <button type="button" className="werkzeug-knopf" onClick={() => setzen('')}>alle zeigen</button>}
      </div>

      <Wohin daten={daten} filter={filter} setzen={setzen} chargeAnsehen={setChargeFenster} />
      <Faules daten={daten} filter={filter} chargen={chargen} staende={staende} oeffnen={punktOeffnen} />
      <Verdunstung daten={daten} filter={filter} chargen={chargen} oeffnen={punktOeffnen} />
      <Marge daten={daten} filter={filter} chargen={chargen} oeffnen={id => setFenster({ auftragId: id })} />
      {fenster !== null && <ArbeitFenster auftragId={fenster.auftragId} messung={fenster.messung} schliessen={() => setFenster(null)} />}
      {punkt !== null && <MessungFenster info={punkt} schliessen={() => setPunkt(null)} />}
      {chargeFenster !== null && <ChargeFenster chargeNr={chargeFenster} schliessen={() => setChargeFenster(null)} />}
    </>
  )
}

function chargenIm(bestand: Bestand[], f: Filter): Bestand[] {
  if (f.gruppe === 'charge') return bestand.filter(b => String(b.charge_nr) === f.schluessel)
  if (f.gruppe === 'sorte') return bestand.filter(b => b.sorte === f.schluessel)
  return bestand
}

/** Die Achsenwahl merkt sich das Gerät — wer den Kalender will, will ihn morgen wieder. */
function useAchse(schluessel: string): [Achse, (a: Achse) => void] {
  const [achse, setAchse] = useState<Achse>(() => {
    try { return localStorage.getItem(schluessel) === 'liegt' ? 'liegt' : 'kalender' } catch { return 'kalender' }
  })
  return [achse, (a: Achse) => {
    setAchse(a)
    try { localStorage.setItem(schluessel, a) } catch { /* privates Fenster: dann eben nicht */ }
  }]
}

/** Eine feste Farbe je Name — alphabetisch, damit eine Sorte überall dieselbe hat. */
function farbwahl(namen: string[]): (n: string) => string {
  const ordnung = [...namen]
  return (n: string) => REIHENFARBEN[Math.max(0, ordnung.indexOf(n)) % REIHENFARBEN.length]
}

const tagVon = (d: string) => Math.floor(Date.parse(d) / TAG)
const tagText = (x: number) => datum(new Date(x * TAG)).slice(0, 6)

/* ---------- U1: Wohin ging der Kürbis? -------------------------------------- */

/** Die sechs Teile, in die der Eingang bis heute zerfällt (DESIGN_RUNDE_R § 3). */
const WOHIN_TEILE: { name: string; farbe: string; hinweis?: string; felder: (keyof Wohin)[] }[] = [
  { name: 'noch im Lager und verkaufsfähig', farbe: 'var(--strom-rest-hell)',
    felder: ['lager_verkaufsfaehig_kg'] },
  { name: 'verkauft', farbe: 'var(--strom-rest)',
    felder: ['geliefert_kg'] },
  { name: 'verdunstet bis heute', farbe: 'var(--strom-verdunstung)',
    hinweis: 'entwichenes Wasser, draussen wie drinnen', felder: ['verdunstet_ausgelagert_kg', 'lager_verdunstet_kg'] },
  { name: 'Faules bis heute', farbe: 'var(--strom-schimmel)',
    hinweis: 'Faules im Lager und beim Abpacken', felder: ['faul_ausgelagert_kg', 'lager_faul_kg', 'fax_kg', 'lager_fax_kg'] },
  { name: 'zu klein', farbe: 'var(--strom-ausschuss)',
    hinweis: 'beim Sortieren aussortiert — steht im Haus, bis ein Lieferschein es holt; kein Verlust', felder: ['klein_ausgelagert_kg', 'lager_klein_kg'] },
  { name: 'zu gross', farbe: 'var(--strom-nebenkanal)',
    hinweis: 'beim Sortieren aussortiert — steht im Haus, bis ein Lieferschein es holt; kein Verlust', felder: ['gross_ausgelagert_kg', 'lager_gross_kg'] },
]
const VERLUST = new Set(['verdunstet bis heute', 'Faules bis heute'])

function wohinZeile(w: Wohin | null, name: string, untertitel: string, ziel?: string): Anteilszeile & { verlust: number } {
  const teile = WOHIN_TEILE.map(t => ({
    name: t.name, farbe: t.farbe, hinweis: t.hinweis,
    kg: t.felder.reduce((a, f) => a + ((w?.[f] as number | null) ?? 0), 0),
  }))
  const rest = ((w?.rest_kg ?? 0) + (w?.lager_rest_kg ?? 0))
  if (Math.abs(rest) > 0.5) teile.push({ name: 'Rest der Zählung', farbe: 'var(--text-ganz-leise)', kg: Math.max(rest, 0), hinweis: 'was die Zerlegung nicht zuordnen konnte' })
  const eingang = w?.eingang_kg ?? 0
  const verlust = teile.filter(t => VERLUST.has(t.name)).reduce((a, t) => a + t.kg, 0)
  return { name, untertitel, bezug: eingang, bezugName: 'am Eingang', teile, ziel,
           rechts: prozent(eingang > 0 ? verlust / eingang : null), verlust: eingang > 0 ? verlust / eingang : 0 }
}

function Wohin({ daten, filter, setzen, chargeAnsehen }: {
  daten: Auswertung; filter: Filter; setzen: (w: string) => void; chargeAnsehen: (nr: number) => void
}) {
  // Runde Z: eine Sorte lässt sich aufklappen — ihre Chargen darunter, ohne
  // den Filter zu wechseln; jede Charge öffnet sich als Fenster.
  const [auf, setAuf] = useState<Set<string>>(new Set())
  const umschalten = (s: string) => setAuf(a => { const n = new Set(a); if (n.has(s)) n.delete(s); else n.add(s); return n })
  const w = wohinVon(daten.wohin, filter.gruppe, filter.schluessel)
  const chargen = chargenIm(daten.bestand, filter)
  const kopf: Anteilszeile & { verlust: number } = {
    ...wohinZeile(w, filter.gruppe === 'gesamt' ? 'Alle Chargen' : filter.gruppe === 'charge' ? `Charge ${filter.schluessel}` : filter.schluessel,
      `${w?.n_chargen ?? chargen.length} ${(w?.n_chargen ?? 0) === 1 ? 'Charge' : 'Chargen'} · ${tonnen(w?.eingang_kg)} Eingang`),
    aktion: filter.gruppe === 'charge'
      ? <button type="button" className="werkzeug-knopf charge-ansehen" onClick={() => chargeAnsehen(Number(filter.schluessel))}>Charge ansehen</button>
      : undefined,
  }

  const chargeZeile = (c: Bestand, eingerueckt = false): Anteilszeile & { verlust: number } => ({
    ...wohinZeile(wohinVon(daten.wohin, 'charge', String(c.charge_nr)), `Charge ${c.charge_nr}`,
      `${c.sorte} · ${c.schlag} · ${tonnen(c.eingang_kg)} Eingang`, `charge|${c.charge_nr}`),
    schluessel: `charge|${c.charge_nr}`, eingerueckt,
    aktion: <button type="button" className="werkzeug-knopf charge-ansehen" onClick={() => chargeAnsehen(c.charge_nr)}>ansehen</button>,
  })
  const nachVerlust = (a: { verlust: number }, b: { verlust: number }) => b.verlust - a.verlust

  // Darunter: je Sorte (Filter Alle, aufklappbar zu ihren Chargen) oder je
  // Charge (Filter Sorte).
  const unterGruppe = filter.gruppe === 'gesamt' ? 'sorte' : filter.gruppe === 'sorte' ? 'charge' : null
  const sortiert: (Anteilszeile & { verlust: number })[] = []
  if (unterGruppe === 'sorte') {
    const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort().map(s => {
      const inSorte = daten.bestand.filter(b => b.sorte === s)
      const z: Anteilszeile & { verlust: number } = {
        ...wohinZeile(wohinVon(daten.wohin, 'sorte', s), s,
          `${inSorte.length} Chargen · ${tonnen(wohinVon(daten.wohin, 'sorte', s)?.eingang_kg)} Eingang`, `sorte|${s}`),
        schluessel: `sorte|${s}`,
        aktion: <button type="button" className="werkzeug-knopf sorte-auf" aria-expanded={auf.has(s)} onClick={() => umschalten(s)}>
                  <span className="chevron" aria-hidden="true" style={{ display: 'inline-flex', transition: 'transform var(--d-mittel)', transform: auf.has(s) ? 'rotate(90deg)' : undefined }}><ZChevron size={12} /></span> {auf.has(s) ? 'Chargen wieder zu' : `${inSorte.length} Chargen einzeln zeigen`}
                </button>,
      }
      return { z, inSorte }
    }).filter(x => x.z.bezug > 0).sort((a, b) => nachVerlust(a.z, b.z))
    for (const { z, inSorte } of sorten) {
      sortiert.push(z)
      if (auf.has(z.name)) sortiert.push(...inSorte.map(c => chargeZeile(c, true)).filter(x => x.bezug > 0).sort(nachVerlust))
    }
  } else if (unterGruppe === 'charge') {
    sortiert.push(...chargen.map(c => chargeZeile(c)).filter(z => z.bezug > 0).sort(nachVerlust))
  }

  return (
    <Karte id="urs-wohin" titel="Wohin ging der Kürbis?">
      {/* Steht darunter noch eine Liste, trägt die die Legende; steht keine da
          (eine einzelne Charge), muss der Kopfbalken sie selbst tragen — sonst
          ist der Balken bunt und niemand weiss, welcher Streifen was ist. */}
      {/* Runde AF: die Legende steht gleich unter dem Kopfbalken, und die Zahl
          rechts trägt ihren Namen — der Betrieb fragte, was das Farbband ist
          und was „20.2 %" heisst. */}
      <Anteilsbalken zeilen={[kopf]} legende rechtsTitel="Verlust bis heute · % des Eingangs" />
      {sortiert.length > 0 && (
        <>
          <div className="tag-trenner">{unterGruppe === 'sorte' ? 'je Sorte' : 'je Charge'} <span className="leise">nach Verlustanteil</span></div>
          <Anteilsbalken zeilen={sortiert} oeffnen={z => z.ziel && setzen(z.ziel)} legende={false} />
          <p className="fussnote">Eine Zeile anklicken macht sie zur Ansicht; „ansehen" öffnet die Charge als Fenster, ohne die Seite zu verlassen.</p>
        </>
      )}
      {(w?.ueberzaehlung_kg ?? 0) > 0 && (
        <p className="fussnote">{tonnen(w?.ueberzaehlung_kg)} mehr geliefert als eingelagert — ein Zählfehler beim Eingang, nicht Ware.</p>
      )}
      <Erklaerung>
        <p>Jeder Balken ist der ganze Eingang der Zeile (100 %) <Herkunft art="gemessen" />, von links nach rechts in die sechs Teile der Legende
        zerlegt: was noch verkaufsfähig liegt, was verkauft ist, was verdunstet und was verfault ist, was zu klein und was zu gross war. Rechts steht
        der Anteil <strong>echter Verlust</strong> — verdunstetes Wasser und Faules, in Prozent des Eingangs; danach sind die Zeilen sortiert.</p>
        <p><strong>Zu klein und zu gross sind kein Verlust.</strong> Die Ware ist nicht weg, nur nicht in der richtigen Grösse: Sie steht
        aussortiert im Haus, bis ein Lieferschein sie holt — und sie war es vom Feld an.</p>
      </Erklaerung>
    </Karte>
  )
}

/* ---------- U2: Faules im Lager --------------------------------------------- */

function Faules({ daten, filter, chargen, staende, oeffnen }: {
  daten: Auswertung; filter: Filter; chargen: Bestand[]; staende: Lagerstand[]; oeffnen: (p: Punkt, titel: string) => void
}) {
  const [achse, setAchse] = useAchse('urs.palox.achse')
  // 0105: „Vergleiche nur unter ihresgleichen" — die Punkte lassen sich je
  // Station zeigen (dann zählt der eigene Anteil dieses Auges, nichts
  // dazugerechnet), und die Chargen mit Linien verbinden: Wer denselben
  // Hagelschaden zweimal sieht, sieht ihn als eine Linie, nicht als zwei
  // Ausreisser.
  const [sicht, setSicht] = useWahl<Sicht>('urs.palox.sicht', 'alle', SICHTEN.map(s => s[0]))
  const [verbinden, setVerbinden] = useWahl<'ja' | 'nein'>('urs.palox.linien', 'nein', ['ja', 'nein'])
  const imFilter = new Set(chargen.map(c => c.charge_nr))
  const punkte = daten.punkte.filter(p => imFilter.has(p.charge_nr) && (sicht === 'alle' || p.station === sicht))
  const wert = (p: Schimmelpunkt) => sicht === 'alle' ? p.anteil : p.anteil_station
  // Je Station urteilt die Plausibilität über den eigenen Anteil, nicht über
  // den aufgelaufenen des Modells (45 % am Band und 10 % beim Waschen machen
  // den Wasch-Punkt nicht unplausibel).
  const plausibel = (p: Schimmelpunkt) => sicht === 'alle' ? p.plausibel : p.plausibel_station
  const gute = punkte.filter(p => plausibel(p) && wert(p) !== null)
  const schlechte = punkte.filter(p => !plausibel(p) && wert(p) !== null)

  // Gruppiert wird eine Ebene feiner als der Filter: alle → je Sorte,
  // eine Sorte → je Charge, eine Charge → eine Reihe.
  const schluesselVon = (p: typeof gute[number]) =>
    filter.gruppe === 'gesamt' ? p.sorte : filter.gruppe === 'sorte' ? `Charge ${p.charge_nr}` : `Charge ${p.charge_nr}`
  const namen = [...new Set(gute.map(schluesselVon))].sort((a, b) => a.localeCompare(b, 'de', { numeric: true }))
  const farbe = farbwahl(namen)

  // 0091: der Kommentar zur Ware am Punkt — „Hagelschaden" erklärt den
  // Ausreisser, bevor jemand ihn sucht.
  const kommentar = new Map(daten.kommentare.map(k => [k.auftrag_id, k.text]))
  const heute = tagVon(daten.heute)
  const p0 = prognoseBei(daten.prognose, filter.gruppe, filter.schluessel, 0)
  const xVon = (p: Schimmelpunkt) => achse === 'kalender' ? tagVon(p.messtag) : p.lagertage

  // Je Gruppe die Masse: die grössten bleiben sichtbar, der Rest ist in der
  // Legende ausgeblendet — mehr als zehn Reihen liest niemand.
  const masseJe = new Map<string, number>()
  for (const p of gute) masseJe.set(schluesselVon(p), (masseJe.get(schluesselVon(p)) ?? 0) + p.basis_jetzt_kg)
  const rang = [...masseJe.entries()].sort((a, b) => b[1] - a[1]).map(([n]) => n)
  const sichtbar = new Set(rang.slice(0, 10))

  const reihen: Reihe[] = namen.map(n => ({
    name: n,
    farbe: farbe(n), marker: true, linie: false, form: 'kreis' as const,
    ausgeblendet: !sichtbar.has(n),
    punkte: gute.filter(p => schluesselVon(p) === n).map(p => ({
      x: xVon(p),
      y: (wert(p) ?? 0) * 100,
      name: `Charge ${p.charge_nr} · ${p.sorte}`,
      text: `${datum(p.messtag)} · ${stationText(p.station)} · liegt seit ${Math.round(p.lagertage)} Tagen · ${kg(p.schimmel_kg, 0)} von ${kg(p.basis_jetzt_kg, 0)} · ${quelleText(p.quelle)}${p.auftrag_id != null && kommentar.has(p.auftrag_id) ? ` · Kommentar: ${kommentar.get(p.auftrag_id)}` : ''}`,
      auftragId: p.auftrag_id, chargeNr: p.charge_nr,
      groesse: p.auftrag_id != null && kommentar.has(p.auftrag_id) ? 6 : undefined,
    })),
  })).filter(r => r.punkte.length > 0)

  // 0105: die Punkte derselben Charge verbinden — in der Reihenfolge der Achse,
  // dünn und gestrichelt in der Farbe ihrer Gruppe, ohne eigenen Eintrag in
  // der Legende. Nur Chargen mit zwei und mehr Punkten in dieser Sicht.
  if (verbinden === 'ja') {
    const jeCharge = new Map<number, Schimmelpunkt[]>()
    for (const p of gute) jeCharge.set(p.charge_nr, [...(jeCharge.get(p.charge_nr) ?? []), p])
    for (const [nr, ps] of jeCharge) {
      if (ps.length < 2) continue
      const n = schluesselVon(ps[0])
      reihen.push({
        name: `Charge ${nr} verbunden`, farbe: farbe(n), linie: true, marker: false, gestrichelt: true,
        ohneLegende: true, gruppe: n,
        punkte: ps.map(p => ({ x: xVon(p), y: (wert(p) ?? 0) * 100 })).sort((a, b) => a.x - b.x),
      })
    }
  }

  if (schlechte.length > 0) {
    reihen.push({
      name: 'nicht plausibel — nicht in der Rechnung', farbe: 'var(--text-ganz-leise)', marker: true, linie: false,
      punkte: schlechte.map(p => ({
        x: xVon(p),
        y: Math.min((wert(p) ?? 0) * 100, 100),
        name: `Charge ${p.charge_nr} · ${p.sorte}`,
        text: `${datum(p.messtag)} · ${stationText(p.station)} · ${kg(p.schimmel_kg, 0)} von ${kg(p.basis_jetzt_kg, 0)} · nicht plausibel, siehe Messungen${p.auftrag_id != null && kommentar.has(p.auftrag_id) ? ` · Kommentar: ${kommentar.get(p.auftrag_id)}` : ''}`,
        auftragId: p.auftrag_id, chargeNr: p.charge_nr,
      })),
    })
  }

  // Auf der Lagerdauer-Achse: wo die Ware heute liegt. Seit 0106 läuft hier
  // keine Kurve mehr mit — die Kaskade rechnet mit den Stationswerten, nicht
  // mit dem Alter; die Zone zeigt nur, welche Lagerdauern gerade im Haus sind.
  let zonen: Zone[] = []
  let heuteMarke: { x: number; text?: string; rechts?: string } | undefined
  if (achse === 'liegt' && staende.length > 0) {
    const von = Math.min(...staende.map(s => s.von))
    const bis = Math.max(...staende.map(s => s.bis))
    if (staende.length === 1) {
      heuteMarke = { x: staende[0].alter, text: `heute · ${Math.round(staende[0].alter)} Tage im Lager`,
                     rechts: 'länger gelagert' }
    } else {
      // Rechts der Zone steht nicht die Zukunft, sondern längere Lagerdauer —
      // deshalb heisst die Marke hier nicht „Prognose" (Ursachen zeigt keine).
      zonen = [{ von, bis, text: `hier liegt die Ware heute (${Math.round(von)}–${Math.round(bis)} Tage)` }]
    }
  }

  const kennzahlen = daten.paloxStationen.filter(k => k.n_arbeiten > 0 && (sicht === 'alle' || k.station === sicht))

  return (
    <Karte id="urs-palox" titel="Faules im Lager"
           aktion={<div className="segmente-reihe">
             <Segmente wahl={sicht} setzen={setSicht} id="palox-sicht" teile={[...SICHTEN]} />
             <Segmente wahl={achse} setzen={setAchse} id="palox-achse"
                       teile={[['kalender', 'Kalender', 'palox-achse-kalender'], ['liegt', 'liegt seit', 'palox-achse-liegt']]} />
             <label className="ankreuzen klein-text" htmlFor="palox-linien">
               <input id="palox-linien" type="checkbox" checked={verbinden === 'ja'} onChange={e => setVerbinden(e.target.checked ? 'ja' : 'nein')} />
               Chargen verbinden
             </label>
           </div>}>
      {punkte.length === 0
        ? <Leer titel={sicht === 'alle' ? 'Noch keine Messung am Palox' : `Noch keine Messung am Palox: ${stationText(sicht)}`}>Sobald eine Arbeit den Palox zweimal abgelesen hat, steht hier ihr Punkt.</Leer>
        : (
        <Linien reihen={reihen} hoehe={300}
                xTitel={achse === 'kalender' ? 'Messtag' : 'Lagertage'} yTitel="Faules je 100 kg Ware"
                xFormat={achse === 'kalender' ? tagText : x => `${Math.round(x)}`}
                yFormat={y => `${y.toFixed(1)} %`}
                xEinheit={achse === 'kalender' ? 'frei' : 'tage'} yEinheit="prozent" yVon={0}
                xBis={achse === 'kalender' ? heute : undefined}
                heute={achse === 'kalender' ? { x: heute, text: `heute, ${tagText(heute)}`, rechts: '' } : heuteMarke}
                zonen={zonen}
                leer="noch keine Schimmelmessung"
                treffer="punkt" onPunkt={p => oeffnen(p, 'Diese Messung: Faules am Palox')}
                fuss={sicht === 'alle' && p0
                  ? <span className="leise">{p0.faul_je_tag_kg != null
                      ? <>Rechnung heute: {kg(p0.faul_je_tag_kg, 0)} Faules je Tag an der liegenden Ware (Stationswerte, fortgeschrieben mit dem Zuwachs je Woche)</>
                      : <>Rechnung heute: das Faule steht auf dem Stand der Stationswerte — fortgeschrieben wird erst, wenn die Kennzahl je Station einen Zuwachs ausweist</>}</span>
                  : undefined} />
      )}
      {kennzahlen.length > 0 && (
        <div className="kennzahlen" id="palox-stationen">
          {kennzahlen.map(k => (
            <Kennzahl key={k.station} id={`kz-palox-${k.station}`}
                      titel={<>{stationText(k.station)} <Herkunft art="gerechnet" /></>}
                      wert={k.anteil_mittel != null ? `${(k.anteil_mittel * 100).toFixed(1)} %` : '—'}
                      unter={<span className="unter">im Mittel in den Palox, gerechnet über {k.n_arbeiten} Arbeiten und {k.n_chargen} Chargen seit {datum(k.seit)}
                        {k.anteil_median != null && <> · Median {(k.anteil_median * 100).toFixed(1)} %</>}
                        {k.anteil_4w != null && k.n_4w > 0 && <> · letzte vier Wochen {(k.anteil_4w * 100).toFixed(1)} % ({k.n_4w})</>}
                        {' · '}{k.zuwachs_je_woche != null
                          ? <>Zuwachs seit Messbeginn {k.zuwachs_je_woche >= 0 ? '+' : ''}{(k.zuwachs_je_woche * 100).toFixed(2)} Punkte je Woche</>
                          : (k.zuwachs_text ?? 'Zuwachs: noch nicht bestimmbar')}</span>} />
          ))}
        </div>
      )}
      <p className="hilfe">
        Jeder Punkt ist eine Ablesung am Palox <Herkunft art="gemessen" />.{' '}
        Je Station zählt der Anteil dieses Auges allein: An der Sortiermaschine kommt nur eklig Faules in den Palox, an der
        Waschstrasse auch Ästhetik und Schäden — darum werden Stationen nur unter ihresgleichen verglichen. „Chargen
        verbinden" zieht eine Linie durch die Punkte derselben Charge.{' '}
        Die Lagerdauer ist beim Sortieren und beim Waschen + Sortieren vom Zettel abgelesen; beim Waschen hat die
        Palette aus dem Zwischenlager kein Eingangsdatum mehr — dort ist sie das mittlere Eingangsdatum der Charge,
        also geschätzt. Wie oft welches zutrifft: <Link to="/messungen">Messungen</Link>.
      </p>
      <Erklaerung>
        <p>Gemessen wird der Palox, wenn eine Palette an die Sortiermaschine oder an die Waschstrasse kommt — bezogen auf
        die Masse, die an dem Tag aus dem Lager kam. <strong>Kalender</strong> beantwortet „ab wann ging es los",
        <strong> liegt seit</strong> beantwortet „nach wie vielen Wochen".</p>
        <p>Die Kennzahl je Station <Herkunft art="gerechnet" /> ist das nach Masse gewichtete Mittel der plausiblen Punkte
        dieser Station; der Zuwachs ist die Steigung einer massegewichteten Geraden über den Messtag und wird erst nach
        vier Wochen und fünf Arbeiten gezeigt — vorher steht, was noch fehlt.</p>
        <p>Mit diesen Werten rechnet die Kaskade (seit 0106): je Sorte und Station das Mittel der letzten vier Wochen, sonst der Saison,
        sonst aller Sorten — zusammengesetzt über den Weg der Charge (von Hand, oder Band und danach Waschstrasse). Für schon
        ausgelagerte Ware gilt die eigene Messung der Charge. Die Tabelle je Sorte und Station steht unter <Link to="/messungen">Messungen</Link>.</p>
      </Erklaerung>
    </Karte>
  )
}

type Sicht = 'alle' | 'waschen_sortieren' | 'waschen' | 'sortieren'
const SICHTEN = [
  ['alle', 'alle', 'palox-sicht-alle'],
  ['waschen_sortieren', 'Waschen + Sortieren', 'palox-sicht-ws'],
  ['waschen', 'nur Waschen', 'palox-sicht-w'],
  ['sortieren', 'Sortieren', 'palox-sicht-s'],
] as const
const stationText = (s: string) =>
  s === 'waschen_sortieren' ? 'Waschen + Sortieren' : s === 'waschen' ? 'nur Waschen' : s === 'sortieren' ? 'Sortiermaschine' : s === 'lager' ? 'Kontrollpalette' : s

/** Eine gemerkte Wahl (0105): wie useAchse, für beliebige Werte aus einer Liste. */
function useWahl<T extends string>(schluessel: string, sonst: T, erlaubt: readonly T[]): [T, (w: T) => void] {
  const [wert, setWert] = useState<T>(() => {
    try { const w = localStorage.getItem(schluessel); return w !== null && (erlaubt as readonly string[]).includes(w) ? w as T : sonst } catch { return sonst }
  })
  return [wert, (w: T) => { setWert(w); try { localStorage.setItem(schluessel, w) } catch { /* privates Fenster */ } }]
}

const quelleText = (q: string) =>
  q === 'lager' ? 'Lagerkontrolle' : q === 'verarbeitung_gemischt' ? 'Arbeit mit mehreren Chargen' : 'an der Maschine'

/* ---------- U3: Verdunstung -------------------------------------------------- */

function Verdunstung({ daten, filter, chargen, oeffnen }: { daten: Auswertung; filter: Filter; chargen: Bestand[]; oeffnen: (p: Punkt, titel: string) => void }) {
  const [achse, setAchse] = useAchse('urs.verd.achse')
  const imFilter = new Set(chargen.map(c => c.charge_nr))
  const alle = daten.wiegungen.filter(w => imFilter.has(w.charge_nr) && w.lagertage > 0 && w.rate_pro_tag !== null)
  const gute = alle.filter(w => w.verwendbar)
  const schlechte = alle.filter(w => !w.verwendbar)
  const schluesselVon = (w: typeof alle[number]) => filter.gruppe === 'gesamt' ? w.sorte : `Charge ${w.charge_nr}`
  const namen = [...new Set(gute.map(schluesselVon))].sort((a, b) => a.localeCompare(b, 'de', { numeric: true }))
  const farbe = farbwahl(namen)
  const heute = tagVon(daten.heute)
  const rate = (s: string): SortenK | undefined => daten.sorten.verdunstung.find(k => k.sorte === s)
  const kommentar = new Map(daten.kommentare.map(k => [k.auftrag_id, k.text]))

  // Wie beim Faulen: höchstens zehn Reihen sichtbar, der Rest wartet in der
  // Legende (DESIGN_RUNDE_R § 5). Sortiert nach der Zahl der Wägungen — die
  // am besten belegten Sorten stehen vorn.
  const zahlJe = new Map<string, number>()
  for (const w of gute) zahlJe.set(schluesselVon(w), (zahlJe.get(schluesselVon(w)) ?? 0) + 1)
  const sichtbar = new Set([...zahlJe.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10).map(([n]) => n))

  const reihen: Reihe[] = namen.map(n => ({
    name: n, farbe: farbe(n), marker: true, linie: false, form: 'kreis' as const,
    ausgeblendet: !sichtbar.has(n),
    punkte: gute.filter(w => schluesselVon(w) === n).map(w => ({
      x: achse === 'kalender' ? tagVon(w.wiege_ts) : w.lagertage,
      y: (w.rate_pro_tag ?? 0) * 100,
      name: `Charge ${w.charge_nr} · ${w.sorte}`,
      text: `${datum(w.wiege_ts)} · liegt seit ${Math.round(w.lagertage)} Tagen · ${kg(w.netto_damals_kg, 0)} → ${kg(w.netto_jetzt_kg, 0)}${w.auftrag_id != null && kommentar.has(w.auftrag_id) ? ` · Kommentar: ${kommentar.get(w.auftrag_id)}` : ''}`,
      auftragId: w.auftrag_id, chargeNr: w.charge_nr,
      groesse: w.auftrag_id != null && kommentar.has(w.auftrag_id) ? 6 : undefined,
    })),
  })).filter(r => r.punkte.length > 0)

  // 0089: jede Wägung, die nicht zählt, sagt warum — „zu schnell — 4.8 % je
  // Tag ist keine Verdunstung", „schwerer geworden", „Schimmel sichtbar".
  // Der Ausreisser steht im Bild, aber nicht in der Rate.
  if (schlechte.length > 0) {
    reihen.push({
      name: 'zählt nicht in die Rate', farbe: 'var(--text-ganz-leise)', marker: true, linie: false,
      punkte: schlechte.map(w => ({
        x: achse === 'kalender' ? tagVon(w.wiege_ts) : w.lagertage,
        y: Math.max((w.rate_pro_tag ?? 0) * 100, 0),
        name: `Charge ${w.charge_nr} · ${w.sorte}`,
        text: `${datum(w.wiege_ts)} · ${kg(w.netto_damals_kg, 0)} → ${kg(w.netto_jetzt_kg, 0)} · ${w.grund ?? 'zählt nicht in die Rate'}${w.plausibel ? '' : ' — unter Messungen berichtigen'}`,
        auftragId: w.auftrag_id, chargeNr: w.charge_nr,
      })),
    })
  }

  // Auf der Lagerdauer: die Erwartung je Sorte als waagrechte Linie.
  const sortenImBild = filter.gruppe === 'gesamt' ? namen : [...new Set(chargen.map(c => c.sorte))]
  const waagrechte = achse === 'liegt'
    ? sortenImBild.map(s => ({ k: rate(s), s })).filter(x => x.k?.mittel != null)
        .map(x => ({ y: (x.k!.mittel ?? 0) * 100, text: `${x.s}: ${prozent(x.k!.mittel, 3)} je Tag`,
                     farbe: filter.gruppe === 'gesamt' ? farbe(x.s) : 'var(--text-leise)' }))
    : []

  const tabelle = daten.sorten.verdunstung
    .filter(k => k.n > 0 && (filter.gruppe === 'gesamt' || sortenImBild.includes(k.sorte)))
    .sort((a, b) => (a.mittel ?? 0) - (b.mittel ?? 0))

  return (
    <Karte id="urs-verdunstung" titel="Verdunstung"
           aktion={<Segmente wahl={achse} setzen={setAchse} id="verd-achse"
                             teile={[['kalender', 'Kalender', 'verd-achse-kalender'], ['liegt', 'liegt seit', 'verd-achse-liegt']]} />}>
      {alle.length === 0
        ? <Leer titel="Noch keine Palette zweimal gewogen">Die Verdunstung misst, wer dieselbe Palette später noch einmal auf die Waage stellt.</Leer>
        : (
        <Linien reihen={reihen} hoehe={300}
                xTitel={achse === 'kalender' ? 'Wiegetag' : 'Lagertage'} yTitel="Verdunstung je Tag"
                xFormat={achse === 'kalender' ? tagText : x => `${Math.round(x)}`}
                yFormat={y => `${y.toFixed(2)} %`}
                xEinheit={achse === 'kalender' ? 'frei' : 'tage'} yEinheit="prozent" yVon={0}
                xBis={achse === 'kalender' ? heute : undefined}
                heute={achse === 'kalender' ? { x: heute, text: `heute, ${tagText(heute)}`, rechts: '' } : undefined}
                waagrechte={waagrechte}
                leer="noch keine verwendbare Wägung"
                treffer="punkt" onPunkt={p => oeffnen(p, 'Diese Wägung')}
                fuss={<span className="leise">Die Rechnung nimmt je Sorte eine Rate. Fallen die Punkte im Winter sichtbar ab, ist das ein Befund — kein zweites Modell. Ein Punkt angeklickt öffnet die Arbeit dahinter.</span>} />
      )}
      {tabelle.length > 0 && (
        <Aufklapp titel={<><span>Je Sorte: die Rate</span> <span className="leise">{tabelle.length} Sorten, nach Rate sortiert — oben hält am besten</span></>}>
          <div className="rollbar"><table className="dicht">
            <thead><tr><th>Sorte</th><th className="zahl">Rate je Tag</th><th className="zahl">Bereich</th><th className="zahl">Wägungen</th><th>Basis</th></tr></thead>
            <tbody>{tabelle.map(k => (
              <tr key={k.sorte}>
                <td>{k.sorte}</td>
                <td className="zahl"><strong>{prozent(k.mittel, 3)}</strong></td>
                <td className="zahl"><span className="leise">{k.unten != null && k.oben != null ? `${prozent(k.unten, 3)}–${prozent(k.oben, 3)}` : '—'}</span></td>
                <td className="zahl">{k.n}</td>
                <td><span className="leise">{k.basis}</span></td>
              </tr>
            ))}</tbody>
          </table></div>
        </Aufklapp>
      )}
      <Erklaerung>
        <p>Gewogen wird dieselbe Palette zweimal: beim Eingang und später noch einmal. Die Tagesrate ist
        <em> (1 − Netto jetzt / Netto damals)</em> auf einen Tag heruntergerechnet <Herkunft art="gemessen" /> —
        keine Hochrechnung, eine Messung.</p>
        <p>Eine Palette, die schwerer wurde, zählt nicht in die Rate (Waagenrauschen oder ein kopiertes Eingangsgewicht);
        sie steht grau im Bild, damit niemand sie sucht. Ebenso eine Wägung über der Grenze
        <em> verdunstung_rate_max_pro_tag</em> (Vorgabe 1 % je Tag, unter Betrieb → Stammdaten → Einstellungen):
        So schnell verdunstet kein Kürbis — das ist ein falsches Zettelgewicht oder eine andere Palette, und sie
        steht unter Messungen → Auffälligkeiten zum Berichtigen.</p>
      </Erklaerung>
    </Karte>
  )
}

/* ---------- U4: Verschenkte Marge ------------------------------------------- */

/**
 * Die verschenkte Marge — zwei Arten, Kürbis zu verkaufen, zweimal die Frage,
 * was die Waage darüber hinaus in die Kiste gelegt hat (Runde W).
 *
 *   Kiste ab x kg      Der Kunde zahlt die Kiste zu einem Mindestgewicht
 *                      („ab 8 kg"). Jedes Kilo darüber ist geschenkt. Gemessen
 *                      wird an vollen fertigen Paletten: Netto ÷ Kisten =
 *                      gewogen je Kiste; minus Soll = zu viel je Kiste. Wie
 *                      viele Kürbisse in der Kiste liegen, weiss die Waage
 *                      nicht — und es spielt hier keine Rolle.
 *
 *   x Stück je Kiste   Der Kunde zahlt je Kürbis, nach Kaliber („10 Stück K2,
 *                      900–1200 g"). Bezahlt ist die Bandmitte; jedes Gramm
 *                      darüber ist geschenkt. Gemessen: Netto ÷ (Kisten × Stück)
 *                      = gewogen je Stück; minus Bandmitte.
 *
 * Zwei Blöcke, klar getrennt. Jede Zeile lässt sich aufklappen und zeigt
 * die Wägungen dahinter — nur die zur Zeile passenden („Kaliber 1 anklicken
 * → alle Einträge mit Kaliber 1"), jede mit ihrer Charge und dem Weg zur
 * Arbeit. Der Filter oben entscheidet, ob die Zeilen je Sorte (alle, eine
 * Sorte) oder je Charge (eine Charge) gerechnet sind.
 */
function Marge({ daten, filter, chargen, oeffnen }: { daten: Auswertung; filter: Filter; chargen: Bestand[]; oeffnen: (auftragId: number) => void }) {
  const [auf, setAuf] = useState<Set<string>>(new Set())
  const sorten = new Set(chargen.map(c => c.sorte))
  const imFilter = (m: { sorte: string; charge_nr?: number }) =>
    filter.gruppe === 'gesamt' ? true
    : filter.gruppe === 'sorte' ? m.sorte === filter.schluessel
    : m.charge_nr !== undefined ? String(m.charge_nr) === filter.schluessel : sorten.has(m.sorte)
  // Je Sorte gerechnet (alle, eine Sorte) oder je Charge (eine Charge).
  const zeilen: (MargeWiegung & { charge_nr?: number })[] =
    filter.gruppe === 'charge' ? daten.margeCharge.filter(imFilter) : daten.margeWiegung.filter(imFilter)
  const wiegungen = daten.ausgang.filter(w => w.kistensystem !== null && w.kisten > 0 && imFilter(w))
  const bandName = bandNamen(daten.schemata)
  const von = zeilen.map(z => z.von).filter(Boolean).sort()[0]

  const kiste = zeilen.filter(z => z.kistensystem === 'kiste_ab')
    .sort((a, b) => a.sorte.localeCompare(b.sorte, 'de') || (a.soll_kg_pro_kiste ?? 0) - (b.soll_kg_pro_kiste ?? 0))
  const stueck = zeilen.filter(z => z.kistensystem === 'stueck')
    .sort((a, b) => a.sorte.localeCompare(b.sorte, 'de') || (a.kaliber_idx ?? 0) - (b.kaliber_idx ?? 0) || (a.stueck_je_kiste ?? 0) - (b.stueck_je_kiste ?? 0))
  // 0097: derselbe Index kann in zwei Fassungen zwei Bänder sein — die
  // Grenzen gehören zum Schlüssel, sonst fielen zwei Zeilen zusammen.
  const schluessel = (z: typeof zeilen[number]) =>
    `${z.kistensystem}|${z.sorte}|${z.charge_nr ?? ''}|${z.soll_kg_pro_kiste ?? ''}|${z.kaliber_idx ?? ''}|${z.stueck_je_kiste ?? ''}|${z.band_von_g ?? ''}|${z.band_bis_g ?? ''}`
  // Die Wägungen hinter einer Zeile — dieselbe Auswahl, die die Zeile gerechnet hat.
  const dahinter = (z: typeof zeilen[number]) => wiegungen
    .filter(w => w.sorte === z.sorte && w.kistensystem === z.kistensystem
      && (z.charge_nr === undefined || w.charge_nr === z.charge_nr)
      && (z.kistensystem === 'kiste_ab'
        ? Number(w.soll_kg_pro_kiste) === Number(z.soll_kg_pro_kiste)
        : w.kaliber_idx === z.kaliber_idx && w.stueck_je_kiste === z.stueck_je_kiste
          && (w.band_von_g === undefined || ((w.band_von_g ?? null) === (z.band_von_g ?? null) && (w.band_bis_g ?? null) === (z.band_bis_g ?? null)))))
    .sort((a, b) => a.charge_nr - b.charge_nr || a.ts.localeCompare(b.ts))
  const umschalten = (k: string) => setAuf(s => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n })
  const aufknopf = (k: string, n: number) => (
    <button type="button" className="werkzeug-knopf marge-auf" aria-expanded={auf.has(k)} onClick={() => umschalten(k)}>
      <ZChevron size={14} />{n} {n === 1 ? 'Wägung' : 'Wägungen'}
    </button>
  )
  const arbeitKnopf = (w: AusgangKennzahl) => (
    <button type="button" className="werkzeug-knopf" onClick={() => oeffnen(w.auftrag_id)}>Arbeit</button>
  )

  return (
    <Karte id="urs-marge" titel="Verschenkte Marge">
      {kiste.length === 0 && stueck.length === 0
        ? <Leer titel="Noch keine fertige Palette gewogen">Sobald eine volle fertige Palette gewogen ist — „Kiste ab x kg" oder nach Kaliber —, steht sie hier.</Leer>
        : (
        <>
          {/* Runde AF: der Untertitel ist weg; dass die Zahlen gemessen sind, sagt die Karte selbst (beschriftung.mjs R5). */}
          <p className="leise-satz">Zwei Arten, Kürbis zu verkaufen — und zweimal die Frage, was die Waage über das Bezahlte hinaus in die Kiste gelegt hat. Gemessen <Herkunft art="gemessen" /> an den gewogenen vollen fertigen Paletten.</p>
          <section className="marge-teil" data-block="kiste_ab" id="urs-marge-kiste">
            <h3>Kiste ab x kg</h3>
            <p className="leise">Der Kunde zahlt die Kiste zu einem Mindestgewicht. Jedes Kilo darüber ist geschenkt: Netto der Palette ÷ Kisten = gewogen je Kiste, minus Soll = zu viel je Kiste. Wie viele Kürbisse in der Kiste liegen, weiss die Waage nicht — es spielt hier keine Rolle.</p>
            {kiste.length === 0 ? <p className="leise">Noch keine Palette „Kiste ab x kg" gewogen.</p> : (
              <div className="rollbar"><table className="dicht marge-tabelle">
                {/* Die Spalten heissen wie im Begriffslexikon (pruefstand/begriffe.json). */}
                <thead><tr><th>Sorte</th><th className="zahl">Soll je Kiste</th><th className="zahl">Gewogen je Kiste</th><th className="zahl">Zu viel je Kiste</th><th>Wägungen</th></tr></thead>
                <tbody>{kiste.map(z => {
                  const k = schluessel(z), ws = dahinter(z)
                  return (
                    <Fragment key={k}>
                      <tr>
                        <td className="nowrap"><strong>{z.sorte}</strong>{z.charge_nr !== undefined && <span className="leise"> · Charge {z.charge_nr}</span>}</td>
                        <td className="zahl">{z.soll_kg_pro_kiste?.toFixed(1)} kg</td>
                        <td className="zahl"><strong>{z.kg_je_kiste?.toFixed(2)} kg</strong>
                          {z.sd_je_kiste != null && <span className="leise"> ± {z.sd_je_kiste.toFixed(2)}</span>}</td>
                        <td className={`zahl ${tonVon(z.zuviel_je_kiste, z.soll_kg_pro_kiste)}`}>
                          {z.zuviel_je_kiste != null ? `${z.zuviel_je_kiste > 0 ? '+' : ''}${z.zuviel_je_kiste.toFixed(2)} kg` : '—'}
                          {z.zuviel_je_kiste != null && z.soll_kg_pro_kiste
                            ? <span className="leise"> {prozent(z.zuviel_je_kiste / z.soll_kg_pro_kiste, 0)}</span> : null}
                        </td>
                        <td className="nowrap">{aufknopf(k, z.n_wiegungen)}<span className="leise"> · {zahl(z.kisten)} Kisten</span></td>
                      </tr>
                      {auf.has(k) && (
                        <tr className="marge-dahinter"><td colSpan={5}>
                          <table className="dicht">
                            <thead><tr><th>Datum</th><th>Charge</th><th className="zahl">Kisten</th><th className="zahl">Gewogen je Kiste</th><th className="zahl">Zu viel je Kiste</th><th>Kaliber</th><th></th></tr></thead>
                            <tbody>{ws.map(w => (
                              <tr key={w.id} className={w.voll ? undefined : 'leise'}>
                                <td>{datum(w.ts)}</td>
                                <td>Charge {w.charge_nr}</td>
                                <td className="zahl">{w.kisten}</td>
                                <td className="zahl">{w.kg_pro_kiste != null ? `${w.kg_pro_kiste.toFixed(2)} kg` : '—'}</td>
                                <td className="zahl">{w.ueberfuellung_je_kiste != null ? `${w.ueberfuellung_je_kiste > 0 ? '+' : ''}${w.ueberfuellung_je_kiste.toFixed(2)} kg` : '—'}</td>
                                <td>{bandText(w.kaliber_idx, w.band_von_g ?? z.band_von_g, w.band_bis_g ?? z.band_bis_g) ?? (w.kaliber_idx != null ? bandName(w.sorte, w.kaliber_idx) : '—')}</td>
                                <td className="nowrap">{arbeitKnopf(w)}{!w.voll && <span className="leise"> · nicht voll</span>}</td>
                              </tr>
                            ))}</tbody>
                          </table>
                        </td></tr>
                      )}
                    </Fragment>
                  )
                })}</tbody>
              </table></div>
            )}
          </section>

          <section className="marge-teil" data-block="stueck" id="urs-marge-stueck">
            <h3>x Stück je Kiste</h3>
            <p className="leise">Der Kunde zahlt je Kürbis, nach Kaliber. Bezahlt ist die Bandmitte; jedes Gramm darüber ist geschenkt: Netto der Palette ÷ (Kisten × Stück) = gewogen je Stück, minus Bandmitte. <strong>Bandmitte</strong> heisst hier nicht die Mitte der Grenzen, sondern der Schwerpunkt der Kürbisse dieser Sorte innerhalb des Bandes, aus den Sortierdateien — was der Kunde im Mittel bekommt. Das Band ist das der Fassung, mit der die Arbeit lief: Ändert der Betrieb die Fassung, kann „K1" danach ein anderes Band sein, und die Zeilen bleiben getrennt.</p>
            {stueck.length === 0 ? <p className="leise">Noch keine Palette nach Kaliber gewogen.</p> : (
              <div className="rollbar"><table className="dicht marge-tabelle">
                <thead><tr><th>Sorte</th><th>Kaliber</th><th className="zahl">Je Kiste</th><th className="zahl">Gewogen je Stück</th><th className="zahl">Über Bandmitte</th><th>Wägungen</th></tr></thead>
                <tbody>{stueck.map(z => {
                  const k = schluessel(z), ws = dahinter(z)
                  const mitte = z.band_mittel_g ?? null, g = z.g_je_kuerbis ?? null
                  return (
                    <Fragment key={k}>
                      <tr>
                        <td className="nowrap"><strong>{z.sorte}</strong>{z.charge_nr !== undefined && <span className="leise"> · Charge {z.charge_nr}</span>}</td>
                        <td className="nowrap"><strong>{bandText(z.kaliber_idx, z.band_von_g, z.band_bis_g) ?? bandName(z.sorte, z.kaliber_idx)}</strong>{mitte != null && <span className="leise"> · Mitte {Math.round(mitte)} g</span>}</td>
                        <td className="zahl">{z.stueck_je_kiste} Stück</td>
                        <td className="zahl"><strong>{g != null ? `${Math.round(g)} g` : '—'}</strong></td>
                        <td className={`zahl ${z.g_ueber_bandmitte != null && z.g_ueber_bandmitte > 0 ? 'rot' : ''}`}>
                          {z.g_ueber_bandmitte != null ? `${z.g_ueber_bandmitte > 0 ? '+' : ''}${Math.round(z.g_ueber_bandmitte)} g` : '—'}
                          {z.g_ueber_bandmitte != null && mitte ? <span className="leise"> {prozent(z.g_ueber_bandmitte / mitte, 0)}</span> : null}
                        </td>
                        <td className="nowrap">{aufknopf(k, z.n_wiegungen)}<span className="leise"> · {zahl(z.kisten)} Kisten</span></td>
                      </tr>
                      {auf.has(k) && (
                        <tr className="marge-dahinter"><td colSpan={6}>
                          <table className="dicht">
                            <thead><tr><th>Datum</th><th>Charge</th><th className="zahl">Kisten</th><th className="zahl">Gewogen je Stück</th><th className="zahl">Über Bandmitte</th><th></th></tr></thead>
                            <tbody>{ws.map(w => {
                              const gw = w.kg_pro_kuerbis != null ? w.kg_pro_kuerbis * 1000 : null
                              return (
                                <tr key={w.id} className={w.voll ? undefined : 'leise'}>
                                  <td>{datum(w.ts)}</td>
                                  <td>Charge {w.charge_nr}</td>
                                  <td className="zahl">{w.kisten}</td>
                                  <td className="zahl">{gw != null ? `${Math.round(gw)} g` : '—'}</td>
                                  <td className="zahl">{gw != null && w.band_mittel_g != null ? `${gw - w.band_mittel_g > 0 ? '+' : ''}${Math.round(gw - w.band_mittel_g)} g` : '—'}</td>
                                  <td className="nowrap">{arbeitKnopf(w)}{!w.voll && <span className="leise"> · nicht voll</span>}</td>
                                </tr>
                              )
                            })}</tbody>
                          </table>
                        </td></tr>
                      )}
                    </Fragment>
                  )
                })}</tbody>
              </table></div>
            )}
          </section>
        </>
      )}
      <p className="hilfe">
        Mittel aus allen gewogenen fertigen Paletten{von ? ` seit ${datum(von)}` : ''} <Herkunft art="gemessen" /> —
        nicht auf verkaufte Kisten hochgerechnet. Eine nicht volle Palette (weniger Kisten drauf) zählt je Kiste mit; sie steht als „nicht voll" dabei.
      </p>
    </Karte>
  )
}

/** Runde AD: das Band mit den Grenzen, die die Zeile selbst trägt (aus der
 *  Fassung des Auftrags, 0097) — „K2 · 600–1100 g"; ohne Index das eigene
 *  Band einer Wasch-Arbeit („eigenes Band · 700–900 g"). null, wenn keine Grenzen da sind. */
function bandText(idx: number | null | undefined, von: number | null | undefined, bis: number | null | undefined): string | null {
  if (von == null || bis == null) return null
  return `${idx == null ? 'eigenes Band' : `K${idx + 1}`} · ${zahl(von)}–${zahl(bis)} g`
}

/** Das Kaliber beim Namen: „K2 · 900–1200 g" — aus dem Sortierschema der Sorte.
 *  Nur noch der Ersatz, wenn eine Zeile keine Grenzen trägt (Datenbank vor 0097). */
function bandNamen(schemata: Schema[]): (sorte: string, idx: number | null) => string {
  return (sorte, idx) => {
    if (idx == null) return 'ohne Kaliber'
    const schema = schemata.find(s => s.sorte === sorte && s.art === 'kaliber' && s.kaeufer === null)
      ?? schemata.find(s => s.sorte === sorte && s.art === 'kaliber')
    const band = schema?.kaliber_baender?.[idx]
    return band ? `K${idx + 1} · ${zahl(band[0])}–${zahl(band[1])} g` : `K${idx + 1}`
  }
}

const tonVon = (zuviel: number | null, soll: number | null) =>
  zuviel == null || !soll ? '' : zuviel / soll > 0.05 ? 'rot' : zuviel < 0 ? 'gruen' : ''
