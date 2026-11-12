/**
 * KW-Planung (Runde BL): was in welcher Kalenderwoche an welchen Kunden ging.
 *
 * Der Betrieb: „Wir wollen einfach nachschauen, wie viel lief in den letzten
 * KWs nach Kunde und Produkt. … Kunde und KW. Erste Spalte Produkt, die
 * nächsten Spalten die KWs, die ausgesucht sind, rechts davon Summe. … Wenn
 * ich mehrere Kunden anklicke, machst du zwei Tabellen untereinander."
 *
 * Keine zweite Rechnung: Die Zahlen sind die Positionen der Perigon-Dateien
 * (v_kunde_tag — je Kunde, Tag und Artikel), nur nach Kalenderwoche
 * zusammengezählt. Ein Artikel ist Artikelgruppe × Grösse × Label, wie überall
 * im Reiter. Reine Funktionen, kein Netz — prüfbar (test/kw.test.ts).
 */
import type { KundeTag } from './daten'
import { kundenGruppe, gruppenFolge, rang, type GruppeRang } from './artikel.ts'

const TAG = 86400000

// Reine Tagesrechnung auf dem Kalendertag (JJJJ-MM-TT), ohne Uhrzeit und ohne Zone: der Tag als Zahl
// (Mitternacht UTC) und zurück. Kein „heute" aus der Uhr — das kommt von aussen (daten.heute).
const zwei = (n: number) => String(n).padStart(2, '0')
const tagZahl = (d: string) => Date.UTC(Number(d.slice(0, 4)), Number(d.slice(5, 7)) - 1, Number(d.slice(8, 10)))
const tagText = (t: number) => { const d = new Date(t); return `${d.getUTCFullYear()}-${zwei(d.getUTCMonth() + 1)}-${zwei(d.getUTCDate())}` }
/** Der Kalendertag `tage` Tage später (oder früher). */
export const tagPlus = (datum: string, tage: number) => tagText(tagZahl(datum) + tage * TAG)

/** Die Kalenderwoche nach ISO 8601 (Montag bis Sonntag; KW 1 ist die Woche mit dem ersten Donnerstag). */
export function isoWoche(datum: string): { jahr: number; kw: number; schluessel: string } {
  const t = tagZahl(datum)
  const wochentag = (new Date(t).getUTCDay() + 6) % 7      // Montag = 0
  const donnerstag = t + (3 - wochentag) * TAG
  const jahr = new Date(donnerstag).getUTCFullYear()
  const kw = 1 + Math.floor((donnerstag - Date.UTC(jahr, 0, 1)) / (7 * TAG))
  return { jahr, kw, schluessel: `${jahr}-W${zwei(kw)}` }
}

/** Der Montag einer Kalenderwoche (ISO), als Datum. */
export function wocheMontag(schluessel: string): string {
  const jahr = Number(schluessel.slice(0, 4)), kw = Number(schluessel.slice(6))
  const vierter = Date.UTC(jahr, 0, 4)                              // der 4. Januar liegt immer in KW 1
  const montag1 = vierter - ((new Date(vierter).getUTCDay() + 6) % 7) * TAG
  return tagText(montag1 + (kw - 1) * 7 * TAG)
}

/** „KW 47" — mit dem Jahr nur, wenn die Auswahl über den Jahreswechsel geht. */
export const kwName = (schluessel: string, mitJahr = false) =>
  `KW ${Number(schluessel.slice(6))}${mitJahr ? ` ${schluessel.slice(0, 4)}` : ''}`

/** Die Saison läuft vom 1. Juli bis zum 30. Juni (wie saison_von, 0112). */
export const saisonVon = (d: string) => { const j = Number(d.slice(0, 4)), m = Number(d.slice(5, 7)); return m >= 7 ? j : j - 1 }

/**
 * Alle Kalenderwochen der Saison, von der Woche der ersten Lieferung bis zur
 * laufenden — auch die, in denen nichts ging. Nächste Woche ist es eine mehr.
 * Leer, wenn die Saison noch keine Lieferung hat.
 */
export function wochenDerSaison(zeilen: KundeTag[], saison: number, heute: string): string[] {
  let erste: string | null = null
  for (const z of zeilen) if (Number(z.saison) === saison && (erste === null || z.datum < erste)) erste = z.datum
  if (erste === null) return []
  const ende = wocheMontag(isoWoche(heute).schluessel)
  const wochen: string[] = []
  for (let montag = wocheMontag(isoWoche(erste).schluessel); montag <= ende; montag = tagPlus(montag, 7))
    wochen.push(isoWoche(montag).schluessel)
  return wochen
}

/* ---------- Die Kunden: einzeln und als Gruppe ---------------------------------- */

/** Was man anklickt: ein Kunde ('k:Name') oder eine ganze Gruppe ('g:Name'). */
export type KwWahl = string
export const kundeWahl = (kunde: string): KwWahl => `k:${kunde}`
export const gruppeWahl = (gruppe: string): KwWahl => `g:${gruppe}`

export interface KwKundengruppe { name: string; kunden: { name: string; kg: number }[]; kg: number }

/**
 * Die Kunden der Saison, nach Gruppe geordnet — die Gruppen in der Reihenfolge
 * des Reiters (kunde_gruppe_rang, sonst nach Menge, Kleinkunden zuletzt), die
 * Kunden darin nach Menge. Wer in der Saison nichts bekam, steht nicht da.
 */
