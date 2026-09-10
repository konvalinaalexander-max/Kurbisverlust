/**
 * C1 — Vermessung: wo ist der Code zu blockig, und was liesse sich streichen?
 *
 * WARUM ES DIESES WERKZEUG GIBT
 *
 * C2 findet Objekte, deren Definition **zeichengleich** ist. Das ist der
 * saubere Fall und deshalb der seltene: genau ein Paar in der ganzen
 * Datenbank. Der häufige Fall ist der unsaubere — zwei Stücke Code, die
 * dasselbe tun und sich in einem Namen, einer Zahl, einer Zeile
 * unterscheiden. Zeichenvergleich sieht davon nichts.
 *
 * Dieses Werkzeug vergleicht deshalb nicht Zeichen, sondern **Formen**. Jede
 * Datei wird in Wortmarken zerlegt; Bezeichner, Zeichenketten und Zahlen
 * werden durch Platzhalter ersetzt. Was bleibt, ist das Gerüst. Zwei Blöcke
 * mit gleichem Gerüst tun mit hoher Wahrscheinlichkeit dasselbe, auch wenn
 * kein einziges Wort übereinstimmt.
 *
 * WAS ES MISST
 *
 *   Klone       Blöcke ab 60 Wortmarken, deren Gerüst an zwei oder mehr
 *               Stellen steht. Gemeldet wird der **längste** Block je Paar,
 *               nicht jeder Teilblock — sonst zählt ein Klon von 200 Marken
 *               hundertfach.
 *
 *   Brocken     Die längsten Funktionen und Komponenten, gemessen an Zeilen
 *               und an der grössten Verschachtelungstiefe. Eine lange
 *               Funktion ist für sich kein Fehler; eine lange Funktion mit
 *               Tiefe 6 ist eine, die niemand mehr im Kopf hat.
 *
 *   SQL-Seite   Dasselbe für die Ansichten der Datenbank: wie viele Zeilen,
 *               wie viele CTE-Stufen, wie tief geschachtelt.
 *
 * WAS ES NICHT TUT
 *
 * Es schlägt keine Umbauten vor, die es nicht belegen kann. Ein Klon ist eine
 * Feststellung mit einer Grösse in Zeilen — ob er zusammengelegt werden
 * *soll*, hängt daran, ob die beiden Stellen aus demselben Grund gleich sind
 * oder aus Zufall. Das steht in der Gegenrede, nicht in der Überschrift.
 *
 * Und es misst **keine** Kennzahl, aus der sich eine Note bilden liesse. Eine
 * Zahl wie „durchschnittliche Komplexität 4.2" beantwortet keine Frage, die
 * dieser Betrieb hat.
 */
import { readFileSync } from 'node:fs'
import { frage, lies, alleDateien, befund, messung, WURZEL } from '../umgebung.mjs'
import { relative, join } from 'node:path'

export const lang = false

const WERKSTATT = 'C — Bauwerk'

/** Ab wie vielen Wortmarken ein gleicher Block als Klon zählt. */
const MINDESTMARKEN = 60

/* ---------- Zerlegen ------------------------------------------------------ */

/**
 * Zerlegt Quelltext in Wortmarken und normalisiert sie zu einem Gerüst.
 *
 * Bezeichner werden zu `n`, Zahlen zu `0`, Zeichenketten zu `s`. Damit ist
 * `const kg = netto(a) * 1.5` dasselbe Gerüst wie `const t = brutto(b) * 2.0` —
 * und genau das ist gewollt: Die beiden Zeilen sind derselbe Handgriff.
 *
 * Schlüsselwörter bleiben stehen. Wären auch sie Platzhalter, würden `if` und
 * `for` gleich aussehen, und das Gerüst hiesse nichts mehr.
 *
 * Kommentare fallen weg. Ein Klon bleibt ein Klon, auch wenn über der einen
 * Fassung eine Erklärung steht und über der anderen nicht.
 */
const SCHLUESSEL = new Set(('const let var function return if else for while do switch case break '
  + 'continue new typeof instanceof in of class extends import export from as await async yield '
  + 'try catch finally throw delete void null true false this super default interface type enum '
  + 'select from where group by having order limit offset join left right inner outer full on '
  + 'with as union all except intersect case when then else end and or not is null coalesce '
  + 'sum count avg min max over partition distinct').split(' '))

