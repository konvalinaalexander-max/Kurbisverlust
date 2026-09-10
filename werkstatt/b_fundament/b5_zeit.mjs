/**
 * B5 — Die Zeit.
 *
 * DIE FRAGE
 *
 * Das Programm rechnet mit **Lagertagen**. Lagertage entstehen als Differenz
 * zweier Dinge, die verschiedener Natur sind:
 *
 *   `eingangsdatum`  — ein **Kalendertag**, vom Palettenzettel abgetippt.
 *                      Er meint den Tag, an dem der Arbeiter in der Halle
 *                      stand. Ortszeit, ohne dass es irgendwo dastünde.
 *
 *   `wiege_ts`       — ein **Zeitpunkt**, von der Datenbank gesetzt (`now()`).
 *                      Ein absoluter Augenblick, ohne Ort.
 *
 * Aus dem Zeitpunkt wird mit `::date` wieder ein Kalendertag — **in der
 * Zeitzone der Sitzung**. Die Datenbank läuft auf `Etc/UTC`, der Betrieb liegt
 * in der Schweiz (UTC+1, im Sommer UTC+2). Damit gehört jeder Zeitpunkt
 * zwischen 22:00 UTC und Mitternacht UTC — also 00:00 bis 02:00 Ortszeit —
 * in UTC noch zum Vortag und in Zürich schon zum neuen Tag.
 *
 * Bewiesen, nicht behauptet:
 *
 *     set time zone 'UTC';            select '2026-07-15 22:30+00'::timestamptz::date
 *     → 2026-07-15
 *     set time zone 'Europe/Zurich';  select '2026-07-15 22:30+00'::timestamptz::date
 *     → 2026-07-16
 *
 * Dasselbe Datum, dieselbe Zeile, zwei Antworten. Welche das Programm gibt,
 * hängt an einer Einstellung, die **niemand ausgewählt hat** und die der
 * Betreiber der Datenbank jederzeit ändern kann.
 *
 * DIE ZWEITE HÄLFTE: DIE OBERFLÄCHE
 *
 * Umgekehrt bildet die Oberfläche „heute" mit
 * `new Date().toISOString().slice(0, 10)`. Das ist der Tag **in UTC**, nicht
 * der Tag des Arbeiters. Zwischen 00:00 und 02:00 Ortszeit bietet die Maske
 * also **gestern** als Vorgabe an — und der Arbeiter übernimmt sie.
 *
 * An einer Stelle (`src/pages/Start.tsx`) macht die App es richtig: Sie nimmt
 * die lokale Mitternacht und wandelt sie um. Beide Schreibweisen können nicht
 * gleichzeitig richtig sein.
 *
 * WAS DIESES WERKZEUG TUT
 *
 * 1. Es sucht **jede** Stelle, an der ein Zeitpunkt zu einem Kalendertag wird
 *    oder ein Kalendertag aus „jetzt" entsteht — im SQL und in der Oberfläche.
 * 2. Es misst, **wie gross** ein Tag Unterschied ist: auf der Verdunstungsrate
 *    jeder einzelnen Wägung der Demosaison und auf der Saisonsumme.
 * 3. Es zeigt den Unterschied **ausführbar**, indem es dieselbe Auswertung in
 *    zwei Zeitzonen rechnet und die Zahlen nebeneinanderstellt.
 */
import { frage, wert, tue, kopie, lies, dateien, zeileVon, befund, messung, mittel, quantil } from '../umgebung.mjs'

/* ---------- 1. Wo Zeitpunkt und Kalendertag sich mischen ------------------ */

/**
 * Ein Zeitpunkt, der zu einem Kalendertag wird — in der Zeitzone der Sitzung.
 *
 * Der Tabellenpräfix ist **wahlfrei**: `pg_get_viewdef` lässt ihn weg, sobald
 * der Spaltenname eindeutig ist. Ein Muster, das ihn verlangt, findet
 * ausgerechnet die einfachen Fälle nicht — die Selbstprobe unten hat genau
 * das an der ersten Fassung dieses Werkzeugs vorgeführt.
 */
const SQL_GUSS = /(?:\w+\.)?(\w*(?:_ts|_zeit))\s*::\s*date/gi

/** „Jetzt" als Kalendertag, ohne dass eine Zeitzone genannt wird. */
const SQL_JETZT = /\b(current_date|now\s*\(\s*\)\s*::\s*date|localtimestamp)\b/gi

