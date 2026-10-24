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
import type { ChargeSpur, LieferungOhneCharge, OhneChargeGrund, PerigonBefund, UngereimtZeile } from './daten'
import { STATION_NAME, datum, kg, tonnen } from '../lib/format.ts'
import { PERIGON_ART } from './perigon.ts'

/**
 * Eine Perigon-Zeile, um die es bei einer Sache geht (0126: aus v_perigon_befund,
 * vorher v_perigon_pruefung — die alten Namen der Arten gelten weiter).
 */
export type PerigonZeile = Pick<PerigonBefund, 'quelle' | 'pos_id' | 'datum' | 'kunde' | 'artikel' | 'charge_nr' | 'kg'> & { art: string; satz?: string; befund?: string }

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
  zeilen: PerigonZeile[]
  /** Für umgebucht/vorschlag: welche Paletten (der Betriebsleiter nimmt zurück oder bucht) und woher sie kommen. */
  paletten?: number[]
  von_charge_nr?: number | null
  /**
   * 0122: die Chargen, deren Weg unter der Sache steht (herein, bearbeitet,
   * hinaus) — die Charge selbst, woher umgebucht wird, woher die Ware wohl kam,
   * oder die Chargen mit derselben Perigon-Nummer.
   */
  beteiligt: number[]
  /** 0122: Was schon umgebucht oder zugeordnet ist — und was nicht. */
  stand: string
  /** 0122: Was die App tun würde. Umgebucht wird damit nichts. */
  vorschlag: string
  /** 0122: Ein Vorschlag fürs Chargenregister, den der Betriebsleiter mit einem Klick übernimmt. */
  perigonSetzen?: { charge_nr: number; perigon_nr: number }
  /** Runde BE: die Nummern (Spalte W), unter denen die Belege in Perigon stehen — wo sie keiner Charge gehören */
  nummern?: string[]
}

/** 0122: eine Charge, von der die Ware wohl kam (v_ungereimtheit.mehr.kandidaten). */
export interface Kandidat {
  charge_nr: number; schlag: string; sorte: string; rest_paletten: number
  eingang_kg: number; geliefert_kg: number; eingang_von: string | null
  gleicher_schlag: boolean; gleiche_sorte: boolean
}

/** Je Art der Name auf dem Chip und ein Satz, was sie heisst. */
export const ART_NAME: Record<string, string> = {
  // 0126: die Arten der Perigon-Fälle (v_perigon_befund); was gleich heisst wie eine Sache je Charge, nimmt deren Namen
  ...Object.fromEntries(Object.entries(PERIGON_ART).map(([art, info]) => [art, info.name])),
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
  nachgeordnet: 'Über den Produzenten zugeordnet',
  stammdaten: 'Chargenregister stimmt nicht',
}

const n = (x: unknown): number | null => (x === null || x === undefined || x === '' ? null : Number(x))
const stueck = (k: number, ein: string, mehr: string) => `${k} ${k === 1 ? ein : mehr}`
const name = (z: { charge_nr: number | null; schlag: string | null; sorte: string | null }) =>
  `${z.charge_nr}${z.schlag || z.sorte ? ` (${[z.schlag, z.sorte].filter(Boolean).join(' · ')})` : ''}`
const spanne = (von: string | null, bis: string | null) =>
  !von ? '' : bis && bis !== von ? `zwischen ${datum(von)} und ${datum(bis)}` : `am ${datum(von)}`

/**
 * 0122: Der Betrieb, 23. Oktober: „Was hast du schon umgebucht, was noch
 * nicht, was würdest du wie umbuchen?" Bei Ware, die hinausging, ohne dass
 * die Charge sie hatte, nennt die Datenbank die Chargen, von denen sie wohl
 * kam (ungereimt_kandidaten): derselbe Artikel, laut App noch Paletten da,
 * höchstens die Hälfte verkauft, eingegangen vor dem letzten Lieferschein.
 * Hier wird daraus ein Satz — mit dem, was man zählen muss, bevor man es
 * glaubt.
 */
