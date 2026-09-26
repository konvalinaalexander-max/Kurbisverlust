import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { Aufklapp, Erklaerung, Herkunft, Hinweis, Karte, Leer, Segmente } from '../components/Bausteine'
import { Anteilsbalken, Linien, type Anteilszeile, type Reihe, type Zone } from '../components/Diagramm'
import { lagerstaende, prognoseBei, schimmelKurve, useAuswertung, wohinVon,
         type Auswertung, type Bestand, type Lagerstand, type MargeCharge, type MargeWiegung, type Schema, type SortenK, type Wohin } from '../auswertung/daten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'

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

  const chargen = useMemo(() => daten ? chargenIm(daten.bestand, filter) : [], [daten, filter])
  const staende = useMemo(() => daten ? lagerstaende(chargen, daten.naechste) : [], [chargen, daten])

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null

  const sorten = [...new Set(daten.bestand.map(b => b.sorte))].sort((a, b) => a.localeCompare(b, 'de'))
  const chargenListe = [...daten.bestand].sort((a, b) => a.charge_nr - b.charge_nr)
  const name = filter.gruppe === 'gesamt' ? 'Alle Chargen'
    : filter.gruppe === 'charge' ? `Charge ${filter.schluessel} · ${chargen[0]?.sorte ?? ''}` : filter.schluessel

  return (
    <>
      <Reiterkopf titel="Ursachen"
                  zweck="Wohin der Kürbis bis heute ging, wo und wann das Faule und die Verdunstung entstanden — und was die Waage verschenkt."
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt} />
      <Probleme liste={daten.probleme} />

      <div className="filterleiste haftend">
        <label htmlFor="uf">Ansicht</label>
        <select id="uf" value={filter.gruppe === 'gesamt' ? '' : `${filter.gruppe}|${filter.schluessel}`}
                onChange={e => setzen(e.target.value)}>
          <option value="">alle Chargen</option>
          <optgroup label="Sorte">{sorten.map(s => <option key={s} value={`sorte|${s}`}>{s}</option>)}</optgroup>
          <optgroup label="Charge">{chargenListe.map(c => <option key={c.charge_nr} value={`charge|${c.charge_nr}`}>{c.charge_nr} · {c.sorte}</option>)}</optgroup>
        </select>
        {filter.gruppe !== 'gesamt' && <span className="aktiv-filter">{name}</span>}
        <span>{chargen.length} {chargen.length === 1 ? 'Charge' : 'Chargen'} · {staende.length} mit Ware im Haus</span>
        {filter.gruppe !== 'gesamt' && <button type="button" className="werkzeug-knopf" onClick={() => setzen('')}>alle zeigen</button>}
      </div>

      <Wohin daten={daten} filter={filter} setzen={setzen} />
      <Faules daten={daten} filter={filter} chargen={chargen} staende={staende} />
      <Verdunstung daten={daten} filter={filter} chargen={chargen} />
      <Marge daten={daten} filter={filter} chargen={chargen} />
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
    hinweis: 'liegt und ist heute verkaufsfähig', felder: ['lager_verkaufsfaehig_kg'] },
  { name: 'verkauft', farbe: 'var(--strom-rest)',
    hinweis: 'ausgeliefert — auf einem Lieferschein', felder: ['geliefert_kg'] },
  { name: 'verdunstet bis heute', farbe: 'var(--strom-verdunstung)',
    hinweis: 'entwichenes Wasser, draussen wie drinnen', felder: ['verdunstet_ausgelagert_kg', 'lager_verdunstet_kg'] },
  { name: 'Faules bis heute', farbe: 'var(--strom-schimmel)',
    hinweis: 'Faules im Lager, vom Feld und beim Abpacken', felder: ['faul_ausgelagert_kg', 'lager_faul_kg', 'sockel_ausgelagert_kg', 'lager_sockel_kg', 'fax_kg', 'lager_fax_kg'] },
  { name: 'zu klein', farbe: 'var(--strom-ausschuss)',
    hinweis: 'an die Tiere — kein Verlust, nur nicht Hauptware', felder: ['klein_ausgelagert_kg', 'lager_klein_kg'] },
  { name: 'zu gross', farbe: 'var(--strom-nebenkanal)',
    hinweis: 'in den Nebenkanal — kein Verlust, nur nicht Hauptware', felder: ['gross_ausgelagert_kg', 'lager_gross_kg'] },
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

