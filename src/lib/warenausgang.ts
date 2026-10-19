import type { Blatt, Zelle } from './xlsx'
import { zahl as alsZahlText } from './format.ts'

/**
 * Der Warenausgang aus dem Warenwirtschaftssystem (Perigon), Auswertung
 * „Abgleich Rückverfolgbarkeit". Der Betrieb lädt immer die **ganze** Datei
 * hoch, nicht nur die neuen Zeilen — die App muss also selbst erkennen, was sie
 * schon hat, was neu ist und was sich geändert hat.
 *
 * Aufbau der Datei (32 Spalten, eine Zeile je Charge-Zuordnung):
 *
 *   Position (AufPosId)   ein Artikel auf einem Lieferschein; Menge mal Gewicht
 *                         je Artikel ist die gelieferte Masse.
 *   Chargenzeile          AuftragsChargeManuell und AufPosBatchQuantity: welcher
 *                         Teil der Position aus welcher Charge kam. Eine
 *                         Position hat eine oder mehrere solcher Zeilen.
 *
 * Daraus folgen zwei Summen, die nie vermischt werden dürfen:
 *   - Positionsmasse (je AufPosId einmal): was den Betrieb verlassen hat.
 *   - Chargenmasse (je Chargenzeile): was davon einer Charge zugeordnet ist.
 * Die Differenz ist Ware ohne Chargenbezug — bekannt, aber keiner Charge
 * zuzuordnen. Sie zählt in der Bilanz und nicht in der Chargenrechnung.
 *
 * Reine Funktionen, kein Netz, kein DOM — damit sie prüfbar bleiben.
 */

/* ---------- Spalten ------------------------------------------------------- */

/** Kopfnamen kommen mal so, mal so geschrieben („…ArtikelmengeSoll" gegen
 *  „…ArtikelMengeSoll"). Verglichen wird deshalb ohne Gross- und
 *  Kleinschreibung und ohne Zeichen, die keine Buchstaben oder Ziffern sind. */
export function schluessel(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9äöü]/g, '')
}

export const SPALTEN = {
  journal: 'AuftragsJournal',
  auftragsnr: 'KundenAuftragsNr',
  ruestdatum: 'AuftragsRuestDatum',
  lieferdatum: 'AuftragsLieferDatum',
  kunde: 'AuftragsLieferant',
  artikel_id: 'AuftragsArtId',
  artikel: 'AuftragsArtikel',
  textlinie: 'Textlinie1',
  gebinde: 'AuftragsGebBez',
  gebinde_menge: 'AuftragsGebindemenge',
  gebinde_inhalt: 'AuftragsGebindeinhalt',
  menge: 'AuftragsArtikelMenge',
  batch_gebinde: 'AufPosBatchPackageQuantity Charge',
  batch_menge: 'AufPosBatchQuantity Charge',
  einheit: 'AuftragsArtikelEinheit',
  erloes: 'AuftragsErloesTotExkl',
  charge: 'AuftragsChargeManuell',
  produzent: 'LiefProdAdrName',
  pos_id: 'AufPosId',
  gewicht_je_artikel: 'GewichtProArtikel',
  gewicht_total: 'TotalGewicht',
  // Runde AO (0112): als welches Label der Artikel verkauft wurde (D, K, …)
  // und mit welchem die Charge geliefert wurde (LiefPrsGrpName: D, K, CH-K).
  preisgruppe: 'AuftragsPrsGrpBez',
  liefer_label: 'LiefPrsGrpName',
} as const
export type SpaltenName = keyof typeof SPALTEN

/** Die Spalten, ohne die die Datei nicht die erwartete Auswertung ist. */
export const PFLICHTSPALTEN: SpaltenName[] = [
  'lieferdatum', 'kunde', 'artikel_id', 'artikel', 'menge', 'batch_menge',
  'charge', 'pos_id', 'gewicht_je_artikel',
]

export interface Kopf {
  index: Partial<Record<SpaltenName, number>>
  fehlend: SpaltenName[]
  zeile: number
}

/** Sucht die Kopfzeile (sie steht nicht zwingend zuoberst) und ordnet die Spalten zu. */
export function kopfLesen(zeilen: Zelle[][]): Kopf | null {
  const gesucht = new Map(Object.entries(SPALTEN).map(([k, v]) => [schluessel(v), k as SpaltenName]))
  for (let i = 0; i < Math.min(zeilen.length, 20); i++) {
    const index: Partial<Record<SpaltenName, number>> = {}
    zeilen[i].forEach((z, j) => {
      const name = gesucht.get(schluessel(String(z ?? '')))
      if (name && index[name] === undefined) index[name] = j
    })
    if (Object.keys(index).length >= 6) {
      return { index, zeile: i, fehlend: PFLICHTSPALTEN.filter(s => index[s] === undefined) }
    }
  }
  return null
}

/* ---------- Zeilen -------------------------------------------------------- */

export interface AusgangZeile {
  quelle: string
  pos_id: number
  charge_extern: string          // leer, wenn die Zeile keine Charge nennt
  lauf_nr: number                // 1, 2, … bei mehrfach identischem Schlüssel
  fingerabdruck: string
  datum: string                  // ISO, Lieferdatum (ersatzweise Rüstdatum)
  journal: string
  auftragsnr: string
  kunde: string
  artikel_id: string
  artikel: string
  einheit: string
  menge: number                  // Positionsmenge in der Artikeleinheit
  gewicht_je_artikel: number     // kg je Stück; bei Einheit kg 1 — oder, falsch gepflegt, 0
  batch_menge: number            // Anteil dieser Charge an der Position
  /** Runde AR: leer (null), wenn Perigon die Masse nicht hergibt — ein Stückartikel ohne Stückgewicht. Nie 0 dafür. */
  kg_position: number | null
  kg_charge: number | null
  gebindeart: string | null
  gebinde_menge: number | null
  gebinde_inhalt: number | null
  produzent: string | null
  erloes: number | null
  /** 0112: AuftragsPrsGrpBez — das Label, als das verkauft wurde; LiefPrsGrpName — das der gelieferten Charge. */
  preisgruppe: string | null
  liefer_label: string | null
  zeile_nr: number               // Zeile in der Datei, für die Fehlermeldung
  /** Runde AS: die ganze Zeile, wie sie in der Datei steht — Spaltenname → Wert, alle Spalten. Nur für die Anzeige
   *  (ausgang_position.roh), nicht im Fingerabdruck und nicht in ausgang_uebernehmen. */
  roh?: RohZeile
}