function kandidatenListe(m: Record<string, unknown>): Kandidat[] {
  return Array.isArray(m.kandidaten) ? (m.kandidaten as Kandidat[]) : []
}
const kandidatName = (k: Kandidat) => `${k.charge_nr} (${k.schlag} · ${k.sorte})`
function woherVorschlag(nr: number | null, kgZ: number | null, ks: Kandidat[]): string {
  if (ks.length === 0) return `Keine andere Charge desselben Artikels hat laut App noch viel unverkaufte Ware — dann stimmt eher die Charge auf den Lieferscheinen nicht, oder bei ${nr} fehlt eine Palette im Journal.`
  const [k, ...rest] = ks
  const warum = [k.gleicher_schlag ? 'derselbe Schlag' : null, k.gleiche_sorte ? 'dieselbe Sorte' : 'derselbe Artikel'].filter(Boolean).join(', ')
  return `Am ehesten von ${kandidatName(k)} — ${warum}; dort stehen laut App noch ≈ ${Math.round(k.rest_paletten)} Paletten, ${k.geliefert_kg > 0 ? `verkauft ist erst ${tonnen(k.geliefert_kg)} von ${tonnen(k.eingang_kg)}` : `von ${tonnen(k.eingang_kg)} ist noch nichts verkauft`}.`
    + (rest.length ? ` Sonst ${rest.map(kandidatName).join(', ')}.` : '')
    + ` Zählen: Fehlen dort Paletten für etwa ${kg(kgZ, 0)}, war es diese Ware — dann in Perigon die Charge der Lieferscheine auf ${k.charge_nr} berichtigen und neu einlesen.`
}

