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

/* ---------- Runde BD: ein Fall, ruhig erzählt ---------------------------- */
// Der Betrieb, 24. Oktober, zum Reiter: „an sich in die richtige Richtung —
// aber er überfordert gerade noch." Und zu einem Fall: „das versteh ich nicht —
// wie kommst du auf 768?" Die Antwort stand nirgends: 768 sind drei gleiche
// Zeilen à 256 kg. Hier steht, was die Liste in einer Zeile und das Fenster
// Schritt für Schritt zeigt.

const NAME_DEMETER = /(demeter|\bdem\b)/i
const NAME_KNOSPE = /knospe/i
/** Das Label, das der Artikelname nennt — oder keines. */
export const labelImNamen = (artikel: string | null): string | null =>
  !artikel ? null : NAME_DEMETER.test(artikel) ? 'Demeter' : NAME_KNOSPE.test(artikel) ? 'Knospe' : null
/** Das Label einer Preisgruppe oder eines Lieferlabels: D… Demeter, K… und CH-K Knospe (wie 0113). */
export const labelDerGruppe = (g: string | null): string | null =>
  !g ? null : /^d/i.test(g.trim()) ? 'Demeter' : /^(k|ch-k)/i.test(g.trim()) ? 'Knospe' : null

const kgOder = (x: number | null | undefined) => (x == null ? 'unbekannt' : kg(Number(x), 0))

/**
 * Was an einem Fall nicht passt, in wenigen Worten — die Liste zeigt es unter
 * der Charge. Die Art steht schon über der Liste; hier nur die Zahl oder die
 * Angabe, an der man den Fall wiedererkennt.
 */
export function fallKurz(f: PerigonBefund): string {
  const e = (f.einheit ?? '').trim() || 'Stück'
  switch (f.art) {
    case 'menge_null': return 'Spalte S = 0'
    case 'zu_viel': case 'rest': return `${kgOder(f.kg_zugeteilt)} statt ${kgOder(f.kg_position)}`
    case 'keine_nummer': return 'Spalte W leer'
    case 'ohne_gewicht': return `${f.menge == null ? '?' : Number(f.menge).toLocaleString('de-CH')} ${e}, kein Gewicht`
    case 'ruecknahme': return `${f.menge == null ? '?' : Number(f.menge).toLocaleString('de-CH')} ${e}`
    case 'masse_abweichung': return `App ${kgOder(f.kg_rechnung)}, Datei ${kgOder(f.kg_position)}`
    case 'label_name': return `Name ${labelImNamen(f.artikel) ?? '?'}, Preisgruppe ${f.preisgruppe ?? '?'}`
    case 'demeter_knospe': return `Preisgruppe ${f.preisgruppe ?? '?'}, Lieferlabel ${f.liefer_label ?? '?'}`
    case 'nachholen': return f.charge_nr != null ? `jetzt bei ${f.charge_nr}` : 'jetzt bekannt'
    case 'unbekannt': return 'an keiner Charge'
    case 'mehrdeutig': return 'an mehreren Chargen'
    case 'artikel_sorte': return f.sorte ? `die Charge ist ${f.sorte}` : 'andere Sorte'
    case 'mix': return 'ganz auf eine Charge'
    case 'vor_eingang': {
      const t = /\((\d+) Tage? später\)/.exec(f.satz)
      return t ? `${t[1]} ${t[1] === '1' ? 'Tag' : 'Tage'} vor dem Eingang` : 'vor dem Eingang'
    }
  }
}

/** Die Arten, bei denen sich eine Menge nachrechnen lässt — aus den Zeilen der Position. */
export const MENGEN_ARTEN = new Set<PerigonArt>(['menge_null', 'zu_viel', 'rest', 'keine_nummer', 'ohne_gewicht', 'ruecknahme', 'masse_abweichung'])