/** In der Oberfläche: der Tag in UTC, ausgegeben als wäre er der Tag des Nutzers. */
const TS_UTC_TAG = /new Date\([^)]*\)\s*\.toISOString\(\)\s*\.slice\(\s*0\s*,\s*10\s*\)/g

function sqlStellen(db) {
  const objekte = frage(db, `
    select c.relname as name, c.relkind as art, pg_get_viewdef(c.oid, true) as text
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('v','m')
    union all
    select p.proname, 'f', pg_get_functiondef(p.oid)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'`)

  const raus = []
  for (const o of objekte) {
    for (const m of o.text.matchAll(SQL_GUSS))
      raus.push({ objekt: o.name, art: o.art, stelle: m[0], sorte: 'Zeitpunkt → Kalendertag' })
    for (const m of o.text.matchAll(SQL_JETZT))
      raus.push({ objekt: o.name, art: o.art, stelle: m[0], sorte: '„jetzt" als Kalendertag' })
  }
  return raus
}

/**
 * Kommentare zählen nicht. Seit die Reparatur in `lib/format.ts` steht, erklärt
 * sie den Fehler dort in Worten — samt dem Ausdruck, um den es geht. Ein
 * Werkzeug, das die Erklärung des Fehlers für den Fehler hält, meldet ihn nie
 * als behoben. Genau das ist beim ersten Lauf nach der Reparatur passiert: fünf
 * gefundene Stellen wurden zu einer, und diese eine war der Kommentar.
 *
 * Die Zeilennummern bleiben die der Originaldatei: Ersetzt wird jedes Zeichen
 * eines Kommentars durch ein Leerzeichen, Zeilenumbrüche bleiben stehen.
 */
const ohneKommentare = (t) => t
  .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
  .replace(/(^|[^:])\/\/[^\n]*/g, (m, vor) => vor + ' '.repeat(m.length - vor.length))

function oberflaechenStellen() {
  const raus = []
  for (const pfad of dateien('src')) {
    const text = ohneKommentare(lies(pfad))
    for (const m of text.matchAll(TS_UTC_TAG))
      raus.push({ pfad, zeile: zeileVon(text, m.index), stelle: m[0].replace(/\s+/g, ' ') })
  }
  return raus
}

/* ---------- 2. Wie gross ein Tag ist -------------------------------------- */

/**
 * Die Verdunstungsrate ist `1 − (netto_jetzt / netto_damals)^(1/t)`. Ein Tag
 * mehr oder weniger in `t` verschiebt sie um rund `1/t` ihres Werts — bei
 * einer Lagerdauer von acht Tagen also um mehr als ein Achtel.
 *
 * Gemessen wird nicht mit dieser Näherung, sondern durch Nachrechnen jeder
 * einzelnen Wägung der Demosaison.
 */
function tagesEffekt(db) {
  return frage(db, `
    with w as (
      select id, charge_nr, lagertage,
             netto_damals_kg::float8 as damals, netto_jetzt_kg::float8 as jetzt,
             rate_pro_tag::float8 as rate
        from v_verdunstung_messung
       where verwendbar and lagertage > 0 and netto_damals_kg > 0 and netto_jetzt_kg > 0
    )
    select id, charge_nr, lagertage, rate,
           1 - power(jetzt / damals, 1.0 / greatest(lagertage - 1, 1))            as rate_ein_tag_weniger,
           1 - power(jetzt / damals, 1.0 / (lagertage + 1))                       as rate_ein_tag_mehr
      from w order by lagertage`)
}

/* ---------- 3. Derselbe Bestand, zwei Zeitzonen --------------------------- */

/**
 * Der ausführbare Beweis. Dieselbe Datenbank, dieselben Zeilen — einmal in
 * UTC gerechnet, einmal in Europe/Zurich. Was sich unterscheidet, hängt an
 * einer Einstellung und nicht an den Daten.
 */
