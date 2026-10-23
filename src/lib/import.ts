/**
 * Erkennt und liest Palettendaten aus dem Kürbis-Erntejournal (der bestehenden
 * Wareneingang-App). Quelle ist deren Google Sheet, Tab „Ertragsjournal".
 *
 * Bewusst tolerant: Die Daten kommen entweder eingefügt (Tab- oder
 * Semikolon-getrennt) oder als veröffentlichte CSV. Das Journal hat in Zeile 1
 * einen verbundenen Hinweistext, in Zeile 2 die Köpfe, ab Zeile 3 die Daten —
 * die Kopfzeile wird deshalb gesucht, nicht als erste Zeile angenommen.
 *
 * Verknüpfung zur Charge: Das Journal führt keine Chargennummer, wohl aber
 * Schlag und Sorte. Genau daraus ist die Charge eindeutig (Registry §7). Gibt es
 * doch eine Chargennummer-Spalte, hat sie Vorrang.
 *
 * Reine Funktionen ohne Netz/DOM, damit sie testbar bleiben.
 */

export interface ChargeRef { nr: number; schlag: string; sorte: string }
/** 0122: wie ein Schlag anderswo heisst (schlag_alias) — Inauen ist Oettli, Trüb ist Trüeb. */
export interface SchlagAlias { alias: string; schlag: string }

export interface RohPalette {
  charge_nr: number
  eingangsdatum: string        // ISO
  brutto_kg: number
  kisten: number | null
  gebindeart: string | null
  extern_id: string
}

export interface ImportBericht {
  paletten: RohPalette[]
  probleme: string[]
  quelle: 'chargennummer' | 'schlag-sorte' | null
  kopf: string[]
  /** Runde AS: Chargen, die das Journal mit Nummer, Schlag und Sorte nennt, die App aber noch nicht kennt —
   *  sie werden vor den Paletten angelegt (Saison = Jahr der ersten Palette). */
  neueChargen: (ChargeRef & { saison: number })[]
}

/** Erkennt den Trenner und zerlegt in Zellen; einfache Anführungszeichen-Regel. */
export function tabelleLesen(text: string): string[][] {
  const zeilen = text.replace(/\r\n/g, '\n').split('\n')
  const trenner = erkenneTrenner(zeilen)
  return zeilen
    .map(z => zerlege(z, trenner))
    .filter(z => z.some(feld => feld.trim() !== ''))
}

function erkenneTrenner(zeilen: string[]): string {
  // Nicht die erste Zeile befragen — im Journal ist das ein Hinweistext ohne
  // Trenner. Stattdessen den Trenner nehmen, der über alle Zeilen am häufigsten
  // vorkommt. Tab vor Semikolon vor Komma, wenn es gleich steht.
  let bester = ',', meiste = 0
  for (const t of ['\t', ';', ',']) {
    const summe = zeilen.reduce((n, z) => n + z.split(t).length - 1, 0)
    if (summe > meiste) { meiste = summe; bester = t }
  }
  return bester
}

/** Zerlegt eine Zeile und beachtet Felder in Anführungszeichen (CSV mit Kommas). */
function zerlege(zeile: string, trenner: string): string[] {
  const felder: string[] = []
  let feld = ''
  let inQuotes = false
  for (let i = 0; i < zeile.length; i++) {
    const c = zeile[i]
    if (inQuotes) {
      if (c === '"' && zeile[i + 1] === '"') { feld += '"'; i++ }
      else if (c === '"') inQuotes = false
      else feld += c
    } else if (c === '"') {
      inQuotes = true
    } else if (c === trenner) {
      felder.push(feld); feld = ''
    } else {
      feld += c
    }
  }
  felder.push(feld)
  return felder.map(f => f.trim())
}

/** Synonyme je Feld; alles kleingeschrieben und ohne Sonderzeichen verglichen. */
const SPALTEN: Record<string, string[]> = {
  chargennummer: ['charge', 'chargennummer', 'chargenr', 'charge nr'],
  eingangsdatum: ['datum', 'eingangsdatum', 'eingang'],
  schlag: ['schlag', 'feld', 'standort'],
  sorte: ['sorte'],
  brutto_kg: ['gewicht brutto', 'gewicht brutto kg', 'brutto', 'bruttogewicht', 'gewicht'],
  kisten: ['anzahl gebinde', 'anzahl kisten', 'kisten', 'kistenzahl', 'gebinde'],
  gebindeart: ['gebindeart', 'gebindeart leer g2', 'gebinde art', 'art'],
  extern_id: ['id app', 'id', 'palettenkennung', 'kennung'],
}