/** Eine Zeile der Datei, wie sie dasteht: Spaltenname → Wert (Datum als JJJJ-MM-TT, leer als null). */
export type RohZeile = Record<string, string | number | null>

/** Runde AS: „eine Replika der Excel-Zeile, alle Spalten" — die Kopfzeile gibt die Namen. Doppelte Namen bekommen ihre Spaltennummer. */
export function rohZeile(kopfzeile: Zelle[], r: Zelle[]): RohZeile {
  const roh: RohZeile = {}
  const n = Math.max(kopfzeile.length, r.length)
  for (let j = 0; j < n; j++) {
    const name = String(kopfzeile[j] ?? '').trim() || `Spalte ${j + 1}`
    const schl = name in roh ? `${name} (${j + 1})` : name
    const z = r[j] ?? null
    roh[schl] = z === null || z === '' ? null
      : z instanceof Date ? z.toISOString().slice(0, 10)
      : typeof z === 'number' ? (Number.isFinite(z) ? z : null)
      : String(z).trim() === '' ? null : String(z).trim()
  }
  return roh
}

/* ---------- Die Zeile, wie Excel sie zeigt (Runde AT) --------------------- */

/** Die Zahlenformate, die die Perigon-Auswertung ihren Spalten gibt. */
export type ExcelFormat =
  | 'text'               // Text (@)
  | 'ganz'               // 0;-0
  | 'datum'              // dd.MM.yyyy
  | 'zwei'               // 0.00
  | 'tausend'            // #,##0.00
  | 'tausend_ohne_null'  // #,###.00 — Excel zeigt 0 als „.00"
  | 'tausend_ganz'       // #,##0

/**
 * Runde AT: Die Spalten der Auswertung „Abgleich Rückverfolgbarkeit" in der Folge der Datei (A bis AF), mit
 * Zahlenformat, Ausrichtung und Breite (in Excel-Zeichen), wie die Datei sie setzt. Der Betrieb: „die Zeile
 * mit den Spaltennamen ist anders" — die Datenbank (jsonb) merkt sich die Folge der Spalten nicht, und das
 * Fenster hatte nach den Spalten geordnet, mit denen die App rechnet, den Rest dahinter.
 */
export const PERIGON_ANSICHT: { name: string; format: ExcelFormat; rechts: boolean; breite: number }[] = [
  { name: 'AuftragsErfasser', format: 'text', rechts: false, breite: 21.1 },
  { name: 'AuftragsJournal', format: 'text', rechts: false, breite: 14.27 },
  { name: 'KundenAuftragsNr', format: 'ganz', rechts: true, breite: 14.27 },
  { name: 'AuftragsReferenz', format: 'text', rechts: false, breite: 14.27 },
  { name: 'AuftragsRuestDatum', format: 'datum', rechts: true, breite: 12 },
  { name: 'AuftragsLieferDatum', format: 'datum', rechts: true, breite: 12 },
  { name: 'AuftragsLieferant', format: 'text', rechts: false, breite: 27.92 },
  { name: 'AuftragsArtId', format: 'text', rechts: false, breite: 14.27 },
  { name: 'AuftragsArtikel', format: 'text', rechts: false, breite: 38.59 },
  { name: 'Textlinie1', format: 'text', rechts: false, breite: 37.02 },
  { name: 'AuftragsPrsGrpBez', format: 'text', rechts: false, breite: 14.27 },
  { name: 'AuftragsGebBez', format: 'text', rechts: false, breite: 23.38 },
  { name: 'AuftragsGebindemengeSoll', format: 'zwei', rechts: true, breite: 14.27 },
  { name: 'AuftragsArtikelMengeSoll', format: 'zwei', rechts: true, breite: 14.27 },
  { name: 'AuftragsGebindemenge', format: 'tausend_ohne_null', rechts: true, breite: 9.72 },
  { name: 'AuftragsGebindeinhalt', format: 'tausend', rechts: true, breite: 14.27 },
  { name: 'AuftragsArtikelMenge', format: 'tausend', rechts: true, breite: 14.27 },
  { name: 'AufPosBatchPackageQuantity Charge', format: 'zwei', rechts: true, breite: 14.27 },
  { name: 'AufPosBatchQuantity Charge', format: 'zwei', rechts: true, breite: 14.27 },
  { name: 'AuftragsArtikelEinheit', format: 'text', rechts: false, breite: 14.27 },
  { name: 'AuftragsErloesExkl', format: 'zwei', rechts: true, breite: 14.27 },
  { name: 'AuftragsErloesTotExkl', format: 'zwei', rechts: true, breite: 14.27 },
  { name: 'AuftragsChargeManuell', format: 'tausend_ganz', rechts: true, breite: 14.27 },
  { name: 'LiefProdAdrName', format: 'text', rechts: false, breite: 14.27 },
  { name: 'LiefHerkunft', format: 'text', rechts: false, breite: 14.27 },
  { name: 'LiefPrsGrpName', format: 'text', rechts: false, breite: 14.27 },
  { name: 'LiefCoopRegion', format: 'text', rechts: false, breite: 14.27 },
  // So steht es in der Datei: die nächsten beiden Mengen linksbündig.
  { name: 'LiefInitialMenge', format: 'tausend', rechts: false, breite: 14.27 },
  { name: 'LiefVerfügbareMenge', format: 'zwei', rechts: false, breite: 14.27 },
  { name: 'AufPosId', format: 'ganz', rechts: true, breite: 14.27 },
  { name: 'GewichtProArtikel', format: 'tausend', rechts: false, breite: 14.27 },
  { name: 'TotalGewicht', format: 'tausend', rechts: false, breite: 14.27 },
]

