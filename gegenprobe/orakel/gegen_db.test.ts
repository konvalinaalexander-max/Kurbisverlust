/**
 * Das Orakel gegen die laufende Datenbank: dieselben Zahlen, zweimal
 * gerechnet — einmal in SQL (die App), einmal hier (unabhängig). Jede
 * Abweichung ist ein Befund, und der Test sagt, in welcher Zeile und Spalte.
 *
 * Braucht eine Datenbank mit Schema und Daten (die Demo reicht):
 *   GEGENPROBE_DBNAME=demo node --test gegenprobe/orakel/gegen_db.test.ts
 * Ohne erreichbare Datenbank werden die Fälle **übersprungen und gezählt** —
 * der Läufer (gegenprobe/lauf.mjs) meldet das laut, denn ein übersprungener
 * Vergleich ist kein bestandener.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { DB_URL, bericht, dbErreichbar, frage, vergleiche } from './vergleich.ts'
import { kohorten, rueckgrat, type Palette, type Tara } from './masse.ts'
import { messung, rohwerte, type Waegung } from './verdunstung.ts'
import { schrumpfung } from './varianz.ts'
import { stroeme, summeStimmt, verkaufsfaehigAnteil, m0Zurueck, type Portion } from './kaskade.ts'
import { anpassen, anteilNachModell, type Punkt } from './schimmel.ts'
import { geliefertNichtMehrAlsEingang, kohorteGeschlossen, nichtsUnmoeglich, stroemeSummieren, zeitLaeuftVorwaerts } from './bilanz.ts'
import { nahe } from './zahlen.ts'

const skip = dbErreichbar() ? false : `keine Datenbank unter ${DB_URL}`
const n = (x: unknown) => x == null ? null : Number(x)

function gebinde(): Map<string, Tara> {
  return new Map(frage<{ art: string; k: string | null; p: string | null }>('select art, tara_kg_pro_kiste as k, tara_kg_palette as p from gebinde')
    .map(g => [g.art, { kistenKg: n(g.k), paletteKg: n(g.p) }]))
}

test('Masse: Rückgrat und Kohorten je Charge', { skip }, () => {
  const paletten = frage<Record<string, unknown>>('select id, charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart from palette')
    .map<Palette>(p => ({ id: Number(p.id), chargeNr: Number(p.charge_nr), eingangsdatum: String(p.eingangsdatum),
                          bruttoKg: n(p.brutto_kg), kisten: n(p.kisten), gebindeart: p.gebindeart == null ? null : String(p.gebindeart) }))
  const g = gebinde()
  const db = frage('select charge_nr, n_paletten, n_paletten_mit_netto, eingang_netto_kg, eingang_netto_gemessen_kg from v_charge_rueckgrat where n_paletten > 0')
  const ab = vergleiche(db, [...rueckgrat(paletten, g).values()],
    { db: a => String(a.charge_nr), orakel: b => String(b.chargeNr) },
    [{ db: 'n_paletten', orakel: 'nPaletten' }, { db: 'n_paletten_mit_netto', orakel: 'nMitNetto' },
     { db: 'eingang_netto_kg', orakel: 'eingangKg', rel: 1e-9 }, { db: 'eingang_netto_gemessen_kg', orakel: 'eingangGemessenKg', rel: 1e-9 }])
  assert.equal(ab.length, 0, bericht('v_charge_rueckgrat', ab, db.length))

  const dbK = frage('select charge_nr, eingangsdatum, n_paletten, eingang_kg, anteil from v_charge_kohorte k join v_kohorte_anteil using (charge_nr, eingangsdatum)')
  const abK = vergleiche(dbK, kohorten(paletten, g),
    { db: a => `${a.charge_nr}|${a.eingangsdatum}`, orakel: b => `${b.chargeNr}|${b.eingangsdatum}` },
    [{ db: 'n_paletten', orakel: 'nPaletten' }, { db: 'eingang_kg', orakel: 'eingangKg', abs: 0.005 }, { db: 'anteil', orakel: 'anteil', abs: 5e-7 }])
  assert.equal(abK.length, 0, bericht('v_charge_kohorte/v_kohorte_anteil', abK, dbK.length))
})

test('Verdunstung: Netto, Lagertage, Rate und verwendbar je Wägung', { skip }, () => {
  const roh = frage<Record<string, unknown>>(`
    select w.id, w.charge_nr, c.sorte, w.eingangsdatum, betriebstag(w.wiege_ts) as wiege_tag,
           w.brutto_damals_kg, w.brutto_jetzt_kg, w.kisten, w.gebindeart, w.sichtbar_schimmel, w.gemessen,
           (a.id is not null and a.abgebrochen_ts is not null) as abgebrochen
      from verdunstung_wiegung w join charge c on c.nr = w.charge_nr left join auftrag a on a.id = w.auftrag_id`)
  const g = gebinde()
  const orakel = roh.map<Waegung>(w => ({ id: Number(w.id), chargeNr: Number(w.charge_nr), sorte: String(w.sorte),
    eingangsdatum: String(w.eingangsdatum), wiegeTag: String(w.wiege_tag), bruttoDamalsKg: n(w.brutto_damals_kg),
    bruttoJetztKg: n(w.brutto_jetzt_kg), kisten: n(w.kisten), gebindeart: w.gebindeart == null ? null : String(w.gebindeart),
    sichtbarSchimmel: Boolean(w.sichtbar_schimmel), gemessen: Boolean(w.gemessen), abgebrochen: Boolean(w.abgebrochen) }))
    .map(w => messung(w, g)).map(m => ({ ...m, verwendbar: m.verwendbar ? 1 : 0 }))
  const db = frage('select id, netto_damals_kg, netto_jetzt_kg, lagertage, rate_pro_tag, verwendbar::int as verwendbar from v_verdunstung_messung')
  const ab = vergleiche(db, orakel, { db: a => String(a.id), orakel: b => String(b.id) },
    [{ db: 'netto_damals_kg', orakel: 'nettoDamalsKg', abs: 1e-6 }, { db: 'netto_jetzt_kg', orakel: 'nettoJetztKg', abs: 1e-6 },
     { db: 'lagertage', orakel: 'lagertage' }, { db: 'rate_pro_tag', orakel: 'ratePreTag', abs: 5e-7 }, { db: 'verwendbar', orakel: 'verwendbar' }])
  assert.equal(ab.length, 0, bericht('v_verdunstung_messung', ab, db.length))
})

test('Schrumpfung: Ausschuss, Nebenkanal, Fax und Verdunstung je Sorte', { skip }, () => {
  const sorten = frage<{ sorte: string }>('select sorte from sorte_kaliber').map(s => s.sorte)
  for (const [rohSicht, geschaetzt] of [['v_koeff_roh_kaliber', 'v_koeff_kaliber_geschaetzt'], ['v_koeff_roh_verdunstung', 'v_koeff_verdunstung_geschaetzt']]) {
    const roh = frage<{ art: string; sorte: string; charge_nr: string; anteil: string; gewicht: string }>(`select art, sorte, charge_nr, anteil, gewicht from ${rohSicht} where anteil is not null and gewicht > 0`)
    const db = frage(`select art, sorte, n, c_chargen, mittel_roh, varianz_roh, mittel_gesamt, tau2, b, mittel, varianz, df from ${geschaetzt}`)
    for (const art of new Set(roh.map(r => r.art))) {
      const orakel = schrumpfung(roh.filter(r => r.art === art).map(r => ({ sorte: r.sorte, chargeNr: Number(r.charge_nr), anteil: Number(r.anteil), gewicht: Number(r.gewicht) })), sorten)
        .map(s => ({ ...s, art }))
      const ab = vergleiche(db.filter(d => d.art === art), orakel,
        { db: a => `${a.art}|${a.sorte ?? '∅'}`, orakel: b => `${b.art}|${b.sorte ?? '∅'}` },
        [{ db: 'n', orakel: 'n' }, { db: 'c_chargen', orakel: 'cChargen' }, { db: 'mittel_roh', orakel: 'mittelRoh', rel: 1e-9 },
         { db: 'varianz_roh', orakel: 'varianzRoh', rel: 1e-8 }, { db: 'mittel_gesamt', orakel: 'mittelGesamt', rel: 1e-9 },
         { db: 'tau2', orakel: 'tau2', rel: 1e-8, abs: 1e-15 }, { db: 'b', orakel: 'b', rel: 1e-8 }, { db: 'mittel', orakel: 'mittel', rel: 1e-8 },
         { db: 'varianz', orakel: 'varianz', rel: 1e-8, abs: 1e-15 }, { db: 'df', orakel: 'df' }])
      assert.equal(ab.length, 0, bericht(`${geschaetzt} (${art})`, ab, orakel.length))
    }
  }
})

test('Verderbsmodell: der Fit aus mv_schimmel_punkte gegen mv_schimmel_modell', { skip }, () => {
  const punkte = frage<Record<string, unknown>>(`
    select charge_nr, lagertage as t, anteil as f, basis_jetzt_kg as w, (quelle = 'verarbeitung') as mit_sockel
      from mv_schimmel_punkte
     where plausibel and anteil > 0 and anteil < 1 and lagertage > 0 and quelle in ('verarbeitung', 'lager')`)
    .map<Punkt>(p => ({ chargeNr: Number(p.charge_nr), t: Number(p.t), f: Number(p.f), w: Number(p.w), mitSockel: Boolean(p.mit_sockel) }))
  const m = anpassen(punkte)
  const [db] = frage('select * from mv_schimmel_modell')
  assert.ok(db, 'mv_schimmel_modell hat keine Zeile')
  const paare: [string, number | null, number?][] = [
    ['n', m.n], ['c_chargen', m.cChargen], ['t_min', m.tMin], ['t_max', m.tMax], ['k', m.k, 1e-7], ['ln_lambda', m.lnLambda, 1e-7],
    ['lambda', m.lambda, 1e-7], ['x_mittel', m.xMittel, 1e-9], ['sxx', m.sxx, 1e-7], ['smearing', m.smearing, 1e-7],
    ['ln_lambda_korrigiert', m.lnLambdaKorrigiert, 1e-7], ['sigma2', m.sigma2, 1e-6], ['var_achse', m.varAchse, 1e-6],
    ['var_k', m.varK, 1e-6], ['kov_achse_k', m.kovAchseK, 1e-6], ['t_faktor', m.tFaktor], ['sockel', m.sockel],
    ['sockel_unten', m.sockelUnten], ['sockel_oben', m.sockelOben], ['sockel_nachweis', m.sockelNachweis, 1e-3],
    ['sockel_schwelle', m.sockelSchwelle, 1e-3], ['sockel_var', m.sockelVar, 1e-6],
  ]
  const ab = paare.filter(([sp, wert, rel]) => !nahe(n(db[sp]), wert, rel ?? 1e-9, 1e-9))
    .map(([sp, wert]) => `${sp}: Datenbank ${db[sp]} ≠ Orakel ${wert}`)
  assert.equal(Boolean(db.brauchbar), m.brauchbar, 'brauchbar')
  assert.deepEqual(ab, [], `mv_schimmel_modell (${punkte.length} Punkte):\n  ${ab.join('\n  ')}`)

  if (m.brauchbar) {
    const kurve = frage<{ t: string; mittel: string; unten: string; oben: string }>(
      "select t, schimmelanteil(t, 'mittel') as mittel, schimmelanteil(t, 'unten') as unten, schimmelanteil(t, 'oben') as oben from generate_series(1, 300, 7) t")
    const abK = kurve.filter(z => !nahe(Number(z.mittel), anteilNachModell(m, Number(z.t)), 1e-6, 1e-9)
                              || !nahe(Number(z.unten), anteilNachModell(m, Number(z.t), 'unten'), 1e-6, 1e-9)
                              || !nahe(Number(z.oben), anteilNachModell(m, Number(z.t), 'oben'), 1e-6, 1e-9))
    assert.deepEqual(abK, [], `schimmelanteil(t): ${abK.length} Abweichung(en) bei t = ${abK.map(z => z.t).join(', ')}`)
  }
})

test('Kaskade: Verkaufsanteil, m0 und alle Ströme je Zeile — und die Invarianten K1–K4', { skip }, () => {
  const zeilen = frage<Record<string, unknown>>(`
    select charge_nr, portion, kohorte, alter_tage, m0, m1, m2, r, f, a0, a_klein_n, a_gross_n, a_fax, verkaufsfaehig_anteil,
           verdunstung_kg, sockel_kg, schimmel_kg, klein_kg, nebenkanal_kg, fax_kg, verkaufsfaehig_kg, geliefert_kg, ueberzaehlung_kg
      from mv_kaskade`)
  assert.ok(zeilen.length > 0, 'mv_kaskade ist leer')
  const orakel = zeilen.map(z => {
    const k = { r: Number(z.r), a0: Number(z.a0), f: Number(z.f), aKlein: Number(z.a_klein_n), aGross: Number(z.a_gross_n), aFax: Number(z.a_fax) }
    const t = Number(z.alter_tage), portion = String(z.portion) as Portion
    const m0 = portion === 'lager' ? Number(z.m0) : m0Zurueck(Number(z.geliefert_kg), portion, k, t)
    const s = stroeme(m0, portion, k, t)
    return { schluessel: `${z.charge_nr}|${portion}|${z.kohorte}`, anteil: verkaufsfaehigAnteil(k, t), ...s, summeStimmt: summeStimmt(s) ? 1 : 0 }
  })
  assert.equal(orakel.filter(o => !o.summeStimmt).length, 0, 'Orakel: Ströme summieren nicht')
  const ab = vergleiche(zeilen.map(z => ({ ...z, schluessel: `${z.charge_nr}|${z.portion}|${z.kohorte}` })), orakel,
    { db: a => String(a.schluessel), orakel: b => b.schluessel },
    [{ db: 'verkaufsfaehig_anteil', orakel: 'anteil', rel: 1e-9 }, { db: 'm0', orakel: 'm0', rel: 1e-9 }, { db: 'm1', orakel: 'm1', rel: 1e-9 },
     { db: 'm2', orakel: 'm2', rel: 1e-9 }, { db: 'verdunstung_kg', orakel: 'verdunstungKg', rel: 1e-9, abs: 1e-9 },
     { db: 'sockel_kg', orakel: 'sockelKg', rel: 1e-9, abs: 1e-9 }, { db: 'schimmel_kg', orakel: 'schimmelKg', rel: 1e-9, abs: 1e-9 },
     { db: 'klein_kg', orakel: 'kleinKg', rel: 1e-9, abs: 1e-9 }, { db: 'nebenkanal_kg', orakel: 'nebenkanalKg', rel: 1e-9, abs: 1e-9 },
     { db: 'fax_kg', orakel: 'faxKg', rel: 1e-9, abs: 1e-9 }, { db: 'verkaufsfaehig_kg', orakel: 'verkaufsfaehigKg', rel: 1e-9, abs: 1e-9 }])
  assert.equal(ab.length, 0, bericht('mv_kaskade', ab, zeilen.length))

  // Wer die Ströme summiert, muss auf m0 kommen; wer die Kohorte summiert, auf ihren Eingang.
  const kohortenDb = frage('select k.charge_nr, k.eingangsdatum, b.eingang_kg * k.anteil as eingang_kg from v_kohorte_anteil k join v_kaskade_basis b using (charge_nr)')
  const verstoesse = [
    ...stroemeSummieren(zeilen), ...kohorteGeschlossen(zeilen, kohortenDb), ...geliefertNichtMehrAlsEingang(zeilen),
    ...nichtsUnmoeglich(zeilen, ['m0', 'm1', 'm2', 'verdunstung_kg', 'schimmel_kg', 'verkaufsfaehig_kg', 'geliefert_kg', 'ueberzaehlung_kg'],
                        ['r', 'f', 'a0', 'a_klein_n', 'a_gross_n', 'a_fax', 'verkaufsfaehig_anteil'], r => `${r.charge_nr}/${r.portion}/${r.kohorte}`),
  ]
  assert.deepEqual(verstoesse, [], `Invarianten verletzt:\n  ${verstoesse.slice(0, 15).map(v => `${v.regel} ${v.wo}: ${v.ist} — soll ${v.soll}`).join('\n  ')}`)
})

test('Zeit: kein plausibler Schimmelpunkt und keine Arbeit mit negativen Lagertagen (K7)', { skip }, () => {
  const punkte = frage('select charge_nr, quelle, lagertage, plausibel from mv_schimmel_punkte')
  const arbeiten = frage('select auftrag_id, station, lagertage from v_auftrag_masse')
  const v = zeitLaeuftVorwaerts(punkte, arbeiten)
  assert.deepEqual(v, [], `K7 verletzt (${v.length}):\n  ${v.map(x => `${x.wo}: ${x.ist} — soll ${x.soll}`).join('\n  ')}`)
})
