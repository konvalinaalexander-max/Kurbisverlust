/**
 * Runde BG: die Auffälligkeiten, Fall für Fall (0128). Der Betrieb, 25. Oktober:
 * „bitte ordne die chronologisch … die obersten sollen die neuesten sein …
 * wenn ich dann eine Auffälligkeit öffne … damit ich besser nachvollziehen
 * kann, was eigentlich genau Sache ist. Also das Problem und dann mir
 * Lösungsvorschläge anbieten, die ich dann auch akzeptieren kann oder nicht
 * … spezifische Fallnummer, damit ich dir auch im Chat sagen kann, wie ich
 * mit diesen Fallnummern umgehen möchte … wie kam es überhaupt zu diesen
 * Auffälligkeiten."
 *
 * Eine Auffälligkeit ist ein Fall: Art und Bezug (woran sie hängt, 0128)
 * sind ihre Kennung, unter ihr stehen Nummer und Vermerk. Reine Funktionen —
 * Folge, Tage, Stand, Muster, Vorschlag —, geprüft in test/auffaellig.test.ts.
 *
 * Vorschläge macht die App nur, wo die Daten selbst einen Wert nennen: ein
 * Tag, an dem genau diese Gewichte im Wareneingang stehen; eine Palette am
 * selben Tag, die ein, zwei Kilo neben dem Zettel liegt. Wo nur geraten
 * werden könnte, sagt sie, was sie sieht, und lässt es offen. Übernommen
 * wird ein Vorschlag nur mit Klick des Betriebsleiters (auffaellig­keit_
 * korrigieren), danach rechnet die App neu.
 */
import type { Befund } from './daten'

export type AuffStand = 'offen' | 'in_abklaerung' | 'so_lassen' | 'korrigiert'
export const AUFF_STAND_NAME: Record<AuffStand, string> = {
  offen: 'offen', in_abklaerung: 'in Abklärung', so_lassen: 'so lassen', korrigiert: 'korrigiert',
}

/** Ein Vermerk (auffaelligkeit_vermerk): nur angehängt, der jüngste gilt. */
export interface AuffVermerk {
  id: number; fall: string; stand: AuffStand; notiz: string | null
  schnappschuss: Record<string, unknown> | null; wer: string | null; ts: string
  profil?: { name: string } | null
}

/** Die Kennung eines Falls: Art und Bezug, wie 0128 sie eindeutig hält. */
export const fallKennung = (b: Pick<Befund, 'art' | 'bezug'>): string => `${b.art}|${b.bezug ?? ''}`

/** Ein Kalendertag (JJJJ-MM-TT) in Zürich — der Tag, an dem die Arbeit begann. */
export function tagIn(ts: string | null): string | null {
  if (!ts) return null
  if (/^\d{4}-\d\d-\d\d$/.test(ts)) return ts
  const d = new Date(ts)
  if (Number.isNaN(d.getTime())) return null
  const teile = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Zurich', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(d)
  const w = (t: string) => teile.find(p => p.type === t)?.value ?? ''
  return `${w('year')}-${w('month')}-${w('day')}`
}

/** „2026-09-22" → „22.09.2026", ohne Umweg über die Zeitzone. */
export function tagText(tag: string | null): string {
  if (!tag) return '—'
  const m = /^(\d{4})-(\d\d)-(\d\d)/.exec(tag)
  return m ? `${m[3]}.${m[2]}.${m[1]}` : tag
}

/** Gleich alt: nach Art, dann Bezug — damit die Folge jeden Tag dieselbe ist. */
function gleichAlt(a: Befund, b: Befund): number {
  return a.art.localeCompare(b.art, 'de') || String(a.bezug ?? '').localeCompare(String(b.bezug ?? ''), 'de')
}

/**
 * Die neuesten zuoberst. „Neu" ist der Beginn der Arbeit, an der die
 * Auffälligkeit hängt (bei einer Charge: ihr erster Eingang) — das, was der
 * Betrieb im Kopf hat („das war am Anfang, jetzt ist es behoben"). Ohne Tag
 * ganz unten.
 */
export function neuZuerst(bs: Befund[]): Befund[] {
  return [...bs].sort((a, b) => {
    if (!a.start_ts || !b.start_ts) return (a.start_ts ? 0 : 1) - (b.start_ts ? 0 : 1) || gleichAlt(a, b)
    return b.start_ts.localeCompare(a.start_ts) || gleichAlt(a, b)
  })
}

/**
 * Die Folge, in der Nummern vergeben werden: die älteste zuerst, damit eine
 * höhere Nummer eine jüngere Auffälligkeit ist — und eine, die morgen dazu
 * kommt, die nächste. Wer schon eine Nummer hat, behält sie (0128).
 */
export function nummernFolge(bs: Befund[]): string[] {
  const alt = [...bs].sort((a, b) => {
    if (!a.start_ts || !b.start_ts) return (a.start_ts ? 0 : 1) - (b.start_ts ? 0 : 1) || gleichAlt(a, b)
    return a.start_ts.localeCompare(b.start_ts) || gleichAlt(a, b)
  })
  return [...new Set(alt.map(fallKennung))]
}

/** Je Tag eine Gruppe, in der Folge der Liste (neueste zuerst). */
export function nachTag(bs: Befund[]): { tag: string | null; befunde: Befund[] }[] {
  const gruppen: { tag: string | null; befunde: Befund[] }[] = []
  for (const b of bs) {
    const tag = tagIn(b.start_ts)
    const letzte = gruppen[gruppen.length - 1]
    if (letzte && letzte.tag === tag) letzte.befunde.push(b)
    else gruppen.push({ tag, befunde: [b] })
  }
  return gruppen
}

