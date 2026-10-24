/**
 * Der Reiter Perigon (0126) — was nicht zusammenpasst, nachvollziehbar und
 * mitverfolgt. Der Betrieb, 24. Oktober: „mach einen neuen Reiter und behandle
 * dort die Ungereimtheiten mit viel Detail, mit viel Rückverfolgbarkeit, so
 * dass man es nachvollziehen kann — was sind die Fehler —, dass man sie
 * anklicken und dann auch mitverfolgen kann." Und: „alles, was du im PDF
 * hast, dort in den Reiter — das mit 1719 etc."
 *
 * Hier steht, ohne React (test/perigon.test.ts prüft es):
 *  - je Art, was sie heisst (für jemanden ohne Perigon), woran man sie in der
 *    Datei sieht, was die App daraus macht, was zu tun ist und wo;
 *  - der Stand je Fall aus dem Protokoll (offen, in Abklärung, erledigt,
 *    kein Fehler);
 *  - die Fälle nach Art, nach Sorte (Fall für Fall, wie im Bericht vom
 *    23. Oktober) und nach dem, was zu tun ist.
 * Die Zahlen kommen aus der Datenbank (v_perigon_befund, v_ungereimtheit,
 * v_charge_spur); hier werden sie nur geordnet und in Worte gefasst.
 */
import type { ChargeSpur, PerigonArt, PerigonBefund, PerigonVerlauf, PerigonWo, VermerkStand } from './daten'
import type { Schwere, Ungereimtheit } from './ungereimt'
import { PERIGON_ANSICHT, spaltenBuchstabe } from '../lib/warenausgang.ts'
import { datum, kg, tonnen } from '../lib/format.ts'

/** Wo ein Fall behoben wird — die Fälle einer Position (Perigon) und die Sachen je Charge (Halle, Journal). */
export type Wo = PerigonWo | 'halle' | 'journal'

export interface PerigonArtInfo {
  /** kurz, für Listen und Chips */
  name: string
  /** was es heisst, in Worten ohne Perigon-Kenntnis */
  heisst: string
  /** woran man es in der Datei sieht (Spalten) */
  datei: string
  /** was die App daraus macht — und was sie bewusst nicht tut */
  app: string
  tun: string
  /** die Spalten der Datei, die im Fenster rot umrandet stehen */
  spalten: string[]
  wo: PerigonWo
  /** eine Position (alle ihre Zeilen) oder eine einzelne Chargenzeile */
  ebene: 'position' | 'chargenzeile'
}