function Wohin({ daten, filter, setzen }: { daten: Auswertung; filter: Filter; setzen: (w: string) => void }) {
  const w = wohinVon(daten.wohin, filter.gruppe, filter.schluessel)
  const chargen = chargenIm(daten.bestand, filter)
  const kopf = wohinZeile(w, filter.gruppe === 'gesamt' ? 'Alle Chargen' : filter.gruppe === 'charge' ? `Charge ${filter.schluessel}` : filter.schluessel,
    `${w?.n_chargen ?? chargen.length} ${(w?.n_chargen ?? 0) === 1 ? 'Charge' : 'Chargen'} · ${tonnen(w?.eingang_kg)} Eingang`)

  // Darunter: je Sorte (Filter Alle) oder je Charge (Filter Sorte).
  const unterGruppe = filter.gruppe === 'gesamt' ? 'sorte' : filter.gruppe === 'sorte' ? 'charge' : null
  const zeilen = unterGruppe === 'sorte'
    ? [...new Set(daten.bestand.map(b => b.sorte))].sort().map(s =>
        wohinZeile(wohinVon(daten.wohin, 'sorte', s), s,
          `${daten.bestand.filter(b => b.sorte === s).length} Chargen · ${tonnen(wohinVon(daten.wohin, 'sorte', s)?.eingang_kg)} Eingang`,
          `sorte|${s}`))
    : unterGruppe === 'charge'
    ? chargen.map(c => wohinZeile(wohinVon(daten.wohin, 'charge', String(c.charge_nr)), `Charge ${c.charge_nr}`,
        `${c.sorte} · ${c.schlag} · ${tonnen(c.eingang_kg)} Eingang`, `charge|${c.charge_nr}`))
    : []
  const sortiert = zeilen.filter(z => z.bezug > 0).sort((a, b) => b.verlust - a.verlust)

  return (
    <Karte id="urs-wohin" titel="Wohin ging der Kürbis?"
           unter="Der ganze Eingang, aufgeteilt: was noch gut liegt, was verkauft ist, was verloren ging — alles bis heute.">
      {/* Steht darunter noch eine Liste, trägt die die Legende; steht keine da
          (eine einzelne Charge), muss der Kopfbalken sie selbst tragen — sonst
          ist der Balken bunt und niemand weiss, welcher Streifen was ist. */}
      <Anteilsbalken zeilen={[kopf]} legende={sortiert.length === 0} />
      {sortiert.length > 0 && (
        <>
          <div className="tag-trenner">{unterGruppe === 'sorte' ? 'je Sorte' : 'je Charge'} <span className="leise">nach Verlustanteil</span></div>
          <Anteilsbalken zeilen={sortiert} oeffnen={z => z.ziel && setzen(z.ziel)} />
        </>
      )}
      {(w?.ueberzaehlung_kg ?? 0) > 0 && (
        <p className="fussnote">{tonnen(w?.ueberzaehlung_kg)} mehr geliefert als eingelagert — ein Zählfehler beim Eingang, nicht Ware.</p>
      )}
      <Erklaerung>
        <p>Der Balken ist der ganze Eingang (100 %) <Herkunft art="gemessen" />. Rechts steht der Anteil <strong>echter Verlust</strong> —
        verdunstetes Wasser und Faules; danach sind die Zeilen sortiert.</p>
        <p><strong>Zu klein und zu gross sind kein Verlust.</strong> Die Ware ist nicht weg, nur nicht in der richtigen Grösse:
        Sie geht an die Tiere oder in den Nebenkanal — und sie war es vom Feld an.</p>
      </Erklaerung>
    </Karte>
  )
}

