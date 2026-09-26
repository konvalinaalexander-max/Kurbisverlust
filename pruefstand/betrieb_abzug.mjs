#!/usr/bin/env node
/**
 * Der Betriebsabzug (Runde Y): was die Halle sagt und was die Auswertung
 * findet, als Text ins Repository — damit die nächste Runde am Programm
 * davon ausgeht, nicht von der Erinnerung.
 *
 * Der Betrieb: „wenn du das nächste Mal daran arbeitest, dass du gleich
 * diese Inputs aufgreifst … und dass du von den Fehlern selber lernst."
 *
 * Holt über die REST-Schnittstelle des Supabase-Projekts:
 *   - die Rückmeldungen (zur App und zur Ware) mit Arbeit und Transkript
 *   - die Auffälligkeiten (erg_plausibilitaet), gezählt und einzeln
 *   - den Stand der Modelle (Koeffizienten, Verderbsmodell, Datenqualität)
 * und schreibt docs/betrieb/*.md. Läuft täglich als GitHub-Workflow mit
 * den Secrets SUPABASE_URL und SUPABASE_SERVICE_KEY — ohne sie tut das
 * Skript nichts und sagt es. Die Audiodateien bleiben im Bucket; hier
 * steht ihr Transkript.
 *
 *   SUPABASE_URL=… SUPABASE_SERVICE_KEY=… node pruefstand/betrieb_abzug.mjs
 *
 * Runde Z — der Rückweg: Bevor gezogen wird, spielt der Abzug die
 * Kurzfassungen aus docs/betrieb/kurzfassungen.json in die Datenbank
 * (kurz, kurz_quelle = runde). Erst damit steht ein Kommentar zur Ware im
 * Dashboard — der Betrieb: „es soll erst im Dashboard erscheinen, nachdem
 * du es gelesen hast und verstanden hast." Was der Betriebsleiter selbst
 * gekürzt hat, bleibt (pruefstand/kurzfassung.mjs sagt, was gilt). Mit
 * NUR_EINSPIELEN=1 (der Push-Auslöser des Workflows) endet das Skript danach.
 */
