/**
 * Passt, was vom Zettel getippt wird, zum Wareneingang? Und ist eine Wägung
 * glaubwürdig? (Runde AO)
 *
 * Bisher fand das die Auswertung erst hinterher: Im Abzug vom 11. Oktober
 * sind 45 der 69 Auffälligkeiten „Zettelgewicht", vier „Zetteldatum" und
 * acht „Wägung" — Zahlen, die es bei der Charge der Arbeit im Wareneingang
 * nicht gibt, oder Paletten, die im Lager schwerer geworden sein sollen.
 * Gehäuft bei Chargen desselben Produzenten (1626/1623, 1638/1637,
 * 1650/1649): der Zettel gehört zur Nachbarcharge. Jetzt sagt es die Maske,
 * solange die Palette noch vor einem steht.
 *
 * Dieselben Regeln wie die Auffälligkeiten im Büro (v_plausibilitaet:
 * Zetteldatum, Zettelgewicht, Wägung, Verdunstung), dazu die eine, die nur
 * hier geht: Datum und Gewicht passen genau zu einer Palette einer anderen
 * Charge. Nichts davon hält auf — der Wareneingang kann selbst eine Lücke
 * haben (1627 steht gar nicht drin), und gezählt ist gezählt. Reine
 * Funktionen, damit sie ohne Browser geprüft werden (test/zettel.test.ts).
 */

/** Eine Palette dieser Charge im Wareneingang. */
export interface EingangPalette { eingangsdatum: string; brutto_kg: number | null; kisten?: number | null }
/** Eine Palette einer anderen Charge, am selben Tag eingegangen. */
export interface FremdePalette { charge_nr: number; brutto_kg: number | null }

export type ZettelBefund =
  /** Datum und Gewicht stehen genau so im Wareneingang dieser Charge. */
  | { art: 'passt' }
  /** Datum und Gewicht passen, aber die Palette hat dort andere Kisten:
   *  die Vorbelegung (36) stehen gelassen — oder wirklich eine Teilpalette. */
  | { art: 'kisten_anders'; kisten: number }
  /** Die Charge hat (noch) keinen Wareneingang — es gibt nichts zu vergleichen. */
  | { art: 'ohne_eingang' }
  /** Datum und Gewicht gehören im Wareneingang zu einer anderen Charge. */
  | { art: 'fremde_charge'; charge_nr: number }
  /** Dieses Gewicht kam bei der Charge — aber an anderen Tagen. */
  | { art: 'anderer_tag'; tage: string[] }
  /** An dem Tag kam keine Palette dieser Charge (und das Gewicht hilft nicht weiter). */
  | { art: 'kein_tag' }
  /** Der Tag stimmt, aber keine Palette dieser Charge wog so viel. */
  | { art: 'kein_gewicht' }

/** Gleich wie in der Datenbank (`p.brutto_kg = ap.brutto_zettel_kg`) —
 *  bis auf das, was die Fliesskommazahl im Browser verschmiert. */
const gleich = (a: number | null, b: number) => a !== null && Math.abs(a - b) < 0.005

/**
 * `datum` leer: nichts zu sagen. `brutto` null: das Gewicht ist (noch) nicht
 * getippt — dann wird nur das Datum geprüft. `fremd` sind die Paletten der
 * anderen Chargen an genau diesem Datum. `kisten`: was auf der Maske steht —
 * im Abzug vom 11. Oktober waren 11 der 16 Zettel mit anderer Kistenzahl als
 * die Palette im Wareneingang die stehen gelassene Vorbelegung 36 (bei 40,
 * 32 oder 34 Kisten); das Netto rechnete dann mit der falschen Tara, und der
 * Durchgang meldete eine „Teilpalette mit vollem Zettel".
 */