/** Eine Zeile der Datei, so weit das Nachrechnen sie braucht (ausgang_zeile). */
export interface DateiZeile { charge_extern: string | null; batch_menge: number | null; kg_charge: number | null }
export interface RechenZeile {
  nr: number; charge: string | null
  /** Spalte S, in der Einheit der Position */
  s: number | null
  /** Spalte S in kg — bei Stück mit dem Gewicht je Artikel; leer heisst unbekannt */
  kg: number | null
  /** dieselbe Charge mit derselben Menge stand schon in Zeile … */
  gleichWie: number | null
}
export interface Nachrechnung {
  einheit: string; istKg: boolean
  zeilen: RechenZeile[]
  /** Spalte S über alle Zeilen, in kg */
  zugeteiltKg: number | null
  /** die Position: Q (× AE) */
  positionKg: number | null
  /** was nicht aufgeht — mit dem Wort dazu („zu viel", „ohne Charge" …) */
  unterschied: { kg: number | null; wort: string } | null
  rechnungKg: number | null
  satz: string
}

/**
 * Die Zeilen einer Position nachgerechnet, wie man es mit der Datei in der
 * Hand täte: jede Zeile mit ihrer Charge (Spalte W) und ihrer Menge (Spalte S),
 * die Summe, die Position (Spalte Q), der Unterschied. Die Summen kommen aus
 * der Datenbank (v_perigon_befund) — die Zeilen zeigen, woraus sie bestehen.
 */
