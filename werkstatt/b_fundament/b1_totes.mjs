/**
 * B1 — Was ist tot?
 *
 * DIE FRAGE
 *
 * 2633 Objekte stehen in dieser Datenbank: 63 Ansichten, 38 gespeicherte
 * Ansichten, 42 Funktionen, 93 Indexe, dazu Rechte, Bedingungen,
 * Beschreibungen. Gewachsen über zwölf Runden, in denen fast jede Migration
 * Formeln neu geschrieben hat.
 *
 * Geprüft wird die **Fachlogik** — ob die Zahlen stimmen. Niemand hat je
 * gefragt, ob es all diese Objekte noch braucht.
 *
 * Tote Masse ist nicht harmlos:
 *   - Eine Ansicht, die niemand liest, wird trotzdem bei jedem `drop … cascade`
 *     mitgerissen und neu gebaut. Sie steht in `setup.sql` und kostet dort
 *     Platz, den der SQL-Editor knapp bemisst (Grenze 1000 kB, belegt 574).
 *   - Ein Index, den niemand benutzt, kostet bei **jedem Schreiben** Zeit und
 *     bringt nie etwas zurück. Der Arbeiter an der Waage bezahlt ihn.
 *   - Ein totes Objekt sieht aus wie ein lebendes. Wer es liest, hält es für
 *     Teil der Rechnung und traut sich nicht, daran zu rühren.
 *
 * WIE ES GEMESSEN WIRD
 *
 * Nicht durch Nachsehen, sondern über den **vollständigen Nutzungsgraphen**:
 *
 *   1. Die Wurzeln — was von aussen angesprochen wird: die Oberfläche
 *      (`supabase.from('…')`, `.rpc('…')`), die Prüfungen, die Prüfstände,
 *      das Prüfwerk, die Auslöser, die Rechenfunktion.
 *   2. Von den Wurzeln aus rückwärts durch `pg_depend`: alles, worauf ein
 *      lebendes Objekt aufbaut, lebt ebenfalls.
 *   3. Was übrig bleibt, liest niemand.
 *
 * Der Schluss ist bewusst **vorsichtig**: Ein Name, der irgendwo im Quelltext
 * vorkommt — auch nur in einem Kommentar —, gilt als gelesen. Lieber ein
 * totes Objekt übersehen als ein lebendes zum Abriss vorschlagen.
 *
 * Für Indexe zählt der Graph nicht; sie werden vom Planer benutzt oder nicht.
 * Deshalb läuft hier ein **echter Arbeitstag** über eine Kopie der Datenbank —
 * die ganze Auswertung neu gerechnet und jede Ansicht geladen, die die App
 * lädt — und danach wird `pg_stat_user_indexes` abgelesen. `idx_scan = 0` auf
 * einer frisch kopierten Datenbank hiesse gar nichts; nach diesem Lauf heisst
 * es etwas.
 */
import { frage, tue, kopie, lies, dateien, alleDateien, befund, messung, KATALOG } from '../umgebung.mjs'

export const lang = true

/* ---------- Die Wurzeln: was von aussen angesprochen wird ----------------- */

/** Verzeichnisse, deren Erwähnung ein Objekt am Leben hält. */
const QUELLEN = [
  { verzeichnis: 'src', muster: /\.(ts|tsx)$/, was: 'Oberfläche' },
  { verzeichnis: 'supabase/test', muster: /\.(sql|sh)$/, was: 'Prüfung' },
  { verzeichnis: 'pruefstand', muster: /\.(mjs|sh|json)$/, was: 'Prüfstand' },
  { verzeichnis: 'pruefwerk', muster: /\.mjs$/, was: 'Prüfwerk' },
  { verzeichnis: 'test', muster: /\.ts$/, was: 'Modultest' },
  { verzeichnis: 'supabase', muster: /^(diagnose|demo_daten)\.sql$/, was: 'Betriebswerkzeug' },
]

/**
 * `werkstatt/` steht absichtlich **nicht** in dieser Liste. Sonst hielte jedes
 * Werkzeug jedes Objekt am Leben, dessen Namen es in einem Kommentar erwähnt —
 * und die Werkstatt bewiese am Ende nur, dass sie selbst existiert. Die
 * Selbstprobe unten ist genau daran hängengeblieben, bevor die Zeile hier
 * gestrichen wurde.
 */
