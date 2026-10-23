/**
 * Lagermanagement nach Artikel — die reinen Regeln, ohne React (Runde AQ aus
 * src/pages/Artikel.tsx gezogen, damit test/artikel.test.ts sie prüfen kann).
 *
 * Ein Artikel ist Artikelgruppe × Grösse × Label. Die Wahl oben auf der Seite
 * (Artikel, klein/gross/beide, Demeter/Knospe/beide) filtert; die Übersicht
 * „Wie viel ist von welchem Artikel noch da?" zählt je Gruppe × Label die
 * Chargen zusammen: Eingang, ausgelagert (Eingangsware hinter den
 * Lieferungen), geliefert, im Lager und verkaufsfähig — dazu das
 * Verkaufsfähige nach Grösse (artikel_lager_charge) und, seit Runde AS, der
 * Rest des Lagers so geteilt wie im Lagermanagement nach Charge.
 */
import type { ArtikelLagerCharge, Bestand, ChargeLabel, SorteGruppe } from './daten'

export const GRUPPEN_FOLGE = ['Knirps', 'Butternut', 'Butterkin/Muskat', 'Kabocha', 'Mandarin', 'Mix', 'andere']
/** Die Reihenfolge der Artikelgruppen, wie der Verkauf sie nennt; Unbekanntes zuletzt. */
export const rang = (g: string | null) => { const i = g === null ? -1 : GRUPPEN_FOLGE.indexOf(g); return i < 0 ? 99 : i }

export type GroesseWahl = 'beide' | 'klein' | 'gross'
export type LabelWahl = 'beide' | 'D' | 'K'
export interface Wahl { gruppe: string; groesse: GroesseWahl; label: LabelWahl }
export const OFFEN: Wahl = { gruppe: '', groesse: 'beide', label: 'beide' }

/**
 * Die Grösse einer Lagerzeile, wie der Verkauf sie kennt: klein und gross
 * nach den Kalibern des Artikels, Mandarin je Stück; was in kein Kaliber
 * passt, ist „ausserhalb" (lose verkäuflich); ohne Sortier-CSV „ohne Grösse".
 */
export type Klasse = 'klein' | 'gross' | 'stueck' | 'unique' | 'ausserhalb' | 'ohne'
export const KLASSEN: Klasse[] = ['klein', 'gross', 'stueck', 'unique', 'ausserhalb', 'ohne']
/**
 * 0121: Was als Artikel verkauft wird — alles ausser „passt in keinen Artikel"
 * (ausserhalb): Das ist verkaufsfähig nach der Sortiermaschine, liegt aber
 * zwischen oder ausserhalb der Kaliber der Artikel und geht nur lose. Unique
 * (Hagelware) ist ein eigener Artikel, nur Knospe — der Betrieb: „wie nicht
 * gross oder klein, eine dritte Kategorie: gross, klein, unique".
 */
export const ARTIKEL_KLASSEN: Klasse[] = KLASSEN.filter(k => k !== 'ausserhalb')
export const klasseVon = (g: string): Klasse =>
  g === 'klein' || g === 'gross' || g === 'stueck' ? g : g === 'ohne Verteilung' ? 'ohne' : 'ausserhalb'

/**
 * 0123: Ein Teil des Verkaufsfähigen, wie viel davon als Artikel bezahlt wird —
 * ohne die Überfüllung in den Kisten (a = zu viel ÷ Soll der Charge, aus dem
 * Lager-Ausweis). Was in keinen Artikel passt und Unique bleiben, wie sie sind.
 * `offen`: die Überfüllung ist nicht gewogen oder die Grösse offen — dann ist
 * die Zahl höchstens so gross.
 */
export function alsArtikel(t: ArtikelLagerCharge, rest?: Map<number, RestTeile>): { kg: number; ueberfuellung: number; offen: boolean } {
  const kl = klasseVon(t.groesse)
  const kg = Number(t.kg)
  if (kl === 'ausserhalb' || kl === 'unique') return { kg, ueberfuellung: 0, offen: false }
  const a = rest?.get(t.charge_nr)?.marge
  const netto = a != null ? kg / (1 + a) : kg
  return { kg: netto, ueberfuellung: kg - netto, offen: a === null || kl === 'ohne' }
}

export const passtGruppe = (w: Wahl, g: string | null) => w.gruppe === '' || g === w.gruppe
export const passtLabel = (w: Wahl, l: string | null) => w.label === 'beide' || l === w.label
export const passtKlasse = (w: Wahl, k: Klasse) => w.groesse === 'beide' || k === w.groesse

