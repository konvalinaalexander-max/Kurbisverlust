/**
 * Was im Lager liegt und was davon verkaufsfähig ist — Schritt für Schritt,
 * an jeder Stelle gleich (0121, 0123, v_lager_ausweis).
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
  /** Was die Sortiermaschine durchlässt (verkaufsfaehig_kg) — noch ohne die Artikelgewichte und die Überfüllung. */
  verkaufsfaehig: number
  /** 0123: was in kein Artikelgewicht passt (darunter, darüber, dazwischen); ohne Sortier-CSV leer und nicht gezählt. */
  keinenArtikel: number
  /** 0123: ohne Sortier-CSV — ob es in ein Artikelgewicht passt, ist offen. */
  groesseOffen: number
  /** 0124: Sorte ohne Artikelgruppe — als was sie verkauft wird, ist offen; zählt im Verkaufbaren als obere Schranke. */
  gruppeOffen: number
  /** 0123: die Überfüllung auf dem Teil, der als Artikel geht — in den Kisten verschenkt; nur über gewogene Chargen. */
  ueberfuellung: number
  /** 0123: was wir als Artikel tatsächlich verkaufen können (verkaufbar_kg), mit Unique. */
  verkaufbar: number
  /** 0123: was an `verkaufbar` noch offen ist — je Grund die Zahl der Chargen; leer heisst: alles gemessen. */
  offen: Map<string, number>
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
    verkaufsfaehig: 0, keinenArtikel: 0, groesseOffen: 0, gruppeOffen: 0, ueberfuellung: 0, verkaufbar: 0,
    offen: new Map(), luecken: 0, alterTage: null, rateJeTag: null }
  let alterMal = 0, alterMasse = 0
  for (const a of liste) {
    const ein = z(a.eingang_kg) ?? 0
    if (!(ein > 0)) continue
    s.n += 1
    s.eingang += ein
    if (a.paletten != null) s.paletten = (s.paletten ?? 0) + Number(a.paletten)
    // Eine Rate nicht gemessen: die Datenbank lässt verkaufsfaehig_kg, verdunstet_kg
    // oder faul_kg leer — und damit auch verkaufbar_kg. Die Charge fehlt dann in
    // den Abzügen und wird als Lücke gezählt, nie als 0.
    const vf = z(a.verkaufsfaehig_kg), verkaufbar = z(a.verkaufbar_kg)
    if (vf === null || verkaufbar === null || z(a.faul_kg) === null || z(a.verdunstet_kg) === null) { s.luecken += 1; continue }
    s.verdunstet += z(a.verdunstet_kg) ?? 0
    s.faul += z(a.faul_kg) ?? 0
    s.unique += z(a.unique_kg) ?? 0
    s.klein += z(a.zu_klein_kg) ?? 0
    s.gross += z(a.zu_gross_kg) ?? 0
    s.fax += z(a.fax_kg) ?? 0
    s.verkaufsfaehig += vf
    s.keinenArtikel += z(a.keinen_artikel_kg) ?? 0
    s.groesseOffen += z(a.groesse_offen_kg) ?? 0
    s.gruppeOffen += z(a.gruppe_offen_kg) ?? 0
    // Nicht gewogene Überfüllung ist leer, nicht 0: Sie zieht nichts ab und steht als „offen" da.
    s.ueberfuellung += z(a.ueberfuellung_kg) ?? 0
    s.verkaufbar += verkaufbar
    for (const grund of (a.verkaufbar_offen ?? '').split(', ').filter(Boolean)) s.offen.set(grund, (s.offen.get(grund) ?? 0) + 1)
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
  art: 'start' | 'weg' | 'aussortiert' | 'ergebnis' | 'davon'
  name: string
  kg: number
  wie?: string
  farbe: string
}

/** 0123: Was die Maschine durchlässt, aber in kein Artikelgewicht passt — dieselbe Farbe wie unter Artikel (src/design/tokens.css). */
export const STROM_KEINEN_ARTIKEL = 'var(--strom-keinen-artikel)'
/** 0123: Die Überfüllung geht mit der verkauften Ware hinaus — grau mit einem Hauch Grün. */
export const STROM_UEBERFUELLUNG = 'var(--strom-ueberfuellung)'