/** Eine Zeile aus v_ungereimtheit in Sätzen. */
export function ausZeile(z: UngereimtZeile, perigon: PerigonZeile[]): Ungereimtheit {
  const m = z.mehr ?? {}
  const kgZ = n(z.kg)
  const basis = { schluessel: `${z.art}:${z.charge_nr ?? z.sorte ?? ''}:${String(m.auftrag_id ?? m.pruefung ?? '')}`, art: z.art, kg: kgZ, charge_nr: z.charge_nr, sorte: z.sorte,
    zeilen: [] as PerigonZeile[], beteiligt: z.charge_nr != null ? [z.charge_nr] : [], stand: '', vorschlag: '' }
  const ks = kandidatenListe(m)
  const mitKandidaten = { beteiligt: [...basis.beteiligt, ...ks.slice(0, 2).map(k => k.charge_nr)], vorschlag: woherVorschlag(z.charge_nr, kgZ, ks),
    stand: 'Noch nicht umgebucht. Die App zieht diese Ware von keinem Lager ab, solange niemand sagt, woher sie kam.' }
  switch (z.art) {
    case 'ohne_eingang':
      return { ...basis, ...mitKandidaten, schwere: 'rot',
        titel: `Charge ${name(z)} hat verkauft, aber nie etwas bekommen`,
        was: `Perigon bucht ${stueck(z.n, 'Lieferschein', 'Lieferscheine')} mit ${kg(kgZ, 0)} auf Charge ${z.charge_nr} (${spanne(z.von, z.bis)}). Im Erntejournal steht für diese Charge keine einzige Palette.`,
        warum: `Diese ${kg(kgZ, 0)} zieht die App von keinem Lager ab. Die Ware kam von irgendwoher — dort steht sie jetzt noch im Lager, obwohl sie verkauft ist.`,
        tun: 'Im Erntejournal nachsehen, ob die Paletten unter einer anderen Sorte stehen (dann dort berichtigen), oder in Perigon, ob auf dem Lieferschein die falsche Charge steht.' }
    case 'vor_eingang': {
      const erst = typeof m.erster_eingang === 'string' ? m.erster_eingang : null
      return { ...basis, ...mitKandidaten, schwere: (kgZ ?? 0) >= 500 ? 'rot' : 'gelb',
        titel: `Charge ${name(z)} hat verkauft, bevor sie eingegangen war`,
        was: `${kg(kgZ, 0)} in ${stueck(z.n, 'Lieferschein', 'Lieferscheinen')} gingen ${spanne(z.von, z.bis)} hinaus — die Charge kam laut Erntejournal erst am ${datum(erst)}.`,
        warum: 'Was vor dem Eingang hinausgeht, kann nicht von dieser Charge sein. Bei der Charge, von der es wirklich kam, steht es noch im Lager.',
        tun: 'Klären, welche Ware das war: Stimmt das Datum im Journal (vom Papier nachgetragen)? Oder gehört der Lieferschein zu einer Charge desselben Schlags, die schon da war?',
        zeilen: perigon.filter(p => (p.art === 'Lieferung vor dem Eingang' || p.art === 'vor_eingang') && p.charge_nr === z.charge_nr) }
    }
    case 'ueberzaehlung': {
      const gel = n(m.geliefert_kg), ein = n(m.eingang_kg), aus = n(m.ausgelagert_kg)
      return { ...basis, ...mitKandidaten, schwere: (kgZ ?? 0) >= 1000 || (ein && (kgZ ?? 0) >= 0.1 * ein) ? 'rot' : 'gelb',
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
        stand: 'Keiner Charge zugeordnet — die App verteilt nur nach Menge.',
        titel: `${stueck(z.n, 'Lieferschein', 'Lieferscheine')} ${z.sorte ?? 'ohne Sorte'} ohne Chargennummer`,
        was: `${kg(kgZ, 0)} ${z.sorte ?? ''} gingen ${spanne(z.von, z.bis)} hinaus, ohne dass Perigon sagt, von welcher Charge. `
          + (verteilt.length ? `Die App verteilt sie nach Menge auf ${stueck(verteilt.length, 'Charge', 'Chargen')} dieser Sorte (am meisten: ${gross}).` : 'Keine Charge dieser Sorte hat Eingang — die App kann sie nirgends abziehen.')
          + (vor > 0.5 ? ` ${kg(vor, 0)} davon fallen auf Chargen, die damals noch gar nicht da waren.` : '')
          + (ohneZiel > 0.5 && verteilt.length ? ` ${kg(ohneZiel, 0)} fallen auf gar keine Charge.` : ''),
        warum: 'Für die Menge der ganzen Sorte stimmt das ungefähr, für die einzelne Charge nicht: Wo die Ware wirklich herkam, steht zu viel im Lager, anderswo zu wenig.',
        // 0125: warum jeder einzelne keine Charge hat, steht in der Liste darunter — die Wege sind verschieden.
        tun: 'Die Lieferscheine zeigen: bei jedem steht, warum er keine Charge hat und wo das zu ändern ist (Perigon, Stammdaten oder nichts).' }
    }
    case 'umgebucht':
    case 'vorschlag': {
      const von = n(m.von_charge_nr)
      const grund = typeof m.grund === 'string' ? m.grund : ''
      const paletten = Array.isArray(m.paletten) ? (m.paletten as number[]) : []
      const eingang = spanne(z.von, z.bis).replace(/^am /, 'vom ').replace(/^zwischen /, 'vom ')
      const beteiligt = [...(von != null ? [von] : []), ...basis.beteiligt]
      if (z.art === 'umgebucht') return { ...basis, schwere: 'info', paletten, von_charge_nr: von, beteiligt,
        stand: m.von_betriebsleiter
          ? `Schon umgebucht — vom Betriebsleiter bestätigt. Die ${stueck(z.n, 'Palette zählt', 'Paletten zählen')} bei ${z.charge_nr}; im Erntejournal stehen sie weiter unter ${von}.`
          : `Schon umgebucht — von der App, weil der Beleg reicht. Die ${stueck(z.n, 'Palette zählt', 'Paletten zählen')} bei ${z.charge_nr}; im Erntejournal stehen sie weiter unter ${von}.`,
        titel: `${stueck(z.n, 'Palette', 'Paletten')} von Charge ${von} zählt die App bei Charge ${z.charge_nr}`,
        was: `${grund}. Die Paletten ${eingang} (${kg(kgZ, 0)}) stehen im Erntejournal unter ${von}; verarbeitet und verkauft wurden sie als ${z.charge_nr}.`,
        warum: `So stimmen beide Chargen wieder: ${von} zeigt keine Ware mehr, die längst verkauft ist, und ${z.charge_nr} verkauft nicht mehr, als es bekam.`,
        tun: `Im Erntejournal die Sorte dieser Paletten berichtigen${m.von_betriebsleiter ? '' : ' — oder, wenn die Umbuchung nicht stimmt, hier zurücknehmen'}.` }
      return { ...basis, schwere: 'gelb', paletten, von_charge_nr: von, beteiligt,
        stand: `Noch nicht umgebucht — die ${stueck(z.n, 'Palette zählt', 'Paletten zählen')} weiter bei ${von}.`,
        vorschlag: `Die ${stueck(z.n, 'Palette', 'Paletten')} (${kg(kgZ, 0)}) von ${von} zu ${z.charge_nr} umbuchen, wenn beim Nachzählen bei ${von} so viele fehlen.`,
        titel: `${stueck(z.n, 'Palette', 'Paletten')} von Charge ${von} gehören wohl zu Charge ${z.charge_nr}`,
        was: `${grund}.`,
        warum: `Der Beleg reicht nicht, um es sicher zu sagen — die App bucht nichts um. Stimmt es, steht bei ${von} zu viel im Lager (${kg(kgZ, 0)}), und ${z.charge_nr} verkauft mehr, als es bekam.`,
        tun: `Nachzählen, wie viele Paletten von ${von} noch stehen. Passt es, hier umbuchen — oder im Erntejournal die Sorte berichtigen.` }
    }
    case 'nachgeordnet': {
      const nummern = Array.isArray(m.nummern) ? (m.nummern as string[]) : []
      const grund = typeof m.grund === 'string' ? m.grund : ''
      const pnr = n(m.perigon_nr)
      const nr1 = nummern.length === 1 ? Number(nummern[0]) : null
      const nummerText = nummern.length ? nummern.join(', ') : '–'
      return { ...basis, schwere: 'info', nummern,
        titel: `${stueck(z.n, 'Lieferschein', 'Lieferscheine')} mit der Nummer ${nummerText} zählt die App bei Charge ${name(z)}`,
        was: grund,
        warum: `Die Nummer steht im Chargenregister an keiner Charge. Ohne diese Zuordnung zählten ${kg(kgZ, 0)} bei keiner Charge — und bei ${z.charge_nr} stünde Ware im Lager, die längst verkauft ist.`,
        stand: 'Zugeordnet beim Rechnen, aber noch nicht fest: Die App ordnet bei jedem Rechnen neu zu.',
        vorschlag: nr1 === null ? '' : pnr != null && pnr !== nr1
          ? `Bei ${z.charge_nr} steht heute die Perigon-Nr. ${pnr}, Perigon schreibt ${nr1}. Stimmt ${nr1}, dort ${nr1} eintragen — dann steht es fest.`
          : `Bei ${z.charge_nr} die Perigon-Nr. ${nr1} eintragen — dann steht es fest.`,
        tun: 'Prüfen, ob es stimmt (Planungsliste, Perigon). Stimmt es nicht, in Perigon die Nummer auf den Lieferscheinen berichtigen und neu einlesen.',
        perigonSetzen: nr1 !== null && Number.isInteger(nr1) && z.charge_nr != null && pnr !== nr1 ? { charge_nr: z.charge_nr, perigon_nr: nr1 } : undefined }
    }
    case 'stammdaten':
      return ausStammdaten(z, basis)
  }
}