/** Die Vermerke je Fall, der jüngste zuerst. */
export function vermerkeJeFall(vs: AuffVermerk[]): Map<string, AuffVermerk[]> {
  const m = new Map<string, AuffVermerk[]>()
  for (const v of [...vs].sort((a, b) => b.ts.localeCompare(a.ts) || b.id - a.id)) {
    const l = m.get(v.fall)
    if (l) l.push(v); else m.set(v.fall, [v])
  }
  return m
}

/** Wie es steht: der jüngste Vermerk, sonst offen. */
export function standVon(fall: string, vermerke: Map<string, AuffVermerk[]>): AuffStand {
  return vermerke.get(fall)?.[0]?.stand ?? 'offen'
}

export type StandFilter = 'offen' | 'in_abklaerung' | 'so_lassen' | 'erledigt' | 'alle'
/** „erledigt": was nicht mehr in den Daten steht, weil es korrigiert wurde, ist nicht hier — es steht im Verlauf. */
export function passtStand(s: AuffStand, f: StandFilter): boolean {
  if (f === 'alle') return true
  if (f === 'erledigt') return s === 'so_lassen' || s === 'korrigiert'
  return s === f
}

/**
 * Was korrigiert oder so gelassen wurde und nicht mehr in den Daten steht —
 * aus dem Schnappschuss des Vermerks, damit „das war am Anfang ein Problem,
 * jetzt ist es behoben" sichtbar bleibt.
 */
export function nichtMehrDa(vermerke: Map<string, AuffVermerk[]>, jetzt: Set<string>): AuffVermerk[] {
  return [...vermerke.entries()].filter(([f]) => !jetzt.has(f)).map(([, l]) => l[0]).sort((a, b) => b.ts.localeCompare(a.ts) || b.id - a.id)
}

/* ---------- Was eine Art ist und wie es dazu kommt -------------------- */

export interface ArtInfo {
  /** in Worten, für die Überschrift */
  titel: string
  /** wo im Ablauf das entsteht — in der Halle, im Wareneingang, in der App */
  wie: string
  /** was die App damit rechnet, solange es so steht */
  folge: string
}

/**
 * Je Art: wo sie im Ablauf entsteht und was sie für die Zahlen heisst.
 * Gilt für alle Fälle dieser Art; was den einzelnen Fall ausmacht, steht im
 * Befund und in den Daten darunter.
 */
export const ART_INFO: Record<string, ArtInfo> = {
  'Zettelgewicht': {
    titel: 'Zettelgewicht ohne passende Palette',
    wie: 'Beim Sortieren oder Waschen tippt die Halle von jedem Palettenzettel Eingangsdatum, Gewicht und Kisten ab. Die App sucht dazu im Wareneingang (Erntejournal) eine Palette derselben Charge mit genau diesem Gewicht — und findet keine, oder nur an einem anderen Tag. Meist ist eine Zahl vertippt, der Zettel gehört zu einer anderen Charge, oder die Palette wurde von Hand neu zusammengestellt (Teilpalette).',
    folge: 'Gerechnet wird mit dem Zettel: Zettelgewicht − Kisten × Kistengewicht − Palette. Die Menge stimmt, wenn der Zettel stimmt.',
  },
  'Zetteldatum': {
    titel: 'Zetteldatum ohne Palette an dem Tag',
    wie: 'Das Eingangsdatum vom Zettel gibt es bei dieser Charge im Wareneingang nicht: an dem Tag kam keine ihrer Paletten. Meist ist das Datum vertippt (Tag oder Monat), oder die Zettel gehören zu einer anderen Charge.',
    folge: 'Die Lagerdauer dieser Paletten rechnet ab dem getippten Tag — Verdunstung und Faules hängen daran.',
  },
  'Zetteldatum Zukunft': {
    titel: 'Zetteldatum nach dem Arbeitstag',
    wie: 'Der Zettel nennt ein Eingangsdatum nach dem Tag der Arbeit — eine Palette kann nicht verarbeitet werden, bevor sie eingeht. Meist das Jahr oder der Monat vertippt.',
    folge: 'Die Lagerdauer wäre negativ; die App rechnet diese Paletten ohne Lagertage.',
  },
  'Kistengewicht': {
    titel: 'Kistengewicht unbekannt',
    wie: 'Gezählt wurden Kisten, aber für dieses Kaliber dieser Sorte hat noch keine Arbeit Kisten gewogen. Ohne Gewicht je Kiste kennt die App die Menge nicht. Keine Fehleingabe — eine Messlücke.',
    folge: 'Die Menge dieser Arbeit ist unbekannt, bis eine Wägung da ist — dann rechnet die App rückwirkend.',
  },
  'Ohne Nenner': {
    titel: 'Messung ohne Menge',
    wie: 'Gemessen wurde (etwa Faules), aber an der Arbeit steht keine Menge: keine Kiste gezählt, keine kg eingetragen. Ein Anteil braucht beides.',
    folge: 'Die Messung fliesst nirgends ein, solange die Menge fehlt.',
  },
  'Wägung': {
    titel: 'Wägung ohne Gewichtsverlust',
    wie: 'Eine Palette wurde nach dem Lager gewogen und hat kein Gramm verloren. Meist wurde beim Erfassen das Eingangsgewicht abgeschrieben statt gewogen.',
    folge: 'Sie zählt nicht in die Verdunstungsrate — die Rate kommt aus den übrigen Wägungen.',
  },
  'Verdunstung': {
    titel: 'Zu schnell leichter geworden',
    wie: 'Zwischen Eingang und Wägung verlor die Palette mehr, als ein Kürbis verdunsten kann (Grenze 1 % je Tag). Meist eine andere Palette, eine Teilpalette oder ein vertipptes Gewicht.',
    folge: 'Sie zählt nicht in die Verdunstungsrate, bis sie korrigiert ist.',
  },
  'Palox geleert': {
    titel: 'Palox zwischendurch geleert',
    wie: 'Der Waagenstand des Palox fiel während der Arbeit — er wurde geleert, ohne „Palox leeren" zu drücken. Was zwischen der letzten Ablesung und dem Leeren dazukam, hat niemand gesehen.',
    folge: 'Das Faule dieser Arbeit ist unbekannt — nicht null.',
  },
  'Palette fraglich': {
    titel: 'Mit Palette gewogen — passt nicht',
    wie: 'Der Ausschuss wurde „mit Palette" erfasst, aber nach Abzug der Palette bliebe fast nichts. Meist standen die Kisten direkt auf der Waage.',
    folge: 'Gerechnet wird mit dem, was nach Abzug bleibt — wohl zu wenig.',
  },
  'Überzählung': {
    titel: 'Mehr geliefert als die Rechnung erwartet',
    wie: 'Die Lieferscheine dieser Charge brauchen mehr Eingang, als im Wareneingang steht. Meist fehlt eine Palette im Erntejournal, oder ein Lieferschein ist auf die falsche Charge gebucht — das klärt der Reiter Perigon.',
    folge: 'Die Charge kann nicht unter null fallen; das Zuviel steht als Überzählung da, nicht als Verlust.',
  },
  'Lieferung ohne Eingang': {
    titel: 'Lieferung ohne Wareneingang',
    wie: 'Auf einen Lieferschein ist eine Charge gebucht, von der im Wareneingang nichts steht.',
    folge: 'Die Lieferung kann keiner Ware zugeordnet werden.',
  },
  'Lieferung in der Zukunft': {
    titel: 'Lieferung in der Zukunft',
    wie: 'Ein Lieferschein trägt ein Datum nach heute — vordatiert, oder vertippt.',
    folge: 'Er zählt erst ab seinem Datum.',
  },
  'Tara fehlt': {
    titel: 'Gebinde ohne Tara',
    wie: 'Eine Palette im Wareneingang hat ein Gebinde, dessen Leergewicht die App nicht kennt.',
    folge: 'Das Netto dieser Paletten ist unbekannt.',
  },
}

