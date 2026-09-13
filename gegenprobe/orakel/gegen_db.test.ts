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
import { huelle, standNachTagen, summeStimmtPrognose, summieren, verlustAb, zerlegungStimmt,
         type LagerPortion, type Raender, type Teil } from './prognose.ts'
import { klemm, nahe } from './zahlen.ts'

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
  const arbeiten = frage('select auftrag_id, station, charge_nr, lagertage from v_auftrag_masse')
  const geflaggt = new Set(frage("select distinct charge_nr from v_plausibilitaet where art = 'Zetteldatum Zukunft'").map(r => String(r.charge_nr)))
  const v = zeitLaeuftVorwaerts(punkte, arbeiten, geflaggt)
  assert.deepEqual(v, [], `K7 verletzt (${v.length}):\n  ${v.map(x => `${x.wo}: ${x.ist} — soll ${x.soll}`).join('\n  ')}`)
})

/* ===================== Runde P: die Prognose und die Zerlegung ============ */

/** Die Koeffizienten-Ränder je Sorte, mit denselben Klammern wie v_prognose. */
function raenderJeSorte(): Map<string, Raender> {
  const lies = (sicht: string, deckel: number) =>
    new Map(frage<{ sorte: string; unten: string | null; oben: string | null }>(
      `select sorte, unten, oben from ${sicht}`)
      .map(r => [r.sorte, { unten: klemm(Number(r.unten ?? 0) || 0, 0, deckel),
                            oben:  klemm(Number(r.oben  ?? 0) || 0, 0, deckel) }]))
  const kv = lies('v_koeff_verdunstung', 0.05), ka = lies('v_koeff_ausschuss', 1)
  const kn = lies('v_koeff_nebenkanal', 1),     kf = lies('v_koeff_fax', 1)
  const leer = { unten: 0, oben: 0 }
  const sorten = frage<{ sorte: string }>('select distinct sorte from v_kaskade_basis').map(s => s.sorte)
  return new Map(sorten.map(s => {
    const v = kv.get(s) ?? leer, a = ka.get(s) ?? leer, g = kn.get(s) ?? leer, f = kf.get(s) ?? leer
    return [s, { rUnten: v.unten, rOben: v.oben, a0Unten: 0, a0Oben: 0,
                 kleinUnten: a.unten, kleinOben: a.oben, grossUnten: g.unten, grossOben: g.oben,
                 faxUnten: f.unten, faxOben: f.oben }]
  }))
}