/**
 * 0122: Was im Chargenregister selbst nicht stimmt (v_stammdaten_pruefung).
 * Der Betrieb, 23. Oktober: „Rümlang Sauter 198976 1649 Butterkin, Rümlang
 * Sauter 198976 1650 Tiana — das sollte nicht sein; such auch nach solcher Art
 * von Ungereimtheiten." (Am selben Tag berichtigt: 1650 ist 198977.) Die App
 * ändert das Register nie selbst; sie sagt,
 * was sie vermutet, und der Betriebsleiter übernimmt es mit einem Klick.
 */
function ausStammdaten(z: UngereimtZeile, basis: Omit<Ungereimtheit, 'schwere' | 'titel' | 'was' | 'warum' | 'tun'>): Ungereimtheit {
  const m = z.mehr ?? {}
  const chargenNr = Array.isArray(m.chargen_nr) ? (m.chargen_nr as number[]) : basis.beteiligt
  const mit = { ...basis, beteiligt: chargenNr, stand: 'Nichts geändert — das Chargenregister ändert nur der Betriebsleiter.', vorschlag: '' }
  const und = (xs: string[]) => xs.length <= 1 ? xs.join('') : `${xs.slice(0, -1).join(', ')} und ${xs[xs.length - 1]}`
  switch (m.pruefung) {
    case 'perigon_doppelt': {
      const nr = n(m.perigon_nr)
      const chargen = Array.isArray(m.chargen) ? (m.chargen as { charge_nr: number; schlag: string; sorte: string }[]) : []
      const zeilen = n(m.zeilen_mit_nummer) ?? 0
      type V = { nummer: string; n: number; produzent: string | null; gruppe: string | null; charge_nr: number | null }
      const verwandte = Array.isArray(m.verwandte) ? (m.verwandte as V[]) : []
      // Eine verwandte Nummer, deren Lieferscheine die App schon einer der Chargen gibt, ist wohl deren Nummer.
      const treffer = verwandte.find(v => v.charge_nr != null && chargenNr.includes(v.charge_nr))
      const andere = treffer ? chargenNr.filter(c => c !== treffer.charge_nr) : []
      const vText = verwandte.map(v => `${v.nummer} (${stueck(v.n, 'Zeile', 'Zeilen')}${v.produzent ? `, Produzent ${v.produzent}` : ''}${v.gruppe ? `, ${v.gruppe}` : ''}${v.charge_nr != null ? ` — die App zählt sie bei ${v.charge_nr}` : ' — bei keiner Charge'})`)
      return { ...mit, schwere: zeilen > 0 ? 'rot' : 'gelb',
        nummern: [...(nr != null ? [String(nr)] : []), ...verwandte.map(v => v.nummer)],
        titel: `Perigon-Nr. ${nr} steht an ${stueck(chargen.length, 'Charge', 'Chargen')}: ${und(chargen.map(c => String(c.charge_nr)))}`,
        was: `Im Chargenregister tragen ${und(chargen.map(c => `${c.charge_nr} (${c.schlag} · ${c.sorte})`))} dieselbe Perigon-Nummer ${nr}. Eine Perigon-Nummer gehört zu genau einer Charge. `
          + (zeilen > 0 ? `In den Perigon-Dateien steht ${nr} auf ${stueck(zeilen, 'Zeile', 'Zeilen')}.` : `In den Perigon-Dateien kommt ${nr} nicht vor.`)
          + (vText.length ? ` Dafür stehen dort Nummern, die an keiner Charge stehen, aber dazu passen: ${vText.join('; ')}.` : ''),
        warum: `Lieferscheine mit ${nr} kann die App keiner der ${chargen.length === 2 ? 'beiden' : ''} Chargen geben — sie zählen bei keiner. Und die Nummer, die eine dieser Chargen in Perigon wirklich trägt, findet die App nicht.`,
        vorschlag: treffer
          ? `Wohl hat ${treffer.charge_nr} die Nummer ${treffer.nummer}: Perigon schreibt sie bei ${treffer.gruppe ?? 'dieser Ware'}${treffer.produzent ? ` von ${treffer.produzent}` : ''}, und die App zählt diese Lieferscheine schon dort. Dann bei ${treffer.charge_nr} ${treffer.nummer} eintragen; ${und(andere.map(String))} ${andere.length === 1 ? 'behält' : 'behalten'} ${nr}.`
          : '',
        tun: 'In der Planungsliste und in Perigon nachsehen, welche Charge welche Nummer hat, und unter Stammdaten → Chargen berichtigen.',
        perigonSetzen: treffer && treffer.charge_nr != null ? { charge_nr: treffer.charge_nr, perigon_nr: Number(treffer.nummer) } : undefined }
    }
    case 'ohne_perigon_nr': {
      const pal = n(m.paletten) ?? 0, lief = n(m.lieferscheine) ?? 0
      return { ...mit, schwere: 'gelb',
        titel: `Charge ${name(z)} hat keine Perigon-Nummer`,
        was: `Die Charge hat ${[pal ? stueck(pal, 'Palette', 'Paletten') : null, lief ? stueck(lief, 'Lieferschein', 'Lieferscheine') : null].filter(Boolean).join(' und ')}, aber im Register keine Perigon-Nummer.`,
        warum: 'Lieferscheine, auf denen die Perigon-Nummer statt der eigenen steht, findet die App bei dieser Charge nicht — sie zählen bei keiner.',
        stand: 'Noch keine Nummer eingetragen.',
        tun: 'Die Nummer aus der Planungsliste unter Stammdaten → Chargen eintragen.' }
    }
    case 'schlag_zweimal': {
      const nameR = typeof m.name === 'string' ? m.name : '', gemeint = typeof m.gemeint === 'string' ? m.gemeint : ''
      return { ...mit, schwere: 'gelb',
        titel: `Schlag „${nameR}" ist „${gemeint}"`,
        was: `Im Chargenregister steht „${nameR}" (${stueck(chargenNr.length, 'Charge', 'Chargen')} ${chargenNr.join(', ')}). Das ist derselbe Schlag wie „${gemeint}" — es gibt nur einen.`,
        warum: 'Die App zählt sonst zwei Schläge: Was im Journal oder in Perigon unter dem einen Namen steht, sucht sie beim anderen nicht.',
        vorschlag: `Unter Stammdaten → Chargen „${nameR}" in „${gemeint}" ändern.`,
        tun: 'Den Namen angleichen. Der zweite Name bleibt unter Stammdaten → Chargen („Wer wie heisst"), damit Journal und Perigon ihn weiter finden.' }
    }
    default:
      return { ...mit, schwere: 'gelb', titel: `Chargenregister: ${String(m.pruefung ?? '')}`, was: '', warum: '', tun: '' }
  }
}