export const artInfo = (art: string): ArtInfo => ART_INFO[art] ?? {
  titel: art,
  wie: 'Eine Messung, die nicht zu ihrem Nenner oder zu den übrigen Daten passt.',
  folge: 'Die App rechnet sie nicht wie gemessen — wie genau, steht im Befund.',
}

/* ---------- Zettel und Wareneingang: das Muster und der Vorschlag ------ */

/** Ein Zettel der Arbeit (auftrag_palette). */
export interface Zettel {
  id: number; auftrag_id: number; eingangsdatum: string | null
  brutto_zettel_kg: number | null; kisten: number | null; gebindeart: string | null
}
/** Eine Palette im Wareneingang (palette). */
export interface WarePalette {
  charge_nr: number; eingangsdatum: string; brutto_kg: number | null; kisten: number | null; gebindeart?: string | null
}
export interface ZettelLage {
  /** alle Zettel der Arbeit */
  zettel: Zettel[]
  /** alle Paletten der Charge der Arbeit */
  eigen: WarePalette[]
  /** Paletten anderer Chargen an den Tagen der Zettel */
  fremd: WarePalette[]
  /** Zettel anderer Arbeiten derselben Charge — wer schon eine Palette für sich hat */
  andere: Zettel[]
  /** der Tag, an dem die Arbeit begann */
  arbeitTag: string | null
}

export type Muster = 'datum' | 'tippfehler' | 'zahlendreher' | 'fremde_charge' | 'doppelt' | 'teilpalette' | 'palox' | 'mehrdeutig' | 'ohne_kandidat'
export const MUSTER_NAME: Record<Muster, string> = {
  datum: 'Datum vertippt',
  tippfehler: 'Gewicht vertippt',
  zahlendreher: 'Zahlendreher',
  fremde_charge: 'Zettel einer anderen Charge',
  doppelt: 'schon von einer anderen Arbeit gezählt',
  teilpalette: 'Teilpalette',
  palox: 'Palox mit geschätztem Gewicht',
  mehrdeutig: 'mehrere Möglichkeiten',
  ohne_kandidat: 'nichts Passendes gefunden',
}

export type KorrekturFeld = 'zetteldatum' | 'zettelgewicht' | 'mit_palette'
export interface Vorschlag {
  /** korrigieren: ein Wert wird ersetzt (ein Klick); so_lassen: es stimmt so; von_hand: braucht einen Entscheid ausserhalb */
  art: 'korrigieren' | 'so_lassen' | 'von_hand'
  /** in einem Satz, was geschähe */
  titel: string
  /** woran die App das sieht — Satz für Satz */
  warum: string[]
  sicher?: 'eindeutig' | 'wahrscheinlich'
  was?: KorrekturFeld
  ids?: number[]
  vorher?: string
  nachher?: string
  /** was danach passiert */
  danach?: string
  /** von_hand: wohin */
  wo?: 'arbeit' | 'perigon' | 'charge'
}
export interface Deutung {
  muster: Muster | null
  /** die Zettel, um die es geht */
  betroffen: Zettel[]
  /** je Zettel der Arbeit: was im Wareneingang dazu passt */
  treffer: Map<number, Treffer>
  vorschlag: Vorschlag | null
}

const gleich = (a: number | null, b: number | null) => a !== null && b !== null && Math.abs(a - b) < 0.005
const kgText = (x: number | null) => x === null ? '—' : `${Number.isInteger(x) ? x : x.toFixed(1)} kg`
const mehr = (n: number, ein: string, viele: string) => `${n} ${n === 1 ? ein : viele}`

