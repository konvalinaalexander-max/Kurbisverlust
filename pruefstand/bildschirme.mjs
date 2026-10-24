/**
 * Der Bildschirm-Prüfstand: rendert jede Seite der App in einem echten Browser
 * und legt Screenshots ab — mobil und Desktop, hell und dunkel.
 *
 * Es gibt kein laufendes Supabase dabei: Die Attrappe (attrappe.mjs) antwortet
 * aus den JSON-Dateien in pruefstand/daten/, die daten_dumpen.sh aus der
 * lokalen Demo-Datenbank gezogen hat. Die App sieht also echte Datenformen und
 * echte Zahlen — nur eben ohne Netz.
 *
 * Warum der Aufwand: "npm run build läuft durch" sagt nichts darüber, ob eine
 * Tabelle aus dem Rahmen läuft oder eine Zahl als NaN dasteht. Das sieht man
 * nur auf dem gerenderten Bildschirm.
 *
 *   node pruefstand/bildschirme.mjs            # alle Seiten
 *   node pruefstand/bildschirme.mjs dashboard  # nur Namen mit "dashboard"
 */
import { chromium } from 'playwright'
import { createServer } from 'vite'
import { mkdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ADMIN, CHROMIUM, authAntwort, fehlendeFixtures, fixture, restAntwort, vergessen, vormerken } from './attrappe.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
const BILDER = join(HIER, 'bilder')
const NUR = process.argv[2] ?? ''
// Das erste Argument ist hier ein **Namensfilter**, während jeder andere
// Prüfstand des Projekts an dieser Stelle die Datenbank-URL nimmt. Wer sie aus
// Gewohnheit mitgibt, filtert auf einen Namen, den kein Bildschirm trägt — und
// die Schleife unten übersprang dann klaglos jede einzelne Aufnahme, während
// der Schlusssatz „keine Konsolenfehler" meldete. Gemessen in Runde M: 1.2
// Sekunden statt über fünf Minuten. Ein Filter, der auf nichts passt, ist
// deshalb ein Fehler des Aufrufers und kein leerer Lauf.
// Sprache der Arbeiter-Oberfläche. Ungarisch und Portugiesisch haben die
// längsten Wörter — was dort in den Rahmen passt, passt überall.
//   SPRACHE=hu node pruefstand/bildschirme.mjs auftrag
const SPRACHE = process.env.SPRACHE ?? 'de'
// Die Klickwege der Arbeiter-Masken nennen Reiter und Knöpfe über ihren
// Text-Schlüssel, nicht über das deutsche Wort — sonst liefe der Prüfstand in
// jeder anderen Sprache ins Leere. Das Wörterbuch kommt aus der App selbst,
// über den Vite-Server, sobald er steht (unten).
let T = id => id

/* ---------- Die Bildschirm-Liste ----------------------------------------- */
// Jeder Eintrag: Name, wer angemeldet ist, Pfad, und was vor dem Screenshot
// noch zu tun ist (Klicks, damit Reiter und Dialoge sichtbar werden).
/**
 * Die Auswahl eines Reiters umstellen (Runde R). *Ursachen* und
 * *Lagermanagement* haben dieselbe Filterleiste, nur ein anderes Feld:
 * `#uf` dort, `#lager-filter` hier. Welche Sorte oder Charge die Demo gerade
 * hat, weiss der Prüfstand nicht — er nimmt die erste ihrer Art, die noch Ware
 * im Haus hat. Ohne Bestand fehlen die Kaliber-Tabelle und die Glocke zu
 * Recht, und das Bild zeigte nur leere Karten.
 */
async function waehleGruppe(p, art, feldId = 'uf') {
  const feld = p.locator(`#${feldId}`)
  await feld.waitFor({ state: 'visible', timeout: 60000 })
  const werte = await p.locator(`#${feldId} option[value^="${art}|"]`).evaluateAll(
    os => os.map(o => o.value))
  if (!werte.length) throw new Error(`Filter #${feldId} hat keine Auswahl der Art „${art}"`)
  for (const wert of werte.slice(0, 12)) {
    await feld.selectOption(wert)
    await p.locator('.aktiv-filter').waitFor()
    await p.waitForTimeout(200)
    // Die Filterleiste sagt selbst, ob die Auswahl noch Ware im Haus hat:
    // „3 Chargen · 2 mit Ware im Haus". Null heisst: die nächste nehmen.
    const zeile = await p.locator('.filterleiste span', { hasText: 'mit Ware im Haus' }).first().innerText()
    if (!/·\s*0 mit Ware im Haus/.test(zeile)) return
  }
  await feld.selectOption(werte[0])
  await p.locator('.aktiv-filter').waitFor()
}

/** Tätigkeit wählen und den Plan (Runde T: vor · während · nach) bestätigen —
 *  erst dann kommt die Charge. Jeder Klickweg durch den Assistenten geht hier
 *  durch, damit ein weiterer Schritt nicht an zehn Stellen nachgetragen wird. */
const wahl = async (p, id) => {
  await p.locator(id).click()
  await p.getByRole('button', { name: T('weiter') }).click()
}

/**
 * 0121: Was die Demo von selbst nicht hat — eine Charge, die verkauft hat, ohne
 * je eine Palette zu bekommen (wie 1627 beim Betrieb), Paletten, die die App
 * mit Beleg umgebucht hat, und ein Vorschlag mit zu schwachem Beleg. Die
 * Nummern sind erfunden, damit das Bild nicht vom Stand der Fixtures abhängt.
 */
/**
 * 0125: Lieferscheine ohne Charge mit verschiedenen Gründen — die Demo hat nur
 * von Hand erfasste. Einer davon ganz (Lieferung, Import, Zeilen der Datei),
 * damit sein Fenster sagt, warum: Perigon nennt zwei Chargen, Spalte S ist 0.
 */
