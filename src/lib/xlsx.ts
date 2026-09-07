/**
 * Ein Excel-Blatt lesen — ohne Bibliothek.
 *
 * Eine .xlsx ist ein ZIP mit XML darin. Beides kann der Browser von Haus aus:
 * `DecompressionStream('deflate-raw')` packt aus, `DOMParser` liest XML. Eine
 * Tabellen-Bibliothek wäre eine Abhängigkeit mehr, die in fünf Jahren nicht
 * mehr baut — und wir brauchen von ihr nur einen Bruchteil.
 *
 * Was hier bewusst *nicht* passiert: Formeln rechnen, Formate deuten, Bilder
 * lesen. Gebraucht werden Zellwerte als Text, Zahl oder Datum.
 *
 * Grenzen, die gemeldet und nicht verschwiegen werden: ZIP64 (Dateien über
 * 4 GB) und andere Packverfahren als „deflate" und „gespeichert".
 */

export type Zelle = string | number | Date | boolean | null
export interface Blatt { name: string; zeilen: Zelle[][] }

/* ---------- ZIP ---------------------------------------------------------- */

interface Eintrag { name: string; verfahren: number; start: number; laenge: number; roh: number }

/** Liest das Zentralverzeichnis am Dateiende — dort steht, was drin ist. */
function verzeichnis(buf: Uint8Array): Eintrag[] {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength)
  let eocd = -1
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 66000); i--) {
    if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break }
  }
  if (eocd < 0) throw new Error('Das ist keine .xlsx-Datei (kein ZIP-Ende gefunden).')
  const anzahl = dv.getUint16(eocd + 10, true)
  let p = dv.getUint32(eocd + 16, true)
  if (p === 0xffffffff) throw new Error('ZIP64 wird nicht gelesen — die Datei ist zu gross.')
  const eintraege: Eintrag[] = []
  for (let i = 0; i < anzahl; i++) {
    if (dv.getUint32(p, true) !== 0x02014b50) break
    const verfahren = dv.getUint16(p + 10, true)
    const laenge = dv.getUint32(p + 20, true)
    const roh = dv.getUint32(p + 24, true)
    const nLen = dv.getUint16(p + 28, true)
    const eLen = dv.getUint16(p + 30, true)
    const kLen = dv.getUint16(p + 32, true)
    const versatz = dv.getUint32(p + 42, true)
    const name = new TextDecoder().decode(buf.subarray(p + 46, p + 46 + nLen))
    // Der lokale Kopf wiederholt die Längen — erst dahinter beginnen die Daten.
    const lNam = dv.getUint16(versatz + 26, true)
    const lExt = dv.getUint16(versatz + 28, true)
    eintraege.push({ name, verfahren, start: versatz + 30 + lNam + lExt, laenge, roh })
    p += 46 + nLen + eLen + kLen
  }
  return eintraege
}

async function auspacken(buf: Uint8Array, e: Eintrag): Promise<string> {
  const daten = buf.subarray(e.start, e.start + e.laenge)
  if (e.verfahren === 0) return new TextDecoder().decode(daten)
  if (e.verfahren !== 8) throw new Error(`Unbekanntes Packverfahren ${e.verfahren} in ${e.name}.`)
  const strom = new Blob([daten as unknown as BlobPart]).stream()
    .pipeThrough(new DecompressionStream('deflate-raw'))
  return new TextDecoder().decode(new Uint8Array(await new Response(strom).arrayBuffer()))
}

/* ---------- XML ----------------------------------------------------------- */
// Ein voller XML-Baum für ein Blatt mit 12 000 Zeilen kostet viel Speicher und
// bringt nichts: Die Struktur ist flach und immer gleich. Deshalb wird mit
// regulären Ausdrücken über die Zellen gelaufen — das ist hier kein Missbrauch,
// sondern die einzige Stelle, an der die Form vollständig bekannt ist.

const ENTITAETEN: Record<string, string> = {
  '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'",
}
function text(s: string): string {
  return s.replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
          .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCodePoint(parseInt(n, 16)))
          .replace(/&(amp|lt|gt|quot|apos);/g, m => ENTITAETEN[m])
}

/** Alle <t>-Inhalte eines Knotens, zusammengehängt (formatierter Text ist geteilt). */
function tInhalt(xml: string): string {
  let s = ''
  for (const m of xml.matchAll(/<t[^>]*\/>|<t[^>]*>([\s\S]*?)<\/t>/g)) s += text(m[1] ?? '')
  return s
}

function sharedStrings(xml: string): string[] {
  const out: string[] = []
  for (const m of xml.matchAll(/<si>([\s\S]*?)<\/si>|<si\/>/g)) out.push(tInhalt(m[1] ?? ''))
  return out
}

