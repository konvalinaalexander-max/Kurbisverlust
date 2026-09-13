/**
 * Orakel 8 — die Prognose: dieselbe Kaskade, ein paar Wochen später.
 *
 * Der Betriebsleiter fragt: „Wenn die Ware, die heute liegt, bis Ende März
 * liegen bleibt — wie viel davon ist dann noch verkaufsfähig?" Die Antwort
 * darf keine zweite Mathematik sein. Sie ist die Kaskade (Orakel 4) für die
 * Portion „lager", ausgewertet bei `alter + h` statt bei `alter`:
 *
 *   m1(h) = m0 · (1−r)^(t₀+h)
 *   m2(h) = m1(h) · (1−a₀) · (1−F(t₀+h))
 *   verkaufsfähig(h) = m2(h) · (1 − a_klein − a_gross) · (1 − a_fax)
 *
 * Bei h = 0 steht deshalb exakt die Zahl von heute. Das ist die Probe, die
 * am meisten wert ist: Sie fängt jede Abweichung zwischen dem, was das
 * Dashboard oben zeigt, und dem, was die Prognose darunter rechnet.
 *
 * Die Zerlegung des Verlusts in Wasser und Fäulnis ist **multiplikativ
 * exakt** — beide Teile ergeben zusammen auf den Rappen den Verlust an
 * verkaufsfähiger Ware, und keiner von beiden wird je negativ:
 *
 *   B        = m0 · (1−a₀) · (1 − a_klein − a_gross) · (1 − a_fax)
 *   Wasser   = B · (1−r)^t₀ · (1−F(t₀)) · (1 − (1−r)^h)
 *   Fäulnis  = B · (1−r)^t₀ · (1−r)^h  · (F(t₀+h) − F(t₀))
 *   zusammen = VF(0) − VF(h)
 *
 * Die naive Differenz „faul nachher minus faul vorher" hätte diese
 * Eigenschaft nicht: Bei einer Charge, deren Verderb schon gesättigt ist,
 * verliert auch das Faule Wasser, und die Differenz würde negativ.
 *
 * Gegenstück: `v_prognose` / `erg_prognose` (Migration 0071).
 */
import { normieren, type Koeffizienten } from './kaskade.ts'

/** Eine liegende Portion: eine Kohorte (Eingangstag) einer Charge. */
export interface LagerPortion {
  chargeNr: number
  kohorte: string
  /** Lagertage heute, wie in der Kaskade schon auf 0 geklammert. */
  alterTage: number
  m0: number
  r: number
  a0: number
  /** Schon normiert, wie mv_kaskade sie führt. */
  aKleinN: number
  aGrossN: number
  aFax: number
}

export interface Stand {
  m1: number
  m2: number
  verdunstetKg: number
  sockelKg: number
  faulKg: number
  kanalKg: number
  faxKg: number
  verkaufsfaehigKg: number
  guteWareKg: number
}

/**
 * Der Stand einer liegenden Portion bei Alter t, mit dem Schimmelanteil f
 * an genau diesem Alter. Die Ströme summieren sich auf m0 — das ist die
 * Invariante, die auch hier niemals brechen darf.
 */
export function standBei(p: LagerPortion, f: number): Stand {
  const m1 = p.m0 * Math.pow(1 - p.r, p.alterTage)
  const m2 = m1 * (1 - p.a0) * (1 - f)
  const kanalKg = m2 * (p.aKleinN + p.aGrossN)
  const rest = m2 * (1 - p.aKleinN - p.aGrossN)
  return {
    m1, m2,
    verdunstetKg: p.m0 - m1,
    sockelKg: m1 * p.a0,
    faulKg: m1 * (1 - p.a0) * f,
    kanalKg,
    faxKg: rest * p.aFax,
    verkaufsfaehigKg: rest * (1 - p.aFax),
    guteWareKg: m2,
  }
}

/** Derselbe Stand, aber bei alter + h: dafür bekommt die Portion ein neues Alter. */
export function standNachTagen(p: LagerPortion, h: number, fDann: number): Stand {
  return standBei({ ...p, alterTage: p.alterTage + h }, fDann)
}

export interface Verlust {
  wasserKg: number
  faeulnisKg: number
  verkaufsfaehigKg: number
}

/**
 * Was das Liegen ab heute bis zum Horizont h an verkaufsfähiger Ware
 * kostet, exakt in Wasser und Fäulnis zerlegt.
 */
export function verlustAb(p: LagerPortion, h: number, fHeute: number, fDann: number): Verlust {
  const basis = p.m0 * (1 - p.a0) * (1 - p.aKleinN - p.aGrossN) * (1 - p.aFax) * Math.pow(1 - p.r, p.alterTage)
  const wasserKg = basis * (1 - fHeute) * (1 - Math.pow(1 - p.r, h))
  const faeulnisKg = basis * Math.pow(1 - p.r, h) * Math.max(fDann - fHeute, 0)
  return { wasserKg, faeulnisKg, verkaufsfaehigKg: wasserKg + faeulnisKg }
}

/** Die Ränder der Hülle: alle Koeffizienten gleichzeitig am ungünstigsten Rand. */
export interface Raender {
  rUnten: number; rOben: number
  a0Unten: number; a0Oben: number
  kleinUnten: number; kleinOben: number
  grossUnten: number; grossOben: number
  faxUnten: number; faxOben: number
}

