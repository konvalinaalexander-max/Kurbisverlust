/**
 * Verdichtet die Migrationen zu supabase/setup.sql.
 *
 * WARUM ES DAS GIBT
 *
 * setup.sql war die blosse Aneinanderreihung aller Migrationen — 1,14 MB. Der
 * Supabase-SQL-Editor nimmt das nicht an: Er schickt die Datei als einen
 * Anfragekörper, und der ist bei 1 MB zu Ende. Die Antwort ist "Query is too
 * large to be run via the SQL Editor" — und damit war der einzige Weg
 * versperrt, den der Betrieb hat: markieren, einfügen, Run.
 *
 * Die Grösse kommt nicht von der Datenbank, sondern von ihrer Geschichte.
 * v_saisonbilanz ist über 63 Migrationen neunmal neu geschrieben worden; acht
 * dieser Fassungen standen in setup.sql, wurden beim Einspielen angelegt und
 * Sekunden später überschrieben. Gemessen waren 54 % der Datei solche
 * überholten Fassungen — und der Anteil wächst mit jeder Runde weiter, denn
 * fast jede Migration schreibt Formeln neu.
 *
 * DIE TEILUNG
 *
 * Zwei Dinge stehen in den Migrationen nebeneinander, die sich ganz
 * verschieden verhalten:
 *
 *   Tabellen, Spalten, Bedingungen, Nachträge an den Daten. Das ist eine
 *   Geschichte. Jeder Schritt zählt, keiner darf fehlen: Eine Datenbank, die
 *   seit dem Frühjahr läuft, wird genau durch diese Schritte auf den heutigen
 *   Stand gebracht. Solche Anweisungen bleiben hier vollständig und in ihrer
 *   Reihenfolge stehen — Teil A.
 *
 *   Ansichten, gespeicherte Ansichten, die Funktionen, die auf ihnen rechnen.
 *   Das ist keine Geschichte, sondern ein Zustand: Es zählt nur, wie die
 *   Formel heute lautet. Von jeder bleibt die letzte Fassung, einmal, am Ende
 *   der Datei — Teil B.
 *
 * Teil B braucht eine Reihenfolge, denn eine Ansicht steht auf der anderen.
 * Die wird hier ausgerechnet (topologisch sortiert), nicht geraten. Zuerst
 * wird das alte Rechenwerk weggeräumt — in umgekehrter Reihenfolge, damit
 * nichts unter einem anderen wegbricht —, dann neu gebaut.
 *
 * WAS SICH FÜR DEN NUTZER ÄNDERT
 *
 * Nichts. Dieselbe eine Datei, dieselben vier Handgriffe, dasselbe Ergebnis:
 * eine leere Datenbank wird eingerichtet, eine bestehende aktualisiert, die
 * Daten bleiben stehen. Nur ist die Datei nicht mehr zu gross.
 *
 * WARUM DAS SICHER IST
 *
 * Nicht, weil es plausibel klingt. supabase/test/run.sh baut eine Datenbank
 * aus den einzelnen Migrationen und eine aus setup.sql und vergleicht die
 * Fingerabdrücke: jede Spalte, jede Ansicht, jede gespeicherte Ansicht, jede
 * Funktion, jeder Index, jede Zugriffsregel, jeder Auslöser, jede Bedingung,
 * jedes Recht, jede Beschreibung. Weicht eine Zeile ab, bricht der Lauf ab
 * und nennt sie. Dazu kommt die Aktualisierung von einem alten Stand mit
 * echten Daten (Stufe 3b) und der zweite Durchlauf (Stufe 3).
 *
 * Zwei Zusicherungen prüft der Verdichter selbst und bricht sonst ab:
 *   - keine Anweisung in Teil A benutzt etwas, das nach Teil B gewandert ist
 *   - die Reihenfolge in Teil B ist kreisfrei
 */

const RUMPF = '(?:[a-z_][a-z0-9_]*\\.)?[a-z_][a-z0-9_]*'

