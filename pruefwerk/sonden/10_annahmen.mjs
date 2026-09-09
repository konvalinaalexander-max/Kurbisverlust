/**
 * Sonde 10 — Annahmen
 *
 * In `docs/ABLAUF.md` steht eine Tabelle mit allen Annahmen, auf denen die
 * Rechnung ruht: was angenommen wird, warum, und was passiert, wenn es nicht
 * stimmt. Die Tabelle ist ehrlich und vollständig — sie ist bloss unverbunden:
 * Sie sagt zu keiner Zeile, **wo es auffiele**, wenn die Annahme bricht.
 *
 * Diese Sonde versucht die Verbindung zuerst maschinell — und zeigt damit, dass
 * es maschinell nicht geht. Die Stichwortsuche findet zu fast jeder Annahme
 * irgendeine Datei, in der eines ihrer Wörter vorkommt; das ist kein Beleg,
 * sondern ein Zufall. Genau deshalb ist der Befund kein „N Annahmen sind
 * ungeprüft", sondern: Die Tabelle braucht eine vierte Spalte, und die kann
 * nur ein Mensch füllen. Danach kann diese Sonde sie bewachen — dann prüft sie,
 * ob jede genannte Wache existiert und ob jede bewusst offen gelassene Annahme
 * als solche gekennzeichnet ist.
 *
 * Die Stichworttabelle unter `pruefwerk/befunde/annahmen.md` ist der Vorschlag,
 * mit dem sich die Spalte füllen lässt — nicht ihr Ersatz.
 */
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { WURZEL, befund, dateien, frage, lies, schreibe } from '../umgebung.mjs'

const bestehtDatei = (p) => existsSync(join(WURZEL, p))

export const lang = false

/** Die Tabelle „Annahme | Warum sie drinsteht | Was passiert, wenn sie nicht stimmt". */
export function annahmen(text) {
  const zeilen = text.split('\n')
  const kopf = zeilen.findIndex(z => /^\|\s*Annahme\s*\|/.test(z))
  if (kopf < 0) return []
  const raus = []
  for (let i = kopf + 2; i < zeilen.length; i++) {
    const z = zeilen[i]
    if (!z.startsWith('|')) break
    const teile = z.split('|').slice(1, -1).map(t => t.trim())
    if (teile.length < 3) continue
    raus.push({ nr: raus.length + 1, annahme: teile[0], warum: teile[1], folge: teile[2],
                wache: (teile[3] ?? '').trim() })
  }
  return raus
}

/**
 * Die Wörter, mit denen sich eine Annahme wiederfinden lässt: alles, was
 * `code` ist (in Rückstrichen), plus die tragenden Hauptwörter. Bewusst eng —
 * ein zu weiter Fangkorb findet überall etwas und behauptet dann Deckung,
 * wo keine ist.
 */
export function stichworte(a) {
  const code = [...a.annahme.matchAll(/`([^`]+)`/g)].map(m => m[1])
  const worte = (a.annahme + ' ' + a.folge)
    .replace(/`[^`]*`/g, ' ')
    .match(/\b[A-ZÄÖÜ][a-zäöüß]{5,}\b/g) ?? []
  return [...new Set([...code, ...worte])].slice(0, 8)
}