export function marken(text, { sql = false } = {}) {
  const ohneKommentare = sql
    ? text.replace(/--[^\n]*/g, ' ').replace(/\/\*[\s\S]*?\*\//g, ' ')
    : text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:"'`])\/\/[^\n]*/g, '$1 ')
  const roh = ohneKommentare.match(/'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`|[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|[^\s\w]/g) ?? []
  const aus = []
  for (const m of roh) {
    if (/^['"`]/.test(m)) aus.push({ marke: 's', roh: m })
    else if (/^\d/.test(m)) aus.push({ marke: '0', roh: m })
    else if (/^[A-Za-z_$]/.test(m)) aus.push({ marke: SCHLUESSEL.has(m.toLowerCase()) ? m.toLowerCase() : 'n', roh: m })
    else aus.push({ marke: m, roh: m })
  }
  return aus
}

/* ---------- Klone --------------------------------------------------------- */

/**
 * Sucht Blöcke ab `mindest` Wortmarken, deren Gerüst mehrfach vorkommt.
 *
 * Verfahren: Über alle Dateien läuft ein Fenster fester Länge; sein Gerüst
 * ist der Schlüssel. Zwei Fenster mit gleichem Schlüssel sind ein Treffer.
 * Danach wird jeder Treffer nach vorn und hinten verlängert, solange die
 * Marken übereinstimmen, und Treffer, die vollständig in einem längeren
 * liegen, fallen weg. Sonst meldet ein Klon von 200 Marken 141 Treffer.
 *
 * Der Aufwand ist linear in der Zahl der Marken; auf diesem Bestand sind das
 * rund 200 000, und der Lauf dauert unter einer Sekunde.
 */
export function klone(dateien, mindest = MINDESTMARKEN) {
  const eintraege = dateien.map(d => ({ ...d, m: d.marken.map(x => x.marke) }))
  const nach = new Map()
  eintraege.forEach((d, di) => {
    for (let i = 0; i + mindest <= d.m.length; i++) {
      const s = d.m.slice(i, i + mindest).join(' ')
      if (!nach.has(s)) nach.set(s, [])
      nach.get(s).push([di, i])
    }
  })

  const roh = []
  for (const stellen of nach.values()) {
    if (stellen.length < 2) continue
    // Nur das erste Paar je Gerüst — die anderen entstehen aus demselben Klon.
    const [[ai, aStart], [bi, bStart]] = stellen
    if (ai === bi && Math.abs(aStart - bStart) < mindest) continue   // Überlappung mit sich selbst
    const A = eintraege[ai].m, B = eintraege[bi].m
    let a0 = aStart, b0 = bStart, a1 = aStart + mindest, b1 = bStart + mindest
    while (a0 > 0 && b0 > 0 && A[a0 - 1] === B[b0 - 1]) { a0--; b0-- }
    while (a1 < A.length && b1 < B.length && A[a1] === B[b1]) { a1++; b1++ }
    roh.push({ a: eintraege[ai], b: eintraege[bi], a0, a1, b0, b1, laenge: a1 - a0,
               weitere: stellen.length - 2 })
  }

  // Was ganz in einem längeren Treffer derselben zwei Dateien liegt, fällt weg.
  roh.sort((x, y) => y.laenge - x.laenge)
  const bleibt = []
  for (const r of roh) {
    const drin = bleibt.some(g => g.a === r.a && g.b === r.b
      && r.a0 >= g.a0 && r.a1 <= g.a1 && r.b0 >= g.b0 && r.b1 <= g.b1)
    if (!drin) bleibt.push(r)
  }
  return bleibt
}

/** Auf welcher Zeile steht die Marke mit diesem Index? */
function zeileVonMarke(text, marken, index) {
  const bis = marken.slice(0, index).reduce((n, m) => n + m.roh.length, 0)
  // Grob, aber ausreichend: Wir suchen die Marke selbst im Text.
  let stelle = 0, gefunden = 0
  for (let i = 0; i <= index && i < marken.length; i++) {
    const s = text.indexOf(marken[i].roh, stelle)
    if (s < 0) break
    stelle = s + marken[i].roh.length
    gefunden = s
  }
  void bis
  return text.slice(0, gefunden).split('\n').length
}

/* ---------- Brocken ------------------------------------------------------- */

/**
 * Die grösste Verschachtelungstiefe einer Datei, gezählt an geschweiften
 * Klammern ausserhalb von Zeichenketten.
 */
export function tiefe(marken) {
  let jetzt = 0, groesste = 0
  for (const m of marken) {
    if (m.marke === '{') { jetzt++; if (jetzt > groesste) groesste = jetzt }
    else if (m.marke === '}') jetzt = Math.max(0, jetzt - 1)
  }
  return groesste
}

/**
 * Findet die Funktionen und Komponenten einer Datei mit ihrer Länge in Zeilen.
 *
 * Kein Parser — gesucht wird der Beginn (`function n(`, `const n = (…) =>`,
 * `export function n(`) und danach die zugehörige schliessende Klammer über
 * einen Klammerzähler. Das reicht für eine Vermessung; falsch liegt es nur
 * dort, wo eine geschweifte Klammer in einer Zeichenkette steht, und die
 * Marken haben Zeichenketten bereits ersetzt.
 */
export function bloecke(text) {
  const zeilen = text.split('\n')
  const aus = []
  const anfang = /^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)|^\s*(?:export\s+)?const\s+([A-Za-z_$][\w$]*)\s*(?::[^=]*)?=\s*(?:async\s*)?\(/
  for (let i = 0; i < zeilen.length; i++) {
    const m = anfang.exec(zeilen[i])
    if (!m) continue
    const name = m[1] ?? m[2]
    let auf = 0, gestartet = false, ende = i
    for (let j = i; j < zeilen.length; j++) {
      const ohne = zeilen[j].replace(/'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`/g, '')
      for (const c of ohne) { if (c === '{') { auf++; gestartet = true } else if (c === '}') auf-- }
      if (gestartet && auf <= 0) { ende = j; break }
      ende = j
    }
    if (!gestartet) continue
    aus.push({ name, von: i + 1, bis: ende + 1, zeilen: ende - i + 1,
               tiefe: tiefe(marken(zeilen.slice(i, ende + 1).join('\n'))) })
    i = ende
  }
  return aus
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const raus = []

  /* --- TypeScript --- */
  const ts = alleDateien('src', { muster: /\.(ts|tsx)$/ })
    .concat(alleDateien('test', { muster: /\.(ts|tsx)$/ }))
    .map(d => {
      const text = lies(d.pfad)
      return { pfad: d.pfad, text, marken: marken(text), zeilen: text.split('\n').length }
    })

  /* --- SQL: die Ansichten, wie sie in der laufenden Datenbank stehen --- */
  const sichten = frage(db, `
    select c.relname as name, pg_get_viewdef(c.oid, true) as text
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('v', 'm')
     order by c.relname`).map(z => ({
      pfad: `Datenbank: ${z.name}`, text: z.text,
      marken: marken(z.text, { sql: true }), zeilen: z.text.split('\n').length,
    }))

  const gefundene = klone(ts)
  const sqlKlone = klone(sichten, 120)   // SQL ist wortreicher; 60 Marken sind dort eine Zeile

  const markenGesamt = ts.reduce((a, d) => a + d.marken.length, 0)

  /* --- Messung: die Klone --- */
  const top = gefundene.slice(0, 12)
  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Gleiche Formen im Frontend-Code', einheit: 'Klonpaare',
    spalten: ['Länge (Wortmarken)', 'Stelle A', 'Stelle B', 'weitere Stellen', 'Zeilen A'],
    erklaerung: `${markenGesamt} Wortmarken in ${ts.length} Dateien. Verglichen werden nicht `
      + 'Zeichen, sondern Gerüste: Bezeichner, Zahlen und Zeichenketten sind durch Platzhalter '
      + `ersetzt, Schlüsselwörter stehen. Ein Treffer ab ${MINDESTMARKEN} Marken zählt; er wird `
      + 'nach beiden Seiten verlängert, solange die Formen gleich bleiben, und Treffer innerhalb '
      + `längerer fallen weg. Gefunden: ${gefundene.length} Paare.`,
    zeilen: top.length ? top.map(k => ({
      'Länge (Wortmarken)': k.laenge,
      'Stelle A': `${k.a.pfad}:${zeileVonMarke(k.a.text, k.a.marken, k.a0)}`,
      'Stelle B': `${k.b.pfad}:${zeileVonMarke(k.b.text, k.b.marken, k.b0)}`,
      'weitere Stellen': k.weitere,
      'Zeilen A': zeileVonMarke(k.a.text, k.a.marken, k.a1) - zeileVonMarke(k.a.text, k.a.marken, k.a0) + 1,
    })) : [{ 'Länge (Wortmarken)': '—', 'Stelle A': 'kein Paar ab 60 Marken', 'Stelle B': '—',
             'weitere Stellen': '—', 'Zeilen A': '—' }],
  }))

  /* --- Messung: die Brocken --- */
  const alleBloecke = ts.flatMap(d => bloecke(d.text).map(b => ({ ...b, pfad: d.pfad })))
    .sort((a, b) => b.zeilen - a.zeilen)
  const brocken = alleBloecke.slice(0, 12)
  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Die längsten Funktionen und Komponenten', einheit: 'Zeilen',
    spalten: ['Datei', 'Name', 'Zeilen', 'Tiefe', 'von–bis'],
    erklaerung: `${alleBloecke.length} Funktionen und Komponenten in ${ts.length} Dateien, `
      + `zusammen ${ts.reduce((a, d) => a + d.zeilen, 0)} Zeilen. Länge allein ist kein Mangel — `
      + 'eine Seite mit acht Abschnitten ist lang, weil sie acht Abschnitte hat. Die Spalte '
      + '**Tiefe** ist die aussagekräftigere: Sie zählt geschachtelte Blöcke, und ab vier hat '
      + 'niemand mehr alle Fälle gleichzeitig im Kopf.',
    zeilen: brocken.map(b => ({
      'Datei': b.pfad, 'Name': `\`${b.name}\``, 'Zeilen': b.zeilen, 'Tiefe': b.tiefe,
      'von–bis': `${b.von}–${b.bis}`,
    })),
  }))

  /* --- Befund: Klone im Frontend --- */
  const grosse = gefundene.filter(k => k.laenge >= 100)
  const zeilenGesamt = grosse.reduce((a, k) =>
    a + (zeileVonMarke(k.b.text, k.b.marken, k.b1) - zeileVonMarke(k.b.text, k.b.marken, k.b0) + 1), 0)

  if (grosse.length) {
    const k = grosse[0]
    const aZ = zeileVonMarke(k.a.text, k.a.marken, k.a0)
    const bZ = zeileVonMarke(k.b.text, k.b.marken, k.b0)
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'FORM', klasse: 2, marke: 'Reduktion', sicherheit: 'hoch',
      ort: { datei: `${k.a.pfad}:${aZ}` },
      titel: `${grosse.length} Stellen im Frontend haben dieselbe Form wie eine andere `
           + `(zusammen rund ${zeilenGesamt} Zeilen)`,
      steht_da: `Der längste Fall steht in \`${k.a.pfad}:${aZ}\` und noch einmal in `
        + `\`${k.b.pfad}:${bZ}\` — ${k.laenge} Wortmarken lang, also nicht zwei ähnliche Zeilen, `
        + 'sondern ein zusammenhängender Handgriff. Verglichen wurden Gerüste, nicht Zeichen: '
        + 'Bezeichner, Zahlen und Zeichenketten sind ersetzt, damit zwei Stellen auch dann '
        + `gleich heissen, wenn keine Variable gleich heisst. Insgesamt ${grosse.length} Paare `
        + `ab 100 Marken, ${gefundene.length} ab ${MINDESTMARKEN}.`,
      muesste: 'Wo zwei Stellen aus demselben Grund gleich sind, gehört der Handgriff einmal in '
        + 'eine Funktion und zweimal aufgerufen. Wo sie zufällig gleich sind — zwei Tabellen mit '
        + 'gleichem Aufbau und verschiedener Bedeutung —, bleiben sie besser getrennt. Diese '
        + 'Entscheidung fällt je Paar, nicht pauschal; die Messreihe darüber nennt alle.',
      warum: 'Ein Klon ist keine doppelte Sicherheit, sondern eine halbe: Wer eine Zahl in der '
        + 'einen Fassung richtigstellt und die andere übersieht, hat zwei Anzeigen, die dasselbe '
        + 'heissen und verschieden sind. Genau so ist die zweite Schimmelrechnung entstanden.',
      beleg: 'werkstatt/c_bauwerk/c1_vermessung.mjs: Wortmarken normalisiert, Fenster ab '
        + `${MINDESTMARKEN} Marken, Treffer beidseitig verlängert, enthaltene Treffer entfernt`,
      groesse: { wert: zeilenGesamt, einheit: `Zeilen, die in ${grosse.length} Paaren ein zweites `
                 + 'Mal dastehen (die längere Hälfte je Paar nicht mitgezählt)', basis: 'src/ und test/' },
      gegenrede: 'Gleiche Form ist nicht gleiche Bedeutung. Zwei Bildschirme, die je eine Tabelle '
        + 'mit Filterzeile zeigen, haben dieselbe Form, weil eine Tabelle mit Filterzeile nun '
        + 'einmal so aussieht — daraus eine gemeinsame Funktion zu schnitzen, macht beide Seiten '
        + 'schwerer zu lesen und die gemeinsame Funktion zu einem Ding mit sieben Schaltern. Der '
        + 'Befund nennt deshalb eine Zahl und keine Anweisung. Und: Die Zeilenzahl ist die obere '
        + 'Schranke des Ersparten, nicht das Ersparte — jede Zusammenlegung kostet ihrerseits '
        + 'einen Funktionskopf und eine Aufrufstelle.',
      aufwand: 'mittel',
    }))
  } else {
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'FORM', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
      ort: { datei: 'src/' },
      titel: `Geprüft und in Ordnung: kein Stück Frontend-Code ab 100 Wortmarken steht zweimal`,
      steht_da: `${markenGesamt} Wortmarken in ${ts.length} Dateien, Gerüste verglichen — `
        + `${gefundene.length} Paare ab ${MINDESTMARKEN} Marken, keines ab 100.`,
      muesste: '—',
      warum: 'Doppelter Code läuft auseinander, sobald jemand eine der beiden Stellen anfasst.',
      beleg: 'werkstatt/c_bauwerk/c1_vermessung.mjs',
      groesse: { wert: markenGesamt, einheit: 'Wortmarken verglichen, kein grosser Klon',
                 basis: 'src/ und test/' },
      aufwand: 'klein',
    }))
  }

  /* --- Befund: Klone im SQL --- */
  if (sqlKlone.length) {
    const k = sqlKlone[0]
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'FORM', klasse: 2, marke: 'Reduktion', sicherheit: 'mittel',
      ort: { sicht: k.a.pfad.replace('Datenbank: ', '') },
      titel: `${sqlKlone.length} Ansichten enthalten ein Stück SQL, das anderswo genauso steht`,
      steht_da: `Der längste Fall verbindet \`${k.a.pfad.replace('Datenbank: ', '')}\` und `
        + `\`${k.b.pfad.replace('Datenbank: ', '')}\` über ${k.laenge} Wortmarken. C2 sieht das `
        + 'nicht: Die beiden Ansichten sind als Ganzes verschieden, gleich ist nur ein Stück '
        + 'darin. Verglichen wurde das Gerüst der von PostgreSQL zurückgegebenen Definition, '
        + 'nicht der Quelltext der Migration — Formatierung spielt damit keine Rolle.',
      muesste: 'Ein Stück Rechnung, das in zwei Ansichten gleich dasteht, gehört in eine eigene '
        + 'Ansicht, die beide lesen. Dann steht die Formel einmal da und ändert sich einmal.',
      warum: 'Bei SQL wiegt das schwerer als im Frontend: Eine Formel, die an zwei Stellen steht '
        + 'und an einer geändert wird, ergibt zwei Zahlen, die beide plausibel aussehen. Im '
        + 'Frontend fällt so etwas beim Ansehen auf, in einer Ansicht nicht.',
      beleg: 'werkstatt/c_bauwerk/c1_vermessung.mjs: `pg_get_viewdef` aller Ansichten in '
        + 'Wortmarken zerlegt, Fenster ab 120 Marken',
      groesse: { wert: sqlKlone.length,
                 einheit: `Stellenpaare ab 120 Wortmarken (längstes ${k.laenge})`, basis: 'Demodaten' },
      gegenrede: 'Eine gemeinsame Zwischenansicht ist nicht gratis: Sie ist ein weiteres Objekt '
        + 'in einer Kette, die schon neunzig Objekte lang ist, und der Planer muss sie jedes Mal '
        + 'mit auflösen. Wo das gleiche Stück ein `join` auf dieselbe Stammtabelle ist, ist es '
        + 'zudem eher eine Selbstverständlichkeit als eine Doppelung. Die Zahl ist deshalb eine '
        + 'Liste zum Durchsehen, keine Aufgabenliste.',
      aufwand: 'mittel',
    }))
  }

  /* --- Befund: tiefe Brocken --- */
  const tief = alleBloecke.filter(b => b.tiefe >= 6)
  if (tief.length) {
    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'FORM', klasse: 1, marke: 'Reduktion', sicherheit: 'hoch',
      ort: { datei: `${tief[0].pfad}:${tief[0].von}` },
      titel: `${tief.length} Funktionen sind sechs Blöcke oder tiefer geschachtelt`,
      steht_da: tief.slice(0, 5).map(b => `\`${b.name}\` in ${b.pfad}:${b.von} `
        + `(${b.zeilen} Zeilen, Tiefe ${b.tiefe})`).join('; ')
        + (tief.length > 5 ? ` und ${tief.length - 5} weitere.` : '.'),
      muesste: 'Die inneren Blöcke gehören in eigene Funktionen mit sprechendem Namen. Das macht '
        + 'den Code nicht kürzer — es macht ihn lesbar, und darum geht es.',
      warum: 'Ab Tiefe vier hält niemand mehr alle Fälle gleichzeitig im Kopf. Genau dort '
        + 'entstehen die Fehler, die kein Test findet, weil niemand den Fall erdenkt, den der '
        + 'sechste Block behandelt.',
      beleg: 'werkstatt/c_bauwerk/c1_vermessung.mjs: geschweifte Klammern ausserhalb von '
        + 'Zeichenketten gezählt, je Funktion',
      groesse: { wert: tief.length, einheit: `Funktionen mit Tiefe ≥ 6 von ${alleBloecke.length}`,
                 basis: 'src/ und test/' },
      gegenrede: 'Tiefe entsteht auch aus JSX: Ein Bildschirm mit Karte, Tabelle, Zeile und Zelle '
        + 'ist vier Ebenen tief, bevor eine einzige Bedingung darin steht — und das ist kein '
        + 'Mangel, sondern die Form des Dokuments. Der Zähler unterscheidet das nicht. Wer die '
        + 'Liste durchgeht, muss also je Fall entscheiden, ob die Tiefe aus Logik oder aus '
        + 'Auszeichnung kommt.',
      aufwand: 'mittel',
    }))
  }

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Vier erfundene Fälle:
 *
 *   1. Zwei Blöcke, die sich in **jedem Bezeichner** unterscheiden und
 *      dieselbe Form haben — müssen gefunden werden. Das ist der Fall, für
 *      den es das Werkzeug gibt; ein Zeichenvergleich sieht ihn nicht.
 *   2. Zwei Blöcke mit **verschiedener Form** — dürfen nicht gefunden werden.
 *      Ein Werkzeug, das alles für einen Klon hält, ist wertlos.
 *   3. Ein Block, der ganz in einem längeren Treffer liegt, darf nicht ein
 *      zweites Mal gemeldet werden.
 *   4. Der Tiefenzähler muss eine Zeichenkette mit `{` überstehen.
 */