/**
 * Zerlegt SQL in Anweisungen auf oberster Ebene. Beachtet Zeichenketten,
 * Bezeichner in Anführungszeichen, Zeilen- und Blockkommentare und die
 * Dollar-Anführung ($$, $tag$), in der die Funktionsrümpfe stehen — ein
 * Semikolon darin trennt nichts.
 *
 * Der Text einer Anweisung beginnt hinter dem vorigen Semikolon. Die
 * erklärenden Kommentare davor gehören also dazu und wandern mit ihr.
 */
export function anweisungen(text) {
  const raus = []
  let i = 0, start = 0
  const n = text.length
  while (i < n) {
    const c = text[i]
    if (c === '-' && text[i + 1] === '-') { const e = text.indexOf('\n', i); i = e < 0 ? n : e + 1; continue }
    if (c === '/' && text[i + 1] === '*') {
      let tiefe = 1; i += 2
      while (i < n && tiefe) {
        if (text[i] === '/' && text[i + 1] === '*') { tiefe++; i += 2 }
        else if (text[i] === '*' && text[i + 1] === '/') { tiefe--; i += 2 }
        else i++
      }
      continue
    }
    if (c === "'") { i++; while (i < n) { if (text[i] === "'" && text[i + 1] === "'") i += 2; else if (text[i] === "'") { i++; break } else i++ } continue }
    if (c === '"') { i++; while (i < n) { if (text[i] === '"' && text[i + 1] === '"') i += 2; else if (text[i] === '"') { i++; break } else i++ } continue }
    if (c === '$') {
      const m = /^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/.exec(text.slice(i, i + 64))
      if (m) { const marke = m[0]; const e = text.indexOf(marke, i + marke.length); i = e < 0 ? n : e + marke.length; continue }
    }
    if (c === ';') { raus.push(text.slice(start, i + 1)); i++; start = i; continue }
    i++
  }
  const rest = text.slice(start)
  if (rest.trim()) raus.push(rest)
  return raus
}

/** Der Kern einer Anweisung: ohne Kommentare, klein geschrieben, ohne Rand. */
export function kern(s) {
  return s.replace(/--[^\n]*(?:\n|$)/g, '\n').replace(/\/\*[\s\S]*?\*\//g, ' ').trim().toLowerCase()
}

/**
 * Nur der Code: zusätzlich ohne Zeichenketten. Wer wissen will, ob eine
 * Anweisung eine Ansicht *benutzt*, darf sich nicht davon täuschen lassen,
 * dass ihr Name in einem Text vorkommt — in einer Beschreibung etwa, oder in
 * einer Ausschlussliste wie proname not in ('schimmelanteil', …).
 */
function nurCode(s) {
  return kern(s).replace(/'(?:[^']|'')*'/g, "''")
}

/**
 * Was eine Anweisung braucht, wenn sie an ihrer Stelle ausgeführt wird.
 *
 * Der Rumpf einer PL/pgSQL-Funktion zählt nicht dazu: Postgres liest ihn beim
 * Anlegen nicht, sondern erst beim Aufruf. auswertung_aktualisieren() darf
 * also mv_kaskade nennen, lange bevor es mv_kaskade gibt — gerufen wird sie
 * ganz am Ende. Bei einer Funktion in SQL und in einem do-Block ist es anders:
 * die werden sofort aufgelöst beziehungsweise sofort ausgeführt.
 */
function braucht_jetzt(s) {
  const t = nurCode(s)
  if (/^create\s+(?:or\s+replace\s+)?function\b/.test(t) && /language\s+plpgsql\b/.test(t))
    return t.replace(/\$(\w*)\$[\s\S]*?\$\1\$/g, ' $rumpf$ ')
  return t
}

/** Name ohne Schema. */
const blank = n => n.split('.').slice(-1)[0]

/**
 * Die Signatur einer Funktion — der Typ jedes Arguments. Ohne sie gälten zwei
 * gleichnamige Funktionen mit verschiedenen Argumenten als dieselbe.
 */
function signatur(argtext) {
  return argtext
    .split(',')
    .map(a => a.replace(/\s+default\s+[\s\S]*$/, '').trim().split(/\s+/).filter(Boolean).slice(-1)[0] ?? '')
    .filter(Boolean)
    .join(',')
}