/**
 * Die Perigon-Zeilen einer Art als eine Sache (Lieferung vor dem Eingang gehört zur Charge, nicht hierher).
 * 0126: die Arten heissen wie in v_perigon_befund; die alten Namen (v_perigon_pruefung) gelten weiter.
 */
export function ausPerigon(art: string, zeilen: PerigonZeile[]): Ungereimtheit {
  const summe = zeilen.reduce((a, z) => a + Math.abs(Number(z.kg ?? 0)), 0)
  const k = zeilen.length
  const basis = { schluessel: `perigon:${art}`, art, kg: zeilen.some(z => z.kg != null) ? summe : null, charge_nr: null, sorte: null, zeilen,
    beteiligt: [] as number[], stand: '', vorschlag: '' }
  switch (art) {
    case 'unbekannt':
    case 'mehrdeutig':
    case 'Charge nicht zugeordnet':
      return { ...basis, schwere: 'rot',
        titel: `${stueck(k, 'Lieferschein nennt', 'Lieferscheine nennen')} eine Charge, die die App nicht kennt`,
        was: 'Auf dem Lieferschein steht eine Chargennummer, aber im Chargenregister der App gibt es sie nicht (oder nicht eindeutig).',
        warum: 'Die Ware zählt bei keiner Charge — wo sie herkam, steht sie noch im Lager.',
        tun: 'Unter Stammdaten → Chargen die Nummer anlegen oder bei der richtigen Charge als Perigon-Nr. eintragen. Beim nächsten Rechnen bekommen die Lieferscheine ihre Charge von selbst.' }
    case 'rest':
    case 'Teil ohne Charge':
      return { ...basis, schwere: summe >= 500 ? 'rot' : 'gelb',
        titel: `${stueck(k, 'Position liefert', 'Positionen liefern')} mehr, als sie Chargen zuschreiben`,
        was: 'Die Position nennt eine Menge, schreibt aber nur einen Teil davon einer Charge zu (Spalte S „AufPosBatchQuantity Charge"). Der Rest hat keine Charge.',
        warum: 'Der Rest zählt im Warenausgang, aber bei keiner Charge — dort, wo er herkam, steht er noch im Lager.',
        tun: 'In Perigon die Chargenmengen dieser Positionen prüfen.' }
    case 'artikel_sorte':
    case 'Artikel passt nicht zur Sorte':
      return { ...basis, schwere: 'gelb',
        titel: `${stueck(k, 'Lieferschein', 'Lieferscheine')}: Artikel und Charge passen nicht zusammen`,
        was: 'Verkauft wurde ein Artikel einer anderen Gruppe als die Sorte der Charge, die auf dem Lieferschein steht (etwa Mandarin aus einer Kaori-Kuri-Charge).',
        warum: 'Entweder stimmt die Charge nicht — dann fehlt die Ware bei der richtigen Charge — oder der Artikel; dann stimmt das Lager nach Artikel nicht.',
        tun: 'Den Lieferschein ansehen: Ist der Artikel falsch oder die Charge?' }
    case 'demeter_knospe':
    case 'Als Demeter verkauft, als Knospe geliefert':
      return { ...basis, schwere: 'gelb',
        titel: `${stueck(k, 'Lieferschein', 'Lieferscheine')}: Demeter-Preis für Knospe-Ware`,
        was: 'Verkauft in der Preisgruppe Demeter, aber die Ware der Charge trägt das Lieferlabel Knospe.',
        warum: 'Dem Kunden wurde Demeter verrechnet, geliefert wurde Knospe — oder das Label in Perigon stimmt nicht.',
        tun: 'Label und Preisgruppe in Perigon prüfen.' }
    default: {
      // 0126: die übrigen Arten — Name, was es heisst und was zu tun ist, wie im Reiter Perigon
      const info = (PERIGON_ART as Record<string, (typeof PERIGON_ART)[keyof typeof PERIGON_ART] | undefined>)[art]
      const nurAuskunft = art === 'nachholen' || art === 'ruecknahme'
      return { ...basis, schwere: nurAuskunft ? 'info' : summe >= 500 && art !== 'mix' && art !== 'label_name' ? 'rot' : 'gelb',
        titel: `${stueck(k, 'Perigon-Zeile', 'Perigon-Zeilen')}: ${info?.name ?? art}`,
        was: info?.heisst ?? zeilen[0]?.satz ?? zeilen[0]?.befund ?? '', warum: info?.app ?? '', tun: info?.tun ?? '' }
    }
  }
}

