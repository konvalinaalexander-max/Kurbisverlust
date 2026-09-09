/**
 * Sonde 02 — Bezugsgrössen
 *
 * Eine Prozentzahl besteht aus drei Teilen: Zähler, Nenner und der Beschriftung
 * daneben. Stimmen Zähler und Nenner, die Beschriftung aber nicht, ist die Zahl
 * trotzdem falsch — der Leser rechnet mit dem, was dasteht, nicht mit dem, was
 * im Quelltext steht.
 *
 * Diese Sonde tut zweierlei:
 *
 *   1. Sie zählt jede Prozentzahl der Oberfläche auf, mit Zähler, Nenner und
 *      Beschriftung, und legt das Verzeichnis ab. Ohne diese Liste ist jede
 *      Aussage über Bezugsgrössen ein Gefühl.
 *   2. Sie rechnet die strittige Kennzahl — „Verlust in % wovon?" — in allen
 *      Lesarten aus und beziffert den Unterschied. Entschieden wird sie nicht
 *      hier; entschieden wird sie im Betrieb. Vorgelegt wird sie hier.
 */
import { befund, dateien, frage, lies, schreibe, zeileVon } from '../umgebung.mjs'

export const lang = false

/* ---------- 1. Jede Prozentzahl der Oberfläche finden --------------------- */

/**
 * Findet `prozent(<ausdruck>)` und zerlegt den Ausdruck in Zähler und Nenner.
 * Bewusst kein Parser: Der Quelltext ist von Hand geschrieben und hält sich an
 * ein enges Muster (`bedingung ? zaehler / nenner : null`). Was nicht passt,
 * wird als „Form unbekannt" gemeldet statt stillschweigend übergangen — eine
 * Sonde, die Unverstandenes verschweigt, ist eine Sonde, die nichts findet.
 */
export function stellen(text, pfad) {
  const raus = []
  for (const t of treffer(text, 'prozent(')) {
    const a = t.argument
    // erstes Argument bis zum Komma auf oberster Klammerebene
    const erst = ersterTeil(a)
    const m = /^(?:(.*?)\s*\?\s*)?(.+?)\s*\/\s*(.+?)(?:\s*:\s*null)?$/s.exec(erst.trim())
    raus.push({
      pfad, zeile: zeileVon(text, t.index),
      ausdruck: erst.trim().replace(/\s+/g, ' '),
      wache: m?.[1]?.trim().replace(/\s+/g, ' ') ?? null,
      zaehler: m?.[2]?.trim().replace(/\s+/g, ' ') ?? null,
      nenner: m?.[3]?.trim().replace(/\s+/g, ' ') ?? null,
      beschriftung: beschriftungUm(text, t.index),
      form: m ? (m[1] ? 'bewacht' : 'ungeschützt') : (/^[a-z0-9_.?\[\]()]+$/i.test(erst.trim()) ? 'fertiger Anteil' : 'Form unbekannt'),
    })
  }
  return raus
}

/** Alle Aufrufe eines Namens mit ihrem vollständigen Argument. */
function treffer(text, name) {
  const raus = []
  let i = -1
  while ((i = text.indexOf(name, i + 1)) >= 0) {
    if (/[A-Za-z0-9_.]/.test(text[i - 1] ?? '')) continue      // z. B. „inProzent(" 
    let tiefe = 0, j = i + name.length - 1
    for (; j < text.length; j++) {
      const c = text[j]
      if (c === '(') tiefe++
      else if (c === ')') { tiefe--; if (tiefe === 0) break }
    }
    raus.push({ index: i, argument: text.slice(i + name.length, j) })
  }
  return raus
}

/** Das erste Argument eines Aufrufs — Kommas in inneren Klammern zählen nicht. */
function ersterTeil(a) {
  let tiefe = 0
  for (let i = 0; i < a.length; i++) {
    const c = a[i]
    if (c === '(' || c === '[' || c === '{') tiefe++
    else if (c === ')' || c === ']' || c === '}') tiefe--
    else if (c === ',' && tiefe === 0) return a.slice(0, i)
  }
  return a
}

/**
 * Was neben der Zahl steht. Gesucht wird der nächste Klartext vor oder nach
 * der Fundstelle — genau das, was der Leser sieht.
 */
