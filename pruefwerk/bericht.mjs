#!/usr/bin/env node
/**
 * Aus `pruefwerk/befunde/befunde.json` wird `docs/PRUEFBERICHT.md`.
 *
 *   node pruefwerk/bericht.mjs
 *
 * Der Bericht ist für den Betrieb geschrieben, nicht für die Entwicklung: In
 * klarem Deutsch, jede Feststellung mit ihrer Grösse, jede mit einer Gegenrede.
 * Wer ihn liest, soll entscheiden können, ohne den Quelltext zu öffnen.
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { HIER, WURZEL, schreibe } from './umgebung.mjs'

const MARKEN = ['Reparatur', 'Frage an den Betrieb', 'Entscheidung des Betriebs', 'kein Fehler']
const KLASSEN = {
  3: ['Bedeutung', 'Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch.'],
  2: ['Kette', 'Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht.'],
  1: ['Technisch', 'Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl.'],
}

const daten = JSON.parse(readFileSync(join(HIER, 'befunde/befunde.json'), 'utf8'))
const { stand, befunde } = daten

const ort = (o = {}) => [o.datei && `\`${o.datei}${o.zeile ? ':' + o.zeile : ''}\``,
                         o.sicht && `\`${o.sicht}\``, o.spalte && `Spalte \`${o.spalte}\``]
  .filter(Boolean).join(' · ') || '—'
const groesse = (g) => g ? `**${g.wert} ${g.einheit}** (${g.basis})` : '—'

function eintrag(b) {
  return `### ${b.id} · ${b.titel}

*${b.marke ?? 'Reparatur'} · Sicherheit ${b.sicherheit ?? 'mittel'} · Aufwand ${b.aufwand ?? 'klein'} · ${ort(b.ort)}*

**Grösse.** ${groesse(b.groesse)}

**Was dasteht.** ${b.steht_da}

**Was dastehen müsste.** ${b.muesste}

**Warum das zählt.** ${b.warum}
${b.gegenrede ? `\n**Gegenrede.** ${b.gegenrede}\n` : ''}
<sub>Nachweis: ${b.beleg}</sub>
`
}

const jeKlasse = (k) => befunde.filter(b => b.klasse === k)
const jeMarke = (m) => befunde.filter(b => (b.marke ?? 'Reparatur') === m)

const text = `# Prüfbericht

*Erzeugt von \`pruefwerk/bericht.mjs\` aus dem Lauf des Prüfwerks. Nicht von Hand ändern —
die Fassung, die zählt, entsteht neu mit \`node pruefwerk/lauf.mjs && node pruefwerk/bericht.mjs\`.*

## Was hier steht

${befunde.length} Feststellungen aus ${stand.length} Sonden. Jede hat eine Grösse — ohne Grösse
ist eine Feststellung eine Meinung, und eine Liste von Meinungen nimmt niemand ernst. Jede hat
eine Gegenrede, wo es eine gibt: das beste Argument dagegen, aufgeschrieben von dem, der die
Feststellung gemacht hat.

Nicht jede Feststellung ist ein Fehler. ${jeMarke('kein Fehler').length} sind ausdrücklich
„geprüft und in Ordnung" — sie stehen hier, weil ein Bericht, der nur Fehler nennt, nicht sagt,
wie weit nachgesehen wurde.

| Klasse | Was das heisst | Anzahl |
|---|---|---|
${[3, 2, 1].map(k => `| ${k} — ${KLASSEN[k][0]} | ${KLASSEN[k][1]} | ${jeKlasse(k).length} |`).join('\n')}

| Marke | Was zu tun ist | Anzahl |
|---|---|---|
| Reparatur | Etwas ist falsch und lässt sich richtigstellen, ohne die App zu erweitern. | ${jeMarke('Reparatur').length} |
| Frage an den Betrieb | Zwei Lesarten sind beide vertretbar; entscheiden muss der Betrieb. | ${jeMarke('Frage an den Betrieb').length} |
| Entscheidung des Betriebs | Es geht um den Ablauf im Betrieb, nicht um den Code. | ${jeMarke('Entscheidung des Betriebs').length} |
| kein Fehler | Nachgesehen, in Ordnung. | ${jeMarke('kein Fehler').length} |

## Was geprüft wurde

| Sonde | Feststellungen | Dauer | Selbstprobe |
|---|---|---|---|
${stand.map(s => `| \`${s.sonde}\` | ${s.befunde} | ${s.sekunden} s | ${s.selbstprobe}${s.fehler ? ` — abgebrochen: ${s.fehler}` : ''} |`).join('\n')}

Die Spalte **Selbstprobe** ist die wichtigste der Tabelle. Jede Sonde bekommt einen Fall
vorgesetzt, in dem sie anschlagen *muss*. Steht dort „ok", hat sie ihren eigenen eingebauten
Fehler gefunden; steht dort „STUMPF", sagt auch ihr leeres Ergebnis nichts.

${[3, 2, 1].map(k => jeKlasse(k).length ? `## Klasse ${k} — ${KLASSEN[k][0]}

${KLASSEN[k][1]}

${jeKlasse(k).map(eintrag).join('\n---\n\n')}` : '').filter(Boolean).join('\n')}
`

schreibe('docs/PRUEFBERICHT.md', text)
console.log(`docs/PRUEFBERICHT.md geschrieben — ${befunde.length} Feststellungen aus ${stand.length} Sonden`)
void WURZEL
