/**
 * Das Nettogewicht einer Palette — eine Regel, eine Stelle.
 *
 * Netto = brutto − Kisten × Kistentara − Palettentara
 *
 * Fehlt eines der drei, gibt es kein Netto. Nicht „null Kisten", nicht
 * „Palettentara null" — **unbekannt**. Das ist derselbe Grundsatz, nach dem
 * die Datenbank rechnet (`v_palette.netto_kg` seit 0064), und es ist wichtig,
 * dass beide Seiten dieselbe Antwort geben: Der Arbeiter prüft die
 * Plausibilität einer Wägung an der Zahl, die die Maske zeigt. Zeigt sie eine,
 * wo die Datenbank keine hat, prüft er gegen etwas, das später nicht existiert.
 *
 * `mitPalette = false` gilt dort, wo keine Palette unter der Ware steht — beim
 * Palox etwa, der auf der Waage steht und dessen Leergewicht als Einstellung
 * geführt wird. Dann wird die Palettentara nicht gebraucht und darf fehlen.
 */
export interface Tara {
  tara_kg_pro_kiste: number | null
  tara_kg_palette: number | null
}

export function nettoKg(
  brutto: number | null | undefined,
  kisten: number | null | undefined,
  tara: Tara | null | undefined,
  mitPalette = true,
): number | null {
  if (brutto == null || !Number.isFinite(brutto)) return null
  if (kisten == null || !Number.isFinite(kisten)) return null
  if (tara?.tara_kg_pro_kiste == null) return null
  if (mitPalette && tara.tara_kg_palette == null) return null
  return brutto - kisten * tara.tara_kg_pro_kiste - (mitPalette ? tara.tara_kg_palette! : 0)
}

/** Was der Maske fehlt, in einem Satz für den Arbeiter — oder null. */
export function taraFehlt(tara: Tara | null | undefined, mitPalette = true): string | null {
  if (!tara) return 'Für diese Gebindeart stehen keine Gewichte in den Stammdaten.'
  if (tara.tara_kg_pro_kiste == null) return 'Für diese Gebindeart ist kein Kistengewicht hinterlegt.'
  if (mitPalette && tara.tara_kg_palette == null) return 'Für diese Gebindeart ist kein Palettengewicht hinterlegt.'
  return null
}

/**
 * Summe mehrerer Massen — **unbekannt, sobald eine unbekannt ist**.
 *
 * `a + b` macht in JavaScript aus `null` eine Null: `null + 5` ist 5. Genau
 * dieser stille Übergang ist es, den 0064 in der Datenbank abgestellt hat; er
 * darf in der Oberfläche nicht wieder hereinkommen. Wer die Summe der
 * gemessenen Teile will, sagt das ausdrücklich mit `?? 0` — dann steht es da.
 */
export function summeBekannt(werte: (number | null | undefined)[]): number | null {
  let s = 0
  for (const w of werte) {
    if (w == null) return null
    s += w
  }
  return s
}

/**
 * Wie die Masse einer Arbeit oder Lieferung zustande kam — in der Sprache des
 * Betriebs statt in der der Datenbank.
 *
 * Die Spalte `masse_quelle` sagt, welchen Weg die Rechnung genommen hat. Auf
 * der Chargen-Seite stand sie bisher roh in Klammern („zettel-charge-tara"),
 * und damit stand dort Technik statt einer Auskunft. Was hier nicht steht,
 * wird unverändert durchgereicht — dann fällt der neue Wert auf, statt still
 * hübsch auszusehen.
 */
const HERKUNFT_TEXT: Record<string, string> = {
  gewogen: 'gewogen',
  zettel: 'vom Zettel, Palette im Wareneingang gefunden',
  'zettel-charge-tara': 'vom Zettel, mit der mittleren Tara der Charge',
  palette: 'aus dem Wareneingang',
  'datum-mittel': 'Mittel des Eingangstags',
  'charge-mittel': 'Mittel der Charge',
  paletten: 'aus den gezählten Eingangspaletten',
  wasch_paletten: 'aus den gewaschenen Paletten',
  fax_paletten: 'aus den Fax-Paletten',
  gebinde: 'aus den gezählten Kisten',
  fehlt: 'nicht bekannt',
  unbekannt: 'nicht bekannt',
}

export function herkunftText(quelle: string | null | undefined): string | null {
  if (!quelle) return null
  return HERKUNFT_TEXT[quelle] ?? quelle
}
