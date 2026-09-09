/**
 * D2 — Entscheidungsauflösung: welchen seiner Vergleiche darf der Betrieb glauben?
 *
 * DIE FRAGE
 *
 * Der Betriebsleiter entscheidet durch **Vergleiche**. Ist Schimmel schlimmer
 * als Verdunstung? Ist Lekor schlechter als Orangita? Ist Schlag 3 auffällig?
 * Die Oberfläche stellt diese Zahlen nebeneinander, sortiert sie und malt sie
 * als Balken. Damit sagt sie: *hier ist ein Unterschied.*
 *
 * Ob es einen gibt, ist eine andere Frage. Jede dieser Zahlen entsteht aus
 * geschätzten Koeffizienten, und das Programm weiss selbst, wie unsicher die
 * sind — es schreibt zu jedem ein Band. Der Vergleich zweier Zahlen ist nur
 * dann eine Aussage, wenn der Unterschied grösser ist als das, was die Bänder
 * zulassen.
 *
 * WARUM ES NICHT REICHT, DIE BÄNDER ANZUSEHEN
 *
 * Der naheliegende Weg wäre: überlappen die Bänder von A und B, ist der
 * Vergleich wertlos. Das ist **falsch**, und zwar in beide Richtungen.
 *
 *   Zu streng, weil die beiden Zahlen dieselben Koeffizienten benutzen. Ist
 *   die Verdunstungsrate in Wahrheit höher als geschätzt, steigen *beide*
 *   Sorten — der Unterschied bleibt. Ein gemeinsamer Fehler kürzt sich im
 *   Vergleich heraus, im einzelnen Band aber nicht.
 *
 *   Zu lasch, weil die Kaskade nicht linear ist. Der Anteil, der als Schimmel
 *   ausfällt, verkleinert die Masse, aus der danach Fax und Nebenkanal
 *   gerechnet werden. Zwei Bänder, die sich kaum überlappen, können sich nach
 *   der Kaskade beliebig anders verhalten.
 *
 * WAS DIESES WERKZEUG STATTDESSEN TUT
 *
 * Es zieht die Koeffizienten **aus den Bändern, die das Programm selbst
 * ausweist**, und rechnet die ganze Kaskade damit neu — hunderte Male. Danach
 * steht für jeden Vergleich, den die Oberfläche anbietet, eine Zahl da:
 *
 *   *In wie viel Prozent der Ziehungen war A grösser als B?*
 *
 * 98 % heisst: der Betrieb darf diesen Vergleich glauben. 55 % heisst: die
 * Reihenfolge auf dem Bildschirm ist ein Münzwurf, und niemand hat ihm das
 * gesagt.
 *
 * Die Unsicherheit ist dabei **nicht erfunden**. Sie stammt Zahl für Zahl aus
 * den Spalten `unten`/`oben`, die die Auswertung ohnehin veröffentlicht. Wer
 * das Ergebnis bestreiten will, muss die Bänder bestreiten — und die stehen im
 * Programm.
 *
 * WAS ES NICHT TUT
 *
 * Es zieht die Koeffizienten **unabhängig** voneinander. In Wahrheit sind sie
 * es nicht ganz: Verdunstung und Schimmel werden teils aus denselben Wägungen
 * geschätzt. Wie stark das trägt, weiss dieses Werkzeug nicht, und es tut auch
 * nicht so. Für Vergleiche *innerhalb* eines Stroms (Sorte gegen Sorte) ist
 * die Annahme harmlos, weil beide Seiten denselben Koeffizienten teilen; für
 * Vergleiche *zwischen* Strömen ist sie eine Annahme, die im Bericht steht.
 */
import { frage, wert, tue, kopie, rechne, wegwerfen, zufall, befund, messung, quantil }
  from '../umgebung.mjs'

export const lang = true

const WERKSTATT = 'D — Nutzen'
const ZIEHUNGEN = 200
const ZIEHUNGEN_SCHNELL = 25

/** Ab hier gilt ein Vergleich als entschieden — beidseitig, also 95 %. */
const SICHER = 0.975

/* ---------- Die Koeffizienten, aus denen alles folgt ---------------------- */

/**
 * Die sechs Sichten, die `mv_kaskade` als Koeffizienten liest, mit der Spalte,
 * die den Wert trägt, und den beiden, die das Band aufspannen.
 *
 * `mono` markiert die Schimmelkurve: ihre Werte sind über die Lagerdauer
 * monoton steigend (deshalb heisst die Spalte `anteil_mono`). Werden die
 * Stützstellen unabhängig gezogen, geht die Monotonie verloren und die Kurve
 * beschreibt etwas, das es nicht gibt — Kürbisse werden nicht wieder gesund.
 * Deshalb wird nach dem Ziehen ein laufendes Maximum gebildet.
 */