export async function selbstprobe() {
  const bau = (namen) => 'function ' + namen[0] + '(' + namen[1] + ') {\n'
    + Array.from({ length: 12 }, (_, i) =>
        `  const ${namen[2]}${i} = ${namen[3]}(${namen[1]}, ${i}) + ${namen[4]}[${i}]\n`
        + `  if (${namen[2]}${i} > ${i}) { ${namen[5]}.push(${namen[2]}${i}) }`).join('\n')
    + '\n  return ' + namen[5] + '\n}\n'

  const a = bau(['eins', 'x', 'w', 'rechne', 'liste', 'aus'])
  const b = bau(['zwei', 'y', 'v', 'nimm', 'reihe', 'raus'])
  // Andere Form: keine Bedingung im Rumpf.
  const c = 'function drei(z) {\n'
    + Array.from({ length: 12 }, (_, i) => `  z = z + ${i} * 3 - 1 / 2\n`).join('')
    + '  return z\n}\n'

  const dateien = [a, b, c].map((text, i) => ({ pfad: `p${i}.ts`, text, marken: marken(text) }))
  const g = klone(dateien, 40)

  // 1 + 2: genau ein Paar, und es verbindet p0 mit p1.
  if (g.length !== 1) return false
  if (!((g[0].a.pfad === 'p0.ts' && g[0].b.pfad === 'p1.ts')
     || (g[0].a.pfad === 'p1.ts' && g[0].b.pfad === 'p0.ts'))) return false
  // 3: der Treffer muss über die 40 Marken hinaus verlängert worden sein.
  if (g[0].laenge <= 40) return false

  // 4: eine geschweifte Klammer in einer Zeichenkette darf die Tiefe nicht heben.
  if (tiefe(marken('const s = "{{{{{"\nif (a) { if (b) { c() } }')) !== 2) return false

  // Zwei völlig verschiedene Dateien dürfen kein Paar ergeben.
  if (klone([dateien[2], { pfad: 'p9.ts', text: 'const q = 1\n', marken: marken('const q = 1\n') }], 40).length)
    return false

  return true
}