function ohneChargeVormerken() {
  const vorlage = (fixture('ausgang_zeile') ?? []).find(z => z.quelle === 'DEMO') ?? {}
  const tag = '2026-10-09'
  vormerken('lieferung', [{ id: 990125, datum: tag, charge_nr: null, sorte: 'Kaori Kuri', kg: 1722, kisten: null, gebindeart: null,
    ziel: 'verkauf', kunde: vorlage.kunde ?? null, erfasser: null, ts: `${tag}T08:00:00+00:00`, bemerkung: 'ohne Chargenbezug' }])
  vormerken('lieferung_import', [{ lieferung_id: 990125, quelle: 'DEMO', extern_id: 'DEMO:990125:rest', zeile_id: 990125, ts: `${tag}T08:00:00+00:00` }])
  vormerken('ausgang_zeile', ['1630', '1635'].map((nr, i) => ({ ...vorlage, id: 990125 + i, pos_id: 990125, charge_extern: nr, lauf_nr: 1,
    fingerabdruck: `bild-0125-${i}`, datum: tag, artikel: 'Bio Kürbis roter Knirps Knospe', einheit: 'kg', menge: 1722, gewicht_je_artikel: 0,
    batch_menge: 0, kg_position: 1722, kg_charge: 0, preisgruppe: 'K', liefer_label: 'K' })))
  const z = (id, x) => ({ id, datum: tag, sorte: 'Kaori Kuri', kunde: vorlage.kunde ?? null, kg: 0, quelle: 'DEMO', pos_id: id, artikel: 'Bio Kürbis roter Knirps Knospe', ...x })
  vormerken('v_lieferung_ohne_charge', [
    z(990125, { kg: 1722, nummer: '1630, 1635', grund: 'menge_null',
      satz: 'Perigon nennt die Chargen 1630, 1635, teilt aber keine Menge zu (Spalte S „AufPosBatchQuantity Charge" ist 0) — die ganze Position bleibt ohne Charge.',
      tun: 'In Perigon die Charge und die Menge je Charge (Spalten W und S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.' }),
    z(990126, { datum: '2026-10-16', kg: 288, sorte: 'Tiana', artikel: 'Bio Kürbis Butternut lose', nummer: '991977', grund: 'unbekannt',
      satz: 'Perigon nennt 991977 — diese Nummer steht an keiner Charge der App.',
      tun: 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der Lieferschein sie von selbst.' }),
    z(990127, { datum: '2026-10-18', kg: 272, nummer: '1651', grund: 'nachholen',
      satz: 'Perigon nennt 1651; die Nummer steht inzwischen an Charge 1651 — beim Einlesen kannte die App sie noch nicht.',
      tun: 'Nichts — beim nächsten Rechnen („Neu rechnen" oben) bekommt der Lieferschein die Charge von selbst.' }),
  ])
}

function ungereimtVormerken() {
  // 0122: woher die Ware wohl kam (kandidaten), eine Zuordnung über den Produzenten
  // und der Weg der Ware je Charge — herein, bearbeitet, hinaus.
  const kandidat = { charge_nr: 99126, schlag: 'Prüfschlag', sorte: 'Fictor', rest_paletten: 6, eingang_kg: 2600, geliefert_kg: 0,
    eingang_von: '2026-09-20', gleicher_schlag: true, gleiche_sorte: true }
  vormerken('v_ungereimtheit', [
    { art: 'ohne_eingang', charge_nr: 99127, sorte: 'Fictor', schlag: 'Prüfschlag', kg: 1416, n: 3, von: '2026-09-23', bis: '2026-10-05', mehr: { kandidaten: [kandidat] } },
    { art: 'nachgeordnet', charge_nr: 99129, sorte: 'Tiana', schlag: 'Prüfschlag', kg: 1650, n: 11, von: '2026-10-01', bis: '2026-10-14',
      mehr: { nummern: ['991977'], produzent: 'Prüfhof', perigon_nr: 991976,
        grund: 'Die Nummer 991977 steht an keiner Charge. Perigon nennt als Produzent Prüfhof — das ist Prüfschlag —, und Prüfschlag hat genau eine Charge mit Butternut: 99129.' } },
    { art: 'umgebucht', charge_nr: 99128, sorte: 'Fictor', schlag: 'Prüfschlag', kg: 2012, n: 6, von: '2026-09-23', bis: '2026-09-23',
      mehr: { von_charge_nr: 99126, auftrag_id: 1, grund: '5 von 5 Zetteln der Arbeit 1 (Charge 99128) ohne eigene Palette passen aufs Kilo zu Paletten von Charge 99126 (448 kg, 444 kg, 433 kg, 433 kg, 380 kg); Charge 99128 lieferte 1416 kg bei 0 kg Eingang', paletten: [1, 2, 3, 4, 5, 6], von_betriebsleiter: false } },
    { art: 'vorschlag', charge_nr: 99129, sorte: 'Tiana', schlag: 'Prüfschlag', kg: 2136, n: 6, von: '2026-08-28', bis: '2026-08-31',
      mehr: { von_charge_nr: 99125, auftrag_id: 2, grund: '6 von 8 Zetteln der Arbeit 2 (Charge 99129) ohne eigene Palette passen aufs Kilo zu Paletten von Charge 99125 (428 kg, 434 kg, 444 kg, 430 kg, 437 kg, 437 kg); Charge 99129 lieferte 7444 kg bei 4863 kg Eingang', paletten: [7, 8, 9, 10, 11, 12], von_betriebsleiter: false } },
    // Eine Perigon-Nummer an zwei Chargen — so stand 198976 bei 1649 und 1650,
    // bis der Betrieb die Liste berichtigte; seither nicht mehr in der Demo.
    { art: 'stammdaten', charge_nr: 99130, sorte: 'Butterkin', schlag: 'Prüfschlag', kg: null, n: 2, von: null, bis: null,
      mehr: { pruefung: 'perigon_doppelt', chargen_nr: [99130, 99131], perigon_nr: 991980, zeilen_mit_nummer: 4,
        chargen: [{ charge_nr: 99130, schlag: 'Prüfschlag', sorte: 'Butterkin' }, { charge_nr: 99131, schlag: 'Prüfschlag', sorte: 'Tiana' }],
        verwandte: [{ nummer: '991981', n: 11, produzent: 'Prüfhof', gruppe: 'Butternut', charge_nr: 99131 }] } },
  ])
  const spur = (charge_nr, sorte, x) => ({ charge_nr, schlag: 'Prüfschlag', sorte, artikelgruppe: sorte === 'Tiana' ? 'Butternut' : 'Knirps',
    journal_paletten: 0, journal_kg: null, journal_von: null, journal_bis: null, paletten: 0, eingang_kg: null, weg: null, her: null,
    arbeiten: 0, arbeit_von: null, arbeit_bis: null, arbeit_liste: null, lieferscheine: 0, geliefert_kg: null, lief_von: null, lief_bis: null,
    nach_artikel: null, nachgeordnet: null, rest_paletten: 0, ...x })
  vormerken('v_charge_spur', [
    spur(99125, 'Tiana', { journal_paletten: 20, journal_kg: 8600, journal_von: '2026-08-26', journal_bis: '2026-08-27', paletten: 20, eingang_kg: 8600,
      weg: [{ charge_nr: 99129, stand: 'vorschlag', paletten: 6, kg: 2136 }], arbeiten: 2, arbeit_von: '2026-09-01', arbeit_bis: '2026-09-15',
      arbeit_liste: [{ id: 3, datum: '2026-09-01', station: 'waschen', zettel: 5 }, { id: 4, datum: '2026-09-15', station: 'sortieren', zettel: 4 }],
      lieferscheine: 9, geliefert_kg: 3100, lief_von: '2026-09-02', lief_bis: '2026-10-10', nach_artikel: [{ gruppe: 'Butternut', kg: 3100 }], rest_paletten: 9 }),
    spur(99126, 'Fictor', { journal_paletten: 12, journal_kg: 4612, journal_von: '2026-09-20', journal_bis: '2026-09-22', paletten: 6, eingang_kg: 2600,
      weg: [{ charge_nr: 99128, stand: 'angewandt', paletten: 6, kg: 2012 }], rest_paletten: 6 }),
    spur(99127, 'Fictor', { arbeiten: 1, arbeit_von: '2026-09-24', arbeit_bis: '2026-09-24', arbeit_liste: [{ id: 5, datum: '2026-09-24', station: 'waschen_sortieren', zettel: 5 }],
      lieferscheine: 3, geliefert_kg: 1416, lief_von: '2026-09-23', lief_bis: '2026-10-05', nach_artikel: [{ gruppe: 'Knirps', kg: 1416 }], rest_paletten: null }),
    spur(99128, 'Fictor', { paletten: 6, eingang_kg: 2012, her: [{ charge_nr: 99126, stand: 'angewandt', paletten: 6, kg: 2012 }],
      arbeiten: 1, arbeit_von: '2026-09-23', arbeit_bis: '2026-09-23', arbeit_liste: [{ id: 1, datum: '2026-09-23', station: 'waschen_sortieren', zettel: 5 }],
      lieferscheine: 3, geliefert_kg: 1416, lief_von: '2026-09-23', lief_bis: '2026-10-05', nach_artikel: [{ gruppe: 'Knirps', kg: 1416 }], rest_paletten: 1 }),
    spur(99129, 'Tiana', { journal_paletten: 12, journal_kg: 4863, journal_von: '2026-08-28', journal_bis: '2026-08-31', paletten: 12, eingang_kg: 4863,
      her: [{ charge_nr: 99125, stand: 'vorschlag', paletten: 6, kg: 2136 }], arbeiten: 3, arbeit_von: '2026-09-02', arbeit_bis: '2026-09-22',
      arbeit_liste: [{ id: 2, datum: '2026-09-02', station: 'waschen', zettel: 8 }, { id: 6, datum: '2026-09-12', station: 'sortieren', zettel: 3 }, { id: 7, datum: '2026-09-22', station: 'waschen', zettel: 2 }],
      lieferscheine: 21, geliefert_kg: 7444, lief_von: '2026-09-02', lief_bis: '2026-10-14', nach_artikel: [{ gruppe: 'Butternut', kg: 7300 }, { gruppe: 'Kabocha', kg: 144 }],
      nachgeordnet: [{ weg: 'produzent', n: 11, kg: 1650 }], rest_paletten: 0 }),
  ])
}

/**
 * 0126: der Reiter Perigon — Fälle je Position (v_perigon_befund) wie in den
 * echten Dateien vom 12./14. Oktober (S = 0, dieselbe Zeile dreimal, eine
 * unbekannte Nummer, Mix auf einer Charge, vor dem Eingang), einer davon in
 * Abklärung, einer behoben und nicht mehr in den Daten. Erfundene Positionen,
 * damit das Bild nicht vom Stand der Demo abhängt.
 */
function perigonVormerken() {
  ungereimtVormerken()
  ohneChargeVormerken()
  const f = (art, pos, x) => ({ schluessel: `${art}:DEMO:${pos}${x.nummer ? `:${x.nummer}:1` : ''}`, art, schwere: 'gelb', quelle: 'DEMO', pos_id: pos,
    datum: '2026-10-09', kunde: 'Prüfkunde Ost', artikel: 'Bio Kürbis roter Knirps Knospe', einheit: 'kg', menge: 1722, gewicht_je_artikel: 0,
    preisgruppe: 'K', liefer_label: 'K', kg_position: 1722, kg_zugeteilt: 0, kg_rechnung: 1722, kg_ohne_charge: 1722, kg: 1722,
    nummern: null, nummer: null, lauf_nr: null, charge_nr: null, sorte: 'Kaori Kuri', n_zeilen: 1, satz: '', tun: '', wo: 'perigon',
    eingelesen: '2026-10-12T08:00:00+00:00', ...x })
  const menge = f('menge_null', 990125, { schwere: 'rot', nummern: '1630, 1635', n_zeilen: 2,
    satz: 'Perigon nennt die Chargen 1630, 1635, teilt aber keine Menge zu: Spalte S („AufPosBatchQuantity Charge") ist 0. Die Position hat 1722 kg (Spalte Q × AE) — sie bleibt ganz ohne Charge.',
    tun: 'In Perigon bei dieser Position die Menge (Spalte Q) und die Menge je Charge (Spalte S) eintragen, dann die Datei unter Betrieb → Warenausgang neu einlesen.' })
  vormerken('v_perigon_befund', [
    menge,
    f('zu_viel', 990130, { datum: '2026-10-12', artikel: 'Bio Kürbis Orangita lose', menge: 256, kg_position: 256, kg_zugeteilt: 768, kg_rechnung: 256,
      kg_ohne_charge: 0, kg: 512, nummern: '1620', charge_nr: 1620, sorte: 'Orangita', n_zeilen: 3,
      satz: 'Die Chargenzeilen geben zusammen 768 kg (Spalte S × AE), die Position nur 256 kg (Spalte Q × AE) — 512 kg zu viel. Dieselbe Zeile steht mehrfach da (Charge 1620 dreimal). Die App zählt höchstens die Position: die Charge 1620 bekommt die 256 kg der Position.',
      tun: 'In Perigon die Menge je Charge (Spalte S) berichtigen — zusammen so viel wie die Position —, eine doppelte Zeile entfernen, dann neu einlesen.' }),
    f('unbekannt', 990131, { datum: '2026-10-16', artikel: 'Bio Kürbis Butternut lose', sorte: 'Tiana', menge: 288, kg_position: 288, kg_zugeteilt: 288,
      kg_rechnung: 288, kg_ohne_charge: 288, kg: 288, nummern: '991977', nummer: '991977', lauf_nr: 1, wo: 'stammdaten',
      satz: 'Perigon nennt 991977 — diese Nummer steht an keiner Charge der App.',
      tun: 'Unter Betrieb → Stammdaten → Chargen bei der richtigen Charge als Perigon-Nr. eintragen; beim nächsten Rechnen bekommt der Lieferschein sie von selbst. Ist die Nummer ein Tippfehler, in Perigon berichtigen.' }),
    f('mix', 990132, { datum: '2026-09-30', artikel: 'Bio Kürbis Mix OS', sorte: 'Fictor', menge: 288, kg_position: 288, kg_zugeteilt: 288, kg_rechnung: 288,
      kg_ohne_charge: 0, kg: 288, nummern: '99128', nummer: '99128', lauf_nr: 1, charge_nr: 99128, wo: 'firma',
      satz: 'Verkauft als „Bio Kürbis Mix OS" auf Charge 99128 (Fictor). Ein Mix ist meist aus mehreren Sorten; die App zieht die ganzen 288 kg von 99128 ab.',
      tun: 'Bei der Firma fragen, woraus der Mix ist. Gehört er zu einer anderen Charge, in Perigon die Charge (Spalte W) berichtigen und neu einlesen; stimmt es, hier „kein Fehler" vermerken.' }),
    f('vor_eingang', 990133, { datum: '2026-08-20', artikel: 'Bio Kürbis Butternut Knospe', sorte: 'Tiana', menge: 1827, kg_position: 1827, kg_zugeteilt: 1827,
      kg_rechnung: 1827, kg_ohne_charge: 0, kg: 1827, schwere: 'rot', nummern: '99129', nummer: '99129', lauf_nr: 1, charge_nr: 99129,
      satz: 'Geliefert am 20.08.2026, aber die Charge 99129 kam laut Erntejournal erst am 28.08.2026 an (8 Tage später) — von ihr kann die Ware nicht sein.',
      tun: 'Entweder steht die falsche Charge auf dem Lieferschein (in Perigon Spalte W berichtigen) oder das Eingangsdatum im Erntejournal stimmt nicht.' }),
  ])
  // Runde BD: „wie kommst du auf 768?" — dieselbe Zeile steht dreimal in der Datei, jede mit 256 kg.
  // Die Position ganz (Zeilen, rohe Zeilen, Lieferung), damit das Fenster Zeile für Zeile nachrechnet.
  const vorlage = (fixture('ausgang_zeile') ?? []).find(z => z.quelle === 'DEMO') ?? {}
  const roh = { AufPosId: 990130, AuftragsArtId: 'kürborangl', AuftragsGebBez: 'IFCO', LiefPrsGrpName: 'K', AuftragsArtikel: 'Bio Kürbis Orangita lose',
    AuftragsJournal: 'Lieferschein', AuftragsLieferant: 'Prüfkunde Ost', AuftragsPrsGrpBez: 'K', GewichtProArtikel: 0, AuftragsLieferDatum: '12.10.2026',
    AuftragsArtikelMenge: 256, AuftragsGebindemenge: 4, AuftragsChargeManuell: '1620', AuftragsErloesTotExkl: 0, AuftragsArtikelEinheit: 'kg',
    'AufPosBatchQuantity Charge': 256 }
  vormerken('ausgang_position', [{ quelle: 'DEMO', pos_id: 990130, datum: '2026-10-12', saison: 2026, journal: 'Lieferschein', kunde: 'Prüfkunde Ost',
    artikel_id: 'kürborangl', artikel: 'Bio Kürbis Orangita lose', preisgruppe: 'K', einheit: 'kg', menge: 256, gewicht_je_artikel: 0, kg: 256,
    gebindeart: 'IFCO', gebinde_menge: 4, ts: '2026-10-12T08:00:00+00:00', roh: [roh, roh, roh] }])
  vormerken('ausgang_zeile', [1, 2, 3].map(i => ({ ...vorlage, id: 990130 + i * 10, quelle: 'DEMO', pos_id: 990130, charge_extern: '1620', lauf_nr: i,
    fingerabdruck: `bild-bd-${i}`, datum: '2026-10-12', kunde: 'Prüfkunde Ost', artikel: 'Bio Kürbis Orangita lose', einheit: 'kg', menge: 256,
    gewicht_je_artikel: 0, batch_menge: 256, kg_position: 256, kg_charge: 256, preisgruppe: 'K', liefer_label: 'K' })))
  vormerken('lieferung', [{ id: 990130, datum: '2026-10-12', charge_nr: 1620, sorte: 'Orangita', kg: 256, kisten: null, gebindeart: null,
    ziel: 'verkauf', kunde: 'Prüfkunde Ost', erfasser: null, ts: '2026-10-12T08:00:00+00:00', bemerkung: null }])
  vormerken('lieferung_import', [{ lieferung_id: 990130, quelle: 'DEMO', extern_id: 'DEMO:990130:1620:1', zeile_id: 990140, ts: '2026-10-12T08:00:00+00:00' }])
  const weg = { art: 'keine_nummer', quelle: 'DEMO', pos_id: 990120, datum: '2026-10-09', artikel: 'Bio Kürbis oranger Knirps', kg: 7,
    satz: 'In Perigon steht bei dieser Position keine Chargennummer (Spalte W „AuftragsChargeManuell" ist leer) — 7.0 kg ohne Charge.' }
  vormerken('v_perigon_verlauf', [
    { schluessel: menge.schluessel, ebene: 'zeile', art: 'menge_null', erst_gesehen: '2026-10-12T21:00:00+00:00', zuletzt_gesehen: '2026-10-24T05:00:00+00:00',
      weg_seit: null, schnappschuss: { art: 'menge_null', datum: menge.datum, artikel: menge.artikel, kg: 1722, satz: menge.satz },
      stand: 'in_abklaerung', notiz: 'Büro fragt bei der Firma nach, welche Charge wie viel bekam', vermerk_ts: '2026-10-23T09:12:00+00:00', vermerk_von: 'Alexander', n_vermerke: 1 },
    { schluessel: 'keine_nummer:DEMO:990120', ebene: 'zeile', art: 'keine_nummer', erst_gesehen: '2026-10-10T21:00:00+00:00', zuletzt_gesehen: '2026-10-20T21:00:00+00:00',
      weg_seit: '2026-10-21T05:00:00+00:00', schnappschuss: weg, stand: 'erledigt', notiz: 'in Perigon nachgetragen, Datei neu eingelesen',
      vermerk_ts: '2026-10-20T16:40:00+00:00', vermerk_von: 'Alexander', n_vermerke: 1 },
  ])
  vormerken('perigon_vermerk', [
    { id: 991, schluessel: menge.schluessel, stand: 'in_abklaerung', notiz: 'Büro fragt bei der Firma nach, welche Charge wie viel bekam',
      schnappschuss: { art: 'menge_null' }, wer: ADMIN, ts: '2026-10-23T09:12:00+00:00', profil: { name: 'Alexander' } },
    { id: 990, schluessel: 'keine_nummer:DEMO:990120', stand: 'erledigt', notiz: 'in Perigon nachgetragen, Datei neu eingelesen',
      schnappschuss: weg, wer: ADMIN, ts: '2026-10-20T16:40:00+00:00', profil: { name: 'Alexander' } },
  ])
}

const BILDSCHIRME = [
  { name: 'sprache', wer: null, pfad: '/', frisch: true },
  { name: 'anmelden', wer: null, pfad: '/' },
  { name: 'start', wer: 'arbeiter', pfad: '/' },
  // Runde AD: der Betriebsleiter (und wer die Erlaubnis hat) wählt laufende
  // Arbeiten aus und bricht sie ab — mit der Rückfrage, die genau sie nennt.
  { name: 'start-auswahl', wer: 'admin', pfad: '/',
    tun: async p => {
      await p.locator('#auswahl-an').click()
      await p.locator('.arbeit-karte .wahlkreis').first().click()
      await p.locator('#auswahl-abbrechen').click()
      await p.locator('#auswahl-abbrechen-ja').waitFor()
    } },
  // Der Assistent des Vorarbeiters, Schritt für Schritt (0060: kein Käufer, Kistensystem)
  { name: 'neu-was', wer: 'arbeiter', pfad: '/neu' },
  // Runde T: der Plan in drei Blöcken, direkt nach der Tätigkeit
  { name: 'neu-ueberblick', wer: 'arbeiter', pfad: '/neu',
    tun: async p => { await p.locator('#taet-waschen_sortieren').click() } },
  { name: 'neu-ueberblick-waschen', wer: 'arbeiter', pfad: '/neu',
    tun: async p => { await p.locator('#taet-waschen').click() } },
  { name: 'neu-charge', wer: 'arbeiter', pfad: '/neu',
    tun: async p => { await wahl(p, '#taet-waschen_sortieren'); await p.locator('#charge').fill('1613') } },
  { name: 'neu-system', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await wahl(p, '#taet-waschen_sortieren'); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
    } },
  { name: 'neu-soll', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await wahl(p, '#taet-waschen_sortieren'); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click(); await p.locator('#system-kiste_ab').click()
    } },
  { name: 'neu-stueck', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await wahl(p, '#taet-waschen_sortieren'); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click(); await p.locator('#system-stueck').click()
    } },
  { name: 'neu-baender', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await wahl(p, '#taet-sortieren'); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#baender-anpassen').click()
    } },
  // 'neu-fax' gibt es seit Runde R nicht mehr: die Fax ist eingefroren und
  // steht nicht zur Wahl. Bestehende Fax-Arbeiten (arbeit-fax-*) bleiben
  // lesbar und werden weiter aufgenommen.
  // Waschen (0054): die Bänder der Sorte wählen — oder ein eigenes Kaliber tippen
  { name: 'neu-kaliber', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await wahl(p, '#taet-waschen'); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#kaliber-0').waitFor()
    } },
  { name: 'neu-kaliber-eigen', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await wahl(p, '#taet-waschen'); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#kaliber-eigen').click()
      await p.locator('#kaliber-von').fill('700'); await p.locator('#kaliber-bis').fill('900')
    } },
  { name: 'neu-pruefen', wer: 'arbeiter', pfad: '/neu',
    tun: async p => {
      await wahl(p, '#taet-waschen_sortieren'); await p.locator('#charge').fill('1613')
      await p.getByRole('button', { name: T('weiter') }).click()
      await p.locator('#system-kiste_ab').click(); await p.getByRole('button', { name: T('weiter') }).click()
    } },
  // Die Arbeit: der Zähler sieht den Zähler, der Vorarbeiter die Checkliste
  { name: 'arbeit-zaehler', wer: 'arbeiter', pfad: '/arbeit/OFFEN' },
  { name: 'arbeit-wiegen', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.locator('#zettel').fill('2026-09-01'); await p.locator('#zettel-brutto').fill('950'); await p.locator('#zum-wiegen').click() } },
  { name: 'arbeit-kisten', wer: 'arbeiter', pfad: '/arbeit/OFFENKISTEN' },
  // Waschen (0061): Paletten aus dem Zwischenlager — Sortierdatum und Kisten je Palette
  { name: 'arbeit-wasch-paletten', wer: 'arbeiter', pfad: '/arbeit/OFFENWASCHEN' },
  { name: 'arbeit-liste', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click() } },
  { name: 'arbeit-palox', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-palox').click() } },
  { name: 'arbeit-ausgang', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-ausgang').click() } },
  // Zu klein / zu gross je Palette, am Ende der Waschstrasse mit Sortieren (0061)
  { name: 'arbeit-ausschuss', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-ausschuss').click() } },
  { name: 'arbeit-abschluss', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-abschluss').click() } },
  { name: 'arbeit-abschluss-pruefen', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => {
      await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-abschluss').click()
      await p.locator('#palox').fill('165'); await p.locator('#palox-eintragen').click()
      // Danach je Station (0061): die Wiege-Erinnerung, zu klein / zu gross,
      // die fertigen Paletten — und zuletzt die Chargenfrage. Jeder Schritt
      // wird genommen, wie er kommt; keiner ist auf jeder Station da.
      // Runde T: „Palox zwischendurch geleert?" ist ein eigener, blockierender
      // Schritt — „Weiter" bleibt grau, bis Nein oder Ja gedrückt ist. Und
      // die Gesamtzahl der fertigen Paletten ist ein Schritt mehr.
      for (let i = 0; i < 7; i++) {
        await p.locator('#aus-nichts, #geleert-nein, #charge-ja, .haupt-unten button').first().waitFor()
        if (await p.locator('#charge-ja').count()) break
        if (await p.locator('#geleert-nein').count()) { await p.locator('#geleert-nein').click(); await p.waitForTimeout(300) }
        if (await p.locator('#aus-nichts').count()) { await p.locator('#aus-nichts').click(); await p.waitForTimeout(300) }
        await p.locator('.haupt-unten button:not([disabled])').first().click()
        await p.waitForTimeout(300)
      }
      await p.locator('#charge-ja').click(); await p.getByRole('button', { name: T('weiter') }).click()
    } },
  // Fax (0051, 0060): Paletten als Gesamtzahl, Faules wiegen
  { name: 'arbeit-fax-liste', wer: 'arbeiter', pfad: '/arbeit/OFFENFAX',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click() } },
  { name: 'arbeit-fax-paletten', wer: 'arbeiter', pfad: '/arbeit/OFFENFAX' },
  { name: 'arbeit-fax-faule', wer: 'arbeiter', pfad: '/arbeit/OFFENFAX',
    tun: async p => { await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-faule').click() } },
  // Runde P: der Schritt „Paletten gesamt" im Fax-Abschluss — dort steht
  // „Tage seit dem Waschen". Der Schritt davor („Faules wiegen") wird
  // genommen, wie er kommt; er ist nicht auf jeder Fax-Arbeit da.
  //
  // Das Bild zeigt den **leeren** Fall: In der Demo liegt die letzte
  // Wasch-Arbeit dieser Charge Monate zurück, und weiter als zwei Wochen
  // zurück wird nichts vorgeschlagen (vorschlagTageSeitWaschen). Den
  // vorbelegten Fall misst die Kette (kette.mjs, sechster Durchlauf): Dort
  // ist die Wasch-Arbeit am selben Tag fertig geworden, und im Feld steht 0.
  { name: 'arbeit-fax-tage', wer: 'arbeiter', pfad: '/arbeit/OFFENFAX',
    tun: async p => {
      await p.getByRole('button', { name: T('ichFuehre') }).click(); await p.locator('#check-abschluss').click()
      for (let i = 0; i < 4 && !(await p.locator('#ab-tage').count()); i++) {
        await p.locator('.haupt-unten button:not([disabled])').first().click()
        await p.waitForTimeout(300)
      }
      await p.locator('#ab-tage').waitFor()
    } },
  // Runde V: der Palox wird mitten in der Arbeit geleert (0084) — der Knopf
  // steht in der Checkliste, sobald die Arbeit einen Palox-Stand hat; die
  // Maske fragt zuerst den Stand vor dem Leeren.
  { name: 'arbeit-palox-leeren', wer: 'arbeiter', pfad: '/arbeit/OFFEN',
    tun: async p => {
      await p.getByRole('button', { name: T('ichFuehre') }).click()
      await p.locator('#check-palox-leeren').click()
      await p.locator('#palox-vor').waitFor()
    } },
  { name: 'kontrolle', wer: 'arbeiter', pfad: '/kontrolle' },
  // Runde Q: der zweite Weg auf demselben Bildschirm — die Kontrollpalette,
  // die stehen bleibt und mehrfach gewogen wird (0072).
  { name: 'kontrolle-palette', wer: 'arbeiter', pfad: '/kontrolle',
    tun: async p => { await p.locator('#weg-kp').click(); await p.waitForTimeout(200) } },
  // Die Korrektur (Runde H): der Betriebsleiter berichtigt die Messungen einer Arbeit
  { name: 'arbeit-korrektur', wer: 'admin', pfad: '/arbeit/FERTIG?korrigieren=1' },
  // Betriebsleiter: fünf Reiter
  // Runde R: der erste Reiter ist das Lagermanagement — was liegt, wovon, in
  // welchem Kaliber, heute und in X Wochen. Die Kaliber-Tabelle und die Glocke
  // rufen `lager_kaliber(h)` und `kaliber_glocke(h)` je Stichtag; die Attrappe
  // hat dafür eigene Fixtures, damit „in 6 Wochen" nicht heute zeigt.
  { name: 'lager', wer: 'admin', pfad: '/dashboard' },
  // 0121: „so etwas wie 1627 — das hat Ausgang, aber keinen Eingang — weis in
  // der App auffällig darauf hin." 0126: oben auf dem Lager steht dafür nur noch
  // eine Zeile mit dem Weg in den Reiter Perigon („nicht oberhalb von Artikel
  // etc., sondern mach einen neuen Reiter") — die Sachen selbst prüft
  // perigon-sorten, die Zeile prüft diese Szene: sie zählt und führt hin.
  { name: 'lager-ungereimt', wer: 'admin', pfad: '/dashboard', vorher: ungereimtVormerken,
    tun: async p => {
      const leiste = p.locator('a#ungereimt.perigon-verweis')
      await leiste.waitFor()
      if (!/an \d+ Stellen nicht zusammen/.test(await leiste.innerText())) throw new Error(`die Zeile oben zählt nicht: ${await leiste.innerText()}`)
      await leiste.click()
      await p.locator('#perigon-antwort').waitFor()
    } },
  // 0122 → 0126 → Runde BD: Was war von welcher Charge — der Weg der Ware steht im
  // Reiter Perigon je Sorte für alle ihre Chargen. Seit Runde BD („er überfordert
  // gerade noch") ist jede Sorte eine Zeile, die aufklappt, und jede Sache öffnet
  // ein Fenster. Die Szene prüft dieselben Sätze und Knöpfe wie bis 0126 — nur
  // dort, wo sie jetzt stehen: die Tabelle in der aufgeklappten Sorte, die Sache
  // im Fenster. Die Sachen, die keiner Sorte gehören, prüft perigon-sache.
  { name: 'perigon-sorten', wer: 'admin', pfad: '/perigon/sorten?sorte=Fictor', vorher: perigonVormerken,
    tun: async p => {
      const fictor = p.locator('#sorte-fictor')
      if ((await fictor.locator('.perigon-art-kopf').getAttribute('aria-expanded')) !== 'true') throw new Error('die Sorte aus der Adresse ist nicht aufgeklappt')
      if (await p.locator('#sorte-tiana .sorte-tabelle').count()) throw new Error('eine andere Sorte steht schon offen — die Liste soll ruhig sein')
      await fictor.locator('.sorte-tabelle tbody tr').first().waitFor()
      const zeilen = await fictor.locator('.sorte-tabelle tbody tr').allInnerTexts()
      for (const nr of ['99126', '99127', '99128'])
        if (!zeilen.some(z => z.startsWith(nr))) throw new Error(`Fictor ohne Charge ${nr}: ${JSON.stringify(zeilen.map(z => z.slice(0, 40)))}`)
      const z127 = zeilen.find(z => z.startsWith('99127'))
      if (!z127.includes('keine Palette im Journal') || !z127.includes('3 Lieferscheine')) throw new Error(`99127: ${z127}`)
      if (!zeilen.find(z => z.startsWith('99126')).includes('→ 6 Paletten zu 99128 umgebucht')) throw new Error('99126 ohne die Umbuchung')
      await fictor.locator('.sorte-bild li', { hasText: 'ohne je eine Palette zu bekommen' }).waitFor()
      await fictor.locator('.sach-tabelle tbody tr', { hasText: 'hat verkauft, aber nie etwas bekommen' }).click()
      const f = p.locator('#sache-fenster')
      await f.locator('dd', { hasText: 'Am ehesten von 99126 (Prüfschlag · Fictor)' }).waitFor()
      await f.locator('dd', { hasText: 'Noch nicht umgebucht' }).waitFor()
      await f.locator('#fall-verfolgen').waitFor()
      await p.keyboard.press('Escape')
      await f.waitFor({ state: 'detached' })
      await fictor.locator('.sach-tabelle tbody tr', { hasText: 'zählt die App bei Charge 99128' }).click()
      await f.locator('dd', { hasText: 'Schon umgebucht' }).waitFor()
      await p.keyboard.press('Escape')
      const tiana = p.locator('#sorte-tiana')
      await tiana.locator('.perigon-art-kopf').click()
      if (!(await tiana.locator('.sorte-tabelle', { hasText: 'davon als Kabocha' }).count())) throw new Error('der fremde Artikel beim Ausgang fehlt')
      await tiana.locator('.sach-tabelle tbody tr', { hasText: 'mit der Nummer 991977' }).click()
      await f.locator('button', { hasText: 'Bei 99129 Perigon-Nr. 991977 eintragen' }).waitFor()
    } },
  // Runde BD: eine Sache je Charge aus der Arbeitsliste — dieselben Prüfungen, die
  // bis 0126 im langen Je Sorte standen (eine Perigon-Nr. an zwei Chargen).
  { name: 'perigon-sache', wer: 'admin', pfad: '/perigon/faelle?art=stammdaten', vorher: perigonVormerken,
    tun: async p => {
      const zeile = p.locator('#charge-art-stammdaten .sach-tabelle tbody tr', { hasText: 'Perigon-Nr. 991980 steht an 2 Chargen: 99130 und 99131' })
      await zeile.click()
      const f = p.locator('#sache-fenster')
      await f.locator('dd', { hasText: 'Wohl hat 99131 die Nummer 991981' }).waitFor()
      await f.locator('button', { hasText: 'Bei 99131 Perigon-Nr. 991981 eintragen' }).waitFor()
    } },
  // 0126 → Runde BD: der Reiter Perigon — „er überfordert gerade noch". Oben drei
  // Zahlen und wo zu tun ist (als Filter), darunter je Art eine Zeile, die
  // aufklappt. Bis 0126 prüfte die Szene vier Karten (was zu tun ist, je Art, je
  // Charge, die Dateien); dieselben Inhalte stehen jetzt: der Ort als Knopf, die
  // Arten als Zeilen beider Abschnitte, die Dateien unter „So prüft die App"
  // (perigon-pruefung) mit einer Zeile oben, die dorthin führt.
  { name: 'perigon', wer: 'admin', pfad: '/perigon', vorher: perigonVormerken,
    tun: async p => {
      const kz = await p.locator('#perigon-antwort .kennzahl').count()
      if (kz !== 3) throw new Error(`oben ${kz} Kennzahlen statt drei`)
      for (const wo of ['perigon', 'halle', 'stammdaten']) await p.locator(`#perigon-wo #wo-${wo}`).waitFor()
      for (const art of ['menge_null', 'zu_viel', 'unbekannt', 'mix', 'vor_eingang']) await p.locator(`#art-${art} > .perigon-art-kopf`).waitFor()
      await p.locator('#art-menge_null .perigon-art-kopf', { hasText: 'Charge ohne Menge (Spalte S = 0)' }).waitFor()
      await p.locator('#charge-art-ohne_eingang .perigon-art-kopf', { hasText: 'Verkauft, nie eingegangen' }).waitFor()
      if (await p.locator('.fall-tabelle').count()) throw new Error('die Fälle stehen schon offen — erst die Arten, dann auf Klick die Fälle')
      await p.locator('.perigon-dateien-zeile', { hasText: 'Perigon-Lieferscheine bis' }).waitFor()
      // der Ort filtert: nur Stammdaten — dann steht „Mix" (Firma fragen) nicht mehr da
      await p.locator('#wo-stammdaten').click()
      await p.locator('#wo-stammdaten[aria-pressed="true"]').waitFor()
      await p.locator('#art-mix').waitFor({ state: 'detached', timeout: 5000 }).catch(() => { throw new Error('der Ort filtert nicht') })
      await p.locator('#art-unbekannt').waitFor()
      await p.locator('#wo-stammdaten').click()
      await p.locator('#art-mix').waitFor()
      await p.locator('#art-zu_viel > .perigon-art-kopf').click()
      await p.locator('#art-zu_viel .fall-tabelle tbody tr', { hasText: '768 kg statt 256 kg' }).waitFor()
    } },
  // Runde BD: „das versteh ich nicht — wie kommst du auf 768?" Das Fenster rechnet
  // die Position Zeile für Zeile nach: dreimal Charge 1620 mit 256 kg, zusammen
  // 768 kg, die Position 256 kg, 512 kg zu viel — und die drei Zeilen der Datei.
  { name: 'perigon-fall', wer: 'admin', pfad: '/perigon/faelle?art=zu_viel', vorher: perigonVormerken,
    tun: async p => {
      await p.locator('#art-zu_viel .fall-tabelle tbody tr').first().click()
      const f = p.locator('#lieferung-fenster')
      await f.locator('#fall-kopf', { hasText: 'Die Position steht 3-mal in der Datei, jedes Mal mit Charge 1620 und 256 kg — zusammen 768 kg' }).waitFor()
      const n = f.locator('#fall-nachgerechnet')
      if ((await n.locator('tbody tr').count()) !== 3) throw new Error('nicht drei Zeilen nachgerechnet')
      if ((await n.locator('.fall-gleich').count()) !== 2) throw new Error('Zeile 2 und 3 sagen nicht, dass sie gleich wie Zeile 1 sind')
      await n.locator('tfoot tr', { hasText: '768 kg' }).waitFor()
      await n.locator('tfoot tr.fall-unterschied', { hasText: '512 kg' }).waitFor()
      await n.locator('p', { hasText: 'In der Rechnung der App: 256 kg auf Charge 1620' }).waitFor()
      if (await f.locator('#fall-excel table.excel').isVisible()) throw new Error('die Excel-Zeilen stehen offen — sie gehören hinter einen Klick')
      await f.locator('#fall-excel summary', { hasText: 'Die 3 Zeilen der Perigon-Datei' }).click()
      if ((await f.locator('#fall-excel table.excel tbody tr').count()) !== 3) throw new Error('die Datei zeigt nicht alle drei Zeilen')
      await f.locator('#fall-excel td.falsch').first().waitFor()
    } },
  // Jede Position, die nicht stimmt, nach Art; ein Klick zeigt den Fall nachgerechnet,
  // was zu tun ist und den Verlauf.
  { name: 'perigon-zeilen', wer: 'admin', pfad: '/perigon/faelle?art=menge_null&stand=alle', vorher: perigonVormerken,
    tun: async p => {
      await p.locator('#art-menge_null .fall-tabelle tbody tr').first().click()
      const f = p.locator('#lieferung-fenster')
      await f.locator('#fall-nachgerechnet', { hasText: 'Spalte S' }).waitFor()
      await f.locator('#fall-kopf', { hasText: 'aber in Spalte S steht überall 0' }).waitFor()
      await f.locator('#fall-tun', { hasText: 'In Perigon bei dieser Position' }).waitFor()
      await f.locator('#fall-verfolgen .verfolgen-liste li', { hasText: 'Büro fragt bei der Firma nach' }).waitFor()
    } },
  // Der Betriebsleiter hält fest, wie es steht — der Vermerk steht danach im Verlauf des Falls.
  { name: 'perigon-vermerken', wer: 'admin', pfad: '/perigon/faelle?art=unbekannt', vorher: perigonVormerken,
    tun: async p => {
      await p.locator('#art-unbekannt .fall-tabelle tbody tr').first().click()
      const v = p.locator('#lieferung-fenster #fall-verfolgen')
      await v.locator('#stand-erledigt').click()
      await v.locator('textarea').fill('991977 bei 99131 als Perigon-Nr. eingetragen')
      await v.locator('#fall-vermerken').click()
      await v.locator('.verfolgen-liste li', { hasText: '991977 bei 99131 als Perigon-Nr. eingetragen' }).waitFor()
    } },
  { name: 'perigon-verlauf', wer: 'admin', pfad: '/perigon/verlauf', vorher: perigonVormerken,
    tun: async p => {
      await p.locator('#perigon-vermerke tbody tr', { hasText: 'Büro fragt bei der Firma nach' }).waitFor()
      await p.locator('#perigon-weg tbody tr', { hasText: 'oranger Knirps' }).waitFor()
    } },
  { name: 'perigon-pruefung', wer: 'admin', pfad: '/perigon/pruefung',
    tun: async p => {
      // Runde BD: die Dateien stehen hier (bis 0126 auf der Übersicht).
      await p.locator('#perigon-dateien tbody tr').first().waitFor()
      await p.locator('#perigon-spalten tbody tr', { hasText: 'AufPosBatchQuantity Charge' }).waitFor()
      await p.locator('#pruefung-menge_null').waitFor()
    } },
  // 0121: vom Lager zum Verkaufsfähigen, Schritt für Schritt
  { name: 'lager-kette', wer: 'admin', pfad: '/dashboard',
    tun: async p => {
      await p.locator('#lager-kette dl.kette dt.kette-ergebnis').waitFor()
      await p.locator('#lager-kette').scrollIntoViewIfNeeded()
    } },
  // 22. Oktober: „Ötli und Trüeb … im Google Sheet sind sie drin, aber sie kommen
  // nicht in der Kürbis-App an." Eine Journalzeile, die keiner Charge zuzuordnen
  // ist, meldet der Abgleich beim Öffnen — auch wenn sonst nichts neu ist.
  // (Ein erfundener Schlag, damit das Bild nicht vom Stand der Fixtures abhängt.)
  { name: 'lager-journal-ohne-charge', wer: 'admin', pfad: '/dashboard',
    journal: ['Datum;Person;Schlag;Sorte;Gewicht brutto [kg];Anzahl Gebinde;Gebindeart (leer = G2);ID (App)',
              '20.10.2026;Hans;Neuer Schlag;Kaori Kuri;420;1;Holzpalox;pruef-j-1'].join('\n'),
    tun: async p => {
      const h = p.locator('.hinweis', { hasText: 'keiner Charge zuordnen' })
      await h.waitFor({ timeout: 15000 })
      const t = await h.innerText()
      if (!t.includes('Neuer Schlag · Kaori Kuri') || /Zeile \d+:/.test(t)) throw new Error(`Journal-Hinweis: „${t}"`)
    } },
  { name: 'lager-sorte', wer: 'admin', pfad: '/dashboard',
    tun: async p => { await waehleGruppe(p, 'sorte', 'lager-filter') } },
  { name: 'lager-charge', wer: 'admin', pfad: '/dashboard',
    tun: async p => { await waehleGruppe(p, 'charge', 'lager-filter') } },
  // Ein anderer Stichtag: die rechte Hälfte der Tabelle muss andere Zahlen
  // tragen als die linke, und der Kopf muss das Datum nennen.
  { name: 'lager-wochen', wer: 'admin', pfad: '/dashboard?wochen=6',
    tun: async p => { await p.locator('#lager-tabelle th.gruppe.spaeter').waitFor({ timeout: 60000 }) } },
  // Die Glocke am späteren Stichtag: dieselbe Kurve, nach rechts gewandert.
  { name: 'lager-glocke-wochen', wer: 'admin', pfad: '/dashboard?wochen=8',
    tun: async p => {
      const knopf = p.locator('#glocke-spaeter')
      await knopf.waitFor({ state: 'visible', timeout: 60000 })
      await knopf.click()
      await p.waitForTimeout(400)
    } },
  { name: 'ursachen', wer: 'admin', pfad: '/ursachen' },
  // Und dieselben vier Blöcke je Sorte und je Charge: die Kopfzahlen, das
  // Anteilsband und die beiden Marge-Karten sehen für eine Auswahl anders aus
  // als für alles zusammen — auch das gehört ins Bild.
  { name: 'ursachen-sorte', wer: 'admin', pfad: '/ursachen',
    tun: async p => { await waehleGruppe(p, 'sorte') } },
  { name: 'ursachen-charge', wer: 'admin', pfad: '/ursachen',
    tun: async p => { await waehleGruppe(p, 'charge') } },
  // Runde R: beide Zeitbilder tragen zwei Achsen. Das Bild „Kalender" ist der
  // neue Fall — die Punkte stehen auf dem Messtag, nicht auf der Lagerdauer.
  { name: 'ursachen-kalender', wer: 'admin', pfad: '/ursachen',
    tun: async p => {
      for (const id of ['#palox-achse-kalender', '#verd-achse-kalender']) {
        const knopf = p.locator(id)
        await knopf.waitFor({ state: 'visible', timeout: 60000 })
        await knopf.click()
      }
      await p.waitForTimeout(400)
    } },
  // Runde W: die Marge in zwei Blöcken — eine Zeile aufgeklappt zeigt die
  // Wägungen dahinter; ein Punkt im Verdunstungsbild öffnet die Arbeit.
  { name: 'ursachen-marge-auf', wer: 'admin', pfad: '/ursachen',
    tun: async p => { await p.locator('#urs-marge .marge-auf').first().click(); await p.locator('#urs-marge tr.marge-dahinter').first().waitFor() } },
  { name: 'ursachen-arbeit', wer: 'admin', pfad: '/ursachen',
    tun: async p => {
      await p.locator('#urs-verdunstung circle.marker[data-auftrag]').first().click({ force: true })
      await p.locator('#arbeit-fenster h2').waitFor()
    } },
  // Runde Y: der Kommentar zur Ware steht am Punkt der Faul-Kurve — die Demo
  // hat seit 0093 einen Hagelschaden an ihrer faulsten Sortier-Arbeit.
  { name: 'ursachen-kommentar', wer: 'admin', pfad: '/ursachen',
    tun: async p => {
      const k = (fixture('v_arbeit_kommentar') ?? []).find(k => /^Hagelschaden/.test(k.text))
      if (!k) throw new Error('v_arbeit_kommentar.json kennt keinen Hagelschaden — daten_dumpen.sh nach 0093 neu laufen lassen')
      await p.locator(`#urs-palox circle.marker[data-auftrag="${k.auftrag_id}"]`).first().hover({ force: true })
      await p.locator('.schweb', { hasText: 'Kommentar: Hagelschaden' }).waitFor()
    } },
  // Runde Z: ein Punkt öffnet die Messung — mit Arbeit das Arbeitsfenster,
  // die Messung voran; ohne Arbeit (Kontrollwägung) das Messungsfenster.
  { name: 'ursachen-punkt', wer: 'admin', pfad: '/ursachen',
    tun: async p => {
      await p.locator('#urs-palox circle.marker[data-auftrag]').first().click({ force: true })
      await p.locator('#fenster-messung .kern-wert', { hasText: 'in den Palox' }).waitFor()
      // Runde AS: im Fenster „benutzen" — ein gezählter Punkt steht angekreuzt da
      await p.locator('#messung-benutzen input:checked').waitFor()
    } },
  // Runde AS (0116): der Betriebsleiter nimmt einen Ausreisser aus der Rechnung.
  { name: 'ursachen-ausschliessen', wer: 'admin', pfad: '/ursachen',
    tun: async p => {
      await p.locator('#urs-palox circle.marker[data-auftrag]').first().click({ force: true })
      await p.locator('#messung-benutzen input').uncheck()
      await p.locator('#messung-benutzen', { hasText: 'gilt ab der nächsten Rechnung' }).waitFor()
    } },
  { name: 'ursachen-messung-ohne-arbeit', wer: 'admin', pfad: '/ursachen',
    tun: async p => {
      await p.locator('#urs-verdunstung circle.marker:not([data-auftrag])').first().click({ force: true })
      await p.locator('#messung-fenster h2', { hasText: 'Diese Wägung' }).waitFor()
      await p.locator('#messung-fenster #messung-benutzen').waitFor()
    } },
  // Runde Z: eine Sorte aufklappen, eine Charge als Fenster.
  { name: 'ursachen-charge', wer: 'admin', pfad: '/ursachen',
    tun: async p => {
      await p.locator('#urs-wohin .sorte-auf').first().click()
      await p.locator('#urs-wohin .anteil-zeile.eingerueckt').first().waitFor()
      await p.locator('#urs-wohin .anteil-zeile.eingerueckt .charge-ansehen').first().click()
      await p.locator('#charge-fenster h2', { hasText: 'Charge' }).waitFor()
      await p.locator('#charge-fenster table').first().waitFor()
    } },
  // Runde AO: die Gegenprobe der Verdunstung aus den Sortierdateien derselben Charge (v_lauf_vergleich).
  { name: 'ursachen-laeufe', wer: 'admin', pfad: '/ursachen',
    tun: async p => {
      await p.getByText('Gegenprobe: Sortierdateien derselben Charge').click()
      await p.locator('#urs-verdunstung details[open] table').waitFor()
    } },
  { name: 'chargen', wer: 'admin', pfad: '/chargen' },
  { name: 'chargen-offen', wer: 'admin', pfad: '/chargen',
    tun: async p => {
      await p.locator('tbody tr').first().click()
      // 0121: aufgeklappt steht der Weg vom Lager zum Verkaufsfähigen, Schritt für Schritt
      await p.locator('.chargentabelle .detail-kette dl.kette dt.kette-ergebnis').first().waitFor()
    } },
  // Runde AS (0116): der Hagel je Charge — die Demo hat 20 % an einer Charge;
  // ein Kreuz an einer anderen öffnet das Feld für die Prozent.
  { name: 'chargen-hagel', wer: 'admin', pfad: '/chargen',
    tun: async p => {
      await p.locator('.hagel-zelle button', { hasText: '20 %' }).first().waitFor()
      await p.locator('.hagel-zelle input[type="checkbox"]:not(:checked)').first().check()
      await p.locator('.hagel-feld input').waitFor()
    } },
  // Runde AS: eine Lieferung der geöffneten Charge als Fenster.
  { name: 'chargen-lieferung', wer: 'admin', pfad: '/chargen',
    tun: async p => {
      const mitLieferung = (fixture('erg_lieferung') ?? []).find(l => l.charge_nr != null)
      if (!mitLieferung) throw new Error('erg_lieferung.json kennt keine Lieferung mit Charge')
      await p.locator('.chargentabelle tbody tr', { hasText: String(mitLieferung.charge_nr) }).first().click()
      await p.locator('tr.klickbar[title="die ganze Zeile der Perigon-Datei zeigen"]').first().click()
      await p.locator('#lieferung-fenster #lieferung-deutung').waitFor()
    } },
  // 0121: eine Charge, bei der Perigon und Lager nicht passen — das Zeichen in
  // der Zeile, aufgeklappt die Sache und die Rechnung vom Lager zum Verkaufsfähigen.
  { name: 'chargen-ungereimt', wer: 'admin', pfad: '/chargen', vorher: ungereimtVormerken,
    tun: async p => {
      await p.locator('.chargentabelle tbody tr', { has: p.locator('.ungereimt-mal') }).first().click()
      await p.locator('.chargentabelle .ungereimt-sache').first().waitFor()
    } },
  // 0125: Lieferscheine ohne Charge — eine eigene Zeile am Ende der Chargen, aufgeklappt jeder mit dem Grund;
  // ein Klick öffnet das Fenster, und das sagt, warum.
  { name: 'chargen-ohne-charge', wer: 'admin', pfad: '/chargen', vorher: ohneChargeVormerken,
    tun: async p => {
      await p.locator('#chargen-ohne-charge').click()
      await p.locator('.ohne-charge-tabelle tbody tr').nth(2).waitFor()
      for (const name of ['Charge ohne Menge (Spalte S = 0)', 'Nummer an keiner Charge', 'von Hand erfasst'])
        await p.locator('.ohne-charge-gruende li', { hasText: name }).first().waitFor()
    } },
  { name: 'lieferung-ohne-charge', wer: 'admin', pfad: '/chargen', vorher: ohneChargeVormerken,
    tun: async p => {
      await p.locator('#chargen-ohne-charge').click()
      await p.locator('.ohne-charge-tabelle tbody tr', { hasText: 'Charge ohne Menge' }).first().click()
      await p.locator('#lieferung-fenster #lieferung-falsch', { hasText: 'Spalte S' }).waitFor()
    } },
  { name: 'chargen-ohne-eingang', wer: 'admin', pfad: '/chargen?charge=99127', vorher: ungereimtVormerken,
    tun: async p => {
      await p.locator('tr.ohne-eingang').waitFor()
      await p.locator('.chargentabelle .ungereimt-sache', { hasText: 'nie etwas bekommen' }).waitFor()
    } },
  // Runde AS: die Spaltentitel kleben, solange die Tabelle zu sehen ist —
  // halb hinausgerollt steht der Kopf oben im Bild; ist die Tabelle ganz
  // hinaus, geht er mit ihr (src/design/haftkopf.ts).
  { name: 'chargen-kopf-klebt', wer: 'admin', pfad: '/chargen',
    tun: async p => {
      await p.locator('.chargentabelle tbody tr').first().click()
      const lage = await p.evaluate(async () => {
        const warten = () => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))
        // 22. Oktober: verschoben werden die Kopfzellen, nicht der thead — gemessen wird darum eine Zelle.
        const t = document.querySelector('.chargentabelle'), k = t.querySelector('thead'), zelle = k.querySelector('th:nth-child(2)')
        window.scrollBy(0, t.getBoundingClientRect().top + t.offsetHeight / 2)
        await warten()
        // Und der Kopf liegt oben: wo seine Zelle steht, trifft ein Klick den Kopf, nicht die Zeile darunter.
        const r = zelle.getBoundingClientRect()
        const getroffen = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
        const mitten = { klebt: k.classList.contains('klebt'), oben: r.top, zuoberst: !!getroffen && k.contains(getroffen) }
        window.scrollBy(0, t.getBoundingClientRect().bottom + 200)
        await warten()
        return { mitten, danach: { unten: zelle.getBoundingClientRect().bottom, tabelle: t.getBoundingClientRect().bottom } }
      })
      if (!lage.mitten.klebt || lage.mitten.oben < -1 || lage.mitten.oben > 200) throw new Error(`Kopf der Chargentabelle klebt nicht: ${JSON.stringify(lage.mitten)}`)
      if (!lage.mitten.zuoberst) throw new Error(`Kopf der Chargentabelle liegt unter den Zeilen: ${JSON.stringify(lage.mitten)}`)
      if (lage.danach.unten > lage.danach.tabelle + 1) throw new Error(`Kopf bleibt nach der Tabelle stehen: ${JSON.stringify(lage.danach)}`)
      await p.evaluate(() => window.scrollBy(0, -(document.querySelector('.chargentabelle').getBoundingClientRect().bottom) - innerHeight / 2))
    } },
  // Runde AO: Messungen mit vier Reitern — Arbeiten (vorher unter Betrieb),
  // Auffälligkeiten, Messwerte, Ausstehend (vorher ein eigener Reiter).
  { name: 'messungen', wer: 'admin', pfad: '/messungen' },
  { name: 'messungen-auffaelligkeiten', wer: 'admin', pfad: '/messungen/auffaelligkeiten' },
  { name: 'messungen-messwerte', wer: 'admin', pfad: '/messungen/messwerte' },
  // Runde X: jede Auffälligkeit nennt ihre Arbeit und öffnet sie als Fenster.
  // Runde AS: das Fenster geht im sichtbaren Bildschirm auf, auch bei der
  // letzten Auffälligkeit unten in der langen Liste — vorher hing es an der
  // Karte (Einblend-Animation) und stand mitten in der Liste.
  { name: 'messungen-arbeit', wer: 'admin', pfad: '/messungen/auffaelligkeiten',
    tun: async p => {
      const knopf = p.getByRole('button', { name: 'Arbeit ansehen' }).last()
      await knopf.scrollIntoViewIfNeeded()
      await knopf.click()
      await p.locator('#arbeit-fenster h2').waitFor()
      const box = await p.locator('#arbeit-fenster').boundingBox()
      const hoehe = p.viewportSize().height
      if (!box || box.y < -1 || box.y > hoehe - 40) throw new Error(`Arbeitsfenster nicht im Bildschirm: y=${box?.y}, Bildschirm ${hoehe}px hoch`)
    } },
  // Runde Z: von der Auffälligkeit zur Charge.
  { name: 'messungen-charge', wer: 'admin', pfad: '/messungen/auffaelligkeiten',
    tun: async p => { await p.locator('.befund-kopf .charge-knopf').first().click(); await p.locator('#charge-fenster h2').waitFor() } },
  { name: 'messungen-arbeiten', wer: 'admin', pfad: '/messungen/arbeiten' },
  // Runde AF: je Sorte, welche Messung fehlt — seit Runde AO der vierte Reiter unter Messungen.
  { name: 'ausstehend', wer: 'admin', pfad: '/messungen/ausstehend' },
  // Runde AO (0112): das Lager nach Artikel, und je Kunde die Saison gegen die Vorjahre.
  // Runde AQ: „Wie viel ist von welchem Artikel noch da?" — je Artikel ein
  // Balken, und die Tabelle hat dieselben Zeilen.
  // 0121: eine Perigon-Zeile, die nicht stimmt — im Fenster rot umrandet, darüber in Worten.
  // 0126: Die Leiste oben auf dem Lager, über die diese Szene ging, ist eine Zeile geworden; der Weg
  // geht jetzt über die aufgeklappte Charge (1630 hat in der Demo einen Mandarin), im Reiter Perigon
  // prüft ihn perigon-zeilen.
  { name: 'lieferung-falsch', wer: 'admin', pfad: '/chargen?charge=1630',
    tun: async p => {
      const knopf = p.locator('.chargentabelle .ungereimt-sache button', { hasText: 'Perigon-Zeile' }).first()
      await knopf.click()
      await p.locator('.chargentabelle .ungereimt-zeilen button.link').first().click()
      // 0126: der angeklickte Fall steht oben in Worten, mit seiner Rechnung; darunter, was an der Zeile sonst nicht stimmt
      await p.locator('#lieferung-fenster #fall-kopf', { hasText: 'Mandarin' }).waitFor()
      await p.locator('#lieferung-fenster #lieferung-falsch', { hasText: 'In der Rechnung stehen' }).waitFor()
    } },
  { name: 'artikel', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      await p.locator('#artikel-uebersicht .uebersicht-zeile').first().waitFor()
      const balken = await p.locator('#artikel-uebersicht .uebersicht-zeile').count()
      const zeilen = await p.locator('#artikel-uebersicht-tabelle tbody tr').count()
      if (balken < 2 || balken !== zeilen) throw new Error(`Übersicht: ${balken} Balken, ${zeilen} Tabellenzeilen`)
      // Runde AR (0115): Stück, für die Perigon kein Stückgewicht kennt, stehen
      // nicht in der Linie, aber sie stehen da — die Demo hat 400 im Vorjahr.
      const stueck = (fixture('v_kunde_tag') ?? []).filter(k => k.saison === 2025).reduce((s, k) => s + Number(k.stueck_ohne_gewicht ?? 0), 0)
      if (stueck <= 0) throw new Error('v_kunde_tag.json kennt keine Stück ohne Gewicht — daten_dumpen.sh nach 0115 neu laufen lassen')
      const hinweis = await p.locator('#artikel-ohne-gewicht').innerText()
      if (!hinweis.includes(`${stueck} Stück`)) throw new Error(`Hinweis Stück ohne Gewicht: „${hinweis}" — erwartet ${stueck} Stück`)
    } },
  // Runde AS: eine Tabelle statt zwei, ohne Kisten; der Wochenregler verschiebt
  // nur sie, die Balken bleiben heute; der Balken trägt die Farben des
  // Lagermanagements nach Charge, und eine Zeile klappt ihre Chargen auf.
  { name: 'artikel-tabelle', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      await p.locator('#artikel-uebersicht-tabelle tbody tr').first().waitFor()
      if (await p.locator('#artikel-bestand').count()) throw new Error('Die zweite Tabelle „in Kisten" ist noch da')
      if (/Kisten/.test(await p.locator('#artikel-uebersicht').innerText())) throw new Error('Die Übersicht spricht noch von Kisten')
      const legende = await p.locator('.uebersicht-legende').innerText()
      // 22. Oktober: der faule Teil heisst „faul", nicht mehr „Palox" — seit
      // Oettli in Paloxen liefert, las der Betrieb ihn als Gebinde im Lager.
      for (const w of ['ausgeliefert', 'verkaufsfähig klein', 'zu klein / zu gross', 'faul', 'verdunstet'])
        if (!legende.includes(w)) throw new Error(`Legende ohne „${w}": ${legende}`)
      if (/Palox/.test(legende)) throw new Error(`Die Legende sagt noch „Palox" für das Faule: ${legende}`)
      const vorher = await p.locator('#artikel-uebersicht .uebersicht-wert strong').first().innerText()
      await p.locator('#artikel-wochen').fill('4')
      await p.locator('#artikel-uebersicht-tabelle th.gruppe', { hasText: 'in 4 Wochen' }).waitFor()
      const nachher = await p.locator('#artikel-uebersicht .uebersicht-wert strong').first().innerText()
      if (vorher !== nachher) throw new Error(`Der Balken folgt dem Wochenregler: ${vorher} → ${nachher}`)
      await p.locator('#artikel-uebersicht-tabelle tbody tr.klickbar').first().click()
      await p.locator('#artikel-uebersicht-tabelle tr.artikel-chargen table tbody tr').first().waitFor()
    } },
  // Runde AP (0113): „Wie viel Knirps klein haben wir noch, das wir als Demeter
  // verkaufen können?" — oben gewählt, die Chargen dahinter aufgeklappt.
  { name: 'artikel-knirps-klein-demeter', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      await p.locator('#artikel-gruppe').selectOption('Knirps')
      await p.locator('#artikel-groesse-klein').click()
      await p.locator('#artikel-label-d').click()
      await p.locator('#artikel-chargen-knopf').click()
      await p.locator('#artikel-chargen-wahl table tbody tr').first().waitFor()
      // Runde AQ: gewählt Knirps · Demeter — die Übersicht zeigt nur diesen einen Artikel.
      const balken = await p.locator('#artikel-uebersicht .uebersicht-zeile').count()
      if (balken !== 1) throw new Error(`Übersicht bei Knirps · Demeter: ${balken} Balken statt einem`)
      // Runde AR: die Stück ohne Gewicht sind Muscade, nicht Knirps — der Hinweis folgt der Wahl.
      if (await p.locator('#artikel-ohne-gewicht').count()) throw new Error('Bei Knirps steht der Hinweis auf Muscade-Stück ohne Gewicht')
    } },
  // … und ein Kunde allein im grossen Diagramm, per Klick in der Tabelle.
  { name: 'artikel-kunde', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      await p.locator('.kundentabelle tbody tr').first().click()
      await p.locator('.kundentabelle tbody tr.aktiv').waitFor()
    } },
  // Runde AS: die Gruppe aufgeklappt, ein Kunde gewählt, seine Lieferungen,
  // und eine davon als Fenster — die Rechnung der Masse und die ganze Zeile.
  { name: 'artikel-lieferung', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      await p.locator('.kundentabelle tbody tr.kundengruppe').first().click()
      await p.locator('.kundentabelle tbody tr.kunde-in-gruppe').first().click()
      // Runde AT: die Lieferungen stehen direkt unter dem Kunden, eingerückt in seiner Tabelle.
      await p.locator('.kundentabelle tr.kunde-in-gruppe[aria-expanded="true"] + tr.lieferungen-zeile #kunde-lieferungen tbody tr').first().waitFor()
      await p.locator('#kunde-lieferungen tbody tr', { hasText: '.2025' }).first().click()
      await p.locator('#lieferung-fenster #lieferung-deutung li').first().waitFor()
      // Runde AT: wie in Excel — die Spaltennamen sind die Kopfzeile, die Einträge die Zeile darunter
      // (bis Runde AS standen die Namen untereinander in der ersten Spalte; der Test ging mit der Regel mit).
      await p.locator('#lieferung-fenster table.excel thead th', { hasText: 'AuftragsArtikelMenge' }).waitFor()
      const form = await p.evaluate(() => {
        const t = document.querySelector('#lieferung-fenster table.excel')
        const sections = [...document.querySelectorAll('#lieferung-fenster section')].map(x => x.id)
        // Runde AT, zweiter Teil: die Spalten in der Folge der Datei (A, B, … AF), der Kopf grau wie in Excel.
        const zahl = b => [...b].reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0)
        const folge = [...t.querySelectorAll('thead th[data-spalte]')].map(th => zahl(th.dataset.spalte))
        return { kopf: t.querySelectorAll('thead tr').length, spalten: t.querySelectorAll('thead th').length,
                 zellen: t.querySelector('tbody tr').children.length, sections,
                 inFolge: folge.length >= 5 && folge.every((x, i) => i === 0 || x > folge[i - 1]),
                 erste: t.querySelector('thead th').textContent,
                 kopfGrau: getComputedStyle(t.querySelector('thead th')).backgroundColor }
      })
      if (form.kopf !== 1 || form.spalten < 5 || form.zellen !== form.spalten || form.sections[0] !== 'lieferung-zeile'
          || !form.inFolge || form.erste !== 'AuftragsJournal' || form.kopfGrau !== 'rgb(204, 204, 204)')
        throw new Error(`Perigon-Zeile nicht wie Excel: ${JSON.stringify(form)}`)
    } },
  // Runde AT: ein zweiter Klick auf den Kunden schliesst seine Lieferungen wieder.
  { name: 'artikel-lieferung-zu', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      await p.locator('.kundentabelle tbody tr.kundengruppe').first().click()
      const kunde = p.locator('.kundentabelle tbody tr.kunde-in-gruppe').first()
      await kunde.click()
      await p.locator('tr.lieferungen-zeile #kunde-lieferungen').waitFor()
      await kunde.click()
      await p.locator('tr.lieferungen-zeile').waitFor({ state: 'detached' })
    } },
  // Runde AT: ein Plan für die ganze Gruppe — er gilt für die Gruppe als Ganzes.
  { name: 'artikel-gruppenplan', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      await p.locator('.kundentabelle tr.kundengruppe .stift').first().click()
      await p.locator('.plan-feld input').fill('99000')
      await p.locator('.plan-feld button[type="submit"]').click()
      await p.locator('.kundentabelle tr.kundengruppe td.plan', { hasText: '99 t' }).first().waitFor()
      await p.locator('.kundentabelle tr.kundengruppe td.plan .zelle-unter', { hasText: 'Plan der Gruppe' }).first().waitFor()
    } },
  // Runde AT: die Reihenfolge der Gruppen — die erste eine Stelle nach unten.
  { name: 'artikel-reihenfolge', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      const erste = await p.locator('.kundentabelle tr.kundengruppe .gruppe-kopf strong').first().textContent()
      await p.locator('.kundentabelle tr.kundengruppe .reihenfolge button[aria-label$="nach unten"]').first().click()
      await p.waitForFunction(alt => document.querySelector('.kundentabelle tr.kundengruppe .gruppe-kopf strong')?.textContent !== alt, erste)
      const zweite = await p.locator('.kundentabelle tr.kundengruppe .gruppe-kopf strong').nth(1).textContent()
      if (zweite !== erste) throw new Error(`erwartet ${erste} an zweiter Stelle, steht ${zweite}`)
    } },
  // Runde AS: eine Planmenge mit dem Stift — danach steht sie fett, nicht mehr grau als Vorjahr.
  { name: 'artikel-plan', wer: 'admin', pfad: '/artikel',
    tun: async p => {
      await p.locator('.kundentabelle tbody tr.kundengruppe').first().click()
      await p.locator('.kundentabelle tr.kunde-in-gruppe .stift').first().click()
      await p.locator('.plan-feld input').fill('12500')
      await p.locator('.plan-feld button[type="submit"]').click()
      await p.locator('.kundentabelle tr.kunde-in-gruppe td.plan:not(.plan-vorjahr)', { hasText: '12.5 t' }).first().waitFor()
      await p.locator('#artikel-reicht').waitFor()
    } },
  // Runde AS: was in den Perigon-Dateien auffällt — seit 0126 nicht mehr unter
  // Artikel, sondern im Reiter Perigon (Szenen perigon, perigon-zeilen). Hier
  // bleibt nur, dass Artikel die Karte nicht mehr zeigt, wohl aber die Zeile
  // mit dem Weg dorthin.
  { name: 'artikel-perigon', wer: 'admin', pfad: '/artikel', vorher: perigonVormerken,
    tun: async p => {
      await p.locator('a#ungereimt.perigon-verweis').waitFor()
      if (await p.locator('#perigon-pruefung').count()) throw new Error('die Perigon-Karte steht noch unter Artikel')
    } },
  // Runde Z (0094): der Betriebsleiter kürzt einen ungelesenen Kommentar zur
  // Ware — erst damit steht er im Dashboard. Die Demo hat genau einen offenen;
  // seine Arbeit liegt Monate zurück, also „Ältere zeigen", bis sie da ist.
  { name: 'betrieb-kurzfassung', wer: 'admin', pfad: '/messungen/arbeiten',
    tun: async p => {
      const rm = (fixture('auftrag_rueckmeldung') ?? []).find(r => r.art === 'ware' && !r.kurz)
      if (!rm) throw new Error('auftrag_rueckmeldung.json kennt keinen ungelesenen Kommentar — daten_dumpen.sh nach 0094 neu laufen lassen')
      for (let i = 0; i < 30 && !(await p.locator(`#kurz-${rm.id}`).count()); i++) {
        while (await p.locator('button[aria-label="Rückmeldung öffnen"]').count()) {
          await p.locator('button[aria-label="Rückmeldung öffnen"]').first().click()
        }
        if (await p.locator(`#kurz-${rm.id}`).count()) break
        const aelter = p.getByRole('button', { name: /Ältere zeigen/ })
        if (!(await aelter.count())) throw new Error(`Die Arbeit ${rm.auftrag_id} mit dem ungelesenen Kommentar ist nirgends`)
        await aelter.click()
      }
      await p.locator(`.kurz-block[data-stand="offen"]`).first().waitFor()
      await p.locator(`#kurz-${rm.id}`).fill('Kleine Ware, weiche Stellen')
      await p.locator(`#kurz-speichern-${rm.id}`).click()
      await p.locator(`.kurz-block[data-stand="gekuerzt"]`, { hasText: 'Kleine Ware' }).waitFor()
    } },
  // Runde W: der Löschmodus — Kreise an den Zeilen, dann die Rückfrage.
  { name: 'betrieb-arbeiten-loeschen', wer: 'admin', pfad: '/messungen/arbeiten',
    tun: async p => {
      await p.locator('#arbeiten-loeschen').click()
      await p.locator('.wahlkreis').first().click()
      await p.locator('.wahlkreis').nth(1).click()
      await p.locator('#arbeiten-loeschen-weiter').click()
      await p.locator('#arbeiten-loeschen-ja').waitFor()
    } },
  // Runde AQ: „Erfasst" zählt alle Lieferungen — bis hier nur die neuesten 200
  // der Liste (beim Betrieb 27.7 t statt 209.7 t).
  { name: 'betrieb-lieferungen', wer: 'admin', pfad: '/betrieb/lieferungen',
    tun: async p => {
      const alle = (fixture('v_lieferung_masse') ?? []).length
      const k = p.locator('.kennzahl', { hasText: 'Lieferungen' }).first().locator('.gross-zahl')
      await k.waitFor()
      const gezeigt = Number((await k.textContent()).replace(/[’'\s]/g, ''))
      if (gezeigt !== alle) throw new Error(`„Lieferungen" zeigt ${gezeigt}, eingelesen sind ${alle}`)
    } },
  // Warenausgang einlesen (0055): die Probedatei wählen, Befund und Abgleich lesen
  { name: 'betrieb-import', wer: 'admin', pfad: '/betrieb/lieferungen',
    tun: async p => {
      // Runde AR (0115): was nicht zu den Lieferungen passt, steht oben, bevor jemand etwas wählt
      // (die Demo hat zwei solche Positionen, 0081).
      const n = (fixture('v_ausgang_pruef') ?? []).length
      if (n < 1) throw new Error('v_ausgang_pruef.json ist leer — daten_dumpen.sh nach 0115 neu laufen lassen')
      const warnung = await p.locator('#ausgang-abweichung').innerText()
      if (!warnung.includes(`${n} Positionen stimmen nicht`)) throw new Error(`Abweichung: „${warnung}" — erwartet ${n} Positionen`)
      await p.locator('#ausgang-dateien input[type=file]').setInputFiles('test/daten/warenausgang-probe.xlsx')
      await p.getByText('Bis wo hat es die Daten schon?').waitFor()
    } },
  { name: 'betrieb-csv', wer: 'admin', pfad: '/betrieb/csv' },
  { name: 'betrieb-warteschlange', wer: 'admin', pfad: '/betrieb/warteschlange' },
  { name: 'betrieb-stammdaten', wer: 'admin', pfad: '/betrieb/stammdaten' },
  // Die Demo-Karte im geladenen Zustand: neu laden und entfernen (0052).
  { name: 'betrieb-demo', wer: 'admin', pfad: '/betrieb/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Demo-Daten' }).click() } },
  // Runde Q: der Haken „Die Ernte ist eingebracht" (Q9) steht bei den Chargen.
  { name: 'betrieb-chargen', wer: 'admin', pfad: '/betrieb/stammdaten',
    // „Chargen" steht zweimal auf der Seite: in der Bereichsleiste oben und
    // im Reiter der Stammdaten. Gemeint ist der Reiter — die Bereichsleiste
    // trägt aria-label="Bereiche" und wird damit ausgeschlossen.
    tun: async p => {
      await p.locator('nav.navleiste:not([aria-label="Bereiche"])')
             .getByRole('link', { name: 'Chargen' }).click()
      await p.locator('#ernte-fertig').waitFor()
    } },
  // Runde AS: eine neue Charge anlegen (Oettli 1719) — eine schon vergebene
  // Nummer sperrt den Knopf und sagt es; eine neue mit Schlag und Sorte gibt ihn frei.
  { name: 'betrieb-charge-anlegen', wer: 'admin', pfad: '/betrieb/stammdaten',
    tun: async p => {
      await p.locator('nav.navleiste:not([aria-label="Bereiche"])').getByRole('link', { name: 'Chargen' }).click()
      await p.locator('#charge-anlegen-auf').click()
      const vorhanden = (fixture('charge') ?? [])[0]?.nr
      if (!vorhanden) throw new Error('charge.json ist leer — daten_dumpen.sh laufen lassen')
      await p.locator('#neu-nr').fill(String(vorhanden))
      await p.locator('#charge-anlegen .hinweis', { hasText: `Charge ${vorhanden} gibt es schon` }).waitFor()
      if (await p.locator('#charge-anlegen-ok').isEnabled()) throw new Error('Eine vergebene Nummer lässt sich anlegen')
      // Seit 0120 steht 1719 (Oettli) im Register: die freie Nummer kommt aus
      // dem Register selbst, nicht aus einer festen Zahl.
      const frei = Math.max(...(fixture('charge') ?? []).map(c => c.nr)) + 1
      await p.locator('#neu-nr').fill(String(frei))
      await p.locator('#neu-schlag').fill('Neuer Schlag')
      await p.locator('#neu-sorte').fill('Kaori Kuri')
      if (!(await p.locator('#charge-anlegen-ok').isEnabled())) throw new Error(`Charge ${frei} mit Schlag und Sorte lässt sich nicht anlegen`)
    } },
  // 0122: „Oettli heisst im Bio-Perigon Inauen … Trüb ist Trüeb." Die zweiten
  // Namen unter Stammdaten → Chargen; eine Perigon-Nummer an zwei Chargen ist
  // markiert — erfunden (99132 mit der Nummer von 1649), seit der Betrieb die
  // Liste berichtigt hat und 1650 die 198977 trägt.
  { name: 'betrieb-wer-wie-heisst', wer: 'admin', pfad: '/betrieb/stammdaten',
    vorher: () => {
      const c = (fixture('charge') ?? []).find(x => x.nr === 1649)
      if (c) vormerken('charge', [{ ...c, nr: 99132, schlag: 'Prüfschlag', sorte: 'Tiana' }])
    },
    tun: async p => {
      await p.locator('nav.navleiste:not([aria-label="Bereiche"])').getByRole('link', { name: 'Chargen' }).click()
      const karte = p.locator('.karte', { hasText: 'Wer wie heisst' })
      await karte.locator('td', { hasText: 'Inauen' }).first().waitFor()
      if (!(await karte.locator('tr', { hasText: 'Trüb' }).count())) throw new Error('Trüb → Trüeb fehlt')
      // Mit Fixtures von vor der Berichtigung steht dort „auch bei 1650, 99132".
      await p.locator('tr', { hasText: 'Rümlang Sauter' }).locator('.marke-klein', { hasText: /auch bei (.*, )?99132/ }).first().waitFor()
      // Seit der berichtigten Liste trägt 1650 die 198977 — dann darf dort keine doppelte mehr stehen.
      const c1650 = (fixture('charge') ?? []).find(x => x.nr === 1650)
      if (c1650?.perigon_nr === 198977
          && await p.locator('tr', { hasText: 'Rümlang Sauter' }).locator('.marke-klein', { hasText: 'auch bei 1650' }).count())
        throw new Error('1649 und 1650 tragen wieder dieselbe Perigon-Nummer')
      await karte.scrollIntoViewIfNeeded()
    } },
  { name: 'betrieb-schemata', wer: 'admin', pfad: '/betrieb/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Sortierschemata' }).click() } },
  // Runde AO (0112): welche Sorte als welcher Artikel geht, und was gross und klein heisst.
  { name: 'betrieb-artikel', wer: 'admin', pfad: '/betrieb/stammdaten',
    tun: async p => { await p.getByRole('link', { name: 'Sorten und Artikel' }).click() } },
  { name: 'betrieb-zugang', wer: 'admin', pfad: '/betrieb/zugang' },
]