/** Der Spaltenbuchstabe in Excel: 0 → A, 25 → Z, 26 → AA. */
export function spaltenBuchstabe(i: number): string {
  return i < 26 ? String.fromCharCode(65 + i) : spaltenBuchstabe(Math.floor(i / 26) - 1) + String.fromCharCode(65 + (i % 26))
}

/** Ein Wert so, wie Excel ihn mit dem Format der Spalte zeigt. Text bleibt Text, leer bleibt leer. */
export function excelWert(wert: string | number | null | undefined, format: ExcelFormat): string {
  if (wert == null) return ''
  if (typeof wert === 'string') {
    const iso = format === 'datum' ? /^(\d{4})-(\d{2})-(\d{2})/.exec(wert) : null
    return iso ? `${iso[3]}.${iso[2]}.${iso[1]}` : wert
  }
  switch (format) {
    case 'ganz': return String(Math.round(wert))
    case 'zwei': return wert.toFixed(2)
    case 'tausend': return alsZahlText(wert, 2)
    case 'tausend_ganz': return alsZahlText(wert, 0)
    case 'tausend_ohne_null': return alsZahlText(wert, 2).replace(/^(-?)0(?=\.)/, '$1')
    default: return String(wert)
  }
}

export interface ExcelAnsicht {
  spalten: { name: string; buchstabe: string | null; rechts: boolean; breite: number }[]
  zeilen: string[][]
}

/**
 * Runde AT: Die gespeicherten Zeilen einer Position, wie Excel sie zeigt — Spalten in der Folge der Datei
 * (Namen so geschrieben, wie sie in der Datei stehen), Werte im Format ihrer Spalte. Spalten, die die
 * Auswertung heute nicht hat, kommen dahinter, in der Folge, in der sie gespeichert sind, als Text oder Zahl.
 */
export function excelAnsicht(roh: RohZeile[]): ExcelAnsicht {
  const namen = [...new Set(roh.flatMap(r => Object.keys(r)))]
  const bekannt = new Map(PERIGON_ANSICHT.map((s, i) => [schluessel(s.name), { ...s, i }]))
  const reihe = namen.map(n => ({ n, b: bekannt.get(schluessel(n)) }))
  const geordnet = [
    ...reihe.filter(x => x.b).sort((x, y) => x.b!.i - y.b!.i),
    ...reihe.filter(x => !x.b),
  ]
  return {
    spalten: geordnet.map(({ n, b }) => ({
      name: n, buchstabe: b ? spaltenBuchstabe(b.i) : null, rechts: b ? b.rechts : false, breite: b ? b.breite : 14.27,
    })),
    zeilen: roh.map(r => geordnet.map(({ n, b }) => {
      const w = r[n]
      return excelWert(w, b ? b.format : 'text')
    })),
  }
}

const runden = (n: number) => Math.round(n * 1000) / 1000

/**
 * Die Masse einer Perigon-Menge, in kg — dieselbe Regel wie `perigon_kg()` in
 * der Datenbank (0115):
 *   - Gewicht je Artikel > 0: Menge × Gewicht je Artikel (Stück × kg je Stück,
 *     bei kg-Artikeln × 1);
 *   - sonst, bei Einheit kg: die Menge selbst — sie ist schon das Gewicht;
 *   - sonst (Stück ohne Stückgewicht): unbekannt, null — nicht 0.
 * Runde AR: Bis hier galt Menge × Gewicht je Artikel ohne Ausnahme. Im
 * Perigon-Artikelstamm stand bei vielen kg-Artikeln 0 statt 1 — bei Imhof
 * BioProdukte 2024/25 86.7 t, die im Vergleich mit den Vorjahren als 0 kg
 * zählten, und diese Saison 340 kg, die nie eine Lieferung wurden.
 */
export function perigonKg(menge: number, gewichtJeArtikel: number | null, einheit: string): number | null {
  if (gewichtJeArtikel !== null && gewichtJeArtikel > 0) return runden(menge * gewichtJeArtikel)
  if (/^kg/i.test(einheit.trim())) return runden(menge)
  return null
}