export function kundenGruppen(zeilen: KundeTag[], saison: number, gesetzt: Map<string, string>, rangListe: GruppeRang[]): KwKundengruppe[] {
  const jeKunde = new Map<string, number>()
  for (const z of zeilen) if (Number(z.saison) === saison) jeKunde.set(z.kunde, (jeKunde.get(z.kunde) ?? 0) + Number(z.kg ?? 0))
  const gruppen = new Map<string, KwKundengruppe>()
  for (const [name, menge] of jeKunde) {
    const g = kundenGruppe(name, gesetzt)
    const eintrag = gruppen.get(g) ?? { name: g, kunden: [], kg: 0 }
    eintrag.kunden.push({ name, kg: menge }); eintrag.kg += menge
    gruppen.set(g, eintrag)
  }
  for (const g of gruppen.values()) g.kunden.sort((a, b) => b.kg - a.kg || a.name.localeCompare(b.name, 'de'))
  return gruppenFolge([...gruppen.values()].map(g => ({ name: g.name, menge: g.kg })), rangListe).map(n => gruppen.get(n)!)
}

/** Welche Kunden eine Wahl meint. */
export function kundenDerWahl(wahl: KwWahl, gruppen: KwKundengruppe[]): string[] {
  if (wahl.startsWith('k:')) return [wahl.slice(2)]
  return gruppen.find(g => g.name === wahl.slice(2))?.kunden.map(k => k.name) ?? []
}

/* ---------- Die Tabelle: Artikel × Kalenderwoche --------------------------------- */

export interface KwArtikel {
  schluessel: string
  gruppe: string | null; groesse: string; label: string | null
  /** je gewählter Woche die gelieferte Masse — eine Woche ohne Lieferung fehlt (leer ist nicht null). */
  jeWoche: Map<string, number>
  summe: number
}

export interface KwTabelle {
  artikel: KwArtikel[]
  jeWoche: Map<string, number>
  summe: number
  /** wie viele Positionen der Perigon-Dateien in der Tabelle stecken */
  positionen: number
  /** Stück, deren Masse Perigon nicht hergibt (kein Stückgewicht) — nicht in den Kilos. */
  stueckOhneGewicht: number
  positionenOhneGewicht: number
}

const GROESSE_FOLGE = ['klein', 'gross', 'stueck', 'lose']
const groesseRang = (g: string) => { const i = GROESSE_FOLGE.indexOf(g); return i < 0 ? 9 : i }
const labelRang = (l: string | null) => l === 'D' ? 0 : l === 'K' ? 1 : 2

/**
 * Was an diese Kunden in diesen Wochen ging, je Artikel. Nur was geliefert
 * wurde: ein Artikel ohne Position in den gewählten Wochen hat keine Zeile.
 */
export function kwTabelle(zeilen: KundeTag[], kunden: Iterable<string>, wochen: string[], saison: number): KwTabelle {
  const wer = new Set(kunden), wann = new Set(wochen)
  const artikel = new Map<string, KwArtikel>()
  const jeWoche = new Map<string, number>()
  let summe = 0, positionen = 0, stueckOhneGewicht = 0, positionenOhneGewicht = 0
  for (const z of zeilen) {
    if (Number(z.saison) !== saison || !wer.has(z.kunde)) continue
    const w = isoWoche(z.datum).schluessel
    if (!wann.has(w)) continue
    const schluessel = `${z.gruppe ?? ''}|${z.groesse}|${z.label ?? ''}`
    const a = artikel.get(schluessel) ?? { schluessel, gruppe: z.gruppe, groesse: z.groesse, label: z.label, jeWoche: new Map<string, number>(), summe: 0 }
    artikel.set(schluessel, a)
    positionen += Number(z.positionen ?? 0)
    stueckOhneGewicht += Number(z.stueck_ohne_gewicht ?? 0)
    positionenOhneGewicht += Number(z.positionen_ohne_gewicht ?? 0)
    if (z.kg === null || z.kg === undefined) continue      // keine Position des Tages hat eine Masse
    const masse = Number(z.kg)
    a.jeWoche.set(w, (a.jeWoche.get(w) ?? 0) + masse); a.summe += masse
    jeWoche.set(w, (jeWoche.get(w) ?? 0) + masse); summe += masse
  }
  const liste = [...artikel.values()].sort((a, b) => rang(a.gruppe) - rang(b.gruppe) || (a.gruppe ?? '').localeCompare(b.gruppe ?? '', 'de')
    || groesseRang(a.groesse) - groesseRang(b.groesse) || labelRang(a.label) - labelRang(b.label))
  return { artikel: liste, jeWoche, summe, positionen, stueckOhneGewicht, positionenOhneGewicht }
}

/** „KW 43–46" für zusammenhängende Wochen, sonst „KW 40, 43, 46"; bei vielen einzelnen die Zahl. */
export function wochenText(wochen: string[], alle: string[]): string {
  if (wochen.length === 0) return 'keine Woche'
  const sortiert = [...wochen].sort()
  const mitJahr = new Set(sortiert.map(w => w.slice(0, 4))).size > 1
  if (sortiert.length === 1) return kwName(sortiert[0], mitJahr)
  const i = alle.indexOf(sortiert[0])
  const zusammen = i >= 0 && sortiert.every((w, k) => alle[i + k] === w)
  if (zusammen) return `${kwName(sortiert[0], mitJahr)}–${mitJahr ? kwName(sortiert[sortiert.length - 1], true).slice(3) : Number(sortiert[sortiert.length - 1].slice(6))}`
  if (sortiert.length <= 5) return `KW ${sortiert.map(w => mitJahr ? kwName(w, true).slice(3) : String(Number(w.slice(6)))).join(', ')}`
  return `${sortiert.length} Wochen`
}