const RANG: Record<Schwere, number> = { rot: 0, gelb: 1, info: 2 }

/** Alles zusammen, das Schwerste und Grösste zuerst. */
export function ungereimtheiten(zeilen: UngereimtZeile[], perigon: PerigonZeile[] = []): Ungereimtheit[] {
  const liste = zeilen.map(z => ausZeile(z, perigon))
  const arten = new Map<string, PerigonZeile[]>()
  for (const p of perigon) {
    if (p.art === 'Lieferung vor dem Eingang' || p.art === 'vor_eingang') continue
    arten.set(p.art, [...(arten.get(p.art) ?? []), p])
  }
  for (const [art, z] of arten) liste.push(ausPerigon(art, z))
  return liste.sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || (b.kg ?? 0) - (a.kg ?? 0))
}

/** Die Sachen einer Charge — für die aufgeklappte Charge und das Zeichen in ihrer Zeile. */
export function vonCharge(liste: Ungereimtheit[], nr: number): Ungereimtheit[] {
  // 0122: eine doppelte Perigon-Nummer gehört zu jeder ihrer Chargen; ein Kandidat („woher wohl") nicht —
  // die Charge hat dann nichts falsch gemacht, sie steht nur im Vorschlag.
  return liste.filter(u => u.charge_nr === nr || u.von_charge_nr === nr || u.zeilen.some(z => z.charge_nr === nr)
    || (u.art === 'stammdaten' && u.beteiligt.includes(nr)))
}