export function nachrechnen(f: PerigonBefund, dateiZeilen: DateiZeile[]): Nachrechnung | null {
  if (!MENGEN_ARTEN.has(f.art)) return null
  const einheit = (f.einheit ?? '').trim() || 'Stück'
  const istKg = /^kg/i.test(einheit)
  const gja = f.gewicht_je_artikel == null ? null : Number(f.gewicht_je_artikel)
  const zuKg = (m: number | null) => (m == null ? null : gja != null && gja > 0 ? Math.round(m * gja * 1000) / 1000 : istKg ? m : null)
  const zeilen: RechenZeile[] = dateiZeilen.map((z, i) => {
    const charge = z.charge_extern?.trim() || null
    const s = z.batch_menge == null ? null : Number(z.batch_menge)
    const vorher = dateiZeilen.findIndex((y, j) => j < i && (y.charge_extern?.trim() || null) === charge && Number(y.batch_menge) === s)
    return { nr: i + 1, charge, s, kg: z.kg_charge != null ? Number(z.kg_charge) : zuKg(s), gleichWie: vorher < 0 ? null : vorher + 1 }
  })
  const zug = f.kg_zugeteilt != null ? Number(f.kg_zugeteilt)
    : zeilen.length && zeilen.every(z => z.kg != null) ? zeilen.reduce((a, z) => a + (z.kg ?? 0), 0) : null
  const pos = f.kg_position == null ? null : Number(f.kg_position)
  const rech = f.kg_rechnung == null ? null : Number(f.kg_rechnung)
  const diff = (a: number | null, b: number | null) => (a == null || b == null ? null : Math.round((a - b) * 1000) / 1000)
  const chargen = [...new Set(zeilen.map(z => z.charge).filter((c): c is string => !!c))]
  const n = zeilen.length
  const alleGleich = n > 1 && zeilen.every(z => z.gleichWie === 1 || z.nr === 1)
  let unterschied: Nachrechnung['unterschied'] = null
  let satz = f.satz
  switch (f.art) {
    // Runde BG — der Betrieb: „Chargenzeile mehr als die Position checke ich noch immer nicht … Zeile 1, 2, 3
    // und dann gleich wie Zeile 1, aber ich weiss nicht, was du meinst." Der Satz fängt darum beim Lieferschein
    // an (was geliefert wurde) und sagt dann, was Perigon den Chargen zuteilt — nicht „die Position steht 3-mal da".
    case 'zu_viel': {
      unterschied = { kg: diff(zug, pos), wort: 'zu viel' }
      const mehr = diff(zug, pos)
      if (alleGleich) satz = `Auf dem Lieferschein stehen ${kgOder(pos)}. Perigon schreibt dazu ${n}-mal dieselbe Charge ${zeilen[0].charge ?? '—'} mit ${kgOder(zeilen[0].kg)} — zusammen ${kgOder(zug)}, ${kgOder(mehr)} mehr als geliefert.`
      else if (n === 1) satz = `Auf dem Lieferschein stehen ${kgOder(pos)}. Perigon teilt der Charge ${zeilen[0].charge ?? '—'} aber ${kgOder(zug)} zu — ${kgOder(mehr)} mehr als geliefert.`
      else if (n > 0) satz = `Auf dem Lieferschein stehen ${kgOder(pos)}. Perigon teilt den ${n} Chargenzeilen zusammen ${kgOder(zug)} zu — ${kgOder(mehr)} mehr als geliefert.`
      break
    }
    case 'rest': {
      unterschied = { kg: diff(pos, zug), wort: 'ohne Charge' }
      const fehlt = diff(pos, zug)
      if (n === 1) satz = `Auf dem Lieferschein stehen ${kgOder(pos)}. Perigon teilt der Charge ${zeilen[0].charge ?? '—'} nur ${kgOder(zug)} zu — für ${kgOder(fehlt)} steht keine Charge.`
      else if (n > 0) satz = `Auf dem Lieferschein stehen ${kgOder(pos)}. Perigon teilt den ${n} Chargenzeilen zusammen nur ${kgOder(zug)} zu — für ${kgOder(fehlt)} steht keine Charge.`
      break
    }
    case 'menge_null':
      unterschied = { kg: pos, wort: 'ohne Charge' }
      if (n > 0) satz = `Die Datei nennt ${chargen.length ? `${chargen.length === 1 ? 'die Charge' : 'die Chargen'} ${chargen.join(', ')}` : 'Chargen'}, aber in Spalte S steht überall 0. ${pos != null && pos !== 0 ? `Die ${kgOder(pos)} der Position haben darum keine Charge.` : 'Die Position hat auch keine Menge — sie zählt nirgends.'}`
      break
    case 'keine_nummer':
      unterschied = { kg: pos, wort: 'ohne Charge' }
      satz = `In keiner Zeile steht eine Charge (Spalte W leer). Die ${kgOder(pos)} der Position haben darum keine Charge.`
      break
    case 'ohne_gewicht':
      unterschied = { kg: null, wort: 'Masse unbekannt' }
      satz = `${f.menge == null ? 'Eine Menge' : `${Number(f.menge).toLocaleString('de-CH')} ${einheit}`}, aber ohne Gewicht je ${einheit} (Spalte AE) — wie viel Kilo das sind, weiss niemand. Die App zählt die Position nicht, statt Kilo zu raten.`
      break
    case 'ruecknahme':
      unterschied = { kg: pos, wort: 'zurück' }
      satz = `Die Menge ist negativ: ${f.menge == null ? '?' : Number(f.menge).toLocaleString('de-CH')} ${einheit} — Ware kam zurück. Die App bucht sie als Rücknahme, nicht als Verkauf.`
      break
    case 'masse_abweichung': {
      const d = diff(rech, pos)
      unterschied = { kg: d == null ? null : Math.abs(d), wort: d != null && d > 0 ? 'in der App mehr' : 'in der App weniger' }
      satz = `Die Datei ergibt für diese Position ${kgOder(pos)}, in der Rechnung der App stehen ${kgOder(rech)}. Neu einlesen gleicht es an.`
      break
    }
  }
  return { einheit, istKg, zeilen, zugeteiltKg: zug, positionKg: pos, unterschied, rechnungKg: rech, satz }
}