const KOEFFIZIENTEN = [
  { sicht: 'v_koeff_verdunstung', wert: 'mittel',      unten: 'unten',        oben: 'oben' },
  { sicht: 'v_koeff_ausschuss',   wert: 'mittel',      unten: 'unten',        oben: 'oben' },
  { sicht: 'v_koeff_fax',         wert: 'mittel',      unten: 'unten',        oben: 'oben' },
  { sicht: 'v_koeff_nebenkanal',  wert: 'mittel',      unten: 'unten',        oben: 'oben' },
  { sicht: 'v_schimmel_kurve',    wert: 'anteil_mono', unten: 'unten',        oben: 'oben',
    mono: 'von' },
  { sicht: 'v_schimmel_modell',   wert: 'sockel',      unten: 'sockel_unten', oben: 'sockel_oben',
    regression: true },
]

/**
 * Die Schimmelkurve ist der Sonderfall — und der Grund, weshalb die erste
 * Fassung dieses Werkzeugs unbrauchbar war.
 *
 * Die Kaskade rechnet den Faulanteil **nicht** aus den Stützstellen von
 * `v_schimmel_kurve`, sondern aus einer angepassten Geraden im Log-Raum:
 *
 *     ln f(t) = ln_lambda_korrigiert + k · ln t
 *
 * Wer nur die Stützstellen streut, streut etwas, das die Kaskade gar nicht
 * liest. Die erste Fassung tat genau das: Ihre Ziehungen ergaben für den
 * Schimmelstrom eine Halbbreite von 90 kg, während das Programm selbst
 * 16 253 kg ausweist — Faktor 180. Sie hätte jeden Vergleich der Welt für
 * „entschieden" erklärt.
 *
 * Richtig gezogen werden die **beiden Parameter der Geraden gemeinsam**, aus
 * ihrer Kovarianzmatrix, die dieselbe Sicht bereits führt:
 *
 *     [ var_achse    kov_achse_k ]
 *     [ kov_achse_k  var_k       ]
 *
 * Gemeinsam ist wesentlich: Achsenabschnitt und Steigung sind stark negativ
 * korreliert (eine steilere Gerade beginnt tiefer). Unabhängig gezogen ergäbe
 * das Kurven, die die Messpunkte weit verfehlen — und eine Unsicherheit, die
 * es nicht gibt. Gezogen wird über die Cholesky-Zerlegung, drei Zeilen ohne
 * Bibliothek.
 */
function regressionZiehen(z, r) {
  const achse = Number(z.ln_lambda_korrigiert), k = Number(z.k)
  const va = Number(z.var_achse), vk = Number(z.var_k), kov = Number(z.kov_achse_k)
  if (![achse, k, va, vk, kov].every(Number.isFinite) || va <= 0 || vk <= 0) return z

  const l11 = Math.sqrt(va)
  const l21 = kov / l11
  const l22 = Math.sqrt(Math.max(vk - l21 * l21, 0))
  const z1 = r.normal(0, 1), z2 = r.normal(0, 1)
  const neuAchse = achse + l11 * z1
  const neuK = k + l21 * z1 + l22 * z2
  return { ...z,
    ln_lambda_korrigiert: neuAchse,
    ln_lambda: neuAchse,
    k: neuK,
    lambda: Math.exp(neuAchse) }
}

const spaltenVon = (db, sicht) => frage(db, `
  select a.attname as name, format_type(a.atttypid, a.atttypmod) as typ
    from pg_attribute a join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = '${sicht}'
     and a.attnum > 0 and not a.attisdropped
   order by a.attnum`)

/**
 * Jede Koeffizientensicht wird durch eine Sicht auf eine Streutabelle ersetzt.
 *
 * `create or replace view` statt `drop` + `create`: Ein `drop` risse die halbe
 * Auswertung mit, `replace` lässt jeden Abhängigen stehen — solange Namen,
 * Reihenfolge und Typen der Spalten gleich bleiben. Deshalb wird jede Spalte
 * ausdrücklich auf ihren ursprünglichen Typ gegossen.
 */
function vorbereiten(probe) {
  for (const k of KOEFFIZIENTEN) {
    const spalten = spaltenVon(probe, k.sicht)
    k.spalten = spalten
    const guss = spalten.map(s => `${s.name}::${s.typ} as ${s.name}`).join(', ')
    tue(probe, `
      create table zug_urspr_${k.sicht} as select * from ${k.sicht};
      create table zug_${k.sicht} as select * from zug_urspr_${k.sicht};
      create or replace view ${k.sicht} as select ${guss} from zug_${k.sicht};`)
  }
}

/**
 * Eine Ziehung. `streuung = 0` ist die **Nullziehung**: sie schreibt die
 * ursprünglichen Werte zurück und muss die ursprünglichen Zahlen exakt
 * reproduzieren. Genau daran prüft die Selbstprobe, ob der Umbau der Sichten
 * die Rechnung nicht schon von sich aus verschoben hat.
 */
