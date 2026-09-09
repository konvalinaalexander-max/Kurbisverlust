/**
 * Sonde 01 — Herkunft
 *
 * Jede Zahl auf einem Bildschirm hat einen Weg hinter sich: Rohzeile → Sicht →
 * gespeicherte Sicht → Abfrage der App → Anzeige. Diese Sonde geht den Weg
 * rückwärts und prüft die drei Stellen, an denen er stillschweigend reissen kann.
 *
 *   1. Die App fragt nach Spalten, die es nicht (mehr) gibt. Der Fehler zeigt
 *      sich erst zur Laufzeit, beim Anwender, und nur auf der einen Seite, die
 *      gerade niemand offen hat.
 *   2. Eine gespeicherte Sicht (`erg_…`) weicht von der Sicht ab, aus der sie
 *      gebaut wird. Dann rechnet das Programm richtig und zeigt trotzdem etwas
 *      anderes.
 *   3. Die App schreibt in Spalten, die es nicht gibt.
 */
import { befund, dateien, frage, kopie, lies, rechne, tue, zeileVon } from '../umgebung.mjs'

export const lang = false

/* ---------- Was die App von der Datenbank verlangt ------------------------ */

/**
 * Findet `supabase.from('tabelle')… .select('a, b, c')` und
 * `.insert({ a: …, b: … })` über mehrere Zeilen hinweg.
 *
 * Kein Parser, sondern ein Textleser mit Klammerzählung — der Quelltext ist
 * gleichförmig genug. Was nicht sicher zu lesen ist (`select(*)`, berechnete
 * Namen, eingebettete Beziehungen wie `profil(name)`), wird übersprungen und
 * gezählt, nicht geraten.
 */
