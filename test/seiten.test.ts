/**
 * AB-225: Die App hat jede Tabelle ganz — oder sagt, dass sie sie nicht hat.
 *
 * Runde BL. Der Betrieb: „Stelle sicher, dass das Programm wirklich die ganze
 * Perigon-Datei voll parat hat. Nicht, dass das Programm faul ist und nur die
 * ersten 100 anzeigt." Am 12. November im Betrieb gemessen: beim Laden von
 * „geliefert je Kunde und Tag" (7790 Zeilen, acht Seiten, nur nach dem Datum
 * geordnet) kamen 8 Zeilen doppelt und 8 fehlten.
 *
 * Geprüft wird hier die Regel (src/lib/seiten.ts) gegen eine Datenbank, die
 * sich so verhält wie die echte: bei gleichem Sortierwert ist die Reihenfolge
 * bei jeder Anfrage eine andere. Und dass keine Seite der App an der Regel
 * vorbei holt.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { alleSeiten, volleOrdnung, Unvollstaendig, type Seite } from '../src/lib/seiten.ts'

interface Zeile { kunde: string; datum: string; kg: number; mehr?: { x: number } | null }

/** 2500 Zeilen an 20 Tagen: je Tag 130 Kunden — nach dem Datum allein ist nichts eindeutig,
 *  und die Seitengrenzen (1000, 2000) liegen mitten in einem Tag. */
const TABELLE: Zeile[] = Array.from({ length: 2500 }, (_, i) => ({
  kunde: `K${String(i % 130).padStart(3, '0')}`, datum: `2026-09-${String(1 + Math.floor(i / 130)).padStart(2, '0')}`, kg: i,
}))

