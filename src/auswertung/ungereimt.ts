/**
 * Was zwischen Perigon, Erntejournal und Lager nicht zusammenpasst — in
 * Sätzen, die man ohne Perigon-Kenntnis versteht (0121).
 *
 * Der Betrieb, 22. Oktober: „so etwas wie 1627 — das hat Ausgang, aber
 * keinen Eingang — weis in der App auffällig darauf hin; generell sollte das
 * wirklich prominent sein, überall, wo wir Probleme mit dem Perigon haben."
 * Und: „so, dass ich als Laie die Problematik erkenne, zu meinem Chef gehen
 * kann und sagen: schau, das macht keinen Sinn."
 *
 * Je Sache drei Sätze: was komisch ist, warum es das Lager verfälscht, was zu
 * tun ist. Die Zahlen kommen aus der Datenbank (v_ungereimtheit,
 * v_perigon_pruefung); hier werden sie nur zu Sätzen und nach Gewicht
 * geordnet. Ohne React, damit test/ungereimt.test.ts sie prüfen kann.
 */
import type { PerigonPruefung, UngereimtZeile } from './daten'
import { datum, kg, tonnen } from '../lib/format.ts'

export type Schwere = 'rot' | 'gelb' | 'info'

export interface Ungereimtheit {
  schluessel: string
  /** Die Art der Datenbank, oder für Perigon-Zeilen ihre Art (v_perigon_pruefung.art). */
  art: string
  schwere: Schwere
  titel: string
  was: string
  warum: string
  tun: string
  /** Die Kilo, um die es geht — nie 0 statt unbekannt. */
  kg: number | null
  charge_nr: number | null
  sorte: string | null
  /** Perigon-Zeilen, die dazugehören: ein Klick zeigt die Zeile der Datei mit den falschen Zellen. */
  zeilen: PerigonPruefung[]
  /** Für umgebucht/vorschlag: welche Paletten (der Betriebsleiter nimmt zurück oder bucht) und woher sie kommen. */
  paletten?: number[]
  von_charge_nr?: number | null
}

/** Je Art der Name auf dem Chip und ein Satz, was sie heisst. */
export const ART_NAME: Record<string, string> = {
  ohne_eingang: 'Verkauft, nie eingegangen',
  vor_eingang: 'Verkauft vor dem Eingang',
  ueberzaehlung: 'Mehr verkauft als möglich',
  ohne_charge: 'Lieferschein ohne Charge',
  vorschlag: 'Paletten wohl auf falscher Charge',
  umgebucht: 'Von der App umgebucht',
  'Charge nicht zugeordnet': 'Unbekannte Chargennummer',
  'Teil ohne Charge': 'Teil der Menge ohne Charge',
  'Artikel passt nicht zur Sorte': 'Artikel passt nicht zur Charge',
  'Als Demeter verkauft, als Knospe geliefert': 'Demeter-Preis für Knospe-Ware',
}

const n = (x: unknown): number | null => (x === null || x === undefined || x === '' ? null : Number(x))
const stueck = (k: number, ein: string, mehr: string) => `${k} ${k === 1 ? ein : mehr}`
const name = (z: { charge_nr: number | null; schlag: string | null; sorte: string | null }) =>
  `${z.charge_nr}${z.schlag || z.sorte ? ` (${[z.schlag, z.sorte].filter(Boolean).join(' · ')})` : ''}`
const spanne = (von: string | null, bis: string | null) =>
  !von ? '' : bis && bis !== von ? `zwischen ${datum(von)} und ${datum(bis)}` : `am ${datum(von)}`