test('K8 — v_prognose: dieselbe Kaskade, ein paar Wochen später', { skip }, () => {
  const portionen = frage<Record<string, unknown>>(`
    select charge_nr, sorte, schlag, kohorte, alter_tage, m0, r, a0, a_klein_n, a_gross_n, a_fax,
           r_bekannt, f_bekannt, a0_bekannt, a_klein_bekannt, a_gross_bekannt, a_fax_bekannt, modell_gilt
      from mv_kaskade
     where portion = 'lager' and m0 > 0 and alter_tage >= 0`)
  assert.ok(portionen.length > 0, 'mv_kaskade hat keine liegende Portion — die Prüfung trägt nicht')
  const horizonte = frage<{ h: string }>('select distinct h from v_prognose order by h').map(z => Number(z.h))
  assert.ok(horizonte.length >= 3, `v_prognose hat nur ${horizonte.length} Horizont(e)`)

  // F(t) kommt aus schimmelanteil() — die Formel selbst prüft das Verderbsmodell-Orakel.
  const alter = [...new Set(portionen.map(p => Number(p.alter_tage)))]
  const tWerte = [...new Set(alter.flatMap(a => horizonte.map(h => Math.trunc(a + h))))].sort((x, y) => x - y)
  const f = new Map(frage<{ t: string; m: string; u: string; o: string }>(`
    select t, schimmelanteil(t, 'mittel') as m, schimmelanteil(t, 'unten') as u, schimmelanteil(t, 'oben') as o
      from unnest(array[${tWerte.join(',')}]::numeric[]) t`)
    .map(z => [Number(z.t), { m: Number(z.m), u: Number(z.u), o: Number(z.o) }]))

  const raender = raenderJeSorte()
  const [m] = frage<Record<string, unknown>>('select brauchbar, sockel, sockel_unten, sockel_oben, t_max from mv_schimmel_modell')
  const a0Unten = m && Boolean(m.brauchbar) ? Number(m.sockel_unten ?? m.sockel ?? 0) : 0
  const a0Oben  = m && Boolean(m.brauchbar) ? Number(m.sockel_oben  ?? m.sockel ?? 0) : 0
  const tMax = m?.t_max == null ? Infinity : Number(m.t_max)

  // Je Portion und Horizont ein Teil; dann über die vier Gruppenebenen rollen.
  const teileJeZeile = new Map<string, Teil[]>()
  for (const z of portionen) {
    const p: LagerPortion = { chargeNr: Number(z.charge_nr), kohorte: String(z.kohorte),
      alterTage: Number(z.alter_tage), m0: Number(z.m0), r: Number(z.r), a0: Number(z.a0),
      aKleinN: Number(z.a_klein_n), aGrossN: Number(z.a_gross_n), aFax: Number(z.a_fax) }
    const g = { ...raender.get(String(z.sorte))!, a0Unten, a0Oben }
    const fHeute = f.get(Math.trunc(p.alterTage))!
    for (const h of horizonte) {
      const t = Math.trunc(p.alterTage + h)
      const fDann = f.get(t)!
      const teil: Teil = {
        p, t,
        stand: standNachTagen(p, h, fDann.m),
        verlust: verlustAb(p, h, fHeute.m, fDann.m),
        huelle: huelle(p, h, fDann.u, fDann.o, g),
        bekannt: { r: Boolean(z.r_bekannt), f: Boolean(z.f_bekannt), a0: Boolean(z.a0_bekannt),
                   kanal: Boolean(z.a_klein_bekannt) && Boolean(z.a_gross_bekannt), fax: Boolean(z.a_fax_bekannt) },
        modellGilt: Boolean(z.modell_gilt),
        ueberTMax: t > tMax,
      }
      for (const [gruppe, schluessel] of [['gesamt', ''], ['sorte', String(z.sorte)],
                                          ['schlag', String(z.schlag)], ['charge', String(z.charge_nr)]] as const) {
        const k = `${gruppe}|${schluessel}|${h}`
        if (!teileJeZeile.has(k)) teileJeZeile.set(k, [])
        teileJeZeile.get(k)!.push(teil)
      }
    }
  }
  const orakel = [...teileJeZeile].map(([k, teile]) => {
    const [gruppe, schluessel, h] = k.split('|')
    return { schluessel: k, gruppe, schluesselWert: schluessel, h: Number(h), ...summieren(teile) }
  })
  assert.equal(orakel.filter(o => !summeStimmtPrognose(o)).length, 0,
    'Orakel: die Ströme der Prognose summieren sich nicht auf die liegende Masse')

  const db = frage(`
    select gruppe, schluessel, h, n_kohorten, lager_kg, verdunstet_kg, sockel_kg, faul_kg, kanal_kg, fax_kg,
           verkaufsfaehig_kg, gute_ware_kg, verkaufsfaehig_unten_kg, verkaufsfaehig_oben_kg,
           verlust_wasser_kg, verlust_faeulnis_kg, verlust_verkaufsfaehig_kg, verkaufsfaehig_anteil,
           alter_tage, alter_von, alter_bis, vollstaendig::int as vollstaendig,
           modell_gilt::int as modell_gilt, hochgerechnet::int as hochgerechnet
      from v_prognose`)
  // zahl(…, 2) rundet auf zwei Stellen; der Anteil auf vier.
  const ab = vergleiche(db, orakel.map(o => ({ ...o, vollstaendig: o.vollstaendig ? 1 : 0,
                                               modellGilt: o.modellGilt ? 1 : 0, hochgerechnet: o.hochgerechnet ? 1 : 0,
                                               alterTageGerundet: Math.round(o.alterTage) })),
    { db: a => `${a.gruppe}|${a.schluessel}|${a.h}`, orakel: b => b.schluessel },
    [{ db: 'n_kohorten', orakel: 'nKohorten' },
     { db: 'lager_kg', orakel: 'lagerKg', abs: 0.006 }, { db: 'verdunstet_kg', orakel: 'verdunstetKg', abs: 0.006 },
     { db: 'sockel_kg', orakel: 'sockelKg', abs: 0.006 }, { db: 'faul_kg', orakel: 'faulKg', abs: 0.006 },
     { db: 'kanal_kg', orakel: 'kanalKg', abs: 0.006 }, { db: 'fax_kg', orakel: 'faxKg', abs: 0.006 },
     { db: 'verkaufsfaehig_kg', orakel: 'verkaufsfaehigKg', abs: 0.006 },
     { db: 'gute_ware_kg', orakel: 'guteWareKg', abs: 0.006 },
     { db: 'verkaufsfaehig_unten_kg', orakel: 'vfUntenKg', abs: 0.006 },
     { db: 'verkaufsfaehig_oben_kg', orakel: 'vfObenKg', abs: 0.006 },
     { db: 'verlust_wasser_kg', orakel: 'verlustWasserKg', abs: 0.006 },
     { db: 'verlust_faeulnis_kg', orakel: 'verlustFaeulnisKg', abs: 0.006 },
     { db: 'verlust_verkaufsfaehig_kg', orakel: 'verlustVerkaufsfaehigKg', abs: 0.011 },
     { db: 'verkaufsfaehig_anteil', orakel: 'verkaufsfaehigAnteil', abs: 6e-5 },
     { db: 'alter_tage', orakel: 'alterTageGerundet', abs: 0.51 },
     { db: 'alter_von', orakel: 'alterVon' }, { db: 'alter_bis', orakel: 'alterBis' },
     { db: 'vollstaendig', orakel: 'vollstaendig' }, { db: 'modell_gilt', orakel: 'modellGilt' },
     { db: 'hochgerechnet', orakel: 'hochgerechnet' }])
  assert.equal(ab.length, 0, bericht('v_prognose', ab, db.length))

  // Die Zerlegung ist exakt: Wasser + Fäulnis = was der Horizont an
  // verkaufsfähiger Ware kostet — und beide Teile sind nie negativ.
  const beiNull = new Map(orakel.filter(o => o.h === 0).map(o => [`${o.gruppe}|${o.schluesselWert}`, o.verkaufsfaehigKg]))
  const schief = orakel.filter(o => {
    const vf0 = beiNull.get(`${o.gruppe}|${o.schluesselWert}`)!
    return o.verlustWasserKg < -1e-9 || o.verlustFaeulnisKg < -1e-9
        || !zerlegungStimmt(vf0, o.verkaufsfaehigKg,
             { wasserKg: o.verlustWasserKg, faeulnisKg: o.verlustFaeulnisKg, verkaufsfaehigKg: o.verlustVerkaufsfaehigKg })
  })
  assert.deepEqual(schief.map(o => o.schluessel), [], 'Die Zerlegung in Wasser und Fäulnis geht nicht auf')
})