const GERAETE = [
  { name: 'handy', breite: 390, hoehe: 844 },
  { name: 'desktop', breite: 1440, hoehe: 900 },
]
const THEMEN = ['light', 'dark']

if (NUR && !BILDSCHIRME.some(s => s.name.includes(NUR))) {
  console.error(`Kein Bildschirm heisst wie "${NUR}". Das erste Argument ist ein Namensfilter, `
              + `keine Datenbank-URL.\nVorhanden: ${[...new Set(BILDSCHIRME.map(s => s.name))].join(', ')}`)
  process.exit(1)
}

/* ---------- Ablauf -------------------------------------------------------- */
const vite = await createServer({
  root: join(HIER, '..'),
  server: { port: 5199, strictPort: true },
  logLevel: 'silent',
})
await vite.listen()
const { WOERTERBUCH } = await vite.ssrLoadModule('/src/lib/i18n.ts')
T = id => WOERTERBUCH[SPRACHE]?.[id] ?? WOERTERBUCH.de[id]

// Die offene Arbeit hat die höchste Auftrags-ID im Fixture — ohne Fax, denn
// dort gibt es weder Palox noch Ausschuss (0051), die Klickwege würden fehlen.
const auftraege = fixture('auftrag') ?? []
const offene = auftraege.filter(a => a.status === 'offen' && !a.abgebrochen_ts)
// Die Waschstrasse mit Sortieren (waschen_sortieren) hat alle Masken: Zettel mit
// Gewicht, Wiegen, Palox, fertige Palette — Waschen aus Kisten hat keine
// Paletten, Fax keinen Palox.
const ohneFax = offene.filter(a => !a.ist_fax)
const hand = ohneFax.filter(a => a.station === 'waschen_sortieren')
const OFFEN_ID = hand.length ? Math.max(...hand.map(a => a.id))
  : ohneFax.length ? Math.max(...ohneFax.map(a => a.id)) : offene.length ? Math.max(...offene.map(a => a.id)) : 1