function quelltext() {
  const teile = []
  for (const q of QUELLEN)
    for (const d of alleDateien(q.verzeichnis, { muster: q.muster }))
      teile.push({ pfad: d.pfad, was: q.was, text: lies(d.pfad) })
  return teile
}

/**
 * Die zweite Sorte Wurzel: Funktionen, die **die Datenbank selbst** aufruft —
 * aus einem Auslöser, einer Zugriffsregel, einer Prüfbedingung oder einem
 * Vorgabewert. Sie stehen in keinem Quelltext und sahen in der ersten Fassung
 * dieses Werkzeugs deshalb tot aus: `ausschuss_netto_setzen`,
 * `rolle_schuetzen`, `korrekturfenster`, `ist_beteiligt` — allesamt tragende
 * Teile, die kein `select` je beim Namen nennt.
 */
function vonDerDatenbankGerufen(db, namen) {
  const texte = [
    /* Auslöser **aller** Schemata. `handle_new_user` hängt an `auth.users`;
       eine Suche nur in `public` erklärt sie für tot, und sie ist der Grund,
       warum ein neuer Benutzer überhaupt ein Profil bekommt. */
    ...frage(db, `select n.nspname || '.' || c.relname as was, pg_get_triggerdef(t.oid) as text
                    from pg_trigger t
                    join pg_class c on c.oid = t.tgrelid
                    join pg_namespace n on n.oid = c.relnamespace
                   where not t.tgisinternal`).map(a => ({ was: `Auslöser auf ${a.was}`, text: a.text })),
    ...KATALOG.regeln(db).map(r => ({ was: `Zugriffsregel ${r.tabelle}.${r.name}`,
                                      text: `${r.bedingung ?? ''} ${r.beim_schreiben ?? ''}` })),
    ...KATALOG.bedingungen(db).map(b => ({ was: `Bedingung ${b.tabelle}.${b.name}`, text: b.text })),
    ...frage(db, `select c.relname || '.' || a.attname as was,
                         pg_get_expr(d.adbin, d.adrelid) as text
                    from pg_attrdef d
                    join pg_class c on c.oid = d.adrelid
                    join pg_attribute a on a.attrelid = c.oid and a.attnum = d.adnum
                    join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public'`).map(v => ({ was: `Vorgabewert ${v.was}`, text: v.text })),
  ]
  const raus = new Map()
  for (const n of namen)
    for (const t of texte)
      if (new RegExp(`\\b${n}\\b`).test(t.text ?? '')) {
        if (!raus.has(n)) raus.set(n, [])
        raus.get(n).push(t.was)
      }
  return raus
}

/** Wo taucht der Name auf? Als ganzes Wort, sonst trifft `charge` auch `charge_nr`. */
function erwaehntIn(teile, name) {
  const wort = new RegExp(`\\b${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`)
  return teile.filter(t => wort.test(t.text)).map(t => `${t.was}: ${t.pfad}`)
}

/* ---------- Der Graph: wer baut worauf auf ------------------------------- */

/**
 * `liest[X]` = die Objekte, die X liest.
 *
 * Drei Sorten Kante, und zwei davon hat die erste Fassung dieses Werkzeugs
 * übersehen — mit dem Ergebnis, dass tragende Teile tot aussahen:
 *
 *   Sicht → Tabelle/Sicht — über `pg_rewrite` mit `refclassid = pg_class`.
 *   Sicht → **Funktion**  — über `pg_rewrite` mit `refclassid = pg_proc`.
 *                           Ohne diese Kante sieht jede Funktion tot aus, die
 *                           nur aus einer Sicht heraus gerufen wird
 *                           (`anteil_plausibel` etwa, in sechs Sichten).
 *   Funktion → alles      — Postgres verfolgt Funktionskörper nicht, die
 *                           Namen müssen aus dem Text kommen.
 */