/** Welche Zellformate sind Datumsformate? Nötig, weil Excel Daten als Zahl speichert. */
function datumsformate(stylesXml: string): Set<number> {
  const eigene = new Map<number, string>()
  for (const m of stylesXml.matchAll(/<numFmt[^>]*numFmtId="(\d+)"[^>]*formatCode="([^"]*)"/g)) {
    eigene.set(Number(m[1]), text(m[2]))
  }
  const eingebaut = new Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47])
  const istDatum = (id: number) => {
    if (eingebaut.has(id)) return true
    const code = eigene.get(id)
    if (!code) return false
    // Anführungszeichen und Farbangaben raus, dann auf Datums-/Zeitzeichen prüfen.
    const rein = code.replace(/"[^"]*"/g, '').replace(/\[[^\]]*\]/g, '')
    return /[ymdhs]/i.test(rein) && !/^[^ymd]*general[^ymd]*$/i.test(rein)
  }
  const xfs = stylesXml.match(/<cellXfs[\s\S]*?<\/cellXfs>/)?.[0] ?? ''
  const treffer = new Set<number>()
  let i = 0
  for (const m of xfs.matchAll(/<xf\b[^>]*>/g)) {
    const id = Number(/numFmtId="(\d+)"/.exec(m[0])?.[1] ?? 0)
    if (istDatum(id)) treffer.add(i)
    i++
  }
  return treffer
}

/** Excel zählt Tage ab dem 30.12.1899 (samt dem erfundenen 29.02.1900). */
export function serieAlsDatum(n: number): Date {
  return new Date(Math.round((n - 25569) * 86400000))
}

function spalte(bezug: string): number {
  let n = 0
  for (const z of bezug) {
    const c = z.charCodeAt(0)
    if (c < 65 || c > 90) break
    n = n * 26 + (c - 64)
  }
  return n - 1
}

function blattLesen(xml: string, texte: string[], datum: Set<number>): Zelle[][] {
  const zeilen: Zelle[][] = []
  // Die Attribute werden faul gelesen: `<c r="D2" s="1"/>` hat einen Schrägstrich
  // vor dem `>`, und ein gieriges Muster verschluckte ihn samt der nächsten
  // Zelle — die leere Zelle D trug dann den Wert von E. Zwei Spalten
  // verschoben, keine Fehlermeldung. Gefunden im Vergleich mit einem zweiten
  // Leser; seither prüft das ein Test mit genau dieser Zellfolge.
  for (const zm of xml.matchAll(/<row\b[^>]*?(?:\/>|>([\s\S]*?)<\/row>)/g)) {
    const inhalt = zm[1] ?? ''
    const zeile: Zelle[] = []
    for (const cm of inhalt.matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const attr = cm[1], koerper = cm[2] ?? ''
      const idx = spalte(/r="([A-Z]+)/.exec(attr)?.[1] ?? '')
      const typ = /t="([^"]+)"/.exec(attr)?.[1]
      const stil = Number(/s="(\d+)"/.exec(attr)?.[1] ?? -1)
      const roh = /<v[^>]*>([\s\S]*?)<\/v>/.exec(koerper)?.[1]
      let wert: Zelle = null
      if (typ === 's') wert = texte[Number(roh)] ?? null
      else if (typ === 'inlineStr') wert = tInhalt(koerper) || null
      else if (typ === 'str') wert = roh === undefined ? null : text(roh)
      else if (typ === 'b') wert = roh === '1'
      else if (typ === 'e') wert = null                       // Fehlerzelle (#REF!)
      else if (roh !== undefined && roh !== '') {
        const z = Number(roh)
        wert = Number.isNaN(z) ? text(roh) : (datum.has(stil) ? serieAlsDatum(z) : z)
      }
      if (idx >= 0) { while (zeile.length < idx) zeile.push(null); zeile[idx] = wert }
      else zeile.push(wert)
    }
    zeilen.push(zeile)
  }
  return zeilen
}

/* ---------- Öffentlich ---------------------------------------------------- */

/** Liest alle Blätter einer .xlsx in der Reihenfolge der Arbeitsmappe. */
export async function xlsxLesen(daten: ArrayBuffer | Uint8Array): Promise<Blatt[]> {
  const buf = daten instanceof Uint8Array ? daten : new Uint8Array(daten)
  const eintraege = verzeichnis(buf)
  const finde = (name: string) => eintraege.find(e => e.name === name)
  const lies = async (name: string) => { const e = finde(name); return e ? auspacken(buf, e) : '' }

  const texte = sharedStrings(await lies('xl/sharedStrings.xml'))
  const datum = datumsformate(await lies('xl/styles.xml'))
  const mappe = await lies('xl/workbook.xml')
  const rels = await lies('xl/_rels/workbook.xml.rels')

  const ziel = new Map<string, string>()
  for (const m of rels.matchAll(/<Relationship\b[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"/g)) {
    ziel.set(m[1], m[2].replace(/^\/?xl\//, '').replace(/^\.\//, ''))
  }
  const blaetter: Blatt[] = []
  for (const m of mappe.matchAll(/<sheet\b[^>]*?(?:\/>|>)/g)) {
    const name = text(/name="([^"]*)"/.exec(m[0])?.[1] ?? `Blatt ${blaetter.length + 1}`)
    const rid = /r:id="([^"]+)"/.exec(m[0])?.[1] ?? ''
    const pfad = ziel.get(rid) ?? `worksheets/sheet${blaetter.length + 1}.xml`
    const xml = await lies(`xl/${pfad}`)
    if (!xml) continue
    blaetter.push({ name, zeilen: blattLesen(xml, texte, datum) })
  }
  if (blaetter.length === 0) throw new Error('Die Datei enthält kein lesbares Tabellenblatt.')
  return blaetter
}