/** Ein fester Zufall — der Test fällt jedes Mal gleich aus. */
function zufall(saat: number) { let s = saat; return () => (s = (s * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff }

/**
 * Eine Datenbank wie die echte: geordnet wird nach dem, was verlangt ist —
 * was darin gleich ist, steht bei jeder Anfrage in anderer Reihenfolge.
 */
function datenbank(tabelle: Zeile[], opt: { zaehltNicht?: boolean; zaehltFalsch?: number } = {}) {
  const wuerfel = zufall(7)
  let anfragen = 0
  const holen = (von: number, bis: number, ordnung: [string, boolean][], zaehlen: boolean): Promise<Seite<Zeile>> => {
    anfragen++
    const gemischt = tabelle.map(z => ({ z, r: wuerfel() })).sort((a, b) => a.r - b.r).map(x => x.z)
    const sortiert = gemischt.sort((a, b) => {
      for (const [spalte, auf] of ordnung) {
        const x = a[spalte as keyof Zeile] as string | number, y = b[spalte as keyof Zeile] as string | number
        if (x !== y) return (x < y ? -1 : 1) * (auf ? 1 : -1)
      }
      return 0
    })
    return Promise.resolve({ data: sortiert.slice(von, bis + 1), error: null,
                             count: zaehlen && !opt.zaehltNicht ? tabelle.length + (opt.zaehltFalsch ?? 0) : null })
  }
  return { holen, anfragen: () => anfragen }
}

const schluessel = (z: Zeile) => `${z.datum}|${z.kunde}`

test('nur nach dem Datum geholt, gehen Zeilen verloren — der Fehler, den es gab', async () => {
  // So holte die App bis Runde BL: Seite für Seite, geordnet nach der einen Spalte.
  const db = datenbank(TABELLE)
  const naiv: Zeile[] = []
  for (let von = 0; ; von += 1000) {
    const r = await db.holen(von, von + 999, [['datum', true]], false)
    naiv.push(...(r.data ?? []))
    if ((r.data ?? []).length < 1000) break
  }
  assert.equal(naiv.length, 2500, 'die Zahl stimmt — darum fiel es nie auf')
  const verschieden = new Set(naiv.map(schluessel)).size
  assert.ok(verschieden < 2500, `es müssten Zeilen doppelt sein und andere fehlen (verschieden: ${verschieden})`)
})

test('alleSeiten holt jede Zeile genau einmal, auch wenn nur nach dem Datum geordnet werden soll', async () => {
  const db = datenbank(TABELLE)
  const alle = await alleSeiten<Zeile>(db.holen, ['datum'])
  assert.equal(alle.length, 2500)
  assert.equal(new Set(alle.map(schluessel)).size, 2500, 'keine Zeile doppelt, keine fehlt')
  assert.equal(alle.reduce((s, z) => s + z.kg, 0), TABELLE.reduce((s, z) => s + z.kg, 0), 'die Summe ist die der Tabelle')
  // die gewünschte Ordnung bleibt die erste
  for (let i = 1; i < alle.length; i++) assert.ok(alle[i - 1].datum <= alle[i].datum)
})

test('ohne gewünschte Ordnung ebenso — geordnet wird dann nach allen Spalten', async () => {
  const db = datenbank(TABELLE)
  const alle = await alleSeiten<Zeile>(db.holen)
  assert.equal(new Set(alle.map(schluessel)).size, 2500)
})

test('was in eine Anfrage passt, kostet eine Anfrage', async () => {
  const db = datenbank(TABELLE.slice(0, 300))
  const alle = await alleSeiten<Zeile>(db.holen, [['datum', false]])
  assert.equal(alle.length, 300)
  assert.equal(db.anfragen(), 1)
})

test('genau eine volle Seite: nur die Zählung sagt, dass es alles ist — ohne sie wird weitergefragt', async () => {
  const gezaehlt = datenbank(TABELLE.slice(0, 1000))
  assert.equal((await alleSeiten<Zeile>(gezaehlt.holen)).length, 1000)
  assert.equal(gezaehlt.anfragen(), 2, 'tausend geholt, dann gezählt: tausend — fertig')
  const ohne = datenbank(TABELLE.slice(0, 1000), { zaehltNicht: true })
  assert.equal((await alleSeiten<Zeile>(ohne.holen)).length, 1000)
  assert.ok(ohne.anfragen() >= 3, 'ohne Zählung: die Seiten bis zur leeren, nicht angenommen, das sei alles')
})

test('ohne Zählung (eine Schnittstelle, die keine gibt) kommt trotzdem jede Zeile genau einmal', async () => {
  const db = datenbank(TABELLE, { zaehltNicht: true })
  const alle = await alleSeiten<Zeile>(db.holen, ['datum'])
  assert.equal(new Set(alle.map(schluessel)).size, 2500)
})

test('stimmt die Zahl der geholten Zeilen nicht mit der gezählten, ist das ein Fehler — keine stille Lücke', async () => {
  const db = datenbank(TABELLE, { zaehltFalsch: 3 })
  await assert.rejects(alleSeiten<Zeile>(db.holen, ['datum']), (f: unknown) => {
    assert.ok(f instanceof Unvollstaendig)
    assert.equal(f.geholt, 2500)
    assert.equal(f.gezaehlt, 2503)
    assert.match(f.message, /2500 von 2503/)
    return true
  })
  assert.ok(db.anfragen() >= 8, 'einmal von vorn geholt, bevor es ein Fehler ist')
})

test('der Fehler der Datenbank kommt an, wie er ist (die Seiten lesen seinen Code)', async () => {
  const fehler = { message: 'materialized view "erg_charge" has not been populated', code: '55000' }
  await assert.rejects(alleSeiten<Zeile>(() => Promise.resolve({ data: null, error: fehler })), (f: unknown) => f === fehler)
})

test('volleOrdnung: zuerst das Gewünschte, dann alle einfachen Spalten — Listen und Objekte nicht', () => {
  const o = volleOrdnung([['datum', false]], { kunde: 'a', datum: 'd', kg: 1, mehr: { x: 1 }, leer: null, liste: [1] })
  assert.deepEqual(o, [['datum', false], ['kg', true], ['kunde', true], ['leer', true]])
})

/* ---------- Keine Seite holt an der Regel vorbei -------------------------------- */

function dateien(pfad: string): string[] {
  return readdirSync(pfad).flatMap(n => {
    const p = join(pfad, n)
    return statSync(p).isDirectory() ? dateien(p) : /\.tsx?$/.test(n) ? [p] : []
  })
}
const SRC = join(process.cwd(), 'src')
const quelltext = dateien(SRC).map(p => ({ p: p.replace(SRC, 'src'), text: readFileSync(p, 'utf8') }))

test('seitenweise holt nur lib/db.ts (alleLesen) — nirgends sonst steht .range(', () => {
  const treffer = quelltext.filter(d => /\.range\(/.test(d.text) && d.p !== 'src/lib/db.ts').map(d => d.p)
  assert.deepEqual(treffer, [])
})

test('eine Obergrenze gibt es nur, wo die Seite „die neusten" oder „die nächsten" sagt', () => {
  // Erlaubt, mit Grund — alles andere holt alleLesen:
  const ERLAUBT: Record<string, number> = {
    'src/arbeit/Abschluss.tsx': 1,     // die letzte Ablesung
    'src/pages/NeueArbeit.tsx': 1,     // die neuste Sortierdatei
    'src/pages/Kontrolle.tsx': 5,      // „die nächsten fünf Vorschläge", so heisst die Liste
    'src/pages/CsvUpload.tsx': 15,     // „Zuletzt eingelesen", so heisst die Karte
  }
  const treffer: string[] = []
  for (const d of quelltext) {
    for (const m of d.text.matchAll(/\.limit\(\s*([^)]*)\)/g)) {
      if (/^\s*\*|^\s*\/\//.test(d.text.slice(d.text.lastIndexOf('\n', m.index) + 1, m.index))) continue   // im Kommentar
      const n = Number(m[1])
      if (!(d.p in ERLAUBT) || !Number.isInteger(n) || n > ERLAUBT[d.p]) treffer.push(`${d.p}: .limit(${m[1]})`)
    }
  }
  assert.deepEqual(treffer, [])
})