function graph(db, namen) {
  const liest = new Map()
  const dazu = (wer, was) => {
    if (wer === was) return
    if (!liest.has(wer)) liest.set(wer, new Set())
    liest.get(wer).add(was)
  }

  for (const k of frage(db, `
    select distinct z.relname as wer, q.relname as was
      from pg_depend d
      join pg_rewrite r on r.oid = d.objid and d.classid = 'pg_rewrite'::regclass
      join pg_class z on z.oid = r.ev_class
      join pg_class q on q.oid = d.refobjid
      join pg_namespace nq on nq.oid = q.relnamespace
      join pg_namespace nz on nz.oid = z.relnamespace
     where nq.nspname = 'public' and nz.nspname = 'public'
    union
    select distinct z.relname, p.proname
      from pg_depend d
      join pg_rewrite r on r.oid = d.objid and d.classid = 'pg_rewrite'::regclass
      join pg_class z on z.oid = r.ev_class
      join pg_proc p on p.oid = d.refobjid and d.refclassid = 'pg_proc'::regclass
      join pg_namespace np on np.oid = p.pronamespace
      join pg_namespace nz on nz.oid = z.relnamespace
     where np.nspname = 'public' and nz.nspname = 'public'`))
    dazu(k.wer, k.was)

  for (const f of KATALOG.funktionen(db))
    for (const n of namen)
      if (n !== f.name && new RegExp(`\\b${n}\\b`).test(f.text)) dazu(f.name, n)

  return liest
}

/* ---------- Ein Arbeitstag, damit die Indexe etwas zu tun bekommen -------- */

/**
 * Was die App wirklich lädt. Nicht geraten, sondern aus dem Quelltext
 * gelesen: jedes `supabase.from('…')` und jedes `.rpc('…')`.
 */
