/**
 * Der Plausibilitätsdurchgang (Runde AA): alle Rohdaten einer Saison gegen
 * einfache, erklärbare Regeln — nicht die Rechnung der Datenbank, sondern die
 * Fragen, die ein Mensch stellen würde, der die Zettel durchblättert:
 * „Kann das sein?"
 *
 * Der Betrieb: „meine Idee ist es, dass er nicht nur die Teilpaletten
 * anschaut, sondern alle Daten mal auf Plausibilität testet."
 *
 * Reine Rechnung über JSON-Tabellen (docs/betrieb/rohdaten/ vom Abzug, oder
 * pruefstand/daten/ aus der Demo). Jeder Befund nennt die Prüfung, die
 * Schwere, wo es steht, die Zahlen und warum es verdächtig ist. Was hier
 * herauskommt, ist ein Kandidat — die Runde am Programm liest ihn und
 * schreibt die Zweitmeinung; nichts wird von selbst geändert.
 *
 * Die Regeln sind bewusst grob (Grenzen als Konstanten oben). Sie sollen
 * finden, nicht urteilen. Was die Datenbank schon meldet (Auffälligkeiten),
 * wird hier nicht wiederholt, sondern ergänzt: Teilpaletten, Gewicht je
 * Kiste, doppelte Zeilen, Daten in der falschen Reihenfolge, Lieferungen
 * über dem Eingang, Zahlendreher.
 *
 * Runde AC (erste Zweitmeinung über echte Daten): der Durchgang kennt die
 * Vervielfachung des Journals („n Paletten gleich"), Gebinde ohne Tara, die
 * Teilpalette von Hand (Dreisatz) und mit vollem Zettel, den Zettel auf der
 * fremden Charge, Lieferungen vor dem Eingang, Sortierläufe ohne Eingang,
 * Lieferungen ohne Charge und Arbeiten, die offen bleiben.
 */

/** Welche Tabellen der Abzug als Rohdaten holt — und welche Spalten davon.
 *  Nicht dabei: Kundennamen, Preise, freie Texte, Personen (AB: Betriebsdaten
 *  bleiben draussen). */
export const ROHTABELLEN = {
  charge: ['nr', 'sorte', 'schlag', 'saison', 'ernte_abgeschlossen_ts'],
  palette: ['id', 'charge_nr', 'eingangsdatum', 'brutto_kg', 'kisten', 'gebindeart', 'extern_id', 'quelle'],
  auftrag: ['id', 'weg', 'station', 'charge_nr', 'start_ts', 'ende_ts', 'status', 'abgebrochen_ts', 'ist_fax',
            'kaliber_idx', 'kistensystem', 'soll_kg_pro_kiste', 'stueck_je_kiste', 'paletten_gesamt',
            'fertige_paletten_gesamt', 'palox_unbekannt', 'tage_seit_waschen', 'geplante_paletten'],
  auftrag_palette: ['id', 'auftrag_id', 'palette_id', 'eingangsdatum', 'brutto_zettel_kg', 'sortierdatum', 'kisten', 'gebindeart', 'wiegung_id', 'ts'],
  auftrag_gebinde: ['id', 'auftrag_id', 'kaliber_idx', 'anzahl', 'sortierdatum', 'datum_fehlt', 'ts'],
  schimmel_messung: ['id', 'auftrag_id', 'kg', 'palox_stand_kg', 'palox_geleert', 'palox_nach_leeren', 'brutto_kg', 'kisten', 'gebindeart', 'mit_palette', 'gemessen', 'ts'],
  ausschuss_messung: ['id', 'auftrag_id', 'art', 'kg', 'brutto_kg', 'kisten', 'gebindeart', 'mit_palette', 'gemessen', 'ts'],
  verdunstung_wiegung: ['id', 'auftrag_id', 'charge_nr', 'palette_id', 'eingangsdatum', 'brutto_damals_kg', 'brutto_jetzt_kg',
                        'kisten', 'gebindeart', 'sichtbar_schimmel', 'gemessen', 'wiege_ts', 'kuerbisse_pro_kiste', 'faul_kg'],
  ausgang_wiegung: ['id', 'auftrag_id', 'charge_nr', 'brutto_kg', 'kisten', 'gebindeart', 'kuerbisse_pro_kiste', 'kaliber_idx', 'voll', 'gemessen', 'ts'],
  kontrollpalette: ['id', 'charge_nr', 'palette_id', 'kennzeichen', 'angelegt_ts', 'beendet_ts', 'beendet_grund', 'eingangsdatum', 'brutto_eingang_kg'],
  kontrollpalette_wiegung: ['id', 'kontrollpalette_id', 'brutto_kg', 'kisten', 'gebindeart', 'sichtbar_schimmel', 'wiege_ts'],
  lieferung: ['id', 'datum', 'charge_nr', 'sorte', 'kg', 'kisten', 'gebindeart', 'ziel', 'ts'],
  sortier_lauf: ['id', 'charge_nr', 'auftrag_id', 'datei_zeit', 'n_roh', 'n_overflow', 'n_klein', 'n_dubletten', 'n_gueltig', 'art', 'sortiertag', 'sortiertag_quelle'],
  gebinde: ['art', 'tara_kg_pro_kiste', 'tara_kg_palette'],
  auswertung_stand: ['id', 'geaendert_ts', 'berechnet_ts', 'dauer_ms'],
}