test('K9 — v_wohin: der Eingang, vollständig aufgeteilt', { skip }, () => {
  const db = frage<Record<string, unknown>>('select * from v_wohin')
  assert.ok(db.length > 0, 'v_wohin ist leer')
  const z = (r: Record<string, unknown>, s: string) => r[s] == null ? 0 : Number(r[s])
  const schief: string[] = []
  for (const r of db) {
    const wo = `${r.gruppe}/${r.schluessel}`
    // Erste Identität: alles, was hereinkam, ist entweder draussen oder liegt.
    const rest = z(r, 'eingang_kg') + z(r, 'ueberzaehlung_kg') - z(r, 'geliefert_kg')
      - z(r, 'kanal_ausgelagert_kg') - z(r, 'verdunstet_ausgelagert_kg') - z(r, 'faul_ausgelagert_kg')
      - z(r, 'fax_kg') - z(r, 'lager_kg')
    if (Math.abs(rest - z(r, 'rest_kg')) > 0.02) schief.push(`${wo}: Rest ${z(r, 'rest_kg')} statt ${rest.toFixed(2)}`)
    if (Math.abs(rest) > 0.1) schief.push(`${wo}: die erste Identität lässt ${rest.toFixed(2)} kg offen`)
    // Zweite Identität: was liegt, ist verkaufsfähig oder schon verloren.
    const lagerRest = z(r, 'lager_kg') - z(r, 'lager_verkaufsfaehig_kg') - z(r, 'lager_kanal_kg')
      - z(r, 'lager_fax_kg') - z(r, 'lager_faul_kg') - z(r, 'lager_verdunstet_kg')
    if (Math.abs(lagerRest - z(r, 'lager_rest_kg')) > 0.02)
      schief.push(`${wo}: Lagerrest ${z(r, 'lager_rest_kg')} statt ${lagerRest.toFixed(2)}`)
    if (Math.abs(lagerRest) > 0.1) schief.push(`${wo}: die zweite Identität lässt ${lagerRest.toFixed(2)} kg offen`)
    // „faul" trägt den Sockel mit; er steht daneben noch einmal für sich.
    if (z(r, 'faul_ausgelagert_kg') + 1e-9 < z(r, 'sockel_ausgelagert_kg'))
      schief.push(`${wo}: der Sockel ist grösser als das Faule, in dem er steckt`)
    if (z(r, 'lager_kanal_kg') > 0 && Math.abs(z(r, 'lager_kanal_kg') - z(r, 'lager_klein_kg') - z(r, 'lager_gross_kg')) > 0.1)
      schief.push(`${wo}: zu klein und zu gross ergeben nicht den Kanal im Lager`)
  }
  assert.deepEqual(schief.slice(0, 12), [], `v_wohin (${db.length} Zeilen): ${schief.length} Verstoss/Verstösse`)

  // Die Gruppen sind Zerlegungen derselben Menge: die Chargen ergeben „gesamt".
  const gesamt = db.find(r => r.gruppe === 'gesamt')!
  for (const ebene of ['sorte', 'schlag', 'charge']) {
    const summe = db.filter(r => r.gruppe === ebene).reduce((a, r) => a + z(r, 'eingang_kg'), 0)
    assert.ok(Math.abs(summe - z(gesamt, 'eingang_kg')) <= 0.1,
      `v_wohin: die Ebene „${ebene}" ergibt ${summe.toFixed(2)} kg Eingang, „gesamt" sagt ${z(gesamt, 'eingang_kg')}`)
  }
})

