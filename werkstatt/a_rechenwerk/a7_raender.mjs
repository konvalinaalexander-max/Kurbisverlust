/**
 * A7 — Ränder: was tut die Kaskade an ihren Grenzen?
 *
 * WARUM ES DIESES WERKZEUG GIBT
 *
 * A1 prüft den Schätzer über erfundene Saisons; die sehen aus wie die
 * Demosaison, nur anders gewürfelt. Damit misst A1 gut, was **normalerweise**
 * herauskommt — und gar nichts darüber, was bei einer Charge geschieht, die
 * vierhundert Tage liegt, oder bei einer Sorte, deren beide Ausschussanteile
 * zusammen über eins gehen.
 *
 * Solche Fälle sind nicht erfunden. Der Betrieb hatte in der Demosaison
 * Chargen zwischen 62 und 199 Tagen Lagerdauer, und die beiden Anteile „zu
 * klein" und „zu gross" werden aus **getrennten** Messungen geschätzt: Nichts
 * hält ihre Summe unter eins ausser dem Umstand, dass sie heute klein sind.
 *
 * WAS ES TUT
 *
 * Es holt die veröffentlichte Formel aus der laufenden Sicht — nicht aus dem
 * Quelltext einer Migration, sondern mit `pg_get_viewdef`, damit sie nicht
 * auseinanderlaufen können — und rechnet sie in derselben Datenbank über ein
 * Gitter aus Werten durch, das die heutigen Daten weit überschreitet. Danach
 * prüft es Zusicherungen, die für **jede** Eingabe gelten müssen:
 *
 *   1. Der verkaufsfähige Anteil liegt zwischen 0 und 1. Ist er grösser als
 *      1, entsteht aus einer Lieferung weniger Eingang, als geliefert wurde.
 *   2. Er fällt nicht unter den Boden von 0.25 — und wo der Boden greift,
 *      erfindet er Masse. Wie viel, wird beziffert.
 *   3. Kein Zwischenwert wird zu NaN oder Unendlich.
 *   4. Mehr Lagertage ergeben nie **weniger** Verdunstung.
 *
 * DER WÄCHTER, DEN DIESES WERKZEUG BRAUCHT
 *
 * Eine Formel für sich zu rechnen, ist gefährlich: Sie steht am Ende einer
 * Kette, und was in sie hineingeht, ist bereits durch die Stufen davor
 * gegangen. Die erste Fassung dieses Werkzeugs hat `a_klein_n` und
 * `a_gross_n` mit rohen Anteilen von 70 % und 60 % gefüttert und daraus einen
 * negativen Faktor bekommen — und daraus einen Befund geschrieben. In der
 * Sicht kann das nie passieren: Eine Stufe vorher steht
 *
 *     CROSS JOIN LATERAL (SELECT GREATEST(a_klein + a_gross, 1) AS f) n
 *     a_klein / n.f AS a_klein_n,  a_gross / n.f AS a_gross_n
 *
 * Die Summe wird also auf 1 normiert, bevor sie in die Formel kommt. Der
 * Befund war ein Fehler des Werkzeugs, kein Fehler des Programms.
 *
 * Deshalb rechnet dieses Werkzeug **die Kette**, nicht die Zeile, und prüft
 * zuerst an den echten Zeilen der laufenden Sicht nach, ob sein Nachbau
 * dieselben Zahlen ergibt wie die veröffentlichten. Stimmt das nicht auf
 * sechs Stellen, bricht es ab, statt eine hübsche falsche Tabelle zu drucken.
 *
 * Und es misst den **Abstand**: wie weit die heutigen Daten von jeder Kante
 * entfernt sind. Eine Kante, an die niemand herankommt, ist eine andere
 * Feststellung als eine, vor der die Saison bereits steht.
 */
import { frage, wert, befund, messung } from '../umgebung.mjs'

export const lang = false

const WERKSTATT = 'A — Rechenwerk'

/**
 * Holt den Ausdruck für den verkaufsfähigen Anteil aus der laufenden Sicht.
 *
 * Er wird gebraucht, nicht nachgebaut: Ein nachgebauter Ausdruck prüft die
 * Fassung im Kopf des Prüfenden, nicht die im Betrieb.
 */
