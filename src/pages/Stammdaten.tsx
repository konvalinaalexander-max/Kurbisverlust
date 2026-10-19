import { useCallback, useEffect, useRef, useState } from 'react'
import { imDemoModus, supabase } from '../lib/supabase'
import { chargenAnlegen, einstellung, fehlerText, stammdaten } from '../lib/db'
import { importErkennen, type ImportBericht } from '../lib/import'
import { STATION_NAME, datum, heute as heuteOrtszeit, kg, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Kennzahl, Lade, Marke } from '../components/Bausteine'
import { useBetriebsmodus } from '../lib/betriebsmodus'
import DemoDaten from '../components/DemoDaten'
import { ZHaken, ZStift } from '../components/Zeichen'
import ErfassungLeeren from '../components/ErfassungLeeren'
import type { Charge, Gebinde, Kaeufer, Profil, Sortierschema } from '../lib/typen'

export default function Stammdaten() {
  const modus = useBetriebsmodus()
  const [teil, setTeil] = useState<'gebinde' | 'paletten' | 'chargen' | 'kaliber' | 'artikel'
    | 'abgebrochen' | 'benutzer' | 'einstellungen' | 'vorlauf' | 'demo' | 'leeren'>('gebinde')
  const teile: [typeof teil, string][] = [
    ['gebinde', 'Gebinde & Tara'],
    ['paletten', 'Paletten-Import'],
    ['chargen', 'Chargen'],
    ['kaliber', 'Sortierschemata'],
    // Runde AO (0112): welche Sorte als welcher Artikel geht, und was gross und klein heisst.
    ['artikel', 'Sorten und Artikel'],
    ['abgebrochen', 'Abgebrochene Arbeiten'],
    ['benutzer', 'Benutzer'],
    ['einstellungen', 'Einstellungen'],
    ['vorlauf', 'Erfassungsbeginn'],
    ['demo', 'Demo-Daten'],
    // Ganz hinten und als letzter Reiter: Wer ihn trifft, wollte ihn treffen.
    ['leeren', 'Alles löschen'],
  ]
  return (
    <>
      <h1>Stammdaten</h1>
      <nav className="navleiste unter">
        {teile.map(([t, name]) => (
          <a key={t} href="#" className={teil === t ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); setTeil(t) }}>{name}</a>
        ))}
      </nav>
      {teil === 'gebinde' && <GebindeTara />}
      {teil === 'paletten' && <PalettenImport />}
      {teil === 'chargen' && <Chargen />}
      {teil === 'kaliber' && <Kaliber />}
      {teil === 'artikel' && <SortenArtikel />}
      {teil === 'abgebrochen' && <Abgebrochene />}
      {teil === 'benutzer' && <Benutzer />}
      {teil === 'einstellungen' && <Einstellungen />}
      {teil === 'vorlauf' && <Vorlauf />}
      {/* 0072: Im Echtmodus gibt es die Beispieldaten gar nicht erst zu
          sehen. Der Schutz selbst sitzt in der Datenbank (Auslöser), hier
          steht nur, dass niemand versehentlich darauf tippt.
          0081: Wer über den Demo-Knopf hereinkam, sieht die Karte in jedem
          Fall — sie erklärt dann selbst, was der Demo-Datenbank fehlt. */}
      {teil === 'demo' && ((modus === 'beispiel' || imDemoModus)
        ? <DemoDaten />
        : <Hinweis>Diese Datenbank läuft im Echtmodus. Beispieldaten gehören auf die Beispiel-Webseite — sie werden hier auch dann nicht geladen, wenn jemand es von Hand versucht.</Hinweis>)}
      {/* 0080: Anders als die Demo-Daten gibt es das Leeren in beiden Modi —
          gerade die echte Datenbank braucht es am Testtag. Der Schutz ist
          nicht der Modus, sondern das getippte Wort. */}
      {teil === 'leeren' && <ErfassungLeeren />}
    </>
  )
}

/* ------------------------------------------------------------------ */
function GebindeTara() {
  const [zeilen, setZeilen] = useState<Gebinde[]>([])
  const [laedt, setLaedt] = useState(true)
  const [fehler, setFehler] = useState<string | null>(null)
  const [gespeichert, setGespeichert] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const { data, error } = await supabase.from('gebinde').select('*').order('art')
    if (error) setFehler(fehlerText(error)); else setZeilen((data ?? []) as Gebinde[])
    setLaedt(false)
  }, [])
  useEffect(() => { void laden() }, [laden])

  async function speichern(g: Gebinde) {
    const { error } = await supabase.from('gebinde').update({
      tara_kg_pro_kiste: g.tara_kg_pro_kiste, tara_kg_palette: g.tara_kg_palette,
    }).eq('art', g.art)
    if (error) setFehler(fehlerText(error))
    else { setGespeichert(g.art); setTimeout(() => setGespeichert(null), 2000); void stammdaten(true) }
  }

  if (laedt) return <Lade />

  return (
    <Karte titel="Gebinde und Leergewichte">
      <Hinweis>
        Ohne Tara kein Netto: Brutto minus Kisten mal Kisten-Tara minus Paletten-Tara.
        Fehlt ein Wert, bleibt das Netto der betroffenen Paletten leer und sie fehlen
        in der gesamten Auswertung — lieber einmal nachwiegen als eine Null raten.
      </Hinweis>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {zeilen.length === 0 && (
        <p className="leise">
          Noch keine Gebindearten. Sie entstehen automatisch beim Paletten-Import.
        </p>
      )}
      {zeilen.map((g, i) => (
        <div key={g.art} style={{ borderBottom: '1px solid var(--rand)', padding: '.75rem 0' }}>
          <div className="reihe">
            <strong>{g.art}</strong>
            {g.tara_kg_pro_kiste === null && <Marke art="warnung">Tara fehlt</Marke>}
            {gespeichert === g.art && <Marke art="fertig">gespeichert</Marke>}
          </div>
          <div className="spalten" style={{ marginTop: '.5rem' }}>
            <div className="feld">
              <label>Tara je Kiste (kg)</label>
              <input type="number" step="0.001" min={0}
                     value={g.tara_kg_pro_kiste ?? ''}
                     onChange={e => setZeilen(z => z.map((x, j) => j === i
                       ? { ...x, tara_kg_pro_kiste: e.target.value === '' ? null : Number(e.target.value) } : x))} />
            </div>
            <div className="feld">
              <label>Tara der Palette (kg)</label>
              <input type="number" step="0.001" min={0}
                     value={g.tara_kg_palette ?? ''}
                     onChange={e => setZeilen(z => z.map((x, j) => j === i
                       ? { ...x, tara_kg_palette: e.target.value === '' ? null : Number(e.target.value) } : x))} />
            </div>
          </div>
          <button onClick={() => speichern(g)}>Speichern</button>
        </div>
      ))}
    </Karte>
  )
}

