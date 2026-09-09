/**
 * Was alle vier Werkstätten brauchen.
 *
 * DIE WERKSTÄTTEN UND DAS PRÜFWERK
 *
 * Das Prüfwerk (Runde L, `pruefwerk/`) fragt: *bedeutet diese Zahl, was
 * dasteht?* Die Werkstätten (Runde M) fragen vier andere Fragen:
 *
 *   A Rechenwerk — ist das der richtige Schätzer, und ist er ehrlich über
 *                  sich selbst?
 *   B Fundament  — ist die Datenbank unter der Fachlogik gesund?
 *   C Bauwerk    — ist der Code so gebaut, wie ein Programm dieser Grösse
 *                  gebaut sein sollte?
 *   D Nutzen     — löst dieses Programm die Probleme des Betriebs?
 *
 * Das Handwerkszeug ist dasselbe: eine Datenbank ansprechen, Quelltext lesen,
 * Befunde formen. Es steht deshalb **nicht ein zweites Mal hier**, sondern
 * wird aus `pruefwerk/umgebung.mjs` durchgereicht. Eine Runde, die den Code
 * kleiner machen soll, darf nicht mit dreihundert kopierten Zeilen anfangen.
 *
 * Neu ist nur, was die vier Fragen zusätzlich brauchen:
 *   - gesäter Zufall (Werkstatt A rechnet Tausende erfundener Saisons durch,
 *     und zweimal laufen muss dasselbe ergeben)
 *   - Messungen (Werkstatt C und D erzeugen Tabellen gemessener Werte, die
 *     keine Mängel sind — der Bericht braucht beides)
 *   - Zeitmessung und Ausführungspläne (Werkstatt B)
 *   - Quelltext über alle Dateiarten, nicht nur .ts/.tsx (Werkstatt C)
 *
 * Wie das Prüfwerk ist auch die Werkstatt **nicht Teil der App**: kein Import
 * aus `src/`, kein Eintrag im Build, keine neue Abhängigkeit.
 */
