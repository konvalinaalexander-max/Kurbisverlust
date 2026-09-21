import { test } from 'node:test'
import assert from 'node:assert/strict'
import { csvReinigen, reinigen, werteLesen, trichter, masseKg, REINIGUNG_STANDARD,
         histogrammAbziehen, deltaTrichter } from '../src/lib/csv.ts'
import { dateinamenLesen, jahrFuerMonat } from '../src/lib/dateiname.ts'

const CHARGEN = [1598, 1613, 1614, 1651]

test('liest eine Zahl je Zeile, ignoriert Leerzeilen', () => {
  const { werte, unlesbar } = werteLesen('600\n800\n\n1000\r\n')
  assert.deepEqual(werte, [600, 800, 1000])
  assert.equal(unlesbar, 0)
})

test('zählt unlesbare Zeilen, statt sie stillschweigend zu verlieren', () => {
  const { werte, unlesbar } = werteLesen('600\nGewicht\n800')
  assert.deepEqual(werte, [600, 800])
  assert.equal(unlesbar, 1)
})

test('verwirft Overflow-Werte ab 60000 (16-Bit-Unterlauf)', () => {
  const e = reinigen([600, 65534, 65400, 800])
  assert.equal(e.n_overflow, 2)
  assert.equal(e.n_gueltig, 2)
})

test('verwirft Werte unter 100 g', () => {
  const e = reinigen([600, 98, 2, 800])
  assert.equal(e.n_klein, 2)
  assert.equal(e.n_gueltig, 2)
})

test('fasst direkte Dubletten zusammen, auch Dreier', () => {
  const e = reinigen([600, 600, 800, 900, 900, 900])
  assert.equal(e.n_dubletten, 3)
  assert.deepEqual(e.histogramm, [[600, 1], [800, 1], [900, 1]])
})

test('gleiche Werte an nicht benachbarten Stellen bleiben erhalten', () => {
  // Zwei verschiedene Kürbisse dürfen zufällig gleich schwer sein — nur der
  // Doppel-Trigger der Maschine liefert sie direkt hintereinander.
  const e = reinigen([600, 800, 600])
  assert.equal(e.n_dubletten, 0)
  assert.deepEqual(e.histogramm, [[600, 2], [800, 1]])
})

test('Dubletten-Regel lässt sich abschalten', () => {
  const e = reinigen([600, 600], { ...REINIGUNG_STANDARD, dubletten_zusammenfassen: false })
  assert.equal(e.n_dubletten, 0)
  assert.deepEqual(e.histogramm, [[600, 2]])
})

test('der Trichter geht immer auf', () => {
  const e = csvReinigen(['600', '600', '65534', '50', '900', '900', '900', '1200'].join('\n'))
  assert.equal(e.n_roh - e.n_overflow - e.n_klein - e.n_dubletten, e.n_gueltig)
  assert.match(trichter(e), /8 gelesen.*3 Kürbisse/)
})

test('das Histogramm verliert keine Masse', () => {
  const e = reinigen([600, 800, 1200])
  assert.equal(masseKg(e.histogramm), 2.6)
})

test('erkennt den Standard-Dateinamen', () => {
  const r = dateinamenLesen('1614-25-08-11-10.csv', CHARGEN, 2026)
  assert.equal(r.chargeNr, 1614)
  assert.equal(r.quelle, 'dateiname')
  assert.equal(r.zeit?.getFullYear(), 2026)
  assert.equal(r.zeit?.getMonth(), 7)
  assert.equal(r.zeit?.getDate(), 25)
  assert.equal(r.zeit?.getHours(), 11)
})

test('toleriert andere Trenner und Pfade', () => {
  for (const name of ['1614_25_08_11_10', '1614 25.08 11.10', 'C:\\daten\\1614/25/08/11/10.CSV']) {
    const r = dateinamenLesen(name, CHARGEN, 2026)
    assert.equal(r.chargeNr, 1614, name)
    assert.equal(r.zeit?.getDate(), 25, name)
  }
})

test('nimmt nur Nummern, die es wirklich gibt', () => {
  const r = dateinamenLesen('9999-25-08-11-10', CHARGEN, 2026)
  assert.equal(r.chargeNr, null)
  assert.match(r.hinweis!, /Keine bekannte Chargennummer/)
})

/* ---- Runde U: zwei Arten von Datei ---------------------------------- */

test('das Format ab Oktober 2026 — Charge, Tag, Monat, Jahr', () => {
  const r = dateinamenLesen('1614_07_10_26.csv', CHARGEN, 2026)
  assert.equal(r.art, 'lauf')
  assert.equal(r.chargeNr, 1614)
  assert.equal(r.quelle, 'dateiname')
  assert.equal(r.zeit?.getFullYear(), 2026)
  assert.equal(r.zeit?.getMonth(), 9)      // Oktober
  assert.equal(r.zeit?.getDate(), 7)
})

test('jeder Trenner, ein- wie zweistellig, zwei- wie vierstelliges Jahr', () => {
  for (const name of ['1614.07.10.26', '1614 7 10 26', '1614-07-10-2026', '1614/07/10/26',
                      '1614_7_10_2026.CSV']) {
    const r = dateinamenLesen(name, CHARGEN, 2026)
    assert.equal(r.art, 'lauf', name)
    assert.equal(r.chargeNr, 1614, name)
    assert.equal(r.zeit?.getDate(), 7, name)
    assert.equal(r.zeit?.getMonth(), 9, name)
    assert.equal(r.zeit?.getFullYear(), 2026, name)
  }
})