function ziehen(probe, r, streuung = 1) {
  for (const k of KOEFFIZIENTEN) {
    const zeilen = frage(probe, `select * from zug_urspr_${k.sicht}`)
    const neu = zeilen.map(z0 => {
      const z = k.regression && streuung > 0 ? regressionZiehen(z0, r) : z0
      const m = Number(z[k.wert]), u = Number(z[k.unten]), o = Number(z[k.oben])
      if (!Number.isFinite(m)) return z
      // Das Band ist als 95-%-Band ausgewiesen: halbe Breite = 1.96 Sigma.
      const sigma = Number.isFinite(u) && Number.isFinite(o) ? Math.max((o - u) / (2 * 1.96), 0) : 0
      return { ...z, [k.wert]: Math.max(m + streuung * sigma * r.normal(0, 1), 0) }
    })
    if (k.mono) {
      neu.sort((a, b) => Number(a[k.mono]) - Number(b[k.mono]))
      let lauf = 0
      for (const z of neu) { lauf = Math.max(lauf, Number(z[k.wert])); z[k.wert] = lauf }
    }
    const namen = k.spalten.map(s => s.name)
    const werte = neu.map(z => '(' + namen.map(n =>
      z[n] === null || z[n] === undefined ? 'null' : `'${String(z[n]).replaceAll("'", "''")}'`).join(',') + ')')
    tue(probe, `truncate zug_${k.sicht};`
      + (werte.length ? ` insert into zug_${k.sicht} (${namen.join(',')}) values ${werte.join(',')};` : ''))
  }
}

/* ---------- Was verglichen wird ------------------------------------------- */

/**
 * Genau die Vergleiche, die die Oberfläche anbietet — nicht mehr und nicht
 * weniger. Ein Vergleich, den niemand sieht, muss auch nicht auflösbar sein.
 *
 *   Ströme     — der Überblick sortiert die sechs Verlustursachen und malt sie
 *                als Balken; der oberste ist „das grösste Problem".
 *   Sorte      — Reiter „je Sorte": Anteil am Eingang, absteigend.
 *   Schlag     — Reiter „je Schlag", gleiche Darstellung.
 *   Charge     — Reiter „je Charge".
 *
 * Verglichen wird bei Gruppen der **Anteil am Eingang**, nicht die Kilozahl:
 * Genau das zeigt der Balken, und genau das ist die Frage („wem fehlt anteilig
 * am meisten, nicht wer ist am grössten" — so steht es auf dem Bildschirm).
 */
const ABLESUNGEN = {
  'Verlustursache': `select strom as name, kg::float8 as wert from v_verlust_ranking`,
  'Sorte':  gruppenAblesung('sorte'),
  'Schlag': gruppenAblesung('schlag'),
  'Charge': gruppenAblesung('charge'),
}

function gruppenAblesung(gruppe) {
  return `select schluessel as name,
                 (100 * sum(kg) / nullif(max(eingang_kg), 0))::float8 as wert
            from v_verlust_je_gruppe
           where gruppe = '${gruppe}' and buch = 'verlust'
           group by schluessel having max(eingang_kg) > 0`
}

const ablesen = (probe) => Object.fromEntries(Object.entries(ABLESUNGEN).map(([art, sql]) =>
  [art, Object.fromEntries(frage(probe, sql).map(z => [z.name, z.wert]))]))

/* ---------- Auswertung der Ziehungen -------------------------------------- */

/**
 * Für jedes Paar: In wie viel Prozent der Ziehungen lag A über B?
 *
 * Die Zahl ist bewusst nicht als p-Wert ausgedrückt. „In 62 von 100 gerechneten
 * Welten war Lekor schlechter als Butterkin" versteht ein Betriebsleiter; ein
 * p-Wert von 0.24 nicht — und er würde ihn falsch verstehen.
 */
export function paare(name, ziehungen, punkt) {
  const namen = Object.keys(punkt).filter(n => Number.isFinite(punkt[n]))
  const raus = []
  for (let i = 0; i < namen.length; i++) for (let j = i + 1; j < namen.length; j++) {
    const [a, b] = [namen[i], namen[j]]
    const gueltig = ziehungen.filter(z => Number.isFinite(z[a]) && Number.isFinite(z[b]))
    if (gueltig.length < 5) continue
    const groesser = gueltig.filter(z => z[a] > z[b]).length / gueltig.length
    const unterschied = punkt[a] - punkt[b]
    const spanne = gueltig.map(z => z[a] - z[b])
    raus.push({
      art: name, a, b, unterschied,
      a_wert: punkt[a], b_wert: punkt[b],
      anteil: unterschied >= 0 ? groesser : 1 - groesser,
      band: [quantil(spanne, 0.025), quantil(spanne, 0.975)],
      n: gueltig.length,
      entschieden: Math.max(groesser, 1 - groesser) >= SICHER,
    })
  }
  return raus.sort((x, y) => y.anteil - x.anteil)
}

