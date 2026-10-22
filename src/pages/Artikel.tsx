import { Fragment, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { datum, kg, prozent, tonnen, zahl } from '../lib/format'
import { fehlerText } from '../lib/db'
import { supabase } from '../lib/supabase'
import { useAuth } from '../auth/AuthProvider'
import { Erklaerung, Herkunft, Hinweis, Karte, Kennzahl, Lade, Leer, Marke, Segmente } from '../components/Bausteine'
import { Linien, tonnenAchse, type Reihe } from '../components/Diagramm'
import { artikelGrundlagen, artikelLagerChargeBei, useAuswertung, useStichtag,
         type ArtikelKaliber, type ArtikelLagerCharge, type Bestand, type ChargeLabel, type KundeGruppe, type KundeTag, type PerigonPruefung,
         type SorteGruppe, type Verlaufswoche } from '../auswertung/daten'
import { Ungereimtheiten } from '../auswertung/Ungereimtheiten'
import { Probleme, Rechnet, Reiterkopf } from '../auswertung/Karten'
import { IM_LAGER_TEXT, palettenText } from '../auswertung/lager'
import { WochenFeld } from '../components/WochenFeld'
import { ZChevron, ZHoch, ZRunter, ZStift } from '../components/Zeichen'
import { ARTIKEL_KLASSEN, KLASSEN, OFFEN, gruppenFolge, klasseVon, kundenGruppe, nochZuLiefern, passtGruppe, passtKlasse, passtLabel, passtVerkauf, planSchluessel, rang,
         uebersichtszeilen, type GruppePlan, type GruppeRang, type Klasse, type KundePlan, type RestTeile, type Uebersichtszeile,
         type Wahl } from '../auswertung/artikel'
import { LieferungFenster } from '../betrieb/LieferungFenster'

const TAG = 86400000

/**
 * Lagermanagement nach Artikel — der zweite Lagerreiter (Runde AO, neu
 * gebaut in Runde AP, 12. Oktober).
 *
 *   „Wie viel haben wir Knirps klein noch da, das wir als Demeter verkaufen
 *    können? … Und dann kann ich darauf klicken, und dann sagst du mir im
 *    Dropdown die Chargen an, wie sich die Zahl zusammensetzt. … Knirps
 *    klein, Knirps gross, das sind zwei unterschiedliche Sachen." — und:
 *   „zehn Grafiken, aber alle so mega klein … dann machst du doch lieber, dass
 *    man aussuchen muss, welcher Artikel und welches Label, und dann zeigst
 *    du mir an, wie das bisher gegangen ist."
 *
 * Ein Artikel ist Artikelgruppe × Grösse × Label, wie Perigon ihn führt
 * („Bio Kürbis Knirps Dem klein"). Oben wählt man ihn — Artikel, klein oder
 * gross oder beide, Demeter oder Knospe oder beide —, und alles darunter
 * folgt der Wahl:
 *   1. Wie viel ist von welchem Artikel noch da (Runde AQ): je Artikel ein
 *      Balken — so lang wie sein Eingang, grau, was ausgeliefert ist, orange,
 *      was noch im Lager liegt, blau darin das Verkaufsfähige nach Grösse —,
 *      und dieselben Zahlen als Tabelle. „Mit einer Grafik, nach Artikeln
 *      sortiert, noch im Lager, also Eingang, Ausgang, noch im Lager. Und dann
 *      vielleicht schon auch noch mit Tabelle."
 *   2. Noch da je Artikel und Grösse, in Kisten; ein Klick zeigt die Chargen
 *      dahinter (artikel_lager_charge, 0113).
 *   3. Wie es gegangen ist: EIN grosses Diagramm, kumuliert über die Saison,
 *      diese gegen die Vorjahre — alle Kunden zusammen oder einer (v_kunde_tag).
 *
 * Nichts davon ist eine zweite Rechnung: das Verkaufsfähige ist das der
 * Chargen, nach den Kalibern des Artikels geteilt; die Lieferungen sind die
 * der Perigon-Dateien.
 */

const gruppeName = (g: string | null) =>
  g === null ? 'Artikelgruppe unbekannt' : g === 'Knirps' ? 'Knirps (Hokkaido)' : g
const labelName = (l: string | null) => l === 'D' ? 'Demeter' : l === 'K' ? 'Knospe' : 'Label unbekannt'


// Runde AS: „Was genau ist Verkauf lose?" — lose heisst: verkaufsfähig, aber in
// keinem Kaliber der Artikel; „Grösse offen": keine Sortier-CSV.
// 0121: „lose" heisst jetzt, was es ist — „passt in keinen Artikel"; Unique ist die Hagelware (nur Knospe).
const klasseName = (k: Klasse) =>
  k === 'stueck' ? 'je Stück' : k === 'ausserhalb' ? 'passt in keinen Artikel' : k === 'ohne' ? 'Grösse offen' : k === 'unique' ? 'Unique' : k
const UNIQUE_TEXT = 'Hagelware — nicht faul, nicht klein oder gross: ein eigener Artikel, wird als Knospe verkauft'

const wahlName = (w: Wahl) =>
  `${w.gruppe ? (w.gruppe === 'Knirps' ? 'Knirps' : w.gruppe) : 'alle Artikel'}${w.groesse === 'beide' ? '' : ` ${w.groesse}`}`
  + `${w.label === 'beide' ? '' : ` · ${labelName(w.label)}`}`

const WAHL_SCHLUESSEL = 'artikel.wahl'
function wahlLesen(): Wahl {
  try {
    const w = JSON.parse(localStorage.getItem(WAHL_SCHLUESSEL) ?? 'null') as Partial<Wahl> | null
    if (w && typeof w.gruppe === 'string' && ['beide', 'klein', 'gross'].includes(String(w.groesse))
        && ['beide', 'D', 'K'].includes(String(w.label))) return w as Wahl
  } catch { /* privates Fenster */ }
  return OFFEN
}

interface Grundlagen {
  labels: ChargeLabel[]; gruppen: SorteGruppe[]; kaliber: ArtikelKaliber[]; kunden: KundeTag[]
  kundeGruppe: KundeGruppe[]; plaene: KundePlan[]; pruefung: PerigonPruefung[]
  gruppenRang: GruppeRang[]; gruppenPlaene: GruppePlan[]
}

export default function Artikel() {
  const { daten, laedt, fehler, fortschritt, neuRechnen } = useAuswertung()
  const [wochen, setWochen] = useState(0)
  const lager = useStichtag(artikelLagerChargeBei, 7 * wochen)
  // Die Übersicht zeigt immer heute: Eingang und ausgeliefert gibt es nur bis heute.
  const lagerHeute = useStichtag(artikelLagerChargeBei, 0)
  const [grund, setGrund] = useState<Grundlagen | null>(null)
  const [grundFehler, setGrundFehler] = useState<string | null>(null)
  const [wahl, setWahlRoh] = useState<Wahl>(wahlLesen)
  const { istAdmin } = useAuth()
  const [ladeNr, setLadeNr] = useState(0)
  const setWahl = (w: Wahl) => {
    setWahlRoh(w)
    try { localStorage.setItem(WAHL_SCHLUESSEL, JSON.stringify(w)) } catch { /* privates Fenster */ }
  }
  useEffect(() => {
    let gilt = true
    artikelGrundlagen()
      .then(g => { if (gilt) setGrund(g) })
      .catch((f: unknown) => { if (gilt) setGrundFehler(fehlerText(f)) })
    return () => { gilt = false }
  }, [ladeNr])

  // Runde AS: der Rest des Lagers je Charge, wie die Kaskade ihn teilt (heute) — für die Farben des Balkens.
  // 0121: aus dem Lager-Ausweis — das Faule ohne den Hagel, der Hagel als Unique (Knospe).
  const rest = useMemo(() => new Map<number, RestTeile>((daten?.ausweis ?? [])
    .filter(a => a.verdunstet_kg != null && a.faul_kg != null)
    .map(a => [a.charge_nr, { kanal: Number(a.zu_klein_kg ?? 0) + Number(a.zu_gross_kg ?? 0), faul: Number(a.faul_kg), verdunstet: Number(a.verdunstet_kg),
                              fax: Number(a.fax_kg ?? 0), unique: Number(a.unique_kg ?? 0), bekannt: a.r_bekannt && a.f_bekannt }])),
  [daten?.ausweis])

  const gruppen = useMemo(() => {
    const s = new Set<string>()
    for (const g of grund?.gruppen ?? []) if (g.artikelgruppe) s.add(g.artikelgruppe)
    for (const k of grund?.kunden ?? []) if (k.gruppe) s.add(k.gruppe)
    for (const t of lager.zeilen) if (t.artikelgruppe) s.add(t.artikelgruppe)
    return [...s].sort((a, b) => rang(a) - rang(b) || a.localeCompare(b, 'de'))
  }, [grund, lager.zeilen])

  if (laedt && !daten) return <Rechnet fortschritt={fortschritt} />
  if (fehler) return <Hinweis art="warnung">{fehler}</Hinweis>
  if (!daten) return null

  return (
    <>
      <Reiterkopf titel="Lagermanagement nach Artikel"
                  stand={daten.stand} heute={daten.heute} neuRechnen={() => void neuRechnen()} laeuft={laedt}
                  zeitplan={daten.zeitplan} veraltet={daten.veraltet} aktuell={daten.aktuell} />
      <Probleme liste={daten.probleme} />
      <Ungereimtheiten daten={daten} />
      {grundFehler && <Hinweis art="warnung">Die Zuordnung zu Artikeln liess sich nicht laden: {grundFehler}</Hinweis>}
      {grund && (
        <>
          <Wahlleiste wahl={wahl} setzen={setWahl} gruppen={gruppen} />
          <NochDa bestand={daten.bestand} grund={grund} teile={lager.zeilen} wochen={wochen} wahl={wahl} heute={daten.heute}
                  uebersicht={<Uebersicht bestand={daten.bestand} grund={grund} teileHeute={lagerHeute.zeilen} teile={lager.zeilen} wahl={wahl}
                                          wochen={wochen} setzeWochen={setWochen} stichtag={lager.zeilen[0]?.datum ?? null}
                                          laedt={lager.laedt} lagerFehler={lager.fehler} rest={rest} heute={daten.heute} />} />
          <Verlauf grund={grund} heute={daten.heute} wahl={wahl} lagerHeute={lagerHeute.zeilen} verlauf={daten.verlauf}
                   bestand={daten.bestand} istAdmin={istAdmin} neuLaden={() => setLadeNr(n => n + 1)} />
          <PerigonPruefungen liste={grund.pruefung} />
        </>
      )}
      {!grund && !grundFehler && <Rechnet fortschritt={null} />}
    </>
  )
}

/* ---------- Die Wahl oben: Artikel, Grösse, Label ---------------------------- */

function Wahlleiste({ wahl, setzen, gruppen }: { wahl: Wahl; setzen: (w: Wahl) => void; gruppen: string[] }) {
  const eingeschraenkt = wahl.gruppe !== '' || wahl.groesse !== 'beide' || wahl.label !== 'beide'
  return (
    <div className="filterleiste haftend artikel-wahl" id="artikel-wahl">
      <label htmlFor="artikel-gruppe">Artikel</label>
      <select id="artikel-gruppe" value={wahl.gruppe} onChange={e => setzen({ ...wahl, gruppe: e.target.value })}>
        <option value="">alle Artikel</option>
        {gruppen.map(g => <option key={g} value={g}>{gruppeName(g)}</option>)}
      </select>
      <span className="wahl-teil">
        <span>Grösse</span>
        <Segmente id="artikel-groesse" wahl={wahl.groesse} setzen={g => setzen({ ...wahl, groesse: g })}
                  teile={[['beide', 'beide', 'artikel-groesse-beide'], ['klein', 'klein', 'artikel-groesse-klein'], ['gross', 'gross', 'artikel-groesse-gross']]} />
      </span>
      <span className="wahl-teil">
        <span>Label</span>
        <Segmente id="artikel-label" wahl={wahl.label} setzen={l => setzen({ ...wahl, label: l })}
                  teile={[['beide', 'beide', 'artikel-label-beide'], ['D', 'Demeter', 'artikel-label-d'], ['K', 'Knospe', 'artikel-label-k']]} />
      </span>
      {eingeschraenkt && <button type="button" className="werkzeug-knopf" onClick={() => setzen(OFFEN)}>alle zeigen</button>}
    </div>
  )
}

/* ---------- 1. Was ist noch da? --------------------------------------------- */

/** Je Charge, was sie zu einer Auswahl beiträgt. */
interface Chargenteil { charge_nr: number; sorte: string; label: 'D' | 'K' | null; kg: number; stueck: number | null; klassen: Set<Klasse> }

interface Artikelzeile {
  schluessel: string; gruppe: string | null; klasse: Klasse; label: 'D' | 'K' | null
  kg: number; stueck: number | null; kisten: number | null; stueckJeKiste: number | null
  vonG: number | null; bisG: number | null
  teile: ArtikelLagerCharge[]
}

function artikelzeilen(teile: ArtikelLagerCharge[], wahl: Wahl): Artikelzeile[] {
  const m = new Map<string, Artikelzeile>()
  for (const t of teile) {
    const klasse = klasseVon(t.groesse)
    if (!(Number(t.kg) > 0) || !passtGruppe(wahl, t.artikelgruppe) || !passtLabel(wahl, t.label) || !passtKlasse(wahl, klasse)) continue
    const k = `${t.artikelgruppe ?? ''}|${klasse}|${t.label ?? ''}`
    let z = m.get(k)
    if (!z) {
      z = { schluessel: k, gruppe: t.artikelgruppe, klasse, label: t.label, kg: 0, stueck: null, kisten: null,
            stueckJeKiste: klasse === 'klein' || klasse === 'gross' ? t.stueck_je_kiste : null,
            vonG: t.von_g, bisG: t.bis_g, teile: [] }
      m.set(k, z)
    }
    z.kg += Number(t.kg)
    if (t.stueck != null) z.stueck = (z.stueck ?? 0) + Number(t.stueck)
    z.teile.push(t)
  }
  for (const z of m.values()) z.kisten = z.stueck != null && z.stueckJeKiste ? z.stueck / z.stueckJeKiste : null
  return [...m.values()].sort((a, b) => rang(a.gruppe) - rang(b.gruppe) || (a.gruppe ?? '').localeCompare(b.gruppe ?? '')
                                        || KLASSEN.indexOf(a.klasse) - KLASSEN.indexOf(b.klasse)
                                        || (a.label ?? 'Z').localeCompare(b.label ?? 'Z'))
}

/** Die Teile je Charge zusammengezählt — woraus eine Zahl besteht. */
function jeCharge(teile: ArtikelLagerCharge[]): Chargenteil[] {
  const m = new Map<number, Chargenteil>()
  for (const t of teile) {
    let c = m.get(t.charge_nr)
    if (!c) { c = { charge_nr: t.charge_nr, sorte: t.sorte, label: t.label, kg: 0, stueck: null, klassen: new Set() }; m.set(t.charge_nr, c) }
    c.kg += Number(t.kg)
    if (t.stueck != null) c.stueck = (c.stueck ?? 0) + Number(t.stueck)
    c.klassen.add(klasseVon(t.groesse))
  }
  return [...m.values()].sort((a, b) => b.kg - a.kg)
}

function NochDa({ bestand, grund, teile, wochen, wahl, heute, uebersicht }: {
  bestand: Bestand[]; grund: Grundlagen; teile: ArtikelLagerCharge[]
  wochen: number; wahl: Wahl; heute: string; uebersicht: ReactNode
}) {
  const [zeigeChargen, setZeigeChargen] = useState(false)
  const labelVon = useMemo(() => new Map(grund.labels.map(l => [l.charge_nr, l])), [grund.labels])
  const gruppeVon = useMemo(() => new Map(grund.gruppen.map(g => [g.sorte, g])), [grund.gruppen])
  const chargeVon = useMemo(() => new Map(bestand.map(b => [b.charge_nr, b])), [bestand])
  const zeilen = useMemo(() => artikelzeilen(teile, wahl), [teile, wahl])
  const ausgewaehlt = useMemo(() => zeilen.flatMap(z => z.teile), [zeilen])
  const chargen = useMemo(() => jeCharge(ausgewaehlt), [ausgewaehlt])
  const stichtag = teile[0]?.datum ?? null
  const spaeter = wochen > 0
  const herkunft = spaeter ? 'prognose' : 'gerechnet'
  const gesamt = zeilen.reduce((a, z) => a + z.kg, 0)
  const jeLabel = (l: 'D' | 'K') => zeilen.filter(z => z.label === l).reduce((a, z) => a + z.kg, 0)

  // Die Chargen dahinter, über alle Grössen: Eingang, ausgeliefert, im Lager.
  const dahinter = bestand.filter(b => passtGruppe(wahl, gruppeVon.get(b.sorte)?.artikelgruppe ?? null)
                                    && passtLabel(wahl, labelVon.get(b.charge_nr)?.label ?? null))
  const widerspruch = dahinter.filter(b => (labelVon.get(b.charge_nr)?.n_widerspruch ?? 0) > 0)
  const ohneGruppe = [...new Set(bestand.filter(b => b.lager_kg > 0 && !gruppeVon.get(b.sorte)?.artikelgruppe).map(b => b.sorte))]

  return (
    <>
      <div className="kennzahl-reihe">
        <Kennzahl ton="gruen" id="kz-artikel-gesamt"
                  titel={<>{wahlName(wahl)}: verkaufsfähig {spaeter ? `in ${wochen} Wochen` : 'heute'} <Herkunft art={herkunft} /></>}
                  wert={tonnen(gesamt)}
                  unter={<>
                    noch da
                    {spaeter && stichtag ? <> · am {datum(stichtag).slice(0, 6)}</> : null}
                    {chargen.length > 0 && (
                      <button type="button" className="werkzeug-knopf kennzahl-knopf" id="artikel-chargen-knopf"
                              aria-expanded={zeigeChargen} onClick={() => setZeigeChargen(z => !z)}>
                        aus {chargen.length} {chargen.length === 1 ? 'Charge' : 'Chargen'} <ZChevron size={12} />
                      </button>
                    )}
                  </>} />
        {wahl.label === 'beide' && <>
          <Kennzahl titel={<>davon Demeter <Herkunft art={herkunft} /></>} id="kz-artikel-d" wert={tonnen(jeLabel('D'))}
                    unter={<>{gesamt > 0 ? prozent(jeLabel('D') / gesamt, 0) : '—'} des Verkaufsfähigen</>} />
          <Kennzahl titel={<>davon Knospe <Herkunft art={herkunft} /></>} id="kz-artikel-k" wert={tonnen(jeLabel('K'))}
                    unter={<>{gesamt > 0 ? prozent(jeLabel('K') / gesamt, 0) : '—'} · Demeter darf als Knospe gehen, nicht umgekehrt</>} />
        </>}
        <VerkauftKennzahl kunden={grund.kunden} heute={heute} wahl={wahl} />
      </div>

      {zeigeChargen && chargen.length > 0 && (
        <Karte id="artikel-chargen-wahl" titel={<>Woraus {tonnen(gesamt)} {wahlName(wahl)} bestehen</>}
               aktion={<button type="button" className="werkzeug-knopf" onClick={() => setZeigeChargen(false)}>schliessen</button>}>
          <Chargenliste chargen={chargen} labelVon={labelVon} chargeVon={chargeVon} mitGroesse={wahl.groesse === 'beide'} />
        </Karte>
      )}

      {widerspruch.length > 0 && (
        <Hinweis art="info">
          {widerspruch.length === 1 ? 'Eine Charge wurde' : `${widerspruch.length} Chargen wurden`} als Demeter verkauft, aber als Knospe
          geliefert ({widerspruch.map(b => b.charge_nr).join(', ')}) — {widerspruch.length === 1 ? 'sie zählt' : 'sie zählen'} als Knospe.
          Stimmt das nicht, unter <Link to="/betrieb/stammdaten">Stammdaten → Chargen</Link> Demeter eintragen.
        </Hinweis>
      )}
      {ohneGruppe.length > 0 && (
        <Hinweis art="info">Ohne Artikelgruppe: {ohneGruppe.join(', ')} — in den <Link to="/betrieb/stammdaten">Stammdaten → Sorten</Link> zuordnen.</Hinweis>
      )}

      {uebersicht}
    </>
  )
}

/* ---------- 1. Wie viel ist von welchem Artikel noch da? -------------------- */

/**
 * Runde AS: dieselben Farben wie im Lagermanagement nach Charge — „hier ist
 * es plötzlich grau, blau und pink. Beim anderen war es grün und blau."
 * Grün das Verkaufsfähige, gelb zu klein / zu gross, orange der Palox, blau
 * das Verdunstete; grau, was ausgeliefert ist. Runde AT: „verkauft grau …
 * klein und gross hell und dunkel grün, bei Ursachen ein Grünton in der
 * Mitte" — hell klein, dunkel gross, blass lose (src/design/tokens.css).
 */
const KLASSE_FARBE: Record<Klasse, string> = {
  // Runde AT: hell klein, dunkel gross, die Mitte je Stück — dieselbe Grünfamilie wie Ursachen und Lager nach Charge.
  klein: 'var(--strom-vf-klein)', gross: 'var(--strom-vf-gross)', stueck: 'var(--strom-vf)', unique: 'var(--strom-unique)',
  ausserhalb: 'color-mix(in srgb, var(--strom-vf) 40%, var(--flaeche))',
  ohne: 'color-mix(in srgb, var(--strom-vf) 18%, var(--flaeche))',
}
// 22. Oktober: „Wieso nimmt es die Paloxe noch zum Lager dazu? … vielleicht
// einfach klarer ausweisen — wie viel ist noch hier, im Lager, Anzahl
// Paletten, auch ohne Verdunstung und ohne Palox, und dann wie viel ist
// verkaufsfähig." Der Teil hiess „Palox" — gemeint war das Faule, das beim
// Waschen in den Palox geht; seit Oettli in Paloxen liefert, las man es als
// Gebinde. Jetzt steht das Faule und das Verdunstete hinter dem Lager, blass:
// Es gehört zum Eingang, aber nicht mehr zu dem, was auf den Paletten liegt.
const IM_LAGER: { feld: 'kanal' | 'fax'; name: string; farbe: string; heisst: string }[] = [
  { feld: 'kanal', name: 'zu klein / zu gross', farbe: 'var(--strom-ausschuss)', heisst: 'liegt auf den Paletten, fällt bei der Sortiermaschine heraus — zu klein geht als Tierfutter, zu gross steht auf den Paletten „+2000 g" und geht in einen anderen Kanal' },
  { feld: 'fax', name: 'faul beim Abpacken', farbe: 'var(--strom-schimmel)', heisst: 'liegt auf den Paletten, wird beim Abpacken als faul aussortiert' },
]
const WEG: { feld: 'faul' | 'verdunstet'; name: string; farbe: string; heisst: string }[] = [
  { feld: 'faul', name: 'faul', farbe: 'var(--strom-schimmel)', heisst: 'seit dem Eingang faul geworden — geht beim Waschen in den Palox, zählt nicht mehr zum Lager' },
  { feld: 'verdunstet', name: 'verdunstet', farbe: 'var(--strom-verdunstung)', heisst: 'Wasser, das die Ware seit dem Eingang verloren hat — zählt nicht mehr zum Lager' },
]
/** Was „lose" heisst, in einem Satz — der Betrieb fragte genau das. */
const LOSE_TEXT = 'verkaufsfähig nach der Sortiermaschine, aber leichter oder schwerer als die Kaliber der Artikel klein und gross — wird nicht weggeworfen, geht lose; zählt nicht im Gesamt der Artikel'

function Uebersicht({ bestand, grund, teileHeute, teile, wahl, wochen, setzeWochen, stichtag, laedt, lagerFehler, rest, heute }: {
  bestand: Bestand[]; grund: Grundlagen; teileHeute: ArtikelLagerCharge[]; teile: ArtikelLagerCharge[]; wahl: Wahl
  wochen: number; setzeWochen: (n: number) => void; stichtag: string | null; laedt: boolean; lagerFehler: string | null
  rest: Map<number, RestTeile>; heute: string
}) {
  const [auf, setAuf] = useState<Set<string>>(new Set())
  const labelVon = useMemo(() => new Map(grund.labels.map(l => [l.charge_nr, l])), [grund.labels])
  const gruppeVon = useMemo(() => new Map(grund.gruppen.map(g => [g.sorte, g])), [grund.gruppen])
  const chargeVon = useMemo(() => new Map(bestand.map(b => [b.charge_nr, b])), [bestand])
  const zeilen = useMemo(() => uebersichtszeilen(bestand, labelVon, gruppeVon, teileHeute, wahl, { spaeter: teile, rest }),
                         [bestand, labelVon, gruppeVon, teileHeute, teile, wahl, rest])
  if (zeilen.length === 0) return lagerFehler ? <Hinweis art="warnung">Das Lager je Artikel liess sich nicht laden: {lagerFehler}</Hinweis> : null
  const spaeter = wochen > 0
  const herkunft = spaeter ? 'prognose' : 'gerechnet'
  const max = Math.max(...zeilen.map(z => z.ausgelagert + z.lager), 1)
  const gewaehlt = (kl: Klasse) => passtKlasse(wahl, kl)
  const summe = (f: (z: Uebersichtszeile) => number) => zeilen.reduce((a, z) => a + f(z), 0)
  // Die Grössenspalten der Tabelle: nur, was die Wahl zeigt und was es am Stichtag gibt.
  const spalten = KLASSEN.filter(kl => gewaehlt(kl) && zeilen.some(z => (z.klassenSpaeter.get(kl) ?? 0) > 0))
  // 0121: das Gesamt der Artikel ohne „passt in keinen Artikel" — das steht rechts davon, durch eine Linie getrennt.
  const vfSpaeter = (z: Uebersichtszeile) => spalten.filter(kl => ARTIKEL_KLASSEN.includes(kl)).reduce((a, kl) => a + (z.klassenSpaeter.get(kl) ?? 0), 0)
  const klassenBalken = KLASSEN.filter(kl => zeilen.some(z => (z.klassen.get(kl) ?? 0) > 0))
  const imLagerDa = IM_LAGER.filter(r => zeilen.some(z => z.rest[r.feld] > 0))
  const wegDa = WEG.filter(r => zeilen.some(z => z.rest[r.feld] > 0))
  const offenDa = zeilen.some(z => z.rest.offen > 0)
  const name = (z: Uebersichtszeile) => `${z.gruppe === 'Knirps' ? 'Knirps' : gruppeName(z.gruppe)} · ${labelName(z.label)}`
  // Runde AS: „Reicht, was da ist?" — je Artikel, was die Kunden nach Plan (ohne Plan: das Vorjahr) noch bekommen
  const saison = saisonVon(heute)
  const gesetztGruppe = new Map(grund.kundeGruppe.map(g => [g.kunde, g.gruppe]))
  const noch = (z: Uebersichtszeile) => z.gruppe === null ? null
    : nochZuLiefern(grund.kunden, grund.plaene, saison, { gruppe: z.gruppe, groesse: wahl.groesse, label: z.label ?? 'beide' }, undefined,
                    { von: k => kundenGruppe(k, gesetztGruppe), plaene: grund.gruppenPlaene }).kg
  const umschalten = (k: string) => setAuf(a => { const n = new Set(a); if (n.has(k)) n.delete(k); else n.add(k); return n })
  // Woher Demeter oder Knospe der Chargen mit Ware kommt.
  const quellen = new Map<string, number>()
  for (const z of zeilen) for (const nr of z.chargen) if ((chargeVon.get(nr)?.lager_kg ?? 0) > 0) {
    const q = labelVon.get(nr)?.quelle ?? 'unbekannt'
    quellen.set(q, (quellen.get(q) ?? 0) + 1)
  }

  return (
    <Karte id="artikel-uebersicht" titel="Wie viel ist von welchem Artikel noch da?">
      <div className="uebersicht" role="list">
        {zeilen.map(z => {
          const ganz = z.ausgelagert + z.lager
          const anteil = (v: number, von: number) => `${von > 0 ? Math.max(Math.min((v / von) * 100, 100), 0) : 0}%`
          const vfKlassen = KLASSEN.map(kl => [kl, z.klassen.get(kl) ?? 0] as const).filter(([, v]) => v > 0)
          const lagerTeile = IM_LAGER.map(r => [r, z.rest[r.feld]] as const).filter(([, v]) => v > 0)
          const wegTeile = WEG.map(r => [r, z.rest[r.feld]] as const).filter(([, v]) => v > 0)
          const lagerText = `${z.imLagerHoechstens ? 'höchstens ' : ''}${masse(z.imLager)}`
          const vfHeute = vfKlassen.filter(([kl]) => gewaehlt(kl) && ARTIKEL_KLASSEN.includes(kl)).reduce((a, [, v]) => a + v, 0)
          return (
            <div key={z.schluessel} className="uebersicht-zeile" role="listitem">
              <div className="uebersicht-name">
                <strong>{name(z)}</strong>
                <span className="leise">{z.n} {z.n === 1 ? 'Charge' : 'Chargen'} · Eingang {masse(z.eingang)}</span>
              </div>
              <div className="uebersicht-bahn">
                <div className="uebersicht-spur" style={{ width: anteil(ganz, max) }}
                     aria-label={`Eingang ${masse(z.eingang)}, ausgeliefert ${masse(z.geliefert)}, im Lager ${lagerText}, verkaufsfähig ${masse(z.vf)}, seit Eingang verdunstet oder faul ${masse(z.rest.faul + z.rest.verdunstet)}`}>
                  <span className="uebersicht-teil ausgeliefert" style={{ width: anteil(z.ausgelagert, ganz) }}
                        title={`ausgeliefert ${masse(z.geliefert)} — dafür gingen ${masse(z.ausgelagert)} Eingangsware aus dem Lager`}>
                    {z.ausgelagert / max >= 0.09 && <em>{masse(z.geliefert)}</em>}
                  </span>
                  <span className="uebersicht-lager" style={{ width: anteil(z.imLager, ganz) }} title={`im Lager ${lagerText}: ${IM_LAGER_TEXT}`}>
                    {vfKlassen.map(([kl, v]) => (
                      <span key={kl} className={`uebersicht-teil${gewaehlt(kl) ? '' : ' gedimmt'}`}
                            style={{ width: anteil(v, z.imLager), background: KLASSE_FARBE[kl] }}
                            title={`verkaufsfähig ${klasseName(kl)}: ${masse(v)}`} />
                    ))}
                    {lagerTeile.map(([r, v]) => (
                      <span key={r.feld} className="uebersicht-teil" style={{ width: anteil(v, z.imLager), background: r.farbe }}
                            title={`${r.name}: ${masse(v)} — ${r.heisst}`} />
                    ))}
                    {z.rest.offen > 0 && <span className="uebersicht-teil offen" style={{ width: anteil(z.rest.offen, z.imLager) }}
                                               title={`${masse(z.rest.offen)} ohne Teilung — Verkaufsfähiges unbekannt`} />}
                  </span>
                  {wegTeile.map(([r, v]) => (
                    <span key={r.feld} className="uebersicht-teil weg" style={{ width: anteil(v, ganz), background: r.farbe }}
                          title={`${r.name}: ${masse(v)} — ${r.heisst}`} />
                  ))}
                </div>
                {z.lager > 0 && <span className="uebersicht-lagertext" title={`Im Lager ist ${IM_LAGER_TEXT}`}>
                  im Lager {z.paletten !== null ? `${palettenText(z.paletten)} · ` : ''}{lagerText}</span>}
              </div>
              <div className="uebersicht-wert">
                <strong>{masse(vfHeute)}</strong>
                <span className="leise">verkaufsfähig{wahl.groesse === 'beide' ? '' : ` ${wahl.groesse}`}{z.luecke > 0 ? ` · ${z.luecke} ohne Zahl` : ''}</span>
              </div>
            </div>
          )
        })}
      </div>
      <div className="legende uebersicht-legende">
        <span><span className="chip" style={{ background: 'var(--strom-verkauft)' }} />ausgeliefert</span>
        {klassenBalken.map(kl => (
          <span key={kl} title={kl === 'ausserhalb' ? LOSE_TEXT : kl === 'unique' ? UNIQUE_TEXT : kl === 'ohne' ? 'keine Sortier-CSV der Charge oder Sorte — die Grösse ist offen' : undefined}>
            <span className="chip" style={{ background: KLASSE_FARBE[kl] }} />{kl === 'ausserhalb' || kl === 'unique' ? klasseName(kl) : `verkaufsfähig ${klasseName(kl)}`}</span>
        ))}
        {imLagerDa.map(r => <span key={r.feld} title={r.heisst}><span className="chip" style={{ background: r.farbe }} />{r.name}</span>)}
        {offenDa && <span><span className="chip uebersicht-chip-offen" />im Lager, Teilung unbekannt</span>}
        {wegDa.length > 0 && <span className="leise">· nicht mehr im Lager:</span>}
        {wegDa.map(r => <span key={r.feld} title={r.heisst}><span className="chip weg" style={{ background: r.farbe }} />{r.name}</span>)}
        <span className="leise">· jeder Balken ist so lang wie der Eingang des Artikels</span>
      </div>

      {/* Runde AS: eine Tabelle statt zwei — „du hast einerseits Knirps und
          Demeter oben … und dann unten nochmal Knirps und Demeter, aber
          einfach klein und gross und ausserhalb. Mach das doch gleich
          zusammen." Der Wochenregler gehört nur ihr; die Balken zeigen heute. */}
      <div className="tabellen-kopf">
        <h3>Je Artikel</h3>
        <WochenFeld id="artikel-wochen" wochen={wochen} setzen={setzeWochen} datum={spaeter ? stichtag : null} />
      </div>
      {lagerFehler && <Hinweis art="warnung">Das Lager je Artikel liess sich nicht laden: {lagerFehler}</Hinweis>}
      <div className="rollbar">
        <table className={`dicht umbruch lagertabelle artikeltabelle uebersicht-tabelle${laedt ? ' laedt' : ''}`} id="artikel-uebersicht-tabelle">
          <thead>
            <tr>
              <th rowSpan={2} className="haftend">Artikel</th>
              <th rowSpan={2} className="zahl">Eingang<Herkunft art="gemessen" /></th>
              <th rowSpan={2} className="zahl">ausgeliefert<Herkunft art="gemessen" /></th>
              <th rowSpan={2} className="zahl" title={`Im Lager ist ${IM_LAGER_TEXT}`}>im Lager<Herkunft art="gerechnet" /></th>
              <th colSpan={spalten.length + 1} className={`gruppe${spaeter ? ' spaeter' : ''}`}>
                verkaufsfähig {spaeter ? `in ${wochen} Wochen` : 'heute'}<Herkunft art={herkunft} />
                {spaeter && stichtag ? <span className="leise"> · {datum(stichtag).slice(0, 6)}</span> : null}
              </th>
              <th rowSpan={2} className="zahl" title="Was die Kunden diese Saison nach Plan noch bekommen (ohne Plan: das ganze Vorjahr), weniger das schon Gelieferte">
                noch zu{' '}<br />liefern</th>
            </tr>
            <tr>
              <th className={`zahl summe${spaeter ? ' spaeter' : ''}`}>gesamt</th>
              {spalten.map(kl => (
                <th key={kl} className={`zahl${spaeter ? ' spaeter' : ''}${kl === 'ausserhalb' ? ' neben-kaliber erste' : ''}`}
                    title={kl === 'ausserhalb' ? LOSE_TEXT : kl === 'unique' ? UNIQUE_TEXT : undefined}>{klasseName(kl)}{kl === 'unique' && <span className="kopf-unter">nur Knospe</span>}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {zeilen.map(z => {
              const offen = auf.has(z.schluessel)
              const zc = jeCharge(teile.filter(t => z.chargen.includes(t.charge_nr) && passtKlasse(wahl, klasseVon(t.groesse)) && Number(t.kg) > 0))
              return (
                <Fragment key={z.schluessel}>
                  <tr className={`klickbar${offen ? ' offen' : ''}`} onClick={() => umschalten(z.schluessel)} aria-expanded={offen}>
                    <th scope="row" className="haftend">
                      <span className="chevron" aria-hidden="true"><ZChevron size={14} /></span>
                      <span className="zeilenname">{z.gruppe === 'Knirps' ? 'Knirps' : gruppeName(z.gruppe)}</span>
                      <span className={`zeilenunter label-${z.label ?? 'x'}`}>{labelName(z.label)}<span className="leise"> · {z.n} {z.n === 1 ? 'Charge' : 'Chargen'}</span></span>
                    </th>
                    <td className="zahl">{masse(z.eingang)}</td>
                    <td className="zahl">{z.geliefert > 0 ? masse(z.geliefert) : <span className="leise">—</span>}</td>
                    {/* 0121: zuerst die Paletten, darunter die Kilo darauf — wie unter Chargen. */}
                    <td className="zahl">{z.lager > 0
                      ? <>{z.paletten !== null && <strong>{palettenText(z.paletten)}</strong>}
                          <span className={z.paletten !== null ? 'zelle-unter' : undefined}>{z.imLagerHoechstens && <span className="mini-wort">höchstens </span>}{masse(z.imLager)}</span></>
                      : (z.klassen.get('unique') ?? 0) > 0 ? <span className="leise" title={UNIQUE_TEXT}>Unique</span> : <span className="leise">—</span>}</td>
                    <td className={`zahl summe${spaeter ? ' spaeter' : ''}`}><strong>{z.lager > 0 ? masse(vfSpaeter(z)) : '—'}</strong>
                      {z.luecke > 0 && <span className="zelle-unter">{z.luecke} {z.luecke === 1 ? 'Charge' : 'Chargen'} ohne Zahl</span>}</td>
                    {spalten.map(kl => {
                      const v = z.klassenSpaeter.get(kl) ?? 0
                      const k = grund.kaliber.find(x => x.gruppe === z.gruppe && x.groesse === kl)
                      return <td key={kl} className={`zahl${spaeter ? ' spaeter' : ''}${kl === 'ausserhalb' ? ' neben-kaliber erste' : ''}`}>{v > 0 ? masse(v) : <span className="leise">—</span>}
                        {k && v > 0 && <span className="zelle-unter">{zahl(k.von_g)}–{zahl(k.bis_g)} g</span>}</td>
                    })}
                    {(() => {
                      const n = noch(z), vf = z.lager > 0 ? vfSpaeter(z) : 0
                      if (n === null) return <td className="zahl"><span className="leise">—</span></td>
                      if (n <= 0) return <td className="zahl" title="nach Plan schon alles geliefert"><span className="leise">0</span></td>
                      const fehlt = n - vf
                      return <td className={`zahl${fehlt > 0 ? ' reicht-nicht' : ''}`} title={fehlt > 0 ? `es fehlen ${masse(fehlt)}` : 'reicht'}>
                        {fehlt > 0 && <span className="ausruf" aria-label="reicht nicht">!</span>}{masse(n)}
                        {fehlt > 0 && <span className="zelle-unter">fehlen {masse(fehlt)}</span>}</td>
                    })()}
                  </tr>
                  {offen && (
                    <tr className="artikel-chargen"><td colSpan={6 + spalten.length}>
                      {zc.length === 0 ? <p className="leise unten-0">Keine Charge mit verkaufsfähiger Ware{wahl.groesse === 'beide' ? '' : ` ${wahl.groesse}`}.</p>
                        : <Chargenliste chargen={zc} labelVon={labelVon} chargeVon={chargeVon} mitGroesse={wahl.groesse === 'beide'} />}
                    </td></tr>
                  )}
                </Fragment>
              )
            })}
          </tbody>
          {zeilen.length > 1 && (
            <tfoot><tr>
              <th scope="row" className="haftend">Summe</th>
              <td className="zahl">{masse(summe(z => z.eingang))}</td>
              <td className="zahl">{masse(summe(z => z.geliefert))}</td>
              <td className="zahl">{zeilen.some(z => z.imLagerHoechstens && z.lager > 0) && <span className="mini-wort">höchstens </span>}{masse(summe(z => z.imLager))}
                {zeilen.some(z => z.paletten !== null) && <span className="zelle-unter">{palettenText(summe(z => z.paletten ?? 0))}</span>}</td>
              <td className={`zahl summe${spaeter ? ' spaeter' : ''}`}><strong>{masse(summe(vfSpaeter))}</strong></td>
              {spalten.map(kl => <td key={kl} className={`zahl${spaeter ? ' spaeter' : ''}${kl === 'ausserhalb' ? ' neben-kaliber erste' : ''}`}>{masse(summe(z => z.klassenSpaeter.get(kl) ?? 0))}</td>)}
              <td className="zahl">{masse(summe(z => noch(z) ?? 0))}</td>
            </tr></tfoot>
          )}
        </table>
      </div>
      {quellen.size > 0 && (
        <p className="hilfe" id="artikel-dahinter">
          Demeter oder Knospe der Chargen mit Ware: {[...quellen.entries()].map(([q, n]) => `${n} ${quelleText(q)}`).join(', ')}.
        </p>
      )}
      <Erklaerung titel="Wie diese Zahlen entstehen">
        <p>Ein Artikel ist hier die Artikelgruppe mit dem Label der Charge — „Knirps · Demeter" sind alle Demeter-Chargen, deren Sorte als
        Knirps verkauft wird; ein Klick auf die Zeile zeigt sie. <strong>Eingang</strong> und <strong>ausgeliefert</strong> sind gewogen bzw.
        vom Lieferschein <Herkunft art="gemessen" />, <strong>im Lager</strong> ist die Eingangsware, die noch nicht ausgeliefert ist, und
        <strong> verkaufsfähig</strong> das, was davon nach Verdunstung, Palox und zu klein/zu gross bleibt <Herkunft art="gerechnet" /> —
        dieselben Zahlen und Farben wie im Lagermanagement nach Charge.</p>
        <p>Das Verkaufsfähige ist nach der Sortier-CSV der Charge (oder ihrer Sorte) auf die Kaliber der Artikel geteilt, jeder Kürbis um die
        gemessene Verdunstung bis zum Stichtag geschrumpft: Wiegt er so viel wie ein kleiner Artikel, zählt er klein, wie ein grosser, gross.
        <strong> Lose</strong> heisst {LOSE_TEXT} — es gehört weder zu „zu klein / zu gross" (das fällt beim Sortieren heraus) noch zu den
        Artikeln. <strong>Grösse offen</strong>: für die Charge und ihre Sorte gibt es keine Sortier-CSV. Kaliber (Coop 2026):{' '}
        {grund.kaliber.filter(k => k.groesse !== 'stueck').slice(0, 2).map(k => `${k.gruppe} ${k.groesse} ${zahl(k.von_g)}–${zahl(k.bis_g)} g`).join(', ')} …</p>
        <p>Die Balken zeigen heute; der Wochenregler verschiebt nur die Spalten „verkaufsfähig" der Tabelle. Eingang und ausgeliefert gibt es nur
        je Artikelgruppe, nicht je Grösse — beim Eingang ist noch nichts sortiert.</p>
      </Erklaerung>
    </Karte>
  )
}

const quelleText = (q: string) =>
  q === 'Perigon' ? 'aus Perigon' : q === 'Produzent' ? 'vom Produzenten' : q === 'angenommen' ? 'angenommen (Knospe)'
    : q === 'Stammdaten' ? 'aus den Stammdaten' : 'unbekannt'

/** Die Chargen hinter einer Zahl — der „Dropdown", den der Betrieb wollte. */
function Chargenliste({ chargen, labelVon, chargeVon, mitGroesse }: {
  chargen: Chargenteil[]; labelVon: Map<number, ChargeLabel>; chargeVon: Map<number, Bestand>; mitGroesse: boolean
}) {
  return (
    <div className="rollbar">
      {/* Vier Spalten — auf dem Handy bleibt so das Kilo im Bild: Sorte und
          Feld stehen unter der Nummer, die Herkunft des Labels darunter. */}
      <table className="dicht chargenliste">
        <thead><tr>
          <th>Charge</th><th>Label</th>
          <th className="zahl">verkaufsfähig<Herkunft art="gerechnet" /></th>
          <th className="zahl">≈ Stück</th>
        </tr></thead>
        <tbody>{chargen.map(c => {
          const l = labelVon.get(c.charge_nr)
          const feld = chargeVon.get(c.charge_nr)?.schlag
          return (
            <tr key={c.charge_nr}>
              <td><Link to={`/chargen?charge=${c.charge_nr}`}>{c.charge_nr}</Link>
                <span className="zelle-unter">{c.sorte}{feld ? ` · ${feld}` : ''}</span></td>
              <td>{labelName(c.label)}
                {l?.quelle && <span className="zelle-unter">{quelleText(l.quelle)}</span>}
                {(l?.n_widerspruch ?? 0) > 0 && <Marke art="warnung">als Demeter verkauft, als Knospe geliefert</Marke>}</td>
              <td className="zahl">{kg(c.kg, 0)}
                {mitGroesse && <span className="zelle-unter">{KLASSEN.filter(k => c.klassen.has(k)).map(klasseName).join(', ')}</span>}</td>
              <td className="zahl">{c.stueck != null ? zahl(Math.round(c.stueck)) : '—'}</td>
            </tr>
          )
        })}</tbody>
      </table>
    </div>
  )
}

const masse = (v: number | null | undefined) =>
  v === null || v === undefined ? '—' : Math.abs(v) >= 1000 ? tonnen(v) : kg(v, 0)

/* ---------- 2. Wie ist es gegangen? ------------------------------------------ */

/** Die Saison läuft vom 1. Juli bis zum 30. Juni (wie saison_von, 0112). */
const saisonVon = (d: string) => { const j = Number(d.slice(0, 4)), m = Number(d.slice(5, 7)); return m >= 7 ? j : j - 1 }
const saisonTag = (d: string, saison: number) => Math.round((Date.parse(d) - Date.UTC(saison, 6, 1)) / TAG)
const saisonText = (s: number) => `${s}/${String(s + 1).slice(2)}`
const tagText = (saison: number) => (t: number) => {
  const d = new Date(Date.UTC(saison, 6, 1) + t * TAG)
  return `${d.getUTCDate()}.${d.getUTCMonth() + 1}.`
}

interface Kurve {
  kunde: string
  /** je Saison die kumulierte Menge über den Saisontagen. */
  saisons: Map<number, { tag: number; kum: number }[]>
  summe: Map<number, number>
  bisHeute: Map<number, number>
}

/** Aus Lieferungen (schon gefiltert) die kumulierte Kurve je Saison. */
function kurveAus(kunde: string, zeilen: KundeTag[], saison: number, tagHeute: number): Kurve {
  const jeSaison = new Map<number, Map<number, number>>()
  for (const k of zeilen) {
    const tage = jeSaison.get(k.saison) ?? new Map<number, number>()
    const t = saisonTag(k.datum, k.saison)
    tage.set(t, (tage.get(t) ?? 0) + Number(k.kg))
    jeSaison.set(k.saison, tage)
  }
  const saisons = new Map<number, { tag: number; kum: number }[]>()
  const summe = new Map<number, number>(), bisHeute = new Map<number, number>()
  for (const [s, tage] of jeSaison) {
    let kum = 0, kumHeute = 0
    const punkte = [{ tag: 0, kum: 0 }]
    for (const [t, kgTag] of [...tage.entries()].sort((a, b) => a[0] - b[0])) {
      kum += kgTag; punkte.push({ tag: t, kum })
      if (t <= tagHeute) kumHeute = kum
    }
    // Die Vorjahre laufen bis zum Saisonende weiter — „die vergangene Zukunft".
    if (s < saison) punkte.push({ tag: 364, kum })
    saisons.set(s, punkte); summe.set(s, kum); bisHeute.set(s, kumHeute)
  }
  return { kunde, saisons, summe, bisHeute }
}

function useVerkauf(kunden: KundeTag[], heute: string, wahl: Wahl) {
  const saison = saisonVon(heute)
  const tagHeute = saisonTag(heute, saison)
  const passend = useMemo(() => kunden.filter(k => k.saison >= saison - 2 && k.saison <= saison
    && passtGruppe(wahl, k.gruppe) && passtLabel(wahl, k.label) && passtVerkauf(wahl, k.groesse)), [kunden, wahl, saison])
  const alle = useMemo(() => kurveAus('alle Kunden', passend, saison, tagHeute), [passend, saison, tagHeute])
  const jeKunde = useMemo(() => {
    const m = new Map<string, KundeTag[]>()
    for (const k of passend) m.set(k.kunde, [...(m.get(k.kunde) ?? []), k])
    return [...m.entries()].map(([kunde, z]) => kurveAus(kunde, z, saison, tagHeute))
      .sort((a, b) => Math.max(b.summe.get(saison - 1) ?? 0, b.summe.get(saison) ?? 0)
                    - Math.max(a.summe.get(saison - 1) ?? 0, a.summe.get(saison) ?? 0))
  }, [passend, saison, tagHeute])
  return { saison, tagHeute, alle, jeKunde, passend, mitVorjahr: kunden.some(k => k.saison < saison) }
}

function VerkauftKennzahl({ kunden, heute, wahl }: { kunden: KundeTag[]; heute: string; wahl: Wahl }) {
  const { saison, alle } = useVerkauf(kunden, heute, wahl)
  const jetzt = alle.bisHeute.get(saison) ?? 0
  const vorjahr = alle.bisHeute.get(saison - 1) ?? 0
  return (
    <Kennzahl titel={<>ausgeliefert {saisonText(saison)} bis heute <Herkunft art="gemessen" /></>} id="kz-artikel-verkauft"
              wert={tonnen(jetzt)}
              unter={vorjahr > 0
                ? <>Vorjahr bis heute {tonnen(vorjahr)} · {jetzt >= vorjahr ? '+' : '−'}{prozent(Math.abs(jetzt / vorjahr - 1), 0)}</>
                : <>kein Vorjahr zum Vergleich</>} />
  )
}

/** Eine Position der Liste je Kunde (v_kunde_position, 0116). */
interface KundePosition {
  quelle: string; pos_id: number; datum: string; saison: number; gruppe: string | null; groesse: string; label: string | null
  artikel: string; menge: number | null; einheit: string | null; kg: number | null
}

/**
 * Wie ist es gegangen — und reicht, was da ist? (Runde AO, umgebaut in Runde AS)
 *
 *   „[der grösste Einzelkunde], Migros, Coop und Kleinkunden … dass ich Coop als Ganzes sehe,
 *    und wenn ich klicke, die einzelnen Kunden." — „Wir möchten mit
 *    Planmengen arbeiten … ein Stift, und ich gebe die Planmenge ein; solange
 *    keine steht, nimm das Vorjahr, aber grau." — „Reicht, was da ist?" —
 *    „beim Kunden-Diagramm den Lagerbestand des Artikels als eigene Linie."
 *
 * Die Tabelle: je Gruppe eine Zeile (aufklappbar zu den Kunden), dazu Plan,
 * erreicht und noch zu liefern; darunter die Summe gegen das Verkaufsfähige
 * im Lager. Das Diagramm zeigt, was gewählt ist — alle, eine Gruppe oder
 * einen Kunden —, und auf Wunsch das Verkaufsfähige des Artikels über die
 * Saison. Unter einem gewählten Kunden stehen seine Lieferungen; ein Klick
 * zeigt die ganze Perigon-Zeile.
 */
function Verlauf({ grund, heute, wahl, lagerHeute, verlauf, bestand, istAdmin, neuLaden }: {
  grund: Grundlagen; heute: string; wahl: Wahl; lagerHeute: ArtikelLagerCharge[]; verlauf: Verlaufswoche[]; bestand: Bestand[]
  istAdmin: boolean; neuLaden: () => void
}) {
  const kunden = grund.kunden
  const [auswahl, setAuswahl] = useState('')          // '' alle · 'g:Gruppe' · 'k:Kunde'
  const [auf, setAuf] = useState<Set<string>>(new Set())
  const [lagerLinie, setLagerLinie] = useState(true)
  const [planOffen, setPlanOffen] = useState<string | null>(null)
  const [gruppeOffen, setGruppeOffen] = useState<string | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const { saison, tagHeute, alle, jeKunde, passend, mitVorjahr } = useVerkauf(kunden, heute, wahl)
  const gesetzt = useMemo(() => new Map(grund.kundeGruppe.map(g => [g.kunde, g.gruppe])), [grund.kundeGruppe])
  const gruppeVon = (k: string) => kundenGruppe(k, gesetzt)
  // Runde AT: je Kunde und je Gruppe — eine Gruppe mit eigenem Plan gilt als Ganzes.
  const ziel = useMemo(() => nochZuLiefern(kunden, grund.plaene, saison, wahl, undefined, { von: gruppeVon, plaene: grund.gruppenPlaene }),
                       [kunden, grund.plaene, grund.gruppenPlaene, saison, wahl, gesetzt])  // eslint-disable-line react-hooks/exhaustive-deps
  const offenJe = ziel.jeKunde

  // Die Gruppen mit ihren Kunden — in der Reihenfolge des Betriebsleiters (kunde_gruppe_rang, 0117),
  // sonst die grösste zuerst, Kleinkunden zuletzt; die Kunden einer Gruppe die grössten zuerst.
  const gruppen = useMemo(() => {
    const m = new Map<string, Kurve[]>()
    const namen = new Set([...jeKunde.map(k => k.kunde), ...offenJe.keys()])
    for (const n of namen) {
      const k = jeKunde.find(x => x.kunde === n) ?? { kunde: n, saisons: new Map(), summe: new Map(), bisHeute: new Map() }
      m.set(gruppeVon(n), [...(m.get(gruppeVon(n)) ?? []), k])
    }
    for (const g of ziel.jeGruppe.keys()) if (!m.has(g)) m.set(g, [])
    const menge = (ks: Kurve[]) => ks.reduce((a, k) => a + Math.max(k.summe.get(saison - 1) ?? 0, k.summe.get(saison) ?? 0), 0)
    const folge = gruppenFolge([...m.entries()].map(([name, ks]) => ({ name, menge: menge(ks) })), grund.gruppenRang)
    return folge.map(name => {
      const ks = m.get(name) ?? []
      return { name, kunden: ks, kurve: kurveAus(name, passend.filter(p => ks.some(k => k.kunde === p.kunde)), saison, tagHeute) }
    })
  }, [jeKunde, offenJe, ziel, passend, saison, tagHeute, gesetzt, grund.gruppenRang])  // eslint-disable-line react-hooks/exhaustive-deps

  const gewaehlt = auswahl.startsWith('k:') ? jeKunde.find(k => k.kunde === auswahl.slice(2)) ?? null
    : auswahl.startsWith('g:') ? gruppen.find(g => g.name === auswahl.slice(2))?.kurve ?? null : alle
  const titel = auswahl ? auswahl.slice(2) : 'alle Kunden'
  const leer = jeKunde.length === 0 && offenJe.size === 0 && ziel.jeGruppe.size === 0

  // Das Verkaufsfähige des Artikels heute, und über die Saison (orange Linie)
  const vfHeute = useMemo(() => lagerHeute.filter(t => passtGruppe(wahl, t.artikelgruppe) && passtLabel(wahl, t.label) && passtKlasse(wahl, klasseVon(t.groesse)))
    .reduce((a, t) => a + Number(t.kg), 0), [lagerHeute, wahl])
  const lagerReihe = useMemo(() => lagerUeberSaison(verlauf, lagerHeute, bestand, grund, wahl, saison, tagHeute),
                             [verlauf, lagerHeute, bestand, grund, wahl, saison, tagHeute])
  const summeOffen = ziel.kg

  /** Den Plan eines Kunden oder einer ganzen Gruppe setzen — leer heisst: wieder ohne. */
  async function planSetzen(art: 'kunde' | 'gruppe', name: string, kgWert: number | null) {
    setFehler(null)
    const s = planSchluessel(wahl)
    const r = art === 'kunde'
      ? (kgWert === null
          ? await supabase.from('kunde_plan').delete().match({ saison, kunde: name, ...s })
          : await supabase.from('kunde_plan').upsert({ saison, kunde: name, ...s, kg: kgWert }, { onConflict: 'saison,kunde,artikelgruppe,groesse,label' }))
      : (kgWert === null
          ? await supabase.from('gruppe_plan').delete().match({ saison, gruppe: name, ...s })
          : await supabase.from('gruppe_plan').upsert({ saison, gruppe: name, ...s, kg: kgWert }, { onConflict: 'saison,gruppe,artikelgruppe,groesse,label' }))
    if (r.error) setFehler(fehlerText(r.error)); else { setPlanOffen(null); neuLaden() }
  }
  async function gruppeSetzen(kunde: string, gruppe: string | null) {
    setFehler(null)
    const r = gruppe === null
      ? await supabase.from('kunde_gruppe').delete().eq('kunde', kunde)
      : await supabase.from('kunde_gruppe').upsert({ kunde, gruppe }, { onConflict: 'kunde' })
    if (r.error) setFehler(fehlerText(r.error)); else { setGruppeOffen(null); neuLaden() }
  }
  /** Runde AT: eine Gruppe eine Stelle nach oben oder unten — gespeichert wird die ganze Reihenfolge. */
  async function verschieben(name: string, schritt: -1 | 1) {
    const folge = gruppen.map(g => g.name)
    const i = folge.indexOf(name), j = i + schritt
    if (i < 0 || j < 0 || j >= folge.length) return
    ;[folge[i], folge[j]] = [folge[j], folge[i]]
    setFehler(null)
    const r = await supabase.from('kunde_gruppe_rang').upsert(folge.map((gruppe, k) => ({ gruppe, rang: k + 1 })), { onConflict: 'gruppe' })
    if (r.error) setFehler(fehlerText(r.error)); else neuLaden()
  }

  /** Die Zahlen einer Zeile: diese Saison, Vorjahr bis heute, Plan, erreicht, noch zu liefern. */
  const zahlen = (k: Kurve, plan: { plan: number; eigen: boolean | 'teils'; offen: number } | undefined) => {
    const jetzt = k.bisHeute.get(saison) ?? 0
    const vorjahrBis = k.bisHeute.get(saison - 1) ?? 0
    const planKg = plan?.plan ?? 0
    return { jetzt, vorjahrBis, planKg, eigen: plan?.eigen ?? false, offen: plan?.offen ?? 0, erreicht: planKg > 0 ? jetzt / planKg : null }
  }
  const zellen = (z: ReturnType<typeof zahlen>, planZelle: ReactNode) => (
    <>
      <td className="zahl"><strong>{masse(z.jetzt)}</strong></td>
      <td className="zahl">{z.vorjahrBis > 0 ? masse(z.vorjahrBis) : '—'}
        {z.vorjahrBis > 0 && z.jetzt > 0 && <span className="zelle-unter">{z.jetzt >= z.vorjahrBis ? '+' : '−'}{prozent(Math.abs(z.jetzt / z.vorjahrBis - 1), 0)}</span>}</td>
      {planZelle}
      <td className="erreicht">{z.erreicht === null ? <span className="leise">kein Plan</span> : (
        <span className="erreicht-balken" title={`${prozent(z.erreicht, 0)} des Plans`}>
          <span style={{ width: `${Math.min(z.erreicht, 1) * 100}%` }} className={z.erreicht >= 1 ? 'voll' : ''} />
          <em>{prozent(z.erreicht, 0)}</em>
        </span>)}</td>
      <td className="zahl">{z.offen > 0 ? <strong>{masse(z.offen)}</strong> : <span className="leise">0</span>}</td>
    </>
  )
  const planZelle = (art: 'kunde' | 'gruppe', name: string, z: ReturnType<typeof zahlen>, unter: string | null, ungezaehlt = false) => (
    <td className={`zahl plan${z.eigen === false || ungezaehlt ? ' plan-vorjahr' : ''}`}>
      {planOffen === `${art}:${name}`
        ? <PlanFeld kg={z.planKg} eigen={z.eigen !== false} setzen={kgWert => void planSetzen(art, name, kgWert)} abbrechen={() => setPlanOffen(null)} />
        : <><span className="plan-wert">{z.planKg > 0 ? masse(z.planKg) : '—'}
            {istAdmin && (
              <button type="button" className="werkzeug-knopf stift" aria-label={`Plan für ${art === 'gruppe' ? 'die Gruppe ' : ''}${name} setzen`}
                      title={art === 'gruppe' ? 'Planmenge für die ganze Gruppe eintragen' : 'Planmenge eintragen'}
                      onClick={e => { e.stopPropagation(); setPlanOffen(`${art}:${name}`) }}><ZStift size={14} /></button>
            )}</span>
            {unter && <span className="zelle-unter">{unter}</span>}</>}
    </td>
  )
  const planUnter = (eigen: boolean | 'teils', planKg: number) =>
    planKg <= 0 ? null : eigen === false ? 'Vorjahr' : eigen === 'teils' ? 'teils Plan' : null

  const gruppenZeile = (g: (typeof gruppen)[number], i: number) => {
    const offenG = ziel.jeGruppe.get(g.name)
    const z = zahlen(g.kurve, offenG)
    const schl = `g:${g.name}`
    const auf_ = auf.has(g.name)
    return (
      <tr key={schl} className={`klickbar kundengruppe${auswahl === schl ? ' aktiv' : ''}`} aria-expanded={auf_} aria-selected={auswahl === schl}
          onClick={() => {
            setAuswahl(auswahl === schl ? '' : schl)
            setAuf(a => { const n = new Set(a); if (n.has(g.name)) n.delete(g.name); else n.add(g.name); return n })
          }}
          title="die Kunden der Gruppe zeigen und die Gruppe im Diagramm">
        <td>
          <span className="gruppe-kopf">
            <span className="chevron" aria-hidden="true"><ZChevron size={14} /></span>
            <strong>{g.name}</strong>
            <span className="leise">{g.kunden.length} {g.kunden.length === 1 ? 'Kunde' : 'Kunden'}</span>
            {istAdmin && gruppen.length > 1 && (
              <span className="reihenfolge" onClick={e => e.stopPropagation()}>
                <button type="button" className="werkzeug-knopf" disabled={i === 0} aria-label={`${g.name} nach oben`} title="eine Stelle nach oben"
                        onClick={() => void verschieben(g.name, -1)}><ZHoch size={14} /></button>
                <button type="button" className="werkzeug-knopf" disabled={i === gruppen.length - 1} aria-label={`${g.name} nach unten`} title="eine Stelle nach unten"
                        onClick={() => void verschieben(g.name, 1)}><ZRunter size={14} /></button>
              </span>
            )}
          </span>
        </td>
        {zellen(z, planZelle('gruppe', g.name, z, offenG?.gruppenplan ? 'Plan der Gruppe' : z.planKg > 0 ? (z.eigen === false ? 'Vorjahr' : 'Summe der Kunden') : null))}
      </tr>
    )
  }

  const kundenZeile = (k: Kurve, gruppenplan: boolean) => {
    const z = zahlen(k, offenJe.get(k.kunde))
    const schl = `k:${k.kunde}`
    const offen = auswahl === schl
    return (
      <Fragment key={schl}>
        <tr className={`klickbar kunde-in-gruppe${offen ? ' aktiv' : ''}`} aria-expanded={offen} aria-selected={offen}
            onClick={() => setAuswahl(offen ? '' : schl)}
            title={offen ? 'Lieferungen schliessen' : 'im Diagramm zeigen und darunter die Lieferungen'}>
          <td>
            <span className="kunde-name">
              <span className="chevron klein" aria-hidden="true"><ZChevron size={12} /></span>
              {k.kunde}
              {istAdmin && <button type="button" className="werkzeug-knopf gruppe-knopf" aria-label={`Gruppe von ${k.kunde} ändern`} title="Gruppe ändern"
                                   onClick={e => { e.stopPropagation(); setGruppeOffen(gruppeOffen === k.kunde ? null : k.kunde) }}>{gruppeVon(k.kunde)}</button>}
            </span>
            {gruppeOffen === k.kunde && (
              <GruppeWahl kunde={k.kunde} jetzt={gruppeVon(k.kunde)} gesetzt={gesetzt.has(k.kunde)}
                          gruppen={[...new Set<string>([...gruppen.map(g => g.name), 'Migros', 'Coop', 'Kleinkunden', ...gesetzt.values()])]}
                          setzen={g => void gruppeSetzen(k.kunde, g)} abbrechen={() => setGruppeOffen(null)} />
            )}
          </td>
          {zellen(z,
                  planZelle('kunde', k.kunde, z, gruppenplan && z.planKg > 0 ? 'Gruppenplan gilt' : planUnter(z.eigen, z.planKg), gruppenplan))}
        </tr>
        {offen && (
          <tr className="lieferungen-zeile">
            <td colSpan={6}><Lieferungen kunde={k.kunde} saison={saison} wahl={wahl} /></td>
          </tr>
        )}
      </Fragment>
    )
  }

  const summenZahlen = zahlen(alle, { plan: [...ziel.jeGruppe.values()].reduce((a, g) => a + g.plan, 0),
                                      eigen: [...ziel.jeGruppe.values()].every(g => g.eigen === true) ? true
                                        : [...ziel.jeGruppe.values()].some(g => g.eigen !== false) ? 'teils' : false,
                                      offen: summeOffen })

  const reicht = vfHeute >= summeOffen
  return (
    <Karte id="artikel-verlauf" titel={<>Wie ist es gegangen? {wahlName(wahl)}</>}
           aktion={<label className="reihe filter-klein lager-linie-wahl">
             <input type="checkbox" checked={lagerLinie} onChange={e => setLagerLinie(e.target.checked)} /> Lager zeigen
           </label>}>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {leer
        ? <Leer titel={kunden.length === 0 ? 'Noch kein Warenausgang' : `Keine Lieferung: ${wahlName(wahl)}`}>
            {kunden.length === 0 ? 'Sobald die Perigon-Dateien eingelesen sind, steht hier je Kunde die Saison.' : 'Oben einen anderen Artikel, eine andere Grösse oder ein anderes Label wählen.'}
          </Leer>
        : (
        <>
          {!mitVorjahr && (
            <Hinweis art="info">Die Vorjahre fehlen noch: Sie kommen aus denselben Perigon-Dateien — einmal neu einlesen unter{' '}
              <Link to="/betrieb/lieferungen">Betrieb → Warenausgang</Link>, dann stehen die zwei Saisons davor gestrichelt daneben.</Hinweis>
          )}
          {gewaehlt
            ? <Linien reihen={[...kurvenReihen(gewaehlt, saison), ...(lagerLinie && lagerReihe ? [lagerReihe] : [])]} hoehe={440} zoom={false}
                      xVon={0} xBis={364} yVon={0} xKalender={Date.UTC(saison, 6, 1)}
                      xFormat={tagText(saison)} yFormat={tonnenAchse} xTitel={`Saison ${saisonText(saison)}`}
                      yTitel={`geliefert, kumuliert — ${titel}`} yEinheit="kg"
                      heute={{ x: tagHeute, text: 'heute', rechts: '' }} leer="keine Lieferung"
                      fuss={<span className="leise">Ausgezogen diese Saison bis heute, gestrichelt die Vorjahre bis zum Saisonende
                        {lagerLinie && lagerReihe ? '; orange das Verkaufsfähige dieses Artikels im Lager (nach heute die Prognose)' : ''}.</span>} />
            : <Leer titel={`${titel}: keine Lieferung`}>{titel} hat {wahlName(wahl)} in den letzten drei Saisons nicht bekommen.</Leer>}
          <OhneGewicht passend={passend} auswahl={auswahl} gruppeVon={gruppeVon} />
          <div className="rollbar">
            <table className="dicht kundentabelle">
              <thead><tr>
                <th>Kunde</th>
                {/* Zweizeilig: einzeilig lief die Tabelle schon am Bildschirm im Büro über den Rand. */}
                <th className="zahl">geliefert{' '}<br />{saisonText(saison)} bis heute<Herkunft art="gemessen" /></th>
                <th className="zahl">geliefert{' '}<br />{saisonText(saison - 1)} bis {datum(heute).slice(0, 6)}<Herkunft art="gemessen" /></th>
                <th className="zahl">Plan {saisonText(saison)}{' '}<br />ganze Saison</th>
                <th>erreicht</th>
                <th className="zahl">noch{' '}<br />zu liefern</th>
              </tr></thead>
              <tbody>{gruppen.map((g, i) => (
                <Fragment key={g.name}>
                  {gruppenZeile(g, i)}
                  {auf.has(g.name) && g.kunden.map(k => kundenZeile(k, !!ziel.jeGruppe.get(g.name)?.gruppenplan))}
                </Fragment>
              ))}</tbody>
              <tfoot>
                <tr className="summe">
                  <td><strong>alle Kunden</strong></td>
                  {zellen(summenZahlen, <td className={`zahl plan${summenZahlen.eigen === false ? ' plan-vorjahr' : ''}`}>
                    {summenZahlen.planKg > 0 ? masse(summenZahlen.planKg) : '—'}
                    {planUnter(summenZahlen.eigen, summenZahlen.planKg) && <span className="zelle-unter">{planUnter(summenZahlen.eigen, summenZahlen.planKg)}</span>}
                  </td>)}
                </tr>
              </tfoot>
            </table>
          </div>
          {/* Ein Satz, keine Zelle: unter der Spalte „Kunde" hätte er geheissen, was er nicht ist. */}
          <p className={`reicht-zeile${reicht ? '' : ' fehlt'}`} id="artikel-reicht">
            {reicht
              ? <>Verkaufsfähig im Lager heute <strong>{masse(vfHeute)}</strong> <Herkunft art="gerechnet" /> — reicht für die{' '}
                  {masse(summeOffen)}, die nach Plan noch zu liefern sind.</>
              : <><span className="ausruf" aria-label="reicht nicht">!</span> Noch zu liefern <strong>{masse(summeOffen)}</strong>, verkaufsfähig im
                  Lager heute nur {masse(vfHeute)} <Herkunft art="gerechnet" /> — es fehlen <strong>{masse(summeOffen - vfHeute)}</strong>.</>}
          </p>
        </>
      )}
      <Erklaerung>
        <p>Die Kürbis-Lieferungen der Perigon-Dateien <Herkunft art="gemessen" />, kumuliert über die Saison vom 1. Juli bis zum
        30. Juni — für den Artikel, die Grösse und das Label oben, so wie der Artikel verkauft wurde (lose verkaufte Ware zählt nur
        bei „beide Grössen"). Die laufende Saison endet heute; die Vorjahre laufen gestrichelt bis zum Saisonende weiter.</p>
        <p><strong>Gruppen:</strong> Migros, Coop (auch RVZ/RZV) und Kleinkunden nach dem Namen — ein anderer Kunde lässt sich mit einem
        Klick auf seine Gruppe einer anderen oder einer neuen zuordnen. Ein Klick auf die Gruppe zeigt ihre Kunden und die Gruppe im
        Diagramm, ein Klick auf einen Kunden ihn allein und darunter seine Lieferungen.</p>
        <p><strong>Plan:</strong> mit dem Stift die Planmenge der Saison für genau diese Wahl (Artikel, Grösse, Label); grau steht, solange
        keine eingetragen ist, die ganze Vorjahressaison. „Schon erreicht" ist diese Saison bis heute geteilt durch den Plan,
        <strong> noch zu liefern</strong> der Plan weniger das schon Gelieferte. Darunter steht, ob das Verkaufsfähige im Lager dafür
        reicht.</p>
      </Erklaerung>
    </Karte>
  )
}

/** Runde AR (0115): Stück, für die Perigon kein Stückgewicht kennt, stehen nicht in der Linie — aber sie stehen da. */
function OhneGewicht({ passend, auswahl, gruppeVon }: { passend: KundeTag[]; auswahl: string; gruppeVon: (k: string) => string }) {
  const m = new Map<number, number>()
  for (const k of passend) {
    if (auswahl.startsWith('k:') && k.kunde !== auswahl.slice(2)) continue
    if (auswahl.startsWith('g:') && gruppeVon(k.kunde) !== auswahl.slice(2)) continue
    if (Number(k.stueck_ohne_gewicht ?? 0) > 0) m.set(k.saison, (m.get(k.saison) ?? 0) + Number(k.stueck_ohne_gewicht))
  }
  if (m.size === 0) return null
  return (
    <div id="artikel-ohne-gewicht"><Hinweis art="info">
      Nicht in den Linien, weil Perigon kein Stückgewicht kennt:{' '}
      {[...m.entries()].sort((a, b) => b[0] - a[0]).map(([s, n]) => `${saisonText(s)} ${zahl(n)} Stück`).join(' · ')}.
      Steht das Stückgewicht im Perigon-Artikelstamm, die Datei neu einlesen.
    </Hinweis></div>
  )
}

/** Die Planmenge eintragen — leer heisst: wieder das Vorjahr. */
function PlanFeld({ kg, eigen, setzen, abbrechen }: { kg: number; eigen: boolean; setzen: (kg: number | null) => void; abbrechen: () => void }) {
  const [wert, setWert] = useState(eigen ? String(Math.round(kg)) : '')
  const zahlWert = wert.trim() === '' ? null : Number(wert.replace(/'/g, '').replace(',', '.'))
  const gueltig = zahlWert === null || (Number.isFinite(zahlWert) && zahlWert >= 0)
  return (
    <form className="plan-feld" onClick={e => e.stopPropagation()} onSubmit={e => { e.preventDefault(); if (gueltig) setzen(zahlWert) }}>
      <input type="text" inputMode="decimal" autoFocus aria-label="Planmenge in kg" placeholder={`Vorjahr ${Math.round(kg)}`} value={wert}
             onChange={e => setWert(e.target.value)} onKeyDown={e => { if (e.key === 'Escape') { e.stopPropagation(); abbrechen() } }} />
      <span className="leise">kg</span>
      <button type="submit" className="werkzeug-knopf" disabled={!gueltig}>{zahlWert === null ? 'Vorjahr' : 'speichern'}</button>
    </form>
  )
}

/** Die Gruppe eines Kunden setzen — oder zurück zur Regel nach dem Namen. */
function GruppeWahl({ kunde, jetzt, gesetzt, gruppen, setzen, abbrechen }: {
  kunde: string; jetzt: string; gesetzt: boolean; gruppen: string[]; setzen: (g: string | null) => void; abbrechen: () => void
}) {
  const [neu, setNeu] = useState('')
  return (
    <div className="gruppe-wahl" onClick={e => e.stopPropagation()} role="group" aria-label={`Gruppe von ${kunde}`}>
      {gruppen.filter(g => g !== jetzt).map(g => <button key={g} type="button" className="werkzeug-knopf" onClick={() => setzen(g)}>{g}</button>)}
      <form onSubmit={e => { e.preventDefault(); if (neu.trim()) setzen(neu.trim()) }}>
        <input type="text" value={neu} onChange={e => setNeu(e.target.value)} placeholder="neue Gruppe" aria-label="neue Gruppe" />
      </form>
      {gesetzt && <button type="button" className="werkzeug-knopf" onClick={() => setzen(null)}>nach dem Namen</button>}
      <button type="button" className="werkzeug-knopf" onClick={abbrechen}>abbrechen</button>
    </div>
  )
}

/** Die Lieferungen eines Kunden (diese und letzte Saison) — ein Klick zeigt die ganze Perigon-Zeile (Runde AS). */
function Lieferungen({ kunde, saison, wahl }: { kunde: string; saison: number; wahl: Wahl }) {
  const [zeilen, setZeilen] = useState<KundePosition[] | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [offen, setOffen] = useState<{ quelle: string; posId: number } | null>(null)
  useEffect(() => {
    let gilt = true
    setZeilen(null)
    void supabase.from('v_kunde_position').select('quelle, pos_id, datum, saison, gruppe, groesse, label, artikel, menge, einheit, kg')
      .eq('kunde', kunde).gte('saison', saison - 1).order('datum', { ascending: false }).limit(500)
      .then(r => { if (!gilt) return; if (r.error) setFehler(fehlerText(r.error)); else setZeilen((r.data ?? []) as KundePosition[]) })
    return () => { gilt = false }
  }, [kunde, saison])
  const passend = (zeilen ?? []).filter(z => passtGruppe(wahl, z.gruppe) && passtLabel(wahl, z.label) && passtVerkauf(wahl, z.groesse))
  return (
    <section id="kunde-lieferungen" className="kunde-lieferungen">
      {/* Runde AT: direkt unter dem Kunden, eingerückt — der Name steht schon in der Zeile darüber. */}
      <p className="kunde-lieferungen-kopf">Lieferungen {saisonText(saison - 1)} und {saisonText(saison)} · {wahlName(wahl)}
        <span className="leise"> — eine Zeile anklicken zeigt sie wie in der Perigon-Datei</span></p>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {zeilen === null && !fehler && <Lade zeilen={2} />}
      {zeilen !== null && passend.length === 0 && <p className="leise">keine</p>}
      {passend.length > 0 && (
        <div className="rollbar innen-rollt"><table className="dicht">
          <thead><tr><th>Datum</th><th>Artikel</th><th className="zahl">Menge</th><th className="zahl">Masse</th><th>Label</th></tr></thead>
          <tbody>{passend.map(z => (
            <tr key={`${z.quelle}:${z.pos_id}`} className="klickbar" onClick={() => setOffen({ quelle: z.quelle, posId: z.pos_id })}
                title="die ganze Zeile der Perigon-Datei zeigen">
              <td>{datum(z.datum)}</td><td>{z.artikel}</td>
              <td className="zahl">{z.menge != null ? `${zahl(z.menge)} ${z.einheit ?? ''}` : '—'}</td>
              <td className="zahl">{z.kg != null ? kg(z.kg, 0) : <span className="leise">unbekannt</span>}</td>
              <td>{labelName(z.label)}</td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
      {offen && <LieferungFenster quelle={offen.quelle} posId={offen.posId} schliessen={() => setOffen(null)} />}
    </section>
  )
}

/**
 * Das Verkaufsfähige des gewählten Artikels über die Saison (Runde AS: „den
 * Lagerbestand als eigene Linie"). Je Woche das Verkaufsfähige der Chargen
 * des Artikels (erg_verlauf, je Charge; nach heute die Prognose), nach Label
 * und Artikelgruppe gewählt; die Grösse mit dem Anteil, den sie heute an der
 * Charge hat (artikel_lager_charge) — ohne Ware heute mit dem Anteil der
 * Artikelgruppe. Bei „beide Grössen" zählt alles.
 */
function lagerUeberSaison(verlauf: Verlaufswoche[], lagerHeute: ArtikelLagerCharge[], bestand: Bestand[], grund: Grundlagen,
                          wahl: Wahl, saison: number, tagHeute: number): Reihe | null {
  const gruppeVon = new Map(grund.gruppen.map(g => [g.sorte, g.artikelgruppe]))
  const labelVon = new Map(grund.labels.map(l => [l.charge_nr, l.label]))
  const sorteVon = new Map(bestand.map(b => [b.charge_nr, b.sorte]))
  // Anteil der gewählten Grösse je Charge (heute), und je Artikelgruppe als Ersatz
  const jeCharge = new Map<number, { teil: number; alle: number }>()
  const jeGruppe = new Map<string, { teil: number; alle: number }>()
  for (const t of lagerHeute) {
    const passt = passtKlasse(wahl, klasseVon(t.groesse)) ? Number(t.kg) : 0
    const c = jeCharge.get(t.charge_nr) ?? { teil: 0, alle: 0 }
    c.teil += passt; c.alle += Number(t.kg); jeCharge.set(t.charge_nr, c)
    const g = jeGruppe.get(t.artikelgruppe ?? '') ?? { teil: 0, alle: 0 }
    g.teil += passt; g.alle += Number(t.kg); jeGruppe.set(t.artikelgruppe ?? '', g)
  }
  const anteil = (nr: number, gruppe: string | null) => {
    if (wahl.groesse === 'beide') return 1
    const c = jeCharge.get(nr)
    if (c && c.alle > 0) return c.teil / c.alle
    const g = jeGruppe.get(gruppe ?? '')
    return g && g.alle > 0 ? g.teil / g.alle : null
  }
  const proTag = new Map<number, number>()
  for (const v of verlauf) {
    if (v.gruppe !== 'charge') continue
    const nr = Number(v.schluessel)
    const sorte = sorteVon.get(nr) ?? null
    const gruppe = sorte ? gruppeVon.get(sorte) ?? null : null
    if (!passtGruppe(wahl, gruppe) || !passtLabel(wahl, labelVon.get(nr) ?? null)) continue
    const a = anteil(nr, gruppe)
    if (a === null) continue
    const t = saisonTag(v.bis, saison)
    if (t < 0 || t > 364) continue
    proTag.set(t, (proTag.get(t) ?? 0) + Number(v.verkaufsfaehig_kg ?? 0) * a)
  }
  if (proTag.size < 2) return null
  return { name: 'verkaufsfähig im Lager', farbe: 'var(--kuerbis)', linie: true, marker: false, dick: true, prognoseAb: tagHeute,
           punkte: [...proTag.entries()].sort((a, b) => a[0] - b[0]).map(([x, y]) => ({ x, y })) }
}

function kurvenReihen(k: Kurve, saison: number): Reihe[] {
  const r: Reihe[] = []
  const farben: Record<number, [string, boolean]> = {
    [saison]: ['var(--blau)', false], [saison - 1]: ['var(--text-2)', true], [saison - 2]: ['var(--text-leise)', true],
  }
  for (const s of [saison, saison - 1, saison - 2]) {
    const p = k.saisons.get(s)
    if (!p || p.length < 2) continue
    r.push({ name: saisonText(s), farbe: farben[s][0], linie: true, marker: false, gestrichelt: farben[s][1], dick: s === saison,
             punkte: p.map(x => ({ x: x.tag, y: x.kum })) })
  }
  return r
}

/* ---------- 3. Was in den Perigon-Dateien auffällt (Runde AS) ------------------ */

/**
 * Der Betrieb: „solche Infos, dass du das Perigon durchscannst — hervorragend.
 * Das darfst du gerne erweitern." Je Art, wie oft, und aufgeklappt jede Zeile
 * mit dem Satz, was zu tun ist (v_perigon_pruefung, 0116); ein Klick zeigt
 * die ganze Zeile der Datei.
 */
function PerigonPruefungen({ liste }: { liste: PerigonPruefung[] }) {
  const [auf, setAuf] = useState<string | null>(null)
  const [offen, setOffen] = useState<{ quelle: string; posId: number } | null>(null)
  const arten = useMemo(() => {
    const m = new Map<string, PerigonPruefung[]>()
    for (const p of liste) m.set(p.art, [...(m.get(p.art) ?? []), p])
    return [...m.entries()].sort((a, b) => b[1].length - a[1].length)
  }, [liste])
  if (liste.length === 0) return null
  return (
    <Karte id="perigon-pruefung" titel="Was in den Perigon-Dateien auffällt">
      <div className="rollbar">
        <table className="dicht perigon-pruefung">
          <thead><tr><th>Art</th><th className="zahl">Zeilen</th><th className="zahl">Masse in der Datei</th></tr></thead>
          <tbody>{arten.map(([art, zeilen]) => (
            <Fragment key={art}>
              <tr className={`klickbar${auf === art ? ' offen' : ''}`} aria-expanded={auf === art} onClick={() => setAuf(auf === art ? null : art)}>
                <td><span className="chevron" aria-hidden="true"><ZChevron size={14} /></span><Marke art={art === 'Teil ohne Charge' ? 'neutral' : 'warnung'}>{art}</Marke></td>
                <td className="zahl">{zahl(zeilen.length)}</td>
                <td className="zahl">{masse(zeilen.reduce((a, z) => a + Number(z.kg ?? 0), 0))}</td>
              </tr>
              {auf === art && zeilen.map(z => (
                <tr key={`${z.quelle}:${z.pos_id}:${z.charge_nr ?? ''}:${z.befund}`} className="klickbar unterzeile"
                    onClick={() => setOffen({ quelle: z.quelle, posId: z.pos_id })} title="die ganze Zeile der Perigon-Datei zeigen">
                  <td colSpan={3}>
                    <span className="leise">{datum(z.datum)} · {z.kunde ?? 'ohne Kunde'} · {z.artikel}{z.kg != null ? ` · ${kg(z.kg, 0)}` : ''}</span>
                    <br />{z.befund}
                  </td>
                </tr>
              ))}
            </Fragment>
          ))}</tbody>
        </table>
      </div>
      <Erklaerung>
        <p>Jede Zeile der laufenden Saison wird beim Rechnen durchgesehen: eine Charge, die Perigon nennt, die Lieferung aber nicht trägt; ein
        Artikel, dessen Gruppe nicht zur Sorte der gelieferten Charge passt; als Demeter verkauft, aber als Knospe geliefert; eine Lieferung vor
        dem ersten Eingang ihrer Charge. Ein Klick auf die Art zeigt die Zeilen, ein Klick auf eine Zeile die ganze Zeile der Datei.</p>
      </Erklaerung>
      {offen && <LieferungFenster quelle={offen.quelle} posId={offen.posId} schliessen={() => setOffen(null)} />}
    </Karte>
  )
}