import { execFileSync } from 'node:child_process'
import { readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

export {
  HIER as PRUEFWERK, WURZEL, url,
  frage, wert, tue, spiele,
  datenbank, frischesSchema, rechne, kopie,
  lies, dateien, zeileVon, schreibe,
} from '../pruefwerk/umgebung.mjs'

import { WURZEL, url, frage, tue, lies } from '../pruefwerk/umgebung.mjs'

/**
 * Eine Wegwerfkopie wieder loswerden.
 *
 * `tue()` stellt jeder Anweisung ein `set client_min_messages` voran; damit
 * werden zwei Anweisungen daraus, `psql` fasst sie in eine Transaktion, und
 * `drop database` darf in keiner Transaktion stehen. Deshalb hier der direkte
 * Weg — und `if exists`, damit ein zweiter Aufruf nichts bricht.
 */
export function wegwerfen(name) {
  execFileSync('psql', [url('postgres'), '-qX', '-c', `drop database if exists ${name}`],
    { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'] })
}

/* ---------- Befunde und Messungen ---------------------------------------- */

let laufendeNummer = new Map()

/**
 * Ein Befund: etwas stimmt nicht, oder etwas wurde geprüft und stimmt.
 *
 * `groesse` ist Pflicht — ohne Grösse ist es eine Meinung. `gegenrede` ist
 * Pflicht, sobald `marke` nicht „kein Fehler" ist: Wer eine Feststellung
 * macht, schreibt das beste Argument dagegen gleich dazu, sonst wird der
 * Bericht eine Sammlung von Fehlalarmen.
 */
export function befund({ werkstatt, kuerzel, klasse, ort, titel, steht_da, muesste,
                         warum, beleg, groesse, sicherheit = 'mittel', gegenrede,
                         marke = 'Reparatur', aufwand = 'klein' }) {
  if (!groesse || groesse.wert === undefined || !groesse.einheit)
    throw new Error(`Befund "${titel}" ohne Grösse — das ist eine Meinung, kein Befund.`)
  if (marke !== 'kein Fehler' && !gegenrede)
    throw new Error(`Befund "${titel}" ohne Gegenrede — erst gegenlesen, dann melden.`)
  const n = (laufendeNummer.get(kuerzel) ?? 0) + 1
  laufendeNummer.set(kuerzel, n)
  return {
    id: `${kuerzel}-${String(n).padStart(3, '0')}`,
    werkstatt, klasse, ort, titel, steht_da, muesste, warum, beleg,
    groesse, sicherheit, gegenrede, marke, aufwand, stand: 'offen',
  }
}

export function nummernZuruecksetzen() { laufendeNummer = new Map() }

/**
 * Eine Messung: eine Tabelle gemessener Werte, die für sich kein Mangel ist.
 *
 * Werkstatt C misst 60 Dateien, Werkstatt D 2600 Zahlen — das gehört in den
 * Bericht, aber nicht in die Mängelliste. Getrennt zu führen ist der
 * Unterschied zwischen einem Bericht, den man lesen kann, und einer Halde.
 */
export function messung({ werkstatt, titel, einheit, zeilen, spalten, erklaerung }) {
  return { art: 'messung', werkstatt, titel, einheit, spalten, zeilen, erklaerung }
}

/* ---------- Gesäter Zufall ------------------------------------------------ */

/**
 * Ein Zufallsgenerator mit Saat. `Math.random()` wäre hier ein Fehler: Eine
 * Werkstatt, die zweimal läuft und zweimal etwas anderes findet, taugt nicht
 * als Beleg. Mulberry32 — dreissig Zeilen, keine Abhängigkeit, gut genug für
 * Simulationen dieser Art.
 */
export function zufall(saat = 20260909) {
  let a = saat >>> 0
  const naechste = () => {
    a = (a + 0x6D2B79F5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  return {
    /** Gleichverteilt in [0, 1). */
    zahl: naechste,
    /** Gleichverteilt in [von, bis). */
    zwischen: (von, bis) => von + naechste() * (bis - von),
    /** Ganzzahl in [von, bis]. */
    ganz: (von, bis) => von + Math.floor(naechste() * (bis - von + 1)),
    /** Standardnormalverteilt (Box-Muller, beide Zahlen genutzt wäre schneller,
     *  aber die Einfachheit ist hier mehr wert als die halbe Ziehung). */
    normal: (mittel = 0, streuung = 1) => {
      const u = Math.max(naechste(), 1e-12), v = naechste()
      return mittel + streuung * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v)
    },
    /** Lognormal mit gegebenem Median und Streuung im Log-Raum. */
    lognormal: (median, sigma) => median * Math.exp(Math.sqrt(-2 * Math.log(Math.max(naechste(), 1e-12)))
      * Math.cos(2 * Math.PI * naechste()) * sigma),
    /** Ein Element aus einer Liste. */
    waehle: (liste) => liste[Math.floor(naechste() * liste.length)],
    /** Eine Liste in zufälliger Reihenfolge (Fisher-Yates). */
    mische: (liste) => {
      const l = [...liste]
      for (let i = l.length - 1; i > 0; i--) {
        const j = Math.floor(naechste() * (i + 1))
        ;[l[i], l[j]] = [l[j], l[i]]
      }
      return l
    },
  }
}

/* ---------- Statistik, die mehrere Werkstätten brauchen ------------------- */

export const mittel = (xs) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null

export function streuung(xs) {
  if (xs.length < 2) return null
  const m = mittel(xs)
  return Math.sqrt(xs.reduce((a, x) => a + (x - m) ** 2, 0) / (xs.length - 1))
}

export function quantil(xs, p) {
  if (!xs.length) return null
  const s = [...xs].sort((a, b) => a - b)
  const i = (s.length - 1) * p
  const u = Math.floor(i), o = Math.ceil(i)
  return u === o ? s[u] : s[u] + (i - u) * (s[o] - s[u])
}

/**
 * Verzerrung und Überdeckung eines Schätzers — die zwei Zahlen, an denen
 * Werkstatt A alles misst.
 *
 *   Verzerrung  — liegt der Schätzer systematisch daneben? In Prozent des
 *                 wahren Werts, damit Ströme verschiedener Grösse vergleichbar
 *                 sind.
 *   Überdeckung — enthält das ausgewiesene 95-%-Band den wahren Wert wirklich
 *                 in 95 % der Fälle? Das ist der schärfere Test: Ein Band, das
 *                 95 % heisst und in 70 % trifft, ist schlimmer als keines,
 *                 weil es Sicherheit vortäuscht.
 */
export function guete(laeufe) {
  const gueltig = laeufe.filter(l => l.geschaetzt !== null && l.geschaetzt !== undefined
                                  && Number.isFinite(l.geschaetzt) && l.wahr)
  if (!gueltig.length) return { n: 0, verzerrung_prozent: null, ueberdeckung: null, streuung_prozent: null }
  const fehler = gueltig.map(l => (l.geschaetzt - l.wahr) / l.wahr)
  const mitBand = gueltig.filter(l => l.unten !== null && l.unten !== undefined
                                   && l.oben !== null && l.oben !== undefined)
  return {
    n: gueltig.length,
    verzerrung_prozent: Number((100 * mittel(fehler)).toFixed(2)),
    streuung_prozent: fehler.length > 1 ? Number((100 * streuung(fehler)).toFixed(2)) : null,
    n_mit_band: mitBand.length,
    ueberdeckung: mitBand.length
      ? Number((mitBand.filter(l => l.unten <= l.wahr && l.wahr <= l.oben).length / mitBand.length).toFixed(3))
      : null,
    n_verworfen: laeufe.length - gueltig.length,
  }
}

/* ---------- Zeit und Ausführungspläne (Werkstatt B) ----------------------- */

/** Wanduhrzeit in Millisekunden. */
export function zeit(fn) {
  const t0 = process.hrtime.bigint()
  const ergebnis = fn()
  return { ms: Number(process.hrtime.bigint() - t0) / 1e6, ergebnis }
}

/**
 * Der Ausführungsplan einer Abfrage, mit den Auffälligkeiten schon
 * herausgezogen: sequenzielle Scans auf grossen Tabellen, Sortierungen, die
 * auf die Platte auslagern, und Fehlschätzungen des Planers.
 */
export function erklaere(db, sql) {
  const roh = execFileSync('psql', [url(db), '-qtAX', '-v', 'ON_ERROR_STOP=1', '-c',
    `explain (analyze, buffers, format json) ${sql}`],
    { encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 })
  const plan = JSON.parse(roh)[0]
  const knoten = []
  const gehe = (k, tiefe = 0) => {
    knoten.push({ tiefe, typ: k['Node Type'], tabelle: k['Relation Name'] ?? null,
                  zeilen_geschaetzt: k['Plan Rows'], zeilen_wirklich: k['Actual Rows'],
                  ms: k['Actual Total Time'], platte: k['Sort Space Type'] === 'Disk',
                  gelesen: (k['Shared Read Blocks'] ?? 0) })
    for (const kind of k.Plans ?? []) gehe(kind, tiefe + 1)
  }
  gehe(plan.Plan)
  const auffaellig = knoten.filter(k =>
    (k.typ === 'Seq Scan' && k.zeilen_wirklich > 5000) ||
    k.platte ||
    (k.zeilen_geschaetzt > 0 && k.zeilen_wirklich > 0 &&
      Math.max(k.zeilen_geschaetzt / k.zeilen_wirklich, k.zeilen_wirklich / k.zeilen_geschaetzt) > 10))
  return { ms: plan['Execution Time'], planungs_ms: plan['Planning Time'], knoten, auffaellig }
}

/* ---------- Quelltext, alle Arten (Werkstatt C) --------------------------- */

/**
 * Alle Dateien eines Verzeichnisses, gleich welcher Endung, mit Grösse.
 * `dateien()` aus dem Prüfwerk kann nur .ts/.tsx — Werkstatt C misst auch
 * SQL, CSS, HTML, Shell und die Werkzeuge selbst.
 */
export function alleDateien(verzeichnis, { muster = /.*/, ausser = /node_modules|\.git|dist|befunde/ } = {}) {
  const raus = []
  const gehe = (d) => {
    let eintraege
    try { eintraege = readdirSync(join(WURZEL, d), { withFileTypes: true }) } catch { return }
    for (const e of eintraege) {
      const p = `${d}/${e.name}`
      if (ausser.test(p)) continue
      if (e.isDirectory()) gehe(p)
      else if (muster.test(e.name)) {
        const s = statSync(join(WURZEL, p))
        raus.push({ pfad: p, bytes: s.size })
      }
    }
  }
  gehe(verzeichnis)
  return raus.sort((a, b) => a.pfad.localeCompare(b.pfad))
}

/** Zeilen einer Datei, ohne die Datei zweimal zu lesen. */
export function zeilen(pfad) { return lies(pfad).split('\n') }

/* ---------- Katalog: was in der Datenbank steht --------------------------- */

export const KATALOG = {
  sichten: (db) => frage(db, `
    select c.relname as name, c.relkind as art, pg_get_viewdef(c.oid, true) as text,
           obj_description(c.oid, 'pg_class') as beschreibung
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('v', 'm') order by 1`),

  funktionen: (db) => frage(db, `
    select p.proname as name, pg_get_functiondef(p.oid) as text,
           p.prosecdef as security_definer, obj_description(p.oid, 'pg_proc') as beschreibung
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f' order by 1`),

  tabellen: (db) => frage(db, `
    select c.relname as name, c.relrowsecurity as rls, c.reltuples::bigint as zeilen_geschaetzt,
           (select count(*) from pg_attribute a
             where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as spalten
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' order by 1`),

  indexe: (db) => frage(db, `
    select i.relname as name, t.relname as tabelle, pg_get_indexdef(i.oid) as text,
           pg_relation_size(i.oid) as bytes
      from pg_class i join pg_index x on x.indexrelid = i.oid
      join pg_class t on t.oid = x.indrelid
      join pg_namespace n on n.oid = i.relnamespace
     where n.nspname = 'public' order by 2, 1`),

  spalten: (db) => frage(db, `
    select c.relname as objekt, c.relkind as art, a.attname as spalte,
           format_type(a.atttypid, a.atttypmod) as typ, a.attnotnull as pflicht,
           (d.adbin is not null) as vorgabe
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
      left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
     where n.nspname = 'public' and c.relkind in ('r', 'v', 'm')
       and a.attnum > 0 and not a.attisdropped
     order by 1, a.attnum`),

  bedingungen: (db) => frage(db, `
    select conrelid::regclass::text as tabelle, conname as name, contype as art,
           convalidated as geprueft, pg_get_constraintdef(oid) as text
      from pg_constraint where connamespace = 'public'::regnamespace order by 1, 2`),

  regeln: (db) => frage(db, `
    select tablename as tabelle, policyname as name, cmd as fuer, roles::text as rollen,
           qual as bedingung, with_check as beim_schreiben
      from pg_policies where schemaname = 'public' order by 1, 2`),

  ausloeser: (db) => frage(db, `
    select c.relname as tabelle, t.tgname as name, pg_get_triggerdef(t.oid) as text
      from pg_trigger t join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and not t.tgisinternal order by 1, 2`),
}

/**
 * Wer liest was: der Abhängigkeitsgraph der Datenbank, aus `pg_depend`.
 * Liefert je Objekt die Liste derer, die darauf aufbauen.
 */
export function leser(db) {
  const kanten = frage(db, `
    select distinct q.relname as quelle, z.relname as ziel
      from pg_depend d
      join pg_rewrite r on r.oid = d.objid and d.classid = 'pg_rewrite'::regclass
      join pg_class z on z.oid = r.ev_class
      join pg_class q on q.oid = d.refobjid
      join pg_namespace nq on nq.oid = q.relnamespace
      join pg_namespace nz on nz.oid = z.relnamespace
     where nq.nspname = 'public' and nz.nspname = 'public' and q.relname <> z.relname`)
  const karte = new Map()
  for (const k of kanten) {
    if (!karte.has(k.quelle)) karte.set(k.quelle, [])
    karte.get(k.quelle).push(k.ziel)
  }
  return karte
}

/** Setzt `heute()` auf ein festes Datum — sonst hängt jede Prüfung am Kalender. */
export function heuteSetzen(db, datum) {
  tue(db, `insert into einstellung (schluessel, wert) values ('heute_test', to_jsonb('${datum}'::text))
           on conflict (schluessel) do update set wert = excluded.wert`)
}
