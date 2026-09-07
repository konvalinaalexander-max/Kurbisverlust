import type { Blatt, Zelle } from './xlsx'

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
  gewicht_je_artikel: number     // kg je Stück; bei Einheit kg ist das 1
  batch_menge: number            // Anteil dieser Charge an der Position
  kg_position: number
  kg_charge: number
  gebindeart: string | null
  gebinde_menge: number | null
  gebinde_inhalt: number | null
  produzent: string | null
  erloes: number | null
  zeile_nr: number               // Zeile in der Datei, für die Fehlermeldung
}

const runden = (n: number) => Math.round(n * 1000) / 1000

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
      kg_position: runden(menge * gja),
      kg_charge: runden(batch * gja),
      gebindeart: wort(w(r, 'gebinde')) || null,
      gebinde_menge: zahl(w(r, 'gebinde_menge')),
      gebinde_inhalt: zahl(w(r, 'gebinde_inhalt')),
      produzent: wort(w(r, 'produzent')) || null,
      erloes: zahl(w(r, 'erloes')),
      zeile_nr: i + 1,
    }
    z.fingerabdruck = fingerabdruck([
      z.datum, z.journal, z.kunde, z.artikel_id, z.artikel, z.einheit,
      z.menge, z.gewicht_je_artikel, z.batch_menge,
      z.gebindeart, z.gebinde_menge, z.gebinde_inhalt, z.produzent, z.erloes,
    ])
    zeilen.push(z)
  }
  return { zeilen, kopf, uebersprungen }
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
  const kgPos = [...positionen.values()].reduce((s, z) => s + z.kg_position, 0)
  const proCharge = new Map<string, number>()
  let kgCharge = 0
  for (const z of k) {
    if (!z.charge_extern || z.kg_charge === 0) continue
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
    e.kg = runden(e.kg + z.kg_charge)
    proArtikel.set(s, e)
  }
  const proJournal = new Map<string, { journal: string; zeilen: number; kg: number }>()
  for (const z of k) {
    const e = proJournal.get(z.journal) ?? { journal: z.journal, zeilen: 0, kg: 0 }
    e.zeilen++
    e.kg = runden(e.kg + z.kg_charge)
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
 */
export function lieferungenBauen(
  zeilen: AusgangZeile[],
  chargeVon: (extern: string) => number | null,
  sorteVon: (z: AusgangZeile) => string | null,
): { lieferungen: Lieferung[]; ruecknahmen: Lieferung[] } {
  const proPos = new Map<string, AusgangZeile[]>()
  for (const z of zeilen) {
    const s = `${z.quelle}|${z.pos_id}`
    const liste = proPos.get(s)
    if (liste) liste.push(z); else proPos.set(s, [z])
  }
  const out: Lieferung[] = []
  const zurueck: Lieferung[] = []
  for (const gruppe of proPos.values()) {
    const erste = gruppe[0]
    const gesamt = erste.kg_position
    if (gesamt < 0) {
      zurueck.push({
        extern_id: `${erste.quelle}:${erste.pos_id}:rueckgabe`,
        datum: erste.datum, charge_nr: erste.charge_extern ? chargeVon(erste.charge_extern) : null,
        sorte: sorteVon(erste), kg: runden(-gesamt),
        gebindeart: erste.gebindeart, kunde: erste.kunde,
        bemerkung: 'Rücknahme (negative Menge in der Datei)',
      })
      continue
    }
    let zugeordnet = 0
    for (const z of gruppe) {
      if (!z.charge_extern || z.kg_charge <= 0) continue
      const kg = runden(Math.min(z.kg_charge, Math.max(gesamt - zugeordnet, 0)))
      if (kg <= 0) continue
      zugeordnet = runden(zugeordnet + kg)
      const nr = chargeVon(z.charge_extern)
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
  return { lieferungen: out, ruecknahmen: zurueck }
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