import { writeFileSync, mkdirSync, existsSync, readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { eintraegePruefen, patchFuer } from './kurzfassung.mjs'

const HIER = dirname(fileURLToPath(import.meta.url))
const ZIEL = join(HIER, '..', 'docs', 'betrieb')
const url = (process.env.SUPABASE_URL ?? '').replace(/\/$/, '')
const key = process.env.SUPABASE_SERVICE_KEY ?? ''
if (!url || !key) {
  console.log('Kein Zugang gesetzt (SUPABASE_URL, SUPABASE_SERVICE_KEY) — nichts abgezogen.')
  process.exit(0)
}

async function rest(pfad) {
  const r = await fetch(`${url}/rest/v1/${pfad}`, { headers: { apikey: key, Authorization: `Bearer ${key}` } })
  if (!r.ok) throw new Error(`${pfad}: ${r.status} ${await r.text()}`)
  return r.json()
}
async function patch(pfad, koerper) {
  const r = await fetch(`${url}/rest/v1/${pfad}`, {
    method: 'PATCH', body: JSON.stringify(koerper),
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
  })
  if (!r.ok) throw new Error(`PATCH ${pfad}: ${r.status} ${await r.text()}`)
}

// ---- 0. Der Rückweg: Kurzfassungen einspielen --------------------------------
const kurzPfad = join(ZIEL, 'kurzfassungen.json')
if (existsSync(kurzPfad)) {
  const eintraege = eintraegePruefen(JSON.parse(readFileSync(kurzPfad, 'utf8')))
  let geschickt = 0, gleich = 0
  const jetzt = new Date().toISOString()
  for (const e of eintraege) {
    const [zeile] = await rest(`auftrag_rueckmeldung?select=*&id=eq.${e.id}`)
    const { patch: p, grund } = patchFuer(zeile ?? null, e, jetzt)
    if (grund) { console.log(`  · ${grund}`); continue }
    if (!p) { gleich++; continue }
    await patch(`auftrag_rueckmeldung?id=eq.${e.id}`, p)
    geschickt++
    console.log(`  ✓ Nr. ${e.id}: ${Object.entries(p).map(([k, v]) => `${k} = ${JSON.stringify(v)}`).join(', ')}`)
  }
  console.log(`Kurzfassungen: ${eintraege.length} Einträge, ${geschickt} eingespielt, ${gleich} standen schon so.`)
  if (process.env.NUR_EINSPIELEN) process.exit(0)
}
const heute = new Date().toISOString().slice(0, 10)
const zeit = ts => ts ? new Date(ts).toLocaleString('de-CH', { timeZone: 'Europe/Zurich', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'
const tag = ts => ts ? new Date(ts).toLocaleDateString('de-CH', { timeZone: 'Europe/Zurich', day: '2-digit', month: '2-digit', year: 'numeric' }) : '—'
const md = s => String(s ?? '').replace(/\|/g, '\\|').replace(/\n+/g, ' ')
const TAETIGKEIT = { 'sortieren': 'Sortieren', 'waschen_sortieren': 'Waschen + Sortieren', 'waschen': 'Waschen' }

const [einstellungen, stand, chargen, profile, auftraege, rueck, befunde, kv, ka, kn, modell, qual, bilanz] = await Promise.all([
  rest('einstellung?select=schluessel,wert&schluessel=in.(betriebsmodus,erfassung_scharf,verdunstung_rate_max_pro_tag,saison_aktuell)'),
  rest('auswertung_stand?select=*'),
  rest('charge?select=nr,sorte,schlag'),
  rest('profil?select=id,name'),
  rest('auftrag?select=id,weg,station,ist_fax,charge_nr,start_ts,ende_ts,status,abgebrochen_ts&order=start_ts.desc&limit=2000'),
  rest('auftrag_rueckmeldung?select=*&order=ts.desc&limit=1000'),
  rest('erg_plausibilitaet?select=*'),
  rest('erg_koeff_verdunstung?select=*'),
  rest('erg_koeff_ausschuss?select=*'),
  rest('erg_koeff_nebenkanal?select=*'),
  rest('erg_modell?select=*'),
  rest('erg_datenqualitaet?select=*'),
  rest('erg_bilanz?select=*'),
])
const modus = einstellungen.find(e => e.schluessel === 'betriebsmodus')?.wert
const chargeText = nr => { const c = chargen.find(x => x.nr === nr); return c ? `${nr} — ${c.schlag} · ${c.sorte}` : String(nr ?? '—') }
const arbeitText = id => {
  const a = auftraege.find(x => x.id === id); if (!a) return `Arbeit ${id}`
  const ta = a.ist_fax ? 'Fax' : (TAETIGKEIT[a.station] ?? a.station)
  const st = a.abgebrochen_ts ? 'abgebrochen' : a.status === 'offen' ? 'läuft' : 'fertig'
  return `${ta} · ${zeit(a.start_ts)} · ${st} · Charge ${chargeText(a.charge_nr)} · Arbeit ${a.id}`
}
const name = id => profile.find(p => p.id === id)?.name ?? 'jemand'
const kopf = titel => `# ${titel}\n\n_Abzug vom ${heute}${modus === 'beispiel' ? ' — **Beispieldaten**, nicht der Betrieb' : ''}. Von \`pruefstand/betrieb_abzug.mjs\` geschrieben; nicht von Hand ändern._\n\n`

// ---- 1. Rückmeldungen -------------------------------------------------------
let r = kopf('Rückmeldungen aus der Halle')
r += 'Was die Person am Ende einer Arbeit gesagt hat — geschrieben, oder mitgeschrieben vom Handy (Transkript, ungeprüft = so wie die Spracherkennung es verstand). Die Aufnahmen liegen im Bucket `rueckmeldungen` des Projekts; hier steht, was sich lesen lässt.\n\n'
r += '**Zur Ware gilt seit 0094:** Ein Kommentar steht erst im Dashboard, wenn jemand ihn gelesen, verstanden und gekürzt hat („Hagelschaden"). Kürzen heisst: ein Eintrag je Nr. in `docs/betrieb/kurzfassungen.json` (der Abzug spielt ihn ein — täglich, und sofort beim Push der Datei), oder der Betriebsleiter tut es unter Betrieb → Arbeiten. Was der Betriebsleiter gekürzt hat, bleibt. Nur Aufnahme, kein Transkript: das kann hier niemand hören — anhören und kürzen kann nur der Betriebsleiter.\n\n'
const offen = rueck.filter(x => x.art === 'ware' && !x.kurz)
if (offen.length) r += `**Noch zu kürzen: ${offen.length}** — Nr. ${offen.map(x => x.id).join(', ')}.\n\n`
for (const art of ['app', 'ware']) {
  const liste = rueck.filter(x => (x.art ?? 'app') === art)
  r += `## ${art === 'app' ? 'Zur App — für die nächste Runde' : 'Zur Ware — für den Betriebsleiter'} (${liste.length})\n\n`
  if (!liste.length) { r += '_keine_\n\n'; continue }
  for (const x of liste) {
    const t = (x.text ?? '').trim()
    const tr = (x.transkript ?? '').trim()
    r += `- **Nr. ${x.id}** · ${tag(x.ts)} · ${arbeitText(x.auftrag_id)} · ${name(x.erfasser)}\n`
    if (art === 'ware') {
      if (x.kurz) r += `  - **gekürzt** (${x.kurz_quelle === 'betriebsleiter' ? 'Betriebsleiter' : 'Runde'}, ${tag(x.kurz_ts)}): „${md(x.kurz)}"${x.kurz_charge_nr ? ` — zugeordnet zu Charge ${chargeText(x.kurz_charge_nr)}` : ''}\n`
      else if (!t && !tr && x.audio_ref) r += '  - **nur Aufnahme, kein Transkript** — steht noch nicht im Dashboard; Betriebsleiter: anhören und unter Betrieb → Arbeiten kürzen\n'
      else r += '  - **noch nicht gekürzt** — steht noch nicht im Dashboard\n'
    }
    if (t) r += `  - „${md(t)}"\n`
    if (tr) r += `  - mitgeschrieben${x.transkript_quelle === 'hand' ? ' (geprüft)' : ' (ungeprüft)'}: „${md(tr)}"\n`
    if (x.audio_ref) r += `  - Aufnahme ${x.audio_sekunden != null ? `${Math.floor(x.audio_sekunden / 60)}:${String(x.audio_sekunden % 60).padStart(2, '0')} ` : ''}\`${x.audio_ref}\`${!tr ? ' — **ohne Transkript**' : ''}\n`
  }
  r += '\n'
}

// ---- 2. Auffälligkeiten ------------------------------------------------------
let b = kopf('Auffälligkeiten der Messungen')
b += 'Was die Auswertung nicht in die Rechnung nimmt, weil es nicht zu seinem Nenner passt. Für die nächste Runde: Wo entsteht das im Ablauf oder in der Maske? Was ist ein Datenfehler, der dem Betrieb gehört? Was könnte die App besser abfangen?\n\n'
const jeArt = new Map()
for (const x of befunde) jeArt.set(x.art, (jeArt.get(x.art) ?? 0) + 1)
b += `## Nach Art (${befunde.length})\n\n| Art | Anzahl |\n|---|---|\n`
for (const [art, n] of [...jeArt.entries()].sort((p, q) => q[1] - p[1])) b += `| ${md(art)} | ${n} |\n`
b += '\n## Einzeln\n\n'
for (const x of [...befunde].sort((p, q) => String(q.start_ts ?? '').localeCompare(String(p.start_ts ?? '')))) {
  b += `- **${md(x.art)}** · Charge ${chargeText(x.charge_nr)}${x.auftrag_id ? ` · ${arbeitText(x.auftrag_id)}` : ''}\n  - ${md(x.befund)}\n  - _${md(x.rat)}_\n`
}

// ---- 3. Modellstand ----------------------------------------------------------
const tabelle = zeilen => {
  if (!zeilen.length) return '_leer_\n\n'
  const spalten = Object.keys(zeilen[0])
  let t = `| ${spalten.join(' | ')} |\n|${spalten.map(() => '---').join('|')}|\n`
  for (const z of zeilen) t += `| ${spalten.map(k => md(typeof z[k] === 'number' ? Math.round(z[k] * 10000) / 10000 : z[k])).join(' | ')} |\n`
  return t + '\n'
}
let m = kopf('Stand der Modelle')
m += `Gerechnet: ${zeit(stand[0]?.berechnet_ts)} · Einstellungen: ${einstellungen.map(e => `${e.schluessel} = ${JSON.stringify(e.wert)}`).join(' · ')}\n\n`
m += 'Für die nächste Runde: Passen die Zahlen zu dem, was die Saison zeigen sollte (docs/SAISONBEGLEITUNG.md)? Wo steht ein Koeffizient auf „Wiegungen aller Sorten", weil die eigenen fehlen? Wo ist ein Band leer, wo ist die Basis dünn?\n\n'
m += '## Verdunstung je Sorte (erg_koeff_verdunstung)\n\n' + tabelle(kv)
m += '## Zu klein / zu gross je Sorte (erg_koeff_ausschuss)\n\n' + tabelle(ka)
m += '## Anderer Kanal je Sorte (erg_koeff_nebenkanal)\n\n' + tabelle(kn)
m += '## Verderbsmodell (erg_modell)\n\n' + tabelle(modell)
m += '## Datenqualität (erg_datenqualitaet)\n\n' + tabelle(qual)
m += '## Bilanz (erg_bilanz)\n\n' + tabelle(bilanz)

// ---- 4. Verlauf — eine Zeile je Abzug -----------------------------------------
mkdirSync(ZIEL, { recursive: true })
const verlaufPfad = join(ZIEL, 'VERLAUF.md')
let v = existsSync(verlaufPfad) ? readFileSync(verlaufPfad, 'utf8') : '# Verlauf der Abzüge\n\nEine Zeile je Abzug — damit man sieht, ob die Auffälligkeiten weniger werden und die Rückmeldungen ankommen.\n\n| Tag | Rückmeldungen App | Rückmeldungen Ware | Auffälligkeiten | davon die häufigste |\n|---|---|---|---|---|\n'
const haeufigste = [...jeArt.entries()].sort((p, q) => q[1] - p[1])[0]
const zeile = `| ${heute} | ${rueck.filter(x => (x.art ?? 'app') === 'app').length} | ${rueck.filter(x => x.art === 'ware').length} (${offen.length} zu kürzen) | ${befunde.length} | ${haeufigste ? `${md(haeufigste[0])} (${haeufigste[1]})` : '—'} |\n`
if (!v.includes(`| ${heute} |`)) v += zeile
else v = v.replace(new RegExp(`\\| ${heute} \\|[^\\n]*\\n`), zeile)

writeFileSync(join(ZIEL, 'RUECKMELDUNGEN.md'), r)
writeFileSync(join(ZIEL, 'AUFFAELLIGKEITEN.md'), b)
writeFileSync(join(ZIEL, 'MODELLSTAND.md'), m)
writeFileSync(verlaufPfad, v)
console.log(`Abzug ${heute}: ${rueck.length} Rückmeldungen, ${befunde.length} Auffälligkeiten → docs/betrieb/`)