function appZugriffe() {
  const von = new Set(), rpc = new Set()
  for (const p of dateien('src')) {
    const t = lies(p)
    for (const m of t.matchAll(/\.from\(\s*'([a-z_0-9]+)'/g)) von.add(m[1])
    for (const m of t.matchAll(/\.rpc\(\s*'([a-z_0-9]+)'/g)) rpc.add(m[1])
  }
  return { von: [...von].sort(), rpc: [...rpc].sort() }
}

function arbeitstag(db) {
  const { von } = appZugriffe()
  tue(db, 'select pg_stat_reset()')
  tue(db, 'select auswertung_aktualisieren()')
  let geladen = 0, gescheitert = []
  for (const t of von) {
    try { tue(db, `select * from ${t} limit 500`); geladen++ }
    catch (e) { gescheitert.push(`${t}: ${e.message.slice(0, 60)}`) }
  }
  // Der Arbeiter fragt gezielt, nicht pauschal — das sind die Zugriffe, bei
  // denen ein Index überhaupt etwas bringen kann.
  const gezielt = [
    `select * from auftrag where status = 'offen' order by start_ts desc limit 20`,
    `select * from palette where charge_nr = (select min(nr) from charge)`,
    `select * from lieferung where datum >= current_date - 60 order by datum desc`,
    `select * from verdunstung_wiegung where charge_nr = (select min(nr) from charge)`,
    `select * from sortier_gewicht where lauf_id = (select min(id) from sortier_lauf)`,
    `select * from auftrag_palette where auftrag_id = (select min(id) from auftrag)`,
    `select * from ausgang_zeile where datei_id = (select min(id) from ausgang_datei)`,
  ]
  for (const q of gezielt) { try { tue(db, q) } catch { /* Tabelle leer, egal */ } }
  return { geladen, gescheitert }
}

/* ---------- Lauf ---------------------------------------------------------- */

export async function laufen({ db = 'demo' } = {}) {
  const raus = []
  const teile = quelltext()

  const sichten = KATALOG.sichten(db)
  const funktionen = KATALOG.funktionen(db)
  const tabellen = KATALOG.tabellen(db)
  const namen = [...sichten.map(s => s.name), ...funktionen.map(f => f.name), ...tabellen.map(t => t.name)]

  const liest = graph(db, namen)

  /* Wurzeln: was ausserhalb der Datenbank beim Namen genannt wird — und was
     die Datenbank selbst aufruft, ohne dass ein Quelltext es nennt. */
  const wurzeln = new Map()
  const intern = vonDerDatenbankGerufen(db, namen)
  for (const n of namen) {
    const wo = [...erwaehntIn(teile, n), ...(intern.get(n) ?? [])]
    if (wo.length) wurzeln.set(n, wo)
  }

  /* Lebendig = Wurzel oder von einer Wurzel aus erreichbar. */
  const lebt = new Set(wurzeln.keys())
  let gewachsen = true
  while (gewachsen) {
    gewachsen = false
    for (const n of [...lebt])
      for (const k of liest.get(n) ?? [])
        if (!lebt.has(k)) { lebt.add(k); gewachsen = true }
  }

  const totSichten = sichten.filter(s => !lebt.has(s.name))
  const totFunktionen = funktionen.filter(f => !lebt.has(f.name))
  const totTabellen = tabellen.filter(t => !lebt.has(t.name))

  /* --- Indexe: nur messbar, nicht ableitbar --- */
  const probe = kopie(db, 'mw_b1')
  const tag = arbeitstag('mw_b1')
  const indexe = frage('mw_b1', `
    select i.relname as name, t.relname as tabelle, s.idx_scan,
           pg_relation_size(i.oid) as bytes, x.indisunique as eindeutig,
           x.indisprimary as schluessel, pg_get_indexdef(i.oid) as text
      from pg_class i
      join pg_index x on x.indexrelid = i.oid
      join pg_class t on t.oid = x.indrelid
      join pg_namespace n on n.oid = i.relnamespace
      left join pg_stat_user_indexes s on s.indexrelid = i.oid
     where n.nspname = 'public'
     order by coalesce(s.idx_scan, 0), pg_relation_size(i.oid) desc`)
  const ungenutzt = indexe.filter(i => (i.idx_scan ?? 0) === 0 && !i.schluessel && !i.eindeutig)

  /* --- Messreihen --- */
  raus.push(messung({
    werkstatt: 'B', titel: 'Objekte der Datenbank und wer sie liest',
    einheit: 'Objekte',
    spalten: ['Art', 'gesamt', 'von aussen angesprochen', 'nur intern gelesen', 'liest niemand'],
    zeilen: [
      { Art: 'Ansichten', gesamt: sichten.filter(s => s.art === 'v').length,
        'von aussen angesprochen': sichten.filter(s => s.art === 'v' && wurzeln.has(s.name)).length,
        'nur intern gelesen': sichten.filter(s => s.art === 'v' && !wurzeln.has(s.name) && lebt.has(s.name)).length,
        'liest niemand': totSichten.filter(s => s.art === 'v').length },
      { Art: 'gespeicherte Ansichten', gesamt: sichten.filter(s => s.art === 'm').length,
        'von aussen angesprochen': sichten.filter(s => s.art === 'm' && wurzeln.has(s.name)).length,
        'nur intern gelesen': sichten.filter(s => s.art === 'm' && !wurzeln.has(s.name) && lebt.has(s.name)).length,
        'liest niemand': totSichten.filter(s => s.art === 'm').length },
      { Art: 'Funktionen', gesamt: funktionen.length,
        'von aussen angesprochen': funktionen.filter(f => wurzeln.has(f.name)).length,
        'nur intern gelesen': funktionen.filter(f => !wurzeln.has(f.name) && lebt.has(f.name)).length,
        'liest niemand': totFunktionen.length },
      { Art: 'Tabellen', gesamt: tabellen.length,
        'von aussen angesprochen': tabellen.filter(t => wurzeln.has(t.name)).length,
        'nur intern gelesen': tabellen.filter(t => !wurzeln.has(t.name) && lebt.has(t.name)).length,
        'liest niemand': totTabellen.length },
    ],
    erklaerung: 'Vorsichtig gezählt: Ein Name, der irgendwo im Quelltext vorkommt — auch nur in '
      + 'einem Kommentar —, gilt als gelesen. Die Spalte „liest niemand" ist damit eine **untere** '
      + 'Schranke; in Wirklichkeit ist mehr tot.',
  }))

  raus.push(messung({
    werkstatt: 'B', titel: 'Indexe nach einem vollständigen Arbeitstag',
    einheit: 'Zugriffe',
    spalten: ['Index', 'Tabelle', 'Zugriffe', 'Bytes', 'Art'],
    zeilen: indexe.slice(0, 40).map(i => ({
      Index: i.name, Tabelle: i.tabelle, Zugriffe: i.idx_scan ?? 0, Bytes: i.bytes,
      Art: i.schluessel ? 'Primärschlüssel' : i.eindeutig ? 'eindeutig' : 'Suchindex',
    })),
    erklaerung: `Auf einer Kopie der Datenbank wurde die Statistik zurückgesetzt, dann die ganze `
      + `Auswertung neu gerechnet, dann ${tag.geladen} Ansichten geladen — genau die, die die App `
      + `lädt — und sieben gezielte Abfragen gestellt, wie ein Arbeiter sie auslöst. Erst danach `
      + `wurde abgelesen. Primärschlüssel und eindeutige Indexe bleiben auch bei null Zugriffen: `
      + `Sie halten eine Bedingung, nicht eine Abfrage.`,
  }))

  /* --- Befunde --- */
  const tot = [...totSichten, ...totFunktionen]
  if (tot.length) {
    const bytesSetup = tot.reduce((a, o) => a + (o.text?.length ?? 0), 0)
    raus.push(befund({
      werkstatt: 'B', kuerzel: 'TOT', klasse: 2,
      ort: { sicht: tot.slice(0, 5).map(o => o.name).join(', ') + (tot.length > 5 ? ' …' : '') },
      titel: `${tot.length} Objekte der Datenbank liest niemand`,
      steht_da: tot.map(o => `\`${o.name}\``).join(', ')
        + `. Weder die Oberfläche noch eine Prüfung, ein Prüfstand, ein Auslöser oder eine andere `
        + `Ansicht spricht sie an — auch nicht mittelbar.`,
      muesste: 'Entfernt werden, oder mit einem Satz versehen, wozu sie da sind. Ansichten und '
        + 'Funktionen halten keine Daten; sie zu entfernen kostet nichts und ist umkehrbar.',
      warum: `Jedes dieser Objekte wird bei jedem \`drop … cascade\` mitgerissen und neu gebaut, `
        + `steht in \`setup.sql\` (${Math.round(bytesSetup / 1024)} kB von 574 kB, Grenze des `
        + `SQL-Editors 1000 kB) und sieht aus wie Teil der Rechnung. Wer es liest, traut sich nicht, `
        + `daran zu rühren — tote Masse macht ein System langsamer zu ändern, nicht nur grösser.`,
      beleg: 'werkstatt/b_fundament/b1_totes.mjs → Nutzungsgraph aus pg_depend plus Quelltextsuche',
      groesse: { wert: tot.length, einheit: 'Objekte ohne Leser',
                 basis: `${sichten.length} Ansichten und ${funktionen.length} Funktionen geprüft` },
      sicherheit: 'hoch',
      gegenrede: 'Die Zählung ist vorsichtig: Ein Name in einem Kommentar hält ein Objekt am Leben. '
        + 'Wer hier steht, wird also wirklich nirgends genannt. Trotzdem kann ein Objekt absichtlich '
        + 'für den Betriebsleiter im SQL-Editor dastehen — dann fehlt ihm ein Satz, der das sagt.',
      marke: 'Reduktion', aufwand: 'klein',
    }))
  }

  if (ungenutzt.length) {
    const bytes = ungenutzt.reduce((a, i) => a + Number(i.bytes), 0)
    raus.push(befund({
      werkstatt: 'B', kuerzel: 'TOT', klasse: 2,
      ort: { tabelle: [...new Set(ungenutzt.map(i => i.tabelle))].join(', ') },
      titel: `${ungenutzt.length} Suchindexe wurden an einem vollständigen Arbeitstag kein einziges Mal benutzt`,
      steht_da: ungenutzt.slice(0, 12).map(i => `\`${i.name}\``).join(', ')
        + (ungenutzt.length > 12 ? ` … und ${ungenutzt.length - 12} weitere` : '')
        + `. Zusammen ${Math.round(bytes / 1024)} kB. Gemessen nach `
        + `\`pg_stat_reset()\`, einer vollständigen Neuberechnung der Auswertung, `
        + `${tag.geladen} geladenen Ansichten und sieben gezielten Abfragen.`,
      muesste: 'Ein Index, den keine Abfrage benutzt, gehört weg — oder es fehlt die Abfrage, für '
        + 'die er gebaut wurde. Beides ist eine Antwort; der heutige Zustand ist keine.',
      warum: 'Ein Index kostet bei **jedem** Schreiben Zeit und bringt nur beim Lesen etwas. Der '
        + 'Arbeiter an der Waage, der auf „Speichern" drückt, bezahlt ihn; der Betriebsleiter, für '
        + 'den er gedacht war, benutzt ihn nicht.',
      beleg: 'werkstatt/b_fundament/b1_totes.mjs → Messreihe „Indexe nach einem vollständigen Arbeitstag"',
      groesse: { wert: ungenutzt.length, einheit: 'ungenutzte Suchindexe',
                 basis: `${indexe.length} Indexe, gemessen über einen vollständigen Arbeitstag auf den Demodaten` },
      sicherheit: 'mittel',
      gegenrede: 'Die Demosaison ist eine Saison; ein Index kann für einen Fall gebaut sein, den sie '
        + 'nicht enthält (eine bestimmte Suche des Betriebsleiters, ein Import bestimmter Grösse). '
        + 'Und bei 844 Paletten wählt der Planer oft den sequenziellen Weg, weil die Tabelle klein '
        + 'ist — bei zehnfacher Menge könnte derselbe Index gebraucht werden. Vor dem Entfernen '
        + 'gehört deshalb der Lasttest dazu, nicht nur dieser Lauf.',
      marke: 'Reduktion', aufwand: 'klein',
    }))
  }

  if (totTabellen.length) {
    raus.push(befund({
      werkstatt: 'B', kuerzel: 'TOT', klasse: 2,
      ort: { tabelle: totTabellen.map(t => t.name).join(', ') },
      titel: `${totTabellen.length} Tabellen liest niemand`,
      steht_da: totTabellen.map(t => `\`${t.name}\` (${t.zeilen_geschaetzt} Zeilen, ${t.spalten} Spalten)`).join(', '),
      muesste: 'Eine Tabelle, die niemand liest, wird entweder noch gebraucht und dann von etwas '
        + 'gelesen — oder sie ist ein Rest. **Nicht entfernen**: In einer Tabelle liegen Daten, und '
        + 'die Regel dieses Projekts ist, dass Tabellen und Spalten bleiben. Aber sie gehört benannt.',
      warum: 'Eine Tabelle, in die geschrieben und aus der nie gelesen wird, kostet den Arbeiter '
        + 'Zeit an der Waage für nichts.',
      beleg: 'werkstatt/b_fundament/b1_totes.mjs → Nutzungsgraph',
      groesse: { wert: totTabellen.length, einheit: 'Tabellen ohne Leser',
                 basis: `${tabellen.length} Tabellen geprüft` },
      sicherheit: 'mittel',
      gegenrede: 'Manche Tabelle wird nur im Betrieb gelesen, über den SQL-Editor, und kommt '
        + 'deshalb in keinem Quelltext vor. Vor jedem Schluss gehört die Frage an den Betrieb.',
      marke: 'Frage an den Betrieb', aufwand: 'klein',
    }))
  }

  /* Das Geprüfte gehört genauso in den Bericht wie das Gefundene — sonst sagt
     die Liste nichts darüber, wie weit nachgesehen wurde. */
  if (!tot.length && !totTabellen.length) {
    raus.push(befund({
      werkstatt: 'B', kuerzel: 'TOT', klasse: 1,
      ort: { sicht: 'alle Ansichten, Funktionen und Tabellen' },
      titel: 'Geprüft und in Ordnung: jede Ansicht, jede Funktion und jede Tabelle hat einen Leser',
      steht_da: `${sichten.filter(s => s.art === 'v').length} Ansichten, `
        + `${sichten.filter(s => s.art === 'm').length} gespeicherte Ansichten, `
        + `${funktionen.length} Funktionen und ${tabellen.length} Tabellen — jedes einzelne wird `
        + `angesprochen: von der Oberfläche, einer Prüfung, einem Prüfstand, einem Auslöser, einer `
        + `Zugriffsregel, einer Prüfbedingung oder einer anderen Ansicht. `
        + `${sichten.filter(s => !wurzeln.has(s.name)).length} Ansichten und `
        + `${funktionen.filter(f => !wurzeln.has(f.name) && lebt.has(f.name)).length} Funktionen `
        + `werden **nur mittelbar** gelesen — sie sind Zwischenstufen der Kette, kein Ballast.`,
      muesste: 'So.',
      warum: 'Nach zwölf Runden Anbau, in denen fast jede Migration Formeln neu geschrieben hat, ist '
        + 'das nicht selbstverständlich. Es gehört gemessen und aufgeschrieben, damit die nächste '
        + 'Runde nicht dieselbe Frage noch einmal stellt.',
      beleg: 'werkstatt/b_fundament/b1_totes.mjs → Nutzungsgraph aus pg_depend (Sicht→Tabelle und '
        + 'Sicht→Funktion), Auslöser aller Schemata, Zugriffsregeln, Prüfbedingungen, Vorgabewerte, '
        + 'dazu die Quelltextsuche über Oberfläche, Prüfungen, Prüfstände und Prüfwerk',
      groesse: { wert: sichten.length + funktionen.length + tabellen.length,
                 einheit: 'Objekte, alle mit Leser', basis: 'vollständiger Nutzungsgraph der Datenbank' },
      sicherheit: 'hoch', marke: 'kein Fehler', aufwand: 'keiner',
    }))
  }

  return raus
}

/* ---------- Selbstprobe --------------------------------------------------- */

/**
 * Gepflanzt wird eine Ansicht, die niemand liest, und eine, die von einer
 * gelesenen Ansicht gelesen wird. Die erste muss auffallen, die zweite nicht —
 * sonst meldet das Werkzeug jede Zwischenstufe der Kette als tot.
 */
export async function selbstprobe({ db = 'demo' } = {}) {
  const p = kopie(db, 'mw_b1_probe')
  /* Die Namen werden zusammengesetzt, damit sie in diesem Quelltext nicht als
     ganzes Wort vorkommen. Sonst hielte die Datei ihre eigenen Probeobjekte
     am Leben — der Fehler, an dem die erste Fassung gescheitert ist. */
  const T = 'v_' + 'probe' + '_ohne_leser'
  const Z = 'v_' + 'probe' + '_zwischenstufe'
  const W = 'v_' + 'probe' + '_wurzel'
  const F = 'f_' + 'probe' + '_nur_bedingung'

  tue(p, `create view ${T} as select 1 as x;
          create view ${Z} as select 2 as y;
          create view ${W} as select * from ${Z};
          create function ${F}(z numeric) returns boolean language sql immutable
            as 'select z >= 0';
          alter table palette add constraint probe_bedingung check (${F}(brutto_kg)) not valid`)

  const sichten = KATALOG.sichten(p)
  const funktionen = KATALOG.funktionen(p)
  const tabellen = KATALOG.tabellen(p)
  const namen = [...sichten.map(s => s.name), ...funktionen.map(f => f.name), ...tabellen.map(t => t.name)]
  const liest = graph(p, namen)

  const teile = quelltext()
  teile.push({ pfad: 'probe', was: 'Oberfläche', text: `supabase.from('${W}')` })

  const intern = vonDerDatenbankGerufen(p, namen)
  const lebt = new Set(namen.filter(n => erwaehntIn(teile, n).length || intern.has(n)))
  let gewachsen = true
  while (gewachsen) {
    gewachsen = false
    for (const n of [...lebt])
      for (const k of liest.get(n) ?? [])
        if (!lebt.has(k)) { lebt.add(k); gewachsen = true }
  }

  const totErkannt = !lebt.has(T)                 // muss auffallen
  const zwischenstufeVerschont = lebt.has(Z)      // darf nicht auffallen
  const bedingungVerschont = lebt.has(F)          // von der Datenbank gerufen

  tue(p, `alter table palette drop constraint if exists probe_bedingung;
          drop view if exists ${W}; drop view if exists ${Z}; drop view if exists ${T};
          drop function if exists ${F}(numeric)`)
  return totErkannt && zwischenstufeVerschont && bedingungVerschont
}