/** Je Art eines Perigon-Falls (v_perigon_befund, 0126). */
export const PERIGON_ART: Record<PerigonArt, PerigonArtInfo> = {
  menge_null: {
    name: 'Charge ohne Menge (Spalte S = 0)', ebene: 'position', wo: 'perigon',
    heisst: 'Perigon schreibt die Chargennummer hin, teilt ihr aber keine Menge zu. Damit ist die Ware für die App von keiner Charge.',
    datei: 'Spalte W: eine oder mehrere Nummern · Spalte S: 0 · Spalte Q: die Menge der Position (manchmal auch 0).',
    app: 'Die ganze Position wird eine Lieferung ohne Charge und nach Menge auf alle Chargen der Sorte verteilt. Bei der Charge, von der die Ware wirklich kam, bleibt sie im Lager stehen. Steht auch in Q eine 0, zählt die Position gar nicht.',
    tun: 'In Perigon bei der Position die Menge je Charge (Spalte S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.',
    spalten: ['AufPosBatchQuantity Charge', 'AuftragsChargeManuell', 'AuftragsArtikelMenge'],
  },
  zu_viel: {
    name: 'Chargenzeilen mehr als die Position', ebene: 'position', wo: 'perigon',
    heisst: 'Eine Position steht je Charge einmal da. Zusammen ergeben die Mengen je Charge mehr, als die Position geliefert hat — oft, weil dieselbe Zeile zwei- oder dreimal dasteht.',
    datei: 'Spalte Q: die Menge der Position (auf jeder Zeile gleich) · Spalte S je Zeile: zusammen mehr als Q.',
    app: 'Gezählt wird höchstens die Position: die Chargen bekommen ihre Menge in der Folge der Zeilen, bis die Position voll ist. Doppelt zählt nichts — bei mehreren Chargen sagt die Datei aber nicht sicher, welche wie viel bekam.',
    tun: 'In Perigon die Menge je Charge berichtigen und eine doppelte Zeile entfernen, dann neu einlesen.',
    spalten: ['AuftragsArtikelMenge', 'AufPosBatchQuantity Charge'],
  },
  rest: {
    name: 'Chargenzeilen weniger als die Position', ebene: 'position', wo: 'perigon',
    heisst: 'Die Mengen je Charge ergeben weniger, als die Position geliefert hat. Der Rest hat keine Charge.',
    datei: 'Spalte Q grösser als die Summe von Spalte S über die Zeilen der Position.',
    app: 'Die Chargen bekommen, was in S steht; der Rest wird eine Lieferung ohne Charge, verteilt auf alle Chargen der Sorte.',
    tun: 'In Perigon die Menge je Charge (Spalte S) nachtragen, dann neu einlesen.',
    spalten: ['AuftragsArtikelMenge', 'AufPosBatchQuantity Charge'],
  },
  keine_nummer: {
    name: 'Position ohne Chargennummer', ebene: 'position', wo: 'perigon',
    heisst: 'In der Chargenspalte steht nichts — Perigon sagt nicht, von welcher Charge die Ware ist.',
    datei: 'Spalte W leer.',
    app: 'Eine Lieferung ohne Charge, nach Menge auf alle Chargen der Sorte verteilt (die Sorte aus dem Artikel). Für die Sorte ungefähr richtig, für die einzelne Charge nicht.',
    tun: 'In Perigon Charge (Spalte W) und Menge je Charge (Spalte S) eintragen, dann neu einlesen.',
    spalten: ['AuftragsChargeManuell'],
  },
  ohne_gewicht: {
    name: 'Stück ohne Gewicht je Artikel', ebene: 'position', wo: 'perigon',
    heisst: 'Verkauft in Stück, aber ohne Gewicht je Stück — wie viel Kilo das sind, weiss niemand.',
    datei: 'Spalte T: Stück · Spalte AE (Gewicht je Artikel): leer oder 0.',
    app: 'Die Position zählt nicht; die App rät keine Kilo. Die Masse ist unbekannt, nie 0 (seit Stand 115).',
    tun: 'In Perigon das Gewicht je Artikel eintragen, dann neu einlesen.',
    spalten: ['GewichtProArtikel', 'AuftragsArtikelEinheit'],
  },
  ruecknahme: {
    name: 'Rücknahme (negative Menge)', ebene: 'position', wo: 'nichts',
    heisst: 'Die Position hat eine negative Menge — Ware kam zurück.',
    datei: 'Spalte Q negativ.',
    app: 'Sie wird als Rücknahme gebucht, nicht als Verkauf — und hier gemeldet, statt wegzufallen.',
    tun: 'Nichts in der App; prüfen, ob die Ware wirklich zurückkam.',
    spalten: ['AuftragsArtikelMenge'],
  },
  masse_abweichung: {
    name: 'Rechnung ≠ Datei', ebene: 'position', wo: 'einlesen',
    heisst: 'Was die App für diese Position an Lieferungen rechnet, ergibt nicht die Masse der Datei — eine Lieferung fehlt, ist doppelt oder wurde von Hand geändert.',
    datei: 'Spalte Q × Spalte AE gegen die Summe der Lieferungen in der App.',
    app: 'Gerechnet wird mit den Lieferungen der App, nicht mit der Datei — bis zum nächsten Einlesen.',
    tun: 'Die Datei unter Betrieb → Warenausgang neu einlesen: was fehlt, wird angelegt, was die Datei nicht mehr ergibt, entfernt.',
    spalten: ['AuftragsArtikelMenge', 'GewichtProArtikel'],
  },
  label_name: {
    name: 'Artikelname gegen Preisgruppe', ebene: 'position', wo: 'perigon',
    heisst: 'Im Namen des Artikels steht Demeter, die Preisgruppe ist Knospe — oder umgekehrt.',
    datei: 'Spalte I (Artikel) gegen Spalte K (Preisgruppe).',
    app: 'Die Preisgruppe gilt — fürs Label der Charge und fürs Lager nach Artikel.',
    tun: 'In Perigon Artikel oder Preisgruppe angleichen.',
    spalten: ['AuftragsArtikel', 'AuftragsPrsGrpBez'],
  },
  nachholen: {
    name: 'Nummer inzwischen bekannt', ebene: 'chargenzeile', wo: 'nichts',
    heisst: 'Die Nummer kannte die App beim Einlesen noch nicht; inzwischen steht sie an einer Charge.',
    datei: 'Spalte W.',
    app: 'Beim nächsten Rechnen bekommt der Lieferschein seine Charge von selbst (seit Stand 121) — ohne neues Einlesen.',
    tun: 'Nichts — „Neu rechnen" genügt.',
    spalten: ['AuftragsChargeManuell'],
  },
  mehrdeutig: {
    name: 'Perigon-Nr. an mehreren Chargen', ebene: 'chargenzeile', wo: 'stammdaten',
    heisst: 'Dieselbe Perigon-Nummer steht im Chargenregister an zwei oder mehr Chargen, und der Artikel sagt nicht, an welcher.',
    datei: 'Spalte W: eine sechsstellige Perigon-Nummer.',
    app: 'Die App rät nicht — der Lieferschein bleibt ohne Charge.',
    tun: 'Unter Betrieb → Stammdaten → Chargen die Nummer nur bei der richtigen Charge lassen.',
    spalten: ['AuftragsChargeManuell'],
  },
  unbekannt: {
    name: 'Nummer an keiner Charge', ebene: 'chargenzeile', wo: 'stammdaten',
    heisst: 'Die Nummer auf dem Lieferschein steht an keiner Charge der App — eine Perigon-Nr., die in der Liste fehlt, oder ein Tippfehler.',
    datei: 'Spalte W.',
    app: 'Der Lieferschein bleibt ohne Charge und wird auf alle Chargen der Sorte verteilt.',
    tun: 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; ist es ein Tippfehler, in Perigon berichtigen.',
    spalten: ['AuftragsChargeManuell'],
  },
  artikel_sorte: {
    name: 'Artikel passt nicht zur Charge', ebene: 'chargenzeile', wo: 'perigon',
    heisst: 'Verkauft wurde ein Artikel einer anderen Gruppe als die Sorte der Charge auf dem Lieferschein — etwa Mandarin aus einer Kaori-Kuri-Charge.',
    datei: 'Spalte I (Artikel) gegen Spalte W (Charge).',
    app: 'Die Ware wird von der genannten Charge abgezogen. Stimmt die Charge nicht, fehlt sie bei der richtigen; stimmt der Artikel nicht, stimmt das Lager nach Artikel nicht.',
    tun: 'Den Lieferschein ansehen und Artikel oder Charge in Perigon berichtigen.',
    spalten: ['AuftragsArtikel', 'AuftragsChargeManuell'],
  },
  demeter_knospe: {
    name: 'Demeter-Preis für Knospe-Ware', ebene: 'chargenzeile', wo: 'perigon',
    heisst: 'Verkauft in der Preisgruppe Demeter, aber die Ware der Charge trägt das Lieferlabel Knospe.',
    datei: 'Spalte K (Preisgruppe) D gegen Spalte Z (Lieferlabel) K.',
    app: 'Gezeigt, nicht verrechnet: am Lager ändert es nichts, an der Rückverfolgbarkeit schon.',
    tun: 'In Perigon Preisgruppe und Lieferlabel prüfen.',
    spalten: ['AuftragsPrsGrpBez', 'LiefPrsGrpName'],
  },
  mix: {
    name: 'Kürbis Mix auf einer Charge', ebene: 'chargenzeile', wo: 'firma',
    heisst: 'Ein „Mix" ist meist aus mehreren Sorten, Perigon bucht ihn aber auf eine einzige Charge.',
    datei: 'Spalte I: Mix · Spalte W: eine Nummer.',
    app: 'Die ganze Menge wird von dieser einen Charge abgezogen. Ist der Mix aus anderen Chargen, steht die genannte zu leer und die anderen zu voll.',
    tun: 'Bei der Firma fragen, woraus der Mix ist. Stimmt es so, hier „kein Fehler" vermerken.',
    spalten: ['AuftragsArtikel', 'AuftragsChargeManuell'],
  },
  vor_eingang: {
    name: 'Geliefert vor dem Eingang', ebene: 'chargenzeile', wo: 'perigon',
    heisst: 'Der Lieferschein ist älter als die erste Palette der Charge im Erntejournal — von ihr kann die Ware nicht sein.',
    datei: 'Spalte F (Lieferdatum) gegen das Eingangsdatum im Journal; Spalte W.',
    app: 'Die Ware wird trotzdem von der genannten Charge abgezogen und gemeldet — je Charge auch unter „Je Sorte".',
    tun: 'In Perigon die Charge berichtigen — oder im Erntejournal das Eingangsdatum, wenn es nicht stimmt.',
    spalten: ['AuftragsLieferDatum', 'AuftragsChargeManuell'],
  },
}