/**
 * Was tut diese Anweisung, und mit welchem Objekt?
 *
 *   baut     legt das Objekt an ("create")
 *   raeumt   nimmt es weg ("drop")
 *   anhang   beschreibt es, gibt Rechte darauf, indiziert es
 *
 * Alles andere — Tabellen, Daten, Regeln, Auslöser — gibt null und bleibt
 * damit unangetastet in Teil A.
 */
export function objekt(s) {
  const t = kern(s)
  let m
  if ((m = new RegExp(`^create\\s+(?:or\\s+replace\\s+)?(materialized\\s+)?view\\s+(?:if\\s+not\\s+exists\\s+)?(${RUMPF})`).exec(t)))
    return { ziel: blank(m[2]), art: m[1] ? 'matview' : 'view', tut: 'baut' }
  if ((m = new RegExp(`^create\\s+(?:or\\s+replace\\s+)?function\\s+(${RUMPF})\\s*\\(([^)]*)`).exec(t)))
    return { ziel: blank(m[1]), art: 'funktion', tut: 'baut', unterschrift: signatur(m[2]), sql: /\)\s*returns[\s\S]*?language\s+sql\b/.test(t) }
  if ((m = new RegExp(`^drop\\s+(materialized\\s+)?view\\s+(?:if\\s+exists\\s+)?(${RUMPF})`).exec(t)))
    return { ziel: blank(m[2]), art: m[1] ? 'matview' : 'view', tut: 'raeumt' }
  if ((m = new RegExp(`^drop\\s+function\\s+(?:if\\s+exists\\s+)?(${RUMPF})\\s*\\(([^)]*)`).exec(t)))
    return { ziel: blank(m[1]), art: 'funktion', tut: 'raeumt', unterschrift: signatur(m[2]) }
  if ((m = new RegExp(`^comment\\s+on\\s+(?:materialized\\s+view|view|function)\\s+(${RUMPF})`).exec(t)))
    return { ziel: blank(m[1]), art: 'anhang', tut: 'anhang' }
  if ((m = new RegExp(`^alter\\s+(?:materialized\\s+view|view|function)\\s+(?:if\\s+exists\\s+)?(${RUMPF})`).exec(t)))
    return { ziel: blank(m[1]), art: 'anhang', tut: 'anhang' }
  if ((m = new RegExp(`^create\\s+(?:unique\\s+)?index\\s+(?:if\\s+not\\s+exists\\s+)?${RUMPF}\\s+on\\s+(${RUMPF})`).exec(t)))
    return { ziel: blank(m[1]), art: 'anhang', tut: 'anhang' }
  // Ein Rundumschlag — "revoke execute on all functions in schema public" —
  // meint alles, was es gibt. Er gehört ans Ende, hinter Teil B: Sonst
  // erwischt er die Funktionen nicht, die dort erst entstehen, und
  // schimmelanteil() wäre plötzlich für jeden ausführbar. In den Migrationen
  // steht er mittendrin und erwischt trotzdem alles, weil dort alles schon
  // da ist.
  if (/^(?:grant|revoke)\s+[\s\S]*?\son\s+all\s+\w+\s+in\s+schema\b/.test(t))
    return { ziel: '', art: 'anhang', tut: 'anhang', rundum: true }
  if ((m = new RegExp(`^(?:grant|revoke)\\s+[\\s\\S]*?\\son\\s+(?:table\\s+|function\\s+)?(${RUMPF})`).exec(t)))
    return { ziel: blank(m[1]), art: 'anhang', tut: 'anhang' }
  return null
}

/** Der Schlüssel, unter dem ein Objekt geführt wird. */
function schluessel(o) {
  return o.art === 'funktion' ? `funktion ${o.ziel}(${o.unterschrift ?? ''})` : `${o.art} ${o.ziel}`
}

/** Typnamen vereinheitlichen, damit int und integer dieselbe Unterschrift sind. */
const TYPGLEICH = new Map([
  ['integer', 'int'], ['int4', 'int'], ['int8', 'bigint'], ['int2', 'smallint'],
  ['bool', 'boolean'], ['float8', 'double precision'], ['float4', 'real'],
  ['varchar', 'character varying'], ['timestamptz', 'timestamp with time zone'],
])
function normTyp(u) {
  return u.split(',').map(t => TYPGLEICH.get(t.trim()) ?? t.trim()).join(',')
}