export function huelle(p: LagerPortion, h: number, fUnten: number, fOben: number, g: Raender):
    { unten: number; oben: number } {
  const zweig = (r: number, a0: number, klein: number, gross: number, fax: number, f: number) => {
    const { aKleinN, aGrossN } = normieren(klein, gross)
    // Der Deckel bei 1 ist rechnerisch überflüssig — nach der Normierung ist
    // die Summe höchstens 1 —, in Fliesskomma aber nicht: 0.8/1.4 + 0.6/1.4
    // ergibt 1.0000000000000002, und die Kante des Bandes würde negativ.
    // Die Sicht setzt denselben Deckel (`least(…, 1)`).
    return p.m0 * Math.pow(1 - r, p.alterTage + h) * (1 - a0) * (1 - f)
         * (1 - Math.min(aKleinN + aGrossN, 1)) * (1 - fax)
  }
  return {
    unten: zweig(g.rOben, g.a0Oben, g.kleinOben, g.grossOben, g.faxOben, fOben),
    oben:  zweig(g.rUnten, g.a0Unten, g.kleinUnten, g.grossUnten, g.faxUnten, fUnten),
  }
}

/** Die Summe über eine Gruppe von Portionen — je Horizont eine Zeile. */
export interface Zeile {
  lagerKg: number
  nKohorten: number
  /** Massegewichtetes Alter **am Horizont**, also t = alter + h — wie die Sicht es führt. */
  alterTage: number
  alterVon: number
  alterBis: number
  verdunstetKg: number
  sockelKg: number
  faulKg: number
  kanalKg: number
  faxKg: number
  verkaufsfaehigKg: number
  guteWareKg: number
  vfUntenKg: number
  vfObenKg: number
  verlustWasserKg: number
  verlustFaeulnisKg: number
  verlustVerkaufsfaehigKg: number
  /** Anteil an der Eingangsware — leer, wenn ein Koeffizient fehlt (leer ist nicht null). */
  verkaufsfaehigAnteil: number | null
  vollstaendig: boolean
  modellGilt: boolean
  hochgerechnet: boolean
}

/** Ein Teil der Summe: eine Portion an einem Horizont, mit allem, was daran hängt. */
export interface Teil {
  p: LagerPortion
  /** Alter am Horizont, t = alter + h. */
  t: number
  stand: Stand
  verlust: Verlust
  huelle: { unten: number; oben: number }
  bekannt: { r: boolean; f: boolean; a0: boolean; kanal: boolean; fax: boolean }
  modellGilt: boolean
  /** Liegt t jenseits des grössten beobachteten Lagertags? */
  ueberTMax: boolean
}

export function summieren(teile: Teil[]): Zeile {
  const s = (f: (x: Teil) => number) => teile.reduce((a, x) => a + f(x), 0)
  const lagerKg = s(x => x.p.m0)
  const verkaufsfaehigKg = s(x => x.stand.verkaufsfaehigKg)
  // „Vollständig" heisst: jeder Koeffizient jeder Portion ist gemessen. Fehlt
  // einer, sind die Massen eine obere Schranke und der Anteil bleibt leer.
  const vollstaendig = teile.every(x => x.bekannt.r && x.bekannt.f && x.bekannt.a0
                                     && x.bekannt.kanal && x.bekannt.fax)
  return {
    lagerKg,
    nKohorten: teile.length,
    alterTage: lagerKg > 0 ? s(x => x.p.m0 * x.t) / lagerKg : 0,
    alterVon: Math.min(...teile.map(x => x.t)),
    alterBis: Math.max(...teile.map(x => x.t)),
    verdunstetKg: s(x => x.stand.verdunstetKg),
    sockelKg: s(x => x.stand.sockelKg),
    faulKg: s(x => x.stand.faulKg),
    kanalKg: s(x => x.stand.kanalKg),
    faxKg: s(x => x.stand.faxKg),
    verkaufsfaehigKg,
    guteWareKg: s(x => x.stand.guteWareKg),
    vfUntenKg: s(x => x.huelle.unten),
    vfObenKg: s(x => x.huelle.oben),
    verlustWasserKg: s(x => x.verlust.wasserKg),
    verlustFaeulnisKg: s(x => x.verlust.faeulnisKg),
    verlustVerkaufsfaehigKg: s(x => x.verlust.verkaufsfaehigKg),
    verkaufsfaehigAnteil: vollstaendig && lagerKg > 0 ? verkaufsfaehigKg / lagerKg : null,
    vollstaendig,
    modellGilt: teile.every(x => x.modellGilt),
    hochgerechnet: teile.some(x => x.modellGilt && x.ueberTMax),
  }
}

/** Die Probe: Ströme summieren sich auf die liegende Masse. */
export function summeStimmtPrognose(z: { verdunstetKg: number; sockelKg: number; faulKg: number;
                                         kanalKg: number; faxKg: number; verkaufsfaehigKg: number;
                                         lagerKg: number }): boolean {
  const summe = z.verdunstetKg + z.sockelKg + z.faulKg + z.kanalKg + z.faxKg + z.verkaufsfaehigKg
  return Math.abs(summe - z.lagerKg) <= 1e-6 * Math.max(z.lagerKg, 1)
}

/** Die Probe: die Zerlegung ergibt den Verlust an verkaufsfähiger Ware. */
export function zerlegungStimmt(vf0: number, vfH: number, v: Verlust): boolean {
  return Math.abs((vf0 - vfH) - (v.wasserKg + v.faeulnisKg)) <= 1e-6 * Math.max(vf0, 1)
}