function zahl(z: Zelle): number | null {
  if (typeof z === 'number') return Number.isFinite(z) ? z : null
  if (typeof z === 'string') {
    const n = Number(z.replace(/'/g, '').replace(',', '.').trim())
    return z.trim() !== '' && Number.isFinite(n) ? n : null
  }
  return null
}

function wort(z: Zelle): string {
  if (z === null || z === undefined) return ''
  if (z instanceof Date) return z.toISOString().slice(0, 10)
  return String(z).trim()
}

function datumIso(z: Zelle): string {
  if (z instanceof Date) return z.toISOString().slice(0, 10)
  const t = wort(z)
  const m = /^(\d{1,2})[.\/](\d{1,2})[.\/](\d{4})$/.exec(t)
  if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`
  return /^\d{4}-\d{2}-\d{2}/.test(t) ? t.slice(0, 10) : ''
}

/**
 * Fingerabdruck einer Zeile (FNV-1a, zweimal 32 Bit als Hex).
 *
 * Warum nicht SHA-256 wie bei der Rohdatei: Der Fingerabdruck wird für jede der
 * zwölftausend Zeilen gebraucht, und `crypto.subtle` ist asynchron. Hier geht es
 * nicht um Fälschungssicherheit, sondern um die Frage „hat sich diese Zeile seit
 * dem letzten Hochladen geändert?" — dafür genügt eine schnelle, gut streuende
 * Funktion.
 */
export function fingerabdruck(teile: (string | number | null)[]): string {
  let h1 = 0x811c9dc5, h2 = 0x01000193
  const s = teile.map(t => (t === null ? '' : String(t))).join('|')
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i)
    h1 = Math.imul(h1 ^ c, 0x01000193) >>> 0
    h2 = Math.imul(h2 ^ (c + i), 0x85ebca6b) >>> 0
  }
  return h1.toString(16).padStart(8, '0') + h2.toString(16).padStart(8, '0')
}

/** Liest ein Blatt in Zeilen um. Zeilen ohne Positions-Id oder Datum fallen weg. */
export function zeilenLesen(blatt: Blatt, quelle: string): {
  zeilen: AusgangZeile[]; kopf: Kopf | null; uebersprungen: number
} {
  const kopf = kopfLesen(blatt.zeilen)
  if (!kopf) return { zeilen: [], kopf: null, uebersprungen: blatt.zeilen.length }
  const w = (r: Zelle[], s: SpaltenName): Zelle => {
    const i = kopf.index[s]
    return i === undefined ? null : (r[i] ?? null)
  }
  const zeilen: AusgangZeile[] = []
  const gesehen = new Map<string, number>()
  let uebersprungen = 0
  for (let i = kopf.zeile + 1; i < blatt.zeilen.length; i++) {
    const r = blatt.zeilen[i]
    const pos = zahl(w(r, 'pos_id'))
    const datum = datumIso(w(r, 'lieferdatum')) || datumIso(w(r, 'ruestdatum'))
    if (pos === null || datum === '') {
      if (r.some(z => z !== null && z !== '')) uebersprungen++
      continue
    }
    const charge = wort(w(r, 'charge'))
    const stamm = `${quelle}|${pos}|${charge}`
    const lauf = (gesehen.get(stamm) ?? 0) + 1
    gesehen.set(stamm, lauf)
    const menge = zahl(w(r, 'menge')) ?? 0
    const gja = zahl(w(r, 'gewicht_je_artikel')) ?? 0
    const batch = zahl(w(r, 'batch_menge')) ?? 0
    const z: AusgangZeile = {
      quelle, pos_id: pos, charge_extern: charge, lauf_nr: lauf, fingerabdruck: '',
      datum,
      journal: wort(w(r, 'journal')),
      auftragsnr: wort(w(r, 'auftragsnr')),
      kunde: wort(w(r, 'kunde')),
      artikel_id: wort(w(r, 'artikel_id')),
      artikel: wort(w(r, 'artikel')) || wort(w(r, 'textlinie')),
      einheit: wort(w(r, 'einheit')),
      menge,
      gewicht_je_artikel: gja,
      batch_menge: batch,
      kg_position: perigonKg(menge, gja, wort(w(r, 'einheit'))),
      kg_charge: perigonKg(batch, gja, wort(w(r, 'einheit'))),
      gebindeart: wort(w(r, 'gebinde')) || null,
      gebinde_menge: zahl(w(r, 'gebinde_menge')),
      gebinde_inhalt: zahl(w(r, 'gebinde_inhalt')),
      produzent: wort(w(r, 'produzent')) || null,
      erloes: zahl(w(r, 'erloes')),
      preisgruppe: wort(w(r, 'preisgruppe')) || null,
      liefer_label: wort(w(r, 'liefer_label')) || null,
      zeile_nr: i + 1,
      roh: rohZeile(blatt.zeilen[kopf.zeile], r),
    }
    // Die zwei Felder aus 0112 (Preisgruppe, Label) gehören bewusst nicht in den
    // Fingerabdruck: sonst stünde nach dem Update jede bekannte Zeile als „geändert" da.
    // Sie gehen mit ausgang_historie_uebernehmen an die Zeilen, jedes Mal.
    z.fingerabdruck = fingerabdruck([
      z.datum, z.journal, z.kunde, z.artikel_id, z.artikel, z.einheit,
      z.menge, z.gewicht_je_artikel, z.batch_menge,
      z.gebindeart, z.gebinde_menge, z.gebinde_inhalt, z.produzent, z.erloes,
    ])
    zeilen.push(z)
  }
  return { zeilen, kopf, uebersprungen }
}

/* ---------- Alle Saisons: die Positionen für den Vergleich je Kunde (0112) -- */

export interface Position {
  pos_id: number; datum: string; journal: string; kunde: string; artikel_id: string; artikel: string
  preisgruppe: string | null; einheit: string; menge: number; gewicht_je_artikel: number
  gebindeart: string | null; gebinde_menge: number | null
  /** Runde AS (0116): alle Zeilen der Datei zu dieser Position (eine je Chargenzeile), mit allen Spalten. */
  roh: RohZeile[]
}

/**
 * Jede Position der Datei einmal — alle Saisons, nicht nur ab dem 1. Juli
 * 2026. Sie gehen nicht in die Bilanz, nur in den Vergleich je Kunde mit den
 * Vorjahren (Lagermanagement nach Artikel). Mitgenommen wird, was Kürbis ist und keine
 * interne Umbuchung (Journal L).
 */
export function positionenAllerSaisons(zeilen: AusgangZeile[], istWare: (z: AusgangZeile) => boolean): Position[] {
  const proPos = new Map<number, AusgangZeile>()
  const rohJe = new Map<number, RohZeile[]>()
  for (const z of zeilen) {
    if (!proPos.has(z.pos_id)) proPos.set(z.pos_id, z)
    if (z.roh) rohJe.set(z.pos_id, [...(rohJe.get(z.pos_id) ?? []), z.roh])
  }
  return [...proPos.values()]
    .filter(z => z.journal !== 'L' && istWare(z))
    .map(z => ({
      pos_id: z.pos_id, datum: z.datum, journal: z.journal, kunde: z.kunde, artikel_id: z.artikel_id, artikel: z.artikel,
      preisgruppe: z.preisgruppe, einheit: z.einheit, menge: z.menge, gewicht_je_artikel: z.gewicht_je_artikel,
      gebindeart: z.gebindeart, gebinde_menge: z.gebinde_menge, roh: rohJe.get(z.pos_id) ?? [],
    }))
}

/* ---------- Kürbis oder nicht? -------------------------------------------- */

/** Wörter, die einen Artikel trotz „Kürbis" im Namen ausschliessen: Buchungen
 *  und Arbeitsleistungen sind keine Ware, die je im Lager lag. */
export const KEINE_WARE = ['verrechnung', 'arbeit', 'lohn', 'transport', 'miete', 'gebühr']

export type Kuerbisurteil = 'ja' | 'nein' | 'vorschlag_ja' | 'vorschlag_nein'

/** Ein Artikel ist die Kennung plus der Name: dieselbe Kennung trug im
 *  Zeitverlauf verschiedene Artikel („kürbmubuk" war Butterkin und Muskat). */
export function artikelSchluessel(z: { artikel_id: string; artikel: string }): string {
  return `${z.artikel_id}|${z.artikel}`
}

/**
 * Ist das ein Kürbis? Die verbindliche Antwort steht in der Zuordnungstabelle,
 * die der Betriebsleiter einmal je Artikel bestätigt — Beobachtung statt
 * Vermutung. Solange sie fehlt, schlägt die Regel etwas vor, und der Vorschlag
 * ist als solcher gekennzeichnet.
 */
export function istKuerbis(
  z: { artikel_id: string; artikel: string },
  bestaetigt?: Map<string, boolean>,
): Kuerbisurteil {
  const b = bestaetigt?.get(artikelSchluessel(z))
  if (b !== undefined) return b ? 'ja' : 'nein'
  const t = `${z.artikel_id} ${z.artikel}`.toLowerCase()
  if (KEINE_WARE.some(x => t.includes(x))) return 'vorschlag_nein'
  return /k(ü|u|ue)rb/.test(t) ? 'vorschlag_ja' : 'vorschlag_nein'
}

export const zaehltAlsKuerbis = (u: Kuerbisurteil) => u === 'ja' || u === 'vorschlag_ja'

/* ---------- Abgleich mit dem, was schon da ist ---------------------------- */

export interface Bekannt { schluessel: string; fingerabdruck: string }
export interface Abgleich {
  neu: AusgangZeile[]
  geaendert: AusgangZeile[]
  unveraendert: number
  verschwunden: string[]     // war in der Datenbank, steht nicht mehr in der Datei
}

/**
 * „Bis wo kennt er die Daten schon, ab wo ist neu?" — der Betrieb lädt immer
 * die ganze Geschichte hoch. `bekanntBis` ist das jüngste Datum, das die
 * Datenbank von dieser Firma hat; neue Zeilen danach sind der erwartete
 * Zuwachs, neue Zeilen davor sind nachgetragene Positionen (und stehen
 * deshalb getrennt). Ohne bekannte Zeilen ist alles neu.
 */
export function neuAbwann(ab: Abgleich, bekanntBis: string | null): {
  bekanntBis: string | null; danach: AusgangZeile[]; davor: AusgangZeile[]; neuVon: string | null; neuBis: string | null
} {
  const danach = bekanntBis === null ? ab.neu : ab.neu.filter(z => z.datum > bekanntBis)
  const davor = bekanntBis === null ? [] : ab.neu.filter(z => z.datum <= bekanntBis)
  const daten = danach.map(z => z.datum).sort()
  return { bekanntBis, danach, davor, neuVon: daten[0] ?? null, neuBis: daten[daten.length - 1] ?? null }
}

export function zeilenSchluessel(z: AusgangZeile): string {
  return `${z.quelle}|${z.pos_id}|${z.charge_extern}|${z.lauf_nr}`
}

/**
 * Was ist neu, was hat sich geändert, was fehlt? Der Betrieb lädt jedes Mal die
 * ganze Datei hoch; ohne diesen Abgleich stünde jede Lieferung nach dem zweiten
 * Hochladen doppelt in der Bilanz.
 */
export function abgleichen(zeilen: AusgangZeile[], bekannt: Bekannt[]): Abgleich {
  const karte = new Map(bekannt.map(b => [b.schluessel, b.fingerabdruck]))
  const neu: AusgangZeile[] = []
  const geaendert: AusgangZeile[] = []
  let unveraendert = 0
  const gesehen = new Set<string>()
  for (const z of zeilen) {
    const s = zeilenSchluessel(z)
    gesehen.add(s)
    const alt = karte.get(s)
    if (alt === undefined) neu.push(z)
    else if (alt !== z.fingerabdruck) geaendert.push(z)
    else unveraendert++
  }
  return {
    neu, geaendert, unveraendert,
    verschwunden: bekannt.filter(b => !gesehen.has(b.schluessel)).map(b => b.schluessel),
  }
}

/* ---------- Zusammenfassung für den Bildschirm ---------------------------- */

export interface ArtikelBefund {
  schluessel: string; artikel_id: string; artikel: string
  urteil: Kuerbisurteil; zeilen: number; kg: number
}
export interface Befund {
  zeilen: number
  kuerbiszeilen: number
  positionen: number
  von: string
  bis: string
  kg_position: number
  kg_charge: number
  kg_ohne_charge: number
  /** Runde AR: Positionen, deren Masse Perigon nicht hergibt (Stück ohne Stückgewicht) — nicht in kg_position. */
  ohne_gewicht: { positionen: number; menge: number }
  chargen: { charge_extern: string; kg: number }[]
  artikel: ArtikelBefund[]
  journale: { journal: string; zeilen: number; kg: number }[]
}

/**
 * Was steht in dieser Datei? Die Positionsmasse wird je AufPosId **einmal**
 * gezählt — sonst zählt eine über drei Chargen aufgeteilte Lieferung dreifach.
 */
export function befund(zeilen: AusgangZeile[], bestaetigt?: Map<string, boolean>): Befund {
  const k = zeilen.filter(z => zaehltAlsKuerbis(istKuerbis(z, bestaetigt)))
  const positionen = new Map<string, AusgangZeile>()
  for (const z of k) positionen.set(`${z.quelle}|${z.pos_id}`, z)
  const kgPos = [...positionen.values()].reduce((s, z) => s + (z.kg_position ?? 0), 0)
  const ohneGewicht = [...positionen.values()].filter(z => z.kg_position === null && z.menge !== 0)
  const proCharge = new Map<string, number>()
  let kgCharge = 0
  for (const z of k) {
    if (!z.charge_extern || !z.kg_charge) continue
    proCharge.set(z.charge_extern, (proCharge.get(z.charge_extern) ?? 0) + z.kg_charge)
    kgCharge += z.kg_charge
  }
  const proArtikel = new Map<string, ArtikelBefund>()
  for (const z of zeilen) {
    const s = artikelSchluessel(z)
    const e = proArtikel.get(s) ?? {
      schluessel: s, artikel_id: z.artikel_id, artikel: z.artikel,
      urteil: istKuerbis(z, bestaetigt), zeilen: 0, kg: 0,
    }
    e.zeilen++
    e.kg = runden(e.kg + (z.kg_charge ?? 0))
    proArtikel.set(s, e)
  }
  const proJournal = new Map<string, { journal: string; zeilen: number; kg: number }>()
  for (const z of k) {
    const e = proJournal.get(z.journal) ?? { journal: z.journal, zeilen: 0, kg: 0 }
    e.zeilen++
    e.kg = runden(e.kg + (z.kg_charge ?? 0))
    proJournal.set(z.journal, e)
  }
  const daten = k.map(z => z.datum).filter(Boolean).sort()
  return {
    zeilen: zeilen.length,
    kuerbiszeilen: k.length,
    positionen: positionen.size,
    von: daten[0] ?? '',
    bis: daten[daten.length - 1] ?? '',
    kg_position: runden(kgPos),
    kg_charge: runden(kgCharge),
    kg_ohne_charge: runden(Math.max(kgPos - kgCharge, 0)),
    ohne_gewicht: { positionen: ohneGewicht.length, menge: runden(ohneGewicht.reduce((s, z) => s + z.menge, 0)) },
    chargen: [...proCharge.entries()]
      .map(([charge_extern, kg]) => ({ charge_extern, kg: runden(kg) }))
      .sort((a, b) => b.kg - a.kg),
    artikel: [...proArtikel.values()].sort((a, b) => b.kg - a.kg || b.zeilen - a.zeilen),
    journale: [...proJournal.values()].sort((a, b) => b.zeilen - a.zeilen),
  }
}

/* ---------- Von der Zeile zur Lieferung ----------------------------------- */

export interface Lieferung {
  extern_id: string
  datum: string
  charge_nr: number | null
  sorte: string | null
  kg: number
  gebindeart: string | null
  kunde: string
  bemerkung: string
}

/**
 * Aus den Zeilen einer Position werden Lieferungen: je Charge eine, und für den
 * Rest ohne Chargenbezug eine weitere. So bleibt die Summe der Lieferungen
 * gleich der gelieferten Masse — ohne Doppelzählung und ohne stillen Verlust.
 *
 * `chargeVon` löst die externe Chargennummer auf: für die eigene Ernte die
 * vierstellige Nummer aus der Charge-Registry, sonst nichts. `sorteVon` liefert
 * die Sorte aus der bestätigten Artikel-Zuordnung.
 *
 * Rücknahmen (negative Menge, etwa eine Gutschrift) kommen getrennt zurück und
 * werden **nicht** stillschweigend übergangen: `lieferung.kg` lässt nur positive
 * Mengen zu, und eine zurückgegangene Palette ist trotzdem eine Bewegung, die
 * jemand sehen muss. In den Dateien des Betriebs sind es zwei Zeilen in zwei
 * Jahren — hätte der Import sie einfach weggelassen, wäre die Bilanz um vier
 * Tonnen danebengelegen, ohne dass es irgendwo aufgefallen wäre.
 *
 * Runde AR: Eine Position, deren Masse Perigon nicht hergibt (Stück ohne
 * Stückgewicht), wird keine Lieferung — sie kommt mit `ohneGewicht` zurück und
 * steht beim Einlesen da, statt still als 0 kg zu verschwinden.
 */
export interface OhneGewicht { extern_id: string; datum: string; kunde: string; artikel: string; menge: number; einheit: string }
export function lieferungenBauen(
  zeilen: AusgangZeile[],
  chargeVon: (extern: string, zeile: AusgangZeile) => number | null,
  sorteVon: (z: AusgangZeile) => string | null,
): { lieferungen: Lieferung[]; ruecknahmen: Lieferung[]; ohneGewicht: OhneGewicht[] } {
  const proPos = new Map<string, AusgangZeile[]>()
  for (const z of zeilen) {
    const s = `${z.quelle}|${z.pos_id}`
    const liste = proPos.get(s)
    if (liste) liste.push(z); else proPos.set(s, [z])
  }
  const out: Lieferung[] = []
  const zurueck: Lieferung[] = []
  const ohneGewicht: OhneGewicht[] = []
  for (const gruppe of proPos.values()) {
    const erste = gruppe[0]
    const gesamt = erste.kg_position
    if (gesamt === null) {
      if (erste.menge !== 0) ohneGewicht.push({
        extern_id: `${erste.quelle}:${erste.pos_id}`, datum: erste.datum, kunde: erste.kunde,
        artikel: erste.artikel, menge: erste.menge, einheit: erste.einheit,
      })
      continue
    }
    if (gesamt < 0) {
      zurueck.push({
        extern_id: `${erste.quelle}:${erste.pos_id}:rueckgabe`,
        datum: erste.datum, charge_nr: erste.charge_extern ? chargeVon(erste.charge_extern, erste) : null,
        sorte: sorteVon(erste), kg: runden(-gesamt),
        gebindeart: erste.gebindeart, kunde: erste.kunde,
        bemerkung: 'Rücknahme (negative Menge in der Datei)',
      })
      continue
    }
    let zugeordnet = 0
    for (const z of gruppe) {
      if (!z.charge_extern || z.kg_charge === null || z.kg_charge <= 0) continue
      const kg = runden(Math.min(z.kg_charge, Math.max(gesamt - zugeordnet, 0)))
      if (kg <= 0) continue
      zugeordnet = runden(zugeordnet + kg)
      // Die Zeile geht mit: bei einer doppelten Perigon-Nummer entscheidet ihr Artikel.
      const nr = chargeVon(z.charge_extern, z)
      out.push({
        extern_id: `${z.quelle}:${z.pos_id}:${z.charge_extern}:${z.lauf_nr}`,
        datum: z.datum, charge_nr: nr, sorte: sorteVon(z), kg,
        gebindeart: z.gebindeart, kunde: z.kunde,
        bemerkung: nr === null ? `Charge ${z.charge_extern} (extern)` : '',
      })
    }
    const rest = runden(gesamt - zugeordnet)
    if (rest > 0) {
      out.push({
        extern_id: `${erste.quelle}:${erste.pos_id}:rest`,
        datum: erste.datum, charge_nr: null, sorte: sorteVon(erste), kg: rest,
        gebindeart: erste.gebindeart, kunde: erste.kunde,
        bemerkung: 'ohne Chargenbezug',
      })
    }
  }
  return { lieferungen: out, ruecknahmen: zurueck, ohneGewicht }
}

/* ---------- Welche Firma ist das? --------------------------------------- */

/**
 * Am 28. September hiess die neue Datei der einen Firma „Imhof Bioprodukte
 * Rückverfolgbarkeit ge…" statt „imhof-bioprodukte". Der Name traf kein
 * Muster, die App legte eine dritte Firma an — und 35 t standen doppelt in
 * der Bilanz. Der Betrieb: „stelle sicher dass er es besser checkt welche
 * datei er kriegt — es gibt nur 2".
 *
 * Darum entscheidet der **Inhalt**, nicht der Name: Positionsnummern sind
 * innerhalb einer Firma eindeutig. Kennt die Datenbank Positionen dieser
 * Datei schon unter einer Firma, ist es diese Firma — der Name darf sagen,
 * was er will. Erst wenn der Inhalt schweigt (nichts davon ist bekannt),
 * zählt der Name; und trifft auch der nichts, wird **nicht** still eine neue
 * Firma angelegt, sondern gefragt.
 */
export type QuelleGrund = 'inhalt' | 'name' | 'offen' | 'mehrdeutig'
export interface QuelleErkennung {
  code: string | null
  grund: QuelleGrund
  /** Je bekannter Firma: wie viele Positionen der Datei sie schon kennt. */
  treffer: { code: string; n: number }[]
}

/** Dateiname und Muster, vergleichbar gemacht: klein, ohne Umlaute, ohne Zeichen. */
export function nameNormalisiert(s: string): string {
  return s.toLowerCase()
    .replace(/ä/g, 'ae').replace(/ö/g, 'oe').replace(/ü/g, 'ue').replace(/ß/g, 'ss')
    .replace(/[^a-z0-9]/g, '')
}

/** Der Schlüssel einer Zeile ohne die Firma — damit sich Dateien und Firmen vergleichen lassen. */
export function positionsSchluessel(z: { pos_id: number; charge_extern: string; lauf_nr: number }): string {
  return `${z.pos_id}|${z.charge_extern}|${z.lauf_nr}`
}

export function quelleErkennen(
  dateiname: string,
  zeilen: { pos_id: number; charge_extern: string; lauf_nr: number }[],
  quellen: { code: string; dateiname_muster: string | null }[],
  bekannt: Map<string, Set<string>>,       // Firma → Positionsschlüssel, die sie schon hat
): QuelleErkennung {
  const meine = new Set(zeilen.map(positionsSchluessel))
  const treffer = quellen
    .map(q => ({ code: q.code, n: [...(bekannt.get(q.code) ?? [])].filter(k => meine.has(k)).length }))
    .filter(t => t.n > 0)
    .sort((a, b) => b.n - a.n)
  if (treffer.length === 1) return { code: treffer[0].code, grund: 'inhalt', treffer }
  if (treffer.length > 1) return { code: null, grund: 'mehrdeutig', treffer }
  // Der Inhalt schweigt: der Name — das längste Muster, das im Namen steckt
  // („imhofbioprodukte" schlägt „imhofbio", sonst träfe die kurze Firma jede Datei der langen).
  const name = nameNormalisiert(dateiname)
  const passend = quellen
    .filter(q => q.dateiname_muster && nameNormalisiert(q.dateiname_muster).length > 0 && name.includes(nameNormalisiert(q.dateiname_muster)))
    .sort((a, b) => nameNormalisiert(b.dateiname_muster!).length - nameNormalisiert(a.dateiname_muster!).length)
  if (passend.length > 0) return { code: passend[0].code, grund: 'name', treffer }
  return { code: null, grund: 'offen', treffer }
}

/** Vorschlag für die Herkunft einer Datei: der Dateiname ohne Beiwerk. */
export function quelleVorschlag(dateiname: string): string {
  return dateiname
    .replace(/\.[a-z]+$/i, '')
    .replace(/abgleich|rückverfolgbarkeit|ruckverfolgbarkeit|seitanfangjahr|gemüse|gemuse|gemuese/gi, ' ')
    .replace(/\d{2,}/g, ' ')
    .trim().toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')
    .slice(0, 40) || 'unbekannt'
}

/* ---------- Die Charge zu einer Chargennummer der Datei ------------------ */

/** Was der Auflöser über eine Charge wissen muss (aus der Tabelle charge). */
export interface ChargeKurz { nr: number; sorte: string; perigon_nr: number | null }

/**
 * Löst die Chargennummer einer Zeile auf: vierstellig ist die eigene Nummer,
 * sechsstellig die Nummer derselben Ware im Perigon der anderen Firma
 * (charge.perigon_nr, aus der Planungsdatei). Eine Perigon-Nummer kann an
 * zwei Chargen stehen (198976: Butterkin und Tiana in Rümlang) — dann
 * entscheidet die Sorte, die der Artikel nahelegt; ohne sie bleibt die Zeile
 * ohne Chargenbezug, damit nichts geraten wird.
 */
export function chargeAufloeser(
  chargen: ChargeKurz[], sorteVonArtikel: (z: { artikel_id: string; artikel: string }) => string | null = () => null,
): (chargeExtern: string, zeile?: { artikel_id: string; artikel: string }) => number | null {
  const eigene = new Map(chargen.map(c => [c.nr, c]))
  const perigon = new Map<number, ChargeKurz[]>()
  for (const c of chargen) {
    if (c.perigon_nr === null) continue
    perigon.set(c.perigon_nr, [...(perigon.get(c.perigon_nr) ?? []), c])
  }
  return (chargeExtern, zeile) => {
    const ziffern = chargeExtern.replace(/\D/g, '')
    if (!ziffern) return null
    const n = Number(ziffern)
    if (eigene.has(n)) return n
    const treffer = perigon.get(n) ?? []
    if (treffer.length === 1) return treffer[0].nr
    if (treffer.length > 1 && zeile) {
      const sorte = sorteVonArtikel(zeile)
      const passend = treffer.filter(c => c.sorte === sorte)
      if (passend.length === 1) return passend[0].nr
    }
    return null
  }
}

/* ---------- Eine Lieferung erklären (Runde AS) ----------------------------- */

/** Was das Lieferungs-Fenster über eine Position weiss — aus ausgang_position und den Zeilen der Datei. */
export interface PositionKurz {
  menge: number | null; einheit: string | null; gewicht_je_artikel: number | null; kg: number | null
  preisgruppe?: string | null
}
export interface ChargenzeileKurz { charge_extern: string; batch_menge: number | null; kg_charge: number | null; liefer_label: string | null }

const zahlText = (n: number) => n.toLocaleString('de-CH', { maximumFractionDigits: 3 })
const labelText = (l: string | null | undefined) => {
  const u = (l ?? '').toUpperCase()
  return u.startsWith('D') ? 'Demeter' : /^(K|CH-K)/.test(u) ? 'Knospe' : null
}

/**
 * Die Deutung einer Perigon-Position in ganzen Sätzen — „160 Stk. × 1.5 kg je
 * Stück = 240 kg" —, nach derselben Regel wie perigonKg und perigon_kg (0115).
 * Der Betrieb: „eine kurze Interpretation, wie du daraus die Kilos berechnest".
 */
export function lieferungDeutung(p: PositionKurz, zeilen: ChargenzeileKurz[]): string[] {
  const s: string[] = []
  const menge = p.menge ?? 0, e = (p.einheit ?? '').trim(), gja = p.gewicht_je_artikel
  const istKg = /^kg/i.test(e)
  if (gja !== null && gja > 0 && istKg && gja === 1) s.push(`Menge ${zahlText(menge)} kg — die Menge ist schon das Gewicht.`)
  else if (gja !== null && gja > 0) s.push(`${zahlText(menge)} ${e || 'Stück'} × ${zahlText(gja)} kg je ${istKg ? 'kg' : (e || 'Stück')} = ${zahlText(perigonKg(menge, gja, e) ?? 0)} kg.`)
  else if (istKg) s.push(`Menge ${zahlText(menge)} kg; das Gewicht je Artikel steht in Perigon auf ${gja ?? 'leer'} — bei einem kg-Artikel ist die Menge das Gewicht: ${zahlText(menge)} kg.`)
  else s.push(`${zahlText(menge)} ${e || 'Stück'}, aber Perigon kennt kein Stückgewicht — die Masse ist unbekannt, nicht 0. Steht es im Perigon-Artikelstamm, die Datei neu einlesen.`)
  const mitCharge = zeilen.filter(z => z.charge_extern !== '')
  for (const z of mitCharge) {
    const kgC = z.kg_charge ?? (z.batch_menge != null ? perigonKg(z.batch_menge, gja, e) : null)
    s.push(`Charge ${z.charge_extern}: ${z.batch_menge != null ? `${zahlText(z.batch_menge)} ${e || 'Stück'}` : 'Menge offen'}`
      + `${kgC != null ? ` → ${zahlText(kgC)} kg` : ' → Masse unbekannt'}${labelText(z.liefer_label) ? `, geliefert als ${labelText(z.liefer_label)}` : ''}.`)
  }
  const zugeordnet = mitCharge.reduce((a, z) => a + (z.kg_charge ?? 0), 0)
  if (mitCharge.length === 0) s.push('Keine Charge genannt — die Masse zählt im Warenausgang, aber keiner Charge.')
  else if (p.kg != null && p.kg - zugeordnet > 0.005) s.push(`${zahlText(Math.round((p.kg - zugeordnet) * 1000) / 1000)} kg der Position nennen keine Charge — sie zählen im Warenausgang, aber keiner Charge.`)
  const verkauft = labelText(p.preisgruppe), geliefert = [...new Set(mitCharge.map(z => labelText(z.liefer_label)).filter(Boolean))]
  if (verkauft) s.push(`Verkauft als ${verkauft} (Preisgruppe ${p.preisgruppe})${geliefert.length > 0 && !geliefert.includes(verkauft) ? ` — geliefert als ${geliefert.join(' und ')}` : ''}.`)
  return s
}
