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
  kistenMax: 60,                           // mehr Kisten stehen auf keiner Palette
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
    const g = m.get(art) ?? m.get('G2') ?? { tara_kg_pro_kiste: 1.5, tara_kg_palette: 25 }
    return { kiste: Number(g.tara_kg_pro_kiste ?? 1.5), palette: mitPalette ? Number(g.tara_kg_palette ?? 25) : 0 }
  }
}
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
  for (const p of T('palette')) {
    const t = tara(p.gebindeart)
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

  // ---- 3. Doppelte Eingangspaletten ----------------------------------------
  const gesehen = new Map()
  for (const p of T('palette')) {
    const k = `${p.charge_nr}|${tag(p.eingangsdatum)}|${p.brutto_kg}|${p.kisten}`
    if (gesehen.has(k)) {
      melden('Doppelte Palette', 'niedrig', `Paletten ${gesehen.get(k)} und ${p.id} · Charge ${p.charge_nr} · ${tag(p.eingangsdatum)}`,
        { brutto_kg: Number(p.brutto_kg), kisten: p.kisten, extern_id: p.extern_id },
        'Zwei Paletten derselben Charge, am selben Tag, mit gleichem Gewicht und gleicher Kistenzahl — echt (zwei gleiche Zettel) oder doppelt erfasst?')
    } else gesehen.set(k, p.id)
  }

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
    if (teil.has(wo) || w.kisten == null || !w.eingangsdatum || !w.wiege_ts) continue
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
  return { befunde, zaehlung, fehlt, tabellen: Object.fromEntries(Object.keys(ROHTABELLEN).map(n => [n, T(n).length])) }
}

/** Der Durchgang als Markdown — das, was die Runde liest. */
export function alsMarkdown(erg, heute, quelle) {
  let m = `# Plausibilitätsdurchgang\n\n_Stand ${heute} · Quelle ${quelle} · von \`pruefstand/durchgang.mjs\` geschrieben; nicht von Hand ändern._\n\n`
  m += 'Jede Zeile ist ein **Kandidat**, kein Urteil: eine Zahl, die so nicht sein kann oder nicht sein sollte, mit dem Grund. Die Runde am Programm liest sie, prüft die Rohzeilen und schreibt die Zweitmeinung; der Betrieb entscheidet.\n\n'
  m += `## Tabellen\n\n| Tabelle | Zeilen |\n|---|---|\n` + Object.entries(erg.tabellen).map(([n, z]) => `| ${n} | ${z} |`).join('\n') + '\n\n'
  if (erg.fehlt.length) m += `_Nicht vorhanden: ${erg.fehlt.join(', ')} — diese Prüfungen liefen leer._\n\n`
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