/**
 * Welche Spalten der Perigon-Zeile zu einer Art gehören — sie werden im
 * Lieferungs-Fenster rot umrandet (Spaltennamen wie in der Datei).
 */
/* ---------- 0125: Lieferscheine ohne Charge, je mit Grund -------------- */

/** Der Grund in zwei, drei Worten — für die Übersicht und die Marke an der Zeile. */
export const OHNE_CHARGE_GRUND: Record<OhneChargeGrund, string> = {
  unbekannt: 'Nummer an keiner Charge',
  mehrdeutig: 'Nummer an mehreren Chargen',
  nachholen: 'Nummer jetzt bekannt',
  menge_null: 'Charge ohne Menge (Spalte S = 0)',
  rest: 'nur teilweise zugeteilt',
  keine_nummer: 'keine Chargennummer',
  ohne_zeile: 'Perigon-Zeile fehlt',
  von_hand: 'von Hand erfasst',
}
/** Wer es richtigstellt: Perigon (Datei), die Stammdaten der App, oder es erledigt sich mit dem nächsten Rechnen. */
export const OHNE_CHARGE_WO: Record<OhneChargeGrund, 'perigon' | 'stammdaten' | 'rechnen' | 'app'> = {
  unbekannt: 'stammdaten', mehrdeutig: 'stammdaten', nachholen: 'rechnen',
  menge_null: 'perigon', rest: 'perigon', keine_nummer: 'perigon', ohne_zeile: 'app', von_hand: 'app',
}

export interface OhneChargeGruppe { grund: OhneChargeGrund; name: string; n: number; kg: number; nummern: string[] }

/** Die Lieferscheine ohne Charge nach Grund: wie viele, wie viel, welche Nummern — das Schwerste zuerst. */
export function ohneChargeUebersicht(liste: LieferungOhneCharge[]): OhneChargeGruppe[] {
  const je = new Map<OhneChargeGrund, OhneChargeGruppe>()
  for (const l of liste) {
    const g = je.get(l.grund) ?? { grund: l.grund, name: OHNE_CHARGE_GRUND[l.grund] ?? l.grund, n: 0, kg: 0, nummern: [] }
    g.n += 1; g.kg += Number(l.kg) || 0
    for (const nr of (l.nummer ?? '').split(',').map(x => x.trim()).filter(Boolean)) if (!g.nummern.includes(nr)) g.nummern.push(nr)
    je.set(l.grund, g)
  }
  return [...je.values()].sort((a, b) => b.kg - a.kg || a.name.localeCompare(b.name))
}

/** Die Zellen der Perigon-Zeile, die beim jeweiligen Grund nicht stimmen (rot umrandet im Fenster). */
export const OHNE_CHARGE_SPALTEN: Record<OhneChargeGrund, string[]> = {
  unbekannt: ['AuftragsChargeManuell'], mehrdeutig: ['AuftragsChargeManuell'], nachholen: ['AuftragsChargeManuell'],
  keine_nummer: ['AuftragsChargeManuell'], menge_null: ['AufPosBatchQuantity Charge', 'AuftragsChargeManuell'],
  rest: ['AuftragsArtikelMenge', 'AufPosBatchQuantity Charge'], ohne_zeile: [], von_hand: [],
}

export const FALSCHE_SPALTEN: Record<string, string[]> = {
  'Charge nicht zugeordnet': ['AuftragsChargeManuell'],
  'Teil ohne Charge': ['AuftragsArtikelMenge', 'AufPosBatchQuantity Charge', 'AuftragsChargeManuell'],
  'Artikel passt nicht zur Sorte': ['AuftragsArtikel', 'AuftragsChargeManuell'],
  'Als Demeter verkauft, als Knospe geliefert': ['AuftragsPrsGrpBez', 'LiefPrsGrpName'],
  'Lieferung vor dem Eingang': ['AuftragsLieferDatum', 'AuftragsChargeManuell'],
  ohne_charge: ['AuftragsChargeManuell'],
  ohne_eingang: ['AuftragsChargeManuell'],
  // 0126: die Arten der Perigon-Fälle (v_perigon_befund)
  ...Object.fromEntries(Object.entries(PERIGON_ART).map(([art, info]) => [art, info.spalten])),
}