/** Der Bezug zerlegt: „zettel:1602:448.00:2026-09-22" → Arbeit, kg, Tag. */
export function bezugTeile(bezug: string | null | undefined): { typ: string; id: number | null; kg: number | null; tag: string | null } {
  const t = String(bezug ?? '').split(':')
  const typ = t[0] ?? ''
  const id = t[1] && /^\d+$/.test(t[1]) ? Number(t[1]) : null
  if (typ === 'zettel') return { typ, id, kg: t[2] ? Number(t[2]) : null, tag: t[3] && /^\d{4}-\d\d-\d\d$/.test(t[3]) ? t[3] : null }
  if (typ === 'zetteldatum') return { typ, id, kg: null, tag: t[2] && /^\d{4}-\d\d-\d\d$/.test(t[2]) ? t[2] : null }
  return { typ, id, kg: null, tag: null }
}

/** Die Zettel, um die es in einer Zettel-Auffälligkeit geht. */
export function betroffeneZettel(b: Befund, zettel: Zettel[]): Zettel[] {
  const t = bezugTeile(b.bezug)
  if (t.typ === 'zettel' && t.kg !== null) {
    return zettel.filter(z => gleich(z.brutto_zettel_kg, t.kg) && (t.tag === null || z.eingangsdatum === t.tag))
  }
  if (t.typ === 'zetteldatum' && t.tag) return zettel.filter(z => z.eingangsdatum === t.tag)
  return []
}

/** Zwei Zahlen aus denselben Ziffern in anderer Folge (342 ↔ 432)? */
export function istZahlendreher(a: number, b: number): boolean {
  if (!Number.isInteger(a) || !Number.isInteger(b) || a === b) return false
  const s = (x: number) => String(x).split('').sort().join('')
  return String(a).length === String(b).length && s(a) === s(b)
}

/** Zwei Tage, die sich in genau einer Ziffer unterscheiden (08.09 ↔ 18.09)? */
export function eineZifferAnders(a: string, b: string): boolean {
  if (a.length !== b.length || a === b) return false
  let n = 0
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) n++
  return n === 1
}

/** Die häufigste Kistenzahl der Paletten der Charge — „voll" für diese Charge. */
function volleKisten(eigen: WarePalette[]): number | null {
  const n = new Map<number, number>()
  for (const p of eigen) if (p.kisten && p.kisten > 1) n.set(p.kisten, (n.get(p.kisten) ?? 0) + 1)
  return [...n.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0]?.[0] ?? null
}

const istPalox = (z: Zettel) => (z.gebindeart ?? '').toLowerCase().includes('palox') || z.kisten === 1

/**
 * Wie viele Paletten dieses Tages und Gewichts sind noch frei — nicht schon
 * von einem Zettel einer anderen Arbeit derselben Charge (oder einem Zettel
 * dieser Arbeit ausserhalb des Falls) belegt?
 */
function frei(tag: string, kgW: number, lage: ZettelLage, ohne: number[]): number {
  const da = lage.eigen.filter(p => p.eingangsdatum === tag && gleich(p.brutto_kg, kgW)).length
  const belegt = [...lage.andere, ...lage.zettel.filter(z => !ohne.includes(z.id))]
    .filter(z => z.eingangsdatum === tag && gleich(z.brutto_zettel_kg, kgW)).length
  return da - belegt
}

/** Welche Zettel (anderer Arbeiten) eine Palette des Wareneingangs schon für sich haben — für die Tabelle. */
export function belegtVon(p: WarePalette, lage: ZettelLage): Zettel[] {
  return [...lage.zettel, ...lage.andere].filter(z => z.eingangsdatum === p.eingangsdatum && gleich(z.brutto_zettel_kg, p.brutto_kg))
}

export interface Treffer {
  /** Tage, an denen eine freie Palette der Charge genau so schwer war (nicht nach dem Arbeitstag) */
  tage: string[]
  /** andere Chargen mit genau diesem Gewicht am Tag des Zettels */
  fremd: number[]
  /** freie Paletten der Charge am selben Tag, 1–2 kg daneben oder mit vertauschten Ziffern, gleiche Kisten */
  nahe: WarePalette[]
  /** steht der Zettel genau so im Wareneingang (Tag und Gewicht)? */
  genau: boolean
}

function zuZettel(z: Zettel, lage: ZettelLage, ohne: number[]): Treffer {
  const tage = [...new Set(lage.eigen
    .filter(p => gleich(p.brutto_kg, z.brutto_zettel_kg) && (!lage.arbeitTag || p.eingangsdatum <= lage.arbeitTag)
              && p.eingangsdatum !== z.eingangsdatum && frei(p.eingangsdatum, p.brutto_kg!, lage, ohne) > 0)
    .map(p => p.eingangsdatum))].sort()
  const fremd = [...new Set(lage.fremd
    .filter(p => p.eingangsdatum === z.eingangsdatum && gleich(p.brutto_kg, z.brutto_zettel_kg))
    .map(p => p.charge_nr))].sort((a, b) => a - b)
  const nahe = lage.eigen.filter(p => p.eingangsdatum === z.eingangsdatum && p.brutto_kg !== null && z.brutto_zettel_kg !== null
    && !gleich(p.brutto_kg, z.brutto_zettel_kg)
    && (Math.abs(p.brutto_kg - z.brutto_zettel_kg) <= 2 || istZahlendreher(p.brutto_kg, z.brutto_zettel_kg))
    && (!z.kisten || !p.kisten || z.kisten === p.kisten)
    && frei(p.eingangsdatum, p.brutto_kg, lage, ohne) > 0)
  const genau = lage.eigen.some(p => p.eingangsdatum === z.eingangsdatum && gleich(p.brutto_kg, z.brutto_zettel_kg))
  return { tage, fremd, nahe, genau }
}

/** Die Charge, zu der die meisten Zettel genau passen — und wie viele. */
function besteFremde(treffer: Treffer[]): { charge: number; n: number } | null {
  const n = new Map<number, number>()
  for (const t of treffer) for (const c of t.fremd) n.set(c, (n.get(c) ?? 0) + 1)
  const [charge, k] = [...n.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0] ?? []
  return charge === undefined ? null : { charge, n: k! }
}