function beschriftungUm(text, index) {
  const umfeld = text.slice(Math.max(0, index - 400), index + 400)
  const worte = [...umfeld.matchAll(/(?:titel|unter|xTitel|yTitel)\s*[:=]\s*[`'"]([^`'"]{3,80})[`'"]|>\s*([A-ZÄÖÜ][^<>{}\n]{3,60}?)\s*</g)]
    .map(m => (m[1] ?? m[2] ?? '').trim()).filter(Boolean)
  const nach = /\}\s*([^<>{}\n]{3,60})/.exec(text.slice(index, index + 200))?.[1]
    ?.trim().replace(/[`'"$\\]+$/, '').trim()
  return [nach, ...worte].filter(Boolean)[0] ?? null
}

/* ---------- 2. Die strittige Kennzahl ------------------------------------ */

/**
 * „Verlust in % wovon?" in allen Lesarten, auf denselben Daten.
 *
 * Wichtig ist die Trennung nach `portion`: Die Kaskade rechnet die
 * ausgelieferte Ware und die liegende Ware getrennt, jede mit ihrer eigenen
 * Eingangsmasse. Damit lässt sich die Frage sauber beantworten, statt sie zu
 * verhandeln.
 */
export function lesarten(db) {
  const s = frage(db, `
    select eingang_kg::numeric as eingang, ausgang_kg::numeric as ausgang,
           geliefert_kg::numeric as geliefert, verlust_heute_kg::numeric as verlust,
           im_haus_heute_kg::numeric as im_haus, ueberzaehlung_kg::numeric as ueber,
           verlust_bekannt from v_saisonbilanz`)[0]
  const p = frage(db, `
    select portion,
           sum(m0)::numeric as m0,
           sum(verdunstung_kg + sockel_kg + schimmel_kg
               + case when portion = 'ausgelagert' then fax_kg else 0 end)::numeric as verlust
      from mv_kaskade group by portion order by 1`)
  const z = (x) => Number(x ?? 0)
  const je = Object.fromEntries(p.map(r => [r.portion, { m0: z(r.m0), verlust: z(r.verlust) }]))
  const eingang = z(s?.eingang), ausgang = z(s?.ausgang), verlust = z(s?.verlust)
  const anteil = (a, b) => (b > 0 ? (100 * a) / b : null)
  return {
    eingang, ausgang, verlust, imHaus: z(s?.im_haus), ueber: z(s?.ueber),
    bekannt: s?.verlust_bekannt === true || s?.verlust_bekannt === 't',
    vomEingang: anteil(verlust, eingang),
    vomRest: anteil(verlust, eingang - ausgang),
    ausgelagert: { ...je.ausgelagert, pct: anteil(je.ausgelagert?.verlust ?? 0, je.ausgelagert?.m0 ?? 0) },
    lager: { ...je.lager, pct: anteil(je.lager?.verlust ?? 0, je.lager?.m0 ?? 0) },
  }
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db }) {
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '02_bezugsgroessen', kuerzel: 'BEZ', ...o }))

  /* 2a. Das Verzeichnis */
  const alle = dateien('src').flatMap(p => stellen(lies(p), p))
  const eins = (n) => alle.filter(a => a.form === n)

  /* 2b. Nenner ohne Wache — eine Division durch null gibt „∞ %" */
  for (const a of eins('ungeschützt')) {
    B({ klasse: 2, ort: { datei: a.pfad, zeile: a.zeile },
        titel: 'Prozentzahl ohne Wache auf dem Nenner',
        steht_da: `prozent(${a.ausdruck})`,
        muesste: `prozent(${a.nenner} > 0 ? ${a.zaehler} / ${a.nenner} : null)` +
                 ' — ohne Nenner ist der Anteil unbekannt, nicht null und nicht unendlich.',
        warum: 'Ist der Nenner 0, kommt Infinity oder NaN heraus. `prozent()` fängt NaN ab und '
             + 'schreibt „—", Infinity aber nicht: dort stünde „∞ %".',
        beleg: `${a.pfad}:${a.zeile}`,
        groesse: { wert: 1, einheit: 'Stelle', basis: 'Quelltextprüfung' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* 2c. Beschriftung nennt einen Nenner, der nicht der verwendete ist.
     Gesucht wird nur die Wendung, die den *ganzen* Eingang meint — „Eingangsware"
     und „Eingangsgewicht" bezeichnen etwas anderes und dürfen nicht anschlagen. */
  const GANZER_EINGANG = /\b(?:des|vom|am|der)\s+Eingang(?:s|smasse)?\b/i
  for (const a of alle) {
    if (!a.beschriftung || !a.nenner) continue
    if (GANZER_EINGANG.test(a.beschriftung) && !/eingang/i.test(a.nenner)) {
      B({ klasse: 2, ort: { datei: a.pfad, zeile: a.zeile },
          titel: 'Beschriftung nennt den Eingang, gerechnet wird mit etwas anderem',
          steht_da: `„${a.beschriftung}" über prozent(… / ${a.nenner})`,
          muesste: 'Entweder mit dem Eingang rechnen oder das nennen, womit gerechnet wird.',
          warum: 'Die Beschriftung ist das, was der Leser als Nenner annimmt. Heute trägt die Stelle, '
               + 'weil der einzige Aufrufer den Eingang übergibt — ein zweiter Aufrufer mit einem '
               + 'anderen Bezug macht die Zahl still falsch.',
          beleg: `${a.pfad}:${a.zeile}`,
          groesse: { wert: 1, einheit: 'Stelle', basis: 'Quelltextprüfung' },
          sicherheit: 'mittel', marke: 'Reparatur', aufwand: 'klein',
          gegenrede: 'Solange es bei einem Aufrufer bleibt, ist nichts falsch. Der Befund ist eine '
                   + 'Falle, keine Fehlfunktion — entsprechend klein zu bewerten.' })
    }
  }

  /* 2e. Prozent von etwas, das unbekannt sein kann — ohne Blick auf das Kennzeichen.
     Zu jedem unsicheren Strom führt die Datenbank ein `…_bekannt`. Wird der Strom
     in eine Prozentzahl gesteckt, ohne dass dieses Kennzeichen in der Nähe steht,
     wird aus „nicht gemessen" ein sauberes „0,0 %". Das ist der Grundsatz
     „leer ist nicht null", an der Stelle verletzt, an der er am meisten weh tut:
     in der Zahl, die ganz oben steht. */
  const staemme = frage(db, `select distinct left(column_name, length(column_name) - 8) as stamm
                               from information_schema.columns
                              where table_schema = 'public' and column_name like '%\\_bekannt'
                                and column_name <> 'koeff_bekannt'`).map(r => r.stamm).filter(Boolean)
  for (const a of alle) {
    if (!a.zaehler) continue
    const stamm = staemme.find(st => new RegExp(`\\b${st}(_|\\b)`, 'i').test(a.zaehler))
    if (!stamm) continue
    const text = lies(a.pfad)
    const i = text.split('\n').slice(0, a.zeile).join('\n').length
    if (/bekannt/i.test(text.slice(Math.max(0, i - 500), i + 500))) continue
    B({ klasse: 3, ort: { datei: a.pfad, zeile: a.zeile },
        titel: `Prozentzahl aus „${stamm}", ohne zu prüfen, ob „${stamm}" gemessen ist`,
        steht_da: `prozent(${a.ausdruck})` + (a.beschriftung ? ` — beschriftet „${a.beschriftung}"` : ''),
        muesste: `Ist \`${stamm}_bekannt\` falsch, gehört dort „nicht gemessen" hin, nicht eine Zahl. `
               + 'Die Datenbank führt das Kennzeichen bereits mit; es wird an dieser Stelle nur nicht gelesen.',
        warum: 'Ohne eine einzige Messung ist der Strom 0 kg — und 0 kg von einem Eingang sind '
             + '0,0 %. Der Leser sieht eine gemessene Null, wo nichts gemessen wurde. Genau dieser '
             + 'Fall tritt auf jedem Betrieb in der ersten Saison ein, bevor die erste Palette gewogen ist.',
        beleg: `${a.pfad}:${a.zeile}`,
        groesse: { wert: 100, einheit: '% Abweichung im ungemessenen Fall', basis: 'unbekannt wird als 0,0 % gezeigt' },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: (/nicht gemessen|unbekannt — nicht null/i.test(text)
            ? 'Die Seite zeigt unter den Zahlen einen Warnstreifen, der die ungemessenen Ursachen '
            + 'aufzählt — der Befund ist also kein Verschweigen. Er bleibt trotzdem stehen: Der '
            + 'Streifen nennt die Ursache, nicht die Folge, und die Prozentzahl darüber sieht '
            + 'unverändert nach einer Messung aus. Wer nur die grosse Zahl liest, liest eine Null. '
            : '')
          + `In den Demodaten ist \`${stamm}\` immer gemessen, deshalb fällt es nie auf — `
          + 'das ist kein Gegenargument, sondern die Erklärung, warum es stehen blieb.' })
  }

  /* 2d. Die strittige Kennzahl — vorlegen, nicht entscheiden */
  const l = lesarten(db)
  if (l.eingang > 0 && l.vomEingang !== null && l.vomRest !== null) {
    const spanne = Math.abs(l.vomRest - l.vomEingang)
    B({ klasse: 3, ort: { sicht: 'v_saisonbilanz', datei: 'src/pages/Ueberblick.tsx', zeile: 66 },
        titel: 'Verlust in Prozent — wovon? Drei Lesarten, bis zu ' + spanne.toFixed(1) + ' Prozentpunkte auseinander',
        steht_da: `„${l.vomEingang.toFixed(2)} % des Eingangs" (${Math.round(l.verlust)} von ${Math.round(l.eingang)} kg). `
                + `Dieselbe Zahl bezogen auf das, was noch nicht ausgeliefert ist, wäre `
                + `${l.vomRest.toFixed(2)} % (${Math.round(l.verlust)} von ${Math.round(l.eingang - l.ausgang)} kg).`,
        muesste: 'Zwei Zahlen nebeneinander, jede mit ihrer Aufgabe: '
               + `Saisonbilanz ${l.vomEingang.toFixed(1)} % des Eingangs (was von allem, was hereinkam, weg ist) und `
               + `getrennt nach Ware: ausgelieferte Ware ${l.ausgelagert.pct?.toFixed(1)} % `
               + `(${Math.round(l.ausgelagert.verlust)} von ${Math.round(l.ausgelagert.m0)} kg Eingangsmasse), `
               + `liegende Ware ${l.lager.pct?.toFixed(1)} % `
               + `(${Math.round(l.lager.verlust)} von ${Math.round(l.lager.m0)} kg, wächst weiter).`,
        warum: 'Die dritte Lesart — Verlust geteilt durch (Eingang − Ausgang) — ist die, nach der '
             + 'gefragt wird, und sie ist die einzige, die niemand verwenden sollte: Der Zähler '
             + 'enthält auch den Verlust der Ware, die bereits ausgeliefert ist, der Nenner aber '
             + 'nicht mehr ihre Masse. Sie mischt zwei Bestände und ist deshalb immer zu hoch. '
             + 'Was hinter der Frage steckt — „welcher Prozentsatz ist die Zahl, an der ich etwas '
             + 'ändern kann?" — beantwortet die Trennung nach Portion, und die rechnet die Kaskade '
             + 'ohnehin schon: die liegende Ware ist die Zahl zum Handeln, die ausgelieferte die '
             + 'zum Nachrechnen.',
        beleg: 'pruefwerk/sonden/02_bezugsgroessen.mjs → lesarten(); mv_kaskade nach portion gruppiert',
        groesse: { wert: Number(spanne.toFixed(1)), einheit: 'Prozentpunkte', basis: `Demosaison, ${Math.round(l.eingang)} kg Eingang` },
        sicherheit: 'hoch', marke: 'Frage an den Betrieb', aufwand: 'klein',
        gegenrede: 'Man kann argumentieren, dass eine einzige Zahl leichter zu merken ist als drei. '
                 + 'Dagegen steht, dass die eine Zahl heute schon zwei Bedeutungen trägt und der '
                 + 'Betriebsleiter nicht sieht, welche. Die Trennung nach Portion kostet keine neue '
                 + 'Rechnung — sie steht bereits in mv_kaskade.' })
  }

  /* Verzeichnis ablegen: die Liste ist der eigentliche Wert dieser Sonde */
  schreibe('pruefwerk/befunde/bezugsgroessen.md', verzeichnis(alle, l))
  return raus
}