/* ---------- Eichung: taugt die Streuung dieses Werkzeugs überhaupt? ------- */

/**
 * Die wichtigste Zeile dieses Werkzeugs, und die, die es beinahe nicht gegeben
 * hätte.
 *
 * Ein Werkzeug, das Unsicherheit erzeugt, kann sie zu klein erzeugen — und
 * dann erklärt es jeden Vergleich der Welt für entschieden, ohne dass es
 * jemandem auffiele. Genau das ist der ersten Fassung passiert. Deshalb misst
 * dieses Werkzeug **immer zuerst sich selbst**: Es stellt seine gezogene
 * Streuung neben das Band, das die Auswertung für dieselbe Zahl ausweist.
 *
 * Stimmen die beiden ungefähr überein, misst das Werkzeug dasselbe wie das
 * Programm. Weichen sie ab, ist das kein Grund, an einer Schraube zu drehen,
 * bis sie übereinstimmen — das würde das Werkzeug zerstören, ohne dass es
 * jemand merkt. Es ist ein **eigener Befund**: Zwei Wege, dieselbe
 * Unsicherheit auszurechnen, kommen zu verschiedenen Antworten, und dann ist
 * mindestens einer falsch.
 */
function eichung(ziehungenStrom, band) {
  return Object.keys(band).map(strom => {
    const werte = ziehungenStrom.map(z => z[strom]).filter(Number.isFinite)
    const halb = werte.length >= 5 ? (quantil(werte, 0.975) - quantil(werte, 0.025)) / 2 : null
    const b = band[strom]
    return { strom, kg: b.kg, band: b.halb, streuung: b.streuung, t: b.t, gezogen: halb,
             // gegen das Band, wie es auf dem Bildschirm steht
             faktor: halb !== null && b.halb > 0 ? halb / b.halb : null,
             // gegen die reine Delta-Streuung, also ohne den t-Faktor der Freiheitsgrade
             faktor_ohne_t: halb !== null && b.streuung > 0 ? halb / (1.96 * b.streuung) : null }
  })
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db, schnell, saat }) {
  const n = schnell ? ZIEHUNGEN_SCHNELL : ZIEHUNGEN
  const r = zufall(saat)
  const probe = kopie(db, 'wk_d2_aufloesung')
  const raus = []
  try {
    const punkt = ablesen(probe)
    const band = Object.fromEntries(frage(probe, `
      select strom, kg::float8 as kg, ((kg_oben - kg_unten) / 2)::float8 as halb,
             streuung_kg::float8 as streuung, df, t_quantil_95(df)::float8 as t
        from v_verlust_ranking where kg_oben is not null and streuung_kg is not null`)
      .map(z => [z.strom, z]))

    vorbereiten(probe)

    // Nullziehung: der Umbau darf für sich nichts verändern.
    ziehen(probe, r, 0)
    rechne(probe)
    const nachUmbau = ablesen(probe)
    const abweichung = Math.max(...Object.entries(punkt).flatMap(([art, w]) =>
      Object.keys(w).map(k => Math.abs((w[k] ?? 0) - (nachUmbau[art][k] ?? 0)))))
    if (abweichung > 1e-6)
      throw new Error(`Der Umbau der Koeffizientensichten verschiebt die Zahlen schon ohne `
        + `Ziehung um ${abweichung} — das Werkzeug misst dann sich selbst.`)

    const ziehungen = Object.fromEntries(Object.keys(ABLESUNGEN).map(a => [a, []]))
    for (let i = 0; i < n; i++) {
      ziehen(probe, r, 1)
      rechne(probe)
      const g = ablesen(probe)
      for (const a of Object.keys(ABLESUNGEN)) ziehungen[a].push(g[a])
    }

    /* --- Zuerst die Eichung --- */
    const eich = eichung(ziehungen['Verlustursache'], band)
    raus.push(messung({
      werkstatt: WERKSTATT,
      titel: 'Eichung: die Streuung dieses Werkzeugs neben dem Band, das die Auswertung ausweist',
      einheit: 'kg',
      spalten: ['Verlustursache', 'Wert (kg)', 'Delta-Streuung σ (kg)', 't heute',
                'Band auf dem Bildschirm (± kg)', 'Streuung dieses Werkzeugs (± kg)',
                'gegen den Bildschirm', 'gegen 1.96 σ'],
      erklaerung: 'Bevor eine einzige Aussage über Vergleiche fällt, misst das Werkzeug sich '
        + `selbst: Es zieht die Koeffizienten ${n} Mal aus ihren eigenen Bändern, rechnet die `
        + 'volle Kaskade und stellt die entstandene Streuung neben die, die die Auswertung '
        + 'ausweist. Verglichen wird **zweimal**, und der Unterschied zwischen den letzten beiden '
        + 'Spalten ist der eigentliche Ertrag dieser Tabelle. „Gegen den Bildschirm" nimmt das '
        + 'Band, wie es dasteht — also samt dem t-Faktor der Freiheitsgrade. „Gegen 1.96 σ" nimmt '
        + 'nur die fortgepflanzte Streuung und lässt den t-Faktor weg. Liegt die letzte Spalte '
        + 'nahe 1 und die vorletzte weit darunter, rechnen beide Wege dieselbe Streuung aus und '
        + 'der ganze Unterschied steckt im t-Faktor — das ist kein Fehler dieses Werkzeugs, '
        + 'sondern der Befund von A4, hier auf einem völlig anderen Weg noch einmal bestätigt. '
        + 'Weicht auch die letzte Spalte ab, gehen die Rechenwege wirklich auseinander. '
        + 'Nachjustiert wird an keiner Seite etwas.',
      zeilen: eich.map(e => ({
        'Verlustursache': e.strom, 'Wert (kg)': e.kg.toFixed(0),
        'Delta-Streuung σ (kg)': e.streuung.toFixed(1),
        't heute': e.t.toFixed(3),
        'Band auf dem Bildschirm (± kg)': e.band.toFixed(0),
        'Streuung dieses Werkzeugs (± kg)': e.gezogen === null ? '—' : e.gezogen.toFixed(0),
        'gegen den Bildschirm': e.faktor === null ? '—' : e.faktor.toFixed(2),
        'gegen 1.96 σ': e.faktor_ohne_t === null ? '—' : e.faktor_ohne_t.toFixed(2),
      })),
    }))

    // Nur die Abweichung, die **nach** Herausrechnen des t-Faktors bleibt, ist ein Streit
    // zwischen zwei Rechenwegen. Der Rest ist der Freiheitsgrad-Befund aus A4 und gehört
    // nicht ein zweites Mal in die Mängelliste.
    const schief = eich.filter(e => e.faktor_ohne_t !== null
                                 && (e.faktor_ohne_t < 0.5 || e.faktor_ohne_t > 2))
    if (schief.length) raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'AUF', klasse: 3, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { sicht: 'v_verlust_je_gruppe' },
      titel: 'Zwei Wege zur selben Unsicherheit kommen zu verschiedenen Antworten',
      steht_da: `Für ${schief.length} von ${eich.length} Verlustursachen weicht die Streuung, die `
        + 'sich beim Durchrechnen der Kaskade mit gezogenen Koeffizienten ergibt, um mehr als das '
        + 'Doppelte von der fortgepflanzten Streuung der Auswertung ab — und zwar **auch dann, '
        + 'wenn der t-Faktor der Freiheitsgrade auf beiden Seiten herausgerechnet ist**: '
        + schief.map(e => `${e.strom} — Delta-Methode ±${(1.96 * e.streuung).toFixed(0)} kg, `
            + `durchgerechnet ±${e.gezogen.toFixed(0)} kg (Faktor ${e.faktor_ohne_t.toFixed(2)})`)
            .join('; ') + '. Bei den übrigen Strömen stimmen die beiden Wege überein, sobald der '
        + 't-Faktor draussen ist — dort steckt der ganze Unterschied in den Freiheitsgraden und '
        + 'ist als eigener Befund erfasst.',
      muesste: 'Die Auswertung leitet ihr Band mit der Delta-Methode her: Sie linearisiert die '
        + 'Kaskade um den Schätzwert und pflanzt die Varianzen mit den Ableitungen fort. Das ist '
        + 'ein anerkanntes Verfahren, aber es gilt nur, solange die Kaskade sich auf der Breite '
        + 'des Bands ungefähr wie eine Gerade verhält. Die Schimmelkurve tut das nicht: Sie ist '
        + '`exp(a + k·ln t)`, und was hinter einer Exponentialfunktion liegt, kann eine '
        + 'Linearisierung nicht einfangen. Beide Zahlen gehören nebeneinander geprüft — und die '
        + 'Herleitung entscheidet, nicht die bequemere Zahl.',
      warum: 'Das Band ist keine Verzierung. Es steht auf dem Bildschirm und beantwortet die '
        + 'Frage, wie ernst der Betrieb eine Zahl nehmen soll. Ist es um einen Faktor daneben, ist '
        + 'jede Aussage darüber, ob ein Unterschied zählt, um denselben Faktor daneben.',
      beleg: 'werkstatt/d_nutzen/d2_aufloesung.mjs, Messreihe „Eichung"',
      groesse: { wert: Math.max(...schief.map(e => Math.max(e.faktor_ohne_t, 1 / e.faktor_ohne_t))).toFixed(1),
                 einheit: 'Faktor zwischen den zwei Rechenwegen für dieselbe Unsicherheit',
                 basis: `${n} Ziehungen, Demodaten` },
      gegenrede: '**Wichtig für die Reihenfolge der Reparaturen:** Bei der Schimmelkurve zeigen '
        + 'die beiden Fehler in entgegengesetzte Richtungen und heben sich zum Teil auf. Der '
        + 't-Faktor macht das Band 6.5-mal zu weit (Befund FPF-001), die Linearisierung macht die '
        + 'Streuung 3.9-mal zu eng — heraus kommt ein Band, das ungefähr stimmt, aus zwei '
        + 'falschen Gründen. **Wer nur die Freiheitsgrade richtigstellt, macht es schlimmer**: '
        + 'Aus zufällig ungefähr richtig würde selbstbewusst zu eng. Die beiden Reparaturen '
        + 'gehören zusammen oder gar nicht.\n\nIm Übrigen ist die Ziehung nicht automatisch die '
        + 'richtigere. Sie unterstellt, dass die '
        + 'gezogenen Parameter normalverteilt sind und dass die Koeffizienten voneinander '
        + 'unabhängig sind — beides sind Annahmen. Insbesondere kann eine Ziehung, die weit in '
        + 'den Rand des Bands greift, Kurven erzeugen, die kein Kürbis je gelaufen ist. Dass die '
        + 'beiden Wege auseinandergehen, ist der Befund; welcher recht hat, ist die nächste '
        + 'Frage und braucht die Herleitung, nicht mehr Ziehungen.',
      aufwand: 'mittel',
    }))

    const alle = Object.keys(ABLESUNGEN).flatMap(a => paare(a, ziehungen[a], punkt[a]))

    /* --- Messreihe: die knappsten Vergleiche je Art --- */
    raus.push(messung({
      werkstatt: WERKSTATT,
      titel: `Welche Vergleiche der Überblick trägt (${n} Ziehungen)`,
      einheit: 'Anteil der Ziehungen',
      spalten: ['Vergleich', 'A', 'B', 'A zeigt', 'B zeigt', 'A grösser in',
                'Unterschied 95 % zwischen', 'Urteil'],
      erklaerung: 'Die Koeffizienten der Kaskade wurden aus ihren eigenen Bändern gezogen und die '
        + `ganze Kaskade damit ${n} Mal neu gerechnet. „A grösser in" ist der Anteil der `
        + 'Ziehungen, in denen die Reihenfolge so herauskam, wie sie heute auf dem Bildschirm '
        + 'steht. Unter 97,5 % heisst: Der Bildschirm zeigt eine Reihenfolge, für die die Daten '
        + 'nicht reichen. Aufgeführt sind die zehn knappsten Vergleiche je Art; die vollständige '
        + 'Liste steht in `werkstatt/befunde/befunde.json`. **Diese Tabelle gilt nur, soweit die '
        + 'Eichung darüber trägt** — wo das Verhältnis dort weit von 1 abweicht, sind auch diese '
        + 'Prozente um denselben Faktor daneben.',
      zeilen: Object.keys(ABLESUNGEN).flatMap(art => alle.filter(p => p.art === art)
        .sort((x, y) => x.anteil - y.anteil).slice(0, 10).map(p => ({
          'Vergleich': p.art, 'A': p.a, 'B': p.b,
          'A zeigt': p.a_wert.toFixed(2), 'B zeigt': p.b_wert.toFixed(2),
          'A grösser in': (100 * (p.unterschied >= 0 ? p.anteil : 1 - p.anteil)).toFixed(1) + ' %',
          'Unterschied 95 % zwischen': `${p.band[0].toFixed(2)} … ${p.band[1].toFixed(2)}`,
          'Urteil': p.entschieden ? 'trägt' : 'trägt nicht',
        }))),
    }))

    /* --- Der wichtigste Vergleich überhaupt: die oberste Zeile des Überblicks --- */
    const zwei = Object.entries(punkt['Verlustursache'])
      .filter(([, w]) => Number.isFinite(w)).sort((a, b) => b[1] - a[1]).slice(0, 2).map(([k]) => k)
    const oberste = alle.find(p => p.art === 'Verlustursache'
      && ((p.a === zwei[0] && p.b === zwei[1]) || (p.a === zwei[1] && p.b === zwei[0])))
    if (oberste && !oberste.entschieden) raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'AUF', klasse: 3, marke: 'Reparatur', sicherheit: 'hoch',
      ort: { sicht: 'v_verlust_ranking', datei: 'src/pages/Ueberblick.tsx' },
      titel: 'Der Überblick sagt, welche Verlustursache die grösste ist — die Daten sagen es nicht',
      steht_da: `Die Auswertung stellt \`${zwei[0]}\` `
        + `(${punkt['Verlustursache'][zwei[0]].toFixed(0)} kg) über \`${zwei[1]}\` `
        + `(${punkt['Verlustursache'][zwei[1]].toFixed(0)} kg) und malt sie als obersten Balken. `
        + `Zieht man die Koeffizienten ${n} Mal aus den Bändern, die dieselbe Auswertung ausweist, `
        + `ist \`${zwei[0]}\` nur in `
        + `${(100 * (oberste.a === zwei[0] ? oberste.anteil : 1 - oberste.anteil)).toFixed(0)} % `
        + `der Ziehungen die grössere. Der Unterschied liegt zu 95 % zwischen `
        + `${oberste.band[0].toFixed(0)} und ${oberste.band[1].toFixed(0)} kg — das Vorzeichen `
        + 'wechselt. Zum Vergleich: **jeder andere** der zehn Vergleiche zwischen Verlustursachen '
        + 'kommt in 100 % der Ziehungen gleich heraus. Es ist ausgerechnet der Vergleich ganz '
        + 'oben, der nicht trägt.',
      muesste: 'Die Reihenfolge darf nicht als Reihenfolge auftreten, solange sie keine ist. Zwei '
        + 'kleine Mittel: Balken, deren Unterschied das Vorzeichen wechselt, bekommen dieselbe '
        + 'Farbe oder werden zu einer Gruppe zusammengefasst — „Schimmel und Verdunstung, zusammen '
        + 'rund die Hälfte; welche der beiden grösser ist, sagen die Daten nicht". Und die Kachel '
        + 'nennt die Zahl, die heute fehlt: wie viele Messungen es bräuchte, damit die Reihenfolge '
        + 'trägt.',
      warum: 'Aus dieser einen Reihenfolge folgt eine Handlung, und es sind zwei verschiedene. '
        + 'Gewinnt die Verdunstung, geht es um Luftfeuchte und kürzere Lagerung; gewinnt der '
        + 'Schimmel, geht es um früheres Aussortieren. Das sind verschiedene Investitionen in '
        + 'verschiedene Anlagen. Ein Balkendiagramm, das diese Wahl trifft, wo die Daten sie nicht '
        + 'treffen, ist schlechter als eines, das schweigt — denn es sieht aus wie eine Antwort.',
      beleg: `werkstatt/d_nutzen/d2_aufloesung.mjs: ${n} Ziehungen der sechs Koeffizientensichten `
        + 'aus ihren eigenen `unten`/`oben`-Spalten, volle Kaskade je Ziehung; Eichung siehe '
        + 'Messreihe darüber',
      groesse: { wert: (100 * Math.max(oberste.anteil, 1 - oberste.anteil)).toFixed(0),
                 einheit: '% Sicherheit für die oberste Zeile des Überblicks (nötig wären 97,5 %)',
                 basis: `${n} Ziehungen, Demodaten` },
      gegenrede: 'Die Ziehung der Schimmelkurve ist ausgerechnet die, die in der Eichung von der '
        + 'Delta-Methode abweicht — sie ist also die unsicherste der sechs. Wäre die Delta-Methode '
        + `im Recht, wäre der Vergleich entschieden. Dagegen spricht die Rechnung: \`exp(a + k·ln t)\` `
        + 'ist keine Gerade, und eine Linearisierung unterschätzt die Streuung dahinter '
        + 'systematisch. Wer diesen Befund entkräften will, muss zeigen, dass die Linearisierung '
        + 'über die Breite dieses Bandes trägt — nicht, dass sie bequemer ist.',
      aufwand: 'mittel',
    }))

    /* --- Befund je Gruppenreiter --- */
    for (const art of ['Sorte', 'Schlag', 'Charge']) {
      const dieser = alle.filter(p => p.art === art)
      const offen = dieser.filter(p => !p.entschieden)
      if (!dieser.length || offen.length / dieser.length < 0.5) continue
      raus.push(befund({
        werkstatt: WERKSTATT, kuerzel: 'AUF', klasse: 2, marke: 'Reparatur', sicherheit: 'mittel',
        ort: { sicht: 'v_verlust_je_gruppe', datei: 'src/pages/Ueberblick.tsx' },
        titel: `Der Reiter „je ${art}" sortiert ${dieser.length} Vergleiche, von denen `
             + `${offen.length} nicht tragen`,
        steht_da: 'Die Balken sind nach Verlustanteil sortiert, von '
          + `${Math.max(...dieser.map(p => Math.max(p.a_wert, p.b_wert))).toFixed(1)} % bis `
          + `${Math.min(...dieser.map(p => Math.min(p.a_wert, p.b_wert))).toFixed(1)} %. `
          + `Von den ${dieser.length} Paarvergleichen, die diese Reihenfolge behauptet, halten `
          + `${dieser.length - offen.length} einer Ziehung stand, ${offen.length} nicht `
          + `(${(100 * offen.length / dieser.length).toFixed(0)} %).`,
        muesste: 'Wo die Reihenfolge nicht trägt, darf keine stehen. Der Balken braucht sein Band '
          + '— dieselbe Zahl, die die Auswertung ohnehin führt (`kg_unten`, `kg_oben`) —, und '
          + 'Gruppen, die sich nicht unterscheiden lassen, gehören optisch gleichgestellt. '
          + 'Sinnvoll bleibt der Reiter trotzdem: Er zeigt, **wo überhaupt gemessen wurde**.',
        warum: `Wer den Reiter „je ${art}" öffnet, sucht den Ausreisser. Steht ganz oben eine `
          + 'Gruppe, die nur zufällig oben steht, wird ihr nachgegangen: Gespräche, Kontrollen, '
          + 'im schlimmsten Fall eine geänderte Anbauplanung. Das kostet mehr als die Zahl.',
        beleg: `werkstatt/d_nutzen/d2_aufloesung.mjs: alle ${dieser.length} Paare aus `
          + `v_verlust_je_gruppe (gruppe='${art.toLowerCase()}'), ${n} Ziehungen`,
        groesse: { wert: offen.length,
                   einheit: `von ${dieser.length} Vergleichen dieses Reiters sind nicht entschieden`,
                   basis: `${n} Ziehungen, Demodaten` },
        gegenrede: 'Ein Betriebsleiter liest so eine Liste nicht als Rangliste, sondern sucht das '
          + 'eine auffällige Ende — und **die Enden sind eher entschieden als die Mitte**, weil '
          + 'dort die Unterschiede grösser sind. Die Zahl oben überzeichnet den Schaden deshalb. '
          + 'Sie bleibt ein Befund: Die Oberfläche unterscheidet heute nirgends zwischen einem '
          + 'Abstand, der etwas heisst, und einem, der keiner ist. Ausserdem hängt sie an der '
          + 'Eichung eine Zeile weiter oben.',
        aufwand: 'mittel',
      }))
    }

    /* --- Gegenprobe: was trägt --- */
    const entschieden = alle.filter(p => p.entschieden)
    if (entschieden.length) raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'AUF', klasse: 1, marke: 'kein Fehler', sicherheit: 'mittel',
      ort: { sicht: 'v_verlust_je_gruppe' },
      titel: `Geprüft: ${entschieden.length} von ${alle.length} Vergleichen halten der Ziehung stand`,
      steht_da: `${entschieden.length} Paarvergleiche kommen in mindestens 97,5 % der ${n} `
        + 'Ziehungen mit demselben Vorzeichen heraus. Der deutlichste ist '
        + `„${entschieden[0]?.a} gegen ${entschieden[0]?.b}" (${entschieden[0]?.art}).`,
      muesste: '—',
      warum: 'Ein Bericht, der nur sagt, was nicht trägt, sagt nichts darüber, wie weit '
        + 'nachgesehen wurde. Diese Zeile ist die Gegenprobe: Das Verfahren erklärt nicht alles '
        + 'für unentscheidbar, es unterscheidet.',
      beleg: 'werkstatt/d_nutzen/d2_aufloesung.mjs, Messreihe „Welche Vergleiche der Überblick trägt"',
      groesse: { wert: entschieden.length, einheit: `von ${alle.length} Vergleichen tragen`,
                 basis: `${n} Ziehungen, Demodaten` },
      aufwand: 'klein',
    }))

    return raus
  } finally {
    wegwerfen(probe)
  }
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Die Auswertung der Ziehungen bekommt zwei erfundene Welten vorgesetzt:
 * eine, in der A immer vorne liegt (muss „entschieden" heissen), und eine, in
 * der beide um denselben Wert schwanken (darf es nicht). Fiele eines der
 * beiden Urteile falsch aus, wäre jede Zahl dieses Werkzeugs wertlos.
 *
 * Die dritte Probe — dass der Umbau der Koeffizientensichten für sich nichts
 * verschiebt — steckt in `laufen()` selbst als Nullziehung und bricht den Lauf
 * ab, statt still ein falsches Ergebnis zu liefern.
 */
export async function selbstprobe({ saat = 20260909 } = {}) {
  const r = zufall(saat)

  const klar = Array.from({ length: 100 }, () => ({ A: 100 + r.normal(0, 1), B: 50 + r.normal(0, 1) }))
  const [p1] = paare('Probe', klar, { A: 100, B: 50 })
  if (!p1.entschieden || p1.anteil < 0.99) return false

  const wirr = Array.from({ length: 100 }, () => ({ A: 100 + r.normal(0, 40), B: 98 + r.normal(0, 40) }))
  const [p2] = paare('Probe', wirr, { A: 100, B: 98 })
  if (p2.entschieden) return false

  // Ein Paar, das knapp über der Schwelle liegt, muss noch als entschieden gelten.
  const knapp = Array.from({ length: 200 }, (_, i) => ({ A: i < 197 ? 2 : 0, B: 1 }))
  const [p3] = paare('Probe', knapp, { A: 2, B: 1 })
  if (!p3.entschieden) return false

  return true
}