test('mit Uhrzeit dahinter: Tag, Monat, Jahr, Stunde, Minute', () => {
  const r = dateinamenLesen('1614_7_10_26_14_35', CHARGEN, 2026)
  assert.equal(r.zeit?.getHours(), 14)
  assert.equal(r.zeit?.getMinutes(), 35)
})

test('nur die Chargennummer heisst Sammeldatei — kein Mangel, die zweite Art', () => {
  for (const name of ['1614.csv', '1614', 'Sortierung 1614.csv']) {
    const r = dateinamenLesen(name, CHARGEN, 2026, Date.UTC(2026, 9, 20, 9, 0))
    assert.equal(r.art, 'sammel', name)
    assert.equal(r.chargeNr, 1614, name)
    assert.equal(r.zeit, null, name)
    assert.equal(r.hinweis, null, name)
  }
})

test('der Zeitstempel der Datei ist kein Sortierdatum mehr, nur noch eine Schranke', () => {
  // Bis Runde U wurde er still als Zeitpunkt des Laufs eingetragen. Bei einer
  // Sammeldatei ist er der Zeitpunkt des letzten Anhängens — für die Kürbisse
  // vom ersten Tag also Wochen zu spät.
  const r = dateinamenLesen('1614.csv', CHARGEN, 2026, Date.UTC(2026, 9, 20, 9, 0))
  assert.equal(r.zeit, null)
  assert.equal(r.quelle, null)
  assert.equal(r.spaetestens?.getTime(), Date.UTC(2026, 9, 20, 9, 0))
})

test('ein unmögliches Datum wird benannt, nicht stillschweigend verschoben', () => {
  // new Date(2026, 1, 31) wäre der 3. März — ein erfundenes Datum.
  const r = dateinamenLesen('1614_31_02_26', CHARGEN, 2026)
  assert.equal(r.art, 'sammel')
  assert.match(r.hinweis!, /gibt es nicht/)
})

test('ein Jahr weit weg von der Saison ist ein Tippfehler, keine Angabe', () => {
  const r = dateinamenLesen('1614_07_10_11', CHARGEN, 2026)
  assert.equal(r.art, 'sammel')
  assert.match(r.hinweis!, /2011/)
})

/* ---- Runde U: das Delta einer wachsenden Datei ----------------------- */

test('die Reinigung ist präfixstabil — darum genügt eine Subtraktion', () => {
  // Genau diese Eigenschaft trägt die ganze Sammeldatei-Lösung: Das
  // Histogramm der gewachsenen Datei ist punktweise nie kleiner als das
  // des Präfixes. Ohne sie wäre das Delta nicht bestimmbar.
  const zufall = (n: number, saat: number) => {
    let s = saat; const a: number[] = []
    for (let i = 0; i < n; i++) {
      s = (s * 1103515245 + 12345) % 2147483648
      const w = 300 + (s % 1200)
      a.push(w)
      if (s % 5 === 0) a.push(w)          // Doppel-Trigger der Maschine
    }
    return a
  }
  const P = zufall(400, 7), S = zufall(300, 99)
  const rP = reinigen(P), rPS = reinigen(P.concat(S)), rS = reinigen(S)
  assert.equal(rPS.n_gueltig - rP.n_gueltig, rS.n_gueltig)
  const d = histogrammAbziehen(rPS.histogramm, rP.histogramm)
  assert.deepEqual(d.negativ, [])
  assert.equal(d.n_neu, rS.n_gueltig)
})

test('das Delta ist, was dazukam — und der Rest zählt nicht noch einmal', () => {
  const d = histogrammAbziehen([[500, 3], [600, 4], [700, 1]], [[500, 3], [600, 2]])
  assert.deepEqual(d.delta, [[600, 2], [700, 1]])
  assert.equal(d.n_neu, 3)
  assert.equal(d.n_bekannt, 5)
  assert.deepEqual(d.negativ, [])
})

test('eine bearbeitete Datei wird erkannt, statt halb übernommen zu werden', () => {
  // Aus der Datei wurde etwas herausgelöscht: eine Stufe wird negativ.
  const d = histogrammAbziehen([[500, 2], [600, 4]], [[500, 3], [600, 2], [700, 1]])
  assert.deepEqual(d.negativ, [[500, 1], [700, 1]])
})

test('dieselbe Datei noch einmal bringt nichts Neues', () => {
  const h: [number, number][] = [[500, 3], [600, 2]]
  const d = histogrammAbziehen(h, h)
  assert.equal(d.n_neu, 0)
  assert.deepEqual(d.delta, [])
  assert.deepEqual(d.negativ, [])
})

test('der Delta-Trichter sagt, was in der Datei steht und was davon neu ist', () => {
  const d = histogrammAbziehen([[500, 3], [600, 4]], [[500, 3]])
  assert.equal(deltaTrichter(d), '7 in der Datei → 3 schon bekannt → 4 neu')
})

test('ein Januar-Lauf gehört zur Saison des Vorjahres', () => {
  assert.equal(jahrFuerMonat(8, 2026), 2026)
  assert.equal(jahrFuerMonat(1, 2026), 2027)
  const r = dateinamenLesen('1613-15-01-08-30', CHARGEN, 2026)
  assert.equal(r.zeit?.getFullYear(), 2027)
})