/* ---------- U2: Faules im Lager --------------------------------------------- */

function Faules({ daten, filter, chargen, staende }: {
  daten: Auswertung; filter: Filter; chargen: Bestand[]; staende: Lagerstand[]
}) {
  const [achse, setAchse] = useAchse('urs.palox.achse')
  const imFilter = new Set(chargen.map(c => c.charge_nr))
  const punkte = daten.punkte.filter(p => imFilter.has(p.charge_nr))
  const gute = punkte.filter(p => p.plausibel && p.anteil !== null)
  const schlechte = punkte.filter(p => !p.plausibel && p.anteil !== null)

  // Gruppiert wird eine Ebene feiner als der Filter: alle → je Sorte,
  // eine Sorte → je Charge, eine Charge → eine Reihe.
  const schluesselVon = (p: typeof gute[number]) =>
    filter.gruppe === 'gesamt' ? p.sorte : filter.gruppe === 'sorte' ? `Charge ${p.charge_nr}` : `Charge ${p.charge_nr}`
  const namen = [...new Set(gute.map(schluesselVon))].sort((a, b) => a.localeCompare(b, 'de', { numeric: true }))
  const farbe = farbwahl(namen)
  const eigene = new Set(gute.map(p => p.charge_nr))

  const modell = daten.modell
  const kurve = schimmelKurve(modell)
  const tMax = modell?.t_max ?? 0
  const heute = tagVon(daten.heute)
  const p0 = prognoseBei(daten.prognose, filter.gruppe, filter.schluessel, 0)

  // Je Gruppe die Masse: die grössten bleiben sichtbar, der Rest ist in der
  // Legende ausgeblendet — mehr als zehn Reihen liest niemand.
  const masseJe = new Map<string, number>()
  for (const p of gute) masseJe.set(schluesselVon(p), (masseJe.get(schluesselVon(p)) ?? 0) + p.basis_jetzt_kg)
  const rang = [...masseJe.entries()].sort((a, b) => b[1] - a[1]).map(([n]) => n)
  const sichtbar = new Set(rang.slice(0, 10))

  const reihen: Reihe[] = namen.map(n => ({
    name: `${n}${filter.gruppe === 'gesamt' ? '' : ''}`,
    farbe: farbe(n), marker: true, linie: false, form: 'kreis' as const,
    ausgeblendet: !sichtbar.has(n),
    punkte: gute.filter(p => schluesselVon(p) === n).map(p => ({
      x: achse === 'kalender' ? tagVon(p.messtag) : p.lagertage,
      y: (p.anteil ?? 0) * 100,
      name: `Charge ${p.charge_nr} · ${p.sorte}`,
      text: `${datum(p.messtag)} · liegt seit ${Math.round(p.lagertage)} Tagen · ${kg(p.schimmel_kg, 0)} von ${kg(p.basis_jetzt_kg, 0)} · ${quelleText(p.quelle)}`,
    })),
  })).filter(r => r.punkte.length > 0)

  if (schlechte.length > 0) {
    reihen.push({
      name: 'nicht plausibel — nicht in der Rechnung', farbe: 'var(--text-ganz-leise)', marker: true, linie: false,
      punkte: schlechte.map(p => ({
        x: achse === 'kalender' ? tagVon(p.messtag) : p.lagertage,
        y: Math.min((p.anteil ?? 0) * 100, 100),
        name: `Charge ${p.charge_nr} · ${p.sorte}`,
        text: `${datum(p.messtag)} · ${kg(p.schimmel_kg, 0)} von ${kg(p.basis_jetzt_kg, 0)} · nicht plausibel, siehe Messungen`,
      })),
    })
  }

  // Auf der Lagerdauer-Achse: die Kurve des Modells und die Chargen von heute.
  let zonen: Zone[] = []
  let heuteMarke: { x: number; text?: string; rechts?: string } | undefined
  if (achse === 'liegt' && kurve) {
    const xEnde = Math.max(Math.ceil((tMax + 30) / 30) * 30, 60, ...staende.map(s => s.bis + 30))
    const ts = Array.from({ length: 49 }, (_, i) => (xEnde * i) / 48)
    reihen.unshift({
      name: 'Modell (alle Sorten)', farbe: 'var(--text-leise)', linie: true, marker: false, gestrichelt: true,
      punkte: ts.map(t => ({ x: t, y: kurve(t).mittel * 100 })),
      band: ts.map(t => ({ x: t, unten: kurve(t).unten * 100, oben: kurve(t).oben * 100 })),
    })
    const von = staende.length ? Math.min(...staende.map(s => s.von)) : null
    const bis = staende.length ? Math.max(...staende.map(s => s.bis)) : null
    if (staende.length === 1) {
      heuteMarke = { x: staende[0].alter, text: `heute · ${Math.round(staende[0].alter)} Tage im Lager`,
                     rechts: 'länger gelagert' }
    } else if (von !== null && bis !== null) {
      // Rechts der Zone steht nicht die Zukunft, sondern längere Lagerdauer —
      // deshalb heisst die Marke hier nicht „Prognose" (Ursachen zeigt keine).
      zonen = [{ von, bis, text: `hier liegt die Ware heute (${Math.round(von)}–${Math.round(bis)} Tage)` }]
    }
    if (staende.length > 0) {
      reihen.push({
        name: 'Chargen heute im Lager', farbe: 'var(--kuerbis)', form: 'raute', marker: true, linie: false,
        punkte: staende.map(s => ({
          x: s.alter, y: kurve(s.alter).mittel * 100,
          name: `Charge ${s.charge.charge_nr} · ${s.charge.sorte}`,
          groesse: 3.5 + 3 * Math.sqrt(s.imHaus / Math.max(1, staende[0]?.imHaus ?? 1)),
          text: `liegt seit ${Math.round(s.alter)} Tagen · ${kg(s.imHaus, 0)} im Haus · ${eigene.has(s.charge.charge_nr) ? 'eigene Messung' : 'wie Mittelmass — keine eigene Messung'}`,
        })),
      })
    }
  }

  return (
    <Karte id="urs-palox" titel="Faules im Lager"
           unter="Jede Messung am Palox: wie viel Faules die Ware hatte, als sie an die Maschine kam — nach Datum oder nach Lagerdauer."
           aktion={<Segmente wahl={achse} setzen={setAchse} id="palox-achse"
                             teile={[['kalender', 'Kalender', 'palox-achse-kalender'], ['liegt', 'liegt seit', 'palox-achse-liegt']]} />}>
      {punkte.length === 0
        ? <Leer titel="Noch keine Messung am Palox">Sobald eine Arbeit den Palox zweimal abgelesen hat, steht hier ihr Punkt.</Leer>
        : (
        <Linien reihen={reihen} hoehe={300}
                xTitel={achse === 'kalender' ? 'Messtag' : 'Lagertage'} yTitel="Faules je 100 kg Ware"
                xFormat={achse === 'kalender' ? tagText : x => `${Math.round(x)}`}
                yFormat={y => `${y.toFixed(1)} %`}
                xEinheit={achse === 'kalender' ? 'frei' : 'tage'} yEinheit="prozent" yVon={0}
                xBis={achse === 'kalender' ? heute : undefined}
                heute={achse === 'kalender' ? { x: heute, text: `heute, ${tagText(heute)}`, rechts: '' } : heuteMarke}
                zonen={zonen}
                senkrechte={achse === 'liegt' && kurve && tMax > 0 ? [{ x: tMax, text: 'bis hier gemessen', farbe: 'var(--text-leise)' }] : []}
                leer="noch keine Schimmelmessung"
                fuss={p0?.faul_je_tag_kg != null
                  ? <span className="leise">Rechnung heute: {kg(p0.faul_je_tag_kg, 0)} Faules je Tag an der liegenden Ware (aus dem Modell)</span>
                  : undefined} />
      )}
      <p className="hilfe">
        Jeder Punkt ist eine Ablesung am Palox <Herkunft art="gemessen" /> — die gestrichelte Kurve ist das Modell
        aus allen Ablesungen <Herkunft art="gerechnet" />.{' '}
        Die Lagerdauer ist beim Sortieren und beim Waschen + Sortieren vom Zettel abgelesen; beim Waschen hat die
        Palette aus dem Zwischenlager kein Eingangsdatum mehr — dort ist sie das mittlere Eingangsdatum der Charge,
        also geschätzt. Wie oft welches zutrifft: <Link to="/messungen">Messungen</Link>.
      </p>
      <Erklaerung>
        <p>Gemessen wird der Palox, wenn eine Palette an die Sortiermaschine oder an die Waschstrasse kommt — bezogen auf
        die Masse, die an dem Tag aus dem Lager kam. <strong>Kalender</strong> beantwortet „ab wann ging es los",
        <strong> liegt seit</strong> beantwortet „nach wie vielen Wochen".</p>
        <p>Auf der Lagerdauer läuft die gestrichelte Kurve des Modells mit, an die alle Ware gerechnet wird; die Rauten sind
        die Chargen mit Ware im Haus. Eine Charge ohne eigene Messung liegt auf der Kurve, weil sie wie Mittelmass gerechnet wird — das sagt ihr Feld.</p>
      </Erklaerung>
    </Karte>
  )
}