/** Eine Zeile aus v_ungereimtheit in Sätzen. */
export function ausZeile(z: UngereimtZeile, perigon: PerigonPruefung[]): Ungereimtheit {
  const m = z.mehr ?? {}
  const kgZ = n(z.kg)
  const basis = { schluessel: `${z.art}:${z.charge_nr ?? z.sorte ?? ''}:${String(m.auftrag_id ?? '')}`, art: z.art, kg: kgZ, charge_nr: z.charge_nr, sorte: z.sorte, zeilen: [] as PerigonPruefung[] }
  switch (z.art) {
    case 'ohne_eingang':
      return { ...basis, schwere: 'rot',
        titel: `Charge ${name(z)} hat verkauft, aber nie etwas bekommen`,
        was: `Perigon bucht ${stueck(z.n, 'Lieferschein', 'Lieferscheine')} mit ${kg(kgZ, 0)} auf Charge ${z.charge_nr} (${spanne(z.von, z.bis)}). Im Erntejournal steht für diese Charge keine einzige Palette.`,
        warum: `Diese ${kg(kgZ, 0)} zieht die App von keinem Lager ab. Die Ware kam von irgendwoher — dort steht sie jetzt noch im Lager, obwohl sie verkauft ist.`,
        tun: 'Im Erntejournal nachsehen, ob die Paletten unter einer anderen Sorte stehen (dann dort berichtigen), oder in Perigon, ob auf dem Lieferschein die falsche Charge steht.' }
    case 'vor_eingang': {
      const erst = typeof m.erster_eingang === 'string' ? m.erster_eingang : null
      return { ...basis, schwere: (kgZ ?? 0) >= 500 ? 'rot' : 'gelb',
        titel: `Charge ${name(z)} hat verkauft, bevor sie eingegangen war`,
        was: `${kg(kgZ, 0)} in ${stueck(z.n, 'Lieferschein', 'Lieferscheinen')} gingen ${spanne(z.von, z.bis)} hinaus — die Charge kam laut Erntejournal erst am ${datum(erst)}.`,
        warum: 'Was vor dem Eingang hinausgeht, kann nicht von dieser Charge sein. Bei der Charge, von der es wirklich kam, steht es noch im Lager.',
        tun: 'Klären, welche Ware das war: Stimmt das Datum im Journal (vom Papier nachgetragen)? Oder gehört der Lieferschein zu einer Charge desselben Schlags, die schon da war?',
        zeilen: perigon.filter(p => p.art === 'Lieferung vor dem Eingang' && p.charge_nr === z.charge_nr) }
    }
    case 'ueberzaehlung': {
      const gel = n(m.geliefert_kg), ein = n(m.eingang_kg), aus = n(m.ausgelagert_kg)
      return { ...basis, schwere: (kgZ ?? 0) >= 1000 || (ein && (kgZ ?? 0) >= 0.1 * ein) ? 'rot' : 'gelb',
        titel: `Charge ${name(z)} hat mehr verkauft, als sie hergeben kann`,
        was: `Verkauft sind ${kg(gel, 0)}. Mit dem gerechneten Verlust brauchte das ${kg(aus, 0)} Eingangsware — eingegangen sind ${kg(ein, 0)}. Es fehlen ${kg(kgZ, 0)}.`,
        warum: `Diese ${kg(kgZ, 0)} zieht die App von keinem Lager ab: Entweder fehlt im Journal eine Palette, ein Lieferschein trägt die falsche Charge — oder die Charge verliert weniger, als gerechnet.`,
        tun: 'Zuerst die Paletten im Journal mit dem Lager vergleichen; dann die Lieferscheine dieser Charge ansehen — passt einer eher zu einer Charge desselben Schlags?' }
    }
    case 'ohne_charge': {
      const vor = n(m.kg_vor_eingang) ?? 0, ohneZiel = n(m.kg_ohne_ziel) ?? 0
      const verteilt = Array.isArray(m.verteilt_auf) ? (m.verteilt_auf as { charge_nr: number; kg: number }[]) : []
      const gross = [...verteilt].sort((a, b) => b.kg - a.kg).slice(0, 3).map(v => `${v.charge_nr} ${tonnen(v.kg)}`).join(', ')
      return { ...basis, schwere: vor + ohneZiel >= 500 ? 'rot' : 'gelb',
        titel: `${stueck(z.n, 'Lieferschein', 'Lieferscheine')} ${z.sorte ?? 'ohne Sorte'} ohne Chargennummer`,
        was: `${kg(kgZ, 0)} ${z.sorte ?? ''} gingen ${spanne(z.von, z.bis)} hinaus, ohne dass Perigon sagt, von welcher Charge. `
          + (verteilt.length ? `Die App verteilt sie nach Menge auf ${stueck(verteilt.length, 'Charge', 'Chargen')} dieser Sorte (am meisten: ${gross}).` : 'Keine Charge dieser Sorte hat Eingang — die App kann sie nirgends abziehen.')
          + (vor > 0.5 ? ` ${kg(vor, 0)} davon fallen auf Chargen, die damals noch gar nicht da waren.` : '')
          + (ohneZiel > 0.5 && verteilt.length ? ` ${kg(ohneZiel, 0)} fallen auf gar keine Charge.` : ''),
        warum: 'Für die Menge der ganzen Sorte stimmt das ungefähr, für die einzelne Charge nicht: Wo die Ware wirklich herkam, steht zu viel im Lager, anderswo zu wenig.',
        tun: 'In Perigon an diesen Lieferscheinen die Charge nachtragen und die Datei unter Betrieb → Warenausgang neu einlesen.' }
    }
    case 'umgebucht':
    case 'vorschlag': {
      const von = n(m.von_charge_nr)
      const grund = typeof m.grund === 'string' ? m.grund : ''
      const paletten = Array.isArray(m.paletten) ? (m.paletten as number[]) : []
      const eingang = spanne(z.von, z.bis).replace(/^am /, 'vom ').replace(/^zwischen /, 'vom ')
      if (z.art === 'umgebucht') return { ...basis, schwere: 'info', paletten, von_charge_nr: von,
        titel: `${stueck(z.n, 'Palette', 'Paletten')} von Charge ${von} zählt die App bei Charge ${z.charge_nr}`,
        was: `${grund}. Die Paletten ${eingang} (${kg(kgZ, 0)}) stehen im Erntejournal unter ${von}; verarbeitet und verkauft wurden sie als ${z.charge_nr}.`,
        warum: `So stimmen beide Chargen wieder: ${von} zeigt keine Ware mehr, die längst verkauft ist, und ${z.charge_nr} verkauft nicht mehr, als es bekam.`,
        tun: `Im Erntejournal die Sorte dieser Paletten berichtigen${m.von_betriebsleiter ? '' : ' — oder, wenn die Umbuchung nicht stimmt, hier zurücknehmen'}.` }
      return { ...basis, schwere: 'gelb', paletten, von_charge_nr: von,
        titel: `${stueck(z.n, 'Palette', 'Paletten')} von Charge ${von} gehören wohl zu Charge ${z.charge_nr}`,
        was: `${grund}.`,
        warum: `Der Beleg reicht nicht, um es sicher zu sagen — die App bucht nichts um. Stimmt es, steht bei ${von} zu viel im Lager (${kg(kgZ, 0)}), und ${z.charge_nr} verkauft mehr, als es bekam.`,
        tun: `Nachzählen, wie viele Paletten von ${von} noch stehen. Passt es, hier umbuchen — oder im Erntejournal die Sorte berichtigen.` }
    }
  }
}

