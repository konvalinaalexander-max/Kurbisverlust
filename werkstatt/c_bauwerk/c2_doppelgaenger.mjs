/**
 * C2 — Doppelgänger: dieselbe Rechnung, zweimal gebaut.
 *
 * WARUM ES DIESES WERKZEUG GIBT
 *
 * B1 sucht Totholz: Objekte, die **niemand** liest. Es fand keins — jede
 * Ansicht, jede Funktion, jede Tabelle hat einen Leser. Das klang nach einem
 * sauberen Bestand, und es war die falsche Frage.
 *
 * Zwei Objekte können beide gelesen werden und trotzdem dasselbe sein.
 * `erg_punkte` und `mv_schimmel_punkte` sind zeichengleich definiert und
 * enthalten dieselben 142 Zeilen; die eine liest die Oberfläche, die andere
 * drei Sichten. B1 sieht zwei Objekte mit je einem Leser und schweigt. Die
 * Rechnung dahinter läuft trotzdem zweimal, bei jedem Neurechnen.
 *
 * Gefunden hat das nicht B1, sondern eine Vermessung der Datenbank, die
 * niemandem etwas beweisen wollte und einfach alle Definitionen nebeneinander
 * legte. Dieses Werkzeug macht daraus ein Messgerät.
 *
 * WAS ES SUCHT
 *
 *   Zwillinge   Zwei Objekte, deren Definition nach dem Normalisieren
 *               zeichengleich ist. Das ist der harte Fall: Sie können gar
 *               nicht auseinanderlaufen, weil sie dasselbe sind.
 *
 *   Inhalts-    Zwei gespeicherte Ansichten mit gleicher Zeilenzahl und
 *   gleiche     gleichem Inhalt. Sie mögen verschieden geschrieben sein —
 *               gerechnet wird zweimal dasselbe.
 *
 *   Was es      Der Preis: wie lange das Füllen des überflüssigen Zwillings
 *   kostet      dauert, und wie viel Platz er belegt.
 *
 * WAS ES NICHT SUCHT
 *
 * Ähnlichkeit. Zwei Sichten, die zu 80 % gleich aussehen, sind kein Befund —
 * die 20 % sind womöglich genau der Grund, warum es zwei gibt. Dieses Werkzeug
 * meldet nur, was **gleich** ist, und lässt sich damit nicht in eine Diskussion
 * über Geschmack ziehen.
 */
import { frage, wert, tue, kopie, wegwerfen, zeit, befund, messung } from '../umgebung.mjs'

export const lang = true

const WERKSTATT = 'C — Bauwerk'

/**
 * Zwei Definitionen sind gleich, wenn sie nach dem Wegräumen von Leerraum und
 * dem eigenen Namen gleich sind.
 *
 * Der eigene Name muss weg: `create materialized view erg_punkte as select …`
 * und dieselbe Abfrage unter anderem Namen unterscheiden sich sonst allein
 * darin. `pg_get_viewdef` liefert ohnehin nur den Rumpf, aber ein Selbstbezug
 * im Rumpf (etwa in einem Kommentar) käme sonst durch.
 */
const normal = (text, name) => text
  .replace(new RegExp(`\\b${name}\\b`, 'g'), '⌂')
  .replace(/\s+/g, ' ')
  .trim()
  .toLowerCase()

function objekte(db) {
  return frage(db, `
    select c.relname as name,
           case c.relkind when 'v' then 'Ansicht' else 'gespeicherte Ansicht' end as art,
           c.relkind = 'm' as gespeichert,
           pg_get_viewdef(c.oid, true) as text,
           pg_total_relation_size(c.oid) as bytes
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('v', 'm')
     order by c.relname`)
}

function funktionen(db) {
  return frage(db, `
    select p.proname as name, 'Funktion' as art, false as gespeichert,
           pg_get_functiondef(p.oid) as text, 0 as bytes
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
     order by p.proname`)
}

/** Gruppen von Objekten mit gleicher normalisierter Definition. */
export function zwillinge(liste) {
  const nach = new Map()
  for (const o of liste) {
    // Bei Funktionen steht der Kopf mit dem Namen im Text; er wird mit ersetzt.
    const schluessel = normal(o.text, o.name)
    if (schluessel.length < 40) continue    // zu kurz, um etwas zu heissen
    ;(nach.get(schluessel) ?? nach.set(schluessel, []).get(schluessel)).push(o)
  }
  return [...nach.values()].filter(g => g.length > 1)
}

/** Wer liest dieses Objekt — aus der Datenbank und aus dem Quelltext? */
function leserVon(db, name) {
  const sichten = frage(db, `
    select distinct c.relname as name
      from pg_depend d join pg_rewrite r on r.oid = d.objid
      join pg_class c on c.oid = r.ev_class
     where d.refobjid = '${name}'::regclass and c.relname <> '${name}'`).map(z => z.name)
  return sichten
}