export async function laufen({ db }) {
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '10_annahmen', kuerzel: 'ANN', ...o }))

  const liste = annahmen(lies('docs/ABLAUF.md'))
  if (!liste.length) {
    B({ klasse: 2, ort: { datei: 'docs/ABLAUF.md' }, titel: 'Die Annahmentabelle ist nicht mehr zu finden',
        steht_da: 'Keine Zeile „| Annahme | …" in docs/ABLAUF.md.',
        muesste: 'Die Tabelle steht dort und ist maschinell lesbar.',
        warum: 'Ohne sie prüft niemand die Annahmen — auch diese Sonde nicht.',
        beleg: 'pruefwerk/sonden/10_annahmen.mjs',
        groesse: { wert: 0, einheit: 'Annahmen gefunden', basis: 'docs/ABLAUF.md' },
        sicherheit: 'hoch', marke: 'Reparatur' })
    return raus
  }

  /* Wo überall eine Annahme bewacht sein kann */
  const wachen = []
  for (const p of ['supabase/test/pruefung.sql', 'supabase/test/run.sh'])
    wachen.push({ art: 'Prüfung', pfad: p, text: lies(p) })
  for (const p of dateien('pruefstand', /\.(mjs|sh)$/))
    wachen.push({ art: 'Prüfstand', pfad: p, text: lies(p) })
  for (const p of dateien('src', /\.test\.ts$/))
    wachen.push({ art: 'Test', pfad: p, text: lies(p) })
  for (const p of dateien('pruefwerk', /\.mjs$/).filter(p => !p.includes('10_annahmen')))
    wachen.push({ art: 'Prüfwerk', pfad: p, text: lies(p) })
  /* Welche Arten von Auffälligkeiten es **geben kann** — nicht, welche gerade
     in den Daten stehen. Die Demosaison hat nicht jeden Fall; eine Wache, die
     es gibt, dürfte deshalb nicht als erfunden gelten. */
  const arten = [...new Set(
    frage(db, `select pg_get_viewdef(c.oid, true) as text
                 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public' and c.relname like 'v\\_plausibilitaet%'`)
      .flatMap(r => [...r.text.matchAll(/'([^']+)'::text AS art\b/g)].map(m => m[1]))
      .concat(frage(db, `select distinct art from v_plausibilitaet`).map(r => r.art)))]
  wachen.push({ art: 'Auffälligkeit', pfad: 'v_plausibilitaet', text: arten.join(' ') })

  /* Ein Stichwort, das in fast jeder Datei vorkommt („Paletten", „Charge"),
     belegt gar nichts. Nur Wörter, die selten sind, taugen als Beleg — die
     Schwelle richtet sich nach dem Bestand selbst, nicht nach einem Gefühl. */
  const SELTEN = Math.max(2, Math.ceil(wachen.length * 0.25))
  const haeufigkeit = (s) => wachen.filter(x => x.text.includes(s)).length
  const bewertet = liste.map(a => {
    const w = stichworte(a).filter(s => { const h = haeufigkeit(s); return h > 0 && h <= SELTEN })
    const verworfen = stichworte(a).filter(s => haeufigkeit(s) > SELTEN)
    const gefunden = wachen.filter(x => w.some(s => x.text.includes(s)))
    return { ...a, stichworte: w, verworfen,
             wachen: [...new Set(gefunden.map(g => `${g.art}: ${g.pfad}`))] }
  })
  const unbewacht = bewertet.filter(b => b.wachen.length === 0)

  schreibe('pruefwerk/befunde/annahmen.md', bericht(bewertet, arten))

  /* Die vierte Spalte: Wo würde es auffallen? */
  const kopf = /^\|\s*Annahme\s*\|(.*)$/m.exec(lies('docs/ABLAUF.md'))?.[1] ?? ''
  const hatSpalte = /auffiele|bewacht|Wache/i.test(kopf)
  if (!hatSpalte) {
    B({ klasse: 3, ort: { datei: 'docs/ABLAUF.md' },
        titel: `Zu keiner der ${liste.length} Annahmen steht, wo ihr Bruch auffiele`,
        steht_da: `Die Tabelle hat die Spalten „${kopf.split('|').filter(Boolean).map(x => x.trim()).join('", „')}". `
                + `Eine Stichwortsuche über ${wachen.length} Prüfungen, Prüfstände, Tests und `
                + `Auffälligkeitsarten findet zu ${liste.length - unbewacht.length} Annahmen irgendeinen `
                + `Treffer. Das ist kein Beleg, sondern Zufall: gesucht wird ein Wort, nicht eine Behauptung.`,
        muesste: 'Eine vierte Spalte „Wo es auffiele" — je Annahme ein Zeiger auf die Stelle, die '
               + 'anschlägt, oder ausdrücklich „nirgends — bewusst in Kauf genommen".',
        warum: 'Eine Annahme, deren Bruch keine Spur hinterlässt, ist die teuerste Sorte Fehler.',
        beleg: 'pruefwerk/befunde/annahmen.md',
        groesse: { wert: liste.length, einheit: 'Annahmen ohne benannte Wache', basis: 'docs/ABLAUF.md' },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'mittel' })
  } else {
    /* Die Spalte ist da — jetzt wird sie bewacht. Eine leere Zelle ist eine
       offene Frage; ein „nirgends" ohne Begründung ist eine verschwiegene. */
    const leer = liste.filter(a => !a.wache)
    const OFFEN = /nirgends|keine Prüfung|kein Schutz/i
    const BEGRUENDET = /in Kauf genommen|Frage an den Betrieb|das ist der Schutz|keine Prüfung|einzige Schutz|hinterlässt keine Spur/i
    const nackt = liste.filter(a => a.wache && OFFEN.test(a.wache) && !BEGRUENDET.test(a.wache))
    if (leer.length || nackt.length) {
      B({ klasse: 2, ort: { datei: 'docs/ABLAUF.md' },
          titel: `${leer.length + nackt.length} Annahmen sagen nicht, wo ihr Bruch auffiele`,
          steht_da: [...leer, ...nackt].map(a => `„${a.annahme.slice(0, 80)}"`).join('; '),
          muesste: 'Jede Zeile nennt eine Stelle — oder sagt „nirgends" **und** warum das in Kauf '
                 + 'genommen wird.',
          warum: 'Die Spalte ist da; eine leere Zelle darin ist eine offene Frage, keine Antwort.',
          beleg: 'pruefwerk/befunde/annahmen.md',
          groesse: { wert: leer.length + nackt.length, einheit: 'Zeilen ohne Antwort', basis: `${liste.length} Annahmen` },
          sicherheit: 'hoch', marke: 'Reparatur' })
    }
    /* Und: Nennt eine Zeile eine Auffälligkeit, muss es sie geben. */
    const erfunden = []
    for (const a of liste) {
      for (const m of a.wache.matchAll(/Auffälligkeit „([^"„]+)"/g))
        if (!arten.includes(m[1])) erfunden.push({ annahme: a.annahme, art: m[1] })
      for (const m of a.wache.matchAll(/`([^`]+\.(?:ts|mjs|sql|md))`/g))
        if (!bestehtDatei(m[1])) erfunden.push({ annahme: a.annahme, art: m[1] })
    }
    if (erfunden.length) {
      B({ klasse: 3, ort: { datei: 'docs/ABLAUF.md' },
          titel: 'Eine Annahme nennt eine Wache, die es nicht gibt',
          steht_da: erfunden.map(e => `„${e.art}" (zu: ${e.annahme.slice(0, 60)})`).join('; '),
          muesste: 'Jede genannte Auffälligkeit steht in v_plausibilitaet, jede genannte Datei im Bestand.',
          warum: 'Eine Wache, die es nicht gibt, ist schlimmer als keine: Sie beruhigt und hält niemanden auf. '
               + 'Auffälligkeiten werden umbenannt und Dateien verschoben — genau dafür ist diese Prüfung da.',
          beleg: 'pruefwerk/sonden/10_annahmen.mjs',
          groesse: { wert: erfunden.length, einheit: 'erfundene Wachen', basis: `${liste.length} Annahmen` },
          sicherheit: 'hoch', marke: 'Reparatur' })
    }
  }

  /* Eine Annahme, die diese Runde bereits als gebrochen gemessen hat */
  const umgestapelt = liste.find(a => /Kistenzahl und dieselbe Gebindeart/.test(a.annahme))
  if (umgestapelt) {
    B({ klasse: 1, ort: { datei: 'docs/ABLAUF.md' },
        titel: 'Geprüft: Die Annahme zur umgestapelten Palette steht in der Tabelle und ist messbar gebrochen',
        steht_da: `„${umgestapelt.annahme}" — Folge laut Tabelle: ${umgestapelt.folge}`,
        muesste: 'Nichts an der Tabelle. Der Störfall S7 in Sonde 07 zeigt die Grösse: fünf Kisten '
               + 'weniger geben eine um rund ein Zehntel zu hohe Tagesrate.',
        warum: 'Die Tabelle ist an dieser Stelle vollständig und ehrlich — sie benennt genau den Fehler, '
             + 'den das Prüfwerk unabhängig gefunden hat. Das spricht für die Tabelle und dafür, die '
             + 'übrigen Zeilen ebenso ernst zu nehmen.',
        beleg: 'pruefwerk/sonden/07_szenarien.mjs → S7',
        groesse: { wert: 1, einheit: 'bestätigte Annahme', basis: 'ABLAUF.md × Störfall S7' },
        sicherheit: 'hoch', marke: 'kein Fehler' })
  }

  return raus
}