/**
 * Die Kette als Schritte (0123). Der Betrieb, 23. Oktober: „Im Lager will ich,
 * was wirklich steht — Paletten, bevor wir etwas in den Palox schmeissen …
 * und verkaufsfähig wirklich das, was wir verkaufen können, minus allem:
 * innerhalb der Artikelgewichte, verschenkte Marge abgezogen, Palox,
 * Verdunstung." Darum beginnt sie bei den Paletten, wie sie eingingen, und
 * endet bei dem, was als Artikel verkauft werden kann. Unique (Hagel) ist ein
 * Artikel: Es wird nicht abgezogen, sondern steht als „davon" unter dem
 * Ergebnis. Die Glieder gehen auf: Eingang − alles Abgezogene = verkaufsfähig.
 */
export function schritte(s: AusweisSumme): Schritt[] {
  const r: Schritt[] = []
  if (!(s.eingang > 0)) return r
  r.push({ art: 'start', name: 'im Lager, wie eingegangen', kg: s.eingang, farbe: 'var(--rand)' })
  if (s.luecken === s.n) return r
  const pro = (x: number) => `${(x * 100).toLocaleString('de-CH', { maximumFractionDigits: 2 })} %`
  r.push({ art: 'weg', name: 'verdunstet', kg: s.verdunstet, farbe: 'var(--strom-verdunstung)',
           wie: s.alterTage !== null && s.rateJeTag !== null ? `im Mittel ${Math.round(s.alterTage)} Tage gelagert, rund ${pro(s.rateJeTag)} je Tag` : undefined })
  r.push({ art: 'weg', name: 'Faules im Palox', kg: s.faul, farbe: 'var(--strom-schimmel)' })
  r.push({ art: 'aussortiert', name: 'zu klein', kg: s.klein, farbe: 'var(--strom-ausschuss)', wie: 'unter dem kleinsten Band der Sortiermaschine — Tierfutter' })
  r.push({ art: 'aussortiert', name: 'zu gross', kg: s.gross, farbe: 'var(--strom-nebenkanal)', wie: 'über dem obersten Band — steht auf den Paletten „+2000 g", anderer Kanal' })
  if (s.fax > 0.5) r.push({ art: 'weg', name: 'Faules beim Abpacken', kg: s.fax, farbe: 'var(--strom-fax)' })
  if (s.keinenArtikel > 0.5) r.push({ art: 'aussortiert', name: 'passt in keinen Artikel', kg: s.keinenArtikel, farbe: STROM_KEINEN_ARTIKEL,
           wie: 'die Maschine lässt es durch, aber es ist leichter oder schwerer als die Gewichte der Artikel' })
  if (s.ueberfuellung > 0.5) r.push({ art: 'weg', name: 'Überfüllung', kg: s.ueberfuellung, farbe: STROM_UEBERFUELLUNG,
           wie: 'geht in den Kisten über dem Sollgewicht mit — verschenkt, nicht bezahlt' })
  r.push({ art: 'ergebnis', name: 'verkaufsfähig', kg: s.verkaufbar, farbe: 'var(--strom-vf)',
           wie: 'als Artikel — in den Gewichten der Artikel, ohne Überfüllung' })
  if (s.unique > 0.5) r.push({ art: 'davon', name: 'davon Unique (Hagel)', kg: s.unique, farbe: 'var(--strom-unique)', wie: 'nicht faul — wird als Knospe verkauft' })
  if (s.groesseOffen > 0.5) r.push({ art: 'davon', name: 'davon Grösse offen', kg: s.groesseOffen, farbe: 'var(--strom-vf)',
           wie: 'keine Sortier-CSV — ob es in die Gewichte der Artikel passt, ist offen' })
  if (s.gruppeOffen > 0.5) r.push({ art: 'davon', name: 'davon Artikelgruppe offen', kg: s.gruppeOffen, farbe: 'var(--strom-vf)',
           wie: 'die Sorte hat keine Artikelgruppe (Stammdaten → Sorten) — als was sie verkauft wird, ist offen' })
  return r
}

/** Was an „verkaufsfähig" offen ist, in einem Satz — leer, wenn alles gemessen ist. */
export function offenText(s: AusweisSumme): string {
  if (s.offen.size === 0) return ''
  const n = (k: number) => `${k} ${k === 1 ? 'Charge' : 'Chargen'}`
  return [...s.offen.entries()].map(([grund, k]) => `${grund} bei ${n(k)}`).join('; ')
}

/** Der Ausweis einer Charge (oder keiner). */
export function ausweisVon(liste: LagerAusweis[], nr: number): LagerAusweis | undefined {
  return liste.find(a => a.charge_nr === nr)
}