/** Die Folge der Arten, wie sie im Reiter stehen: was Ware ohne Charge lässt, dann Mengen, Nummern, Artikel. */
export const ART_FOLGE: PerigonArt[] = ['menge_null', 'keine_nummer', 'rest', 'zu_viel', 'unbekannt', 'mehrdeutig', 'nachholen',
  'vor_eingang', 'mix', 'artikel_sorte', 'label_name', 'demeter_knospe', 'ohne_gewicht', 'masse_abweichung', 'ruecknahme']

export const WO_NAME: Record<Wo, { kurz: string; lang: string }> = {
  perigon: { kurz: 'Perigon', lang: 'In Perigon berichtigen, dann die Datei neu einlesen' },
  stammdaten: { kurz: 'Stammdaten', lang: 'Im Chargenregister (Betrieb → Stammdaten → Chargen)' },
  einlesen: { kurz: 'Einlesen', lang: 'Die Datei neu einlesen (Betrieb → Warenausgang)' },
  firma: { kurz: 'Firma fragen', lang: 'Bei der Firma nachfragen' },
  halle: { kurz: 'Halle zählen', lang: 'In der Halle nachzählen' },
  journal: { kurz: 'Erntejournal', lang: 'Im Erntejournal nachsehen oder berichtigen' },
  nichts: { kurz: 'nichts', lang: 'Nichts — die App erledigt es beim nächsten Rechnen' },
}
export const WO_FOLGE: Wo[] = ['perigon', 'halle', 'journal', 'stammdaten', 'firma', 'einlesen', 'nichts']