export function verlangt(text, pfad) {
  const raus = []
  for (const m of text.matchAll(/\.from\('([a-z0-9_]+)'\)/g)) {
    const tabelle = m[1]
    const ab = kette(text, m.index + m[0].length)
    const zeile = zeileVon(text, m.index)
    const s = /^\s*\.select\(\s*'([^']*)'/m.exec(ab) ?? /\.select\(\s*'([^']*)'/.exec(ab)
    if (s && s[1].trim() !== '*') {
      for (const feld of s[1].split(',').map(f => f.trim()).filter(Boolean)) {
        if (/[()]/.test(feld)) continue                       // eingebettete Beziehung
        raus.push({ pfad, zeile, tabelle, spalte: feld.split(':').pop().trim(), art: 'liest' })
      }
    }
    for (const w of ['insert', 'update']) {
      const i = ab.indexOf(`.${w}(`)
      if (i < 0) continue
      const auf = ab.indexOf('{', i)
      if (auf < 0 || auf > i + w.length + 3) continue          // .insert(zeile) — Variable, nicht lesbar
      let tiefe = 0, j = auf
      for (; j < ab.length; j++) {
        if (ab[j] === '{') tiefe++
        else if (ab[j] === '}') { tiefe--; if (tiefe === 0) break }
      }
      const rumpf = ab.slice(auf + 1, j)
      for (const m2 of rumpf.matchAll(/(^|[,{])\s*([a-z][a-z0-9_]*)\s*:/g)) {
        const t2 = [...rumpf.slice(0, m2.index)]
          .reduce((a, c) => a + (c === '{' || c === '[' ? 1 : c === '}' || c === ']' ? -1 : 0), 0)
        if (t2 !== 0) continue                                 // nur Schlüssel auf oberster Ebene
        raus.push({ pfad, zeile, tabelle, spalte: m2[2], art: w === 'insert' ? 'schreibt' : 'ändert' })
      }
    }
  }
  return raus
}

/**
 * Die Aufrufkette ab einer Stelle: `.select(…).eq(…).order(…)` — und dort zu
 * Ende, wo kein Punkt mehr folgt. Ohne diese Grenze liest der Leser in die
 * nächste Anweisung hinein und schreibt Spalten der einen Tabelle der anderen zu.
 */
function kette(text, i) {
  const anfang = i
  while (i < text.length) {
    const rest = /^\s*(\.)/.exec(text.slice(i, i + 200))
    if (!rest) break
    i += rest[0].length
    while (i < text.length && /[A-Za-z0-9_]/.test(text[i])) i++
    while (i < text.length && /\s/.test(text[i])) i++
    if (text[i] !== '(') continue
    let tiefe = 0
    for (; i < text.length; i++) {
      const c = text[i]
      if (c === '(' || c === '[' || c === '{') tiefe++
      else if (c === ')' || c === ']' || c === '}') { tiefe--; if (tiefe === 0) { i++; break } }
      else if (c === "'" || c === '"' || c === '`') {          // Zeichenketten überspringen
        const q = c; i++
        while (i < text.length && text[i] !== q) i += text[i] === '\\' ? 2 : 1
      }
    }
  }
  return text.slice(anfang, i)
}

export async function laufen({ db }) {
  const raus = []
  const B = (o) => raus.push(befund({ sonde: '01_herkunft', kuerzel: 'HER', ...o }))

  /* 1a. Verlangt die App etwas, das es nicht gibt? */
  const vorhanden = new Map()
  for (const r of frage(db, `select c.relname as objekt, a.attname as spalte
                               from pg_attribute a
                               join pg_class c on c.oid = a.attrelid
                               join pg_namespace n on n.oid = c.relnamespace
                              where n.nspname = 'public' and a.attnum > 0 and not a.attisdropped
                                and c.relkind in ('r','v','m','p')`)) {
    if (!vorhanden.has(r.objekt)) vorhanden.set(r.objekt, new Set())
    vorhanden.get(r.objekt).add(r.spalte)
  }
  const fehlt = []
  for (const pfad of dateien('src')) {
    for (const v of verlangt(lies(pfad), pfad)) {
      const s = vorhanden.get(v.tabelle)
      if (!s) { fehlt.push({ ...v, grund: 'Tabelle oder Sicht fehlt' }); continue }
      if (!s.has(v.spalte)) fehlt.push({ ...v, grund: 'Spalte fehlt' })
    }
  }
  if (fehlt.length) {
    B({ klasse: 3, ort: { datei: fehlt[0].pfad, zeile: fehlt[0].zeile },
        titel: `Die App ${fehlt.length === 1 ? 'verlangt eine Spalte' : `verlangt ${fehlt.length} Spalten`}, die es in der Datenbank nicht gibt`,
        steht_da: fehlt.slice(0, 10).map(f => `${f.pfad}:${f.zeile} ${f.art} ${f.tabelle}.${f.spalte} (${f.grund})`).join('; '),
        muesste: 'Jede Spalte, die die App liest oder schreibt, existiert.',
        warum: 'PostgREST antwortet mit einem Fehler; die Seite bleibt leer oder das Speichern schlägt '
             + 'fehl. Der Übersetzer sieht davon nichts, weil die Namen Zeichenketten sind.',
        beleg: 'pruefwerk/sonden/01_herkunft.mjs → verlangt()',
        groesse: { wert: fehlt.length, einheit: 'Stellen', basis: 'src/** gegen das Schema' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* 1b. Weicht eine gespeicherte Sicht von ihrer Quelle ab? */
  rechne(db)
  const paare = frage(db, `
    select c.relname as gespeichert,
           regexp_replace(pg_get_viewdef(c.oid, true), '(?s).*\\sFROM\\s+([a-z0-9_]+).*', '\\1') as quelle
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'm' and c.relname like 'erg\\_%'
     order by 1`)
  const drift = []
  for (const p of paare) {
    if (!p.quelle || !p.quelle.startsWith('v_')) continue
    // to_jsonb statt einer Spaltenliste: `concat_ws` nimmt höchstens
    // 100 Argumente, und erg_charge hat mehr Spalten als das.
    const d = frage(db, `
      with a as (select md5(string_agg(z, chr(10) order by z)) as h from
                   (select to_jsonb(t)::text as z from ${p.gespeichert} t) s),
           b as (select md5(string_agg(z, chr(10) order by z)) as h from
                   (select to_jsonb(t)::text as z from ${p.quelle} t) s)
      select (select h from a) as gespeichert, (select h from b) as quelle`)[0]
    if (d.gespeichert !== d.quelle) drift.push(p)
  }
  if (drift.length) {
    B({ klasse: 3, ort: { sicht: drift.map(d => d.gespeichert).join(', ') },
        titel: 'Eine gespeicherte Sicht zeigt etwas anderes als die Sicht, aus der sie gebaut wird',
        steht_da: drift.map(d => `${d.gespeichert} ≠ ${d.quelle}`).join('; '),
        muesste: 'Unmittelbar nach `auswertung_aktualisieren()` sind beide gleich.',
        warum: 'Die App liest ausschliesslich die gespeicherten Sichten (damit sie nicht in einen '
             + 'Zeitablauf läuft). Weichen sie ab, rechnet die Datenbank richtig und die App zeigt es '
             + 'falsch — und der Unterschied ist nur zu sehen, wenn man beide nebeneinanderlegt.',
        beleg: 'pruefwerk/sonden/01_herkunft.mjs → 1b',
        groesse: { wert: drift.length, einheit: 'Sichten', basis: `${paare.length} gespeicherte Sichten` },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* 1c. Gespeicherte Sichten, die die Aktualisierung gar nicht anfasst */
  const leer = frage(db, `
    select c.relname as sicht
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'm' and not c.relispopulated
     order by 1`)
  if (leer.length) {
    B({ klasse: 3, ort: { sicht: leer.map(l => l.sicht).join(', ') },
        titel: 'Gespeicherte Sichten bleiben nach der Aktualisierung ungefüllt',
        steht_da: `${leer.length} von ${paare.length}: ${leer.map(l => l.sicht).join(', ')}`,
        muesste: '`auswertung_aktualisieren()` füllt jede gespeicherte Sicht.',
        warum: 'Eine ungefüllte materialisierte Sicht wirft beim Lesen einen Fehler. Die Seite, die '
             + 'sie braucht, bleibt leer — bis jemand sie öffnet, merkt es niemand.',
        beleg: 'pruefwerk/sonden/01_herkunft.mjs → 1c',
        groesse: { wert: leer.length, einheit: 'Sichten', basis: 'nach auswertung_aktualisieren()' },
        sicherheit: 'hoch', marke: 'Reparatur' })
  }

  /* 1d. Die Herkunftsmarke: „gemessen" heisst laut Überblick „aus einer
     vollständigen Liste — jede Palette im Erntejournal, jede Lieferung auf
     einem Lieferschein". Zwei Zahlen tragen diese Marke und enthalten
     Bestandteile, für die sie nicht gilt. */
  const h = frage(db, `
    select round(vorlauf_kg)::numeric as vorlauf, round(ausgang_kg)::numeric as ausgang,
           (select count(*) from charge_vorlauf)::int as n_vorlauf
      from v_saisonbilanz`)[0]
  const ueberblick = lies('src/pages/Ueberblick.tsx')
  const marke = /titel="Ausgeliefert"[\s\S]{0,240}?art="gemessen"/.test(ueberblick)
  if (h && Number(h.vorlauf) > 0 && marke) {
    B({ klasse: 3, ort: { datei: 'src/pages/Ueberblick.tsx', sicht: 'v_saisonbilanz', spalte: 'ausgang_kg' },
        titel: '„Ausgeliefert" trägt die Marke „gemessen" und enthält eine Schätzung',
        steht_da: `ausgang_kg = ${Number(h.ausgang)} kg mit der Marke „gemessen". Davon sind `
                + `${Number(h.vorlauf)} kg \`vorlauf_kg\` — die Angabe des Betriebs, was vor dem `
                + `Erfassungsbeginn schon draussen war (${Number(h.n_vorlauf)} Zeile(n) in `
                + `\`charge_vorlauf\`, mit Bemerkung, ohne Lieferschein). Das sind `
                + `${(100 * Number(h.vorlauf) / Number(h.ausgang)).toFixed(1)} % der Zahl.`,
        muesste: 'Entweder die Marke für diese Zahl anders wählen (gemessen + geschätzter Anteil), '
               + 'oder den Vorlauf aus der Zahl herausnehmen und daneben stellen. Der Untertitel nennt '
               + 'ihn bereits („… vor dem Erfassungsbeginn") — die Marke widerspricht dem Untertitel.',
        warum: 'Die Seite erklärt die Marke selbst: „gemessen heisst: aus einer vollständigen Liste — '
             + 'jede Palette im Erntejournal, jede Lieferung auf einem Lieferschein." Für den Vorlauf '
             + 'gilt das nicht; er ist eine Erinnerung. Solange beides dieselbe Marke trägt, ist die '
             + 'Marke keine Auskunft mehr, sondern Dekoration — und sie steht an vier Stellen des '
             + 'Überblicks.',
        beleg: 'pruefwerk/sonden/01_herkunft.mjs → 1d',
        groesse: { wert: Number(h.vorlauf), einheit: 'kg Schätzung in einer als gemessen ausgewiesenen Zahl',
                   basis: `${(100 * Number(h.vorlauf) / Number(h.ausgang)).toFixed(1)} % von „Ausgeliefert"` },
        sicherheit: 'hoch', marke: 'Reparatur', aufwand: 'klein',
        gegenrede: 'Der Untertitel nennt den Vorlauf ausdrücklich, wer genau liest, sieht ihn also. '
                 + 'Dagegen steht: Die Marke ist die Abkürzung für Leser, die nicht genau lesen — dafür '
                 + 'wurde sie eingeführt. Eine Abkürzung, die im Sonderfall das Gegenteil sagt, ist '
                 + 'schlechter als keine.' })
  }

  return raus
}

/**
 * Selbstprobe — zwei Stufen.
 *
 * Erst der Leser: Quelltext mit bekannten Verlangen, darunter zwei Formen, die
 * er nicht raten darf (`select('*')`, eingebettete Beziehungen).
 *
 * Dann der Abgleich: Auf einer Kopie wird eine gespeicherte Sicht absichtlich
 * anders gebaut als die Sicht, aus der sie stammt. Fällt das nicht auf, taugt
 * der Abgleich nichts.
 */
export async function selbstprobe({ db = 'demo' } = {}) {
  const probe = `
    supabase.from('palette').select('id, brutto_kg, kisten')
    supabase.from('lieferung').insert({ datum: d, kg: n, ziel: 'verkauf' })
    supabase.from('charge').select('*')
    supabase.from('auftrag_teilnehmer').select('profil_id, profil(name)')
  `
  const v = verlangt(probe, 'probe.ts')
  const hat = (t, s, a) => v.some(x => x.tabelle === t && x.spalte === s && x.art === a)
  const leserOk = hat('palette', 'brutto_kg', 'liest') && hat('lieferung', 'ziel', 'schreibt')
    && !v.some(x => x.spalte === '*')                 // select('*') wird nicht geraten
    && !v.some(x => x.spalte.includes('('))           // eingebettete Beziehungen auch nicht
    && v.filter(x => x.tabelle === 'palette').length === 3
    && v.filter(x => x.tabelle === 'lieferung').length === 3
  if (!leserOk) return false

  const k = kopie(db, 'pw_herkunft_probe')
  // Eine zusätzliche gespeicherte Sicht, die absichtlich nicht das zeigt, was
  // ihre Quelle zeigt. Nichts wird verworfen — der Abgleich muss sie finden.
  tue(k, `create materialized view erg_probe_abweichung as
            select * from v_saisonbilanz where eingang_kg < 0;`)
  const gefunden = await laufen({ db: k })
  return gefunden.some(b => b.titel.includes('etwas anderes'))
}