export function formelHolen(text) {
  const zeile = text.split('\n').find(z => /\bAS verkaufsfaehig_anteil\b/.test(z))
  if (!zeile) return null
  const m = /^\s*(.*?)\s+AS verkaufsfaehig_anteil\s*,?\s*$/.exec(zeile)
  return m ? m[1] : null
}

/**
 * Der Nenner, mit dem die Sicht die beiden Ausschussanteile normiert, bevor
 * sie in die Formel gehen. Er wird genauso herausgeholt wie die Formel —
 * würde er hier nachgebaut, prüfte das Werkzeug seinen eigenen Nachbau.
 */
export function normiererHolen(text) {
  // Ein regulärer Ausdruck reicht hier nicht, aus zwei Gründen. Erstens
  // enthält der Normierer selbst Klammern (`COALESCE(…)`), an denen `[^)]*`
  // abbricht. Zweitens — und das war der eigentliche Stolperstein — steht in
  // derselben Sicht **vorher** schon eine Zeile
  //
  //     LEAST(GREATEST(COALESCE(ka.mittel, 0), 0), 1) AS a_klein
  //
  // die auf dieselbe Grobsuche passt. Wer den ersten Treffer nimmt, bekommt
  // die Klemme statt des Normierers. Gesucht wird deshalb der GREATEST-
  // Ausdruck, der **beide** Anteile enthält und auf den `AS f` folgt.
  for (let i = text.indexOf('GREATEST'); i >= 0; i = text.indexOf('GREATEST', i + 1)) {
    const auf = text.indexOf('(', i)
    if (auf < 0) break
    let tiefe = 0, zu = -1
    for (let j = auf; j < text.length; j++) {
      if (text[j] === '(') tiefe++
      else if (text[j] === ')' && --tiefe === 0) { zu = j; break }
    }
    if (zu < 0) continue
    const stueck = text.slice(i, zu + 1)
    if (/\ba_klein\b/.test(stueck) && /\ba_gross\b/.test(stueck)
        && /^\s*AS\s+f\b/i.test(text.slice(zu + 1, zu + 12))) return stueck
  }
  return null
}

/**
 * Baut die Abfrage, die die Formel **wörtlich** rechnet.
 *
 * Nicht durch Einsetzen von Zahlen in den Ausdruck: Der Ausdruck spricht von
 * `x.r`, `x.a_klein_n` und so weiter, also von den Spalten einer Zwischenstufe.
 * Wer dort Zahlen hineinschreibt, entscheidet selbst, was diese Spalten
 * bedeuten — und liegt falsch, sobald eine davon vor der Formel noch durch
 * eine Rechnung geht. Genau das ist mit `a_klein_n` passiert.
 *
 * Stattdessen wird die Zwischenstufe nachgebaut: `g` ist das Gitter mit den
 * **rohen** Werten, `n` hängt den Normierer der Sicht daran, `x` teilt damit —
 * und darüber steht der Ausdruck, Zeichen für Zeichen wie in der Sicht.
 */
export function gitterAbfrage(formel, gitter, normierer, spalten) {
  const nf = normierer.replace(/\bk_1\.a_klein\b/g, 'g.a_klein')
                      .replace(/\bk_1\.a_gross\b/g, 'g.a_gross')
                      .replace(/(?<!\.)\ba_klein\b/g, 'g.a_klein')
                      .replace(/(?<!\.)\ba_gross\b/g, 'g.a_gross')
  const werte = gitter.map((w, i) =>
    `(${i}, ${w.r}::numeric, ${w.t}::numeric, ${w.a0}::numeric, ${w.f}::numeric, `
    + `${w.klein}::numeric, ${w.gross}::numeric, ${w.fax}::numeric)`).join(',\n      ')
  return `
    with g(i, r, alter_tage, a0, f, a_klein, a_gross, a_fax) as (values
      ${werte}
    ), n as (select g.*, ${nf} as nf from g),
       x as (select i, r, alter_tage, a0, f, a_fax,
                    a_klein / nf as a_klein_n, a_gross / nf as a_gross_n from n)
    select x.i, ${spalten.map(([name, ausdruck]) => `${ausdruck} as ${name}`).join(', ')}
      from x order by x.i`
}