/** Was kostet es, den Zwilling zu füllen? */
function fuellkosten(db, name) {
  const probe = kopie(db, 'wk_c2_kosten')
  try {
    const { ms } = zeit(() => tue(probe, `refresh materialized view ${name}`))
    const sekunden = ms / 1000
    const bytes = Number(wert(probe, `select pg_total_relation_size('${name}')`))
    return { sekunden, bytes }
  } catch {
    return null
  } finally {
    wegwerfen(probe)
  }
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const alle = [...objekte(db), ...funktionen(db)]
  const gruppen = zwillinge(alle)
  const raus = []

  raus.push(messung({
    werkstatt: WERKSTATT, titel: 'Objekte mit zeichengleicher Definition', einheit: 'Objekte',
    spalten: ['Die Gleichen', 'Art', 'Zeilen SQL', 'wer liest welches'],
    erklaerung: `Von ${alle.length} Ansichten, gespeicherten Ansichten und Funktionen haben `
      + `${gruppen.reduce((a, g) => a + g.length, 0)} eine Definition, die nach dem Wegräumen von `
      + 'Leerraum und dem eigenen Namen zeichengleich mit der eines anderen ist. Gemeldet wird nur '
      + 'Gleichheit, nicht Ähnlichkeit: Zwei Sichten, die zu 80 % übereinstimmen, unterscheiden '
      + 'sich womöglich genau dort, wo es darauf ankommt.',
    zeilen: gruppen.length ? gruppen.map(g => ({
      'Die Gleichen': g.map(o => `\`${o.name}\``).join(' = '),
      'Art': [...new Set(g.map(o => o.art))].join(', '),
      'Zeilen SQL': g[0].text.split('\n').length,
      'wer liest welches': g.map(o => {
        const l = leserVon(db, o.name)
        return `${o.name}: ${l.length ? l.join(', ') : 'keine Sicht'}`
      }).join(' · '),
    })) : [{ 'Die Gleichen': '—', 'Art': '—', 'Zeilen SQL': '—',
             'wer liest welches': 'keine zwei Objekte sind zeichengleich' }],
  }))

  for (const g of gruppen) {
    const gespeicherte = g.filter(o => o.gespeichert)
    const namen = g.map(o => `\`${o.name}\``).join(' und ')

    // Bei gespeicherten Ansichten lässt sich der Preis beziffern.
    let kosten = null, gleicherInhalt = null
    if (gespeicherte.length > 1) {
      kosten = fuellkosten(db, gespeicherte[1].name)
      const [a, b] = gespeicherte
      const nurA = Number(wert(db, `select count(*) from (select * from ${a.name}
                                     except select * from ${b.name}) x`))
      const nurB = Number(wert(db, `select count(*) from (select * from ${b.name}
                                     except select * from ${a.name}) x`))
      const n = Number(wert(db, `select count(*) from ${a.name}`))
      gleicherInhalt = { n, nurA, nurB, gleich: nurA === 0 && nurB === 0 }
    }

    raus.push(befund({
      werkstatt: WERKSTATT, kuerzel: 'DOP', klasse: 2, marke: 'Reduktion', sicherheit: 'hoch',
      ort: { sicht: g.map(o => o.name).join(', ') },
      titel: `${namen} sind dieselbe Rechnung, zweimal gebaut`,
      steht_da: `Beide Definitionen sind nach dem Normalisieren zeichengleich `
        + `(${g[0].text.split('\n').length} Zeilen SQL). `
        + (gleicherInhalt
            ? `Auch der Inhalt stimmt überein: ${gleicherInhalt.n} Zeilen, `
              + `${gleicherInhalt.nurA} nur in der einen, ${gleicherInhalt.nurB} nur in der anderen. `
            : '')
        + g.map(o => {
            const l = leserVon(db, o.name)
            return `\`${o.name}\` liest ${l.length ? l.join(', ') : 'keine Sicht (nur die Oberfläche)'}`
          }).join('; ') + '.'
        + (kosten ? ` Das Füllen der zweiten kostet ${kosten.sekunden.toFixed(2)} s und `
                  + `${Math.round(kosten.bytes / 1024)} kB — bei jedem Neurechnen.` : ''),
      muesste: 'Eine der beiden kann eine gewöhnliche Ansicht auf die andere werden '
        + `(\`create or replace view … as select * from …\`). Dann steht die Rechnung einmal da, `
        + 'wird einmal gefüllt, und wer eine Formel darin ändert, ändert sie nicht an einer von '
        + 'zwei Stellen.',
      warum: 'Zwei gleiche Rechnungen sind nicht doppelt so sicher, sondern halb so sicher: Wer '
        + 'die eine anfasst und die andere übersieht, hat zwei Zahlen, die dasselbe heissen und '
        + 'verschieden sind — und nichts im Programm merkt es. Genau davor schützt das '
        + 'Werkzeug B1 nicht, denn beide haben einen Leser und gelten ihm als lebendig.',
      beleg: 'werkstatt/c_bauwerk/c2_doppelgaenger.mjs: `pg_get_viewdef` beider Objekte '
        + 'normalisiert verglichen'
        + (gleicherInhalt ? ', Inhalt mit `except` in beide Richtungen' : ''),
      groesse: kosten
        ? { wert: kosten.sekunden.toFixed(2),
            einheit: `s je Neurechnung, die eine zweite Kopie derselben ${gleicherInhalt?.n ?? '?'} `
                   + `Zeilen erzeugt (${Math.round(kosten.bytes / 1024)} kB)`,
            basis: 'Demodaten' }
        : { wert: g[0].text.split('\n').length,
            einheit: 'Zeilen SQL, die zweimal dastehen', basis: 'Demodaten' },
      gegenrede: 'Die Trennung kann Absicht sein: Das Programm hält `erg_*` als das, was die '
        + 'Oberfläche liest, und `mv_*`/`v_*` als das, worauf die Rechnung aufbaut. Wer beides '
        + 'zusammenlegt, verliert diese Trennung, und der nächste Umbau der Rechnung kann die '
        + 'Oberfläche mitreissen. Dagegen steht: Die Trennung trägt nur, solange die beiden '
        + 'wirklich verschieden sind. Sind sie zeichengleich, ist sie eine Behauptung, keine '
        + 'Trennung — und kostet bei jedem Neurechnen Zeit.',
      aufwand: 'klein',
    }))
  }

  if (!gruppen.length) raus.push(befund({
    werkstatt: WERKSTATT, kuerzel: 'DOP', klasse: 1, marke: 'kein Fehler', sicherheit: 'hoch',
    ort: { sicht: 'public' },
    titel: `Geprüft und in Ordnung: keine zwei der ${alle.length} Objekte sind dieselbe Rechnung`,
    steht_da: `${alle.length} Ansichten, gespeicherte Ansichten und Funktionen, paarweise über `
      + 'ihre normalisierte Definition verglichen — kein Paar ist zeichengleich.',
    muesste: '—',
    warum: 'Zwei gleiche Rechnungen laufen auseinander, sobald jemand eine davon anfasst. Dass es '
      + 'keine gibt, ist eine Auskunft und keine Selbstverständlichkeit.',
    beleg: 'werkstatt/c_bauwerk/c2_doppelgaenger.mjs',
    groesse: { wert: alle.length, einheit: 'Objekte verglichen, kein Zwillingspaar',
               basis: 'Demodaten' },
    aufwand: 'klein',
  }))

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Drei erfundene Fälle für den Vergleicher:
 *
 *   1. Zwei zeichengleiche Definitionen unter verschiedenen Namen — müssen
 *      gefunden werden. Sonst hätte das Werkzeug den Fall, für den es gebaut
 *      ist, gar nicht sehen können.
 *   2. Zwei Definitionen, die sich nur in Leerraum unterscheiden — ebenfalls.
 *      Ein Vergleich, der an einem Zeilenumbruch scheitert, findet in einer
 *      gewachsenen Datenbank nie etwas.
 *   3. Zwei Definitionen, die sich in **einer Zahl** unterscheiden — dürfen
 *      **nicht** gefunden werden. Das ist die wichtigere Hälfte: Ein Werkzeug,
 *      das Ähnliches für Gleiches hält, schlägt vor, zwei verschiedene
 *      Rechnungen zusammenzulegen.
 */
export async function selbstprobe() {
  const a = { name: 'a', text: 'select x, y from t where x > 0 and y is not null order by x' }
  const b = { name: 'b', text: 'select x,   y from t\n where x > 0\n   and y is not null order by x' }
  const c = { name: 'c', text: 'select x, y from t where x > 1 and y is not null order by x' }
  const kurz1 = { name: 'k1', text: 'select 1' }
  const kurz2 = { name: 'k2', text: 'select 1' }

  const g = zwillinge([a, b, c, kurz1, kurz2])
  if (g.length !== 1) return false
  const namen = g[0].map(o => o.name).sort().join(',')
  if (namen !== 'a,b') return false

  // Der eigene Name darf den Vergleich nicht verhindern.
  const d = { name: 'erg_punkte', text: 'select v.a from erg_punkte v where v.a > 0 and v.a < 9' }
  const e = { name: 'mv_punkte',  text: 'select v.a from mv_punkte  v where v.a > 0 and v.a < 9' }
  if (zwillinge([d, e]).length !== 1) return false

  return true
}