/* ------------------------------------------------------------------ */
/* Paletten aus dem Erntejournal übernehmen                            */
/* ------------------------------------------------------------------ */
function PalettenImport() {
  const [text, setText] = useState('')
  const [csvUrl, setCsvUrl] = useState('')
  const [bericht, setBericht] = useState<ImportBericht | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)
  const [holt, setHolt] = useState(false)

  useEffect(() => {
    void einstellung<string>('journal_csv_url', '').then(setCsvUrl)
  }, [])

  async function pruefen(roh: string) {
    setFehler(null); setMeldung(null)
    try {
      const { chargen } = await stammdaten()
      const b = importErkennen(roh, chargen)
      setBericht(b)
      if (b.paletten.length === 0 && b.probleme.length === 0) {
        setFehler('Keine Datenzeilen erkannt. Ist der richtige Bereich kopiert?')
      }
    } catch (f) { setFehler(fehlerText(f)) }
  }

  async function vomSheetHolen() {
    if (!csvUrl.trim()) { setFehler('Bitte zuerst die veröffentlichte CSV-Adresse eintragen.'); return }
    setHolt(true); setFehler(null); setMeldung(null)
    try {
      const antwort = await fetch(csvUrl.trim(), { redirect: 'follow' })
      if (!antwort.ok) throw new Error(`Das Sheet antwortete mit ${antwort.status}. `
        + 'Ist die Tabelle „Im Web veröffentlicht" (als CSV)?')
      const csv = await antwort.text()
      if (/^\s*</.test(csv)) throw new Error('Die Adresse liefert eine Webseite statt CSV. '
        + 'Bitte die Veröffentlichungs-Adresse mit „output=csv" verwenden, nicht die normale Sheet-URL.')
      // Adresse merken, damit sie beim nächsten Mal schon dasteht
      await supabase.from('einstellung').upsert(
        { schluessel: 'journal_csv_url', wert: csvUrl.trim(), bemerkung:
          'Veröffentlichte CSV-Adresse des Erntejournal-Tabs „Ertragsjournal".' },
        { onConflict: 'schluessel' })
      await pruefen(csv)
    } catch (f) {
      // Der häufigste Stolperstein ist eine Blockade durch den Browser (CORS),
      // wenn die falsche Adresse verwendet wird.
      const t = fehlerText(f)
      setFehler(/failed to fetch/i.test(t)
        ? 'Das Sheet ließ sich nicht laden. Meist liegt es an der Adresse: Sie muss die '
          + '„Im Web veröffentlichen"-Adresse sein (endet auf output=csv), nicht die normale '
          + 'Bearbeitungs-Adresse des Sheets.'
        : t)
    } finally { setHolt(false) }
  }

  async function importieren() {
    if (!bericht) return
    setLaeuft(true); setFehler(null)
    try {
      // Gebindearten anlegen, falls eine im Journal steht, die es noch nicht gibt.
      // Die Tara ist über Migration 0010 bereits gesetzt; hier nichts überschreiben.
      // Runde AS: neue Chargen aus dem Journal zuerst — sonst hätten ihre Paletten keine Charge.
      const angelegt = await chargenAnlegen(bericht.neueChargen)
      const arten = [...new Set(bericht.paletten.map(z => z.gebindeart).filter(Boolean))] as string[]
      if (arten.length) {
        const { error } = await supabase.from('gebinde')
          .upsert(arten.map(art => ({ art })), { onConflict: 'art', ignoreDuplicates: true })
        if (error) throw error
      }
      // Ein Upsert schreibt beim Konflikt ALLE Felder der Nutzlast. Eine
      // Quelle ohne Kistenspalte schickt `kisten: null` — und hätte damit
      // bestehende, gemessene Kistenzahlen auf NULL zurückgesetzt. Was
      // nicht in der Datei steht, darf nichts überschreiben: die leeren
      // Felder gehen gar nicht erst mit.
      const ohneLeere = bericht.paletten.map(z => {
        const rein: Record<string, unknown> = {}
        for (const [k, v] of Object.entries(z)) if (v !== null) rein[k] = v
        return rein
      })
      for (let i = 0; i < ohneLeere.length; i += 500) {
        const { error } = await supabase.from('palette')
          .upsert(ohneLeere.slice(i, i + 500), { onConflict: 'extern_id' })
        if (error) throw error
      }
      setMeldung(`${bericht.paletten.length} Paletten übernommen${angelegt ? `, ${angelegt === 1 ? 'eine Charge' : `${angelegt} Chargen`} neu angelegt (${bericht.neueChargen.map(c => c.nr).join(', ')})` : ''}.`)
      setBericht(null); setText('')
      void stammdaten(true)
    } catch (f) { setFehler(fehlerText(f)) } finally { setLaeuft(false) }
  }

  const ohneGebinde = bericht?.paletten.filter(z => !z.gebindeart).length ?? 0
  const bruttoSumme = bericht?.paletten.reduce((s, z) => s + z.brutto_kg, 0) ?? 0

  return (
    <>
      <Karte titel="Direkt aus dem Google Sheet holen">
        <Hinweis>
          Einmal im Erntejournal-Sheet einrichten: <em>Datei → Freigeben → Im Web
          veröffentlichen</em>, dort den Tab <strong>Ertragsjournal</strong> und das
          Format <strong>CSV</strong> wählen. Die entstehende Adresse (endet auf
          <code>output=csv</code>) hier einfügen — danach genügt ein Knopfdruck.
        </Hinweis>
        <div className="feld">
          <label htmlFor="csv">Veröffentlichte CSV-Adresse des Tabs „Ertragsjournal"</label>
          <input id="csv" value={csvUrl} onChange={e => setCsvUrl(e.target.value)}
                 placeholder="https://docs.google.com/spreadsheets/d/e/…/pub?gid=…&single=true&output=csv" />
        </div>
        <button className="haupt" onClick={vomSheetHolen} disabled={holt || !csvUrl.trim()}>
          {holt ? 'Hole …' : 'Jetzt vom Sheet holen'}
        </button>
      </Karte>

      <Karte titel="Oder von Hand einfügen">
        <p className="leise">
          Im Sheet den Bereich samt Kopfzeile markieren, kopieren und hier einfügen.
          Erkannt werden Datum, Schlag, Sorte, Brutto, Kisten, Gebinde — die Charge
          ergibt sich aus Schlag + Sorte.
        </p>
        <div className="feld">
          <label htmlFor="einfuegen">Eingefügte Zeilen</label>
          <textarea id="einfuegen" rows={6} value={text} onChange={e => setText(e.target.value)}
                    placeholder={'Datum\tPerson\tSchlag\tSorte\tGewicht brutto [kg]\tAnzahl Gebinde\tGebindeart'} />
        </div>
        <button onClick={() => pruefen(text)} disabled={!text.trim()}>Prüfen</button>
      </Karte>

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {meldung && <Hinweis art="gut">{meldung}</Hinweis>}

      {bericht && bericht.probleme.length > 0 && (
        <Hinweis art="warnung">
          <strong>{bericht.probleme.length} Zeilen übersprungen</strong>
          <ul style={{ margin: '.4rem 0 0', paddingLeft: '1.2rem' }}>
            {bericht.probleme.slice(0, 12).map((p, i) => <li key={i}>{p}</li>)}
            {bericht.probleme.length > 12 && <li>… und {bericht.probleme.length - 12} weitere</li>}
          </ul>
          <p className="leise" style={{ margin: '.4rem 0 0' }}>
            Meist ein Schlag oder eine Sorte, die anders geschrieben ist als in der
            Chargen-Liste. Die Schreibweise muss zeichengenau übereinstimmen.
          </p>
        </Hinweis>
      )}

      {bericht && bericht.paletten.length > 0 && (
        <Karte titel={`${bericht.paletten.length} Paletten bereit`}>
          <p>
            <strong>{kg(bruttoSumme, 0)} brutto</strong> · Zuordnung über
            {' '}{bericht.quelle === 'chargennummer' ? 'Chargennummer' : 'Schlag + Sorte'}
            {/* Vorher stand hier „gelten als G2". Das war falsch: eine LEERE
                Zelle wird zu G2, eine FEHLENDE SPALTE zu NULL — und ohne
                Gebindeart findet v_palette keine Tara und liefert für diese
                Zeilen gar kein Netto. Der Import meldete Erfolg, die
                Eingangsmasse verschwand lautlos. */}
            {ohneGebinde > 0 && ` · ${ohneGebinde} ohne Gebindeart — ohne sie gibt es für diese Paletten kein Nettogewicht`}
          </p>
          {bericht.neueChargen.length > 0 && (
            <Hinweis art="info">
              <strong>{bericht.neueChargen.length === 1 ? 'Eine neue Charge' : `${bericht.neueChargen.length} neue Chargen`}</strong> — werden mit den Paletten angelegt:{' '}
              {bericht.neueChargen.map(c => `${c.nr} ${c.schlag} · ${c.sorte}`).join(', ')}.
            </Hinweis>
          )}
          <div className="rollbar">
            <table>
              <thead><tr><th>Charge</th><th>Datum</th><th className="zahl">Brutto</th>
                <th className="zahl">Kisten</th><th>Gebinde</th></tr></thead>
              <tbody>
                {bericht.paletten.slice(0, 12).map((z, i) => (
                  <tr key={i}>
                    <td>{z.charge_nr}</td><td>{datum(z.eingangsdatum)}</td>
                    <td className="zahl">{kg(z.brutto_kg, 1)}</td>
                    <td className="zahl">{z.kisten ?? '—'}</td><td>{z.gebindeart ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {bericht.paletten.length > 12 && (
            <p className="leise">… und {bericht.paletten.length - 12} weitere.</p>
          )}
          <button className="haupt" style={{ width: '100%', marginTop: '.75rem' }}
                  onClick={importieren} disabled={laeuft}>
            {laeuft ? 'Läuft …' : `${bericht.paletten.length} Paletten übernehmen`}
          </button>
          <p className="leise" style={{ marginTop: '.5rem' }}>
            Schon vorhandene Paletten werden nicht doppelt angelegt — du kannst
            jederzeit die aktualisierte Tabelle erneut holen.
          </p>
        </Karte>
      )}
    </>
  )
}

/* ------------------------------------------------------------------ */
function Chargen() {
  const [chargen, setChargen] = useState<Charge[]>([])
  const [zahlen, setZahlen] = useState<Record<number, { n: number; kg: number | null }>>({})
  // Runde Q, Q9: „vlt kann ich ja irgendwo dann in den einstellungen angeben
  // - nun ernte vorbei". Solange die Ernte läuft, ist die Erntespanne einer
  // Charge vorläufig — es kann noch eine Palette dazukommen und das mittlere
  // Eingangsdatum verschieben. Danach steht sie. Die Auswertung liest das
  // Zeichen in v_charge_erntespanne.ernte_fertig (0073).
  const [ernteFertig, setErnteFertig] = useState<boolean | null>(null)
  const [speichert, setSpeichert] = useState(false)
  const [fehler, setFehler] = useState<string | null>(null)
  /** Runde AO: wie viele noch Ware im Haus haben, und das Label aus Perigon als Vorschlag.
   *  Seit 0113 auch, woher es sonst kommt: vom Produzenten oder angenommen. */
  const [imHaus, setImHaus] = useState<Set<number>>(new Set())
  const [perigon, setPerigon] = useState<Map<number, { label: string | null; quelle: string | null; gemischt: boolean; widerspruch: boolean }>>(new Map())
  useEffect(() => {
    void einstellung<boolean>('ernte_abgeschlossen', false).then(w => setErnteFertig(!!w))
    void (async () => {
      const [b, l] = await Promise.all([
        supabase.from('erg_charge').select('charge_nr, lager_kg'),
        supabase.from('v_charge_label').select('charge_nr, label, quelle, gemischt, n_widerspruch'),
      ])
      setImHaus(new Set(((b.data ?? []) as { charge_nr: number; lager_kg: number }[]).filter(x => x.lager_kg > 0).map(x => x.charge_nr)))
      setPerigon(new Map(((l.data ?? []) as { charge_nr: number; label: string | null; quelle: string | null; gemischt: boolean; n_widerspruch?: number }[])
        .filter(x => x.quelle !== 'Stammdaten')
        .map(x => [x.charge_nr, { label: x.label, quelle: x.quelle, gemischt: x.gemischt, widerspruch: (x.n_widerspruch ?? 0) > 0 }])))
    })()
  }, [])
  async function labelSetzen(c: Charge, label: 'D' | 'K' | null) {
    setFehler(null)
    const { error } = await supabase.from('charge').update({ label }).eq('nr', c.nr)
    if (error) { setFehler(fehlerText(error)); return }
    setChargen(cs => cs.map(x => x.nr === c.nr ? { ...x, label } : x))
  }
  async function ernteSetzen(wert: boolean) {
    setSpeichert(true); setFehler(null)
    const { error } = await supabase.from('einstellung').upsert(
      { schluessel: 'ernte_abgeschlossen', wert,
        bemerkung: 'Die Ernte ist eingebracht — die Erntespanne jeder Charge steht fest (0072/0073).' },
      { onConflict: 'schluessel' })
    setSpeichert(false)
    if (error) { setFehler(fehlerText(error)); return }
    setErnteFertig(wert)
  }
  useEffect(() => {
    void (async () => {
      const s = await stammdaten(true)
      setChargen(s.chargen)
      const { data } = await supabase.from('v_charge_rueckgrat')
        .select('charge_nr, n_paletten, eingang_netto_kg')
      const map: Record<number, { n: number; kg: number | null }> = {}
      for (const r of (data ?? []) as { charge_nr: number; n_paletten: number
        eingang_netto_kg: number | null }[]) {
        map[r.charge_nr] = { n: r.n_paletten, kg: r.eingang_netto_kg }
      }
      setZahlen(map)
    })()
  }, [])
  const gesamtPaletten = Object.values(zahlen).reduce((s, z) => s + z.n, 0)
  const gesamtKg = Object.values(zahlen).reduce((s, z) => s + (z.kg ?? 0), 0)
  const mitDaten = Object.values(zahlen).filter(z => z.n > 0).length
  const ohneEingang = chargen.length - mitDaten

  return (
    <>
      <Karte titel="Ernte bisher erfasst">
        <div className="spalten">
          <Kennzahl titel="Netto insgesamt" wert={tonnen(gesamtKg)}
                    unter="aus dem Erntejournal übernommen" />
          <Kennzahl titel="Paletten" wert={zahl(gesamtPaletten)} />
          {/* Runde AO: „31 von 42" war nicht zu verstehen — die drei Zahlen getrennt. */}
          <Kennzahl titel="Chargen" wert={`${zahl(chargen.length)} angelegt`}
                    unter={<>{zahl(mitDaten)} mit Eingang · {zahl(imHaus.size)} mit Ware im Haus
                      {ohneEingang > 0 && <> · {zahl(ohneEingang)} angelegt, aber noch ohne Palette</>}</>} />
        </div>
        {/* Q9: ein Schalter, keine Rechnerei. Die App kann nicht wissen, ob
            zwischen zwei Lieferungen drei Tage Regen liegen oder die Saison
            vorbei ist — das weiss nur der Betrieb. */}
        <label className="haken" style={{ display: 'flex', alignItems: 'center', gap: '.6rem', minHeight: 44 }}>
          <input type="checkbox" id="ernte-fertig" checked={ernteFertig === true}
                 disabled={ernteFertig === null || speichert}
                 onChange={e => void ernteSetzen(e.target.checked)} />
          <span>Die Ernte ist eingebracht</span>
        </label>
        <p className="fussnote" style={{ marginBottom: 0 }}>
          {ernteFertig
            ? 'Die Erntespanne jeder Charge steht fest. Das mittlere Eingangsdatum, aus dem das Alter der Ware gerechnet wird, ändert sich nicht mehr.'
            : 'Solange der Haken fehlt, gilt jede Erntespanne als vorläufig — es kann noch eine Palette dazukommen und das mittlere Eingangsdatum verschieben.'}
        </p>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      </Karte>

    <Karte titel={`Chargen (${chargen.length})`}>
      {/* Runde AQ: ein Satz statt vier, ohne „Join-Schlüssel". */}
      <p className="leise">Die Nummern kommen aus dem Erntejournal. Demeter oder Knospe hier setzen geht vor Perigon.</p>
      <ChargeAnlegen chargen={chargen} angelegt={c => setChargen(alt => [...alt, c].sort((a, b) => a.nr - b.nr))} />
      <div className="rollbar">
        <table>
          <thead><tr><th>Nr</th><th>Schlag</th><th>Sorte</th>
            <th className="zahl">Paletten</th><th className="zahl">Eingang</th><th>Demeter / Knospe</th></tr></thead>
          <tbody>
            {chargen.map(c => {
              const p = perigon.get(c.nr)
              return (
                <tr key={c.nr}>
                  <td>{c.nr}</td><td>{c.schlag}</td><td>{c.sorte}</td>
                  <td className="zahl">{zahlen[c.nr]?.n ?? 0}</td>
                  <td className="zahl">{kg(zahlen[c.nr]?.kg)}</td>
                  <td className="nowrap">
                    <select value={c.label ?? ''} aria-label={`Label der Charge ${c.nr}`}
                            onChange={e => void labelSetzen(c, (e.target.value || null) as 'D' | 'K' | null)}>
                      <option value="">{p?.label
                        ? `${p.quelle === 'Perigon' ? 'aus Perigon' : p.quelle === 'Produzent' ? 'vom Produzenten' : 'angenommen'}: ${p.label === 'D' ? 'Demeter' : 'Knospe'}`
                        : '— unbekannt'}</option>
                      <option value="D">Demeter</option>
                      <option value="K">Knospe</option>
                    </select>
                    {p?.gemischt && <> <Marke art="neutral">Perigon liefert D und K — gilt als Demeter</Marke></>}
                    {p?.widerspruch && <> <Marke art="warnung">als Demeter verkauft, als Knospe geliefert</Marke></>}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </Karte>
    </>
  )
}

/**
 * Runde AS: „neue Chargen, Ötli 1719 und Trüb 1763 … schau, dass du damit
 * umgehen kannst". Das Erntejournal ordnet über Schlag und Sorte zu — eine
 * Charge, die es noch nicht gibt, legt der Betriebsleiter hier an, mit der
 * Nummer aus Perigon und Schlag und Sorte genau wie im Journal. Danach finden
 * Journal und Perigon sie von selbst.
 */
function ChargeAnlegen({ chargen, angelegt }: { chargen: Charge[]; angelegt: (c: Charge) => void }) {
  const [offen, setOffen] = useState(false)
  const [nr, setNr] = useState('')
  const [schlag, setSchlag] = useState('')
  const [sorte, setSorte] = useState('')
  const [saison, setSaison] = useState(String(new Date().getFullYear()))
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)
  const n = Number(nr)
  const nrOk = Number.isInteger(n) && n > 0 && n < 100000
  const doppelt = nrOk && chargen.some(c => c.nr === n)
  const bereit = nrOk && !doppelt && schlag.trim() !== '' && sorte.trim() !== '' && Number.isInteger(Number(saison))
  const sorten = [...new Set(chargen.map(c => c.sorte))].sort((a, b) => a.localeCompare(b, 'de'))
  const schlaege = [...new Set(chargen.map(c => c.schlag))].sort((a, b) => a.localeCompare(b, 'de'))
  async function anlegen() {
    if (!bereit || laeuft) return
    setLaeuft(true); setFehler(null)
    const neu = { nr: n, schlag: schlag.trim(), sorte: sorte.trim(), saison: Number(saison) }
    const { data, error } = await supabase.from('charge').insert(neu).select('*').single()
    setLaeuft(false)
    if (error) { setFehler(fehlerText(error)); return }
    angelegt(data as Charge)
    void stammdaten(true)
    setNr(''); setSchlag(''); setSorte(''); setOffen(false)
  }
  if (!offen) return <button type="button" className="knopf klein" id="charge-anlegen-auf" onClick={() => setOffen(true)}>Charge anlegen</button>
  return (
    <div className="charge-anlegen" id="charge-anlegen">
      <div className="feld"><label htmlFor="neu-nr">Nummer</label>
        <input id="neu-nr" inputMode="numeric" value={nr} onChange={e => setNr(e.target.value)} placeholder="1719" aria-invalid={nr !== '' && (!nrOk || doppelt)} /></div>
      <div className="feld"><label htmlFor="neu-schlag">Schlag (wie im Journal)</label>
        <input id="neu-schlag" list="neu-schlaege" value={schlag} onChange={e => setSchlag(e.target.value)} placeholder="Oettli" /></div>
      <div className="feld"><label htmlFor="neu-sorte">Sorte</label>
        <input id="neu-sorte" list="neu-sorten" value={sorte} onChange={e => setSorte(e.target.value)} /></div>
      <div className="feld"><label htmlFor="neu-saison">Saison</label>
        <input id="neu-saison" inputMode="numeric" value={saison} onChange={e => setSaison(e.target.value)} /></div>
      <datalist id="neu-sorten">{sorten.map(x => <option key={x} value={x} />)}</datalist>
      <datalist id="neu-schlaege">{schlaege.map(x => <option key={x} value={x} />)}</datalist>
      {doppelt && <Hinweis art="warnung">Charge {n} gibt es schon.</Hinweis>}
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <div className="knopf-reihe" style={{ display: 'flex' }}>
        <button type="button" className="haupt" id="charge-anlegen-ok" onClick={() => void anlegen()} disabled={!bereit || laeuft}>
          {laeuft ? 'Legt an …' : 'Anlegen'}</button>
        <button type="button" onClick={() => setOffen(false)}>Abbrechen</button>
      </div>
    </div>
  )
}

/* ------------------------------------------------------------------ */
/* Sortierschemata: je Sorte, datiert, nie überschrieben                */
/* ------------------------------------------------------------------ */
/**
 * Eine Fassung sagt, was zu klein, was Kaliber und was zu gross ist. Jede
 * trägt ein gilt_ab; geändert wird nie eine Zeile, es kommt eine neue dazu.
 * Sonst würde die Sortier-CSV vom Oktober mit den Grenzen vom Januar
 * klassiert — und der gemessene Anteil änderte sich, ohne dass ein Kürbis
 * anders gewogen wurde.
 *
 * Bis 0060 hing die Fassung am Käufer (Coop wollte Kaliberbänder, Migros
 * Kisten ab acht Kilo). Seit 0060 fragt die Arbeiter-App keinen Käufer mehr
 * und neue Fassungen gelten je Sorte. Die alten Zeilen behalten ihren Käufer
 * — sie sind erhoben worden und werden nicht umgeschrieben; darum steht er
 * hier weiter, wo er dransteht.
 */
function Kaliber() {
  const [zeilen, setZeilen] = useState<Sortierschema[]>([])
  const [kaeufer, setKaeufer] = useState<Kaeufer[]>([])
  const [sorten, setSorten] = useState<string[]>([])
  const [fehler, setFehler] = useState<string | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)

  // Neue Fassung
  const [fSorte, setFSorte] = useState('')
  const [fKaeufer, setFKaeufer] = useState('')
  const [fGiltAb, setFGiltAb] = useState(heuteOrtszeit())
  const [fArt, setFArt] = useState<'kaliber' | 'kiste'>('kaliber')
  const [fVerlust, setFVerlust] = useState('')
  const [fBaender, setFBaender] = useState('')
  const [fKanal, setFKanal] = useState('2000')
  const [fSoll, setFSoll] = useState('8')
  const [fBemerkung, setFBemerkung] = useState('')
  // Neuer Käufer
  const [kName, setKName] = useState('')
  /** Runde AO: „Ändern" füllt das Formular mit der geltenden Fassung. */
  const formular = useRef<HTMLDivElement | null>(null)
  function aendern(z: Sortierschema) {
    setFSorte(z.sorte); setFKaeufer(z.kaeufer ?? ''); setFGiltAb(heuteOrtszeit())
    setFArt(z.art === 'kiste' ? 'kiste' : 'kaliber')
    setFVerlust(z.verlust_unter == null ? '' : String(z.verlust_unter))
    setFBaender((z.kaliber_baender ?? []).map(([a, b]) => `${a}–${b}`).join(' · '))
    setFKanal(z.kanal_ab == null ? '2000' : String(z.kanal_ab))
    setFSoll(z.soll_kg_pro_kiste == null ? '8' : String(z.soll_kg_pro_kiste))
    setFBemerkung(''); setMeldung(null); setFehler(null)
    formular.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  const laden = useCallback(async () => {
    const [sc, k, st] = await Promise.all([
      supabase.from('sortierschema').select('*').order('sorte').order('kaeufer').order('gilt_ab', { ascending: false }),
      supabase.from('kaeufer').select('*').order('name'),
      stammdaten(),
    ])
    if (sc.error) setFehler(fehlerText(sc.error))
    setZeilen((sc.data ?? []) as Sortierschema[])
    setKaeufer((k.data ?? []) as Kaeufer[])
    setSorten(st.kaliber.map(x => x.sorte))
  }, [])
  useEffect(() => { void laden() }, [laden])

  /** „600–1100 · 1100–1600" oder „600-1100, 1100-1600" → [[600,1100],[1100,1600]] */
  function baenderLesen(text: string): [number, number][] | null {
    const teile = text.split(/[·,;\n]+/).map(x => x.trim()).filter(Boolean)
    const erg: [number, number][] = []
    for (const t of teile) {
      const m = t.match(/^(\d+)\s*[-–]\s*(\d+)$/)
      if (!m) return null
      erg.push([Number(m[1]), Number(m[2])])
    }
    return erg.length ? erg : null
  }

  async function fassungAnlegen() {
    setFehler(null); setMeldung(null)
    if (!fSorte) { setFehler('Sorte fehlt.'); return }
    const zeile: Record<string, unknown> = {
      sorte: fSorte, kaeufer: fKaeufer || null, gilt_ab: fGiltAb, art: fArt,
      bemerkung: fBemerkung.trim() || null,
    }
    if (fArt === 'kaliber') {
      const b = baenderLesen(fBaender)
      if (!b || fVerlust === '' || fKanal === '') {
        setFehler('Für Kaliberbänder braucht es Verlust-Grenze, Bänder (z. B. 600–1100 · 1100–1600) und Nebenkanal-Grenze.')
        return
      }
      Object.assign(zeile, { verlust_unter: Number(fVerlust), kaliber_baender: b, kanal_ab: Number(fKanal) })
    } else {
      if (fSoll === '') { setFehler('Soll je Kiste fehlt.'); return }
      Object.assign(zeile, { soll_kg_pro_kiste: Number(fSoll) })
    }
    // Runde AO: Gibt es für denselben Tag schon eine Fassung, wird sie
    // berichtigt statt eine zweite angelegt — ältere Tage bleiben, wie sie waren.
    const gleicherTag = zeilen.find(z => z.sorte === fSorte && (z.kaeufer ?? '') === fKaeufer && z.gilt_ab === fGiltAb)
    const { error } = gleicherTag
      ? await supabase.from('sortierschema').update(zeile).eq('id', gleicherTag.id)
      : await supabase.from('sortierschema').insert(zeile)
    if (error) { setFehler(fehlerText(error)); return }
    setMeldung(gleicherTag
      ? `Fassung für ${fSorte}${fKaeufer ? ` / ${fKaeufer}` : ''} ab ${datum(fGiltAb)} berichtigt.`
      : `Neue Fassung für ${fSorte}${fKaeufer ? ` / ${fKaeufer}` : ''} ab ${datum(fGiltAb)} angelegt.`)
    setFBaender(''); setFVerlust(''); setFBemerkung('')
    void laden()
  }

  async function kaeuferAnlegen() {
    const name = kName.trim()
    if (!name) return
    const code = name.toLowerCase().replace(/[^a-z0-9äöü]+/g, '-').replace(/(^-|-$)/g, '')
    const { error } = await supabase.from('kaeufer').insert({ code, name })
    if (error) setFehler(fehlerText(error)); else { setKName(''); void laden() }
  }

  const kaeuferName = (code: string | null) =>
    code === null ? 'Standard' : (kaeufer.find(k => k.code === code)?.name ?? code)
  const schemaText = (z: Sortierschema) =>
    z.art === 'kiste'
      ? `Kiste ab ${z.soll_kg_pro_kiste} kg`
      : `< ${zahl(z.verlust_unter)} g zu klein · ${(z.kaliber_baender ?? []).map(([a, b]) => `${a}–${b}`).join(' · ')} · ≥ ${zahl(z.kanal_ab)} g zu gross`

  // Je Sorte die aktuell gültige Fassung oben, ältere darunter; alte Fassungen
  // mit Käufer bleiben ein eigener Block, damit ihre Grenzen zuordenbar sind.
  const gruppen = new Map<string, Sortierschema[]>()
  for (const z of zeilen) {
    const k = `${z.sorte}|${z.kaeufer ?? ''}`
    gruppen.set(k, [...(gruppen.get(k) ?? []), z])
  }

  return (
    <>
      <Karte titel="Sortierschemata">
        <p className="leise">Was zu klein, was Kaliber und was zu gross ist, gilt ab einem Datum — „Ändern" legt eine neue Fassung an, die alten bleiben für die alten Sortier-CSV.</p>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {meldung && <Hinweis art="gut">{meldung}</Hinweis>}
        {/* Je Sorte ein Block (alte Fassungen mit Käufer je eigener), je Fassung
            eine Zeile. Eine Tabelle mit vier Spalten quetschte die Regel auf dem
            Handy in eine schmale Spalte und schnitt sie ab. */}
        <div className="fassungen">
          {[...gruppen.values()].map(fassungen => (
            <div key={`${fassungen[0].sorte}|${fassungen[0].kaeufer ?? ''}`} className="gruppe">
              <div className="kopf">
                <strong>{fassungen[0].sorte}</strong>
                <span className="leise">{kaeuferName(fassungen[0].kaeufer)}</span>
                <button type="button" className="werkzeug-knopf" style={{ marginLeft: 'auto' }}
                        onClick={() => aendern(fassungen[0])}><ZStift size={14} />Ändern</button>
              </div>
              {fassungen.map((z, i) => (
                <div key={z.id} className={`fassung${i === 0 ? '' : ' leise'}`}>
                  <span>{z.gilt_ab <= '2000-01-01' ? 'seit immer' : `ab ${datum(z.gilt_ab)}`}</span>
                  <span>
                    {schemaText(z)}
                    {bemerkungKurz(z.bemerkung) ? <span className="leise"> — {bemerkungKurz(z.bemerkung)}</span> : null}
                  </span>
                </div>
              ))}
            </div>
          ))}
        </div>
      </Karte>

      <div ref={formular} />
      <Karte titel="Fassung ändern oder neu anlegen">
        <p className="leise" style={{ marginTop: 0 }}>
          „Ändern" oben füllt dieses Formular mit der geltenden Fassung. Gespeichert gilt sie ab dem gewählten Tag;
          was vorher sortiert wurde, behält seine Grenzen. Am selben Tag nochmals speichern berichtigt die Fassung dieses Tages.
        </p>
        <div className="spalten">
          <div className="feld">
            <label htmlFor="f-sorte">Sorte</label>
            <select id="f-sorte" value={fSorte} onChange={e => setFSorte(e.target.value)}>
              <option value="">— wählen —</option>
              {sorten.map(x => <option key={x}>{x}</option>)}
            </select>
          </div>
          <div className="feld">
            <label htmlFor="f-kaeufer">Käufer</label>
            <select id="f-kaeufer" value={fKaeufer} onChange={e => setFKaeufer(e.target.value)}>
              <option value="">Standard (ohne bestimmten Käufer)</option>
              {kaeufer.map(k => <option key={k.code} value={k.code}>{k.name}</option>)}
            </select>
          </div>
          <div className="feld">
            <label htmlFor="f-ab">gilt ab</label>
            <input id="f-ab" type="date" value={fGiltAb} onChange={e => setFGiltAb(e.target.value)} />
          </div>
          <div className="feld">
            <label htmlFor="f-art">Art</label>
            <select id="f-art" value={fArt} onChange={e => setFArt(e.target.value as 'kaliber' | 'kiste')}>
              <option value="kaliber">Kaliberbänder (Gramm)</option>
              <option value="kiste">Kiste ab x kg</option>
            </select>
          </div>
        </div>
        {fArt === 'kaliber' ? (
          <div className="spalten">
            <div className="feld">
              <label htmlFor="f-verlust">zu klein unter (g)</label>
              <input id="f-verlust" type="number" min={0} value={fVerlust}
                     onChange={e => setFVerlust(e.target.value)} />
            </div>
            <div className="feld">
              <label htmlFor="f-baender">Bänder (z. B. 600–1100 · 1100–1600 · 1600–2000)</label>
              <input id="f-baender" value={fBaender} onChange={e => setFBaender(e.target.value)} />
            </div>
            <div className="feld">
              <label htmlFor="f-kanal">zu gross ab (g)</label>
              <input id="f-kanal" type="number" min={0} value={fKanal}
                     onChange={e => setFKanal(e.target.value)} />
            </div>
          </div>
        ) : (
          <div className="feld">
            <label htmlFor="f-soll">Soll je Kiste (kg)</label>
            <input id="f-soll" type="number" step="0.1" min={0} value={fSoll}
                   onChange={e => setFSoll(e.target.value)} />
          </div>
        )}
        <div className="feld">
          <label htmlFor="f-bem">Bemerkung <span className="leise">(freiwillig)</span></label>
          <input id="f-bem" value={fBemerkung} onChange={e => setFBemerkung(e.target.value)} />
        </div>
        <button className="haupt" onClick={fassungAnlegen}>Fassung speichern</button>
        <p className="leise" style={{ marginTop: '.5rem' }}>
          Bereits eingelesene Läufe bleiben nach ihrer alten Fassung klassiert. Soll
          ein Lauf nach einer anderen Fassung gerechnet werden, ordne ihn unter
          „Warteschlange" einem Auftrag mit dem passenden Käufer zu.
        </p>
      </Karte>

      <Karte titel={`Käufer (${kaeufer.length})`}>
        <p className="leise">
          Die Arbeiter können beim Starten einer Arbeit selbst einen neuen Käufer
          anlegen — hier stehen alle, mit denen je gearbeitet wurde.
        </p>
        <div className="reihe" style={{ alignItems: 'flex-end' }}>
          <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
            <label htmlFor="k-name">Neuer Käufer</label>
            <input id="k-name" value={kName} onChange={e => setKName(e.target.value)}
                   placeholder="z. B. Coop" />
          </div>
          <button onClick={kaeuferAnlegen} disabled={!kName.trim()}>Anlegen</button>
        </div>
        {kaeufer.length > 0 && (
          <p style={{ marginTop: '.75rem', marginBottom: 0 }}>
            {kaeufer.map(k => k.name).join(' · ')}
          </p>
        )}
      </Karte>
    </>
  )
}

/**
 * Runde AQ: Die Vorbelegungen beim Einrichten tragen eine Entwickler-Bemerkung
 * („Ausgangswert aus der Spezifikation (§6)", „Standard beim Einrichten —
 * Sollgewicht aus der Einstellung. Echtes Sollgewicht je Sorte: …"), die bei
 * jeder Sorte zweimal dastand. In der Liste heisst sie „Vorgabe"; was der
 * Betrieb selbst schreibt, bleibt Wort für Wort.
 */
function bemerkungKurz(b: string | null | undefined): string | null {
  if (!b) return null
  if (/^Ausgangswert aus der Spezifikation/.test(b) || /^Standard beim Einrichten/.test(b)) return 'Vorgabe'
  return b
}

/* ------------------------------------------------------------------ */
/* Sorten und Artikel (Runde AO, 0112)                                  */
/* ------------------------------------------------------------------ */
/**
 * Als welcher Artikel eine Sorte verkauft wird, und was der Artikel gross
 * und klein nennt. Beides braucht „Lagermanagement nach Artikel": die Gruppe fasst die
 * Sorten zusammen (Kaori Kuri, Amoro, … sind alle Knirps), die Kaliber teilen
 * das Verkaufsfähige in gross und klein. Vorbelegt aus den Verkäufen 2026 und
 * den Coop-Artikeldaten 2026; leer heisst: die Gruppe, als die die Sorte am
 * meisten verkauft wurde.
 */
const ARTIKELGRUPPEN = ['Knirps', 'Butternut', 'Butterkin/Muskat', 'Kabocha', 'Mandarin', 'Mix', 'andere']

function SortenArtikel() {
  const [sorten, setSorten] = useState<{ sorte: string; artikelgruppe: string | null; gruppe_verkauft: string | null }[]>([])
  const [eigene, setEigene] = useState<Map<string, string | null>>(new Map())
  const [kaliber, setKaliber] = useState<{ gruppe: string; groesse: string; von_g: number; bis_g: number; stueck_je_kiste: number | null; bemerkung: string | null }[]>([])
  const [entwurf, setEntwurf] = useState<Map<string, { von: string; bis: string; stueck: string }>>(new Map())
  const [fehler, setFehler] = useState<string | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)
  const laden = useCallback(async () => {
    const [v, sk, k] = await Promise.all([
      supabase.from('v_sorte_artikelgruppe').select('sorte, artikelgruppe, gruppe_verkauft').order('sorte'),
      supabase.from('sorte_kaliber').select('sorte, artikelgruppe'),
      supabase.from('artikel_kaliber').select('gruppe, groesse, von_g, bis_g, stueck_je_kiste, bemerkung').order('gruppe').order('von_g'),
    ])
    for (const r of [v, sk, k]) if (r.error) { setFehler(fehlerText(r.error)); return }
    setSorten((v.data ?? []) as typeof sorten)
    setEigene(new Map(((sk.data ?? []) as { sorte: string; artikelgruppe: string | null }[]).map(x => [x.sorte, x.artikelgruppe])))
    setKaliber((k.data ?? []) as typeof kaliber)
  }, [])
  useEffect(() => { void laden() }, [laden])

  async function gruppeSetzen(sorte: string, gruppe: string | null) {
    setFehler(null); setMeldung(null)
    const { error } = await supabase.from('sorte_kaliber').update({ artikelgruppe: gruppe }).eq('sorte', sorte)
    if (error) { setFehler(fehlerText(error)); return }
    setMeldung(`${sorte}: ${gruppe ?? 'wie verkauft'}`)
    void laden()
  }
  async function kaliberSpeichern(k: typeof kaliber[number]) {
    const e = entwurf.get(`${k.gruppe}|${k.groesse}`)
    if (!e) return
    setFehler(null); setMeldung(null)
    const von = Number(e.von), bis = Number(e.bis), stueck = e.stueck === '' ? null : Number(e.stueck)
    if (!(von >= 0) || !(bis > von)) { setFehler('Das Kaliber braucht „von" kleiner als „bis".'); return }
    const { error } = await supabase.from('artikel_kaliber').update({ von_g: von, bis_g: bis, stueck_je_kiste: stueck })
      .eq('gruppe', k.gruppe).eq('groesse', k.groesse)
    if (error) { setFehler(fehlerText(error)); return }
    setEntwurf(m => { const n = new Map(m); n.delete(`${k.gruppe}|${k.groesse}`); return n })
    setMeldung(`${k.gruppe} ${k.groesse}: ${von}–${bis} g gespeichert`)
    void laden()
  }
  const wert = (k: typeof kaliber[number]) => entwurf.get(`${k.gruppe}|${k.groesse}`)
    ?? { von: String(k.von_g), bis: String(k.bis_g), stueck: k.stueck_je_kiste == null ? '' : String(k.stueck_je_kiste) }
  const setze = (k: typeof kaliber[number], teil: Partial<{ von: string; bis: string; stueck: string }>) =>
    setEntwurf(m => new Map(m).set(`${k.gruppe}|${k.groesse}`, { ...wert(k), ...teil }))

  return (
    <>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {meldung && <Hinweis art="gut">{meldung}</Hinweis>}
      <Karte titel="Als welcher Artikel geht die Sorte?">
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Sorte</th><th>Artikelgruppe</th><th>verkauft als</th></tr></thead>
          <tbody>{sorten.map(x => (
            <tr key={x.sorte}>
              <td>{x.sorte}</td>
              <td>
                <select value={eigene.get(x.sorte) ?? ''} aria-label={`Artikelgruppe von ${x.sorte}`}
                        onChange={e => void gruppeSetzen(x.sorte, e.target.value || null)}>
                  <option value="">{x.gruppe_verkauft ? `wie verkauft (${x.gruppe_verkauft})` : '— unbekannt'}</option>
                  {ARTIKELGRUPPEN.map(g => <option key={g} value={g}>{g}</option>)}
                </select>
              </td>
              <td className="leise">{x.gruppe_verkauft ?? '—'}
                {x.gruppe_verkauft && eigene.get(x.sorte) && x.gruppe_verkauft !== eigene.get(x.sorte) && <> <Marke art="warnung">anders als eingetragen</Marke></>}</td>
            </tr>
          ))}</tbody>
        </table></div>
        <p className="leise">„verkauft als" kommt aus dem Warenausgang: als welcher Artikel die Chargen der Sorte geliefert wurden.</p>
      </Karte>
      <Karte titel="Was gross und klein heisst">
        <div className="rollbar"><table className="dicht">
          <thead><tr><th>Artikelgruppe</th><th>Grösse</th><th className="zahl">von (g)</th><th className="zahl">bis (g)</th><th className="zahl">Stück je Kiste</th><th></th></tr></thead>
          <tbody>{kaliber.map(k => {
            const w = wert(k), geaendert = entwurf.has(`${k.gruppe}|${k.groesse}`)
            return (
              <tr key={`${k.gruppe}|${k.groesse}`}>
                <td>{k.gruppe}</td><td>{k.groesse === 'stueck' ? 'eine Grösse' : k.groesse}</td>
                <td className="zahl"><input type="number" min={0} value={w.von} style={{ width: '5.5rem' }} aria-label={`${k.gruppe} ${k.groesse} von`} onChange={e => setze(k, { von: e.target.value })} /></td>
                <td className="zahl"><input type="number" min={0} value={w.bis} style={{ width: '5.5rem' }} aria-label={`${k.gruppe} ${k.groesse} bis`} onChange={e => setze(k, { bis: e.target.value })} /></td>
                <td className="zahl"><input type="number" min={1} value={w.stueck} style={{ width: '4.5rem' }} aria-label={`${k.gruppe} ${k.groesse} Stück je Kiste`} onChange={e => setze(k, { stueck: e.target.value })} /></td>
                <td>{geaendert && <button type="button" className="klein" onClick={() => void kaliberSpeichern(k)}><ZHaken size={14} />speichern</button>}</td>
              </tr>
            )
          })}</tbody>
        </table></div>
        <p className="leise">Vorbelegt aus den Coop-Artikeldaten 2026. Ein Kürbis zählt klein, wenn er von ≤ Gewicht &lt; bis wiegt; was in kein Kaliber passt, steht in „Lagermanagement nach Artikel" als ausserhalb (lose verkäuflich).</p>
      </Karte>
    </>
  )
}

/* ------------------------------------------------------------------ */
/* Abgebrochene Arbeiten aufräumen                                     */
/* ------------------------------------------------------------------ */
function Abgebrochene() {
  const [zeilen, setZeilen] = useState<{ id: number; charge_nr: number; weg: string
    station: string; start_ts: string; abgebrochen_ts: string; abbruch_grund: string | null }[]>([])
  const [fehler, setFehler] = useState<string | null>(null)
  const [sicher, setSicher] = useState<number | null>(null)

  const laden = useCallback(async () => {
    const { data, error } = await supabase.from('auftrag')
      .select('id, charge_nr, weg, station, start_ts, abgebrochen_ts, abbruch_grund')
      .not('abgebrochen_ts', 'is', null).order('abgebrochen_ts', { ascending: false })
    if (error) setFehler(fehlerText(error)); else setZeilen((data ?? []) as typeof zeilen)
  }, [])
  useEffect(() => { void laden() }, [laden])

  async function loeschen(id: number) {
    const { error } = await supabase.rpc('auftrag_endgueltig_loeschen', { p_auftrag_id: id })
    setSicher(null)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  return (
    <Karte titel={`Abgebrochene Arbeiten (${zeilen.length})`}>
      <Hinweis>
        Ein Arbeiter kann eine laufende Arbeit abbrechen — etwa wenn die falsche
        Charge gewählt wurde. Die erfassten Zeilen bleiben dann als Spur stehen,
        zählen aber in <strong>keiner</strong> Auswertung mehr mit.
        <p style={{ margin: '.4rem 0 0' }}>
          Endgültiges Löschen räumt zusätzlich die Palettenwägungen weg, die sonst
          verwaist zurückblieben und weiter in die Verdunstungsrate zählten. Eine
          zugeordnete Sortier-CSV wandert zurück in die Warteschlange.
        </p>
      </Hinweis>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {zeilen.length === 0 && <p className="leise">Nichts abgebrochen.</p>}
      {zeilen.map(z => (
        <div key={z.id} style={{ borderBottom: '1px solid var(--rand)', padding: '.75rem 0' }}>
          <div className="reihe">
            <strong>Charge {z.charge_nr}</strong>
            <Marke art="warnung">abgebrochen</Marke>
            <span className="leise" style={{ marginLeft: 'auto' }}>
              {zeitpunkt(z.abgebrochen_ts)}
            </span>
          </div>
          <p className="leise" style={{ margin: '.2rem 0' }}>
            {STATION_NAME[z.station] ?? z.station} · gestartet {zeitpunkt(z.start_ts)}
            {z.abbruch_grund && ` · ${z.abbruch_grund}`}
          </p>
          {sicher === z.id ? (
            <div className="reihe">
              <button className="gefahr" onClick={() => loeschen(z.id)}>
                Ja, endgültig löschen
              </button>
              <button onClick={() => setSicher(null)}>Doch nicht</button>
            </div>
          ) : (
            <button className="gefahr" style={{ minHeight: 34, padding: '.3rem .7rem' }}
                    onClick={() => setSicher(z.id)}>Endgültig löschen</button>
          )}
        </div>
      ))}
    </Karte>
  )
}

/* ------------------------------------------------------------------ */
function Benutzer() {
  const [zeilen, setZeilen] = useState<Profil[]>([])
  const [fehler, setFehler] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const { data, error } = await supabase.from('profil').select('*').order('name')
    if (error) setFehler(fehlerText(error)); else setZeilen((data ?? []) as Profil[])
  }, [])
  useEffect(() => { void laden() }, [laden])

  async function rolleSetzen(p: Profil, rolle: 'admin' | 'arbeiter') {
    const { error } = await supabase.from('profil').update({ rolle }).eq('id', p.id)
    if (error) setFehler(fehlerText(error)); else void laden()
  }
  /** Runde AD (0097): wer laufende Arbeiten abbrechen darf, auch fremde —
   *  der Betriebsleiter setzt den Haken, die Datenbank prüft ihn. */
  async function erlaubnisSetzen(p: Profil, darf: boolean) {
    const { error } = await supabase.from('profil').update({ darf_abbrechen: darf }).eq('id', p.id)
    if (error) setFehler(fehlerText(error)); else void laden()
  }

  return (
    <Karte titel="Benutzer">
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <div className="rollbar">
        <table>
          <thead><tr><th>Name</th><th>Rolle</th><th>Darf laufende Arbeiten abbrechen</th><th /></tr></thead>
          <tbody>
            {zeilen.map(p => (
              <tr key={p.id}>
                <td>{p.name}</td>
                <td>{p.rolle === 'admin' ? 'Betriebsleiter' : 'Arbeiter'}</td>
                <td>
                  {p.rolle === 'admin'
                    ? <span className="leise">immer</span>
                    : <button type="button" role="checkbox" aria-checked={!!p.darf_abbrechen} aria-label={`${p.name} darf laufende Arbeiten abbrechen`}
                              className={`wahlkreis${p.darf_abbrechen ? ' an' : ''}`} onClick={() => void erlaubnisSetzen(p, !p.darf_abbrechen)}>
                        {p.darf_abbrechen && <ZHaken size={14} />}
                      </button>}
                </td>
                <td style={{ textAlign: 'right' }}>
                  <button style={{ minHeight: 32, padding: '.2rem .6rem' }}
                          onClick={() => rolleSetzen(p, p.rolle === 'admin' ? 'arbeiter' : 'admin')}>
                    {p.rolle === 'admin' ? 'zum Arbeiter' : 'zum Betriebsleiter'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="fussnote">Wer den Haken hat, kann auf der Startseite laufende Arbeiten auswählen und abbrechen — auch solche, die andere begonnen haben. Der Betriebsleiter darf es immer; fertige Arbeiten bricht niemand ab.</p>
    </Karte>
  )
}

/* ------------------------------------------------------------------ */
function Einstellungen() {
  const [zeilen, setZeilen] = useState<{ schluessel: string; wert: unknown; bemerkung: string | null }[]>([])
  const [fehler, setFehler] = useState<string | null>(null)
  const [gespeichert, setGespeichert] = useState<string | null>(null)

  const laden = useCallback(async () => {
    const { data, error } = await supabase.from('einstellung').select('*').order('schluessel')
    if (error) setFehler(fehlerText(error)); else setZeilen((data ?? []) as typeof zeilen)
  }, [])
  useEffect(() => { void laden() }, [laden])

  async function speichern(schluessel: string, roh: string) {
    let wert: unknown
    try { wert = JSON.parse(roh) } catch { setFehler(`„${roh}" ist kein gültiger Wert.`); return }
    const { error } = await supabase.from('einstellung').update({ wert }).eq('schluessel', schluessel)
    if (error) setFehler(fehlerText(error))
    else { setGespeichert(schluessel); setTimeout(() => setGespeichert(null), 2000); void laden() }
  }

  return (
    <Karte titel="Einstellungen">
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {zeilen.map(z => (
        <div key={z.schluessel} style={{ borderBottom: '1px solid var(--rand)', padding: '.75rem 0' }}>
          <div className="reihe">
            <strong>{z.schluessel}</strong>
            {gespeichert === z.schluessel && <Marke art="fertig">gespeichert</Marke>}
          </div>
          {z.bemerkung && <p className="leise" style={{ margin: '.2rem 0 .5rem' }}>{z.bemerkung}</p>}
          <div className="reihe" style={{ alignItems: 'flex-end' }}>
            <input defaultValue={JSON.stringify(z.wert)} style={{ flex: 1 }}
                   onKeyDown={e => { if (e.key === 'Enter') speichern(z.schluessel, e.currentTarget.value) }} />
            <button onClick={e => {
              const feld = (e.currentTarget.previousElementSibling as HTMLInputElement)
              speichern(z.schluessel, feld.value)
            }}>Speichern</button>
          </div>
        </div>
      ))}
    </Karte>
  )
}


/* ------------------------------------------------------------------ */
/* Erfassungsbeginn: was vor der App schon rausging (AB-07)            */
/* ------------------------------------------------------------------ */
function Vorlauf() {
  const [chargen, setChargen] = useState<Charge[]>([])
  const [beginn, setBeginn] = useState('')
  const [werte, setWerte] = useState<Record<number, string>>({})
  const [fehler, setFehler] = useState<string | null>(null)
  const [gespeichert, setGespeichert] = useState<number | 'beginn' | null>(null)

  const laden = useCallback(async () => {
    const [s, b, v] = await Promise.all([
      stammdaten(),
      einstellung<string | null>('erfassungsbeginn', null),
      supabase.from('charge_vorlauf').select('charge_nr, ausgang_vor_app_kg'),
    ])
    setChargen(s.chargen)
    setBeginn(b ?? '')
    const map: Record<number, string> = {}
    for (const r of (v.data ?? []) as { charge_nr: number; ausgang_vor_app_kg: number }[]) {
      map[r.charge_nr] = String(r.ausgang_vor_app_kg)
    }
    setWerte(map)
  }, [])
  useEffect(() => { void laden() }, [laden])

  async function beginnSpeichern() {
    const { error } = await supabase.from('einstellung')
      .update({ wert: beginn || null }).eq('schluessel', 'erfassungsbeginn')
    if (error) setFehler(fehlerText(error))
    else { setGespeichert('beginn'); setTimeout(() => setGespeichert(null), 2000) }
  }

  async function vorlaufSpeichern(nr: number) {
    const kg = werte[nr]
    if (kg === undefined || kg === '') {
      await supabase.from('charge_vorlauf').delete().eq('charge_nr', nr)
    } else {
      const { error } = await supabase.from('charge_vorlauf')
        .upsert({ charge_nr: nr, ausgang_vor_app_kg: Number(kg) }, { onConflict: 'charge_nr' })
      if (error) { setFehler(fehlerText(error)); return }
    }
    setGespeichert(nr); setTimeout(() => setGespeichert(null), 2000)
  }

  return (
    <Karte titel="Erfassungsbeginn">
      <p className="leise" style={{ marginTop: 0 }}>
        Die Saison lief schon, als die App kam. Trage ein, ab wann die App
        mitzählt und wie viel je Charge davor schon ausgeliefert war — sonst
        weist die Bilanz den späten Start als fehlende Masse aus.
      </p>
      <div className="reihe" style={{ alignItems: 'flex-end', marginBottom: '1rem' }}>
        <div className="feld" style={{ flex: 1, marginBottom: 0 }}>
          <label htmlFor="v-beginn">Erfassungsbeginn</label>
          <input id="v-beginn" type="date" value={beginn}
                 onChange={e => setBeginn(e.target.value)} />
        </div>
        <button className="haupt" onClick={beginnSpeichern}>Speichern</button>
        {gespeichert === 'beginn' && <Marke art="fertig">gespeichert</Marke>}
      </div>
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <table>
        <thead><tr><th>Charge</th><th>Vorher ausgeliefert (kg)</th><th></th></tr></thead>
        <tbody>
          {chargen.map(c => (
            <tr key={c.nr}>
              <td>{c.nr} · {c.sorte}</td>
              <td>
                <input type="number" inputMode="decimal" min={0} style={{ width: '8rem' }}
                       value={werte[c.nr] ?? ''}
                       onChange={e => setWerte(w => ({ ...w, [c.nr]: e.target.value }))} />
              </td>
              <td style={{ textAlign: 'right' }}>
                <button className="klein" onClick={() => void vorlaufSpeichern(c.nr)}>Speichern</button>
                {gespeichert === c.nr && <Marke art="fertig">ok</Marke>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Karte>
  )
}