/** Wo eine Sache je Charge behoben wird (v_ungereimtheit). */
export function sacheWo(u: Pick<Ungereimtheit, 'art'>): Wo {
  switch (u.art) {
    case 'ueberzaehlung': case 'vorschlag': return 'halle'
    case 'ohne_eingang': case 'vor_eingang': case 'umgebucht': return 'journal'
    case 'nachgeordnet': case 'stammdaten': return 'stammdaten'
    case 'ohne_charge': return 'perigon'
    default: return 'perigon'
  }
}

export const STAND_NAME: Record<VermerkStand, string> = {
  offen: 'offen', in_abklaerung: 'in Abklärung', erledigt: 'erledigt', kein_fehler: 'kein Fehler',
}
export const STAND_FOLGE: VermerkStand[] = ['offen', 'in_abklaerung', 'erledigt', 'kein_fehler']

/** Der Stand eines Falls: was zuletzt vermerkt ist, sonst offen. */
export function standVon(verlauf: Map<string, PerigonVerlauf>, schluessel: string): VermerkStand {
  return verlauf.get(schluessel)?.stand ?? 'offen'
}
/** Offen heisst: nicht nur Auskunft, und niemand hat „erledigt" oder „kein Fehler" vermerkt. */
export function istOffen(schwere: Schwere, stand: VermerkStand): boolean {
  return schwere !== 'info' && (stand === 'offen' || stand === 'in_abklaerung')
}
/** Die Kilo, um die es geht — eine Abweichung nach unten zählt wie eine nach oben. */
export const betroffen = (x: { kg: number | null }) => (x.kg == null ? null : Math.abs(Number(x.kg)))