const quelleText = (q: string) =>
  q === 'lager' ? 'Lagerkontrolle' : q === 'verarbeitung_gemischt' ? 'Arbeit mit mehreren Chargen' : 'an der Maschine'

/* ---------- U3: Verdunstung -------------------------------------------------- */

function Verdunstung({ daten, filter, chargen }: { daten: Auswertung; filter: Filter; chargen: Bestand[] }) {
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
      text: `${datum(w.wiege_ts)} · liegt seit ${Math.round(w.lagertage)} Tagen · ${kg(w.netto_damals_kg, 0)} → ${kg(w.netto_jetzt_kg, 0)}`,
    })),
  })).filter(r => r.punkte.length > 0)

  if (schlechte.length > 0) {
    reihen.push({
      name: 'nicht verwendbar — nicht in der Rate', farbe: 'var(--text-ganz-leise)', marker: true, linie: false,
      punkte: schlechte.map(w => ({
        x: achse === 'kalender' ? tagVon(w.wiege_ts) : w.lagertage,
        y: Math.max((w.rate_pro_tag ?? 0) * 100, 0),
        name: `Charge ${w.charge_nr} · ${w.sorte}`,
        text: `${datum(w.wiege_ts)} · die Palette wurde nicht leichter — die Wägung zählt nicht in die Rate`,
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
           unter="Jede gewogene Palette: wie viel Wasser die Ware je Tag verlor — nach Datum oder nach Lagerdauer."
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
                fuss={<span className="leise">Die Rechnung nimmt je Sorte eine Rate. Fallen die Punkte im Winter sichtbar ab, ist das ein Befund — kein zweites Modell.</span>} />
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
        sie steht grau im Bild, damit niemand sie sucht.</p>
      </Erklaerung>
    </Karte>
  )
}

/* ---------- U4: Verschenkte Marge ------------------------------------------- */

/**
 * Die verschenkte Marge — gegliedert wie der Filter oben (Runde V).
 *
 * Der Betrieb über die zwei alten Karten: „scheusslich … sagt nicht welches
 * kaliber … die messungen übereinander und nicht clever zusammengefasst".
 * Jetzt eine Karte, eine Ebene feiner als die Ansicht:
 *
 *   alle Chargen  →  je Sorte ein Block, ihre Chargen darunter aufklappbar
 *   eine Sorte    →  je Charge ein Block
 *   eine Charge   →  ihre Wägungen
 *
 * In jedem Block stehen die Kiste-ab-Zeilen (Soll, gewogen, zu viel) und die
 * Stück-Zeilen (Kaliber mit seinem Band in Gramm, gewogen je Kürbis, über
 * der Bandmitte). Das Kaliber heisst, was es wiegt: „K2 · 900–1200 g".
 */
function Marge({ daten, filter, chargen }: { daten: Auswertung; filter: Filter; chargen: Bestand[] }) {
  const sorten = new Set(chargen.map(c => c.sorte))
  const imFilter = (m: { sorte: string; charge_nr?: number }) =>
    filter.gruppe === 'gesamt' ? true
    : filter.gruppe === 'sorte' ? m.sorte === filter.schluessel
    : m.charge_nr !== undefined ? String(m.charge_nr) === filter.schluessel : sorten.has(m.sorte)
  const jeSorte = daten.margeWiegung.filter(imFilter)
  const jeCharge = daten.margeCharge.filter(imFilter)
  const bandName = bandNamen(daten.schemata)
  const von = [...jeSorte, ...jeCharge].map(z => z.von).filter(Boolean).sort()[0]

  // Die Blöcke: was der Filter eine Stufe feiner hergibt.
  const bloecke: { schluessel: string; titel: string; unter?: string; zeilen: MargeWiegung[]; chargen?: { nr: number; schlag: string; zeilen: MargeCharge[] }[] }[] = []
  const chargenVon = (sorte: string) => {
    const nrn = [...new Set(jeCharge.filter(z => z.sorte === sorte).map(z => z.charge_nr))].sort((a, b) => a - b)
    return nrn.map(nr => ({ nr, schlag: jeCharge.find(z => z.charge_nr === nr)?.schlag ?? '', zeilen: jeCharge.filter(z => z.charge_nr === nr) }))
  }
  if (filter.gruppe === 'gesamt') {
    for (const sorte of [...new Set(jeSorte.map(z => z.sorte))].sort((a, b) => a.localeCompare(b, 'de'))) {
      bloecke.push({ schluessel: sorte, titel: sorte, zeilen: jeSorte.filter(z => z.sorte === sorte), chargen: chargenVon(sorte) })
    }
  } else if (filter.gruppe === 'sorte') {
    for (const c of chargenVon(filter.schluessel)) {
      bloecke.push({ schluessel: `c${c.nr}`, titel: `Charge ${c.nr}`, unter: c.schlag, zeilen: c.zeilen })
    }
  } else {
    for (const c of chargenVon(chargen[0]?.sorte ?? '')) {
      bloecke.push({ schluessel: `c${c.nr}`, titel: `Charge ${c.nr} · ${chargen[0]?.sorte ?? ''}`, unter: c.schlag, zeilen: c.zeilen })
    }
  }
  const nWiegungen = jeSorte.reduce((s, z) => s + z.n_wiegungen, 0)

  return (
    <Karte id="urs-marge" titel="Verschenkte Marge"
           unter="Was die Kiste über dem Soll hat und der Kürbis über seiner Bandmitte, ist geschenkt — gemessen an den gewogenen vollen fertigen Paletten.">
      {bloecke.length === 0
        ? <Leer titel="Noch keine fertige Palette gewogen">Sobald eine volle fertige Palette gewogen ist — „Kiste ab x kg" oder nach Kaliber —, steht sie hier.</Leer>
        : (
        <>
          {filter.gruppe === 'sorte' && jeSorte.length > 0 && (
            <div className="marge-block" data-block="sorte">
              <h3 className="marge-titel">{filter.schluessel} <span className="leise">· alle Chargen · {nWiegungen} {nWiegungen === 1 ? 'Wägung' : 'Wägungen'}</span></h3>
              <MargeZeilen zeilen={jeSorte} bandName={bandName} />
            </div>
          )}
          {bloecke.map(b => (
            <div className="marge-block" data-block={b.schluessel} key={b.schluessel}>
              <h3 className="marge-titel">{b.titel}{b.unter && <span className="leise"> · {b.unter}</span>}
                <span className="leise"> · {b.zeilen.reduce((s, z) => s + z.n_wiegungen, 0)} {b.zeilen.reduce((s, z) => s + z.n_wiegungen, 0) === 1 ? 'Wägung' : 'Wägungen'}</span></h3>
              <MargeZeilen zeilen={b.zeilen} bandName={bandName} />
              {b.chargen && b.chargen.length > 0 && (
                <Aufklapp titel={<><span>{b.chargen.length === 1 ? 'die Charge dahinter' : `${b.chargen.length} Chargen dahinter`}</span> <span className="leise">dieselben Zahlen, je Charge</span></>}>
                  {b.chargen.map(c => (
                    <div className="marge-charge" key={c.nr}>
                      <h4 className="marge-titel klein">Charge {c.nr}{c.schlag && <span className="leise"> · {c.schlag}</span>}</h4>
                      <MargeZeilen zeilen={c.zeilen} bandName={bandName} />
                    </div>
                  ))}
                </Aufklapp>
              )}
            </div>
          ))}
        </>
      )}
      <p className="hilfe">
        Mittel aus den gewogenen vollen Paletten{von ? ` seit ${datum(von)}` : ''} <Herkunft art="gemessen" /> —
        nicht auf verkaufte Kisten hochgerechnet. Kiste ab: gewogen je Kiste gegen das Soll. Stück: Gramm je Kürbis
        gegen die Bandmitte — sie ist, was der Kunde bezahlt.
      </p>
    </Karte>
  )
}

/** Das Kaliber beim Namen: „K2 · 900–1200 g" — aus dem Sortierschema der Sorte. */
function bandNamen(schemata: Schema[]): (sorte: string, idx: number | null) => string {
  return (sorte, idx) => {
    if (idx == null) return 'ohne Kaliber'
    const schema = schemata.find(s => s.sorte === sorte && s.art === 'kaliber' && s.kaeufer === null)
      ?? schemata.find(s => s.sorte === sorte && s.art === 'kaliber')
    const band = schema?.kaliber_baender?.[idx]
    return band ? `K${idx + 1} · ${zahl(band[0])}–${zahl(band[1])} g` : `K${idx + 1}`
  }
}

/** Die Zeilen eines Blocks: erst Kiste ab (nach Soll), dann Stück (nach Kaliber). */
function MargeZeilen({ zeilen, bandName }: { zeilen: MargeWiegung[]; bandName: (sorte: string, idx: number | null) => string }) {
  const kiste = zeilen.filter(z => z.kistensystem === 'kiste_ab').sort((a, b) => (a.soll_kg_pro_kiste ?? 0) - (b.soll_kg_pro_kiste ?? 0))
  const stueck = zeilen.filter(z => z.kistensystem === 'stueck').sort((a, b) => (a.kaliber_idx ?? 0) - (b.kaliber_idx ?? 0) || (a.stueck_je_kiste ?? 0) - (b.stueck_je_kiste ?? 0))
  const spanne = Math.max(0.5, ...kiste.map(z => Math.abs(z.zuviel_je_kiste ?? 0)))
  return (
    <div className="rollbar"><table className="dicht marge-tabelle">
      {/* Die Spalten heissen wie im Begriffslexikon (pruefstand/begriffe.json):
          „Soll je Kiste", „Gewogen je Kiste", „Zu viel je Kiste". Ein neuer
          Name für dieselbe Grösse ist ein neuer Begriff — und dann weiss
          niemand mehr, ob zwei Zahlen dasselbe meinen. */}
      {kiste.length > 0 && (
        <>
          <thead><tr><th>Kistensystem</th><th className="zahl">Soll je Kiste</th><th className="zahl">Gewogen je Kiste</th><th className="zahl">Zu viel je Kiste</th><th>Wägungen</th></tr></thead>
          <tbody>{kiste.map(z => (
            <tr key={`k${z.soll_kg_pro_kiste}`}>
              {/* Das Soll steht in seiner Spalte; hier nur das System — eine Zahl
                  ohne eigene Beschriftung wäre eine Zahl zu viel (beschriftung.mjs). */}
              <td className="nowrap">Kiste ab x kg</td>
              <td className="zahl">{z.soll_kg_pro_kiste?.toFixed(1)} kg</td>
              <td className="zahl"><strong>{z.kg_je_kiste?.toFixed(2)} kg</strong>
                {z.sd_je_kiste != null && <span className="leise"> ± {z.sd_je_kiste.toFixed(2)}</span>}</td>
              <td className={`zahl ${tonVon(z.zuviel_je_kiste, z.soll_kg_pro_kiste)}`}>
                {z.zuviel_je_kiste != null ? `${z.zuviel_je_kiste > 0 ? '+' : ''}${z.zuviel_je_kiste.toFixed(2)} kg` : '—'}
                {z.zuviel_je_kiste != null && z.soll_kg_pro_kiste
                  ? <span className="leise"> {prozent(z.zuviel_je_kiste / z.soll_kg_pro_kiste, 0)}</span> : null}
              </td>
              <td className="marge-spur-zelle">
                <span className="marge-spur" aria-hidden="true">
                  <span className="marge-null" />
                  <span className={`marge-stab ${(z.zuviel_je_kiste ?? 0) < 0 ? 'minus' : 'plus'}`}
                        style={{ width: `${(Math.abs(z.zuviel_je_kiste ?? 0) / spanne) * 50}%`,
                                 left: (z.zuviel_je_kiste ?? 0) < 0 ? `${50 - (Math.abs(z.zuviel_je_kiste ?? 0) / spanne) * 50}%` : '50%' }} />
                </span>
                <span className="leise nowrap">{z.n_wiegungen} · {zahl(z.kisten)} Kisten</span>
              </td>
            </tr>
          ))}</tbody>
        </>
      )}
      {stueck.length > 0 && (
        <>
          <thead><tr><th>Kaliber</th><th className="zahl">Je Kiste</th><th className="zahl">Gewogen je Stück</th><th className="zahl">Über Bandmitte</th><th>Wägungen</th></tr></thead>
          <tbody>{stueck.map(z => {
            const mitte = z.band_mittel_g ?? null, g = z.g_je_kuerbis ?? null
            // Die Lage im Band: 0 = Unterkante, 1 = Oberkante — die Bandbreite
            // ist die halbe Mitte, wie die Wägung sie sieht.
            const breite = mitte != null ? mitte * 0.5 : null
            const lage = g != null && mitte != null && breite ? Math.min(1, Math.max(0, 0.5 + (g - mitte) / (2 * breite))) : null
            return (
              <tr key={`s${z.kaliber_idx}|${z.stueck_je_kiste}`}>
                <td className="nowrap"><strong>{bandName(z.sorte, z.kaliber_idx)}</strong>
                  {mitte != null && <span className="leise"> · Mitte {Math.round(mitte)} g</span>}</td>
                <td className="zahl">{z.stueck_je_kiste} Stück</td>
                <td className="zahl"><strong>{g != null ? `${Math.round(g)} g` : '—'}</strong></td>
                <td className={`zahl ${z.g_ueber_bandmitte != null && z.g_ueber_bandmitte > 0 ? 'rot' : ''}`}>
                  {z.g_ueber_bandmitte != null ? `${z.g_ueber_bandmitte > 0 ? '+' : ''}${Math.round(z.g_ueber_bandmitte)} g` : '—'}
                </td>
                <td className="marge-spur-zelle">
                  <span className="band-spur" aria-hidden="true" title={mitte != null ? `Bandmitte ${Math.round(mitte)} g` : undefined}>
                    <span className="band-mitte" />
                    {lage !== null && <span className="band-punkt" style={{ left: `${lage * 100}%` }} />}
                  </span>
                  <span className="leise nowrap">{z.n_wiegungen} · {zahl(z.kisten)} Kisten</span>
                </td>
              </tr>
            )
          })}</tbody>
        </>
      )}
    </table></div>
  )
}

const tonVon = (zuviel: number | null, soll: number | null) =>
  zuviel == null || !soll ? '' : zuviel / soll > 0.05 ? 'rot' : zuviel < 0 ? 'gruen' : ''