/**
 * Die Unterschrift, auf die sich eine Anweisung über eine Funktion bezieht —
 * oder null, wenn sie keine nennt.
 *
 * "grant execute on function verlust_ranking(text, text, numeric)" nennt eine.
 * Eine Migration von 2026 hat sie damals vergeben; heute heisst die Funktion
 * (text, text, int). Ein solches Recht in Teil B wäre ein Fehler, kein Recht.
 */
function funktionsUnterschrift(t) {
  const m = new RegExp(`\\bfunction\\s+(${RUMPF})\\s*\\(([^)]*)\\)`).exec(t)
  return m ? { name: blank(m[1]), unterschrift: normTyp(m[2]) } : null
}

/**
 * Was eine Migration selbst über eine Anweisung sagt.
 *
 * Eine Handvoll Anweisungen baut Ansichten über zusammengesetztes SQL:
 * "execute format('create materialized view %I as select * from %I', …)" in
 * einer Schleife. Da hilft kein Lesen — der Name entsteht erst beim Laufen.
 * Statt zu raten, sagt es die Migration selbst, in einem Kommentar direkt
 * über der Anweisung:
 *
 *   -- verdichter: baut erg_gewichte erg_kaliber erg_gebinde
 *
 * Damit ist die Anweisung ein Objekt des Rechenwerks wie jedes andere: Sie
 * wandert nach Teil B, wird richtig einsortiert, und was sie baut, kann
 * danach beschrieben und indiziert werden. Fehlt die Angabe bei einer
 * Anweisung, die so etwas tut, bricht der Bau ab und sagt es.
 */
export function marke(s) {
  const namen = []
  for (const m of s.matchAll(/^\s*--\s*verdichter:\s*baut\s+(.+)$/gim))
    namen.push(...m[1].split(/[\s,]+/).map(x => x.trim().toLowerCase()).filter(Boolean))
  return namen
}

/**
 * Baut diese Anweisung eine Ansicht aus zusammengesetztem SQL?
 *
 * Nur das Anlegen zählt. Wer dynamisch wegräumt — wie das Aufräumen ganz am
 * Anfang in 0000 —, braucht keine Angabe: Weggeräumt wird in Teil A, gebaut
 * in Teil B, und was Teil A wegräumt, baut Teil B ohnehin neu.
 */
function baut_dynamisch(t) {
  return /\bexecute\b/.test(t)
    && /\bcreate\s+(?:or\s+replace\s+)?(?:materialized\s+view|view)\b/.test(t)
}

/**
 * Verdichtet die Anweisungsliste.
 * Gibt { teilA, teilB, bericht } zurück; wirft, wenn eine Zusicherung bricht.
 */
