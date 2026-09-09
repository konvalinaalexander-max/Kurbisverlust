/**
 * A1 — Schätzer-Prüfstand mit bekannter Wahrheit, über eine Reihe von
 *      Stichprobengrössen.
 *
 * DIE FRAGE
 *
 * Der Simulations-Prüfstand aus Runde D (`supabase/test/simulation/`) misst
 * Verzerrung und Überdeckung **je Verluststrom über eine ganze Saison**. Das
 * ist die richtige Frage für die Bilanz — aber nicht für die Schätzer.
 *
 * Ein Strom kann richtig herauskommen, weil sich zwei Fehler aufheben. Und
 * eine Zahl, die bei zwölf Wägungen trägt, sagt nichts über die Saison, in der
 * es drei waren. Der Betrieb misst **punktuell**: In der Demosaison haben von
 * vierzehn Sorten genau zwei eigene Verdunstungswägungen (n = 7 und n = 6),
 * die übrigen zwölf leihen sich den Koeffizienten aller Sorten.
 *
 * Dieses Werkzeug fragt deshalb je **Koeffizient einzeln** und über eine Reihe
 * von Stichprobengrössen: n = 1, 2, 3, 5, 10, 30.
 *
 *   Verzerrung  — liegt der Schätzer systematisch daneben?
 *   Überdeckung — enthält das ausgewiesene 95-%-Band den wahren Wert wirklich
 *                 in 95 % der Fälle?
 *
 * Die Überdeckung ist der schärfere Test. Ein Band, das 95 % heisst und in
 * 70 % trifft, ist schlimmer als gar kein Band: Es täuscht Sicherheit vor.
 *
 * PAARWEISER AUFBAU
 *
 * Alle Stichprobengrössen sehen **dieselben** erfundenen Saisons (dieselben
 * Laufnummern, dieselbe Saat). So misst der Vergleich zwischen n = 3 und
 * n = 30 wirklich den Unterschied der Stichprobe und nicht den Zufall der
 * Welten. Ohne das bräuchte man ein Vielfaches an Läufen für dieselbe Aussage.
 */
import { execFileSync } from 'node:child_process'
import { join } from 'node:path'
import { WURZEL, url, frage, wert, tue, spiele, frischesSchema, befund, messung, guete, mittel } from '../umgebung.mjs'

export const lang = true

const SIM = join(WURZEL, 'supabase/test/simulation')

/** Die Stichprobengrössen, die der Betrieb wirklich erreicht — plus der Vergleichsfall. */
const STICHPROBEN = [1, 2, 3, 5, 10, 30]

/**
 * Wie viele Saisons je Stichprobengrösse. Zwanzig reichen, um eine Verzerrung
 * von zehn Prozent von null zu unterscheiden; für die Überdeckung sind sie
 * knapp (ein Treffer mehr oder weniger sind fünf Prozentpunkte), deshalb wird
 * die Überdeckung nur grob beurteilt und mit ihrer Unsicherheit ausgewiesen.
 */
const LAEUFE = 20
const LAEUFE_SCHNELL = 5

/* ---------- Eine Saison erzeugen und auswerten ---------------------------- */

