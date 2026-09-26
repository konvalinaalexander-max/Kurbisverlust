/**
 * Der Rückweg (Runde Z): Kurzfassungen aus docs/betrieb/kurzfassungen.json
 * in die Datenbank — was daraus je Rückmeldung zu ändern ist.
 *
 * Der Betrieb: „es soll erst im Dashboard erscheinen, nachdem du es gelesen
 * hast und verstanden hast … runterbrechen und abkürzen auf Hagelschaden …
 * ordne es korrekt den Chargen zu und den Aufträgen."
 *
 * Reine Rechnung, ohne Netz — damit npm test sie prüfen kann. Der Abzug
 * (betrieb_abzug.mjs) holt je Eintrag die Zeile, fragt hier, was sich
 * ändert, und schickt genau das als PATCH.
 *
 * Regeln:
 *   - Eine Kurzfassung des Betriebsleiters (kurz_quelle = betriebsleiter)
 *     wird nie überschrieben — es sei denn, der Eintrag sagt es ausdrücklich
 *     (ueberschreiben: true), weil der Betriebsleiter es so wollte.
 *   - kurz: Text → Kurzfassung der Runde (kurz_quelle = runde, kurz_ts jetzt);
 *     null → Kurzfassung zurücknehmen (dann steht sie nirgends mehr).
 *   - charge_nr → kurz_charge_nr, nur mit Kurzfassung (Regel der Tabelle).
 *   - art → 'ware' oder 'app'; zur App gibt es keine Kurzfassung.
 *   - auftrag_id → an eine andere Arbeit hängen.
 *   - Was schon so steht, wird nicht noch einmal geschickt.
 */

const ARTEN = new Set(['ware', 'app'])

/** Prüft die ganze Datei; wirft mit einer Zeile je Fehler. */
export function eintraegePruefen(datei) {
  if (!datei || typeof datei !== 'object' || !Array.isArray(datei.eintraege)) {
    throw new Error('kurzfassungen.json: erwartet { "eintraege": [ … ] }')
  }
  const fehler = []
  const gesehen = new Set()
  datei.eintraege.forEach((e, i) => {
    const wo = `Eintrag ${i + 1}`
    if (!e || typeof e !== 'object') { fehler.push(`${wo}: kein Objekt`); return }
    if (!Number.isInteger(e.id) || e.id <= 0) fehler.push(`${wo}: id fehlt oder ist keine ganze Zahl`)
    else if (gesehen.has(e.id)) fehler.push(`${wo}: id ${e.id} steht doppelt`)
    else gesehen.add(e.id)
    if ('kurz' in e && e.kurz !== null && (typeof e.kurz !== 'string' || !e.kurz.trim())) fehler.push(`${wo}: kurz ist weder Text noch null`)
    if ('charge_nr' in e && e.charge_nr !== null && !Number.isInteger(e.charge_nr)) fehler.push(`${wo}: charge_nr ist keine ganze Zahl`)
    if ('art' in e && !ARTEN.has(e.art)) fehler.push(`${wo}: art muss ware oder app sein`)
    if ('auftrag_id' in e && !Number.isInteger(e.auftrag_id)) fehler.push(`${wo}: auftrag_id ist keine ganze Zahl`)
    if ('ueberschreiben' in e && typeof e.ueberschreiben !== 'boolean') fehler.push(`${wo}: ueberschreiben ist kein Wahrheitswert`)
    const bekannt = new Set(['id', 'kurz', 'charge_nr', 'art', 'auftrag_id', 'ueberschreiben', 'warum'])
    for (const k of Object.keys(e)) if (!bekannt.has(k)) fehler.push(`${wo}: unbekanntes Feld „${k}"`)
  })
  if (fehler.length) throw new Error(fehler.join('\n'))
  return datei.eintraege
}

/**
 * Was an der Zeile zu ändern ist — oder null, wenn nichts. `grund` sagt,
 * warum nichts geschickt wird, wenn der Eintrag etwas wollte.
 */
export function patchFuer(zeile, eintrag, jetzt) {
  if (!zeile) return { patch: null, grund: `Nr. ${eintrag.id} gibt es nicht (mehr)` }
  const p = {}
  const willKurz = 'kurz' in eintrag
  const artNeu = 'art' in eintrag ? eintrag.art : zeile.art
  const kurzNachher = willKurz ? (eintrag.kurz === null ? null : eintrag.kurz.trim()) : zeile.kurz

  if (zeile.kurz_quelle === 'betriebsleiter' && !eintrag.ueberschreiben
      && (willKurz || 'charge_nr' in eintrag)) {
    return { patch: null, grund: `Nr. ${eintrag.id}: der Betriebsleiter hat selbst gekürzt („${zeile.kurz}") — bleibt, ausser der Eintrag sagt ueberschreiben: true` }
  }
  // Zur App gibt es keine Kurzfassung (Regel der Tabelle). Wer ein gekürztes
  // Feedback zur App macht, sagt kurz: null dazu — nichts wird stillschweigend
  // weggenommen.
  if (artNeu === 'app' && kurzNachher) {
    return { patch: null, grund: `Nr. ${eintrag.id}: zur App gibt es keine Kurzfassung — entweder art: ware oder kurz: null dazu` }
  }
  if ('charge_nr' in eintrag && eintrag.charge_nr !== null && !kurzNachher) {
    return { patch: null, grund: `Nr. ${eintrag.id}: eine andere Charge geht nur mit Kurzfassung` }
  }

  if (willKurz) {
    if (kurzNachher === null) {
      if (zeile.kurz !== null) Object.assign(p, { kurz: null, kurz_quelle: null, kurz_ts: null, kurz_charge_nr: null })
    } else if (zeile.kurz !== kurzNachher || zeile.kurz_quelle !== 'runde') {
      Object.assign(p, { kurz: kurzNachher, kurz_quelle: 'runde', kurz_ts: jetzt })
    }
  }
  if ('charge_nr' in eintrag && eintrag.charge_nr !== (zeile.kurz_charge_nr ?? null)) p.kurz_charge_nr = eintrag.charge_nr
  if ('art' in eintrag && eintrag.art !== zeile.art) p.art = eintrag.art
  if ('auftrag_id' in eintrag && eintrag.auftrag_id !== zeile.auftrag_id) p.auftrag_id = eintrag.auftrag_id
  return Object.keys(p).length ? { patch: p, grund: null } : { patch: null, grund: null }
}