/** Vergleichsform: klein, Satzzeichen weg, Umlaute bleiben Umlaute (22. Oktober). Bis hier
 *  wurde jeder Buchstabe ausserhalb a–z ein Leerzeichen: Ein ü, das als u + Trema ankommt
 *  (je nach Tastatur oder Programm), wurde „tru eb" statt „tr eb", und die Zeile von Trüeb
 *  fand ihre Charge nicht; „Trüb" und „Tröb" waren dasselbe. Jetzt erst NFC, dann alle
 *  Buchstaben behalten. */
const norm = (s: string) => s.normalize('NFC').toLowerCase().replace(/[^\p{L}\p{N} ]+/gu, ' ').replace(/\s+/g, ' ').trim()

function findeSpalte(kopf: string[], feld: string): number {
  const namen = SPALTEN[feld]
  // exakter Treffer vor Teiltreffer, damit „Sorte" nicht in „Gebindeart" fällt
  const nk = kopf.map(norm)
  for (const name of namen) { const i = nk.indexOf(name); if (i !== -1) return i }
  for (let i = 0; i < nk.length; i++) if (namen.some(n => nk[i].startsWith(n))) return i
  return -1
}

/** Sucht die Kopfzeile (bis zu 6 Zeilen weit) — im Journal steht davor ein Hinweis. */
function findeKopf(zeilen: string[][]): number {
  for (let i = 0; i < Math.min(zeilen.length, 6); i++) {
    const nk = zeilen[i].map(norm)
    const hatSchlag = nk.some(z => z === 'schlag' || z === 'feld')
    const hatSorte = nk.some(z => z === 'sorte')
    const hatCharge = nk.some(z => SPALTEN.chargennummer.includes(z))
    if ((hatSchlag && hatSorte) || hatCharge) return i
  }
  return 0
}

export function datumLesen(roh: string): string | null {
  const t = roh.trim()
  if (/^\d{4}-\d{2}-\d{2}/.test(t)) return t.slice(0, 10)
  const m = t.match(/^(\d{1,2})[.\/](\d{1,2})[.\/](\d{2,4})/)
  if (!m) return null
  const jahr = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])
  const p = (n: string) => n.padStart(2, '0')
  const monat = Number(m[2]), tag = Number(m[1])
  if (monat < 1 || monat > 12 || tag < 1 || tag > 31) return null
  return `${jahr}-${p(m[2])}-${p(m[1])}`
}

/** Leere Gebindeart = Standard „G2" (so ist die Spalte im Journal gemeint).
 *  Runde AS: Paloxen, wie man sie schreibt („Holzpalox", „Palox Holz", „Plastik-Palox"),
 *  heissen wie in der Gebinde-Tabelle — sonst hätte jede Schreibweise ihr eigenes Gebinde ohne Tara. */
export function gebindeNormalisieren(roh: string | null | undefined): string {
  const t = (roh ?? '').trim()
  if (t === '') return 'G2'
  const k = t.toLowerCase().replace(/[^a-zäöü]+/g, '')
  if (/pal+o[xcks]+/.test(k)) {
    if (/holz/.test(k)) return 'Holz Palox'
    if (/plastik|kunststoff/.test(k)) return 'Plastik Palox'
  }
  return t
}

/**
 * 0122: Der Betrieb, 23. Oktober: „Es gibt nur einen — Trüb ist Trüeb", und
 * Oettli heisst im Bio-Perigon Inauen. Ein Name, den schlag_alias kennt, wird
 * zum Namen des Schlags, auf beiden Seiten: im Journal und im Register. So
 * findet „Trüb · Amoro" die Charge von Trüeb, und eine neue Charge wird unter
 * dem einen Namen angelegt, nicht unter dem zweiten.
 */
export function schlagNamen(aliase: SchlagAlias[]): (name: string) => string {
  const von = new Map(aliase.map(a => [norm(a.alias), a.schlag.trim()]))
  return name => von.get(norm(name)) ?? name.trim()
}