const RANG: Record<Schwere, number> = { rot: 0, gelb: 1, info: 2 }
const summe = (xs: (number | null)[]) => (xs.some(x => x != null) ? xs.reduce<number>((a, x) => a + (x ?? 0), 0) : null)
const stueck = (k: number, ein: string, mehr: string) => `${k} ${k === 1 ? ein : mehr}`

/** Die Spalte einer Datei als Buchstabe (A … AF), wie Excel sie zeigt. */
export function spaltenZeichen(name: string): string | null {
  const i = PERIGON_ANSICHT.findIndex(s => s.name === name)
  return i < 0 ? null : spaltenBuchstabe(i)
}

/* ---------- Die Fälle je Art -------------------------------------------- */

export interface ArtGruppe {
  art: PerigonArt; info: PerigonArtInfo; faelle: PerigonBefund[]
  offen: number; kg: number | null; schwere: Schwere
}

/** Die Fälle je Art, das Schwerste und Grösste zuerst; innerhalb einer Art die grössten zuerst. */
export function nachArt(faelle: PerigonBefund[], verlauf: Map<string, PerigonVerlauf>): ArtGruppe[] {
  const m = new Map<PerigonArt, PerigonBefund[]>()
  for (const f of faelle) m.set(f.art, [...(m.get(f.art) ?? []), f])
  return [...m.entries()].map(([art, liste]) => {
    const schwere = liste.some(f => f.schwere === 'rot') ? 'rot' : liste.some(f => f.schwere === 'gelb') ? 'gelb' : 'info'
    return {
      art, info: PERIGON_ART[art], schwere: schwere as Schwere,
      faelle: [...liste].sort((a, b) => (betroffen(b) ?? -1) - (betroffen(a) ?? -1) || b.datum.localeCompare(a.datum)),
      offen: liste.filter(f => istOffen(f.schwere, standVon(verlauf, f.schluessel))).length,
      kg: summe(liste.map(betroffen)),
    }
  }).sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || (b.kg ?? 0) - (a.kg ?? 0) || ART_FOLGE.indexOf(a.art) - ART_FOLGE.indexOf(b.art))
}

export type StandFilter = 'offen' | 'abklaerung' | 'erledigt' | 'alle'
export interface Filter { art: string; quelle: string; stand: StandFilter; suche: string; sorte: string; charge: number | null }
export const FILTER_LEER: Filter = { art: '', quelle: '', stand: 'offen', suche: '', sorte: '', charge: null }

/** Die Fälle, die zum Filter passen. Die Suche geht über Artikel, Kunde, Nummern, Charge, Position und Sorte. */
export function filtern(faelle: PerigonBefund[], verlauf: Map<string, PerigonVerlauf>, f: Filter): PerigonBefund[] {
  const s = f.suche.trim().toLowerCase()
  return faelle.filter(x => {
    if (f.art && x.art !== f.art) return false
    if (f.quelle && x.quelle !== f.quelle) return false
    if (f.sorte && x.sorte !== f.sorte) return false
    if (f.charge != null && x.charge_nr !== f.charge && !(x.nummern ?? '').split(', ').includes(String(f.charge))) return false
    const st = standVon(verlauf, x.schluessel)
    if (f.stand === 'offen' && !istOffen(x.schwere, st)) return false
    if (f.stand === 'abklaerung' && st !== 'in_abklaerung') return false
    if (f.stand === 'erledigt' && st !== 'erledigt' && st !== 'kein_fehler') return false
    if (!s) return true
    return [x.artikel, x.kunde, x.nummern, x.charge_nr, x.pos_id, x.sorte, x.quelle].some(v => v != null && String(v).toLowerCase().includes(s))
  })
}