/** Runde BG: eine Chargenzeile im Bild „Lieferschein und Chargen". */
export interface ZuteilungsZeile extends RechenZeile {
  /** wo der Balken der Zeile anfängt — die Zeilen davor zusammen, in kg (das Bild stapelt sie wie im Excel untereinander) */
  ab: number | null
  /** was davon innerhalb der gelieferten Menge liegt */
  innen: number | null
  /** was darüber hinausgeht — mehr, als geliefert wurde */
  drueber: number | null
}
export type ZuteilungsMuster = 'gleich' | 'teils_gleich' | 'eine' | 'mehrere' | 'rest' | 'ohne_menge' | 'ohne_nummer' | 'sonst'
export interface Zuteilung {
  zeilen: ZuteilungsZeile[]
  /** die gemeinsame Skala der Balken: das Grössere von geliefert und zugeteilt; leer, wo beides unbekannt ist */
  skala: number | null
  muster: ZuteilungsMuster
  /** woran es wohl liegt — eine Vermutung in Worten; leer, wo die Datei nichts nahelegt */
  woran: string | null
}

/**
 * Runde BG — der Betrieb: „Chargenzeile mehr als die Position checke ich noch
 * immer nicht … hier sprichst du gegen eine Wand." Das Bild dazu: oben, was
 * auf dem Lieferschein steht (Spalte Q), darunter jede Chargenzeile als
 * Balken, der dort anfängt, wo die Zeile davor aufhört — so sieht man, wie
 * weit die Zeilen zusammen über die gelieferte Menge hinausgehen. Gerechnet
 * wird hier nichts Neues: die Zeilen und Summen sind die der Nachrechnung.
 * Dazu, woran es wohl liegt — aus dem, was die Datei selbst zeigt: gleiche
 * Zeilen, eine einzige Zeile mit gleichen Gebinden, mehrere Chargen.
 */
export function zuteilung(r: Nachrechnung, art: PerigonArt, gebinde: { position: number | null; zeile: number | null } | null = null): Zuteilung {
  const pos = r.positionKg
  let bisher: number | null = 0
  const zeilen: ZuteilungsZeile[] = r.zeilen.map(z => {
    const ab = bisher
    if (z.kg == null || ab == null) { bisher = null; return { ...z, ab: null, innen: null, drueber: null } }
    bisher = ab + z.kg
    if (pos == null) return { ...z, ab, innen: z.kg, drueber: 0 }
    const innen = Math.max(0, Math.min(ab + z.kg, pos) - ab)
    return { ...z, ab, innen, drueber: Math.round((z.kg - innen) * 1000) / 1000 }
  })
  const werte = [pos, r.zugeteiltKg].filter((x): x is number => x != null)
  const skala = werte.length ? Math.max(...werte) : null
  const n = zeilen.length
  const wiederholt = zeilen.filter(z => z.gleichWie != null).length
  const muster: ZuteilungsMuster =
    art === 'rest' ? 'rest' : art === 'menge_null' ? 'ohne_menge' : art === 'keine_nummer' ? 'ohne_nummer'
    : art !== 'zu_viel' || n === 0 ? 'sonst'
    : n === 1 ? 'eine'
    : wiederholt === n - 1 && zeilen.every(z => z.gleichWie == null || z.gleichWie === 1) ? 'gleich'
    : wiederholt > 0 ? 'teils_gleich' : 'mehrere'
  let woran: string | null = null
  switch (muster) {
    case 'gleich':
      woran = `Die ${n} Zeilen sind gleich — dieselbe Charge, dieselbe Menge. Geliefert wurde einmal: Perigon hat dieselbe Zuteilung ${n}-mal in die Datei geschrieben, oder sie wurde ${n}-mal erfasst.`
      break
    case 'teils_gleich':
      woran = `${wiederholt === 1 ? 'Eine Zeile wiederholt' : `${wiederholt} Zeilen wiederholen`} eine Zeile davor — dieselbe Charge, dieselbe Menge. Das sieht nach einer doppelt geschriebenen Zuteilung aus.`
      break
    case 'eine': {
      woran = 'Es ist eine einzige Charge, ihr ist aber mehr zugeteilt, als geliefert wurde.'
      const gp = gebinde?.position ?? null, gz = gebinde?.zeile ?? null
      if (gp != null && gz != null && gp > 0)
        woran += gp === gz
          ? ` Die Zahl der Gebinde stimmt überein (${gp.toLocaleString('de-CH')} auf dem Lieferschein und bei der Charge) — wohl wurde nachträglich nur das Gewicht der Position geändert (etwa nach dem Wägen), die Zuteilung zur Charge aber nicht.`
          : ` Auch die Gebinde weichen ab: ${gp.toLocaleString('de-CH')} auf dem Lieferschein, ${gz.toLocaleString('de-CH')} bei der Charge.`
      break
    }
    case 'mehrere':
      woran = 'Mehrere Chargen zusammen ergeben mehr, als geliefert wurde. Welche Charge wirklich wie viel gab, sagt die Datei nicht.'
      break
    case 'rest':
      woran = 'Perigon hat nur einen Teil der Lieferung einer Charge zugeteilt; für den Rest steht keine Charge.'
      break
    case 'ohne_menge':
      woran = 'Perigon nennt die Charge, teilt ihr aber nichts zu (Spalte S = 0).'
      break
    case 'ohne_nummer':
      woran = 'In keiner Zeile steht eine Charge (Spalte W leer).'
      break
  }
  return { zeilen, skala, muster, woran }
}