/**
 * Selbstprobe: Der Leser bekommt drei Schnipsel mit bekannten Eigenschaften
 * vorgesetzt. Findet er sie nicht, ist er stumpf — dann sagen auch seine
 * leeren Befunde nichts.
 */
export async function selbstprobe() {
  const probe = `
    const a = <span>{prozent(verlust / eingang)}</span>              // ungeschützt
    const b = <span>{prozent(eingang > 0 ? verlust / eingang : null)}</span>  // bewacht
    const c = <span>{prozent(anteilFertig)}</span>                   // fertiger Anteil
  `
  const s = stellen(probe, 'probe.tsx')
  return s.length === 3
      && s[0].form === 'ungeschützt' && s[0].zaehler === 'verlust' && s[0].nenner === 'eingang'
      && s[1].form === 'bewacht' && s[1].nenner === 'eingang'
      && s[2].form === 'fertiger Anteil'
}

/* ---------- Das Verzeichnis ---------------------------------------------- */

/** Jede Prozentzahl der Oberfläche als Tabelle — die Grundlage jeder Aussage. */
function verzeichnis(alle, l) {
  const z = (x) => String(x ?? '—').replace(/\|/g, '\\|')
  const p = (x) => (x === null || x === undefined ? '—' : x.toFixed(2) + ' %')
  return `# Verzeichnis der Prozentzahlen

Erzeugt von \`pruefwerk/sonden/02_bezugsgroessen.mjs\`. Jede Stelle in \`src/\`,
an der die Oberfläche eine Prozentzahl zeigt, mit ihrem Zähler, ihrem Nenner und
der Beschriftung, die der Leser daneben sieht.

**Formen.** *bewacht* — der Nenner wird vor der Division geprüft, sonst „—".
*ungeschützt* — er wird nicht geprüft. *fertiger Anteil* — der Wert kommt
schon als Anteil aus der Datenbank, hier wird nur formatiert. *Form unbekannt* —
das Muster passt nicht; solche Stellen sind von Hand nachzusehen.

${alle.length} Stellen in ${new Set(alle.map(a => a.pfad)).size} Dateien.

| Stelle | Zähler | Nenner | Beschriftung | Form |
|---|---|---|---|---|
${alle.map(a => `| \`${a.pfad}:${a.zeile}\` | \`${z(a.zaehler)}\` | \`${z(a.nenner)}\` | ${z(a.beschriftung)} | ${a.form} |`).join('\n')}