/* ---------- Fall für Fall, je Sorte ------------------------------------- */

export interface SorteFall {
  sorte: string
  /** alle Chargen der Sorte mit Eingang oder Lieferschein — der Weg der Ware */
  chargen: ChargeSpur[]
  sachen: Ungereimtheit[]
  zeilen: PerigonBefund[]
  schwere: Schwere
  kg: number
  /** was in der Sorte nicht passt, in kurzen Sätzen — das Bild über alle Chargen */
  bild: string[]
  /** Chargen mit Eingang, aber nie einem Lieferschein */
  nieGeliefert: number[]
  /** Perigon-Nummern derselben Sorte, die aufeinander folgen — nur, wo die Sorte nicht aufgeht */
  aehnlich: string[]
}

/**
 * Zwei Perigon-Nummern, die man leicht verwechselt: aufeinanderfolgend
 * (198969 und 198970 — so stehen 1630 und 1628 in der Liste). Die Nummern der
 * Planungsliste sind fortlaufend; „eine Stelle anders" träfe fast jedes Paar
 * und sagte nichts mehr.
 */
export function aehnlicheNummer(a: number, b: number): boolean {
  return Math.abs(a - b) === 1
}

/**
 * Je Sorte, in der etwas nicht passt, alle ihre Chargen mit dem Weg der Ware —
 * wie im Bericht vom 23. Oktober („Kaori Kuri: verkauft wird unter wenigen
 * Nummern, drei Chargen haben nie einen Lieferschein"). Das Bild über die
 * ganze Sorte zeigt, was eine Charge allein nicht zeigt: wo zu viel
 * hinausgeht und wo nie etwas hinausging.
 */