/** Der Tag, den die meisten Zettel nennen — nur, wenn kein anderer Tag gleich viele hat. */
function besterTag(treffer: Treffer[]): { tag: string; n: number } | null {
  const n = new Map<string, number>()
  for (const t of treffer) for (const d of t.tage) n.set(d, (n.get(d) ?? 0) + 1)
  const liste = [...n.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
  if (liste.length === 0) return null
  if (liste.length > 1 && liste[1][1] === liste[0][1]) return null
  return { tag: liste[0][0], n: liste[0][1] }
}

/**
 * Das Muster einer Zettel-Auffälligkeit (Zettelgewicht, Zetteldatum) und,
 * wo die Daten einen Wert nennen, der Vorschlag.
 *
 * Kam am Tag des Zettels keine Palette der Charge, geht es um den Tag — und
 * um alle Zettel dieses Tages zusammen (dieselbe Antwort wie beim
 * Zetteldatum, ob man über das Datum oder über ein Gewicht kommt):
 *   - stehen alle an genau einem anderen Tag so im Wareneingang: Datum
 *     vertippt, Vorschlag dieser Tag — „eindeutig", wenn es mehrere Zettel
 *     sind und keine andere Charge dieselben Gewichte am getippten Tag hat;
 *   - stehen mehr am getippten Tag bei einer anderen Charge: Zettel einer
 *     anderen Charge (kein Klick: die ganze Arbeit wechselte die Charge);
 *   - steht wenigstens die Hälfte an einem Tag: Vorschlag, „wahrscheinlich";
 *   - kam die Charge nur an einem Tag: Vorschlag, „wahrscheinlich".
 * Kam an dem Tag eine Palette der Charge, aber nicht mit diesem Gewicht:
 *   - passen andere Zettel dieses Tages genau, stimmt der Tag; dann geht es
 *     um das Gewicht (unten). Sonst wie oben, für diesen einen Zettel.
 *   - Palox (eine Kiste): im Wareneingang steht ein geschätztes Gewicht —
 *     so lassen;
 *   - genau eine freie Palette am Tag 1–2 kg daneben oder mit vertauschten
 *     Ziffern, gleiche Kisten: Gewicht vertippt, Vorschlag diese Palette;
 *     mehrere: welche es war, sagt nur der Zettel;
 *   - eine andere Charge hat genau dieses Gewicht an dem Tag: fremde Charge;
 *   - weniger Kisten als eine volle Palette der Charge: Teilpalette — so
 *     lassen, der Zettel ist richtig gerechnet;
 *   - sonst: nichts Passendes.
 * „Frei" heisst: nicht schon von einem anderen Zettel belegt.
 */
export function zettelDeutung(b: Befund, lage: ZettelLage): Deutung {
  const t = bezugTeile(b.bezug)
  const betroffen = betroffeneZettel(b, lage.zettel)
  const treffer = new Map(lage.zettel.map(z => [z.id, zuZettel(z, lage, betroffen.map(y => y.id))]))
  const leer: Deutung = { muster: null, betroffen, treffer, vorschlag: null }
  if (betroffen.length === 0) return leer
  const von = betroffen[0].eingangsdatum
  if (!von) return leer
  const tagDa = lage.eigen.some(p => p.eingangsdatum === von)

  if (t.typ === 'zetteldatum' || !tagDa) {
    const gruppe = lage.zettel.filter(z => z.eingangsdatum === von)
    return { ...tagDeutung(b, lage, gruppe, von, false), betroffen, treffer }
  }
  let hinweis: string | null = null
  if (t.tag !== null) {
    const geschwister = lage.zettel.filter(z => !betroffen.some(y => y.id === z.id) && z.eingangsdatum === von && treffer.get(z.id)?.genau)
    if (geschwister.length === 0) {
      const d = tagDeutung(b, lage, betroffen, von, true)
      if (d.vorschlag) return { ...d, betroffen, treffer }
    } else {
      const tage = [...new Set(betroffen.flatMap(z => treffer.get(z.id)?.tage ?? []))]
      hinweis = `${mehr(geschwister.length, 'anderer Zettel', 'andere Zettel')} dieser Arbeit vom ${tagText(von)} ${geschwister.length === 1 ? 'steht' : 'stehen'} genau so im Wareneingang — der Tag stimmt also.`
        + (tage.length > 0 ? ` Dass eine Palette mit ${kgText(betroffen[0].brutto_zettel_kg)} am ${tage.map(tagText).join(', ')} kam, ist wohl Zufall.` : '')
    }
  }
  return { ...gewichtDeutung(b, lage, betroffen, hinweis), treffer }
}

/** Der Tag einer Gruppe von Zetteln — siehe zettelDeutung. `einzeln`: ein Zettelgewicht mit Tag, ohne Geschwister. */
function tagDeutung(b: Befund, lage: ZettelLage, gruppe: Zettel[], von: string, einzeln: boolean): Omit<Deutung, 'betroffen' | 'treffer'> {
  const ids = gruppe.map(z => z.id)
  const tr = gruppe.map(z => zuZettel(z, lage, ids))
  const n = gruppe.length
  const tag = besterTag(tr)
  const f = besteFremde(tr)
  const tagDa = lage.eigen.some(p => p.eingangsdatum === von)
  const eingangstage = [...new Set(lage.eigen.filter(p => !lage.arbeitTag || p.eingangsdatum <= lage.arbeitTag).map(p => p.eingangsdatum))].sort()

  const datum = (auf: string, sicher: 'eindeutig' | 'wahrscheinlich', grund: string[]): Omit<Deutung, 'betroffen' | 'treffer'> => ({
    muster: 'datum',
    vorschlag: {
      art: 'korrigieren', was: 'zetteldatum', ids, vorher: von, nachher: auf, sicher,
      titel: `Zetteldatum ${tagText(von)} → ${tagText(auf)}${n > 1 ? ` an allen ${n} Zetteln vom ${tagText(von)}` : ''}`,
      warum: [
        ...grund,
        ...(eineZifferAnders(von, auf) ? ['Die beiden Daten unterscheiden sich in einer Ziffer — ein Tippfehler liegt nahe.'] : []),
        ...(f ? [`Am ${tagText(von)} hat aber Charge ${f.charge} ${f.n === 1 ? 'eine Palette' : `${f.n} Paletten`} mit ${f.n === 1 ? 'einem dieser Gewichte' : 'diesen Gewichten'} — ganz sicher ist es nicht.`] : []),
        ...(einzeln ? ['Es ist ein einzelnes Gewicht — bei vielen Paletten kann es auch zufällig an einem anderen Tag vorkommen.'] : []),
      ],
      danach: `Danach rechnet die App neu. Die Lagerdauer dieser Paletten beginnt am ${tagText(auf)}; passt der Zettel dann zu seiner Palette, verschwindet die Auffälligkeit.`,
    },
  })
  const passtSatz = (auf: string, k: number) => k === n
    ? (n === 1 ? `Eine freie Palette mit genau ${kgText(gruppe[0].brutto_zettel_kg)} kam bei Charge ${b.charge_nr} am ${tagText(auf)}.`
               : `Alle ${n} Gewichte stehen bei Charge ${b.charge_nr} am ${tagText(auf)} genau so im Wareneingang.`)
    : `${k} der ${n} Gewichte stehen bei Charge ${b.charge_nr} am ${tagText(auf)} genau so im Wareneingang; die übrigen gibt es an keinem Tag.`
  const fremd = (x: { charge: number; n: number }): Omit<Deutung, 'betroffen' | 'treffer'> => ({
    muster: 'fremde_charge',
    vorschlag: {
      art: 'von_hand', wo: 'arbeit',
      titel: `Gehören die Zettel zu Charge ${x.charge}?`,
      warum: [
        n === 1 ? `Am ${tagText(von)} kam bei Charge ${x.charge} eine Palette mit genau ${kgText(gruppe[0].brutto_zettel_kg)}.`
                : `${x.n} der ${n} Gewichte vom ${tagText(von)} stehen genau so bei Charge ${x.charge} im Wareneingang.`,
        `Bei Charge ${b.charge_nr} ${tagDa ? 'gibt es diese Gewichte an dem Tag nicht' : 'kam an dem Tag nichts'}.`,
        'Mit einem Klick ändert die App das nicht: es hiesse, die ganze Arbeit gehört zu einer anderen Charge. Das prüft der Betriebsleiter in der Korrektur der Arbeit — oder fragt in der Halle.',
      ],
    },
  })

  if (tag && tag.n === n) return datum(tag.tag, !f && n > 1 && !einzeln ? 'eindeutig' : 'wahrscheinlich', [passtSatz(tag.tag, n)])
  if (f && f.n >= Math.ceil(n / 2) && f.n > (tag?.n ?? 0)) return fremd(f)
  if (tag && tag.n >= Math.ceil(n / 2)) return datum(tag.tag, 'wahrscheinlich', [passtSatz(tag.tag, tag.n)])
  // Stehen die Gewichte im Wareneingang, aber hat diese Paletten schon eine andere Arbeit gezählt?
  const schon = gruppe.map(z => lage.andere.filter(y => gleich(y.brutto_zettel_kg, z.brutto_zettel_kg)
    && lage.eigen.some(p => p.eingangsdatum === y.eingangsdatum && gleich(p.brutto_kg, z.brutto_zettel_kg))))
  const nSchon = schon.filter(l => l.length > 0).length
  if (!tag && nSchon >= Math.ceil(n / 2)) {
    const arbeiten = [...new Set(schon.flat().map(y => y.auftrag_id))].sort((a, c) => a - c)
    const tage = [...new Set(schon.flat().map(y => y.eingangsdatum!))].sort()
    return {
      muster: 'doppelt',
      vorschlag: {
        art: 'von_hand', wo: 'arbeit',
        titel: `Schon gezählt? Dieselben Paletten stehen bei ${arbeiten.length === 1 ? `Arbeit ${arbeiten[0]}` : `den Arbeiten ${arbeiten.join(', ')}`}.`,
        warum: [
          `${n === 1 ? 'Das Gewicht steht' : `${nSchon} der ${n} Gewichte stehen`} bei Charge ${b.charge_nr} am ${tage.map(tagText).join(', ')} im Wareneingang — aber diese ${nSchon === 1 ? 'Palette hat' : 'Paletten hat'} schon ${arbeiten.length === 1 ? `Arbeit ${arbeiten[0]}` : `eine der Arbeiten ${arbeiten.join(', ')}`} gezählt.`,
          'Wurde dieselbe Palette zweimal erfasst, zählt sie doppelt in die Menge. Das weiss die Halle; ändern lässt es sich in der Korrektur der Arbeit.',
        ],
      },
    }
  }
  const ohneGewicht = gruppe.every(z => z.brutto_zettel_kg === null)
  if (!einzeln && !f && eingangstage.length === 1 && eingangstage[0] !== von) {
    return datum(eingangstage[0], 'wahrscheinlich',
      [`Charge ${b.charge_nr} kam nur an einem Tag, am ${tagText(eingangstage[0])}${ohneGewicht ? ' — die Zettel haben kein Gewicht, an dem es sich bestätigen liesse.' : ' — die Gewichte der Zettel stehen dort aber nicht genau so.'}`])
  }
  if (f) return fremd(f)
  const tage = [...new Set(tr.flatMap(x => x.tage))].sort()
  if (tage.length > 1) {
    return {
      muster: 'mehrdeutig',
      vorschlag: {
        art: 'von_hand', wo: 'arbeit', titel: 'Welcher Tag? Die Daten sagen es nicht eindeutig.',
        warum: [`Dieselben Gewichte kamen bei Charge ${b.charge_nr} an ${mehr(tage.length, 'Tag', 'Tagen')}: ${tage.map(tagText).join(', ')}.`,
                'Die App schlägt nichts vor, wo sie raten müsste — der Zettel selbst sagt es.'],
      },
    }
  }
  if (einzeln) return { muster: null, vorschlag: null }
  return {
    muster: 'ohne_kandidat',
    vorschlag: { art: 'von_hand', wo: 'arbeit', titel: 'Kein Tag passt — auf dem Zettel nachsehen.',
                 warum: [ohneGewicht
                   ? `${n === 1 ? 'Der Zettel hat' : 'Die Zettel haben'} kein Gewicht, an dem die App die Palette erkennen könnte. Charge ${b.charge_nr} kam an ${eingangstage.length === 0 ? 'keinem Tag vor der Arbeit' : `${mehr(eingangstage.length, 'Tag', 'Tagen')}: ${eingangstage.slice(-6).map(tagText).join(', ')}${eingangstage.length > 6 ? ' …' : ''}`}.`
                   : `Keines der Gewichte steht bei Charge ${b.charge_nr} im Wareneingang an einem anderen Tag, und keine andere Charge hat sie am ${tagText(von)}.`] },
  }
}

/** Das Gewicht eines Zettels, dessen Tag stimmt — siehe zettelDeutung. */
function gewichtDeutung(b: Befund, lage: ZettelLage, betroffen: Zettel[], hinweis: string | null): Omit<Deutung, 'treffer'> {
  const z0 = betroffen[0]
  const ids = betroffen.filter(z => z.eingangsdatum === z0.eingangsdatum).map(z => z.id)
  const n = ids.length
  const tr0 = zuZettel(z0, lage, ids)
  const vorne = hinweis ? [hinweis] : []
  if (betroffen.every(istPalox)) {
    return {
      muster: 'palox', betroffen,
      vorschlag: {
        art: 'so_lassen', titel: 'So lassen — ein Palox, gerechnet mit dem Zettel',
        warum: [...vorne,
          'Der Zettel gehört zu einem Palox (eine Kiste). Im Wareneingang stehen Palox oft mit einem geschätzten Gewicht (rund 300 kg) — genau gleich kann der Zettel dann nicht sein.',
          'Gerechnet wird mit dem Zettelgewicht minus Tara — das ist das gewogene.'],
      },
    }
  }
  const nahe = [...new Set(tr0.nahe.map(p => p.brutto_kg!))].sort((a, c) => a - c)
  if (nahe.length === 1) {
    const w = nahe[0]
    const dreher = istZahlendreher(w, z0.brutto_zettel_kg ?? 0)
    return {
      muster: dreher ? 'zahlendreher' : 'tippfehler', betroffen,
      vorschlag: {
        art: 'korrigieren', was: 'zettelgewicht', ids, vorher: String(z0.brutto_zettel_kg), nachher: String(w), sicher: 'wahrscheinlich',
        titel: `Zettelgewicht ${kgText(z0.brutto_zettel_kg)} → ${kgText(w)}${n > 1 ? ` an ${n} Zetteln` : ''}`,
        warum: [...vorne,
          dreher ? `Am ${tagText(z0.eingangsdatum)} kam bei Charge ${b.charge_nr} eine Palette mit ${kgText(w)} — dieselben Ziffern in anderer Folge.`
                 : `Am ${tagText(z0.eingangsdatum)} kam bei Charge ${b.charge_nr} eine Palette mit ${kgText(w)} — ${kgText(Math.abs(w - (z0.brutto_zettel_kg ?? 0)))} neben dem Zettel${z0.kisten ? `, mit denselben ${z0.kisten} Kisten` : ''}, und kein anderer Zettel hat sie.`,
          'Ein vertipptes Gewicht ist nie ganz sicher — der Zettel in der Halle sagt es.'],
        danach: 'Danach rechnet die App neu und nimmt für diese Palette das Gewicht aus dem Wareneingang.',
      },
    }
  }
  if (nahe.length > 1) {
    return {
      muster: 'mehrdeutig', betroffen,
      vorschlag: {
        art: 'von_hand', wo: 'arbeit', titel: 'Welche Palette? Mehrere liegen fast gleich schwer.',
        warum: [...vorne,
          `Am ${tagText(z0.eingangsdatum)} kamen bei Charge ${b.charge_nr} mehrere freie Paletten mit fast ${kgText(z0.brutto_zettel_kg)}: ${nahe.map(kgText).join(', ')}. Welche es war, sagt nur der Zettel.`,
          'Gerechnet wird mit dem Zettel — ein, zwei Kilo machen in der Rechnung kaum etwas aus.'],
      },
    }
  }
  if (tr0.fremd.length > 0) {
    return {
      muster: 'fremde_charge', betroffen,
      vorschlag: {
        art: 'von_hand', wo: 'arbeit', titel: `Gehört dieser Zettel zu Charge ${tr0.fremd[0]}?`,
        warum: [...vorne,
          `Am ${tagText(z0.eingangsdatum)} kam bei Charge ${tr0.fremd[0]} eine Palette mit genau ${kgText(z0.brutto_zettel_kg)}; bei Charge ${b.charge_nr} keine.`,
          'Eine einzelne Palette einer Nachbarcharge kann mitgelaufen sein. Mit einem Klick ändert die App das nicht.'],
      },
    }
  }
  const voll = volleKisten(lage.eigen)
  if (voll && z0.kisten && z0.kisten < voll * 0.8) {
    return {
      muster: 'teilpalette', betroffen,
      vorschlag: {
        art: 'so_lassen', titel: 'So lassen — eine Teilpalette, richtig gerechnet',
        warum: [...vorne,
          `Der Zettel nennt ${z0.kisten} Kisten; eine volle Palette dieser Charge hat ${voll}. Eine solche Palette wurde von Hand neu zusammengestellt und gewogen — im Wareneingang steht sie so nicht.`,
          'Gerechnet wird mit dem Zettel: Gewicht minus Kisten × Kistengewicht minus Palette. Das stimmt für eine Teilpalette.'],
      },
    }
  }
  const amTag = lage.eigen.filter(p => p.eingangsdatum === z0.eingangsdatum && p.brutto_kg !== null)
    .sort((x, y) => Math.abs(x.brutto_kg! - (z0.brutto_zettel_kg ?? 0)) - Math.abs(y.brutto_kg! - (z0.brutto_zettel_kg ?? 0)))
  return {
    muster: 'ohne_kandidat', betroffen,
    vorschlag: {
      art: 'von_hand', wo: 'arbeit', titel: 'Das Gewicht passt nicht — auf dem Zettel nachsehen.',
      warum: [...vorne,
        amTag.length > 0
          ? `Am ${tagText(z0.eingangsdatum)} kam bei Charge ${b.charge_nr} keine freie Palette mit bis 2 kg Unterschied; am nächsten: ${[...new Set(amTag.slice(0, 4).map(p => p.brutto_kg!))].slice(0, 3).map(kgText).join(', ')}.`
          : `Am ${tagText(z0.eingangsdatum)} kam bei Charge ${b.charge_nr} nichts.`,
        'Gerechnet wird mit dem Zettel — stimmt er, stimmt auch die Menge.'],
    },
  }
}

/**
 * Der Vorschlag für die übrigen Arten — ohne Daten nachzuladen. Ein Klick
 * nur dort, wo der Befund selbst sagt, was zu tun ist (Palette fraglich);
 * sonst „so lassen", wo es so stimmt oder sich von selbst heilt, oder der
 * Weg dorthin, wo es zu ändern wäre.
 */
export function artVorschlag(b: Befund): Vorschlag | null {
  const t = bezugTeile(b.bezug)
  switch (b.art) {
    case 'Palette fraglich':
      return t.typ === 'ausschuss_messung' && t.id !== null ? {
        art: 'korrigieren', was: 'mit_palette', ids: [t.id], vorher: 'true', nachher: 'false', sicher: 'wahrscheinlich',
        titel: '„mit Palette" abwählen — die Kisten standen direkt auf der Waage',
        warum: ['Nach Abzug der Palette bliebe weniger, als die Kisten selbst wiegen müssten.'],
        danach: 'Danach rechnet die App das Netto ohne Palette und neu.',
      } : null
    case 'Kistengewicht':
      return { art: 'so_lassen', titel: 'So lassen — heilt von selbst', warum: ['Sobald eine Arbeit dieses Kalibers Kisten oder fertige Paletten wiegt, kennt die App das Kistengewicht — rückwirkend auch für diese Arbeit.'] }
    case 'Wägung':
    case 'Verdunstung':
      return { art: 'so_lassen', titel: 'So lassen — zählt schon nicht in die Rate', warum: ['Die App lässt diese Wägung aus der Verdunstungsrate weg. Korrigieren lohnt nur, wenn das richtige Gewicht bekannt ist.'] }
    case 'Palox geleert':
      return { art: 'so_lassen', titel: 'So lassen — nichts zu korrigieren', warum: ['Was vor dem Leeren dazukam, weiss niemand; die App rechnet das Faule dieser Arbeit als unbekannt, nicht als null. Beim nächsten Mal in der Halle „Palox leeren" drücken.'] }
    case 'Ohne Nenner':
    case 'Kaliber fehlt':
      return b.auftrag_id ? { art: 'von_hand', wo: 'arbeit', titel: 'An der Arbeit nachtragen', warum: ['Was fehlt, weiss nur die Halle — in der Korrektur der Arbeit eintragen.'] } : null
    case 'Lieferung in der Zukunft':
      return { art: 'so_lassen', titel: 'So lassen, wenn er vordatiert ist', warum: ['Ein vordatierter Lieferschein ist in Ordnung: er zählt ab seinem Tag, und die Auffälligkeit verschwindet dann von selbst.', 'Ist das Datum vertippt, gehört es in Perigon berichtigt (dann die Datei neu einlesen) — oder unter Betrieb → Warenausgang, wenn er von Hand erfasst ist.'] }
    case 'Überzählung':
    case 'Lieferung ohne Eingang':
      return { art: 'von_hand', wo: 'perigon', titel: 'Im Reiter Perigon klären', warum: ['Ob eine Palette im Erntejournal fehlt oder ein Lieferschein auf die falsche Charge gebucht ist, zeigt der Fall der Charge im Reiter Perigon.'] }
    default:
      return b.auftrag_id ? { art: 'von_hand', wo: 'arbeit', titel: 'In der Korrektur der Arbeit prüfen', warum: ['Was zu ändern wäre, steht im Befund; ändern lässt es sich in der Korrektur der Arbeit.'] } : null
  }
}

/** Ist es eine Auffälligkeit, deren Zettel die App nachlädt? */
export const istZettelFall = (b: Befund): boolean =>
  (b.art === 'Zettelgewicht' || b.art === 'Zetteldatum') && b.auftrag_id !== null && /^zettel(datum)?:/.test(b.bezug ?? '')

/** Für den Chat: „Auffälligkeit 12 — Zetteldatum, Charge 1627, Arbeit 1602 (01.10.2026)". */
export function chatZeile(b: Befund, nr: number | null): string {
  const tag = tagIn(b.start_ts)
  return `Auffälligkeit ${nr ?? '?'} — ${b.art}, Charge ${b.charge_nr}${b.auftrag_id ? `, Arbeit ${b.auftrag_id}` : ''}${tag ? ` (${tagText(tag)})` : ''}`
}