export function zettelBefund(eigen: EingangPalette[], fremd: FremdePalette[], datum: string, brutto: number | null, kisten: number | null = null): ZettelBefund | null {
  if (datum === '') return null
  if (eigen.length === 0) return { art: 'ohne_eingang' }
  const amTag = eigen.filter(p => p.eingangsdatum === datum)
  if (brutto === null || !(brutto > 0)) return amTag.length === 0 ? { art: 'kein_tag' } : null
  const treffer = amTag.filter(p => gleich(p.brutto_kg, brutto))
  if (treffer.length > 0) {
    // Die Kistenzahl der Palette(n) im Wareneingang — die häufigste, wenn
    // mehrere gleich schwere am selben Tag kamen. Passt eine, ist alles gut.
    const bekannt = treffer.map(p => p.kisten).filter((k): k is number => k !== null && k !== undefined && k > 0)
    if (kisten !== null && kisten > 0 && bekannt.length > 0 && !bekannt.includes(kisten)) {
      const haeufig = [...new Set(bekannt)].sort((a, b) => bekannt.filter(k => k === b).length - bekannt.filter(k => k === a).length || a - b)[0]
      return { art: 'kisten_anders', kisten: haeufig }
    }
    return { art: 'passt' }
  }
  const fremde = fremd.find(p => gleich(p.brutto_kg, brutto))
  if (fremde) return { art: 'fremde_charge', charge_nr: fremde.charge_nr }
  const tage = [...new Set(eigen.filter(p => gleich(p.brutto_kg, brutto)).map(p => p.eingangsdatum))].sort()
  if (tage.length > 0) return { art: 'anderer_tag', tage }
  return amTag.length === 0 ? { art: 'kein_tag' } : { art: 'kein_gewicht' }
}

export type WiegungBefund =
  /** Das Eingangsdatum liegt nicht vor heute — es gibt keine Lagertage. */
  | { art: 'datum' }
  /** Nach Abzug von Kisten und Palette bleibt nichts übrig. */
  | { art: 'netto' }
  /** Schwerer als beim Eingang (über 1 %): im Lager wird keine Palette schwerer. */
  | { art: 'schwerer'; kg: number }
  /** Aufs Kilo gleich schwer — meist ist das Eingangsgewicht abgeschrieben. */
  | { art: 'gleich' }
  /** Leichter, als ein Kürbis verdunsten kann (Grenze aus den Einstellungen). */
  | { art: 'zu_schnell'; prozentJeTag: number }

/**
 * Wie die Auswertung die Wägung später beurteilt (v_plausibilitaet „Wägung"
 * und „Verdunstung"): beide Gewichte netto, mit denselben Kisten und
 * derselben Palette. Ohne Tara (`taraKiste`/`taraPalette` null) wird nichts
 * gesagt — dafür steht der Hinweis „Tara fehlt" schon da.
 */
export function wiegungBefund(w: {
  damals: number; jetzt: number; kisten: number
  taraKiste: number | null; taraPalette: number | null
  tage: number; grenzeJeTag: number
}): WiegungBefund | null {
  if (!(w.damals > 0) || !(w.jetzt > 0) || !(w.kisten > 0)) return null
  if (w.tage <= 0) return { art: 'datum' }
  if (w.taraKiste === null || w.taraPalette === null) return null
  const tara = w.kisten * w.taraKiste + w.taraPalette
  const nettoDamals = w.damals - tara, nettoJetzt = w.jetzt - tara
  if (nettoDamals <= 0 || nettoJetzt <= 0) return { art: 'netto' }
  if (nettoJetzt > nettoDamals * 1.01) return { art: 'schwerer', kg: Math.round(nettoJetzt - nettoDamals) }
  if (nettoJetzt === nettoDamals) return { art: 'gleich' }
  // Wie v_verdunstung_messung: 1 − (jetzt/damals)^(1/Tage) — der Anteil je
  // Tag mit Zinseszins, nicht linear. 58 → 38 kg in 34 Tagen sind 1.24 %.
  const rate = 1 - Math.pow(nettoJetzt / nettoDamals, 1 / w.tage)
  if (rate > w.grenzeJeTag) return { art: 'zu_schnell', prozentJeTag: Math.round(rate * 1000) / 10 }
  return null
}

/** Ganze Tage zwischen zwei Daten (JJJJ-MM-TT), wie `betriebstag − eingangsdatum`. */
export function tageZwischen(von: string, bis: string): number {
  const a = Date.parse(von + 'T00:00:00Z'), b = Date.parse(bis + 'T00:00:00Z')
  return Number.isFinite(a) && Number.isFinite(b) ? Math.round((b - a) / 86_400_000) : 0
}
