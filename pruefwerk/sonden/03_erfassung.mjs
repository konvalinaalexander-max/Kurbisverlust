/**
 * Sonde 03 — Erfassung
 *
 * Zwischen dem, was im Betrieb beobachtet wird, und dem, was die Datenbank
 * speichert, liegen zwei Fehlerarten, die beide teuer sind:
 *
 *   Erfasst und nie gelesen. Der Arbeiter tippt eine Zahl ein, die keine Sicht
 *   je anfasst. Das kostet Zeit an der Waage — und schlimmer: Es sieht so aus,
 *   als würde die Zahl gebraucht, also achtet niemand darauf, ob sie stimmt.
 *
 *   Gelesen und nicht erzwungen. Die Maske verlangt ein Feld, die Datenbank
 *   nicht. Was durch die Maske kommt, ist vollständig; was über den
 *   Excel-Import, eine spätere Maske oder eine Korrektur von Hand hereinkommt,
 *   muss es nicht sein — und die Rechnung dahinter nimmt die Lücke als Null.
 *
 * Beides ist im Bestand nachweisbar, ohne den Betrieb zu fragen: Die Sonde
 * vergleicht die Spalten der Erfassungstabellen mit allem, was sie irgendwo
 * liest, und die Pflichtfelder der Masken mit den Bedingungen der Tabellen.
 */
import { befund, dateien, frage, lies } from '../umgebung.mjs'
import { verlangt } from './01_herkunft.mjs'

export const lang = false

/** Die Tabellen, in die im Betrieb geschrieben wird — nicht die Stammdaten. */
const ERFASSUNG = [
  'palette', 'lieferung', 'auftrag', 'auftrag_palette', 'auftrag_gebinde', 'auftrag_angabe',
  'auftrag_teilnehmer', 'schimmel_messung', 'ausschuss_messung', 'verdunstung_wiegung',
  'ausgang_wiegung', 'sortier_lauf', 'sortier_gewicht',
]

/** Spalten, die zur Buchführung gehören und nirgends „gelesen" werden müssen. */
const VERWALTUNG = /^(id|erfasser|erfasst_ts|ts|erstellt_ts|geaendert_ts|angelegt_ts|quelle|bemerkung)$/