function inZeitzone(db, zone) {
  tue(db, `alter database ${db} set timezone to '${zone}'`)
  tue(db, `select auswertung_aktualisieren()`)
  const b = frage(db, `select eingang_kg::float8 as eingang, geliefert_kg::float8 as geliefert,
                              verlust_heute_kg::float8 as verlust,
                              verdunstung_heute_kg::float8 as verdunstung,
                              im_haus_heute_kg::float8 as im_haus, heute
                         from v_saisonbilanz`)[0]
  const t = frage(db, `select count(*) n, sum(lagertage) summe_lagertage,
                              avg(rate_pro_tag)::float8 as mittlere_rate
                         from v_verdunstung_messung where verwendbar`)[0]
  return { zone, ...b, ...t }
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db = 'demo' } = {}) {
  const raus = []
  const sql = sqlStellen(db)
  const ui = oberflaechenStellen()

  /* Der ausführbare Beweis kommt zuerst: Er liefert die Zahl, mit der die
     Befunde darunter ihre Grösse angeben. Eine Grösse aus einer Näherung wäre
     schwächer als eine, die man nachrechnen kann. */
  kopie(db, 'mw_b5')
  const utc = inZeitzone('mw_b5', 'UTC')
  const zuerich = inZeitzone('mw_b5', 'Europe/Zurich')
  tue('mw_b5', `alter database mw_b5 reset timezone`)
  const unterschiede = ['eingang', 'geliefert', 'verlust', 'verdunstung', 'im_haus', 'summe_lagertage']
    .map(f => ({ Grösse: f, UTC: utc[f], 'Europe/Zurich': zuerich[f],
                 Unterschied: Number((Number(zuerich[f]) - Number(utc[f])).toFixed(2)) }))
    .filter(z => Math.abs(z.Unterschied) > 0.005)
  const verlustDelta = Math.abs(Number(zuerich.verlust) - Number(utc.verlust))
  const tageDelta = Math.abs(Number(zuerich.summe_lagertage) - Number(utc.summe_lagertage))

  /* --- Messreihe: wo sich Zeitpunkt und Kalendertag mischen --- */
  raus.push(messung({
    werkstatt: 'B', titel: 'Wo aus einem Zeitpunkt ein Kalendertag wird',
    einheit: 'Stellen',
    spalten: ['Ort', 'Art', 'Stelle', 'Sorte'],
    zeilen: [
      ...sql.map(s => ({ Ort: s.objekt, Art: { v: 'Sicht', m: 'gespeichert', f: 'Funktion' }[s.art] ?? s.art,
                         Stelle: '`' + s.stelle + '`', Sorte: s.sorte })),
      ...ui.map(u => ({ Ort: `${u.pfad}:${u.zeile}`, Art: 'Oberfläche',
                        Stelle: '`' + u.stelle + '`', Sorte: 'Tag in UTC statt Ortszeit' })),
    ],
    erklaerung: 'Jede dieser Stellen wandelt einen absoluten Augenblick in einen Kalendertag um — '
      + 'oder umgekehrt. Das Ergebnis hängt an einer Zeitzone. Genannt wird sie an keiner einzigen.',
  }))

  /* --- Messreihe: was ein Tag kostet --- */
  const effekt = tagesEffekt(db)
  if (effekt.length) {
    const relativ = effekt.map(e => Math.abs(e.rate_ein_tag_weniger - e.rate) / e.rate)
    raus.push(messung({
      werkstatt: 'B', titel: 'Was ein Tag Unterschied auf der Verdunstungsrate ausmacht',
      einheit: 'Prozent',
      spalten: ['Lagertage', 'Wägungen', 'Rate je Tag', 'ein Tag weniger', 'Unterschied %'],
      zeilen: [
        ...[[0, 15], [15, 40], [40, 90], [90, 400]].map(([von, bis]) => {
          const g = effekt.filter(e => e.lagertage >= von && e.lagertage < bis)
          if (!g.length) return null
          const u = g.map(e => 100 * Math.abs(e.rate_ein_tag_weniger - e.rate) / e.rate)
          return {
            Lagertage: `${von}–${bis === 400 ? '∞' : bis}`,
            'Wägungen': g.length,
            'Rate je Tag': mittel(g.map(e => e.rate)).toExponential(3),
            'ein Tag weniger': mittel(g.map(e => e.rate_ein_tag_weniger)).toExponential(3),
            'Unterschied %': mittel(u).toFixed(1),
          }
        }).filter(Boolean),
      ],
      erklaerung: `${effekt.length} verwendbare Wägungen der Demosaison, jede einzeln nachgerechnet. `
        + `Die Rate geht **potenziert** in jede Verdunstungszahl der Sorte ein — ein Fehler hier `
        + `vervielfacht sich über die Lagerdauer.`,
    }))

    const median = quantil(relativ, 0.5) * 100
    const schlimmster = Math.max(...relativ) * 100
    const kuerzeste = Math.min(...effekt.map(e => e.lagertage))

    raus.push(befund({
      werkstatt: 'B', kuerzel: 'ZEIT', klasse: 3,
      ort: { sicht: 'v_verdunstung_messung', spalte: 'lagertage' },
      titel: 'Lagertage entstehen aus einem UTC-Kalendertag minus einem Schweizer Kalendertag',
      steht_da: `\`lagertage = wiege_ts::date − eingangsdatum\`. Links ein Zeitpunkt, in der Zeitzone `
        + `der Sitzung zum Tag gemacht — die Datenbank läuft auf **Etc/UTC**. Rechts ein `
        + `Kalendertag, vom Palettenzettel abgetippt, also Ortszeit. Bewiesen: derselbe Augenblick `
        + `\`2026-07-15 22:30+00\` ist in UTC der **15. Juli**, in Europe/Zurich der **16. Juli**. `
        + `Jede Erfassung zwischen 00:00 und 02:00 Ortszeit bekommt damit einen Lagertag zu wenig.`,
      muesste: 'Entweder die Datenbank auf `Europe/Zurich` stellen (eine Zeile, wirkt überall), oder '
        + 'jeden Guss ausdrücklich schreiben: `(wiege_ts at time zone \'Europe/Zurich\')::date`. '
        + 'Was nicht geht, ist der heutige Zustand: Die Antwort hängt an einer Einstellung, die '
        + 'niemand ausgewählt hat und die der Betreiber der Datenbank jederzeit ändern kann.',
      warum: `Die Rate geht **potenziert** in jede Verdunstungszahl ein. Ein Tag auf der Lagerdauer `
        + `verschiebt sie im Median um ${median.toFixed(1)} %, bei der kürzesten Lagerdauer der `
        + `Demosaison (${kuerzeste} Tage) um ${schlimmster.toFixed(1)} %. Und das ist nicht `
        + `theoretisch: Stellt man dieselbe Demosaison von UTC auf Europe/Zurich um, verschieben `
        + `sich ${tageDelta} Lagertag und damit **${verlustDelta.toFixed(2)} kg** der ausgewiesenen `
        + `Verlustmasse — ohne dass sich eine einzige erfasste Zahl geändert hätte. Betroffen ist `
        + `nur, was nach Mitternacht erfasst wird; aber niemand sieht, welche Zeile das war, und `
        + `korrigierbar ist es hinterher nicht mehr.`,
      beleg: 'werkstatt/b_fundament/b5_zeit.mjs → Messreihe „Dieselbe Datenbank, zwei Zeitzonen" '
        + '(ausführbar, nachrechenbar) und „Was ein Tag Unterschied ausmacht"',
      groesse: { wert: Number(verlustDelta.toFixed(2)), einheit: 'kg Unterschied im Saisonverlust',
                 basis: `dieselbe Demosaison, nur die Zeitzone der Datenbank geändert `
                      + `(${tageDelta} Lagertag verschoben sich); je Wägung Median `
                      + `${median.toFixed(1)} %, schlimmster Fall ${schlimmster.toFixed(1)} %` },
      sicherheit: 'hoch',
      gegenrede: 'Betroffen sind nur Erfassungen zwischen Mitternacht und 01:00 (Winter) oder 02:00 '
        + '(Sommer) Ortszeit. In einem Betrieb, der um 17 Uhr Feierabend macht, kommt das nie vor — '
        + 'dann ist der Befund folgenlos. Er bleibt trotzdem einer, weil die Richtigkeit einer Zahl '
        + 'nicht davon abhängen darf, wann jemand sie eintippt; und weil während der Ernte auch '
        + 'nachts gewaschen wird.',
      marke: 'Reparatur', aufwand: 'klein',
    }))
  }

  /* --- Die Oberfläche: „heute" in UTC --- */
  if (ui.length) {
    const richtig = /new Date\(\);?\s*\w*\.setHours\(0/.test(lies('src/pages/Start.tsx'))
    raus.push(befund({
      werkstatt: 'B', kuerzel: 'ZEIT', klasse: 3,
      ort: { datei: ui[0].pfad, zeile: ui[0].zeile },
      titel: `${ui.length} Stellen der Oberfläche bilden „heute" in UTC, eine bildet es richtig`,
      steht_da: ui.map(u => `\`${u.pfad}:${u.zeile}\``).join(', ')
        + ` verwenden \`new Date().toISOString().slice(0, 10)\` — das ist der Kalendertag in **UTC**. `
        + (richtig
            ? 'In `src/pages/Start.tsx` steht dagegen `new Date(); heute.setHours(0,0,0,0)` und dann '
            + '`.toISOString()` — das ist die **lokale** Mitternacht, korrekt umgerechnet. '
            : '')
        + 'Beide Schreibweisen können nicht gleichzeitig richtig sein.',
      muesste: 'Ein Ort, an dem „heute" gebildet wird, in der Zeitzone des Betriebs — und alle '
        + 'anderen Stellen rufen ihn auf. Heute steht dieselbe Zeile sechsmal im Code, fünfmal '
        + 'falsch und einmal richtig.',
      warum: 'Diese Zeilen füllen die **Vorgabe** von Datumsfeldern: das Lieferdatum, das Datum '
        + 'einer neuen Arbeit, das Gültig-ab einer Stammdatenfassung. Ein Arbeiter, der um '
        + '00:30 Ortszeit eine Lieferung erfasst, bekommt **gestern** vorgeschlagen und übernimmt '
        + 'es — und die Ware zählt einen Tag zu früh in den Ausgang.',
      beleg: 'werkstatt/b_fundament/b5_zeit.mjs → Messreihe „Wo aus einem Zeitpunkt ein Kalendertag wird"',
      groesse: { wert: ui.length, einheit: 'Stellen mit dem UTC-Tag als Vorgabe', basis: 'src/**' },
      sicherheit: 'hoch',
      gegenrede: 'Es ist nur die Vorgabe; der Arbeiter kann das Datum ändern und tut es beim '
        + 'Wareneingang auch, weil er es vom Zettel abliest. Bei der Lieferung und beim Start einer '
        + 'Arbeit liest er nichts ab — dort bleibt die Vorgabe stehen.',
      marke: 'Reparatur', aufwand: 'klein',
    }))
  }

  raus.push(messung({
    werkstatt: 'B', titel: 'Dieselbe Datenbank, zwei Zeitzonen',
    einheit: 'kg beziehungsweise Tage',
    spalten: ['Grösse', 'UTC', 'Europe/Zurich', 'Unterschied'],
    zeilen: unterschiede.length ? unterschiede
      : [{ 'Grösse': 'alle geprüften', UTC: '—', 'Europe/Zurich': '—',
           Unterschied: 'keiner auf den Demodaten' }],
    erklaerung: 'Dieselben Zeilen, zweimal ausgewertet — geändert wurde **nur die Zeitzone der '
      + 'Datenbank**, keine einzige Zahl in den Daten. Was sich hier unterscheidet, hängt an einer '
      + 'Einstellung und nicht am Betrieb. Auf der Demosaison betrifft es eine einzige Wägung; '
      + 'ihr eine Lagertag verschiebt die ausgewiesene Verlustmasse der ganzen Saison.',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Gepflanzt wird eine Sicht, die genau den gesuchten Fehler macht: ein
 * Zeitpunkt, in der Sitzungszeitzone zum Tag gemacht. Das Werkzeug muss sie
 * finden. Und eine zweite, die es richtig macht (`at time zone`) — die darf
 * es **nicht** melden, sonst meldet es alles.
 */
export async function selbstprobe({ db = 'demo' } = {}) {
  const p = kopie(db, 'mw_b5_probe')
  tue(p, `create or replace view v_probe_falsch as
            select w.id, w.wiege_ts::date - w.eingangsdatum as tage from verdunstung_wiegung w;
          create or replace view v_probe_richtig as
            select w.id, (w.wiege_ts at time zone 'Europe/Zurich')::date - w.eingangsdatum as tage
              from verdunstung_wiegung w`)
  const gefunden = sqlStellen(p)
  const falschGefunden = gefunden.some(s => s.objekt === 'v_probe_falsch')
  const richtigGemeldet = gefunden.some(s => s.objekt === 'v_probe_richtig')
  tue(p, 'drop view if exists v_probe_falsch; drop view if exists v_probe_richtig')
  return falschGefunden && !richtigGemeldet
}
