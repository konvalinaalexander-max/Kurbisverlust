import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { einstellung, fehlerText, stammdaten } from '../lib/db'
import { importErkennen, type ImportBericht } from '../lib/import'
import { STATION_NAME, datum, kg, tonnen, zahl, zeitpunkt } from '../lib/format'
import { Hinweis, Karte, Kennzahl, Lade, Marke } from '../components/Bausteine'
import DemoDaten from '../components/DemoDaten'
import type { Charge, Gebinde, Kaeufer, Profil, Sortierschema } from '../lib/typen'

export default function Stammdaten() {
  const [teil, setTeil] = useState<'gebinde' | 'paletten' | 'chargen' | 'kaliber'
    | 'abgebrochen' | 'benutzer' | 'einstellungen' | 'vorlauf' | 'demo'>('gebinde')
  const teile: [typeof teil, string][] = [
    ['gebinde', 'Gebinde & Tara'],
    ['paletten', 'Paletten-Import'],
    ['chargen', 'Chargen'],
    ['kaliber', 'Sortierschemata'],
    ['abgebrochen', 'Abgebrochene Arbeiten'],
    ['benutzer', 'Benutzer'],
    ['einstellungen', 'Einstellungen'],
    ['vorlauf', 'Erfassungsbeginn'],
    ['demo', 'Demo-Daten'],
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
      {teil === 'abgebrochen' && <Abgebrochene />}
      {teil === 'benutzer' && <Benutzer />}
      {teil === 'einstellungen' && <Einstellungen />}
      {teil === 'vorlauf' && <Vorlauf />}
      {teil === 'demo' && <DemoDaten />}
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
      const arten = [...new Set(bericht.paletten.map(z => z.gebindeart).filter(Boolean))] as string[]
      if (arten.length) {
        const { error } = await supabase.from('gebinde')
          .upsert(arten.map(art => ({ art })), { onConflict: 'art', ignoreDuplicates: true })
        if (error) throw error
      }
      for (let i = 0; i < bericht.paletten.length; i += 500) {
        const { error } = await supabase.from('palette')
          .upsert(bericht.paletten.slice(i, i + 500), { onConflict: 'extern_id' })
        if (error) throw error
      }
      setMeldung(`${bericht.paletten.length} Paletten übernommen.`)
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
            {ohneGebinde > 0 && ` · ${ohneGebinde} ohne Gebindeart (gelten als G2)`}
          </p>
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

  return (
    <>
      <Karte titel="Ernte bisher erfasst">
        <div className="spalten">
          <Kennzahl titel="Netto insgesamt" wert={tonnen(gesamtKg)}
                    unter="aus dem Erntejournal übernommen" />
          <Kennzahl titel="Paletten" wert={zahl(gesamtPaletten)} />
          <Kennzahl titel="Chargen mit Ware" wert={`${mitDaten} von ${chargen.length}`} />
        </div>
        <p className="leise" style={{ marginBottom: 0 }}>
          Das ist die bisher eingelagerte Menge — sie wächst mit jedem Import aus
          dem Google Sheet. Die genaue Verlust-Auswertung steht im Dashboard.
        </p>
      </Karte>

    <Karte titel={`Chargen (${chargen.length})`}>
      <p className="leise">
        Die Chargennummer ist der Join-Schlüssel des ganzen Systems — sie kommt
        aus dem Erntejournal und wird hier nicht neu vergeben.
      </p>
      <div className="rollbar">
        <table>
          <thead><tr><th>Nr</th><th>Schlag</th><th>Sorte</th>
            <th className="zahl">Paletten</th><th className="zahl">Eingang</th></tr></thead>
          <tbody>
            {chargen.map(c => (
              <tr key={c.nr}>
                <td>{c.nr}</td><td>{c.schlag}</td><td>{c.sorte}</td>
                <td className="zahl">{zahlen[c.nr]?.n ?? 0}</td>
                <td className="zahl">{kg(zahlen[c.nr]?.kg)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Karte>
    </>
  )
}

/* ------------------------------------------------------------------ */
/* Sortierschemata: je Sorte und Käufer, datiert, nie überschrieben     */
/* ------------------------------------------------------------------ */
/**
 * Das Sortierschema hängt am Käufer, nicht an der Sorte (Betrieb, 2. Sept.):
 * Coop will Kaliberbänder, Migros will Kisten ab acht Kilo, und beim nächsten
 * Auftrag ist es wieder anders. Jede Fassung trägt ein gilt_ab; geändert wird
 * nie eine Zeile, es kommt eine neue dazu. Sonst würde die Sortier-CSV vom
 * Oktober mit den Grenzen vom Januar klassiert — und der gemessene Anteil
 * änderte sich, ohne dass ein Kürbis anders gewogen wurde.
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
  const [fGiltAb, setFGiltAb] = useState(new Date().toISOString().slice(0, 10))
  const [fArt, setFArt] = useState<'kaliber' | 'kiste'>('kaliber')
  const [fVerlust, setFVerlust] = useState('')
  const [fBaender, setFBaender] = useState('')
  const [fKanal, setFKanal] = useState('2000')
  const [fSoll, setFSoll] = useState('8')
  const [fBemerkung, setFBemerkung] = useState('')
  // Neuer Käufer
  const [kName, setKName] = useState('')

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
    const { error } = await supabase.from('sortierschema').insert(zeile)
    if (error) { setFehler(fehlerText(error)); return }
    setMeldung(`Neue Fassung für ${fSorte}${fKaeufer ? ` / ${fKaeufer}` : ''} ab ${datum(fGiltAb)} angelegt.`)
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

  // Je (Sorte × Käufer) die aktuell gültige Fassung oben, ältere darunter.
  const gruppen = new Map<string, Sortierschema[]>()
  for (const z of zeilen) {
    const k = `${z.sorte}|${z.kaeufer ?? ''}`
    gruppen.set(k, [...(gruppen.get(k) ?? []), z])
  }

  return (
    <>
      <Karte titel="Sortierschemata">
        <p className="leise">
          Was zu klein, was Kaliber und was zu gross ist, hängt am Käufer — und
          gilt ab einem Datum. Eine Fassung wird nie geändert: Es kommt eine neue
          dazu, damit jede alte Sortier-CSV nach den Regeln klassiert bleibt, die
          an ihrem Tag galten. Jeder Auftrag merkt sich seine Fassung.
        </p>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {meldung && <Hinweis art="gut">{meldung}</Hinweis>}
        <div className="rollbar">
          <table>
            <thead><tr><th>Sorte</th><th>Käufer</th><th>gilt ab</th><th>Regel</th></tr></thead>
            <tbody>
              {[...gruppen.values()].map(fassungen => fassungen.map((z, i) => (
                <tr key={z.id} className={i === 0 ? '' : 'leise'}>
                  <td>{i === 0 ? z.sorte : ''}</td>
                  <td>{i === 0 ? kaeuferName(z.kaeufer) : ''}</td>
                  <td>{z.gilt_ab <= '2000-01-01' ? 'seit immer' : datum(z.gilt_ab)}</td>
                  <td>{schemaText(z)}{z.bemerkung ? <span className="leise"> — {z.bemerkung}</span> : null}</td>
                </tr>
              )))}
            </tbody>
          </table>
        </div>
      </Karte>

      <Karte titel="Neue Fassung anlegen">
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
        <button className="haupt" onClick={fassungAnlegen}>Fassung anlegen</button>
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

  return (
    <Karte titel="Benutzer">
      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      <div className="rollbar">
        <table>
          <thead><tr><th>Name</th><th>Rolle</th><th /></tr></thead>
          <tbody>
            {zeilen.map(p => (
              <tr key={p.id}>
                <td>{p.name}</td>
                <td>{p.rolle === 'admin' ? 'Betriebsleiter' : 'Arbeiter'}</td>
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