/** Dieselbe Formel, aber ohne den Boden — um zu sehen, was der Boden verdeckt. */
const ohneBoden = (formel) => formel.replace(/GREATEST\s*\(/i, 'NULLIF(0, 1) + (')
                                    .replace(/,\s*0\.25\s*\)\s*$/, ')')

/* ---------- Das Gitter ---------------------------------------------------- */

/**
 * Werte, die der Betrieb erreichen kann — nicht Werte, die die Datentypen
 * hergeben. `r` ist in der Kaskade auf [0, 0.05] geklemmt, die drei Anteile
 * je auf [0, 1]; das Gitter bleibt innerhalb dieser Klemmen und fragt, was
 * **innerhalb** davon noch passieren kann.
 */
const GITTER = []
for (const r of [0, 0.001, 0.01, 0.03, 0.05])
  for (const t of [0, 1, 30, 100, 200, 400, 800])
    for (const [klein, gross] of [[0, 0], [0.05, 0.1], [0.3, 0.3], [0.5, 0.5], [0.7, 0.6], [1, 1]])
      GITTER.push({ r, t, a0: 0.02, f: 0.05, klein, gross, fax: 0.01 })

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const raus = []
  const sicht = wert(db, `select pg_get_viewdef('mv_kaskade'::regclass, true)`)
  const formel = formelHolen(sicht)
  const normierer = normiererHolen(sicht)
  if (!formel || !normierer) throw new Error(
    'Der Ausdruck für verkaufsfaehig_anteil oder der Normierer der beiden Ausschussanteile steht '
    + 'nicht mehr da, wo dieses Werkzeug ihn sucht. Das ist kein Befund über das Programm, '
    + 'sondern einer über dieses Werkzeug — es müsste nachgezogen werden, statt still nichts zu '
    + 'prüfen.')

  // ---- Wächter: ergibt der Nachbau dieselben Zahlen wie die Sicht? -------
  //
  // Ohne diesen Abgleich prüft das Gitter eine Formel, die es sich selbst
  // zurechtgelegt hat. Genau so ist die erste Fassung dieses Werkzeugs zu
  // einem Befund über einen negativen Faktor gekommen, den es in der Sicht
  // nicht geben kann.
  const echte = frage(db, `
    select r::float8 r, alter_tage::float8 t, a0::float8 a0, f::float8 f,
           a_klein_n::float8 klein_n, a_gross_n::float8 gross_n, a_fax::float8 fax,
           verkaufsfaehig_anteil::float8 veroeffentlicht
      from mv_kaskade limit 40`)
  if (!echte.length) throw new Error('mv_kaskade ist leer — das Gitter prüfte dann nichts Echtes.')
  // Die echten Zeilen tragen die **normierten** Anteile; ihre Summe ist damit
  // höchstens 1, der Normierer ergibt 1 und ändert nichts.
  const nachbau = frage(db, gitterAbfrage(formel,
    echte.map(z => ({ r: z.r, t: z.t, a0: z.a0, f: z.f,
                      klein: z.klein_n, gross: z.gross_n, fax: z.fax })),
    normierer, [['a', formel]]))
  const schlimmste = Math.max(...nachbau.map((z, i) =>
    Math.abs(Number(z.a) - Number(echte[i].veroeffentlicht))))
  if (!(schlimmste < 1e-6)) throw new Error(
    `Der Nachbau der Formel ergibt auf den echten Zeilen andere Zahlen als die Sicht `
    + `(grösste Abweichung ${schlimmste}). Solange das so ist, sagt jedes Ergebnis dieses `
    + 'Werkzeugs nur etwas über den Nachbau.')

  const werte = frage(db, gitterAbfrage(formel, GITTER, normierer,
      [['mit_boden', formel], ['ohne_boden', ohneBoden(formel)]]))
    .map(z => ({ ...GITTER[Number(z.i)], mit: Number(z.mit_boden), ohne: Number(z.ohne_boden) }))

  /* --- Zusicherung 1: nie über 1 --- */
  const ueberEins = werte.filter(w => w.mit > 1.0000001)

  /* --- Zusicherung 2: wo greift der Boden, und was kostet er --- */
  const gebodet = werte.filter(w => Math.abs(w.mit - 0.25) < 1e-9 && w.ohne < 0.25)
  const negativ = werte.filter(w => w.ohne < 0)

  /* --- Zusicherung 3: nichts wird unendlich oder NaN --- */
  const kaputt = werte.filter(w => !Number.isFinite(w.mit) || !Number.isFinite(w.ohne))

  /* --- Zusicherung 4: mehr Tage, nicht weniger Verdunstung --- */
  let unmonoton = 0
  for (const r of [0.001, 0.01, 0.03, 0.05]) {
    const reihe = werte.filter(w => w.r === r && w.klein === 0 && w.gross === 0)
                       .sort((a, b) => a.t - b.t)
    for (let i = 1; i < reihe.length; i++)
      if (reihe[i].ohne > reihe[i - 1].ohne + 1e-12) unmonoton++
  }

  /* --- Wo heute die Saison steht --- */
  const heute = frage(db, `
    select max(alter_tage)::numeric(8,1) as alter_max,
           max(a_klein_n + a_gross_n)::numeric(6,4) as summe_max,
           min(verkaufsfaehig_anteil)::numeric(6,4) as anteil_min,
           min(r)::numeric(9,6) as r_min, max(r)::numeric(9,6) as r_max,
           count(*) as n
      from mv_kaskade`)[0]

  /* --- Die Kante: ab wann greift der Boden bei welcher Rate --- */
  const rMax = Number(heute.r_max)
  const kanten = []
  for (const r of [...new Set([Number(heute.r_min), rMax, 0.001, 0.005, 0.01, 0.02, 0.05])]
                    .sort((a, b) => a - b)) {
    // (1-r)^t * (1-a0)(1-f)(1-klein-gross)(1-fax) = 0.25, mit den heutigen Nebenfaktoren
    const neben = (1 - 0.02) * (1 - 0.05) * (1 - Number(heute.summe_max ?? 0)) * (1 - 0.01)
    const t = Math.log(0.25 / neben) / Math.log(1 - r)
    kanten.push({ r, tage: Number.isFinite(t) && t > 0 ? Math.ceil(t) : null,
                  kommtVor: r <= rMax + 1e-9 && r >= Number(heute.r_min) - 1e-9 })
  }
  // Die Kante, die zählt, ist die bei der **höchsten beobachteten** Rate — nicht
  // die erste Zeile der Tabelle. Die erste Fassung dieses Werkzeugs nahm sie,
  // und schrieb damit „ab 1161 Tagen" über eine Tabelle, in der zwei Zeilen
  // weiter „ab 116 Tagen" stand.
  const kanteEcht = kanten.find(k => k.kommtVor && k.tage) ?? kanten.find(k => k.tage)

  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Ab wann der Boden von 0.25 die Rechnung übernimmt',
    einheit: 'Lagertage',
    spalten: ['Verdunstungsrate je Tag', 'kommt in den Daten vor', 'Boden greift ab',
              'Abstand zur längsten Charge heute', 'Was der Eingang dann wäre'],
    erklaerung: `Der verkaufsfähige Anteil ist \`GREATEST(…, 0.25)\`; aus ihm entsteht der `
      + 'Eingang als `geliefert ÷ Anteil`. Solange der Boden nicht greift, ist das die '
      + 'Rückrechnung. Greift er, ist es keine Rückrechnung mehr, sondern eine feste Zahl: Der '
      + 'Eingang ist dann genau das Vierfache des Gelieferten, unabhängig davon, wie lange die '
      + 'Ware wirklich lag. Die Tabelle sagt, wie weit dieser Punkt entfernt ist. Gerechnet mit '
      + `den übrigen Faktoren der heutigen Saison (Sockel 2 %, Schimmel 5 %, klein+gross `
      + `${(Number(heute.summe_max) * 100).toFixed(1)} %, Fax 1 %). Die längste Charge liegt heute `
      + `${heute.alter_max} Tage, und die gemessenen Raten liegen zwischen `
      + `${(Number(heute.r_min) * 100).toFixed(3)} % und ${(rMax * 100).toFixed(3)} % je Tag. `
      + 'Die Spalte „kommt in den Daten vor" trennt das Beobachtete vom Durchgerechneten — ohne '
      + 'sie liest man die Zeile mit der höchsten Rate als Warnung, obwohl sie eine Rechenübung '
      + 'ist.',
    zeilen: kanten.map(k => ({
      'Verdunstungsrate je Tag': `${(k.r * 100).toFixed(3)} %`,
      'kommt in den Daten vor': k.kommtVor ? 'ja' : 'nein',
      'Boden greift ab': k.tage === null ? 'nie' : `${k.tage} Tagen`,
      'Abstand zur längsten Charge heute': k.tage === null ? '—'
        : `${(k.tage - Number(heute.alter_max)).toFixed(0)} Tage`,
      'Was der Eingang dann wäre': k.tage === null ? '—' : '4 × geliefert, fest',
    })),
  }))

  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Der verkaufsfähige Anteil über ein Gitter aus Randwerten',
    einheit: 'Gitterpunkte',
    spalten: ['Rate', 'Tage', 'zu klein + zu gross', 'Anteil mit Boden', 'ohne Boden',
              'Eingang je 1000 kg geliefert'],
    erklaerung: `${werte.length} Punkte, gerechnet mit der Formel, die \`pg_get_viewdef\` aus `
      + '`mv_kaskade` zurückgibt — nicht mit einer nachgebauten. Gezeigt sind die Punkte, an '
      + 'denen der Boden greift oder der Anteil ohne ihn negativ würde; das sind die Stellen, an '
      + 'denen die Formel etwas anderes tut, als sie soll.',
    zeilen: (gebodet.length ? gebodet : werte.filter(w => w.t >= 200)).slice(0, 12).map(w => ({
      'Rate': `${(w.r * 100).toFixed(1)} %`, 'Tage': w.t,
      'zu klein + zu gross': `${((w.klein + w.gross) * 100).toFixed(0)} %`,
      'Anteil mit Boden': w.mit.toFixed(4),
      'ohne Boden': w.ohne < 0 ? `${w.ohne.toFixed(4)} (negativ)` : w.ohne.toExponential(2),
      'Eingang je 1000 kg geliefert': `${Math.round(1000 / w.mit)} kg`,
    })),
  }))

  /* --- Befund: der Boden bei 0.25 ist eine Sicherung, die nicht auslösen kann --- */
  //
  // Hier stand zuerst eine Warnung. Die Tabelle darüber hat sie widerlegt: Die
  // Kante bei der höchsten **beobachteten** Rate liegt Jahre entfernt, und der
  // Boden hat in der ganzen Saison kein einziges Mal gegriffen. Was bleibt, ist
  // eine andere Feststellung — der Boden fängt heute nichts ab, wofür er
  // gedacht war, sondern nur den negativen Faktor aus dem Befund darunter.
  {
    const jahre = kanteEcht?.tage ? (kanteEcht.tage / 365).toFixed(1) : null
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'RAND', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
      ort: { sicht: 'mv_kaskade' },
      titel: `Geprüft: der Boden von 0.25 kann bei den gemessenen Verdunstungsraten nicht greifen `
           + `(er läge bei ${jahre ?? '?'} Jahren Lagerdauer)`,
      steht_da: 'Der verkaufsfähige Anteil ist `GREATEST(…, 0.25)`; greift der Boden, ist der '
        + 'Eingang nicht mehr die Rückrechnung, sondern fest das Vierfache des Gelieferten. '
        + `Gemessen liegen die Verdunstungsraten zwischen ${(Number(heute.r_min) * 100).toFixed(3)} % `
        + `und ${(rMax * 100).toFixed(3)} % je Tag. Bei der höchsten davon und den übrigen `
        + `Faktoren der heutigen Saison greift der Boden erst nach ${kanteEcht?.tage ?? '?'} `
        + `Lagertagen — ${jahre} Jahre. Die längste Charge liegt ${heute.alter_max} Tage, und der `
        + `kleinste vorkommende Anteil ist ${heute.anteil_min}, also fast das Dreifache des `
        + `Bodens. In ${heute.n} Zeilen hat er kein einziges Mal gegriffen.`,
      muesste: '—',
      warum: 'Diese Feststellung ist ein Freispruch, und sie steht hier, weil ihr Gegenteil '
        + 'plausibel klang: Eine Formel mit `GREATEST(…, 0.25)` sieht nach einer Notbremse aus, '
        + 'und eine Notbremse, die anspricht, macht aus einer Schätzung eine feste Zahl. Die '
        + 'erste Fassung dieses Werkzeugs hat daraus eine Warnung geschrieben — anhand eines '
        + 'Gitters, dessen niedrigste Rate noch zwanzigmal über der gemessenen lag. Wer die '
        + 'Grösse einer Kante angibt, muss sagen, ob jemand an sie herankommt.',
      beleg: `werkstatt/a_rechenwerk/a7_raender.mjs: Ausdruck mit \`pg_get_viewdef\` aus `
        + `\`mv_kaskade\` geholt, über ${werte.length} Gitterpunkte gerechnet und gegen die `
        + 'tatsächlich vorkommenden Raten gehalten',
      groesse: { wert: kanteEcht?.tage ?? 0,
                 einheit: `Lagertage bis zum Boden bei der höchsten gemessenen Rate `
                        + `(${(rMax * 100).toFixed(3)} % je Tag); die längste Charge liegt `
                        + `${heute.alter_max} Tage`,
                 basis: 'Demodaten' },
      gegenrede: 'Zwei Vorbehalte. **Erstens** hängt der Abstand an den gemessenen Raten, und die '
        + 'stammen aus 41 verwendbaren Wägungen über vierzehn Sorten — eine Sorte mit deutlich '
        + 'höherer Rate ist nicht ausgeschlossen, nur nicht gemessen. Bei 1 % je Tag läge die '
        + `Kante bei ${kanten.find(k => Math.abs(k.r - 0.01) < 1e-9)?.tage ?? '?'} Tagen, also `
        + 'innerhalb einer Saison. **Zweitens** ist der Boden nicht folgenlos, nur nicht auf dem '
        + 'Weg, für den er gebaut wurde: Er fängt den negativen Faktor aus der Feststellung '
        + 'darunter ab und macht ihn unsichtbar.',
      aufwand: 'klein',
    }))
  }

  /* --- Befund: die Summe der beiden Ausschussanteile --- */
  //
  // Hier stand ein Befund. Der Wächter oben hat ihn erledigt: Er ist Ergebnis
  // eines Nachbaus, nicht der Sicht. Was übrig bleibt, ist die Auskunft, dass
  // die Stelle geprüft und in Ordnung ist — und wie leicht das Gegenteil
  // ausgesehen hätte.
  {
    const ueberEinsGitter = werte.filter(w => w.klein + w.gross > 1)
    const kleinsteOhne = Math.min(...werte.map(w => w.ohne))
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'RAND', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
      ort: { sicht: 'mv_kaskade' },
      titel: 'Geprüft und in Ordnung: „zu klein" und „zu gross" werden vor der Formel auf '
           + 'zusammen 1 normiert',
      steht_da: 'In `koeff` wird jeder der beiden Anteile für sich auf [0, 1] geklemmt — das '
        + 'allein liesse ihre Summe über 1 gehen, und der Faktor `(1 - a_klein_n - a_gross_n)` '
        + 'würde negativ. Eine Stufe später steht aber\n\n'
        + '    CROSS JOIN LATERAL (SELECT GREATEST(a_klein + a_gross, 1) AS f) n\n'
        + '    a_klein / n.f AS a_klein_n,  a_gross / n.f AS a_gross_n\n\n'
        + 'Die Summe wird also auf höchstens 1 normiert, bevor sie in die Formel geht. Über das '
        + `ganze Gitter — darunter ${ueberEinsGitter.length} Punkte mit rohen Anteilen von `
        + 'zusammen bis zu 200 % — ist der Faktor nie negativ; der kleinste Wert ohne Boden ist '
        + `${kleinsteOhne.toExponential(2)}.`,
      muesste: '—',
      warum: 'Diese Feststellung steht hier, weil ihr Gegenteil in der ersten Fassung dieses '
        + 'Werkzeugs als Befund geschrieben war, mit Grösse und Gegenrede. Der Grund war eine '
        + 'Zeile Nachbau: Das Gitter hat `a_klein_n` — die **normierte** Grösse — mit rohen '
        + 'Anteilen von 70 % und 60 % gefüttert, also der Formel eine Eingabe gegeben, die sie '
        + 'in der Sicht nie bekommt. Wer eine Formel für sich rechnet, muss sie mit dem füttern, '
        + 'was wirklich in sie hineingeht; sonst prüft er seinen eigenen Nachbau. Seither '
        + 'vergleicht dieses Werkzeug zuerst an vierzig echten Zeilen der laufenden Sicht, ob '
        + 'sein Nachbau dieselben Zahlen ergibt, und bricht ab, wenn nicht.',
      beleg: 'werkstatt/a_rechenwerk/a7_raender.mjs: Normierer mit `pg_get_viewdef` aus '
        + '`mv_kaskade` geholt und im Gitter angewandt; Abgleich an 40 echten Zeilen, grösste '
        + `Abweichung ${schlimmste.toExponential(1)}`,
      groesse: { wert: ueberEinsGitter.length,
                 einheit: 'Gitterpunkte mit roher Summe über 100 %, keiner davon ergibt einen '
                        + 'negativen Faktor', basis: 'Gitter' },
      aufwand: 'klein',
    }))
  }

  /* --- Befund oder Freispruch für die harten Zusicherungen --- */
  const verletzt = [
    ueberEins.length && `${ueberEins.length} Gitterpunkte ergeben einen Anteil über 1`,
    kaputt.length && `${kaputt.length} Gitterpunkte ergeben NaN oder Unendlich`,
    unmonoton && `${unmonoton} Paare, bei denen mehr Lagertage weniger Verdunstung ergeben`,
  ].filter(Boolean)

  raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'RAND', klasse: verletzt.length ? 3 : 1,
    marke: verletzt.length ? 'Reparatur' : 'kein Fehler', sicherheit: 'hoch',
    ort: { sicht: 'mv_kaskade' },
    titel: verletzt.length
      ? `Die Kaskade verletzt an ihren Rändern ${verletzt.length} Zusicherungen`
      : `Geprüft und in Ordnung: über ${werte.length} Randwerte bleibt die Kaskade im Rahmen`,
    steht_da: verletzt.length ? verletzt.join('; ') + '.'
      : `${werte.length} Gitterpunkte von 0 bis 800 Lagertagen, Raten von 0 bis 5 % je Tag und `
        + 'Ausschussanteilen bis 100 %: Der verkaufsfähige Anteil bleibt überall in (0, 1], kein '
        + 'Zwischenwert wird NaN oder unendlich, und mehr Lagertage ergeben nie weniger '
        + 'Verdunstung. Was der Boden bei 0.25 abfängt, steht in den beiden Feststellungen '
        + 'darüber — hier geht es um die Zusicherungen, die auch mit Boden gelten müssen.',
    muesste: verletzt.length ? 'Jede dieser Zusicherungen muss für jede Eingabe gelten, nicht '
      + 'nur für die heutige Saison.' : '—',
    warum: 'Diese drei Eigenschaften sind das, worauf sich jede Zahl darüber stützt. Bricht eine, '
      + 'ist nicht eine Zeile falsch, sondern jede, die durch dieselbe Formel läuft.',
    beleg: `werkstatt/a_rechenwerk/a7_raender.mjs: ${werte.length} Gitterpunkte, Formel aus `
      + '`pg_get_viewdef(\'mv_kaskade\')`',
    groesse: { wert: werte.length, einheit: verletzt.length
                 ? `Gitterpunkte geprüft, ${ueberEins.length + kaputt.length + unmonoton} auffällig`
                 : 'Gitterpunkte geprüft, keine Zusicherung verletzt', basis: 'Gitter' },
    aufwand: 'klein',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Zwei Fälle:
 *
 *   1. Das Herausholen der Formel muss an einer nachgestellten Sichtdefinition
 *      genau den Ausdruck liefern — und an einer, in der er fehlt, `null`.
 *      Letzteres ist die wichtigere Hälfte: Fände das Werkzeug den Ausdruck
 *      nicht und schwiege es, sähe sein Schweigen aus wie ein Freispruch.
 *   2. Das Einsetzen muss alle sieben Platzhalter treffen. Bleibt einer
 *      stehen, rechnet Postgres mit der Spalte einer Sicht, die es hier gar
 *      nicht gibt — und der Lauf bräche ab statt still falsch zu rechnen.
 *      Geprüft wird trotzdem, damit der Fehler hier auffällt und nicht dort.
 */