// Grenzen — grob, aus der Erfahrung mit G2-Kisten und Euro-Paletten.
export const GRENZEN = {
  kgJeKisteMin: 4, kgJeKisteMax: 30,      // netto je Kiste, Eingang und fertige Paletten
  kistenMax: 66,                           // 12 Lagen à 5 sind der Regelfall (60); 13 Lagen kommen vor
                                           // (Palette 6904, Saison 2026: 65 Kisten, Gewicht je Kiste passt)
  zettelDreisatzKg: 1,                     // Teilpalette von Hand: Zettel = Palette × Kisten/Kisten, auf 1 kg genau
  offenTage: 2,                            // eine Arbeit, die länger offen steht, ist vergessen oder versehentlich
  zettelAbweichung: 0.4,                   // Zettelgewicht gegen das Chargenmittel
  rateMaxProTag: 0.01,                     // Verdunstung: darüber ist es keine
  schwererAb: 0.005,                       // mehr als ein halbes Prozent schwerer: keine Verdunstung, ein Fehler
  paloxKgMax: 1000,                        // mehr Faules hat kein Palox
  ausschussKisteMax: 60,                   // eine einzelne Kiste
  arbeitStundenMax: 16,
  saisonVorlaufTage: 60,
}

const tag = x => (x ? String(x).slice(0, 10) : null)
const tage = (a, b) => (Date.parse(tag(a)) - Date.parse(tag(b))) / 86400000
const r1 = x => Math.round(x * 10) / 10
const r3 = x => Math.round(x * 1000) / 1000

function taraVon(gebinde) {
  const m = new Map((gebinde ?? []).map(g => [g.art, g]))
  return (art, mitPalette = true) => {
    const g = m.get(art)
    // „bekannt": die Stammdaten kennen das Leergewicht dieses Gebindes. Ein
    // Holz-Palox ohne Tara (Saison 2026) ist nicht bekannt — sein Netto ist
    // geschätzt, und ein Urteil „je Kiste" wäre keins.
    const bekannt = !!g && g.tara_kg_pro_kiste != null
    const q = g ?? m.get('G2') ?? { tara_kg_pro_kiste: 1.5, tara_kg_palette: 25 }
    return { kiste: Number(q.tara_kg_pro_kiste ?? 1.5), palette: mitPalette ? Number(q.tara_kg_palette ?? 25) : 0, bekannt }
  }
}
/** Das Journal sagt „n Paletten gleich": der Import legt n Zeilen an, extern_id
 *  „…#2", „…#3" … Solche Zeilen sind keine doppelte Erfassung, sie sind das
 *  Journal. Gibt die Basis zurück, wenn es eine Vervielfachung ist. */