## Die strittige Kennzahl, in Zahlen

Gemessen auf der Demosaison.

| Lesart | Zähler | Nenner | Ergebnis |
|---|---|---|---|
| Saisonbilanz: Verlust vom Eingang | ${Math.round(l.verlust)} kg | ${Math.round(l.eingang)} kg Eingang | **${p(l.vomEingang)}** |
| ausgelieferte Ware, für sich | ${Math.round(l.ausgelagert.verlust)} kg | ${Math.round(l.ausgelagert.m0)} kg Eingangsmasse dahinter | **${p(l.ausgelagert.pct)}** |
| liegende Ware, für sich | ${Math.round(l.lager.verlust)} kg | ${Math.round(l.lager.m0)} kg Eingangsmasse | **${p(l.lager.pct)}** |
| Verlust von (Eingang − Ausgang) | ${Math.round(l.verlust)} kg | ${Math.round(l.eingang - l.ausgang)} kg | ${p(l.vomRest)} |

Die letzte Zeile ist die Lesart, nach der gefragt wurde. Sie mischt zwei
Bestände: Im Zähler steht auch der Verlust der Ware, die schon ausgeliefert ist,
im Nenner steht deren Masse nicht mehr. Sie ist deshalb immer zu hoch und wird
umso höher, je mehr ausgeliefert ist — am Saisonende, wenn fast alles draussen
ist, geht sie gegen unendlich. Die beiden mittleren Zeilen beantworten dieselbe
Frage sauber, weil die Kaskade ohnehin nach Portion trennt.

Die Summe der beiden Portionsmassen (${Math.round(l.ausgelagert.m0 + l.lager.m0)} kg)
liegt über dem Eingang (${Math.round(l.eingang)} kg). Die Differenz von
${Math.round(l.ueber)} kg ist die Überzählung: hinter den Lieferungen steckt mehr
Eingangsware, als für diese Chargen je erfasst wurde. Sie steht als eigene Zahl
in der Saisonbilanz und ist hier nur der Vollständigkeit halber genannt.
`
}