/**
 * Was von der liegenden Eingangsmasse einer Charge nicht verkaufsfähig ist —
 * so geteilt, wie die Kaskade es tut (erg_prognose, h = 0): zu klein / zu
 * gross, faul (in den Palox), verdunstet, Faules beim Abpacken. Liegende
 * Eingangsmasse = verkaufsfähig + diese vier. `bekannt`: Verdunstung und
 * Faules sind gemessen — sonst ist, was im Lager liegt, eine obere Schranke.
 */
export interface RestTeile { kanal: number; faul: number; verdunstet: number; fax: number; bekannt?: boolean
  /** 0121: Hagelware (Unique) — nicht faul; wird als Knospe verkauft. faul ist dann das Faule ohne Hagel. */
  unique?: number
  /** 0123: Überfüllung je Soll (zu viel ÷ Soll) der Charge; null = nicht gewogen; fehlt = kein Ausweis. */
  marge?: number | null }

/** Ein Artikel ohne Grösse (Gruppe × Label), mit allem, was seine Chargen bis heute erlebt haben. */
export interface Uebersichtszeile {
  schluessel: string; gruppe: string | null; label: 'D' | 'K' | null; n: number
  eingang: number; ausgelagert: number; geliefert: number
  /** Die liegende Eingangsmasse: Eingang − ausgelagert (der Balken ist so lang wie der Eingang). */
  lager: number
  /** 23. Oktober: im Lager — die Paletten vom Eingang, die noch stehen, mit dem Gewicht beim Eingang (src/auswertung/lager.ts).
   *  imLagerHoechstens: seit dem 23. Oktober immer false — die Eingangsmasse hängt an keiner Rate. */
  imLager: number; imLagerHoechstens: boolean
  /** 0123: das Verkaufsfähige ist eine obere Schranke — eine Charge ohne gewogene Überfüllung oder ohne Sortier-CSV. */
  vfHoechstens: boolean
  /** Die Eingangspaletten, die noch da sind (Σ n_rest_paletten); null, wenn keine Charge eine Zahl hat. */
  paletten: number | null
  /** Das Verkaufsfähige heute; luecke: Chargen mit Ware, deren Verkaufsfähiges unbekannt ist (nie 0). */
  vf: number; luecke: number
  /** Das Verkaufsfähige nach Grösse, heute und am Stichtag der Tabelle (Runde AS: Wochenregler nur dort). */
  klassen: Map<Klasse, number>; klassenSpaeter: Map<Klasse, number>
  /** Runde AS: der Rest des Lagers wie im Lagermanagement nach Charge; offen — Chargen ohne Teilung (nie 0 statt unbekannt).
   *  0123: ueberfuellung — was in den Kisten über dem Soll verschenkt wird, auf dem Teil, der als Artikel geht (heute). */
  rest: RestTeile & { offen: number; ueberfuellung: number }
  chargen: number[]
}