export function jeSorte(spur: ChargeSpur[], sachen: Ungereimtheit[], faelle: PerigonBefund[],
                        chargen: { nr: number; sorte: string; perigon_nr: number | null }[]): SorteFall[] {
  const sorteVonCharge = new Map(spur.map(s => [s.charge_nr, s.sorte]))
  const sorten = new Set<string>()
  const sorteDerSache = (u: Ungereimtheit) => u.sorte ?? (u.charge_nr != null ? sorteVonCharge.get(u.charge_nr) ?? null : null)
  for (const u of sachen) { const s = sorteDerSache(u); if (s && u.schwere !== 'info') sorten.add(s) }
  for (const f of faelle) if (f.sorte && f.schwere !== 'info') sorten.add(f.sorte)
  const out: SorteFall[] = []
  for (const sorte of sorten) {
    const ch = spur.filter(s => s.sorte === sorte && (s.journal_paletten > 0 || s.paletten > 0 || s.lieferscheine > 0))
      .sort((a, b) => a.charge_nr - b.charge_nr)
    const su = sachen.filter(u => sorteDerSache(u) === sorte)
    const ze = faelle.filter(f => f.sorte === sorte)
    const ernst = [...su.filter(u => u.schwere !== 'info'), ...ze.filter(f => f.schwere !== 'info')]
    const schwere: Schwere = ernst.some(x => x.schwere === 'rot') ? 'rot' : ernst.length ? 'gelb' : 'info'
    const ueber = su.filter(u => u.art === 'ueberzaehlung')
    const ohneEin = su.filter(u => u.art === 'ohne_eingang')
    const vor = su.filter(u => u.art === 'vor_eingang')
    const ohne = su.filter(u => u.art === 'ohne_charge')
    const nie = ch.filter(s => s.journal_paletten > 0 && s.lieferscheine === 0)
    const bild: string[] = []
    if (ueber.length) bild.push(`${stueck(ueber.length, 'Charge verkauft', 'Chargen verkaufen')} mehr, als sie hergeben kann (${ueber.map(u => `${u.charge_nr} ${tonnen(u.kg)}`).join(', ')}).`)
    if (ohneEin.length) bild.push(`${stueck(ohneEin.length, 'Charge hat', 'Chargen haben')} verkauft, ohne je eine Palette zu bekommen (${ohneEin.map(u => u.charge_nr).join(', ')}).`)
    if (vor.length) bild.push(`${stueck(vor.length, 'Charge hat', 'Chargen haben')} verkauft, bevor sie eingegangen war (${vor.map(u => `${u.charge_nr} ${tonnen(u.kg)}`).join(', ')}).`)
    if (nie.length && (ueber.length || ohneEin.length || vor.length)) {
      const pal = nie.reduce((a, s) => a + Math.max(0, Math.round(Number(s.rest_paletten ?? s.paletten))), 0)
      bild.push(`${stueck(nie.length, 'Charge hat', 'Chargen haben')} Eingang, aber noch nie einen Lieferschein (${nie.map(s => s.charge_nr).join(', ')}; laut App ≈ ${stueck(pal, 'Palette', 'Paletten')}) — von dort kam die Ware wohl.`)
    }
    if (ohne.length) bild.push(`${tonnen(summe(ohne.map(u => u.kg)))} gingen ohne Charge hinaus und sind auf alle Chargen der Sorte verteilt.`)
    const zeErnst = ze.filter(f => f.schwere !== 'info')
    if (zeErnst.length) bild.push(`${stueck(zeErnst.length, 'Perigon-Zeile stimmt', 'Perigon-Zeilen stimmen')} nicht (${[...new Set(zeErnst.map(f => PERIGON_ART[f.art].name))].join(', ')}).`)
    const umg = su.filter(u => u.art === 'umgebucht' || u.art === 'vorschlag')
    if (umg.length) bild.push(umg.map(u => u.art === 'umgebucht' ? `Umgebucht mit Beleg: ${u.titel}.` : `Vorschlag, nicht gebucht: ${u.titel}.`).join(' '))
    // Nur wo die Sorte nicht aufgeht, ist eine verwechselbare Nummer eine Erklärung — sonst ist sie bloss da.
    const mitNr = ueber.length || ohneEin.length || vor.length ? chargen.filter(c => c.sorte === sorte && c.perigon_nr != null) : []
    const aehnlich: string[] = []
    for (let i = 0; i < mitNr.length; i++) for (let j = i + 1; j < mitNr.length; j++) {
      const a = mitNr[i], b = mitNr[j]
      if (aehnlicheNummer(a.perigon_nr!, b.perigon_nr!))
        aehnlich.push(`Die Perigon-Nummern von ${a.nr} (${a.perigon_nr}) und ${b.nr} (${b.perigon_nr}) folgen aufeinander — eine Ziffer daneben, und die Ware steht auf der falschen Charge.`)
    }
    out.push({ sorte, chargen: ch, sachen: su, zeilen: ze, schwere, kg: summe(ernst.map(betroffen)) ?? 0, bild, nieGeliefert: nie.map(s => s.charge_nr), aehnlich })
  }
  return out.sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || b.kg - a.kg)
}

/* ---------- Was zu tun ist ---------------------------------------------- */

export interface Eintrag {
  schluessel: string; titel: string; kg: number | null; schwere: Schwere
  /** ein Perigon-Fall (öffnet die Zeile der Datei) oder eine Sache je Charge (öffnet die Sorte) */
  fall?: PerigonBefund; sache?: Ungereimtheit
}
export interface Aufgabe { wo: Wo; eintraege: Eintrag[]; kg: number | null }

/** Ein Perigon-Fall als Zeile einer Liste: Datum, Artikel, Nummern, Art. */
export function fallTitel(f: PerigonBefund): string {
  return `${datum(f.datum)} · ${f.artikel}${f.nummern ? ` · ${f.nummern}` : ''} — ${PERIGON_ART[f.art].name}`
}

