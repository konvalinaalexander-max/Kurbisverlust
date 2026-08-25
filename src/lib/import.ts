/**
 * Erkennt und liest Palettendaten aus dem Kürbis-Erntejournal (der bestehenden
 * Wareneingang-App). Quelle ist deren Google Sheet, Tab „Ertragsjournal".
 *
 * Bewusst tolerant: Die Daten kommen entweder eingefügt (Tab- oder
 * Semikolon-getrennt) oder als veröffentlichte CSV. Das Journal hat in Zeile 1
 * einen verbundenen Hinweistext, in Zeile 2 die Köpfe, ab Zeile 3 die Daten —
 * die Kopfzeile wird deshalb gesucht, nicht als erste Zeile angenommen.
 *
 * Verknüpfung zur Charge: Das Journal führt keine Chargennummer, wohl aber
 * Schlag und Sorte. Genau daraus ist die Charge eindeutig (Registry §7). Gibt es
 * doch eine Chargennummer-Spalte, hat sie Vorrang.
 *
 * Reine Funktionen ohne Netz/DOM, damit sie testbar bleiben.
 */

export interface ChargeRef { nr: number; schlag: string; sorte: string }

export interface RohPalette {
  charge_nr: number
  eingangsdatum: string        // ISO
  brutto_kg: number
  kisten: number | null
  gebindeart: string | null
  extern_id: string
}

export interface ImportBericht {
  paletten: RohPalette[]
  probleme: string[]
  quelle: 'chargennummer' | 'schlag-sorte' | null
  kopf: string[]
}

/** Erkennt den Trenner und zerlegt in Zellen; einfache Anführungszeichen-Regel. */
export function tabelleLesen(text: string): string[][] {
  const zeilen = text.replace(/\r\n/g, '\n').split('\n')
  const trenner = erkenneTrenner(zeilen)
  return zeilen
    .map(z => zerlege(z, trenner))
    .filter(z => z.some(feld => feld.trim() !== ''))
}

function erkenneTrenner(zeilen: string[]): string {
  // Nicht die erste Zeile befragen — im Journal ist das ein Hinweistext ohne
  // Trenner. Stattdessen den Trenner nehmen, der über alle Zeilen am häufigsten
  // vorkommt. Tab vor Semikolon vor Komma, wenn es gleich steht.
  let bester = ',', meiste = 0
  for (const t of ['\t', ';', ',']) {
    const summe = zeilen.reduce((n, z) => n + z.split(t).length - 1, 0)
    if (summe > meiste) { meiste = summe; bester = t }
  }
  return bester
}

/** Zerlegt eine Zeile und beachtet Felder in Anführungszeichen (CSV mit Kommas). */
function zerlege(zeile: string, trenner: string): string[] {
  const felder: string[] = []
  let feld = ''
  let inQuotes = false
  for (let i = 0; i < zeile.length; i++) {
    const c = zeile[i]
    if (inQuotes) {
      if (c === '"' && zeile[i + 1] === '"') { feld += '"'; i++ }
      else if (c === '"') inQuotes = false
      else feld += c
    } else if (c === '"') {
      inQuotes = true
    } else if (c === trenner) {
      felder.push(feld); feld = ''
    } else {
      feld += c
    }
  }
  felder.push(feld)
  return felder.map(f => f.trim())
}

/** Synonyme je Feld; alles kleingeschrieben und ohne Sonderzeichen verglichen. */
const SPALTEN: Record<string, string[]> = {
  chargennummer: ['charge', 'chargennummer', 'chargenr', 'charge nr'],
  eingangsdatum: ['datum', 'eingangsdatum', 'eingang'],
  schlag: ['schlag', 'feld', 'standort'],
  sorte: ['sorte'],
  brutto_kg: ['gewicht brutto', 'gewicht brutto kg', 'brutto', 'bruttogewicht', 'gewicht'],
  kisten: ['anzahl gebinde', 'anzahl kisten', 'kisten', 'kistenzahl', 'gebinde'],
  gebindeart: ['gebindeart', 'gebindeart leer g2', 'gebinde art', 'art'],
  extern_id: ['id app', 'id', 'palettenkennung', 'kennung'],
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim()

function findeSpalte(kopf: string[], feld: string): number {
  const namen = SPALTEN[feld]
  // exakter Treffer vor Teiltreffer, damit „Sorte" nicht in „Gebindeart" fällt
  const nk = kopf.map(norm)
  for (const name of namen) { const i = nk.indexOf(name); if (i !== -1) return i }
  for (let i = 0; i < nk.length; i++) if (namen.some(n => nk[i].startsWith(n))) return i
  return -1
}

/** Sucht die Kopfzeile (bis zu 6 Zeilen weit) — im Journal steht davor ein Hinweis. */
function findeKopf(zeilen: string[][]): number {
  for (let i = 0; i < Math.min(zeilen.length, 6); i++) {
    const nk = zeilen[i].map(norm)
    const hatSchlag = nk.some(z => z === 'schlag' || z === 'feld')
    const hatSorte = nk.some(z => z === 'sorte')
    const hatCharge = nk.some(z => SPALTEN.chargennummer.includes(z))
    if ((hatSchlag && hatSorte) || hatCharge) return i
  }
  return 0
}

export function datumLesen(roh: string): string | null {
  const t = roh.trim()
  if (/^\d{4}-\d{2}-\d{2}/.test(t)) return t.slice(0, 10)
  const m = t.match(/^(\d{1,2})[.\/](\d{1,2})[.\/](\d{2,4})/)
  if (!m) return null
  const jahr = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])
  const p = (n: string) => n.padStart(2, '0')
  const monat = Number(m[2]), tag = Number(m[1])
  if (monat < 1 || monat > 12 || tag < 1 || tag > 31) return null
  return `${jahr}-${p(m[2])}-${p(m[1])}`
}