export function uebersichtszeilen(bestand: Bestand[], labelVon: Map<number, ChargeLabel>, gruppeVon: Map<string, SorteGruppe>,
                           teile: ArtikelLagerCharge[], wahl: Wahl,
                           weiter: { spaeter?: ArtikelLagerCharge[]; rest?: Map<number, RestTeile> } = {}): Uebersichtszeile[] {
  const m = new Map<string, Uebersichtszeile>()
  const zuZeile = new Map<number, Uebersichtszeile>()
  for (const b of bestand) {
    const gruppe = gruppeVon.get(b.sorte)?.artikelgruppe ?? null
    const label = labelVon.get(b.charge_nr)?.label ?? null
    if (!passtGruppe(wahl, gruppe) || !passtLabel(wahl, label)) continue
    const k = `${gruppe ?? ''}|${label ?? ''}`
    let z = m.get(k)
    if (!z) {
      z = { schluessel: k, gruppe, label, n: 0, eingang: 0, ausgelagert: 0, geliefert: 0, lager: 0, imLager: 0, imLagerHoechstens: false,
            vfHoechstens: false, paletten: null, vf: 0, luecke: 0,
            klassen: new Map(), klassenSpaeter: new Map(), rest: { kanal: 0, faul: 0, verdunstet: 0, fax: 0, offen: 0, ueberfuellung: 0 }, chargen: [] }
      m.set(k, z)
    }
    z.n += 1
    z.chargen.push(b.charge_nr)
    z.eingang += Number(b.eingang_kg); z.ausgelagert += Number(b.ausgelagert_kg)
    z.geliefert += Number(b.geliefert_kg); z.lager += Number(b.lager_kg)
    if (b.lager_kg > 0) {
      if (b.verkaufsfaehig_lager_kg === null) z.luecke += 1
      else z.vf += Number(b.verkaufsfaehig_lager_kg)
      if (b.n_rest_paletten != null) z.paletten = (z.paletten ?? 0) + Number(b.n_rest_paletten)
      // Der Rest nur, wo die Kaskade ihn geteilt hat und das Verkaufsfähige bekannt ist —
      // sonst liegt die ganze Ware dieser Charge als „offen" im Balken, nie als 0.
      const r = weiter.rest?.get(b.charge_nr)
      // 23. Oktober: Im Lager ist die Eingangsmasse der Paletten, die noch stehen — ohne Abzug.
      // Was verdunstet und faul ist, steht als Teil des Lagers im Balken, nicht daneben.
      z.imLager += Number(b.lager_kg)
      if (r && b.verkaufsfaehig_lager_kg !== null) {
        z.rest.kanal += r.kanal; z.rest.faul += r.faul; z.rest.verdunstet += r.verdunstet; z.rest.fax += r.fax
        z.rest.offen += Math.max(Number(b.lager_kg) - Number(b.verkaufsfaehig_lager_kg) - r.kanal - r.faul - r.verdunstet - r.fax - (r.unique ?? 0), 0)
      } else z.rest.offen += Math.max(Number(b.lager_kg) - Number(b.verkaufsfaehig_lager_kg ?? 0), 0)
    }
    zuZeile.set(b.charge_nr, z)
  }
  // 0121: Unique (Hagel) geht als Knospe — in die Knospe-Zeile der Artikelgruppe, auch wenn die Charge Demeter ist.
  for (const b of bestand) {
    const u = weiter.rest?.get(b.charge_nr)?.unique ?? 0
    if (!(u > 0) || !(b.lager_kg > 0)) continue
    const gruppe = gruppeVon.get(b.sorte)?.artikelgruppe ?? null
    if (!passtGruppe(wahl, gruppe) || !passtLabel(wahl, 'K')) continue
    const k = `${gruppe ?? ''}|K`
    let z = m.get(k)
    if (!z) {
      z = { schluessel: k, gruppe, label: 'K', n: 0, eingang: 0, ausgelagert: 0, geliefert: 0, lager: 0, imLager: 0, imLagerHoechstens: false,
            vfHoechstens: false, paletten: null, vf: 0, luecke: 0,
            klassen: new Map(), klassenSpaeter: new Map(), rest: { kanal: 0, faul: 0, verdunstet: 0, fax: 0, offen: 0, ueberfuellung: 0 }, chargen: [] }
      m.set(k, z)
    }
    const eigen = zuZeile.get(b.charge_nr)
    if (eigen && eigen !== z) eigen.imLager = Math.max(eigen.imLager - u, 0)
    if (eigen !== z) z.imLager += u
    z.klassen.set('unique', (z.klassen.get('unique') ?? 0) + u)
    z.klassenSpaeter.set('unique', (z.klassenSpaeter.get('unique') ?? 0) + u)
    if (!z.chargen.includes(b.charge_nr)) z.chargen.push(b.charge_nr)
  }
  // Das Verkaufsfähige nach Grösse: heute für den Balken, am Stichtag für die Tabelle.
  // 0123: ohne die Überfüllung — was als Artikel geht, in Kisten über dem Soll, ist zu
  // a/(1+a) verschenkt (a aus den gewogenen Paletten der Charge, sonst ihrer Sorte).
  // Nicht gewogen: nichts abgezogen, aber die Zahl ist höchstens so gross.
  const zuteilen = (liste: ArtikelLagerCharge[], feld: 'klassen' | 'klassenSpaeter') => {
    for (const t of liste) {
      const z = zuZeile.get(t.charge_nr)
      if (!z || !(Number(t.kg) > 0)) continue
      const kl = klasseVon(t.groesse)
      const n = alsArtikel(t, weiter.rest)
      if (n.offen) z.vfHoechstens = true
      if (feld === 'klassen') z.rest.ueberfuellung += n.ueberfuellung
      z[feld].set(kl, (z[feld].get(kl) ?? 0) + n.kg)
    }
  }
  zuteilen(teile, 'klassen')
  zuteilen(weiter.spaeter ?? teile, 'klassenSpaeter')
  return [...m.values()].filter(z => z.eingang > 0 || (z.klassen.get('unique') ?? 0) > 0)
    .sort((a, b) => rang(a.gruppe) - rang(b.gruppe) || (a.gruppe ?? '').localeCompare(b.gruppe ?? '')
                    || (a.label ?? 'Z').localeCompare(b.label ?? 'Z'))
}