/**
 * 0122: Der Weg der Ware einer Charge in drei Stationen — für die kleine
 * Tabelle unter jeder Sache. Der Betrieb, 23. Oktober: „Aktuell ist noch nicht
 * ganz klar, was jetzt von welcher Charge war — ob der Eingang bei welcher
 * Charge war, dann die Arbeit im Lager bei welcher Charge und der
 * Warenausgang bei welcher Charge." Je Station eine Zeile mit Menge und Tagen;
 * was umgebucht ist oder nur vorgeschlagen, steht beim Eingang, Ware unter
 * fremdem Artikel beim Ausgang. Leer heisst „keine", unbekannt heisst
 * „unbekannt" — nie 0 für etwas, das fehlt.
 */
export interface SpurText {
  charge: string
  herein: string[]
  bearbeitet: string[]
  hinaus: string[]
  noch: string
  /** Verkauft, aber nie eingegangen — der Eingang ist in der Tabelle rot. */
  ohneEingang: boolean
}

const kurzTag = (iso: string | null) => {
  if (!iso) return ''
  const [, mo, ta] = iso.slice(0, 10).split('-')
  return `${Number(ta)}.${Number(mo)}.`
}
export const spanneKurz = (von: string | null, bis: string | null) =>
  !von ? '' : bis && bis.slice(0, 10) !== von.slice(0, 10) ? `${kurzTag(von)}–${kurzTag(bis)}` : kurzTag(von)

export function spurText(s: ChargeSpur): SpurText {
  const pal = (k: number) => stueck(k, 'Palette', 'Paletten')
  const herein = s.journal_paletten > 0
    ? [`${pal(s.journal_paletten)} · ${tonnen(n(s.journal_kg))}`, spanneKurz(s.journal_von, s.journal_bis)]
    : ['keine Palette im Journal']
  for (const w of s.weg ?? [])
    herein.push(w.stand === 'angewandt' ? `→ ${pal(w.paletten)} zu ${w.charge_nr} umgebucht` : `→ ${pal(w.paletten)} gehören wohl zu ${w.charge_nr} (nicht umgebucht)`)
  for (const h of s.her ?? [])
    herein.push(h.stand === 'angewandt' ? `← ${pal(h.paletten)} von ${h.charge_nr} umgebucht` : `← ${pal(h.paletten)} von ${h.charge_nr} wohl hierher (nicht umgebucht)`)
  if (s.paletten !== s.journal_paletten) herein.push(`die App zählt ${pal(s.paletten)}`)

  const stationen = new Map<string, number>()
  for (const a of s.arbeit_liste ?? []) stationen.set(a.station, (stationen.get(a.station) ?? 0) + 1)
  const bearbeitet = s.arbeiten > 0
    ? [[...stationen].map(([st, k]) => `${k}× ${STATION_NAME[st] ?? st}`).join(', '), spanneKurz(s.arbeit_von, s.arbeit_bis)]
    : ['keine Arbeit']

  const hinaus = s.lieferscheine > 0
    ? [`${stueck(s.lieferscheine, 'Lieferschein', 'Lieferscheine')} · ${tonnen(n(s.geliefert_kg))}`, spanneKurz(s.lief_von, s.lief_bis)]
    : ['kein Lieferschein']
  // 0124: was keine Perigon-Zeile hat (von Hand erfasst), ist ein eigener Teil — kein fremder Artikel
  const hand = (s.nach_artikel ?? []).find(a => a.gruppe === 'ohne Perigon-Zeile')
  // Ware unter einem anderen Artikel als die Sorte der Charge (Mix ist gemischt, nicht fremd)
  const fremd = (s.nach_artikel ?? []).filter(a => s.artikelgruppe && a.gruppe !== s.artikelgruppe && a.gruppe !== 'Mix' && a.gruppe !== 'ohne Perigon-Zeile')
  if (fremd.length) hinaus.push(`davon als ${fremd.map(a => `${a.gruppe === 'andere' ? 'anderer Artikel' : a.gruppe} ${tonnen(a.kg)}`).join(', ')}`)
  if (hand) hinaus.push(`${tonnen(hand.kg)} davon ohne Perigon-Zeile (von Hand erfasst)`)
  const prod = (s.nachgeordnet ?? []).find(x => x.weg === 'produzent')
  if (prod) hinaus.push(`${prod.n} davon über den Produzenten zugeordnet`)

  const rest = n(s.rest_paletten)
  return {
    charge: `${s.charge_nr} · ${s.schlag} · ${s.sorte}`,
    herein: herein.filter(Boolean), bearbeitet: bearbeitet.filter(Boolean), hinaus: hinaus.filter(Boolean),
    noch: rest === null ? 'unbekannt' : `≈ ${pal(Math.max(0, Math.round(rest)))}`,
    ohneEingang: s.journal_paletten === 0 && s.paletten === 0 && s.lieferscheine > 0,
  }
}