test('K10 — erg_verlauf: die Saison Woche für Woche, unabhängig nachgerechnet', { skip }, () => {
  const wochen = frage<{ woche: string; bis: string }>(
    "select distinct woche, bis from erg_verlauf order by bis")
  assert.ok(wochen.length > 4, `erg_verlauf hat nur ${wochen.length} Woche(n)`)
  const portionen = frage<Record<string, unknown>>(`
    select charge_nr, portion, kohorte, m0, r, a0, a_klein_n, a_gross_n, a_fax,
           case when portion = 'ausgelagert' then kohorte + round(alter_tage)::int end as liefertag,
           case when portion = 'ausgelagert' then fax_kg else 0 end as fax_kg
      from mv_kaskade where m0 > 0 and kohorte is not null`)
  assert.ok(portionen.length > 0, 'mv_kaskade ist leer')

  // F(t) wie der Verlauf sie braucht: am Tag null ist nichts faul.
  const tage = new Set<number>()
  const tag = (s: string) => Math.round(Date.parse(s + 'T00:00:00Z') / 86400000)
  for (const p of portionen) for (const w of wochen) {
    const bis = tag(w.bis), koh = tag(String(p.kohorte))
    if (koh > bis) continue
    tage.add(Math.max(Math.min(bis, p.liefertag == null ? bis : tag(String(p.liefertag))) - koh, 0))
  }
  const liste = [...tage].sort((a, b) => a - b)
  const f = new Map(frage<{ t: string; f: string }>(`
    select t, case when t <= 0 then 0 else schimmelanteil(t, 'mittel') end as f
      from unnest(array[${liste.join(',')}]::numeric[]) t`).map(z => [Number(z.t), Number(z.f)]))

  // Der Eingang kommt aus den Kohorten des Orakels, nicht aus v_palette:
  // Paletten ohne Nettogewicht werden dort mit dem Mittel der übrigen
  // hochgerechnet (0064), und genau so führt die Saisonbilanz sie. Wer hier
  // v_palette summiert, misst einen anderen Eingang als der Rest der App.
  const paletten = frage<Record<string, unknown>>(
    'select id, charge_nr, eingangsdatum, brutto_kg, kisten, gebindeart from palette')
    .map<Palette>(x => ({ id: Number(x.id), chargeNr: Number(x.charge_nr), eingangsdatum: String(x.eingangsdatum),
                          bruttoKg: n(x.brutto_kg), kisten: n(x.kisten),
                          gebindeart: x.gebindeart == null ? null : String(x.gebindeart) }))
  const eingang = kohorten(paletten, gebinde())
    .map(k => ({ eingangsdatum: k.eingangsdatum, kg: String(k.eingangKg) }))
  const ausgang = frage<{ datum: string; kg: string }>(
    'select datum, sum(masse_kg) as kg from v_lieferung_charge_tag group by datum')

  const orakel = wochen.map(w => {
    const bis = tag(w.bis)
    let verdunstung = 0, sockel = 0, schimmel = 0, fax = 0
    let imHaus = 0, lager = 0, kanal = 0, faxLager = 0, verkaufsfaehig = 0
    for (const p of portionen) {
      const koh = tag(String(p.kohorte))
      if (koh > bis) continue
      const lief = p.liefertag == null ? null : tag(String(p.liefertag))
      const t = Math.max(Math.min(bis, lief ?? bis) - koh, 0)
      const m0 = Number(p.m0), r = Number(p.r), a0 = Number(p.a0)
      const ft = f.get(t)!
      const nachWasser = m0 * Math.pow(1 - r, t)
      verdunstung += m0 * (1 - Math.pow(1 - r, t))
      sockel += nachWasser * a0
      schimmel += nachWasser * (1 - a0) * ft
      if (lief != null && lief <= bis) fax += Number(p.fax_kg)
      if (lief == null || lief > bis) {
        const gut = nachWasser * (1 - a0) * (1 - ft)
        const kn = Number(p.a_klein_n) + Number(p.a_gross_n)
        lager += m0
        imHaus += gut
        kanal += gut * kn
        faxLager += gut * (1 - kn) * Number(p.a_fax)
        verkaufsfaehig += gut * (1 - kn) * (1 - Number(p.a_fax))
      }
    }
    const summe = (zeilen: { kg: string }[], datum: (z: never) => string) =>
      zeilen.filter(z => tag(datum(z as never)) <= bis).reduce((a, z) => a + Number(z.kg), 0)
    return {
      schluessel: w.bis,
      eingangKumKg: summe(eingang, (z: { eingangsdatum: string }) => z.eingangsdatum),
      ausgangKumKg: summe(ausgang, (z: { datum: string }) => z.datum),
      verdunstungKumKg: verdunstung, sockelKumKg: sockel, schimmelKumKg: schimmel, faxKumKg: fax,
      verlustKumKg: verdunstung + schimmel + sockel + fax,
      imHausKg: imHaus, lagerKg: lager, verkaufsfaehigKg: verkaufsfaehig,
      kanalKg: kanal, faxLagerKg: faxLager,
    }
  })

  const db = frage(`
    select bis, eingang_kum_kg, ausgang_kum_kg, verdunstung_kum_kg, schimmel_kum_kg, sockel_kum_kg,
           fax_kum_kg, verlust_kum_kg, im_haus_kg, lager_kg, verkaufsfaehig_kg, kanal_kg, fax_lager_kg
      from erg_verlauf where gruppe = 'gesamt'`)
  // Der Ausgang ist je Charge, Tag und Buch auf zwei Stellen gerundet; über
  // ein halbes Jahr summiert sich das auf wenige Rappen. 0.05 kg ist dafür
  // reichlich und immer noch zehntausendmal feiner als die kleinste Zahl,
  // die auf dem Bildschirm steht.
  const ab = vergleiche(db, orakel, { db: a => String(a.bis), orakel: b => b.schluessel },
    [{ db: 'eingang_kum_kg', orakel: 'eingangKumKg', abs: 0.05 },
     { db: 'ausgang_kum_kg', orakel: 'ausgangKumKg', abs: 0.05 },
     { db: 'verdunstung_kum_kg', orakel: 'verdunstungKumKg', abs: 0.05 },
     { db: 'schimmel_kum_kg', orakel: 'schimmelKumKg', abs: 0.05 },
     { db: 'sockel_kum_kg', orakel: 'sockelKumKg', abs: 0.05 },
     { db: 'fax_kum_kg', orakel: 'faxKumKg', abs: 0.05 },
     { db: 'verlust_kum_kg', orakel: 'verlustKumKg', abs: 0.05 },
     { db: 'im_haus_kg', orakel: 'imHausKg', abs: 0.05 },
     { db: 'lager_kg', orakel: 'lagerKg', abs: 0.05 },
     { db: 'verkaufsfaehig_kg', orakel: 'verkaufsfaehigKg', abs: 0.05 },
     { db: 'kanal_kg', orakel: 'kanalKg', abs: 0.05 },
     { db: 'fax_lager_kg', orakel: 'faxLagerKg', abs: 0.05 }])
  assert.equal(ab.length, 0, bericht('erg_verlauf (gesamt)', ab, db.length))

  // An der Stützstelle heute muss der Verlauf sagen, was die Saisonbilanz sagt.
  const [heute] = frage<Record<string, unknown>>(`
    select v.lager_kg as v_lager, b.lager_kg as b_lager,
           v.verkaufsfaehig_kg as v_vf, b.verkaufsfaehig_heute_kg as b_vf,
           v.im_haus_kg as v_haus, b.im_haus_heute_kg as b_haus,
           v.eingang_kum_kg as v_ein, b.eingang_kg as b_ein
      from erg_verlauf v cross join erg_bilanz b
     where v.gruppe = 'gesamt' and v.bis = b.heute`)
  assert.ok(heute, 'erg_verlauf hat keine Stützstelle an heute')
  for (const [was, a, b] of [['im Lager', heute.v_lager, heute.b_lager],
                             ['verkaufsfähig', heute.v_vf, heute.b_vf],
                             ['im Haus', heute.v_haus, heute.b_haus],
                             ['Eingang', heute.v_ein, heute.b_ein]] as const)
    assert.ok(Math.abs(Number(a) - Number(b)) <= 0.05,
      `Verlauf und Saisonbilanz sagen bei „${was}" Verschiedenes: ${a} gegen ${b}`)
})

