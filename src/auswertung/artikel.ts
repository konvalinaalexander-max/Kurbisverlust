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
export type Klasse = 'klein' | 'gross' | 'stueck' | 'ausserhalb' | 'ohne'
export const KLASSEN: Klasse[] = ['klein', 'gross', 'stueck', 'ausserhalb', 'ohne']
export const klasseVon = (g: string): Klasse =>
  g === 'klein' || g === 'gross' || g === 'stueck' ? g : g === 'ohne Verteilung' ? 'ohne' : 'ausserhalb'

export const passtGruppe = (w: Wahl, g: string | null) => w.gruppe === '' || g === w.gruppe
export const passtLabel = (w: Wahl, l: string | null) => w.label === 'beide' || l === w.label
export const passtKlasse = (w: Wahl, k: Klasse) => w.groesse === 'beide' || k === w.groesse

/**
 * Was vom Lager einer Charge nicht mehr verkaufsfähig ist — so geteilt, wie
 * die Kaskade es tut (erg_prognose, h = 0): zu klein / zu gross, Palox,
 * verdunstet, Faules beim Abpacken. Lager = verkaufsfähig + diese vier.
 */
export interface RestTeile { kanal: number; faul: number; verdunstet: number; fax: number }

/** Ein Artikel ohne Grösse (Gruppe × Label), mit allem, was seine Chargen bis heute erlebt haben. */
export interface Uebersichtszeile {
  schluessel: string; gruppe: string | null; label: 'D' | 'K' | null; n: number
  eingang: number; ausgelagert: number; geliefert: number; lager: number
  /** Das Verkaufsfähige heute; luecke: Chargen mit Ware, deren Verkaufsfähiges unbekannt ist (nie 0). */
  vf: number; luecke: number
  /** Das Verkaufsfähige nach Grösse, heute und am Stichtag der Tabelle (Runde AS: Wochenregler nur dort). */
  klassen: Map<Klasse, number>; klassenSpaeter: Map<Klasse, number>
  /** Runde AS: der Rest des Lagers wie im Lagermanagement nach Charge; offen — Chargen ohne Teilung (nie 0 statt unbekannt). */
  rest: RestTeile & { offen: number }
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
      z = { schluessel: k, gruppe, label, n: 0, eingang: 0, ausgelagert: 0, geliefert: 0, lager: 0, vf: 0, luecke: 0,
            klassen: new Map(), klassenSpaeter: new Map(), rest: { kanal: 0, faul: 0, verdunstet: 0, fax: 0, offen: 0 }, chargen: [] }
      m.set(k, z)
    }
    z.n += 1
    z.chargen.push(b.charge_nr)
    z.eingang += Number(b.eingang_kg); z.ausgelagert += Number(b.ausgelagert_kg)
    z.geliefert += Number(b.geliefert_kg); z.lager += Number(b.lager_kg)
    if (b.lager_kg > 0) {
      if (b.verkaufsfaehig_lager_kg === null) z.luecke += 1
      else z.vf += Number(b.verkaufsfaehig_lager_kg)
      // Der Rest nur, wo die Kaskade ihn geteilt hat und das Verkaufsfähige bekannt ist —
      // sonst liegt die ganze Ware dieser Charge als „offen" im Balken, nie als 0.
      const r = weiter.rest?.get(b.charge_nr)
      if (r && b.verkaufsfaehig_lager_kg !== null) {
        z.rest.kanal += r.kanal; z.rest.faul += r.faul; z.rest.verdunstet += r.verdunstet; z.rest.fax += r.fax
        z.rest.offen += Math.max(Number(b.lager_kg) - Number(b.verkaufsfaehig_lager_kg) - r.kanal - r.faul - r.verdunstet - r.fax, 0)
      } else z.rest.offen += Math.max(Number(b.lager_kg) - Number(b.verkaufsfaehig_lager_kg ?? 0), 0)
    }
    zuZeile.set(b.charge_nr, z)
  }
  // Das Verkaufsfähige nach Grösse: heute für den Balken, am Stichtag für die Tabelle.
  const zuteilen = (liste: ArtikelLagerCharge[], feld: 'klassen' | 'klassenSpaeter') => {
    for (const t of liste) {
      const z = zuZeile.get(t.charge_nr)
      if (!z || !(Number(t.kg) > 0)) continue
      const kl = klasseVon(t.groesse)
      z[feld].set(kl, (z[feld].get(kl) ?? 0) + Number(t.kg))
    }
  }
  zuteilen(teile, 'klassen')
  zuteilen(weiter.spaeter ?? teile, 'klassenSpaeter')
  return [...m.values()].filter(z => z.eingang > 0)
    .sort((a, b) => rang(a.gruppe) - rang(b.gruppe) || (a.gruppe ?? '').localeCompare(b.gruppe ?? '')
                    || (a.label ?? 'Z').localeCompare(b.label ?? 'Z'))
}