function saison(db, { lauf, n_wiegungen, n_lagerkontrollen = 0, anteil_lager = 0.25,
                      selektion = 0, anteil_sockel = 0 }) {
  const psql = (datei, mehr = []) => execFileSync('psql',
    [url(db), '-qX', '-v', 'ON_ERROR_STOP=1',
     '-v', `lauf=${lauf}`, '-v', `selektion=${selektion}`,
     '-v', `n_wiegungen=${n_wiegungen}`, '-v', `anteil_lager=${anteil_lager}`,
     '-v', `n_lagerkontrollen=${n_lagerkontrollen}`, '-v', `anteil_sockel=${anteil_sockel}`,
     ...mehr, '-f', join(SIM, datei)],
    { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'], maxBuffer: 64 * 1024 * 1024 })
  psql('saison.sql')
  psql('erfassung.sql')
  tue(db, 'select auswertung_aktualisieren()')
}

/**
 * Wahrheit und Schätzung je Koeffizient, für einen Lauf.
 *
 * Die Zuordnung ist die heikle Stelle dieses Werkzeugs, deshalb steht sie an
 * einem Ort und ist einzeln begründet:
 *
 *   r (Verdunstung)  — die Simulation setzt eine Basisrate je Saison und
 *                      streut sie je Palette. Der wahre Wert für den
 *                      Vergleich ist die massegewichtete Rate der Saison;
 *                      geschätzt wird sie je Sorte, wir nehmen den Mittelwert
 *                      über die Sorten, die **eigene** Messungen haben, und,
 *                      wo es keine gibt, den gepoolten Wert.
 *   Schimmelkurve    — verglichen wird der Anteil bei 120 Lagertagen: wahr
 *                      1 − exp(−λ·t^k), geschätzt aus v_schimmel_kurve am
 *                      selben Alter.
 *   a_klein, a_gross — Anteile aus der Sortier-CSV, direkt vergleichbar.
 *   Sockel a₀        — wahr aus sim.parameter.anteil_sockel, geschätzt aus
 *                      v_schimmel_modell.sockel (0, wenn nicht nachgewiesen).
 */
function ablesen(db, lauf) {
  const p = frage(db, `select * from sim.parameter where lauf = ${lauf}`)[0]
  if (!p) return null

  const kv = frage(db, `select sorte, mittel::float8 as mittel, unten::float8 as unten,
                               oben::float8 as oben, n, basis from v_koeff_verdunstung`)
  const eigene = kv.filter(z => z.n > 0 && /dieser Sorte/.test(z.basis ?? ''))
  const genommen = eigene.length ? eigene : kv
  const r = {
    wahr: Number(p.r_basis),
    geschaetzt: mittel(genommen.map(z => z.mittel).filter(x => x !== null)),
    unten: mittel(genommen.map(z => z.unten).filter(x => x !== null)),
    oben: mittel(genommen.map(z => z.oben).filter(x => x !== null)),
    n_eigene_sorten: eigene.length,
    n_messungen: Math.max(0, ...kv.map(z => z.n ?? 0)),
    geliehen: kv.filter(z => !/dieser Sorte/.test(z.basis ?? '')).length,
  }

  const T = 120
  const kurve = frage(db, `select von, bis, anteil_mono::float8 as anteil,
                                  unten::float8 as unten, oben::float8 as oben, n
                             from v_schimmel_kurve
                            where ${T} >= von and ${T} < bis and n > 0`)[0]
  const schimmel = {
    wahr: 1 - Math.exp(-Number(p.schimmel_lambda) * Math.pow(T, Number(p.schimmel_k))),
    geschaetzt: kurve ? kurve.anteil : null,
    unten: kurve ? kurve.unten : null,
    oben: kurve ? kurve.oben : null,
  }

  const ka = frage(db, `select avg(mittel)::float8 as m, avg(unten)::float8 as u,
                               avg(oben)::float8 as o, max(n) as n from v_koeff_ausschuss`)[0]
  const kn = frage(db, `select avg(mittel)::float8 as m, avg(unten)::float8 as u,
                               avg(oben)::float8 as o, max(n) as n from v_koeff_nebenkanal`)[0]

  const sm = frage(db, `select sockel::float8 as sockel, sockel_unten::float8 as unten,
                               sockel_oben::float8 as oben, sockel_nachweis::float8 as nachweis,
                               sockel_schwelle::float8 as schwelle, brauchbar, n
                          from v_schimmel_modell`)[0]

  return {
    lauf,
    n_wiegungen: p.n_wiegungen,
    koeffizienten: {
      'Verdunstungsrate r': r,
      'Verderbskurve bei 120 Tagen': schimmel,
      'Anteil zu klein': { wahr: Number(p.anteil_klein), geschaetzt: ka?.m ?? null,
                           unten: ka?.u ?? null, oben: ka?.o ?? null, n_messungen: ka?.n ?? 0 },
      'Anteil zu gross': { wahr: Number(p.anteil_gross), geschaetzt: kn?.m ?? null,
                           unten: kn?.u ?? null, oben: kn?.o ?? null, n_messungen: kn?.n ?? 0 },
      'Sockel a₀': { wahr: Number(p.anteil_sockel ?? 0), geschaetzt: sm?.sockel ?? null,
                     unten: sm?.unten ?? null, oben: sm?.oben ?? null,
                     nachweis: sm?.nachweis ?? null, schwelle: sm?.schwelle ?? null },
    },
    geliehen: r.geliehen,
    sorten_gesamt: kv.length,
  }
}

/* ---------- Urteil ------------------------------------------------------- */

/**
 * Ab wann ist ein Schätzer schlecht? Die Schwellen sind bewusst grosszügig —
 * es geht nicht darum, jede kleine Verzerrung zu melden, sondern die zu
 * finden, die eine Entscheidung des Betriebs kippen würde.
 */
const VERZERRUNG_GRENZE = 15      // Prozent
const UEBERDECKUNG_UNTEN = 0.80   // von versprochenen 0.95

export async function laufen({ schnell = false } = {}) {
  const db = 'mw_a1'
  const laeufe = schnell ? LAEUFE_SCHNELL : LAEUFE
  const raus = []

  frischesSchema(db)
  spiele(db, join(SIM, 'aufbau.sql'))

  /* Die Messreihe: je Stichprobengrösse dieselben Welten. */
  const ergebnisse = new Map()   // n → [ablesung]
  for (const n of STICHPROBEN) {
    const je = []
    for (let lauf = 1; lauf <= laeufe; lauf++) {
      saison(db, { lauf, n_wiegungen: n, n_lagerkontrollen: 0 })
      const a = ablesen(db, lauf)
      if (a) je.push(a)
    }
    ergebnisse.set(n, je)
  }

  const NAMEN = ['Verdunstungsrate r', 'Verderbskurve bei 120 Tagen',
                 'Anteil zu klein', 'Anteil zu gross', 'Sockel a₀']

  /* ---------- Messreihe in den Bericht ---------- */
  const zeilen = []
  for (const name of NAMEN) {
    for (const n of STICHPROBEN) {
      const g = guete(ergebnisse.get(n).map(a => a.koeffizienten[name]))
      zeilen.push({
        Koeffizient: name,
        'Wägungen je Saison': n,
        Läufe: g.n,
        'Verzerrung %': g.verzerrung_prozent ?? '—',
        'Streuung %': g.streuung_prozent ?? '—',
        'Überdeckung': g.ueberdeckung !== null ? `${Math.round(100 * g.ueberdeckung)} %` : '—',
        'ohne Schätzung': g.n_verworfen,
      })
    }
  }
  raus.push(messung({
    werkstatt: 'A', titel: 'Güte jedes Koeffizienten über die Stichprobengrösse',
    einheit: 'Prozent', spalten: Object.keys(zeilen[0]), zeilen,
    erklaerung: `${laeufe} erfundene Saisons je Stichprobengrösse, alle Grössen sehen dieselben `
      + `Welten (paarweiser Aufbau). Verzerrung ist der mittlere relative Fehler — 0 heisst `
      + `unverzerrt. Überdeckung ist der Anteil der Läufe, in denen der wahre Wert im `
      + `ausgewiesenen 95-%-Band lag; sie sollte bei 95 % liegen.`,
  }))

  /* ---------- Befunde ---------- */
  for (const name of NAMEN) {
    const beiWenig = guete(ergebnisse.get(3).map(a => a.koeffizienten[name]))
    const beiViel = guete(ergebnisse.get(30).map(a => a.koeffizienten[name]))

    if (beiWenig.verzerrung_prozent !== null && Math.abs(beiWenig.verzerrung_prozent) > VERZERRUNG_GRENZE) {
      raus.push(befund({
        werkstatt: 'A', kuerzel: 'SCH', klasse: 3,
        ort: { sicht: name },
        titel: `„${name}" liegt bei drei Wägungen um ${beiWenig.verzerrung_prozent} % daneben`,
        steht_da: `Bei drei Wägungen je Saison — der Grössenordnung, die der Betrieb wirklich `
          + `erreicht — liegt die Schätzung im Mittel ${beiWenig.verzerrung_prozent} % neben der `
          + `Wahrheit (${beiWenig.n} Läufe, Streuung ${beiWenig.streuung_prozent} %). `
          + `Bei dreissig Wägungen sind es ${beiViel.verzerrung_prozent} %.`,
        muesste: 'Eine Verzerrung nahe null, oder — wenn sie sich nicht vermeiden lässt — ein '
          + 'Hinweis an der Zahl, in welche Richtung sie zu klein oder zu gross ist.',
        warum: 'Eine Verzerrung mittelt sich über die Saisons **nicht** heraus. Sie steht in jeder '
          + 'Zahl, die diesen Koeffizienten benutzt, und der Betriebsleiter hat keine Möglichkeit, '
          + 'sie zu bemerken.',
        beleg: 'werkstatt/a_rechenwerk/a1_schaetzer.mjs — Messreihe „Güte jedes Koeffizienten"',
        groesse: { wert: Math.abs(beiWenig.verzerrung_prozent), einheit: '% Verzerrung bei n = 3',
                   basis: `${beiWenig.n} erfundene Saisons mit bekannter Wahrheit` },
        sicherheit: beiWenig.n >= 15 ? 'hoch' : 'mittel',
        gegenrede: `Bei dreissig Wägungen beträgt die Verzerrung ${beiViel.verzerrung_prozent} % — `
          + `der Schätzer ist also nicht grundsätzlich falsch, sondern nur bei kleiner Stichprobe. `
          + `Wer mehr misst, hat das Problem nicht. Nur misst der Betrieb nicht mehr.`,
        marke: 'Frage an den Betrieb', aufwand: 'mittel',
      }))
    }

    if (beiWenig.ueberdeckung !== null && beiWenig.ueberdeckung < UEBERDECKUNG_UNTEN && beiWenig.n_mit_band >= 10) {
      raus.push(befund({
        werkstatt: 'A', kuerzel: 'SCH', klasse: 3,
        ort: { sicht: name },
        titel: `Das 95-%-Band von „${name}" trifft bei drei Wägungen nur in `
             + `${Math.round(100 * beiWenig.ueberdeckung)} % der Fälle`,
        steht_da: `Von ${beiWenig.n_mit_band} Läufen mit ausgewiesenem Band enthielt es den wahren `
          + `Wert in ${Math.round(100 * beiWenig.ueberdeckung)} % — versprochen sind 95 %.`,
        muesste: 'Entweder ein breiteres Band, oder eine ehrliche Beschriftung: „Bereich, solange '
          + 'die Annahmen tragen" statt „95 %".',
        warum: 'Ein Band, das 95 % heisst und in weniger trifft, ist schlimmer als gar kein Band — '
          + 'es täuscht Sicherheit vor, auf die der Betrieb sich verlässt.',
        beleg: 'werkstatt/a_rechenwerk/a1_schaetzer.mjs — Spalte „Überdeckung"',
        groesse: { wert: Math.round(100 * (0.95 - beiWenig.ueberdeckung)),
                   einheit: 'Prozentpunkte Überdeckung fehlen',
                   basis: `${beiWenig.n_mit_band} Läufe mit Band bei n = 3` },
        sicherheit: beiWenig.n_mit_band >= 15 ? 'mittel' : 'Verdacht',
        gegenrede: `Bei ${beiWenig.n_mit_band} Läufen ist ein Treffer mehr oder weniger schon `
          + `${Math.round(100 / beiWenig.n_mit_band)} Prozentpunkte. Die Zahl ist eine Richtung, `
          + `kein Beweis — für einen Beweis bräuchte es hundert Läufe je Stichprobengrösse.`,
        marke: 'Reparatur', aufwand: 'mittel',
      }))
    }
  }

  /* ---------- Der geliehene Koeffizient ---------- */
  const beispiel = ergebnisse.get(3)[0]
  if (beispiel && beispiel.geliehen > 0) {
    const eigen = ergebnisse.get(3).map(a => a.koeffizienten['Verdunstungsrate r'])
    const g = guete(eigen)
    raus.push(befund({
      werkstatt: 'A', kuerzel: 'SCH', klasse: 3,
      ort: { sicht: 'v_koeff_verdunstung', spalte: 'unten/oben' },
      titel: 'Eine Sorte, die sich den Koeffizienten einer anderen leiht, bekommt kein breiteres Band',
      steht_da: `In der Demosaison haben 2 von 14 Sorten eigene Verdunstungswägungen; die übrigen 12 `
        + `bekommen den Wert „Wiegungen aller Sorten" — **mit demselben Band wie der gepoolte Wert**. `
        + `Das Band bildet nur die Streuung der Wägungen ab, nicht die zusätzliche Unsicherheit `
        + `darüber, ob die fremde Sorte sich überhaupt gleich verhält. In der Simulation liegt die `
        + `Überdeckung des gepoolten Werts bei ${g.ueberdeckung !== null ? Math.round(100 * g.ueberdeckung) + ' %' : 'nicht messbar'}.`,
      muesste: 'Ein geliehener Koeffizient trägt zwei Unsicherheiten: die der Messung und die der '
        + 'Übertragung. Das Band müsste beide enthalten — oder die Zahl müsste sagen, dass sie '
        + 'geliehen ist. Die Spalte `basis` sagt es bereits; auf dem Bildschirm steht es nicht.',
      warum: 'Der Betriebsleiter vergleicht Sorten miteinander. Zwölf seiner vierzehn Sorten tragen '
        + 'dieselbe geliehene Zahl mit demselben Band — jeder Unterschied, den er zwischen ihnen '
        + 'sieht, kommt allein aus der Lagerdauer, nicht aus der Sorte. Das ist genau die '
        + 'Verwechslung, die zu einer falschen Sortenwahl führt.',
      beleg: 'v_koeff_verdunstung in der Demosaison (Spalte `basis`) + werkstatt/a_rechenwerk/a1_schaetzer.mjs',
      groesse: { wert: 12, einheit: 'von 14 Sorten mit geliehenem Koeffizienten',
                 basis: 'Demosaison, v_koeff_verdunstung' },
      sicherheit: 'hoch',
      gegenrede: 'Pooling ist die richtige Antwort auf eine dünne Stichprobe — die Alternative wäre, '
        + 'für zwölf Sorten gar nichts zu sagen. Der Einwand richtet sich nicht gegen das Pooling, '
        + 'sondern gegen das Band und gegen das Schweigen darüber auf dem Bildschirm.',
      marke: 'Reparatur', aufwand: 'klein',
    }))
  }

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Das Messgerät dieses Werkzeugs ist `guete()` samt der Schwellen darüber.
 * Die Selbstprobe pflanzt einen Schätzer mit bekannter Verzerrung und einem
 * bekannt zu schmalen Band und verlangt, dass beides erkannt wird.
 *
 * Sie fährt **keine** Simulation: Ein Werkzeug, dessen Selbstprobe zehn
 * Minuten braucht, wird abgeschaltet, und dann prüft es gar nichts mehr.
 */
export async function selbstprobe() {
  const wahr = 0.0005

  // Ein um 30 % zu hoher Schätzer mit einem Band, das nur ±2 % breit ist.
  const schlecht = Array.from({ length: 20 }, (_, i) => ({
    wahr,
    geschaetzt: wahr * (1.30 + (i % 5 - 2) * 0.01),
    unten: wahr * 1.28, oben: wahr * 1.32,
  }))
  const gs = guete(schlecht)
  const erkanntVerzerrung = Math.abs(gs.verzerrung_prozent) > VERZERRUNG_GRENZE
  const erkanntBand = gs.ueberdeckung < UEBERDECKUNG_UNTEN

  // Ein guter Schätzer darf nicht anschlagen — sonst meldet das Werkzeug alles.
  const gut = Array.from({ length: 20 }, (_, i) => ({
    wahr,
    geschaetzt: wahr * (1 + (i % 7 - 3) * 0.01),
    unten: wahr * 0.90, oben: wahr * 1.10,
  }))
  const gg = guete(gut)
  const keinFehlalarm = Math.abs(gg.verzerrung_prozent) <= VERZERRUNG_GRENZE
                     && gg.ueberdeckung >= UEBERDECKUNG_UNTEN

  return erkanntVerzerrung && erkanntBand && keinFehlalarm
}
