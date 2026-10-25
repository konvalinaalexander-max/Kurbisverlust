/**
 * Beispiele, die die Demo von selbst nicht hat — für bildschirme.mjs und
 * beschriftung.mjs gleich, damit beide Prüfstände denselben Fall sehen.
 */
import { fixture, vormerken } from './attrappe.mjs'

/*
 * Runde BG, 25. Oktober: Die Demo rechnet vom heutigen Tag aus. Welche Charge
 * noch Ware im Lager hat und auf welcher der Mandarin-Lieferschein steht,
 * wandert mit dem Datum — gestern hatte die erste Zeile (1598) noch Ware,
 * heute ist sie ausverkauft und zeigt zu Recht keine Lagerrechnung; der
 * Mandarin stand auf 1630 und steht jetzt auf 1628. Die Szenen nehmen die
 * Nummer darum aus den Fixtures, nicht aus dem Kopf.
 */

/** Die kleinste Chargennummer, die laut v_lager_ausweis heute noch etwas im Lager hat. */
export function chargeMitLager() {
  const nr = (fixture('v_lager_ausweis') ?? []).filter(a => Number(a.eingang_kg) > 0).map(a => a.charge_nr).sort((a, b) => a - b)[0]
  if (nr == null) throw new Error('v_lager_ausweis.json kennt keine Charge mit Ware im Lager — daten_dumpen.sh neu laufen lassen')
  return nr
}

/** Der Lieferschein, auf dem die Demo einen Artikel einer anderen Sorte verkauft (der Mandarin auf einer Kaori Kuri). */
function fremderArtikel() {
  const f = (fixture('v_perigon_befund') ?? []).find(b => b.art === 'artikel_sorte' && b.charge_nr != null && /Mandarin/.test(b.artikel ?? ''))
  if (!f) throw new Error('v_perigon_befund.json kennt keinen Mandarin auf fremder Charge — daten_dumpen.sh neu laufen lassen')
  return f
}

/** Die Charge mit dem Mandarin. */
export const chargeMitFremdemArtikel = () => fremderArtikel().charge_nr

/**
 * Am Mandarin-Lieferschein noch eine zweite Sache: die Rechnung nennt 50 kg
 * mehr als die Datei. Bis zum 24. Oktober hatte die Demo das zufällig selbst
 * (auf 1630); jetzt steht es fest, damit das Fenster zeigen muss, was an der
 * Position sonst noch nicht stimmt.
 */
export function fremderArtikelVormerken() {
  const f = fremderArtikel(), rechnung = Number(f.kg_position) + 50
  vormerken('v_perigon_befund', [{ ...f, schluessel: `masse_abweichung:${f.quelle}:${f.pos_id}`, art: 'masse_abweichung', schwere: 'gelb',
    nummern: null, nummer: null, lauf_nr: null, kg_rechnung: rechnung, kg: 50, wo: 'einlesen',
    satz: `In der Rechnung stehen für diese Position ${rechnung} kg, die Datei ergibt ${f.kg_position} kg — 50 kg zu viel.`,
    tun: 'Die Datei unter Betrieb → Warenausgang neu einlesen.' }])
}

/** Die Zeile einer Charge in der Chargentabelle — an der Nummer erkannt, nicht an der Stelle. */
export const chargenZeile = (p, nr) => p.locator('.chargentabelle tbody tr')
  .filter({ has: p.locator('td:nth-child(2) > strong', { hasText: new RegExp(`^${nr}$`) }) }).first()

/**
 * Runde BG: eine Zettel-Auffälligkeit, wie sie beim Betrieb am häufigsten ist —
 * drei Zettel einen Tag zu früh datiert, jedes Gewicht steht am Tag danach
 * genau so im Wareneingang. Die Demo hat nur ein Zetteldatum ohne Wareneingang
 * dahinter; die Nummern sind erfunden, damit das Bild nicht vom Stand der
 * Fixtures abhängt.
 */
export function auffVormerken() {
  const A = 990200, C = 99130, start = '2026-10-21T07:30:00+00:00'
  const b = (art, bezug, befund, rat) => ({ art, bezug, auftrag_id: A, charge_nr: C, sorte: 'Muscade', start_ts: start, befund, rat })
  vormerken('erg_plausibilitaet', [
    b('Zetteldatum', `zetteldatum:${A}:2026-10-07`, '3 Palette(n) mit Zetteldatum 07.10.2026 gezählt, aber an dem Tag kam keine Palette dieser Charge',
      'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'),
    b('Zettelgewicht', `zettel:${A}:448.00:2026-10-07`, '1 Palette(n) mit 448.00 kg vom Zettel und Eingangsdatum 07.10.2026 gezählt. Eine Palette dieses Gewichts gibt es in der Charge, aber an einem anderen Tag — gerechnet wird mit den gezählten Kisten und ihrer Tara (Zettel − Kisten × Kiste − Palette), nicht mit der Palette selbst.',
      'Eingangsdatum an der Zählung prüfen — oder das Datum der Palette im Wareneingang.'),
  ])
  vormerken('auftrag', [{ id: A, weg: 'hand', station: 'waschen_sortieren', ist_fax: false, charge_nr: C, start_ts: start,
    ende_ts: '2026-10-21T11:00:00+00:00', status: 'abgeschlossen', abgebrochen_ts: null }])
  vormerken('auftrag_palette', [[990201, 448, 36], [990202, 433, 36], [990203, 380, 33]].map(([id, kg, kisten]) =>
    ({ id, auftrag_id: A, eingangsdatum: '2026-10-07', brutto_zettel_kg: kg, kisten, gebindeart: 'G2' })))
  vormerken('palette', [448, 433, 380, 441, 455, 470].map((kg, i) => ({ id: 990210 + i, charge_nr: C, eingangsdatum: '2026-10-08', brutto_kg: kg,
    kisten: kg === 380 ? 33 : 36, gebindeart: 'G2', extern_id: `bild-bg-${i}`, quelle: 'journal-import' })))
}
