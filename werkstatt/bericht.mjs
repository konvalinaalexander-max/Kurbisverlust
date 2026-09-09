#!/usr/bin/env node
/**
 * Aus `werkstatt/befunde/befunde.json` wird `docs/WERKSTATTBERICHT.md`.
 *
 *   node werkstatt/bericht.mjs
 *
 * Der Bericht ist für den Betrieb geschrieben, nicht für die Entwicklung: in
 * klarem Deutsch, jede Feststellung mit ihrer Grösse, jede mit einer
 * Gegenrede. Wer ihn liest, soll entscheiden können, ohne den Quelltext zu
 * öffnen.
 *
 * Er enthält ausdrücklich auch, **was geprüft und für richtig befunden**
 * wurde. Eine Liste, die nur Mängel nennt, sagt nichts darüber, wie weit
 * nachgesehen wurde — und ist damit als Entscheidungsgrundlage wertlos.
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { WURZEL, schreibe } from './umgebung.mjs'

const KLASSEN = {
  3: ['Bedeutung', 'Die Zahl steht da und meint etwas anderes, als der Leser denkt — oder sie ist falsch.'],
  2: ['Kette', 'Erfassung, Rechnung und Anzeige passen nicht sauber zusammen; heute trägt es, morgen vielleicht nicht.'],
  1: ['Technisch', 'Im Bestand nachgesehen und in Ordnung befunden, oder eine Kleinigkeit ohne Folge für eine Zahl.'],
}

const MARKEN = [
  ['Reparatur', 'Etwas ist falsch und lässt sich richtigstellen, ohne die App zu erweitern.'],
  ['Reduktion', 'Der Code wird kleiner, das Verhalten bleibt gleich — bewiesen, nicht behauptet.'],
  ['Frage an den Betrieb', 'Zwei Antworten sind beide vertretbar; entscheiden muss der Betrieb.'],
  ['Entscheidung des Betriebs', 'Es geht um den Ablauf in der Halle, nicht um den Code.'],
  ['kein Fehler', 'Nachgesehen, in Ordnung.'],
]

const daten = JSON.parse(readFileSync(join(WURZEL, 'werkstatt/befunde/befunde.json'), 'utf8'))
const { stand, befunde, messungen = [], saat, db } = daten

const ort = (o = {}) => [
  o.datei && `\`${o.datei}${o.zeile ? ':' + o.zeile : ''}\``,
  o.sicht && `\`${o.sicht}\``,
  o.funktion && `\`${o.funktion}()\``,
  o.spalte && `Spalte \`${o.spalte}\``,
  o.tabelle && `Tabelle \`${o.tabelle}\``,
].filter(Boolean).join(' · ') || '—'

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

function messungstabelle(m) {
  const kopf = `| ${m.spalten.join(' | ')} |`
  const trenn = `|${m.spalten.map(() => '---').join('|')}|`
  const zeilen = m.zeilen.map(z => `| ${m.spalten.map(s => String(z[s] ?? '—')).join(' | ')} |`)
  return `### ${m.titel}

${m.erklaerung}

${kopf}
${trenn}
${zeilen.join('\n')}
`
}

const jeKlasse = (k) => befunde.filter(b => b.klasse === k)
const jeMarke = (m) => befunde.filter(b => (b.marke ?? 'Reparatur') === m)
const jeWerkstatt = (w) => befunde.filter(b => (b.werkstatt ?? '').startsWith(w))

const WERKSTAETTEN = [
  ['Phase 0', 'Schärfe der vorhandenen Werkzeuge',
   'Sehen die Werkzeuge der letzten Runde überhaupt noch etwas?'],
  ['A', 'Rechenwerk', 'Ist das der richtige Schätzer, und ist er ehrlich über sich selbst?'],
  ['B', 'Fundament', 'Ist die Datenbank unter der Fachlogik gesund?'],
  ['C', 'Bauwerk', 'Ist der Code so gebaut, wie ein Programm dieser Grösse gebaut sein sollte?'],
  ['D', 'Nutzen', 'Löst dieses Programm die Probleme des Betriebs?'],
]

const text = `# Werkstattbericht — Runde M

*Erzeugt von \`werkstatt/bericht.mjs\` aus dem Lauf der vier Werkstätten. Nicht von Hand
ändern — die Fassung, die zählt, entsteht neu mit
\`node werkstatt/lauf.mjs && node werkstatt/bericht.mjs\`.
Datenbank: \`${db}\`, Saat: ${saat} (alles Zufällige hängt daran; zweimal laufen ergibt dasselbe).*

## Was hier steht

${befunde.length} Feststellungen und ${messungen.length} Messreihen aus ${stand.length} Werkzeugen
in vier Werkstätten. Jede Feststellung hat eine **Grösse** — ohne Grösse ist eine Feststellung
eine Meinung, und eine Liste von Meinungen nimmt niemand ernst. Jede hat eine **Gegenrede**:
das beste Argument dagegen, aufgeschrieben von dem, der die Feststellung gemacht hat.

Nicht jede Feststellung ist ein Fehler. ${jeMarke('kein Fehler').length} sind ausdrücklich
„geprüft und in Ordnung" — sie stehen hier, weil ein Bericht, der nur Mängel nennt, nicht sagt,
wie weit nachgesehen wurde.

| Werkstatt | Die Frage | Feststellungen |
|---|---|---|
${WERKSTAETTEN.map(([k, n, f]) => `| **${k} — ${n}** | ${f} | ${jeWerkstatt(k).length} |`).join('\n')}

| Klasse | Was das heisst | Anzahl |
|---|---|---|
${[3, 2, 1].map(k => `| ${k} — ${KLASSEN[k][0]} | ${KLASSEN[k][1]} | ${jeKlasse(k).length} |`).join('\n')}

| Marke | Was zu tun ist | Anzahl |
|---|---|---|
${MARKEN.map(([m, t]) => `| ${m} | ${t} | ${jeMarke(m).length} |`).join('\n')}

## Was geprüft wurde

| Werkstatt | Werkzeug | Feststellungen | Messreihen | Dauer | Selbstprobe |
|---|---|---|---|---|---|
${stand.map(s => `| ${s.werkstatt} | \`${s.werkzeug}\` | ${s.befunde} | ${s.messungen ?? 0} | ${s.sekunden} s | ${s.selbstprobe}${s.fehler ? ` — abgebrochen: ${s.fehler}` : ''} |`).join('\n')}

Die Spalte **Selbstprobe** ist die wichtigste der Tabelle. Jedes Werkzeug bekommt einen Fall
vorgesetzt, in dem es anschlagen *muss*. Steht dort „ok", hat es seinen eigenen eingebauten
Fehler gefunden; steht dort „STUMPF" oder „ohne", sagt auch sein leeres Ergebnis nichts.

${[3, 2, 1].map(k => jeKlasse(k).length ? `## Klasse ${k} — ${KLASSEN[k][0]}

${KLASSEN[k][1]}

${jeKlasse(k).map(eintrag).join('\n---\n\n')}` : '').filter(Boolean).join('\n')}
${messungen.length ? `\n## Messreihen

Zahlen, die für sich kein Mangel sind, aber die Grundlage der Feststellungen darüber —
und die Antwort auf die Frage, wie weit nachgesehen wurde.

${messungen.map(messungstabelle).join('\n---\n\n')}` : ''}
`

schreibe('docs/WERKSTATTBERICHT.md', text)
console.log(`docs/WERKSTATTBERICHT.md geschrieben — ${befunde.length} Feststellungen, `
          + `${messungen.length} Messreihen aus ${stand.length} Werkzeugen`)
