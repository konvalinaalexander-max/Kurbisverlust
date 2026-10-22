/**
 * Was im Lager liegt und was davon verkaufsfähig ist — Schritt für Schritt,
 * an jeder Stelle gleich (0121, v_lager_ausweis).
 *
 * Der Betrieb, 22. Oktober: „bei Artikel und bei Chargen jeweils ausweisen,
 * wie viele Kilo im Lager sind — als Paletten … und daneben davon
 * verkaufsfähig: minus Verdunstung (mit Lagerdauer und täglicher Rate), minus
 * Palox, minus zu klein, zu gross … und vielleicht minus verschenkte Marge."
 * Und: „was mit Hagelschaden ist, wird nicht fortgeschmissen und ist auch
 * nicht faul — das ist Unique, wie ein eigener Artikel, nur Knospe."
 *
 * Gerechnet ist alles in der Datenbank; hier wird nur zusammengezählt (je
 * Sorte, je Auswahl) und in Schritte gefasst. Leer bleibt leer: Fehlt einer
 * Charge eine Zahl, ist die Summe „mindestens", nie die Summe der übrigen.
 * Ohne React, damit test/ausweis.test.ts es prüfen kann.
 */
import type { LagerAusweis } from './daten'

export interface AusweisSumme {
  n: number
  /** Eingangspaletten, die noch liegen (Σ n_rest_paletten); null, wenn keine Charge eine Zahl hat. */
  paletten: number | null
  /** Was auf diesen Paletten beim Eingang lag. */
  eingang: number
  verdunstet: number
  faul: number
  unique: number
  klein: number
  gross: number
  fax: number
  verkaufsfaehig: number
  /** Überfüllung in den Kisten — nur über Chargen mit gewogener Marge (sonst unbekannt). */
  marge: number
  margeBekannt: boolean
  /** Chargen mit Ware, deren Kette eine Lücke hat (eine Rate nicht gemessen) — ihre Teile fehlen in den Summen. */
  luecken: number
  /** Mittleres Alter der Ware (nach Masse) und daraus die Verdunstung je Tag in Prozent der Eingangsmasse. */
  alterTage: number | null
  rateJeTag: number | null
}

const z = (x: number | null | undefined) => (x === null || x === undefined ? null : Number(x))

/** Die Kette über mehrere Chargen. */
export function summiere(liste: LagerAusweis[]): AusweisSumme {
  const s: AusweisSumme = { n: 0, paletten: null, eingang: 0, verdunstet: 0, faul: 0, unique: 0, klein: 0, gross: 0, fax: 0,
    verkaufsfaehig: 0, marge: 0, margeBekannt: true, luecken: 0, alterTage: null, rateJeTag: null }
  let alterMal = 0, alterMasse = 0
  for (const a of liste) {
    const ein = z(a.eingang_kg) ?? 0
    if (!(ein > 0)) continue
    s.n += 1
    s.eingang += ein
    if (a.paletten != null) s.paletten = (s.paletten ?? 0) + Number(a.paletten)
    const vf = z(a.verkaufsfaehig_kg)
    if (vf === null || z(a.faul_kg) === null || z(a.verdunstet_kg) === null) { s.luecken += 1; continue }
    s.verdunstet += z(a.verdunstet_kg) ?? 0
    s.faul += z(a.faul_kg) ?? 0
    s.unique += z(a.unique_kg) ?? 0
    s.klein += z(a.zu_klein_kg) ?? 0
    s.gross += z(a.zu_gross_kg) ?? 0
    s.fax += z(a.fax_kg) ?? 0
    s.verkaufsfaehig += vf
    const m = z(a.marge_kg)
    if (m === null) s.margeBekannt = false
    else s.marge += m
    if (a.alter_tage != null) { alterMal += Number(a.alter_tage) * ein; alterMasse += ein }
  }
  if (alterMasse > 0) {
    s.alterTage = alterMal / alterMasse
    s.rateJeTag = s.alterTage > 0 && s.eingang > 0 ? s.verdunstet / s.eingang / s.alterTage : null
  }
  return s
}

/** Ein Schritt der Kette: Name, Kilo (− abgezogen, = Ergebnis), und ein Halbsatz, woher. */
export interface Schritt {
  art: 'start' | 'weg' | 'aussortiert' | 'unique' | 'ergebnis' | 'davon'
  name: string
  kg: number
  wie?: string
  farbe: string
}

/**
 * Die Kette als Schritte. sicht = 'charge': zu klein / zu gross nach den
 * Bändern der Sortiermaschine. Für die Artikel stehen danach die Artikel-
 * Kaliber (klein, gross, passt in keinen Artikel) — das macht die Seite selbst.
 */
export function schritte(s: AusweisSumme, mitMarge = true): Schritt[] {
  const r: Schritt[] = []
  if (!(s.eingang > 0)) return r
  r.push({ art: 'start', name: 'auf den Paletten, wie eingegangen', kg: s.eingang, farbe: 'var(--rand)' })
  if (s.luecken === s.n) return r
  const pro = (x: number) => `${(x * 100).toLocaleString('de-CH', { maximumFractionDigits: 2 })} %`
  r.push({ art: 'weg', name: 'verdunstet', kg: s.verdunstet, farbe: 'var(--strom-verdunstung)',
           wie: s.alterTage !== null && s.rateJeTag !== null ? `im Mittel ${Math.round(s.alterTage)} Tage gelagert, rund ${pro(s.rateJeTag)} je Tag` : undefined })
  r.push({ art: 'weg', name: 'Faules im Palox', kg: s.faul, farbe: 'var(--strom-schimmel)' })
  if (s.unique > 0.5) r.push({ art: 'unique', name: 'Unique (Hagel)', kg: s.unique, farbe: 'var(--strom-unique)', wie: 'nicht faul — wird als Knospe verkauft' })
  r.push({ art: 'aussortiert', name: 'zu klein', kg: s.klein, farbe: 'var(--strom-ausschuss)', wie: 'unter dem kleinsten Band der Sortiermaschine — Tierfutter' })
  r.push({ art: 'aussortiert', name: 'zu gross', kg: s.gross, farbe: 'var(--strom-nebenkanal)', wie: 'über dem obersten Band — steht auf den Paletten „+2000 g", anderer Kanal' })
  if (s.fax > 0.5) r.push({ art: 'weg', name: 'Faules beim Abpacken', kg: s.fax, farbe: 'var(--strom-fax)' })
  r.push({ art: 'ergebnis', name: 'verkaufsfähig', kg: s.verkaufsfaehig, farbe: 'var(--strom-vf)' })
  if (mitMarge && s.margeBekannt && s.marge > 0.5) {
    r.push({ art: 'davon', name: 'davon Überfüllung in den Kisten', kg: s.marge, farbe: 'var(--strom-vf-klein)',
             wie: `${pro(s.marge / Math.max(s.verkaufsfaehig - s.marge, 1))} über dem Sollgewicht — geht mit, wird nicht verrechnet` })
    r.push({ art: 'davon', name: 'verrechenbar', kg: s.verkaufsfaehig - s.marge, farbe: 'var(--strom-vf)' })
  }
  return r
}

/** Der Ausweis einer Charge (oder keiner). */
export function ausweisVon(liste: LagerAusweis[], nr: number): LagerAusweis | undefined {
  return liste.find(a => a.charge_nr === nr)
}