// Die Kisten-Maske gibt es seit 0061 nur noch beim Sortieren: dort werden die
// gefüllten Kaliber-Kisten gezählt. Beim Waschen sind es Paletten mit
// Sortierdatum und Kistenzahl, an der Waschstrasse geht die Ware direkt raus.
const mitKisten = offene.filter(a => a.station === 'sortieren' && !a.ist_fax)
const OFFEN_KISTEN_ID = mitKisten.length ? Math.max(...mitKisten.map(a => a.id)) : OFFEN_ID
// Waschen aus dem Zwischenlager: der Palettenzähler mit Sortierdatum (0061)
const waschen = offene.filter(a => a.station === 'waschen' && !a.ist_fax)
const OFFEN_WASCHEN_ID = waschen.length ? Math.max(...waschen.map(a => a.id)) : OFFEN_ID
// Eine fertige Arbeit für die Korrektur-Ansicht des Betriebsleiters (Runde H)
const fertige = auftraege.filter(a => a.status === 'abgeschlossen' && !a.abgebrochen_ts && !a.ist_fax)
const FERTIG_ID = fertige.length ? Math.max(...fertige.map(a => a.id)) : OFFEN_ID
const faxOffen = offene.filter(a => a.ist_fax)
const OFFEN_FAX_ID = faxOffen.length ? Math.max(...faxOffen.map(a => a.id)) : OFFEN_ID