export function importErkennen(text: string, chargen: ChargeRef[], aliase: SchlagAlias[] = []): ImportBericht {
  const zeilen = tabelleLesen(text)
  if (zeilen.length < 2) {
    return { paletten: [], probleme: ['Zu wenig Zeilen — Kopf und mindestens eine Datenzeile nötig.'],
             quelle: null, kopf: [], neueChargen: [] }
  }

  const kopfIdx = findeKopf(zeilen)
  const kopf = zeilen[kopfIdx]
  const idx = Object.fromEntries(Object.keys(SPALTEN).map(f => [f, findeSpalte(kopf, f)]))

  const perCharge = idx.chargennummer !== -1
  const perSchlagSorte = idx.schlag !== -1 && idx.sorte !== -1
  if (idx.eingangsdatum === -1 || idx.brutto_kg === -1 || (!perCharge && !perSchlagSorte)) {
    return {
      paletten: [], quelle: null, kopf, neueChargen: [],
      probleme: [`Nötige Spalten nicht gefunden. Erkannt: ${kopf.join(', ')}. `
        + 'Gebraucht werden Datum, Brutto und entweder eine Chargennummer oder Schlag + Sorte.'],
    }
  }

  // Charge-Nachschlag über Schlag+Sorte; ein zweiter Name des Schlags zählt als der eine (0122)
  const schlagName = schlagNamen(aliase)
  const schluessel = (schlag: string, sorte: string) => `${norm(schlagName(schlag))}|${norm(sorte)}`
  const chargeVon = new Map<string, number>()
  for (const c of chargen) chargeVon.set(schluessel(c.schlag, c.sorte), c.nr)
  const bekannteNr = new Set(chargen.map(c => c.nr))

  const paletten: RohPalette[] = []
  const probleme: string[] = []
  const laufNr = new Map<string, number>()
  const neu = new Map<number, ChargeRef & { saison: number }>()

  for (let r = kopfIdx + 1; r < zeilen.length; r++) {
    const f = zeilen[r]
    const zeileNr = r + 1
    const brutto = zahl(f[idx.brutto_kg])
    // Datenzeilen erkennt das Journal an Brutto als Zahl > 0 — so fallen
    // Hinweiszeilen, Summenzeilen und Leerzeilen von selbst heraus.
    if (brutto === null || brutto <= 0) continue

    let chargeNr: number | null = null
    if (perCharge) {
      const nr = Number((f[idx.chargennummer] ?? '').trim())
      if (bekannteNr.has(nr) || neu.has(nr)) chargeNr = nr
      // Runde AS (Oettli 1719, Trüb 1763): eine neue Nummer mit Schlag und
      // Sorte ist eine neue Charge — sie wird angelegt, statt die Zeile zu
      // verwerfen. Ohne Schlag oder Sorte bleibt sie ein Problem: anlegen
      // kann sie dann nur der Betriebsleiter unter Stammdaten → Chargen.
      // Kennt die App Schlag und Sorte schon unter einer anderen Nummer, ist
      // es eher ein Tippfehler in der Nummer: dann wie bisher über Schlag und
      // Sorte zuordnen, nie eine zweite Charge daneben anlegen.
      else if (Number.isInteger(nr) && nr > 0 && nr < 100000
               && !chargeVon.has(schluessel((idx.schlag !== -1 ? f[idx.schlag] : '') ?? '', (idx.sorte !== -1 ? f[idx.sorte] : '') ?? ''))) {
        const schlag = schlagName(idx.schlag !== -1 ? f[idx.schlag] ?? '' : '')
        const sorte = (idx.sorte !== -1 ? f[idx.sorte] ?? '' : '').trim()
        const datum = datumLesen(f[idx.eingangsdatum] ?? '')
        if (schlag && sorte && datum) {
          neu.set(nr, { nr, schlag, sorte, saison: Number(datum.slice(0, 4)) })
          chargeNr = nr
        } else {
          probleme.push(`Zeile ${zeileNr}: Charge ${nr} ist neu — ${!schlag || !sorte ? 'Schlag oder Sorte fehlt im Journal' : 'Datum nicht lesbar'}; unter Stammdaten → Chargen anlegen`)
          continue
        }
      }
    }
    if (chargeNr === null && perSchlagSorte) {
      const schlag = f[idx.schlag] ?? '', sorte = f[idx.sorte] ?? ''
      chargeNr = chargeVon.get(schluessel(schlag, sorte)) ?? null
      if (chargeNr === null && (schlag.trim() || sorte.trim())) {
        probleme.push(`Zeile ${zeileNr}: keine Charge für „${schlag.trim()} · ${sorte.trim()}" — unter Stammdaten → Chargen mit Nummer anlegen, Schlag und Sorte wie im Journal`)
        continue
      }
    }
    if (chargeNr === null) {
      probleme.push(`Zeile ${zeileNr}: Charge nicht bestimmbar`)
      continue
    }

    const datum = datumLesen(f[idx.eingangsdatum] ?? '')
    if (!datum) { probleme.push(`Zeile ${zeileNr}: Datum „${f[idx.eingangsdatum]}" nicht lesbar`); continue }

    const kisten = idx.kisten !== -1 ? zahl(f[idx.kisten]) : null
    const gebinde = idx.gebindeart !== -1 ? gebindeNormalisieren(f[idx.gebindeart]) : null

    // Stabile Kennung: die App-ID aus Spalte K, sonst aus dem Zeileninhalt.
    let extern: string
    const kennung = idx.extern_id !== -1 ? (f[idx.extern_id] ?? '').trim() : ''
    if (kennung) {
      extern = `journal:${kennung}`
    } else {
      // Die Ersatz-Kennung darf NUR aus dem bestehen, was eine Zeile
      // ausmacht — nicht aus allem, was zufällig danebensteht.
      //
      // Vorher standen Kistenzahl und Gebindeart mit drin. Das ging gut,
      // solange das Erntejournal keine Kistenspalte hatte. Bekommt es eine
      // (genau darum geht es in dieser Runde), ändert sich für JEDE bereits
      // importierte Zeile die Kennung: `onConflict: 'extern_id'` findet
      // nichts mehr, und der zweite Import legt jede Palette ein zweites
      // Mal an. Die Eingangsmasse der Saison verdoppelt sich — ohne eine
      // einzige Fehlermeldung.
      //
      // Charge, Datum und Bruttogewicht identifizieren eine Palette; die
      // laufende Nummer trennt gleiche Zeilen desselben Tages. Was sonst
      // noch in der Zeile steht, darf die Kennung nicht bewegen.
      const kern = [chargeNr, datum, brutto].join('|')
      const n = (laufNr.get(kern) ?? 0) + 1
      laufNr.set(kern, n)
      extern = `${kern}#${n}`
    }

    paletten.push({ charge_nr: chargeNr, eingangsdatum: datum, brutto_kg: brutto,
                    kisten, gebindeart: gebinde, extern_id: extern })
  }

  return { paletten, probleme, kopf, neueChargen: [...neu.values()],
           quelle: perCharge ? 'chargennummer' : 'schlag-sorte' }
}