/* ---------- Runde AS: Kundengruppen, Planmengen, reicht es? ---------------- */

/** Verkauft: KundeTag.groesse ist gross, klein oder lose — lose zählt nur bei „beide". */
export const passtVerkauf = (w: Wahl, g: string) => w.groesse === 'beide' || g === w.groesse

/**
 * Zu welcher Gruppe ein Kunde gehört (Runde AS). Der Betrieb: „dass ich Coop
 * als Ganzes sehe … Migros, Coop, und dann alles andere sind Kleinkunden."
 * Was der Betriebsleiter gesetzt hat (kunde_gruppe), gilt; sonst ordnet der
 * Name: Migros, Coop (auch die Verteilzentralen RVZ/RZV), sonst Kleinkunden.
 */
export function kundenGruppe(kunde: string, gesetzt: Map<string, string>): string {
  const g = gesetzt.get(kunde)
  if (g) return g
  if (/migros/i.test(kunde)) return 'Migros'
  if (/\bcoop\b|^r[vz][vz]\b/i.test(kunde)) return 'Coop'
  return 'Kleinkunden'
}

/** Eine Planmenge (kunde_plan, 0116): je Saison und Kunde, für eine Wahl — '' heisst alle. */
export interface KundePlan { saison: number; kunde: string; artikelgruppe: string; groesse: string; label: string; kg: number }

/** Unter welchem Schlüssel ein Plan für diese Wahl steht. */
export const planSchluessel = (w: Wahl) =>
  ({ artikelgruppe: w.gruppe, groesse: w.groesse === 'beide' ? '' : w.groesse, label: w.label === 'beide' ? '' : w.label })

/**
 * Der Plan eines Kunden für eine Saison und eine Wahl. Ein eingetragener Plan
 * gilt genau für die Wahl, für die er steht; ohne ihn ist der Plan die ganze
 * Vorjahressaison (`vorjahr`). Bei „Demeter und Knospe" zählen eingetragene
 * Pläne je Label zusammen — das fehlende Label mit seinem Vorjahr. `eigen`
 * sagt, ob der Betrieb ihn gesetzt hat (true), teils (eines der Labels) oder
 * nicht (false — dann ist es das Vorjahr).
 */
export function planFuer(kunde: string, saison: number, w: Wahl, plaene: KundePlan[],
                         vorjahr: (label: LabelWahl) => number): { kg: number; eigen: boolean | 'teils' } {
  const s = planSchluessel(w)
  const finde = (label: string) => plaene.find(p => p.saison === saison && p.kunde === kunde && p.artikelgruppe === s.artikelgruppe
                                                   && p.groesse === s.groesse && p.label === label)
  const genau = finde(s.label)
  if (genau) return { kg: Number(genau.kg), eigen: true }
  if (w.label === 'beide') {
    const d = finde('D'), k = finde('K')
    if (d || k) {
      const ohneLabel = Math.max(vorjahr('beide') - vorjahr('D') - vorjahr('K'), 0)
      return { kg: (d ? Number(d.kg) : vorjahr('D')) + (k ? Number(k.kg) : vorjahr('K')) + ohneLabel, eigen: d && k ? true : 'teils' }
    }
  }
  return { kg: vorjahr(w.label), eigen: false }
}

/** Die Planmenge einer ganzen Kundengruppe (gruppe_plan, 0117) — gleiche Schlüssel wie KundePlan. */
export interface GruppePlan { saison: number; gruppe: string; artikelgruppe: string; groesse: string; label: string; kg: number }

/** Wo eine Gruppe steht (kunde_gruppe_rang, 0117): kleiner Rang zuerst. */
export interface GruppeRang { gruppe: string; rang: number }

/**
 * Die Reihenfolge der Kundengruppen (Runde AT): was der Betriebsleiter
 * geordnet hat, zuerst und in seiner Folge; danach die übrigen nach ihrer
 * Menge, die grösste zuerst — Kleinkunden ohne Rang immer zuletzt.
 */
export function gruppenFolge(gruppen: { name: string; menge: number }[], rang: GruppeRang[]): string[] {
  const r = new Map(rang.map(x => [x.gruppe, Number(x.rang)]))
  const stufe = (g: { name: string }) => r.has(g.name) ? 0 : g.name === 'Kleinkunden' ? 2 : 1
  return [...gruppen].sort((a, b) => stufe(a) - stufe(b) || (r.get(a.name) ?? 0) - (r.get(b.name) ?? 0)
                                     || b.menge - a.menge || a.name.localeCompare(b.name, 'de')).map(g => g.name)
}

export interface Offen { plan: number; eigen: boolean | 'teils'; geliefert: number; offen: number }