mkdirSync(BILDER, { recursive: true })
// In der Entwicklungsumgebung liegt ein fertiges Chromium unter /opt — dessen
// Version muss nicht zur Playwright-Version passen, für Screenshots genügt es.
const browser = await chromium.launch({
  executablePath: CHROMIUM,
})
let fehler = 0
let aufnahmen = 0

for (const geraet of GERAETE) {
  for (const thema of THEMEN) {
    for (const schirm of BILDSCHIRME) {
      if (NUR && !schirm.name.includes(NUR)) continue
      const kontext = await browser.newContext({
        viewport: { width: geraet.breite, height: geraet.hoehe },
        colorScheme: thema,
        locale: 'de-CH',
      })
      const seite = await kontext.newPage()
      vergessen()               // jeder Bildschirm beginnt bei den Fixtures
      const meldungen = []
      seite.on('console', m => { if (m.type() === 'error') meldungen.push(m.text()) })
      seite.on('pageerror', f => meldungen.push(String(f)))

      await seite.route('**/rest/v1/**', r => restAntwort(r).catch(() => r.abort()))
      await seite.route('**/auth/v1/**', r => authAntwort(r, schirm.wer).catch(() => r.abort()))
      await seite.route('**/storage/v1/**', r => r.fulfill({ json: {} }))
      // 22. Oktober: ein Erntejournal für den Abgleich beim Öffnen, wo der Bildschirm eines mitbringt
      if (schirm.journal) {
        vormerken('einstellung', [{ schluessel: 'journal_csv_url', wert: 'https://journal.pruefstand.test/ertragsjournal.csv' }])
        await seite.route('https://journal.pruefstand.test/**', r => r.fulfill({ status: 200, contentType: 'text/csv', body: schirm.journal }))
      }
      // 0121: Zeilen, die die Demo nicht hat (eine Charge wie 1627), vor dem Laden vormerken
      schirm.vorher?.()

      // Sprache + Anmeldung vorbereiten, bevor die App lädt
      await seite.addInitScript(({ wer, frisch, sprache }) => {
        if (frisch) { localStorage.clear(); return }
        localStorage.setItem('sprache', sprache)
        localStorage.setItem('sprache_tag', new Date().toISOString().slice(0, 10))
        if (wer) localStorage.setItem('pruefstand_wer', wer)
      }, { wer: schirm.wer, frisch: schirm.frisch ?? false, sprache: SPRACHE })

      const pfad = schirm.pfad.replace('OFFENKISTEN', String(OFFEN_KISTEN_ID))
                              .replace('OFFENWASCHEN', String(OFFEN_WASCHEN_ID))
                              .replace('OFFENFAX', String(OFFEN_FAX_ID))
                              .replace('FERTIG', String(FERTIG_ID))
                              .replace('OFFEN', String(OFFEN_ID))
      await seite.goto(`http://localhost:5199${pfad}`, { waitUntil: 'networkidle' })

      /*
       * Anmelden — warten, bis sie gegriffen hat, nicht bis das Netz ruhig ist.
       *
       * Hier stand zweimal ein Trugschluss. Zuerst `isVisible()`, das nicht
       * wartet, sondern im selben Augenblick nachsieht. Dann, nach dem ersten
       * Anlauf, ein `waitForLoadState('networkidle')` nach dem Klick — und
       * das ist das eigentliche Loch: „networkidle" heisst „seit 500 ms keine
       * Verbindung offen". Der Klick auf „Los geht's" löst aber erst einen
       * React-Zustandswechsel aus, und die Anmeldung geht danach über die
       * Leitung. Ist sie in diesem Augenblick noch nicht losgeschickt, gilt
       * das Netz als ruhig, der Prüfstand lädt die Zielseite — und die App
       * startet ohne Sitzung neu und zeigt wieder den Anmeldeschirm.
       *
       * Belegt durch das Bild des fehlgeschlagenen Laufs: Zu sehen war die
       * Anmeldeseite mit bereits eingetragenem „Tomasz". Der Name wird
       * gespeichert, *bevor* signInAnonymously() aufgerufen wird — ein
       * eingetragener Name beweist also den Klick, nicht die Anmeldung. Der
       * Klickweg suchte danach „Ich führe diese Arbeit" auf der
       * Anmeldeseite, dreissig Sekunden lang, vergeblich. Und weil es vom
       * Zufall der Zeitverhältnisse abhing, wanderte der Befund von Lauf zu
       * Lauf über verschiedene Bildschirme.
       *
       * Also auf den Beweis warten: Die Anmeldung hat gegriffen, wenn der
       * Anmeldeschirm verschwunden ist. Erst dann wird die Zielseite geladen.
       * Bleibt er stehen, ist das ein eigener Befund mit klarem Namen — und
       * nicht mehr ein rätselhafter Timeout drei Schritte später.
       */
      async function anmelden(marke, schritte, beweis) {
        try {
          await marke.waitFor({ state: 'visible', timeout: 30000 })
        } catch {
          meldungen.push('Anmeldung: der Anmeldeschirm kam nicht')
          return
        }
        await schritte()
        try {
          await beweis.waitFor({ state: 'hidden', timeout: 30000 })
        } catch {
          meldungen.push('Anmeldung: hat nicht gegriffen, der Anmeldeschirm steht noch')
          return
        }
        // 22. Oktober: Auf dem CI-Läufer lief dieser Aufruf zweimal über 30 s
        // (20.10. /neu, 22.10. /kontrolle) — lokal nicht nachzustellen, auch
        // nicht mit leerem Vite-Zwischenspeicher (1 s). Der Fehler beendete den
        // ganzen Lauf, ohne zu sagen, welcher Bildschirm. Jetzt ein zweiter
        // Versuch; scheitert auch er, ist es der Befund dieses Bildschirms.
        for (let versuch = 1; ; versuch++) {
          try {
            await seite.goto(`http://localhost:5199${pfad}`, { waitUntil: 'networkidle' })
            break
          } catch (f) {
            if (versuch >= 2) {
              meldungen.push(`Anmeldung: die Seite lud nach der Anmeldung zweimal nicht (${String(f).split('\n')[0]})`)
              return
            }
          }
        }
      }

      if (schirm.wer === 'admin') {
        const login = seite.getByRole('button', { name: 'Betriebsleiter' })
        // Der Knopf „Betriebsleiter" ist schon weg, sobald das Formular
        // aufgeht — er taugt nicht als Beweis. Das E-Mail-Feld verschwindet
        // erst, wenn die Anmeldung durch ist.
        await anmelden(login, async () => {
          await login.click()
          await seite.getByLabel('E-Mail').fill('chef@hof.test')
          await seite.getByLabel('Passwort').fill('pruefstand')
          await seite.getByRole('button', { name: 'Anmelden', exact: true }).click()
        }, seite.getByLabel('E-Mail'))
      } else if (schirm.wer === 'arbeiter') {
        const feld = seite.getByLabel(T('deinName'))
        await anmelden(feld, async () => {
          await feld.fill('Tomasz')
          await seite.getByRole('button', { name: T('losGehts') }).click()
        }, feld)
      }

      try { await schirm.tun?.(seite) } catch (f) { meldungen.push(`Klickweg: ${f}`) }
      await seite.waitForLoadState('networkidle').catch(() => {})
      await seite.waitForTimeout(800)  // Zähler und Linien sind bis dahin fertig animiert

      const datei = join(BILDER, `${schirm.name}--${geraet.name}-${thema}${SPRACHE === 'de' ? '' : `-${SPRACHE}`}.png`)
      await seite.screenshot({ path: datei, fullPage: true })
      aufnahmen++

      // Wagerechtes Überlaufen der ganzen Seite ist immer ein Fehler.
      const ueberlauf = await seite.evaluate(() =>
        document.documentElement.scrollWidth - document.documentElement.clientWidth)
      const zeile = [`${schirm.name} (${geraet.name}, ${thema})`]
      if (ueberlauf > 1) {
        fehler++
        // Wer ragt hinaus? Die ersten drei Übeltäter mit Klasse und Breite —
        // sonst sucht man den einen Pixel in 170 Bildern von Hand.
        const taeter = await seite.evaluate(() => {
          const grenze = document.documentElement.clientWidth
          return [...document.querySelectorAll('body *')]
            .filter(e => e.getBoundingClientRect().right > grenze + 1)
            .filter(e => ![...e.children].some(k => k.getBoundingClientRect().right > grenze + 1))
            .slice(0, 3)
            .map(e => `${e.tagName.toLowerCase()}${e.className && typeof e.className === 'string' ? '.' + e.className.trim().split(/\s+/).join('.') : ''}→${Math.round(e.getBoundingClientRect().right)}`)
        })
        zeile.push(`ÜBERLAUF ${ueberlauf}px (${taeter.join(', ') || 'kein Element ragt hinaus'})`)
      }
      // Runde AT: auf dem Bildschirm im Büro (1440 px) verschwindet auf den vier Hauptseiten keine
      // Spalte hinter dem Kartenrand — eine Tabelle, die dort seitlich rollen muss, ist zu breit gebaut.
      if (geraet.name === 'desktop' && ['lager', 'ursachen', 'chargen', 'artikel'].includes(schirm.name)) {
        const zuBreit = await seite.evaluate(() => [...document.querySelectorAll('.rollbar > table')]
          .filter(t => !t.closest('.dialog') && t.scrollWidth > t.parentElement.clientWidth + 1)
          .map(t => `table.${t.className.trim().split(/\s+/).slice(0, 2).join('.')} ${t.scrollWidth}/${t.parentElement.clientWidth}px`))
        if (zuBreit.length) { fehler++; zeile.push(`ZU BREIT: ${zuBreit.join(', ')}`) }
      }
      if (meldungen.length) { fehler++; zeile.push(`KONSOLE: ${meldungen[0]}`) }
      if (zeile.length > 1) console.log('  ✗ ' + zeile.join(' — '))
      await kontext.close()
    }
  }
}

await browser.close()
await vite.close()
for (const t of fehlendeFixtures) console.warn(`  ! kein Fixture für ${t} — leere Antwort`)
console.log(`Fertig: ${aufnahmen} Aufnahmen in ${BILDER}`
          + `${fehler ? ` — ${fehler} Seiten mit Konsolenfehlern oder Überlauf` : ', keine Konsolenfehler'}`)
// Ohne diese Zeile konnte der Prüfstand nichts melden: Er schrieb „✗" auf den
// Bildschirm und endete trotzdem mit null, ging also in jeder Kette der Form
// `run.sh && kette && bildschirme` stillschweigend durch.
process.exit(fehler || aufnahmen === 0 ? 1 : 0)