test('K11 — v_naechste_charge: eine einzige Zwei-Wochen-Zahl', { skip }, () => {
  const db = frage(`
    select charge_nr, lager_kg, masse_jetzt_kg, verdunstung_14_kg, schimmel_14_kg, prognose_verlust_14_kg,
           alter_tage, alter_von, alter_bis, n_kohorten, modell_gilt::int as modell_gilt,
           hochgerechnet::int as hochgerechnet
      from v_naechste_charge`)
  assert.ok(db.length > 0, 'v_naechste_charge ist leer')
  const p = frage<Record<string, unknown>>(`
    select p0.schluessel, p0.lager_kg, p0.gute_ware_kg, p0.n_kohorten, p0.alter_tage, p0.alter_von, p0.alter_bis,
           p14.verlust_wasser_kg, p14.verlust_faeulnis_kg, p14.verlust_verkaufsfaehig_kg,
           p0.modell_gilt::int as modell_gilt, p0.hochgerechnet::int as hochgerechnet
      from v_prognose p0
      join v_prognose p14 on p14.gruppe = 'charge' and p14.schluessel = p0.schluessel and p14.h = 14
     where p0.gruppe = 'charge' and p0.h = 0 and p0.lager_kg > 0`)
  const orakel = p.map(z => ({
    schluessel: String(z.schluessel),
    lagerKg: Number(z.lager_kg), masseJetztKg: Number(z.gute_ware_kg),
    nKohorten: Number(z.n_kohorten), alterTage: Number(z.alter_tage),
    alterVon: Number(z.alter_von), alterBis: Number(z.alter_bis),
    verdunstung14Kg: Number(z.verlust_wasser_kg),
    schimmel14Kg: Number(z.modell_gilt) ? Number(z.verlust_faeulnis_kg) : null,
    prognoseVerlust14Kg: Number(z.modell_gilt) ? Number(z.verlust_verkaufsfaehig_kg) : null,
    modellGilt: Number(z.modell_gilt), hochgerechnet: Number(z.hochgerechnet),
  }))
  // Die Sicht rundet auf eine Stelle (zahl(…, 1)); v_prognose auf zwei.
  const ab = vergleiche(db, orakel, { db: a => String(a.charge_nr), orakel: b => b.schluessel },
    [{ db: 'lager_kg', orakel: 'lagerKg', abs: 0.006 }, { db: 'masse_jetzt_kg', orakel: 'masseJetztKg', abs: 0.006 },
     { db: 'n_kohorten', orakel: 'nKohorten' }, { db: 'alter_tage', orakel: 'alterTage' },
     { db: 'alter_von', orakel: 'alterVon' }, { db: 'alter_bis', orakel: 'alterBis' },
     { db: 'verdunstung_14_kg', orakel: 'verdunstung14Kg', abs: 0.06 },
     { db: 'schimmel_14_kg', orakel: 'schimmel14Kg', abs: 0.06 },
     { db: 'prognose_verlust_14_kg', orakel: 'prognoseVerlust14Kg', abs: 0.06 },
     { db: 'modell_gilt', orakel: 'modellGilt' }, { db: 'hochgerechnet', orakel: 'hochgerechnet' }])
  assert.equal(ab.length, 0, bericht('v_naechste_charge', ab, db.length))

  // Die Reihenfolge ist die Aussage: oben steht, was am meisten kostet.
  const werte = db.map(z => z.prognose_verlust_14_kg == null ? null : Number(z.prognose_verlust_14_kg))
  const ohneLeer = werte.filter(w => w != null) as number[]
  assert.deepEqual(werte.slice(0, ohneLeer.length), ohneLeer,
    'v_naechste_charge: eine Zeile ohne Zahl steht vor einer mit Zahl')
  assert.deepEqual(ohneLeer, [...ohneLeer].sort((a, b) => b - a),
    'v_naechste_charge: die teuerste Charge steht nicht oben')
})