function zahl(roh: string | undefined): number | null {
  if (roh === undefined) return null
  const t = roh.trim().replace(/['\s]/g, '').replace(',', '.')
  if (t === '') return null
  const n = Number(t)
  return Number.isFinite(n) ? n : null
}

/**
 * Was der Abgleich beim Öffnen des Dashboards sagt (22. Oktober). Der Betrieb:
 * „Ötli und Trüeb … im Google Sheet sind sie drin, aber sie kommen nicht in der
 * Kürbis-App an." Gab es keine neue Palette, schwieg der Abgleich — auch wenn
 * Zeilen keiner Charge zugeordnet werden konnten. Jetzt sagt er es, mit dem
 * ersten Grund (ohne Zeilennummer, gleiche Gründe einmal).
 */
export function abgleichMeldung(neu: number, angelegt: number[], probleme: string[]): { art: 'gut' | 'warnung'; text: string } | null {
  const gruende = [...new Set(probleme.map(p => p.replace(/^Zeile \d+:\s*/, '')))]
  const beispiel = gruende.length ? ` (${gruende[0]}${gruende.length === 2 ? ' — und ein weiterer Grund' : gruende.length > 2 ? ` — und ${gruende.length - 1} weitere Gründe` : ''})` : ''
  const zeilen = (n: number) => n === 1 ? 'eine Zeile' : `${n} Zeilen`
  if (neu > 0) {
    return { art: 'gut', text: `${neu === 1 ? '1 neue Palette' : `${neu} neue Paletten`} aus dem Erntejournal übernommen`
      + (angelegt.length ? ` · ${angelegt.length === 1 ? 'eine neue Charge' : `${angelegt.length} neue Chargen`} angelegt (${angelegt.join(', ')})` : '')
      + (probleme.length ? ` · ${zeilen(probleme.length)} ohne Charge${beispiel}` : '')
      + '. Sie zählen ab der nächsten Rechnung — heute Nacht oder mit „Neu rechnen".' }
  }
  if (probleme.length) {
    return { art: 'warnung', text: `Im Erntejournal ${probleme.length === 1 ? 'steht eine Zeile' : `stehen ${probleme.length} Zeilen`}, die die App keiner Charge zuordnen kann${beispiel}. ${probleme.length === 1 ? 'Sie kommt' : 'Sie kommen'} erst an, wenn es die Charge gibt.` }
  }
  return null
}
