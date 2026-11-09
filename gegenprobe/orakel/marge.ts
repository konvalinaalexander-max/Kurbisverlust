/**
 * 0136 — die verschenkte Marge je Charge, unabhängig von `v_verschenkt_charge` nachgerechnet.
 *
 * Der Betrieb am 9. November: „Zum Hochrechnen ist ja eigentlich nur Verkauf + Verdunstung + Palox +
 * verschenkte Marge." Was in den Kisten über dem Sollgewicht mitging, ist hinausgegangen, ohne in
 * Perigon zu stehen: verkaufte Kisten „ab x kg" × zu viel je Kiste — gewogen bei der Charge (über alle
 * ihre Zeilen, auch wenn die Verkaufsdatei die Lieferung unter einer anderen Sorte führt), sonst bei
 * ihrer Sorte. Stück-Kisten haben kein Sollgewicht, ein unbekanntes Kistensystem wird nicht gerechnet.
 *
 * Eingabe sind die gespeicherten Zeilen von `erg_ueberfuellung` (Schritt 1 der Rechnung): was verkauft
 * und was gewogen ist. Gerechnet wird hier nur, was daraus folgt.
 */
export interface UeberfuellungZeile {
  gruppe: string; chargeNr: number | null; sorte: string | null; kistensystem: string | null
  sollKg: number | null; kgVerkauft: number | null; kistenVerkauft: number | null; zuviel: number | null
}

/** Je Charge das Verschenkte in kg (auf zwei Stellen, wie die Sicht); Chargen ohne Verschenktes fehlen. */
export function verschenktJeCharge(zeilen: UeberfuellungZeile[], sorteVon: Map<number, string>): Map<number, number> {
  const gewogen = new Map<string, number[]>()
  const merke = (k: string, x: number) => gewogen.set(k, [...(gewogen.get(k) ?? []), x])
  for (const z of zeilen) {
    if (z.kistensystem !== 'kiste_ab' || z.zuviel == null) continue
    if (z.gruppe === 'charge' && z.chargeNr != null) merke(`charge|${z.chargeNr}|${z.sollKg}`, z.zuviel)
    else if (z.gruppe === 'sorte') merke(`sorte|${z.sorte}|${z.sollKg}`, z.zuviel)
  }
  const mittel = (k: string) => { const l = gewogen.get(k); return l ? l.reduce((a, b) => a + b, 0) / l.length : null }
  // verkaufte Kisten je Charge und Sollgewicht — über alle Zeilen der Charge, gleich unter welcher Sorte
  const kisten = new Map<string, { charge: number; soll: number | null; kisten: number | null }>()
  for (const z of zeilen) {
    if (z.gruppe !== 'charge' || z.chargeNr == null || z.kistensystem !== 'kiste_ab' || !(Number(z.kgVerkauft) > 0) || !sorteVon.has(z.chargeNr)) continue
    const k = `${z.chargeNr}|${z.sollKg}`
    const v = kisten.get(k) ?? { charge: z.chargeNr, soll: z.sollKg, kisten: null }
    if (z.kistenVerkauft != null) v.kisten = (v.kisten ?? 0) + z.kistenVerkauft
    kisten.set(k, v)
  }
  const roh = new Map<number, number>()
  for (const v of kisten.values()) {
    if (v.kisten == null) continue
    const zuviel = mittel(`charge|${v.charge}|${v.soll}`) ?? mittel(`sorte|${sorteVon.get(v.charge)}|${v.soll}`)
    if (zuviel == null) continue
    roh.set(v.charge, (roh.get(v.charge) ?? 0) + v.kisten * zuviel)
  }
  return new Map([...roh].map(([c, x]) => [c, Math.round(x * 100) / 100] as [number, number]).filter(([, x]) => x > 0))
}

/** Das Verschenkte einer Charge auf eine ihrer Lieferzeilen, nach kg verteilt (Σ über die Zeilen = das der Charge). */
export function verschenktAufZeile(geliefertKg: number, summeGeliefertKg: number, verschenktCharge: number): number {
  return summeGeliefertKg > 0 ? verschenktCharge * geliefertKg / summeGeliefertKg : 0
}