export async function laufen({ db }) {
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '03_erfassung', kuerzel: 'ERF', ...o }))

  const spalten = frage(db, `
    select c.relname as tabelle, a.attname as spalte, a.attnotnull as pflicht,
           (d.adbin is not null) as vorgabe, format_type(a.atttypid, a.atttypmod) as art
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
      left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
     where n.nspname = 'public' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
       and c.relname = any(array[${ERFASSUNG.map(t => `'${t}'`).join(',')}])
     order by 1, a.attnum`)

  /* Alles, was irgendwo liest: Sichten, Funktionen, Auslöser, Oberfläche. */
  const leser = frage(db, `
    select coalesce(pg_get_viewdef(c.oid, true), '') as text
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('v','m')`).map(r => r.text)
    .concat(frage(db, `select pg_get_functiondef(p.oid) as text from pg_proc p
                        join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.prokind = 'f'`).map(r => r.text))
    .concat(dateien('src').map(p => lies(p)))
    .concat(dateien('supabase', /\.(sql|mjs)$/).filter(p => !p.includes('/migrations/')).map(p => lies(p)))
    .join('\n')

  /* 3a. Erfasst und nie gelesen */
  const tot = []
  for (const s of spalten) {
    if (VERWALTUNG.test(s.spalte)) continue
    // Vorkommen ausserhalb der eigenen Tabellendefinition
    const wort = new RegExp(`\\b${s.spalte}\\b`, 'g')
    if ((leser.match(wort) ?? []).length === 0) tot.push(s)
  }
  if (tot.length) {
    B({ klasse: 2, ort: { sicht: [...new Set(tot.map(t => t.tabelle))].join(', ') },
        titel: `${tot.length} erfasste Spalten werden nirgends gelesen`,
        steht_da: tot.map(t => `${t.tabelle}.${t.spalte}`).join(', '),
        muesste: 'Entweder gelesen werden oder nicht erfasst. Wenn sie als Beleg für später gedacht '
               + 'sind, gehört das in die Beschreibung der Spalte — dann ist es eine Entscheidung '
               + 'und kein Versehen.',
        warum: 'Jede erfasste Zahl kostet Zeit an der Waage und suggeriert Bedeutung. Eine Zahl, die '
             + 'niemand liest, wird auch von niemandem geprüft — und wenn sie später doch gebraucht '
             + 'wird, ist sie seit Monaten falsch.',
        beleg: 'pruefwerk/sonden/03_erfassung.mjs → 3a',
        groesse: { wert: tot.length, einheit: 'Spalten', basis: `${spalten.length} Spalten in ${ERFASSUNG.length} Erfassungstabellen` },
        sicherheit: 'mittel', marke: 'Entscheidung des Betriebs', aufwand: 'klein',
        gegenrede: 'Die Suche geht über Wortvorkommen. Eine Spalte, die nur über `select *` mitkommt '
                 + 'und in der Oberfläche über einen berechneten Namen angesprochen wird, kann fälschlich '
                 + 'als tot gelten. Die Liste ist kurz genug, um sie von Hand durchzugehen.' })
  }

  /* 3b. Die Maske verlangt es, die Datenbank nicht */
  const schreibt = new Map()          // tabelle → Set(spalte)
  for (const p of dateien('src'))
    for (const v of verlangt(lies(p), p).filter(v => v.art === 'schreibt')) {
      if (!schreibt.has(v.tabelle)) schreibt.set(v.tabelle, new Set())
      schreibt.get(v.tabelle).add(v.spalte)
    }
  const weich = spalten.filter(s => !s.pflicht && !s.vorgabe && !VERWALTUNG.test(s.spalte)
                                 && schreibt.get(s.tabelle)?.has(s.spalte))
  if (weich.length) {
    /* Die gefährliche Teilmenge: Felder, die eine Sicht mit `coalesce(…, 0)` liest.
       Dort wird aus der Lücke nachweislich eine Null, die weiterrechnet — bei
       allen anderen kann eine Lücke auch einfach zu NULL führen und damit
       ehrlich bleiben. */
    const sichten = frage(db, `select pg_get_viewdef(c.oid, true) as text
                                 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                where n.nspname = 'public' and c.relkind in ('v','m')`)
      .map(r => r.text).join('\n')
    const rechnend = weich.filter(s =>
      new RegExp(`COALESCE\\(\\s*[a-z_0-9]*\\.?${s.spalte}\\s*,\\s*\\(?0`, 'i').test(sichten))
    B({ klasse: rechnend.length ? 3 : 2, ort: { sicht: [...new Set(weich.map(w => w.tabelle))].join(', ') },
        titel: rechnend.length
          ? `${rechnend.length} Felder verlangt die Maske, die Datenbank lässt sie leer — und die Rechnung macht eine Null daraus`
          : `${weich.length} Felder verlangt die Maske, die Datenbank lässt sie leer`,
        steht_da: (rechnend.length
            ? `Mit Folge für die Rechnung (\`coalesce(…, 0)\` in einer Sicht): `
              + rechnend.map(w => `${w.tabelle}.${w.spalte}`).join(', ') + '. '
            : '')
          + `Insgesamt ${weich.length} Felder, die die Maske verlangt und die Tabelle nicht: `
          + weich.map(w => `${w.tabelle}.${w.spalte}`).join(', '),
        muesste: '`not null` auf den Feldern, ohne die die Zeile nicht rechenbar ist. Wo eine Lücke '
               + 'zulässig sein soll, gehört sie ausdrücklich zugelassen — und die Rechnung dahinter '
               + 'muss sie als „unbekannt" behandeln, nicht als Null.',
        warum: 'Die Maske ist nicht der einzige Weg in die Tabelle: Der Excel-Import des Warenausgangs, '
             + 'eine Korrektur im SQL-Editor und jede künftige Maske schreiben an ihr vorbei. Die '
             + 'Bedingung in der Tabelle ist die einzige Stelle, die für alle Wege gilt. '
             + '`palette.kisten` ist der belegte Fall: fehlt die Zahl, rechnet `v_palette` mit null '
             + 'Kisten und das Nettogewicht wird zu hoch (Sonde 08).',
        beleg: 'pruefwerk/sonden/03_erfassung.mjs → 3b',
        groesse: { wert: rechnend.length || weich.length,
                   einheit: rechnend.length ? 'Felder, aus deren Lücke eine Null wird' : 'Felder ohne Bedingung',
                   basis: `${weich.length} Felder, die die Maske verlangt` },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: 'Eine Bedingung nachträglich zu setzen kann an Altbeständen scheitern, in denen '
                 + 'die Lücke schon steht. Dann ist die richtige Antwort nicht „lassen", sondern '
                 + 'erst aufräumen und dann setzen — oder die Lücke sauber als „unbekannt" durch '
                 + 'die Rechnung tragen.' })
  }

  /* 3c. Mehr geliefert als hereingekommen — der Erfassungsfehler, der keine
     Auffälligkeit auslöst. Die Kaskade fängt ihn ab (`ueberzaehlung_kg`, damit
     die Bilanz aufgeht), aber abfangen ist nicht dasselbe wie melden. */
  const ueber = frage(db, `
    select round(sum(ueberzaehlung_kg))::numeric as gesamt,
           round(sum(eingang_kg))::numeric as eingang,
           count(*) filter (where ueberzaehlung_kg > 0)::int as chargen,
           max(round(100 * ueberzaehlung_kg / nullif(eingang_kg, 0), 1))::numeric as schlimmste,
           (array_agg(charge_nr order by ueberzaehlung_kg desc))[1] as charge
      from erg_charge`)[0]
  const arten = frage(db, `select distinct art from v_plausibilitaet`).map(r => r.art)
  if (Number(ueber?.chargen ?? 0) > 0 && !arten.some(a => /berzählung|mehr geliefert/i.test(a))) {
    B({ klasse: 3, ort: { sicht: 'v_plausibilitaet' },
        titel: 'Mehr geliefert als hereingekommen — und keine Auffälligkeit dazu',
        steht_da: `${Number(ueber.chargen)} Chargen liefern zusammen ${Number(ueber.gesamt)} kg mehr aus, `
                + `als für sie je als Eingang erfasst wurde (${Number(ueber.schlimmste)} % bei Charge `
                + `${ueber.charge}). \`v_plausibilitaet\` kennt dafür keine Art: gemeldet werden `
                + arten.map(a => `„${a}"`).join(', ') + '.',
        muesste: 'Eine Auffälligkeit „Überzählung" mit der Charge, den Kilo und dem Sprung zur '
               + 'Korrektur — wie bei „Zetteldatum" und „Lieferung in der Zukunft" auch. Der Betrieb '
               + 'sieht Auffälligkeiten unter Messungen; nur dort sucht er nach etwas zu Korrigierendem.',
        warum: 'Eine Charge, die mehr abgibt, als sie bekommen hat, ist kein Verlustphänomen, sondern '
             + 'ein Erfassungsfehler: eine fehlende Palette im Erntejournal, eine Lieferung auf die '
             + 'falsche Charge gebucht, eine vertauschte Chargennummer. Die Kaskade fängt ihn ab, damit '
             + 'die Bilanz aufgeht — und genau deshalb fällt er niemandem auf. Er verzerrt aber jede '
             + 'Verlustquote dieser Charge, weil ihr Nenner zu klein ist.',
        beleg: 'pruefwerk/sonden/03_erfassung.mjs → 3c',
        groesse: { wert: Number(ueber.gesamt), einheit: 'kg mehr geliefert als erfasst',
                   basis: `${Number(ueber.chargen)} Chargen, ${(100 * Number(ueber.gesamt) / Number(ueber.eingang)).toFixed(2)} % des Eingangs` },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: 'Die Zahl steht auf der Chargen-Seite jeder betroffenen Charge („mehr geliefert als '
                 + 'hereingekommen") und in der Bilanz unter Messungen. Sie ist also nicht verborgen — '
                 + 'nur nicht dort, wo der Betrieb nach Fehlern sucht, und ohne den Sprung zur '
                 + 'Korrektur, den die anderen Auffälligkeiten haben.' })
  }

  return raus
}

/**
 * Selbstprobe: Eine Spalte, die es sicher gibt und die sicher gelesen wird
 * (`palette.brutto_kg`), darf nicht als tot gelten; eine erfundene schon.
 */
export async function selbstprobe({ db = 'demo' } = {}) {
  const r = await laufen({ db })
  const totMeldung = r.find(b => b.titel.includes('nirgends gelesen'))
  if (totMeldung && /palette\.brutto_kg/.test(totMeldung.steht_da)) return false
  const s = frage(db, `select count(*) as n from pg_attribute a join pg_class c on c.oid = a.attrelid
                        where c.relname = 'palette' and a.attname = 'brutto_kg'`)[0]
  return Number(s.n) === 1 && r.length > 0
}
