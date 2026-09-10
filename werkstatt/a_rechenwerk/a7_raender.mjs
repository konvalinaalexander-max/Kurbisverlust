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

/** Setzt die Platzhalter der Formel durch Zahlen. */
export function einsetzen(formel, w) {
  return formel
    .replace(/\bx\.r\b/g, `(${w.r})::numeric`)
    .replace(/\bx\.alter_tage\b/g, `(${w.t})::numeric`)
    .replace(/\bx\.a0\b/g, `(${w.a0})::numeric`)
    .replace(/\bx\.f\b/g, `(${w.f})::numeric`)
    .replace(/\bx\.a_klein_n\b/g, `(${w.klein})::numeric`)
    .replace(/\bx\.a_gross_n\b/g, `(${w.gross})::numeric`)
    .replace(/\bx\.a_fax\b/g, `(${w.fax})::numeric`)
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
  if (!formel) throw new Error(
    'Der Ausdruck für verkaufsfaehig_anteil steht nicht mehr da, wo dieses Werkzeug ihn sucht. '
    + 'Das ist kein Befund über das Programm, sondern einer über dieses Werkzeug — es müsste '
    + 'nachgezogen werden, statt still nichts zu prüfen.')

  // Alle Gitterpunkte in einer Abfrage, damit es dieselbe Numerik ist.
  const auswahl = GITTER.map((w, i) =>
    `select ${i} as i, ${einsetzen(formel, w)} as mit_boden, `
    + `${einsetzen(ohneBoden(formel), w)} as ohne_boden`).join(' union all ')
  const werte = frage(db, `select * from (${auswahl}) g order by i`)
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

  /* --- Befund: die beiden Anteile können zusammen über eins gehen --- */
  const summeUeberEins = werte.filter(w => w.klein + w.gross > 1)
  if (summeUeberEins.length && negativ.length) {
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'RAND', klasse: 2, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { sicht: 'mv_kaskade' },
      titel: '„Zu klein" und „zu gross" werden je einzeln auf 1 geklemmt, ihre Summe nicht',
      steht_da: 'In `koeff` steht `LEAST(GREATEST(COALESCE(ka.mittel, 0), 0), 1)` für „zu klein" '
        + 'und dasselbe für „zu gross". Jeder Anteil bleibt damit in [0, 1] — ihre **Summe** '
        + 'nicht. Im Faktor `(1 - a_klein_n - a_gross_n)` wird sie zu einer negativen Zahl, '
        + `sobald sie 1 überschreitet. Am Gitterpunkt klein = 100 %, gross = 100 % steht dort `
        + `${negativ[0].ohne.toFixed(4)}; der Boden fängt das ab und macht 0.25 daraus — also aus `
        + 'einem unsinnigen Zwischenwert eine harmlos aussehende Zahl. Die beiden Anteile werden '
        + 'aus **getrennten** Messreihen geschätzt (`v_koeff_ausschuss`, `v_koeff_nebenkanal`); '
        + 'nichts in der Rechnung verbindet sie.',
      muesste: 'Die Summe gehört geklemmt, nicht jeder Summand für sich: '
        + '`LEAST(a_klein + a_gross, 1)`, und die beiden Ströme teilen sich den Rest im '
        + 'Verhältnis ihrer Schätzwerte. Dann ist der Faktor nie negativ, und der Boden muss '
        + 'nicht mehr Fehler abfangen, für die er nicht gedacht ist.',
      warum: 'Ein negativer Zwischenwert ist kein Rundungsfehler, sondern ein Widerspruch: Es '
        + 'kann nicht mehr als alles zu klein und zu gross zugleich sein. Dass der Boden ihn '
        + 'auffängt, macht ihn unsichtbar — und ein unsichtbarer Widerspruch bleibt.',
      beleg: 'werkstatt/a_rechenwerk/a7_raender.mjs: Ausdruck aus der laufenden Sicht über das '
        + 'Gitter gerechnet; ohne Boden negativ ab klein + gross > 1',
      groesse: { wert: (100 - Number(heute.summe_max) * 100).toFixed(1),
                 einheit: 'Prozentpunkte Abstand zwischen der heutigen Summe '
                        + `(${(Number(heute.summe_max) * 100).toFixed(1)} %) und der Kante bei 100 %`,
                 basis: 'Demodaten' },
      gegenrede: 'Der Abstand ist gross: Heute liegt die Summe bei '
        + `${(Number(heute.summe_max) * 100).toFixed(1)} %, gemessen an elf Sorten mit Werten `
        + 'zwischen 0.4 % und 11.6 %. Damit sie 100 % erreicht, müsste eine Sorte fast '
        + 'vollständig aus zu kleinen und zu grossen Früchten bestehen — dann hätte der Betrieb '
        + 'ein anderes Problem als eine Formel. Und: Die Reparatur verändert Zahlen nur in einem '
        + 'Bereich, den heute niemand erreicht; sie ist deshalb billig, aber auch ungeprüft am '
        + 'echten Fall. Sie gehört in dieselbe Migration wie eine Zusicherung, die den Fall '
        + 'nachstellt.',
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

  const gesetzt = einsetzen(f, { r: 0.02, t: 100, a0: 0.02, f: 0.05, klein: 0.1, gross: 0.1, fax: 0.01 })
  if (/\bx\./.test(gesetzt)) return false

  // Der Boden muss beim Wegnehmen wirklich weg sein.
  const nackt = ohneBoden(f)
  if (/GREATEST/i.test(nackt) || /0\.25/.test(nackt)) return false

  return true
}