/** Eine Angabe der Datei — mit der Spalte, in der sie steht, und was sie heisst. */
export interface Angabe { was: string; spalte: string | null; wert: string; heisst: string | null }

/**
 * Was die Datei sagt, wo nichts zu rechnen ist: zwei Angaben, die einander
 * widersprechen — Artikel gegen Preisgruppe, Preisgruppe gegen Lieferlabel,
 * Artikel gegen Charge, Lieferdatum gegen Charge, die Nummer gegen das
 * Chargenregister.
 */
export function gegenueber(f: PerigonBefund): Angabe[] | null {
  const sp = (name: string) => spaltenZeichen(name)
  const artikel: Angabe = { was: 'Artikel', spalte: sp('AuftragsArtikel'), wert: f.artikel, heisst: null }
  const nummer = (heisst: string | null): Angabe => ({ was: 'Charge', spalte: sp('AuftragsChargeManuell'), wert: f.nummer ?? f.nummern ?? 'leer', heisst })
  const charge = f.charge_nr != null ? `Charge ${f.charge_nr}${f.sorte ? ` · ${f.sorte}` : ''}` : null
  switch (f.art) {
    case 'label_name': return [
      { ...artikel, heisst: labelImNamen(f.artikel) ? `im Namen ${labelImNamen(f.artikel)}` : null },
      { was: 'Preisgruppe', spalte: sp('AuftragsPrsGrpBez'), wert: f.preisgruppe ?? 'leer', heisst: labelDerGruppe(f.preisgruppe) },
    ]
    case 'demeter_knospe': return [
      { was: 'Preisgruppe', spalte: sp('AuftragsPrsGrpBez'), wert: f.preisgruppe ?? 'leer', heisst: labelDerGruppe(f.preisgruppe) ? `verkauft als ${labelDerGruppe(f.preisgruppe)}` : null },
      { was: 'Lieferlabel', spalte: sp('LiefPrsGrpName'), wert: f.liefer_label ?? 'leer', heisst: labelDerGruppe(f.liefer_label) ? `geliefert als ${labelDerGruppe(f.liefer_label)}` : null },
    ]
    case 'artikel_sorte': case 'mix': return [artikel, nummer(charge)]
    case 'vor_eingang': return [{ was: 'Lieferdatum', spalte: sp('AuftragsLieferDatum'), wert: datum(f.datum), heisst: null }, nummer(charge)]
    case 'unbekannt': return [nummer('steht an keiner Charge im Chargenregister')]
    case 'mehrdeutig': return [nummer('steht an mehreren Chargen im Chargenregister')]
    case 'nachholen': return [nummer(charge ? `inzwischen bei ${charge}` : 'inzwischen bekannt')]
    default: return null
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