/** Die Perigon-Zeilen einer Art als eine Sache (Lieferung vor dem Eingang gehört zur Charge, nicht hierher). */
export function ausPerigon(art: string, zeilen: PerigonPruefung[]): Ungereimtheit {
  const summe = zeilen.reduce((a, z) => a + Number(z.kg ?? 0), 0)
  const k = zeilen.length
  const basis = { schluessel: `perigon:${art}`, art, kg: zeilen.some(z => z.kg != null) ? summe : null, charge_nr: null, sorte: null, zeilen }
  switch (art) {
    case 'Charge nicht zugeordnet':
      return { ...basis, schwere: 'rot',
        titel: `${stueck(k, 'Lieferschein nennt', 'Lieferscheine nennen')} eine Charge, die die App nicht kennt`,
        was: 'Auf dem Lieferschein steht eine Chargennummer, aber im Chargenregister der App gibt es sie nicht (oder nicht eindeutig).',
        warum: 'Die Ware zählt bei keiner Charge — wo sie herkam, steht sie noch im Lager.',
        tun: 'Unter Stammdaten → Chargen die Nummer anlegen oder bei der richtigen Charge als Perigon-Nr. eintragen. Beim nächsten Rechnen bekommen die Lieferscheine ihre Charge von selbst.' }
    case 'Teil ohne Charge':
      return { ...basis, schwere: summe >= 500 ? 'rot' : 'gelb',
        titel: `${stueck(k, 'Position liefert', 'Positionen liefern')} mehr, als sie Chargen zuschreiben`,
        was: 'Die Position nennt eine Menge, schreibt aber nur einen Teil davon einer Charge zu (Spalte S „AufPosBatchQuantity Charge"). Der Rest hat keine Charge.',
        warum: 'Der Rest zählt im Warenausgang, aber bei keiner Charge — dort, wo er herkam, steht er noch im Lager.',
        tun: 'In Perigon die Chargenmengen dieser Positionen prüfen.' }
    case 'Artikel passt nicht zur Sorte':
      return { ...basis, schwere: 'gelb',
        titel: `${stueck(k, 'Lieferschein', 'Lieferscheine')}: Artikel und Charge passen nicht zusammen`,
        was: 'Verkauft wurde ein Artikel einer anderen Gruppe als die Sorte der Charge, die auf dem Lieferschein steht (etwa Mandarin aus einer Kaori-Kuri-Charge).',
        warum: 'Entweder stimmt die Charge nicht — dann fehlt die Ware bei der richtigen Charge — oder der Artikel; dann stimmt das Lager nach Artikel nicht.',
        tun: 'Den Lieferschein ansehen: Ist der Artikel falsch oder die Charge?' }
    case 'Als Demeter verkauft, als Knospe geliefert':
      return { ...basis, schwere: 'gelb',
        titel: `${stueck(k, 'Lieferschein', 'Lieferscheine')}: Demeter-Preis für Knospe-Ware`,
        was: 'Verkauft in der Preisgruppe Demeter, aber die Ware der Charge trägt das Lieferlabel Knospe.',
        warum: 'Dem Kunden wurde Demeter verrechnet, geliefert wurde Knospe — oder das Label in Perigon stimmt nicht.',
        tun: 'Label und Preisgruppe in Perigon prüfen.' }
    default:
      return { ...basis, schwere: 'gelb', titel: `${stueck(k, 'Perigon-Zeile', 'Perigon-Zeilen')}: ${art}`, was: zeilen[0]?.befund ?? '', warum: '', tun: '' }
  }
}