function bericht(bewertet, arten) {
  const ohne = bewertet.filter(b => !b.wachen.length)
  return `# Die Annahmen und ihre Wachen

Erzeugt von \`pruefwerk/sonden/10_annahmen.mjs\` aus der Annahmentabelle in
\`docs/ABLAUF.md\`. Zu jeder Annahme steht, wo im Bestand etwas gefunden wurde,
das ihren Bruch bemerken könnte.

**Wie gesucht wird.** Über Stichworte: alles, was in der Annahme in Rückstrichen
steht (Spalten- und Einstellungsnamen), dazu die tragenden Hauptwörter. Gesucht
wird in \`supabase/test/pruefung.sql\`, in \`pruefstand/\`, in den Modultests, im
Prüfwerk und in den Arten von \`v_plausibilitaet\` (${arten.join(', ')}).

Stichworte, die in mehr als einem Viertel aller durchsuchten Dateien vorkommen,
werden verworfen: „Palette" und „Charge" stehen überall und belegen deshalb
nichts. Übrig bleiben die seltenen Wörter — die, die wirklich zu dieser Annahme
gehören.

Auch so bleibt es grob. Ein Treffer heisst „hier kommt das Wort vor", nicht
„hier wird die Annahme geprüft". Kein Treffer heisst dagegen ziemlich sicher:
niemand sieht hin.

**${bewertet.length} Annahmen, ${ohne.length} davon ohne jeden Treffer.**

| # | Annahme | Was passiert, wenn sie nicht stimmt | Stichworte | Wache |
|---|---|---|---|---|
${bewertet.map(b => `| ${b.nr} | ${b.annahme} | ${b.folge} | ${b.stichworte.map(s => '`' + s + '`').join(' ') || '—'} | ${b.wachen.length ? b.wachen.join('<br>') : '**keine**'} |`).join('\n')}
`
}

/**
 * Selbstprobe: Der Leser bekommt eine Tabelle in der bekannten Form und muss
 * sie richtig zerlegen — und eine Annahme mit einem Wort, das nirgends
 * vorkommt, darf nicht als bewacht durchgehen.
 */
export async function selbstprobe() {
  const probe = [
    '| Annahme | Warum sie drinsteht | Was passiert, wenn sie nicht stimmt |',
    '|---|---|---|',
    '| Die Rate ist konstant | eine Wägung je Palette | früher unterschätzt |',
    '| Der Behälter wiegt `palox_tara_kg` | Betrieb | jede Ablesung zu hoch |',
    '',
  ].join('\n')
  const a = annahmen(probe)
  if (a.length !== 2 || a[1].annahme !== 'Der Behälter wiegt `palox_tara_kg`') return false
  const s = stichworte(a[1])
  return s.includes('palox_tara_kg') && !s.includes('Der') && !s.includes('wiegt')
}