const journalBasis = p => { const m = /^(.*)#\d+$/.exec(String(p?.extern_id ?? '')); return m ? m[1] : null }
const netto = (brutto, kisten, t, mitPalette = true) =>
  brutto == null || kisten == null ? null : Number(brutto) - Number(kisten) * t.kiste - (mitPalette ? t.palette : 0)

/**
 * Alle Prüfungen über die Tabellen. `heute` als ISO-Tag, damit der Durchgang
 * reproduzierbar ist. Fehlende Tabellen zählen als leer und werden genannt.
 */
export function durchgang(d, heute) {
  const T = n => Array.isArray(d[n]) ? d[n] : []
  const fehlt = Object.keys(ROHTABELLEN).filter(n => !Array.isArray(d[n]))
  const tara = taraVon(T('gebinde'))
  const befunde = []
  const melden = (pruefung, schwere, wo, werte, warum) => befunde.push({ pruefung, schwere, wo, werte, warum })

  const paletten = new Map(T('palette').map(p => [p.id, p]))
  const auftraege = new Map(T('auftrag').map(a => [a.id, a]))
  const chargen = new Map(T('charge').map(c => [c.nr, c]))
  const arbeitText = id => { const a = auftraege.get(id); return a ? `Arbeit ${id} (${a.station}, Charge ${a.charge_nr}, ${tag(a.start_ts)})` : `Arbeit ${id}` }

  // ---- 1. Teilpalette: weniger (oder mehr) Kisten gewogen als am Eingang ----
  for (const w of T('verdunstung_wiegung')) {
    const p = w.palette_id != null ? paletten.get(w.palette_id) : null
    if (!p || w.kisten == null || p.kisten == null) continue
    if (w.kisten < p.kisten) {
      const t = tara(w.gebindeart)
      const nd = netto(w.brutto_damals_kg, w.kisten, t), nj = netto(w.brutto_jetzt_kg, w.kisten, t)
      const anteil = w.kisten / p.kisten
      melden('Teilpalette', 'hoch', `Wägung ${w.id} · ${arbeitText(w.auftrag_id)} · Charge ${w.charge_nr}`,
        { kisten_gewogen: w.kisten, kisten_eingang: p.kisten, zettel_brutto_kg: Number(p.brutto_kg), brutto_damals_kg: Number(w.brutto_damals_kg), brutto_jetzt_kg: Number(w.brutto_jetzt_kg),
          netto_damals_ganz_kg: nd, netto_damals_anteilig_kg: nd == null ? null : r1(nd * anteil), netto_jetzt_kg: nj },
        `Nur ${w.kisten} von ${p.kisten} Kisten gewogen, aber das Zettelgewicht gilt für die ganze Palette. Anteilig gerechnet wäre der Bezug ${nd == null ? '?' : r1(nd * anteil)} kg statt ${nd} kg.`)
    } else if (w.kisten > p.kisten) {
      melden('Teilpalette', 'hoch', `Wägung ${w.id} · ${arbeitText(w.auftrag_id)} · Charge ${w.charge_nr}`,
        { kisten_gewogen: w.kisten, kisten_eingang: p.kisten },
        `Mehr Kisten gewogen (${w.kisten}) als am Eingang gezählt (${p.kisten}) — Palette verwechselt, oder eine Zählung ist falsch.`)
    }
  }

  // ---- 2. Eingang: Gewicht je Kiste, Kistenzahl -----------------------------
  const kgJeKisteJeCharge = new Map()
  const ohneTara = new Map()
  for (const p of T('palette')) {
    const t = tara(p.gebindeart)
    if (!t.bekannt) {
      const o = ohneTara.get(p.gebindeart ?? '—') ?? { n: 0, brutto_kg: 0, chargen: new Set() }
      o.n++; o.brutto_kg += Number(p.brutto_kg ?? 0); o.chargen.add(p.charge_nr); ohneTara.set(p.gebindeart ?? '—', o)
      continue
    }
    const n = netto(p.brutto_kg, p.kisten, t)
    if (p.kisten != null && (p.kisten < 1 || p.kisten > GRENZEN.kistenMax)) {
      melden('Eingang Kisten', 'mittel', `Palette ${p.id} · Charge ${p.charge_nr} · ${tag(p.eingangsdatum)}`, { kisten: p.kisten, brutto_kg: Number(p.brutto_kg) },
        `${p.kisten} Kisten auf einer Palette — das gibt es nicht; vermutlich vertippt.`)
    } else if (n != null && p.kisten > 0) {
      const je = n / p.kisten
      if (je < GRENZEN.kgJeKisteMin || je > GRENZEN.kgJeKisteMax) {
        melden('Eingang Gewicht je Kiste', 'mittel', `Palette ${p.id} · Charge ${p.charge_nr} · ${tag(p.eingangsdatum)}`,
          { brutto_kg: Number(p.brutto_kg), kisten: p.kisten, netto_je_kiste_kg: r1(je) },
          `${r1(je)} kg netto je Kiste — ausserhalb von ${GRENZEN.kgJeKisteMin}–${GRENZEN.kgJeKisteMax} kg. Einheit (kg statt g?), Zahlendreher oder falsche Kistenzahl.`)
      } else {
        const l = kgJeKisteJeCharge.get(p.charge_nr) ?? []; l.push(je); kgJeKisteJeCharge.set(p.charge_nr, l)
      }
    }
  }
  for (const [art, o] of ohneTara)
    melden('Gebinde ohne Tara', 'mittel', `Gebindeart ${art}`, { paletten: o.n, brutto_kg: r1(o.brutto_kg), chargen: [...o.chargen].join(', ') },
      `${o.n} Paletten (${r1(o.brutto_kg)} kg brutto) in einem Gebinde, dessen Leergewicht die Stammdaten nicht kennen — ihr Netto ist geschätzt, nicht gewogen. Unter Betrieb → Stammdaten die Tara eintragen; ein Palox zählt als eine „Kiste" mit seinem eigenen Leergewicht.`)

  // ---- 3. Doppelte Eingangspaletten — mehr Gleichstände, als der Zufall erklärt ----
  // Bei 60 Paletten eines Tages mit Gewichten zwischen 460 und 500 kg sind
  // Gleichstände normal: Saison 2026 hatte 750 Paare gleicher Zettel, rund 590
  // davon erwartet der Zufall (n·(n−1)/2 geteilt durch die Spannweite). Ein
  // einzelnes Paar ist darum kein Kandidat (Runde AC — vorher waren es 518
  // Zeilen Rauschen). Ein Tag mit deutlich mehr Paaren als erwartet ist einer:
  // abgeschrieben statt gewogen, oder Zeilen doppelt erfasst. Vervielfachungen
  // des Journals („n Paletten gleich", extern_id …#n) zählen gar nicht mit.
  const jeTag = new Map()
  let vervielfacht = 0
  for (const p of T('palette')) {
    if (journalBasis(p) != null) { vervielfacht++; continue }
    const k = `${p.charge_nr}|${tag(p.eingangsdatum)}`
    const l = jeTag.get(k) ?? []; l.push(p); jeTag.set(k, l)
  }
  for (const [k, l] of jeTag) {
    if (l.length < 2) continue
    const jeKisten = new Map()
    for (const p of l) { const g = jeKisten.get(p.kisten) ?? []; g.push(Number(p.brutto_kg)); jeKisten.set(p.kisten, g) }
    let paare = 0, erwartet = 0; const gleich = []
    for (const [kisten, ws] of jeKisten) {
      const cnt = new Map(); for (const w of ws) cnt.set(w, (cnt.get(w) ?? 0) + 1)
      for (const [w, c] of cnt) if (c > 1) { paare += c * (c - 1) / 2; gleich.push(`${c}×${w} kg/${kisten}`) }
      // Paletten eines Tages streuen um mindestens ±10 kg; eine Reihe identischer
      // Gewichte ist keine Streuung, sondern Abschreiben — darum mindestens 20.
      const spann = Math.max(Math.max(...ws) - Math.min(...ws) + 1, 20)
      erwartet += ws.length * (ws.length - 1) / 2 / spann
    }
    if (paare > 2 * erwartet + 3) {
      const [nr, t] = k.split('|')
      melden('Doppelte Palette', 'niedrig', `Charge ${nr} · ${t}`, { paletten: l.length, paare_gleich: paare, paare_durch_zufall: r1(erwartet), gleich: gleich.slice(0, 8).join(', ') },
        `${l.length} Paletten an einem Tag, davon ${paare} Paare mit gleichem Gewicht und gleicher Kistenzahl — der Zufall erklärt etwa ${r1(erwartet)}. Abgeschrieben statt gewogen, oder Zeilen doppelt erfasst? (${gleich.slice(0, 8).join(', ')})`)
    }
  }
  const hinweise = []
  if (vervielfacht) hinweise.push(`${vervielfacht} Paletten sind Vervielfachungen einer Journalzeile („n Paletten gleich", extern_id …#n) — keine Kandidaten.`)

  // ---- 4. Zettelgewicht gegen das Chargenmittel -----------------------------
  const mittelJeCharge = new Map([...kgJeKisteJeCharge].map(([nr, l]) => [nr, l.reduce((a, b) => a + b, 0) / l.length]))
  for (const z of T('auftrag_palette')) {
    if (z.brutto_zettel_kg == null || z.palette_id != null) continue
    const a = auftraege.get(z.auftrag_id); if (!a) continue
    const m = mittelJeCharge.get(a.charge_nr); if (m == null) continue
    const t = tara(z.gebindeart ?? 'G2')
    const kisten = z.kisten ?? 36
    const je = netto(z.brutto_zettel_kg, kisten, t) / kisten
    if (Math.abs(je - m) / m > GRENZEN.zettelAbweichung) {
      melden('Zettelgewicht', 'mittel', `Zettel ${z.id} · ${arbeitText(z.auftrag_id)} · ${tag(z.eingangsdatum)}`,
        { zettel_brutto_kg: Number(z.brutto_zettel_kg), kisten_angenommen: kisten, netto_je_kiste_kg: r1(je), charge_mittel_je_kiste_kg: r1(m) },
        `${r1(je)} kg je Kiste laut Zettel gegen ${r1(m)} kg im Mittel der Charge — Zahlendreher, oder eine Palette mit anderer Kistenzahl.`)
    }
  }

  // ---- 4b. Zettel gegen das Journal: warum die Datenbank die Palette nicht findet ----
  // Die Datenbank sucht zu jedem Zettel die Palette im Journal (Charge, Gewicht,
  // Kisten); findet sie keine, rechnet sie mit Kisten × Tara (0090) und meldet
  // „Zettelgewicht". Hier steht das WARUM — die Muster der Saison 2026: die
  // Halle rechnet Teilpaletten von Hand im Dreisatz um (235 kg für 18 von 36
  // Kisten einer 470-kg-Palette), oder sie schreibt den vollen Zettel zu
  // weniger Kisten (473 kg für 16 Kisten), vertippt die Kistenzahl, zählt eine
  // Palette zweimal — oder die Palette gehört zu einer anderen Charge derselben
  // Sorte, weil die Arbeit auf die falsche Charge gebucht ist.
  const palJeCharge = new Map()
  for (const p of T('palette')) { const l = palJeCharge.get(p.charge_nr) ?? []; l.push(p); palJeCharge.set(p.charge_nr, l) }
  const sorteVon = nr => chargen.get(nr)?.sorte
  const zettelJeArbeitKg = new Map()
  const teilZettelWiegung = new Set()
  for (const z of T('auftrag_palette')) {
    if (z.brutto_zettel_kg == null || z.kisten == null) continue
    const a = auftraege.get(z.auftrag_id); if (!a) continue
    const kg = Number(z.brutto_zettel_kg)
    const eigene = palJeCharge.get(a.charge_nr) ?? []
    const zk = `${z.auftrag_id}|${kg}`; zettelJeArbeitKg.set(zk, (zettelJeArbeitKg.get(zk) ?? 0) + 1)
    if (eigene.some(p => Number(p.brutto_kg) === kg && p.kisten === z.kisten)) continue
    const wo = `Zettel ${z.id} · ${arbeitText(z.auftrag_id)} · ${tag(z.eingangsdatum) ?? 'ohne Datum'}`
    const amTag = l => l.find(p => tag(p.eingangsdatum) === tag(z.eingangsdatum)) ?? l[0]
    const gleichesGewicht = eigene.filter(p => Number(p.brutto_kg) === kg)
    if (gleichesGewicht.length) {
      const p = amTag(gleichesGewicht)
      if (z.kisten < p.kisten) {
        const gewogen = z.wiegung_id != null
        if (gewogen) teilZettelWiegung.add(z.wiegung_id)
        melden('Teilpalette mit vollem Zettel', gewogen ? 'hoch' : 'mittel', wo,
          { zettel_kg: kg, kisten_zettel: z.kisten, palette: p.id, kisten_palette: p.kisten, anteilig_kg: r1(kg * z.kisten / p.kisten) },
          `${z.kisten} von ${p.kisten} Kisten der Palette ${p.id}, aber das Zettelgewicht der ganzen Palette (${kg} kg). Anteilig wären es ${r1(kg * z.kisten / p.kisten)} kg — oder die Kistenzahl ist vertippt.${gewogen ? ' Die Verdunstungswägung dazu rechnet mit zu viel Anfangsgewicht und zählt so nicht.' : ''}`)
      } else {
        melden('Zettel Kistenzahl', 'mittel', wo, { zettel_kg: kg, kisten_zettel: z.kisten, palette: p.id, kisten_palette: p.kisten },
          `Gleiches Gewicht wie Palette ${p.id} (${tag(p.eingangsdatum)}), aber ${z.kisten} statt ${p.kisten} Kisten — Kistenzahl vertippt?`)
      }
      continue
    }
    const dreisatz = eigene.filter(p => p.kisten > z.kisten && Math.abs(Number(p.brutto_kg) * z.kisten / p.kisten - kg) <= GRENZEN.zettelDreisatzKg)
    if (dreisatz.length) {
      const p = amTag(dreisatz)
      melden('Teilpalette von Hand umgerechnet', 'mittel', wo,
        { zettel_kg: kg, kisten_zettel: z.kisten, palette: p.id, palette_kg: Number(p.brutto_kg), kisten_palette: p.kisten, dreisatz_kg: r1(Number(p.brutto_kg) * z.kisten / p.kisten), moegliche_paletten: dreisatz.length },
        `${kg} kg für ${z.kisten} Kisten ist ${Number(p.brutto_kg)} kg × ${z.kisten}/${p.kisten} — eine Teilpalette, von Hand im Dreisatz umgerechnet (Palette ${p.id}${dreisatz.length > 1 ? ` oder ${dreisatz.length - 1} weitere` : ''}). Die App findet die Palette so nicht und rechnet mit Kisten × Tara; die Verdunstung dieser Palette bleibt ohne Bezug.`)
      continue
    }
    const fremd = []
    for (const [nr, l] of palJeCharge) {
      if (nr === a.charge_nr || sorteVon(nr) !== sorteVon(a.charge_nr)) continue
      for (const p of l) if (Number(p.brutto_kg) === kg && p.kisten === z.kisten && tag(p.eingangsdatum) === tag(z.eingangsdatum)) fremd.push(p)
    }
    if (fremd.length)
      melden('Zettel auf fremde Charge', 'hoch', wo,
        { zettel_kg: kg, kisten: z.kisten, zetteldatum: tag(z.eingangsdatum), charge_der_arbeit: a.charge_nr, passt_auf: fremd.map(p => `Palette ${p.id} (Charge ${p.charge_nr})`).join(', ') },
        `In Charge ${a.charge_nr} gibt es diese Palette nicht — in Charge ${fremd[0].charge_nr} (gleiche Sorte) aber genau: ${kg} kg, ${z.kisten} Kisten, ${tag(z.eingangsdatum)}. Die Arbeit ist wohl auf die falsche Charge gebucht, oder die Halle hat Paletten der anderen Charge verarbeitet.`)
  }
  for (const [zk, n] of zettelJeArbeitKg) {
    if (n < 2) continue
    const [aid, kg] = zk.split('|'); const a = auftraege.get(Number(aid)); if (!a) continue
    const vorhanden = (palJeCharge.get(a.charge_nr) ?? []).filter(p => Number(p.brutto_kg) === Number(kg)).length
    if (vorhanden > 0 && n > vorhanden)
      melden('Zettel doppelt', 'mittel', `${arbeitText(a.id)} · ${kg} kg`, { zettel: n, paletten_im_journal: vorhanden },
        `${n} Zettel mit ${kg} kg in dieser Arbeit, aber die Charge hat nur ${vorhanden} Palette(n) mit diesem Gewicht — dieselbe Palette zweimal gezählt?`)
  }

  // ---- 5. Zeiten in der falschen Reihenfolge --------------------------------
  for (const w of T('verdunstung_wiegung')) {
    if (w.eingangsdatum && w.wiege_ts && tage(w.wiege_ts, w.eingangsdatum) < 0)
      melden('Zeitfolge', 'hoch', `Wägung ${w.id} · Charge ${w.charge_nr}`, { wiegetag: tag(w.wiege_ts), eingangsdatum: tag(w.eingangsdatum) },
        'Gewogen, bevor die Palette eingegangen ist — eines der zwei Daten ist falsch.')
  }
  for (const z of T('auftrag_palette')) {
    if (z.sortierdatum && z.eingangsdatum && tage(z.sortierdatum, z.eingangsdatum) < 0)
      melden('Zeitfolge', 'mittel', `Zettel ${z.id} · ${arbeitText(z.auftrag_id)}`, { sortierdatum: tag(z.sortierdatum), eingangsdatum: tag(z.eingangsdatum) },
        'Sortiert, bevor die Palette eingegangen ist — Zetteldatum oder Sortierdatum vertippt.')
  }
  for (const a of T('auftrag')) {
    if (a.ende_ts && a.start_ts) {
      const h = (Date.parse(a.ende_ts) - Date.parse(a.start_ts)) / 3600000
      if (h < 0) melden('Zeitfolge', 'hoch', arbeitText(a.id), { start: a.start_ts, ende: a.ende_ts }, 'Die Arbeit endet vor ihrem Anfang.')
      else if (h > GRENZEN.arbeitStundenMax && !a.abgebrochen_ts)
        melden('Arbeitsdauer', 'niedrig', arbeitText(a.id), { stunden: r1(h) }, `${r1(h)} Stunden — wohl über Nacht offen geblieben und erst am nächsten Tag abgeschlossen; der Durchsatz je Stunde stimmt dann nicht.`)
    } else if (a.status === 'offen' && a.start_ts && !a.abgebrochen_ts) {
      const t = tage(heute, a.start_ts)
      if (t >= GRENZEN.offenTage)
        melden('Arbeit offen', 'niedrig', arbeitText(a.id), { tage_offen: r1(t) }, `Seit ${r1(t)} Tagen offen — vergessen abzuschliessen (dann fehlt die Arbeit in der Rechnung) oder aus Versehen begonnen (dann abbrechen).`)
    }
  }
  const eingaenge = T('palette').map(p => tag(p.eingangsdatum)).filter(Boolean).sort()
  if (eingaenge.length) {
    const erster = eingaenge[Math.floor(eingaenge.length * 0.02)]
    for (const p of T('palette')) {
      const e = tag(p.eingangsdatum); if (!e) continue
      if (e > heute) melden('Datum', 'hoch', `Palette ${p.id} · Charge ${p.charge_nr}`, { eingangsdatum: e, heute }, 'Eingangsdatum in der Zukunft.')
      else if (tage(erster, e) > GRENZEN.saisonVorlaufTage) melden('Datum', 'mittel', `Palette ${p.id} · Charge ${p.charge_nr}`, { eingangsdatum: e, saisonbeginn_etwa: erster }, `Mehr als ${GRENZEN.saisonVorlaufTage} Tage vor dem Saisonbeginn — Jahr oder Monat vertippt?`)
    }
  }

  // ---- 6. Verdunstung, die keine sein kann (ausser Teilpalette, oben) ------
  const teil = new Set(befunde.filter(b => b.pruefung === 'Teilpalette').map(b => b.wo))
  for (const w of T('verdunstung_wiegung')) {
    const wo = `Wägung ${w.id} · ${arbeitText(w.auftrag_id)} · Charge ${w.charge_nr}`
    if (teil.has(wo) || teilZettelWiegung.has(w.id) || w.kisten == null || !w.eingangsdatum || !w.wiege_ts) continue
    const t = tara(w.gebindeart)
    const nd = netto(w.brutto_damals_kg, w.kisten, t), nj = netto(w.brutto_jetzt_kg, w.kisten, t)
    const dt = tage(w.wiege_ts, w.eingangsdatum)
    if (nd == null || nj == null || nd <= 0 || dt <= 0) continue
    const rate = 1 - Math.pow(nj / nd, 1 / dt)
    if (rate > GRENZEN.rateMaxProTag)
      melden('Verdunstung zu hoch', 'mittel', wo, { netto_damals_kg: r1(nd), netto_jetzt_kg: r1(nj), tage: r1(dt), rate_je_tag: r3(rate) },
        `${r1(rate * 100)} % je Tag ist keine Verdunstung. Keine Teilpalette erkennbar (keine Eingangskisten bekannt oder gleich viele) — Kisten gewechselt, Zahlendreher, oder doch eine halbe Palette ohne Verknüpfung zum Eingang?`)
    else if (nj > nd * (1 + GRENZEN.schwererAb))
      melden('Schwerer geworden', 'mittel', wo, { netto_damals_kg: r1(nd), netto_jetzt_kg: r1(nj), tage: r1(dt) },
        'Die Palette ist schwerer geworden — Zettel und Waage vertauscht, oder eine andere Palette gewogen.')
  }

  // ---- 7. Palox: Zahlendreher und fallende Stände ---------------------------
  const jeArbeit = new Map()
  for (const s of T('schimmel_messung')) {
    if (Number(s.kg) > GRENZEN.paloxKgMax)
      melden('Zahlendreher Palox', 'hoch', `Ablesung ${s.id} · ${arbeitText(s.auftrag_id)}`, { kg: Number(s.kg), palox_stand_kg: s.palox_stand_kg },
        `${s.kg} kg Faules in einem Palox — ein Palox fasst etwa 400 kg. Vermutlich eine Null zu viel.`)
    const l = jeArbeit.get(s.auftrag_id) ?? []; l.push(s); jeArbeit.set(s.auftrag_id, l)
  }
  for (const [id, l] of jeArbeit) {
    l.sort((a, b) => String(a.ts).localeCompare(String(b.ts)))
    for (let i = 1; i < l.length; i++) {
      const v = l[i - 1], n = l[i]
      if (v.palox_stand_kg != null && n.palox_stand_kg != null && Number(n.palox_stand_kg) < Number(v.palox_stand_kg) && !n.palox_geleert && !n.palox_nach_leeren)
        melden('Palox-Stand fällt', 'mittel', `Ablesungen ${v.id} → ${n.id} · ${arbeitText(id)}`, { vorher_kg: Number(v.palox_stand_kg), nachher_kg: Number(n.palox_stand_kg) },
          'Der Waagenstand sinkt ohne Leeren — zwischendurch geleert und nicht eingetragen, oder abgelesen und vertippt.')
    }
  }

  // ---- 8. Ausschuss: keine einzelne Kiste ----------------------------------
  for (const s of T('ausschuss_messung')) {
    if (Number(s.kg) > GRENZEN.ausschussKisteMax && (s.kisten == null || s.kisten <= 1))
      melden('Ausschuss', 'mittel', `Ausschuss ${s.id} · ${arbeitText(s.auftrag_id)}`, { art: s.art, kg: Number(s.kg), kisten: s.kisten },
        `${s.kg} kg ${s.art} als eine Kiste — so schwer ist keine. Mehrere Kisten zusammen, oder eine Palette?`)
  }

  // ---- 9. Arbeit ohne Nenner -----------------------------------------------
  // Ein Nenner ist: gezählte Paletten, gezählte Kisten (Kaliber), gewogene
  // fertige Paletten, oder eine Gesamtzahl — dieselben Wege wie in
  // v_auftrag_masse (docs/HERLEITUNG.md § 2).
  const mitPaletten = new Set(T('auftrag_palette').map(z => z.auftrag_id))
  const mitGebinde = new Set(T('auftrag_gebinde').map(z => z.auftrag_id))
  const mitAusgang = new Set(T('ausgang_wiegung').map(z => z.auftrag_id))
  for (const a of T('auftrag')) {
    if (a.status !== 'abgeschlossen' || a.ist_fax || a.abgebrochen_ts) continue
    const faul = (jeArbeit.get(a.id) ?? []).reduce((s, x) => s + Number(x.kg ?? 0), 0)
    if (faul > 0 && !mitPaletten.has(a.id) && !mitGebinde.has(a.id) && !mitAusgang.has(a.id) && a.paletten_gesamt == null && a.fertige_paletten_gesamt == null)
      melden('Ohne Nenner', 'hoch', arbeitText(a.id), { faules_kg: faul },
        `${faul} kg Faules, aber keine Palette und keine Kiste gezählt — die Menge hat keinen Bezug. Nachtragen (Korrektur), sonst zählt sie nirgends.`)
  }

  // ---- 10. Lieferungen über dem Eingang, Chargen ohne Eingang ---------------
  const eingangJeCharge = new Map()
  for (const p of T('palette')) {
    const n = netto(p.brutto_kg, p.kisten, tara(p.gebindeart)) ?? 0
    eingangJeCharge.set(p.charge_nr, (eingangJeCharge.get(p.charge_nr) ?? 0) + n)
  }
  const lieferJeCharge = new Map()
  for (const l of T('lieferung')) {
    if (l.charge_nr == null) continue
    const kg = l.kg != null ? Number(l.kg) : (l.kisten != null ? Number(l.kisten) * 9 : 0)
    lieferJeCharge.set(l.charge_nr, (lieferJeCharge.get(l.charge_nr) ?? 0) + kg)
  }
  for (const [nr, kg] of lieferJeCharge) {
    const e = eingangJeCharge.get(nr)
    if (e == null) melden('Lieferung ohne Eingang', 'hoch', `Charge ${nr}`, { geliefert_kg: r1(kg) }, 'Lieferungen für eine Charge, von der keine Palette im Erntejournal steht — Journal unvollständig oder falsche Chargennummer auf dem Lieferschein.')
    else if (kg > e * 1.02) melden('Lieferung über Eingang', 'hoch', `Charge ${nr}`, { geliefert_kg: r1(kg), eingang_netto_kg: r1(e) }, `Mehr ausgeliefert als eingegangen (${r1(kg)} gegen ${r1(e)} kg netto). Eingang fehlt im Journal, oder Lieferungen tragen die falsche Charge.`)
  }
  for (const a of T('auftrag')) {
    if (a.charge_nr != null && !eingangJeCharge.has(a.charge_nr) && !a.abgebrochen_ts)
      melden('Arbeit ohne Eingang', 'hoch', arbeitText(a.id), { charge_nr: a.charge_nr }, 'Eine Arbeit an einer Charge, von der keine Palette im Erntejournal steht.')
  }
  // Geliefert, bevor die erste Palette kam: Charge 1626 der Saison 2026 — sechs
  // Lieferungen ab 2. September, im Journal der erste Eingang am 23. September.
  const ersterEingang = new Map()
  for (const p of T('palette')) { const e = tag(p.eingangsdatum); if (e && (!ersterEingang.has(p.charge_nr) || e < ersterEingang.get(p.charge_nr))) ersterEingang.set(p.charge_nr, e) }
  const vorEingang = new Map()
  for (const l of T('lieferung')) {
    if (l.charge_nr == null) continue
    const e = ersterEingang.get(l.charge_nr), t = tag(l.datum)
    if (!e || !t || t >= e) continue
    const v = vorEingang.get(l.charge_nr) ?? { n: 0, kg: 0, von: t, bis: t, eingang: e }
    v.n++; v.kg += Number(l.kg ?? 0); if (t < v.von) v.von = t; if (t > v.bis) v.bis = t; vorEingang.set(l.charge_nr, v)
  }
  for (const [nr, v] of vorEingang)
    melden('Lieferung vor Eingang', 'hoch', `Charge ${nr}`, { lieferungen: v.n, kg: r1(v.kg), von: v.von, bis: v.bis, erster_eingang: v.eingang },
      `${v.n} Lieferungen (${r1(v.kg)} kg) vom ${v.von} bis ${v.bis}, aber die erste Palette dieser Charge kam laut Journal erst am ${v.eingang} — im Journal fehlt der frühere Eingang, oder die Lieferscheine tragen die falsche Charge.`)
  for (const s of T('sortier_lauf')) {
    if (s.charge_nr == null || eingangJeCharge.has(s.charge_nr)) continue
    const alternativen = [...eingangJeCharge.keys()].filter(nr => sorteVon(nr) != null && sorteVon(nr) === sorteVon(s.charge_nr))
    melden('Sortierlauf ohne Eingang', 'hoch', `Sortierlauf ${s.id} · Charge ${s.charge_nr} · ${tag(s.sortiertag ?? s.datei_zeit)}`,
      { n_gueltig: s.n_gueltig, charge_nr: s.charge_nr, chargen_derselben_sorte_mit_eingang: alternativen.join(', ') || '—' },
      `Eine Sortierdatei mit ${s.n_gueltig} Kürbissen zu einer Charge, von der keine Palette im Journal steht — der Eingang fehlt, oder die Datei gehört zu einer anderen Charge dieser Sorte${alternativen.length ? ` (${alternativen.join(', ')})` : ''}.`)
  }
  const ohneCharge = T('lieferung').filter(l => l.charge_nr == null)
  if (ohneCharge.length) {
    const t = ohneCharge.map(l => tag(l.datum)).filter(Boolean).sort()
    melden('Lieferung ohne Charge', 'mittel', 'Lieferungen', { lieferungen: ohneCharge.length, kg: r1(ohneCharge.reduce((s, l) => s + Number(l.kg ?? 0), 0)), von: t[0] ?? '—', bis: t[t.length - 1] ?? '—' },
      `${ohneCharge.length} Lieferungen ohne Chargennummer — sie fehlen in jeder Chargenbilanz und im „Wohin" je Sorte. Unter Betrieb → Warenausgang die Charge nachtragen.`)
  }
  for (const nr of new Set([...T('palette').map(p => p.charge_nr), ...T('auftrag').map(a => a.charge_nr)])) {
    if (nr != null && chargen.size && !chargen.has(nr)) melden('Charge unbekannt', 'mittel', `Charge ${nr}`, {}, 'Diese Chargennummer steht nicht in den Stammdaten.')
  }

  // ---- 11. Fertige Paletten: Gewicht je Kiste -------------------------------
  for (const g of T('ausgang_wiegung')) {
    if (g.kisten == null || g.kisten <= 0) continue
    const je = netto(g.brutto_kg, g.kisten, tara(g.gebindeart)) / g.kisten
    if (je < GRENZEN.kgJeKisteMin || je > GRENZEN.kgJeKisteMax)
      melden('Fertige Palette je Kiste', 'mittel', `Fertige Palette ${g.id} · ${arbeitText(g.auftrag_id)}`, { brutto_kg: Number(g.brutto_kg), kisten: g.kisten, netto_je_kiste_kg: r1(je) },
        `${r1(je)} kg netto je Kiste — ausserhalb von ${GRENZEN.kgJeKisteMin}–${GRENZEN.kgJeKisteMax} kg. Kistenzahl oder Gewicht vertippt, oder halbe Palette als voll markiert.`)
  }

  // ---- 12. Kontrollpaletten: Kisten wechseln, Gewicht steigt ----------------
  const kp = new Map(T('kontrollpalette').map(k => [k.id, k]))
  const kpw = new Map()
  for (const w of T('kontrollpalette_wiegung')) { const l = kpw.get(w.kontrollpalette_id) ?? []; l.push(w); kpw.set(w.kontrollpalette_id, l) }
  for (const [id, l] of kpw) {
    l.sort((a, b) => String(a.wiege_ts).localeCompare(String(b.wiege_ts)))
    const k = kp.get(id)
    for (let i = 1; i < l.length; i++) {
      const v = l[i - 1], n = l[i]
      const wo = `Kontrollpalette ${k?.kennzeichen ?? id} · Charge ${k?.charge_nr ?? '?'} · ${tag(n.wiege_ts)}`
      if (v.kisten != null && n.kisten != null && v.kisten !== n.kisten)
        melden('Kontrollpalette Kisten', 'mittel', wo, { kisten_vorher: v.kisten, kisten_nachher: n.kisten }, 'Die Kistenzahl der Kontrollpalette hat sich geändert — Kisten entnommen? Dann ist der Vergleich mit der ersten Wägung schief.')
      if (Number(n.brutto_kg) > Number(v.brutto_kg) * 1.01)
        melden('Kontrollpalette schwerer', 'mittel', wo, { vorher_kg: Number(v.brutto_kg), nachher_kg: Number(n.brutto_kg) }, 'Die Kontrollpalette ist schwerer geworden — Zahlendreher, oder eine andere Palette gewogen.')
    }
  }

  // ---- 13. Zetteldatum ohne Palette an dem Tag ------------------------------
  const tageJeCharge = new Map()
  for (const p of T('palette')) { const s = tageJeCharge.get(p.charge_nr) ?? new Set(); s.add(tag(p.eingangsdatum)); tageJeCharge.set(p.charge_nr, s) }
  for (const z of T('auftrag_palette')) {
    if (z.palette_id != null || !z.eingangsdatum) continue
    const a = auftraege.get(z.auftrag_id); if (!a) continue
    const s = tageJeCharge.get(a.charge_nr)
    if (s && !s.has(tag(z.eingangsdatum)))
      melden('Zetteldatum ohne Palette', 'mittel', `Zettel ${z.id} · ${arbeitText(z.auftrag_id)}`, { zetteldatum: tag(z.eingangsdatum), tage_der_charge: [...s].sort().join(', ') },
        'An diesem Tag kam laut Journal keine Palette dieser Charge — Datum vertippt (12./21.?) oder Palette fehlt im Journal.')
  }

  const zaehlung = {}
  for (const b of befunde) zaehlung[b.pruefung] = (zaehlung[b.pruefung] ?? 0) + 1
  const rang = { hoch: 0, mittel: 1, niedrig: 2 }
  befunde.sort((a, b) => rang[a.schwere] - rang[b.schwere] || a.pruefung.localeCompare(b.pruefung) || a.wo.localeCompare(b.wo))
  return { befunde, zaehlung, fehlt, hinweise, tabellen: Object.fromEntries(Object.keys(ROHTABELLEN).map(n => [n, T(n).length])) }
}

/** Der Durchgang als Markdown — das, was die Runde liest. */
export function alsMarkdown(erg, heute, quelle) {
  let m = `# Plausibilitätsdurchgang\n\n_Stand ${heute} · Quelle ${quelle} · von \`pruefstand/durchgang.mjs\` geschrieben; nicht von Hand ändern._\n\n`
  m += 'Jede Zeile ist ein **Kandidat**, kein Urteil: eine Zahl, die so nicht sein kann oder nicht sein sollte, mit dem Grund. Die Runde am Programm liest sie, prüft die Rohzeilen und schreibt die Zweitmeinung; der Betrieb entscheidet.\n\n'
  m += `## Tabellen\n\n| Tabelle | Zeilen |\n|---|---|\n` + Object.entries(erg.tabellen).map(([n, z]) => `| ${n} | ${z} |`).join('\n') + '\n\n'
  if (erg.fehlt.length) m += `_Nicht vorhanden: ${erg.fehlt.join(', ')} — diese Prüfungen liefen leer._\n\n`
  for (const h of erg.hinweise ?? []) m += `_${h}_\n\n`
  m += `## Nach Prüfung (${erg.befunde.length})\n\n| Prüfung | Anzahl |\n|---|---|\n` + Object.entries(erg.zaehlung).sort((a, b) => b[1] - a[1]).map(([n, z]) => `| ${n} | ${z} |`).join('\n') + '\n\n'
  for (const s of ['hoch', 'mittel', 'niedrig']) {
    const l = erg.befunde.filter(b => b.schwere === s)
    if (!l.length) continue
    m += `## Schwere ${s} (${l.length})\n\n`
    for (const b of l) {
      const w = Object.entries(b.werte).map(([k, v]) => `${k} = ${v == null ? '—' : v}`).join(' · ')
      m += `- **${b.pruefung}** · ${b.wo}\n  - ${b.warum}\n  - _${w}_\n`
    }
    m += '\n'
  }
  if (!erg.befunde.length) m += '_Kein Kandidat — alle Rohdaten liegen innerhalb der Grenzen._\n'
  return m
}