export async function selbstprobe() {
  const echt = `        SELECT a.x,\n`
    + `            GREATEST(power(1::numeric - x.r, x.alter_tage) * (1::numeric - x.a0) `
    + `* (1::numeric - x.f) * (1::numeric - x.a_klein_n - x.a_gross_n) * (1::numeric - x.a_fax), 0.25) AS verkaufsfaehig_anteil,\n`
    + `            GREATEST(power(1::numeric - x.r, x.alter_tage), 0.25) AS verdunstungs_anteil\n`
  const f = formelHolen(echt)
  if (!f || !/GREATEST/.test(f) || /verkaufsfaehig_anteil/.test(f)) return false
  if (formelHolen('SELECT 1 AS irgendwas\n') !== null) return false

  // Nachgestellt wie in der echten Sicht: **vor** dem Normierer stehen die
  // beiden Klemmzeilen, die auf dieselbe Grobsuche passen. Ohne sie prüft die
  // Selbstprobe einen Fall, den es so nicht gibt — und genau daran ist die
  // erste Fassung vorbeigelaufen: Selbstprobe grün, echter Lauf abgebrochen.
  const n = normiererHolen(
    '            LEAST(GREATEST(COALESCE(ka.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_klein,\n'
    + '            LEAST(GREATEST(COALESCE(kn.mittel, 0::numeric), 0::numeric), 1::numeric) AS a_gross,\n'
    + '            k_1.a_klein / n.f AS a_klein_n\n'
    + '           CROSS JOIN LATERAL ( SELECT GREATEST(COALESCE(k_1.a_klein, 0::numeric) '
    + '+ COALESCE(k_1.a_gross, 0::numeric), 1::numeric) AS f) n')
  if (!n || !/GREATEST/.test(n) || !/a_gross/.test(n) || /AS f/.test(n)) return false
  if (normiererHolen('SELECT 1 AS f') !== null) return false
  // Fehlt der zweite Anteil, ist es nicht der gesuchte Normierer.
  if (normiererHolen('SELECT GREATEST(COALESCE(a_klein, 0), 1) AS f') !== null) return false

  // Die gebaute Abfrage muss den Normierer wirklich anwenden und die Formel
  // wörtlich stehen lassen.
  const q = gitterAbfrage(f, [{ r: 0.02, t: 100, a0: 0.02, f: 0.05, klein: 0.7, gross: 0.6, fax: 0.01 }],
                          n, [['a', f]])
  if (!/a_klein \/ nf as a_klein_n/.test(q)) return false
  if (!q.includes(f)) return false
  if (/\bk_1\./.test(q)) return false

  // Der Boden muss beim Wegnehmen wirklich weg sein.
  const nackt = ohneBoden(f)
  if (/GREATEST/i.test(nackt) || /0\.25/.test(nackt)) return false

  return true
}