/** Leere Gebindeart = Standard „G2" (so ist die Spalte im Journal gemeint). */
export function gebindeNormalisieren(roh: string | null | undefined): string {
  const t = (roh ?? '').trim()
  return t === '' ? 'G2' : t
}

export function importErkennen(text: string, chargen: ChargeRef[]): ImportBericht {
  const zeilen = tabelleLesen(text)
  if (zeilen.length < 2) {
    return { paletten: [], probleme: ['Zu wenig Zeilen — Kopf und mindestens eine Datenzeile nötig.'],
             quelle: null, kopf: [] }
  }

  const kopfIdx = findeKopf(zeilen)
  const kopf = zeilen[kopfIdx]
  const idx = Object.fromEntries(Object.keys(SPALTEN).map(f => [f, findeSpalte(kopf, f)]))

  const perCharge = idx.chargennummer !== -1
  const perSchlagSorte = idx.schlag !== -1 && idx.sorte !== -1
  if (idx.eingangsdatum === -1 || idx.brutto_kg === -1 || (!perCharge && !perSchlagSorte)) {
    return {
      paletten: [], quelle: null, kopf,
      probleme: [`Nötige Spalten nicht gefunden. Erkannt: ${kopf.join(', ')}. `
        + 'Gebraucht werden Datum, Brutto und entweder eine Chargennummer oder Schlag + Sorte.'],
    }
  }

  // Charge-Nachschlag über Schlag+Sorte
  const chargeVon = new Map<string, number>()
  for (const c of chargen) chargeVon.set(`${norm(c.schlag)}|${norm(c.sorte)}`, c.nr)
  const bekannteNr = new Set(chargen.map(c => c.nr))

  const paletten: RohPalette[] = []
  const probleme: string[] = []
  const laufNr = new Map<string, number>()

  for (let r = kopfIdx + 1; r < zeilen.length; r++) {
    const f = zeilen[r]
    const zeileNr = r + 1
    const brutto = zahl(f[idx.brutto_kg])
    // Datenzeilen erkennt das Journal an Brutto als Zahl > 0 — so fallen
    // Hinweiszeilen, Summenzeilen und Leerzeilen von selbst heraus.
    if (brutto === null || brutto <= 0) continue

    let chargeNr: number | null = null
    if (perCharge) {
      const nr = Number((f[idx.chargennummer] ?? '').trim())
      if (bekannteNr.has(nr)) chargeNr = nr
    }
    if (chargeNr === null && perSchlagSorte) {
      const schlag = f[idx.schlag] ?? '', sorte = f[idx.sorte] ?? ''
      chargeNr = chargeVon.get(`${norm(schlag)}|${norm(sorte)}`) ?? null
      if (chargeNr === null && (schlag.trim() || sorte.trim())) {
        probleme.push(`Zeile ${zeileNr}: keine Charge für „${schlag.trim()} · ${sorte.trim()}"`)
        continue
      }
    }
    if (chargeNr === null) {
      probleme.push(`Zeile ${zeileNr}: Charge nicht bestimmbar`)
      continue
    }

    const datum = datumLesen(f[idx.eingangsdatum] ?? '')
    if (!datum) { probleme.push(`Zeile ${zeileNr}: Datum „${f[idx.eingangsdatum]}" nicht lesbar`); continue }

    const kisten = idx.kisten !== -1 ? zahl(f[idx.kisten]) : null
    const gebinde = idx.gebindeart !== -1 ? gebindeNormalisieren(f[idx.gebindeart]) : null

    // Stabile Kennung: die App-ID aus Spalte K, sonst aus dem Zeileninhalt.
    let extern: string
    const kennung = idx.extern_id !== -1 ? (f[idx.extern_id] ?? '').trim() : ''
    if (kennung) {
      extern = `journal:${kennung}`
    } else {
      const kern = [chargeNr, datum, brutto, kisten ?? '', gebinde ?? ''].join('|')
      const n = (laufNr.get(kern) ?? 0) + 1
      laufNr.set(kern, n)
      extern = `${kern}#${n}`
    }

    paletten.push({ charge_nr: chargeNr, eingangsdatum: datum, brutto_kg: brutto,
                    kisten, gebindeart: gebinde, extern_id: extern })
  }

  return { paletten, probleme, kopf,
           quelle: perCharge ? 'chargennummer' : 'schlag-sorte' }
}

function zahl(roh: string | undefined): number | null {
  if (roh === undefined) return null
  const t = roh.trim().replace(/['\s]/g, '').replace(',', '.')
  if (t === '') return null
  const n = Number(t)
  return Number.isFinite(n) ? n : null
}