export function verdichten(liste) {
  const info = liste.map(objekt)
  const kerne = liste.map(nurCode)
  const jetzt = liste.map(braucht_jetzt)

  // ---- 1. Blöcke: aufeinanderfolgende Anweisungen zum selben Objekt --------
  // "drop v_x", "create v_x", "comment on view v_x", "grant select on v_x"
  // stehen im Quelltext beieinander und gehören zusammen.
  // Ein Block endet, wo ein anderes Objekt beginnt. Bei Funktionen zählt die
  // Unterschrift mit: verlust_ranking(text,text,numeric) und
  // verlust_ranking(text,text,int) sind zwei Objekte, auch wenn zwei
  // Aufräum-Zeilen für beide direkt untereinander stehen.
  const bloecke = []
  for (let i = 0; i < liste.length; i++) {
    if (!info[i]) continue
    const b = { ziel: info[i].ziel, von: i, bis: i, art: null, unterschrift: null, sql: false, schluessel: null }
    while (i < liste.length && info[i] && info[i].ziel === b.ziel) {
      if (info[i].tut !== 'anhang') {
        const k = schluessel(info[i])
        if (b.schluessel && k !== b.schluessel) break
        b.schluessel = k
        b.art = info[i].art
        b.unterschrift ??= info[i].unterschrift
        b.sql ||= !!info[i].sql
      }
      b.bis = i
      i++
    }
    i--
    if (b.art) bloecke.push(b)   // reine Anhang-Blöcke sind keine Definition
  }

  const jeObjekt = new Map()
  for (const b of bloecke) {
    if (!jeObjekt.has(b.schluessel)) jeObjekt.set(b.schluessel, [])
    jeObjekt.get(b.schluessel).push(b)
  }

  // Was gibt es am Ende noch? Nicht geraten, sondern durchgespielt: "create"
  // legt an, "drop" nimmt weg, die letzte Anweisung entscheidet. Nur so ist
  // zu sehen, dass verlust_ranking(text,text,numeric) — fünfmal geschrieben —
  // am Ende nicht mehr da ist, weil 0062 sie durch (text,text,int) ersetzt.
  const amEnde = new Set()
  for (let i = 0; i < liste.length; i++) {
    const o = info[i]
    if (!o || o.tut === 'anhang') continue
    if (o.tut === 'baut') amEnde.add(schluessel(o)); else amEnde.delete(schluessel(o))
  }

  // ---- 2. Wer wandert nach Teil B? ----------------------------------------
  // Alle Ansichten. Dazu jede Funktion in SQL, deren Rumpf eine gewanderte
  // Ansicht liest: Postgres prüft SQL-Rümpfe beim Anlegen, sie kann also nicht
  // vorher stehen. Funktionen in PL/pgSQL dürfen bleiben — ihr Rumpf wird
  // erst beim Aufruf aufgelöst.
  const wandert = new Set()
  for (const [k, b] of jeObjekt) if (b[0].art === 'view' || b[0].art === 'matview') wandert.add(k)
  for (let runde = 0; runde < 10; runde++) {
    const namen = [...wandert].map(k => jeObjekt.get(k)[0].ziel)
    let neu = false
    for (const [k, b] of jeObjekt) {
      if (wandert.has(k) || !b.some(x => x.sql)) continue
      const text = b.map(x => kerne.slice(x.von, x.bis + 1).join(' ')).join(' ')
      if (namen.some(n => new RegExp(`\\b${n}\\b`).test(text))) { wandert.add(k); neu = true }
    }
    if (!neu) break
  }

  // Anweisungen, die ihre Ansichten aus Textstücken zusammensetzen, sagen
  // selbst, was sie bauen. Ohne Angabe bricht der Bau ab — lieber ein klarer
  // Halt als eine setup.sql, die an der falschen Stelle aufhört.
  const markiert = new Map()     // Stelle → gebaute Namen
  liste.forEach((s, i) => {
    const namen = marke(s)
    if (namen.length) { markiert.set(i, namen); return }
    if (info[i] || !baut_dynamisch(kern(s))) return
    throw new Error(
      'Diese Anweisung baut Ansichten aus zusammengesetztem SQL, sagt aber nicht, welche:\n'
      + '  ' + kern(s).slice(0, 120).replace(/\s+/g, ' ') + '\n'
      + 'Bitte in der Migration eine Zeile darübersetzen:\n'
      + '  -- verdichter: baut <name> <name> …')
  })
  // Eine angemeldete Anweisung baut ihre Namen neu — mit "drop … if exists"
  // davor. Alles, was dieselben Namen **früher** gebaut hat, ist damit
  // überholt. In setup.sql wird jedes Objekt genau einmal gebaut; stünden
  // zwei Bauanweisungen für erg_bilanz darin, entschiede die Sortierung
  // statt der Absicht, welche zuerst liefe — und die zweite bräche ab.
  //
  // Der Fall entsteht, sobald eine Migration die Kaskade neu baut: „drop …
  // cascade" reisst die gespeicherten Ergebnisse mit, und sie werden danach
  // wieder angelegt. Nach dem Verdichten ist von jedem Objekt nur noch die
  // jüngste Anweisung übrig, und genau die soll bauen.
  const markeStellen = [...markiert.entries()].sort((a, b) => a[0] - b[0])
  const ueberholt = (name, stelle) => markeStellen.some(([i, ns]) => i > stelle && ns.includes(name))
  const ueberholteMarken = new Set()
  for (const [i, ns] of markeStellen)
    if (markeStellen.some(([j, ms]) => j > i && ns.every(n => ms.includes(n)))) ueberholteMarken.add(i)
  for (const i of ueberholteMarken) markiert.delete(i)

  const ausMarke = new Set([...markiert.values()].flat())

  // Welche Funktionen gibt es am Ende, mit welcher Unterschrift? Nur darauf
  // dürfen Rechte, Beschreibungen und Einstellungen zeigen.
  const endgueltig = new Map()
  for (const k of amEnde) {
    if (!k.startsWith('funktion ')) continue
    const name = k.slice('funktion '.length, k.indexOf('('))
    if (!endgueltig.has(name)) endgueltig.set(name, new Set())
    endgueltig.get(name).add(normTyp(k.slice(k.indexOf('(') + 1, -1)))
  }
    /**
   * Muss diese Anweisung aus einer überholten Fassung gerettet werden?
   *
   * Beschreibungen und Rechte überleben ein "create or replace" — sie stehen
   * also oft nur einmal, in der ersten Fassung, und gelten seither weiter.
   * Fällt diese Fassung weg, fielen sie mit: v_plausibilitaet stünde ohne
   * Erklärung da, und schema_stand() wäre plötzlich für jeden ausführbar.
   * Indizes dagegen bleiben nicht: Sie zeigen auf Spalten, die es in der
   * neuen Fassung nicht mehr geben muss.
   */
  const nachtragen = t => /^(comment|grant|revoke)\b/.test(t)

  /** Zeigt diese Anweisung auf eine Funktion, die es so nicht mehr gibt? */
  const veraltet = i => {
    const u = funktionsUnterschrift(kerne[i])
    return !!u && endgueltig.has(u.name) && !endgueltig.get(u.name).has(u.unterschrift)
  }

  // ---- 3. Was bleibt stehen? ---------------------------------------------
  const weg = new Set()          // fällt ganz weg
  const nachB = new Set()        // wandert nach Teil B
  const nachtrag = new Map()     // Stelle → Gerettetes, das dahinter nachrückt
  const bericht = []

  // Was eine spätere angemeldete Anweisung ohnehin neu baut, muss hier nicht
  // noch einmal gebaut werden (siehe „überholt" oben).
  for (const [k, b] of jeObjekt) {
    if (wandert.has(k) && ueberholt(b[0].ziel, b.at(-1).von)) {
      for (const x of b) for (let i = x.von; i <= x.bis; i++) weg.add(i)
      wandert.delete(k)
      bericht.push({ objekt: k, entfernt: b.length, bytes: b.reduce((s2, x) => s2 + kerne.slice(x.von, x.bis + 1).join('').length, 0) })
    }
  }
  for (const i of ueberholteMarken) weg.add(i)

  for (const [k, b] of jeObjekt) {
    if (weg.has(b[0].von) && !wandert.has(k)) continue
    if (wandert.has(k)) {
      // Vom letzten Block bleibt alles: die Definition, ihre Beschreibung,
      // ihre Indizes. Aus früheren Blöcken bleiben nur die Leserechte — sie
      // gehen beim Neubau verloren und müssen neu vergeben werden, während
      // eine alte Beschreibung nur veraltet und ein alter Index auf eine
      // Spalte zeigt, die es nicht mehr gibt.
      // Gibt es das Objekt am Ende gar nicht mehr — v_auftrag_sortierart etwa
      // ist 0043 gebaut und 0048 als Ballast weggeräumt worden —, dann bleibt
      // nur das Wegräumen. Ein Leserecht auf etwas, das es nicht gibt, wäre
      // in Teil B ein Fehler.
      const existiert = amEnde.has(k)
      for (let j = 0; j < b.length; j++) {
        const letzter = j === b.length - 1
        for (let i = b[j].von; i <= b[j].bis; i++) {
          const behalten = (letzter || nachtragen(kerne[i]))
            && !veraltet(i)
            && (existiert || info[i].tut !== 'anhang')
          if (behalten) nachB.add(i); else weg.add(i)
        }
      }
      const gespart = b.slice(0, -1).reduce((s, x) => s + kerne.slice(x.von, x.bis + 1).length, 0)
      if (b.length > 1) bericht.push({ objekt: k, entfernt: b.length - 1, bytes: gespart })
      continue
    }
    // Bleibt in Teil A: nur überholte Fassungen entfernen, und nur, wenn
    // dazwischen niemand das Objekt benutzt.
    if (b.length < 2) continue
    const treffer = new RegExp(`\\b${b[0].ziel}\\b`)
    // Wohin das Gerettete rückt: hinter die letzte Anweisung, die das Objekt
    // anlegt, aber vor deren eigene Beschreibung — so gilt am Ende, was die
    // jüngste Fassung sagt, und nicht, was eine alte einmal gesagt hat.
    const letzterBlock = b.at(-1)
    let hinter = null
    for (let i = letzterBlock.von; i <= letzterBlock.bis; i++) if (info[i].tut !== 'anhang') hinter = i
    let entfernt = 0, bytes = 0
    for (let j = 0; j < b.length - 1; j++) {
      let gebraucht = false
      for (let i = b[j].bis + 1; i < b[j + 1].von && !gebraucht; i++)
        if (!weg.has(i) && !nachB.has(i) && treffer.test(kerne[i])) gebraucht = true
      if (gebraucht) continue
      for (let i = b[j].von; i <= b[j].bis; i++) {
        if (hinter !== null && nachtragen(kerne[i]) && !veraltet(i) && amEnde.has(k)) {
          if (!nachtrag.has(hinter)) nachtrag.set(hinter, [])
          nachtrag.get(hinter).push(liste[i])
        }
        weg.add(i); bytes += liste[i].length
      }
      entfernt++
    }
    if (entfernt) bericht.push({ objekt: k, entfernt, bytes })
  }

  // Beschreibungen und Rechte, die ein gewandertes Objekt nennen, müssen
  // mitwandern — sie stünden sonst in Teil A vor dem, worauf sie sich
  // beziehen. Das betrifft auch die, die im Quelltext allein stehen, weit weg
  // von der Ansicht, die sie beschreiben.
  const gewandert = [...new Set([...[...wandert].map(k => jeObjekt.get(k)[0].ziel), ...ausMarke])]
  const lebt = new Set(ausMarke)
  for (const k of amEnde) lebt.add(k.slice(k.indexOf(' ') + 1).split('(')[0])
  liste.forEach((_, i) => {
    if (weg.has(i) || nachB.has(i) || markiert.has(i)) return
    if (!info[i] || info[i].tut !== 'anhang') return
    if (info[i].rundum) { nachB.add(i); return }
    const genannt = gewandert.filter(n => new RegExp(`\\b${n}\\b`).test(kerne[i]))
    if (!genannt.length) return
    // Nennt es eine Ansicht, die es am Ende nicht mehr gibt, oder eine
    // Funktion mit einer Unterschrift von damals, wäre es in Teil B ein
    // Fehler — dann fällt es weg, wie es heute auch endet.
    if (genannt.every(n => lebt.has(n)) && !veraltet(i)) nachB.add(i); else weg.add(i)
  })

  // ---- 4. Zusicherung: Teil A darf nichts Gewandertes brauchen ------------
  // Ein "drop … if exists" zählt nicht: Es räumt weg, was da ist, und tut
  // sonst nichts. Steht es in Teil A und wird das Objekt in Teil B neu
  // gebaut, ist genau das die Absicht.
  const offen = []
  liste.forEach((_, i) => {
    if (weg.has(i) || nachB.has(i) || markiert.has(i)) return
    if (/^drop\s+[\s\S]*?\bif\s+exists\b/.test(jetzt[i])) return
    for (const n of gewandert) if (new RegExp(`\\b${n}\\b`).test(jetzt[i])) { offen.push([n, jetzt[i].slice(0, 80)]); break }
  })
  if (offen.length) {
    throw new Error('Teil A benutzt etwas, das nach Teil B gewandert ist:\n'
      + offen.slice(0, 5).map(([n, s]) => `  ${n} in: ${s.replace(/\s+/g, ' ')}`).join('\n'))
  }

  // ---- 5. Teil B ordnen ---------------------------------------------------
  const knoten = [...wandert].map(k => {
    const letzter = jeObjekt.get(k).at(-1)
    const bauen = []
    for (let i = letzter.von; i <= letzter.bis; i++) if (info[i].tut !== 'anhang') bauen.push(i)
    return { k, ziel: jeObjekt.get(k)[0].ziel, art: jeObjekt.get(k)[0].art, bauen, ab: letzter.von, namen: [jeObjekt.get(k)[0].ziel] }
  }).filter(x => x.bauen.length)

  // Die angemeldeten Anweisungen sind Knoten wie jeder andere — nur dass ihre
  // Namen aus der Markierung kommen und ihre Abhängigkeiten auch in
  // Zeichenketten stehen dürfen (dort steht ja ihr zusammengesetztes SQL).
  for (const [i, namen] of markiert)
    knoten.push({ k: `angemeldet@${i}`, ziel: namen[0], art: 'marke', bauen: [i], ab: i, namen, text: kern(liste[i]) })

  // Ein Name kann mehrere Knoten haben: verlust_ranking gibt es mit drei
  // Unterschriften, eine wird gebaut, zwei werden weggeräumt. Wer die
  // Funktion liest, muss hinter alle drei — sonst liest er die, die gerade
  // weggeräumt wird.
  const nameZuKnoten = new Map()
  for (const x of knoten) for (const n of x.namen) {
    if (!nameZuKnoten.has(n)) nameZuKnoten.set(n, [])
    nameZuKnoten.get(n).push(x)
  }

  // Kante A → B: A liest B, also muss B zuerst stehen. Zwischen Knoten
  // desselben Namens wird keine Kante gezogen — die stehen in der
  // Reihenfolge, in der sie in den Migrationen stehen, und ein "drop" und ein
  // "create" derselben Funktion würden sich sonst gegenseitig blockieren.
  const braucht = new Map(knoten.map(x => [x.k, new Set()]))
  for (const x of knoten) {
    const text = x.text ?? x.bauen.map(i => kerne[i]).join(' ')
    for (const [name, ys] of nameZuKnoten) {
      if (!new RegExp(`\\b${name}\\b`).test(text)) continue
      for (const y of ys) if (!y.namen.some(n2 => x.namen.includes(n2))) braucht.get(x.k).add(y.k)
    }
  }

  // Kahn, stabil nach ursprünglicher Stelle.
  const offen2 = new Map(knoten.map(x => [x.k, new Set(braucht.get(x.k))]))
  const reihe = []
  const wartend = [...knoten].sort((a, b) => a.ab - b.ab)
  while (wartend.length) {
    const i = wartend.findIndex(x => offen2.get(x.k).size === 0)
    if (i < 0) throw new Error('Teil B ist nicht kreisfrei — betroffen: '
      + wartend.slice(0, 6).map(x => x.k).join(', '))
    const [x] = wartend.splice(i, 1)
    reihe.push(x)
    for (const o of offen2.values()) o.delete(x.k)
  }

  // ---- 6. Zusammensetzen --------------------------------------------------
  const teilA = []
  liste.forEach((s2, i) => {
    if (!weg.has(i) && !nachB.has(i) && !markiert.has(i)) teilA.push(s2)
    if (nachtrag.has(i)) teilA.push(...nachtrag.get(i))
  })
  const anhang = []
  liste.forEach((_, i) => { if (nachB.has(i) && info[i]?.tut === 'anhang') anhang.push(liste[i]) })

  const raeumen = reihe
    .filter(x => x.art === 'view' || x.art === 'matview')
    .reverse()
    .map(x => `drop ${x.art === 'matview' ? 'materialized view' : 'view'} if exists ${x.ziel} cascade;`)

  const bauen = reihe.flatMap(x => x.bauen
    .filter(i => x.art === 'marke' || info[i].tut === 'baut' || info[i].art === 'funktion')
    .map(i => liste[i]))

  return {
    teilA,
    raeumen,
    bauen,
    anhang,
    reihe,
    bericht: bericht.sort((a, b) => b.bytes - a.bytes),
    gewandert: wandert.size,
  }
}