/**
 * Was diese Saison noch zu liefern ist — je Kunde der Plan weniger das schon
 * Gelieferte, nie unter null —, über alle Kunden, die den Artikel im Vorjahr
 * oder in dieser Saison bekamen oder einen Plan haben (Runde AS: „Reicht, was
 * da ist?").
 *
 * Runde AT: mit `gruppen` auch je Gruppe. Hat eine Gruppe einen eigenen Plan
 * (gruppe_plan), gilt er für die Gruppe als Ganzes: Plan weniger das
 * Gelieferte aller ihrer Kunden; die Pläne der Kunden darin zählen dann nicht
 * noch einmal. Ohne Gruppenplan ist die Gruppe die Summe ihrer Kunden. `kg`
 * ist dann die Summe über die Gruppen.
 */
export function nochZuLiefern(kunden: { kunde: string; saison: number; gruppe: string | null; groesse: string; label: string | null; kg: number | null }[],
                              plaene: KundePlan[], saison: number, w: Wahl, nurKunden?: Set<string>,
                              gruppen?: { von: (kunde: string) => string; plaene: GruppePlan[] }):
    { kg: number; jeKunde: Map<string, Offen>; jeGruppe: Map<string, Offen & { gruppenplan: boolean }> } {
  const passt = (k: typeof kunden[number], l: LabelWahl) => passtGruppe(w, k.gruppe) && passtVerkauf(w, k.groesse) && passtLabel({ ...w, label: l }, k.label)
  const namen = new Set<string>()
  for (const k of kunden) if ((k.saison === saison || k.saison === saison - 1) && passt(k, w.label)) namen.add(k.kunde)
  const s = planSchluessel(w)
  for (const p of plaene) if (p.saison === saison && p.artikelgruppe === s.artikelgruppe && p.groesse === s.groesse) namen.add(p.kunde)
  const jeKunde = new Map<string, Offen>()
  const summeVon = (n: string, sai: number, l: LabelWahl) =>
    kunden.filter(k => k.kunde === n && k.saison === sai && passt(k, l)).reduce((a, k) => a + Number(k.kg ?? 0), 0)
  const planVon = (n: string, l: LabelWahl) => planFuer(n, saison, { ...w, label: l }, plaene, l2 => summeVon(n, saison - 1, l2))
  let summe = 0
  for (const n of namen) {
    if (nurKunden && !nurKunden.has(n)) continue
    const plan = planVon(n, w.label)
    const geliefert = summeVon(n, saison, w.label)
    const offen = Math.max(plan.kg - geliefert, 0)
    jeKunde.set(n, { plan: plan.kg, eigen: plan.eigen, geliefert, offen })
    summe += offen
  }
  const jeGruppe = new Map<string, Offen & { gruppenplan: boolean }>()
  if (!gruppen) return { kg: summe, jeKunde, jeGruppe }

  // Je Gruppe: ihr eigener Plan, sonst die Summe ihrer Kunden.
  const mitglieder = new Map<string, string[]>()
  for (const n of jeKunde.keys()) mitglieder.set(gruppen.von(n), [...(mitglieder.get(gruppen.von(n)) ?? []), n])
  for (const p of gruppen.plaene) if (p.saison === saison && p.artikelgruppe === s.artikelgruppe && p.groesse === s.groesse && !mitglieder.has(p.gruppe))
    if (!nurKunden) mitglieder.set(p.gruppe, [])
  summe = 0
  for (const [g, ns] of mitglieder) {
    const geliefert = ns.reduce((a, n) => a + (jeKunde.get(n)?.geliefert ?? 0), 0)
    const ohneGruppenplan = (l: LabelWahl) => ns.reduce((a, n) => a + planVon(n, l).kg, 0)
    const gp = planFuer(g, saison, w, gruppen.plaene.map(p => ({ ...p, kunde: p.gruppe })), ohneGruppenplan)
    const eigenKunden = ns.map(n => jeKunde.get(n)?.eigen ?? false)
    const eigen: boolean | 'teils' = gp.eigen !== false ? gp.eigen
      : eigenKunden.length > 0 && eigenKunden.every(e => e === true) ? true : eigenKunden.some(e => e !== false) ? 'teils' : false
    const offen = gp.eigen !== false ? Math.max(gp.kg - geliefert, 0) : ns.reduce((a, n) => a + (jeKunde.get(n)?.offen ?? 0), 0)
    jeGruppe.set(g, { plan: gp.kg, eigen, geliefert, offen, gruppenplan: gp.eigen !== false })
    summe += offen
  }
  return { kg: summe, jeKunde, jeGruppe }
}