/** Alles Offene, nach dem Ort, an dem es behoben wird; je Ort das Grösste zuerst. */
export function aufgaben(faelle: PerigonBefund[], sachen: Ungereimtheit[], verlauf: Map<string, PerigonVerlauf>): Aufgabe[] {
  const m = new Map<Wo, Eintrag[]>()
  const dazu = (wo: Wo, e: Eintrag) => m.set(wo, [...(m.get(wo) ?? []), e])
  for (const f of faelle) {
    if (!istOffen(f.schwere, standVon(verlauf, f.schluessel))) continue
    dazu(f.wo, { schluessel: f.schluessel, titel: fallTitel(f), kg: betroffen(f), schwere: f.schwere, fall: f })
  }
  for (const u of sachen) {
    if (!istOffen(u.schwere, standVon(verlauf, u.schluessel))) continue
    dazu(sacheWo(u), { schluessel: u.schluessel, titel: u.titel, kg: u.kg, schwere: u.schwere, sache: u })
  }
  return WO_FOLGE.filter(w => m.has(w)).map(wo => {
    const e = m.get(wo)!.sort((a, b) => RANG[a.schwere] - RANG[b.schwere] || (b.kg ?? -1) - (a.kg ?? -1))
    return { wo, eintraege: e, kg: summe(e.map(x => x.kg)) }
  })
}

/* ---------- Die Lage in Zahlen ------------------------------------------ */

export interface Lage {
  hereinKg: number | null; hereinPaletten: number; chargenMitEingang: number
  hinausKg: number | null; lieferscheine: number; chargenMitLieferschein: number
  ohneChargeKg: number | null; nochPaletten: number | null
}

/** Herein laut Erntejournal, hinaus laut Perigon, ohne Charge, laut App noch da — über alle Chargen. */
export function lageInZahlen(spur: ChargeSpur[], sachen: Ungereimtheit[]): Lage {
  const mitEingang = spur.filter(s => s.journal_paletten > 0)
  const mitLief = spur.filter(s => s.lieferscheine > 0)
  const rest = spur.map(s => (s.rest_paletten == null ? null : Math.max(0, Number(s.rest_paletten))))
  return {
    hereinKg: summe(mitEingang.map(s => (s.journal_kg == null ? null : Number(s.journal_kg)))),
    hereinPaletten: mitEingang.reduce((a, s) => a + s.journal_paletten, 0), chargenMitEingang: mitEingang.length,
    hinausKg: summe(mitLief.map(s => (s.geliefert_kg == null ? null : Number(s.geliefert_kg)))),
    lieferscheine: mitLief.reduce((a, s) => a + s.lieferscheine, 0), chargenMitLieferschein: mitLief.length,
    ohneChargeKg: summe(sachen.filter(u => u.art === 'ohne_charge').map(u => u.kg)),
    nochPaletten: rest.some(r => r != null) ? Math.round(rest.reduce<number>((a, r) => a + (r ?? 0), 0)) : null,
  }
}

/** Der Fall in einem Satz für die Spur (schnappschuss) — was er war, falls er später verschwindet. */
export function schnappschuss(f: PerigonBefund): Record<string, unknown> {
  return { art: f.art, quelle: f.quelle, pos_id: f.pos_id, datum: f.datum, artikel: f.artikel, nummern: f.nummern, charge_nr: f.charge_nr,
           sorte: f.sorte, kg: f.kg, satz: f.satz }
}
export function sacheSchnappschuss(u: Ungereimtheit): Record<string, unknown> {
  return { art: u.art, charge_nr: u.charge_nr, sorte: u.sorte, kg: u.kg, titel: u.titel }
}

/** Was ein verschwundener oder vermerkter Fall war, aus dem Schnappschuss — für den Verlauf. */
export function schnappschussText(s: Record<string, unknown> | null | undefined): string {
  if (!s) return ''
  const art = typeof s.art === 'string' ? s.art : ''
  const name = (PERIGON_ART as Record<string, PerigonArtInfo | undefined>)[art]?.name
  if (typeof s.titel === 'string') return s.titel
  const teile = [typeof s.datum === 'string' ? datum(s.datum) : null, typeof s.artikel === 'string' ? s.artikel : null,
                 typeof s.nummern === 'string' ? s.nummern : null, s.kg != null ? kg(Number(s.kg), 0) : null].filter(Boolean)
  return `${name ?? art}${teile.length ? ` — ${teile.join(' · ')}` : ''}`
}