const RANG: Record<Schwere, number> = { rot: 0, gelb: 1, info: 2 }

/** Alles zusammen, das Schwerste und Grösste zuerst. */
export function ungereimtheiten(zeilen: UngereimtZeile[], perigon: PerigonPruefung[]): Ungereimtheit[] {
  const liste = zeilen.map(z => ausZeile(z, perigon))
  const arten = new Map<string, PerigonPruefung[]>()
  for (const p of perigon) {
    if (p.art === 'Lieferung vor dem Eingang') continue
    arten.set(p.art, [...(arten.get(p.art) ?? []), p])
  }
  for (const [art, z] of arten) liste.push(ausPerigon(art, z))
  return liste.sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || (b.kg ?? 0) - (a.kg ?? 0))
}

/** Die Sachen einer Charge — für die aufgeklappte Charge und das Zeichen in ihrer Zeile. */
export function vonCharge(liste: Ungereimtheit[], nr: number): Ungereimtheit[] {
  return liste.filter(u => u.charge_nr === nr || u.von_charge_nr === nr || u.zeilen.some(z => z.charge_nr === nr))
}

/**
 * Welche Spalten der Perigon-Zeile zu einer Art gehören — sie werden im
 * Lieferungs-Fenster rot umrandet (Spaltennamen wie in der Datei).
 */
export const FALSCHE_SPALTEN: Record<string, string[]> = {
  'Charge nicht zugeordnet': ['AuftragsChargeManuell'],
  'Teil ohne Charge': ['AuftragsArtikelMenge', 'AufPosBatchQuantity Charge', 'AuftragsChargeManuell'],
  'Artikel passt nicht zur Sorte': ['AuftragsArtikel', 'AuftragsChargeManuell'],
  'Als Demeter verkauft, als Knospe geliefert': ['AuftragsPrsGrpBez', 'LiefPrsGrpName'],
  'Lieferung vor dem Eingang': ['AuftragsLieferDatum', 'AuftragsChargeManuell'],
  ohne_charge: ['AuftragsChargeManuell'],
  ohne_eingang: ['AuftragsChargeManuell'],
}
