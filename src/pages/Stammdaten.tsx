import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { einstellung, fehlerText, stammdaten } from '../lib/db'
import { importErkennen, type ImportBericht } from '../lib/import'
import { datum, kg, tonnen, zahl } from '../lib/format'
import { Hinweis, Karte, Kennzahl, Lade, Marke } from '../components/Bausteine'
import type { Charge, Gebinde, Profil, SorteKaliber } from '../lib/typen'

export default function Stammdaten() {
  const [teil, setTeil] = useState<'gebinde' | 'paletten' | 'chargen' | 'kaliber' | 'benutzer' | 'einstellungen'>('gebinde')
  const teile: [typeof teil, string][] = [
    ['gebinde', 'Gebinde & Tara'],
    ['paletten', 'Paletten-Import'],
    ['chargen', 'Chargen'],
    ['kaliber', 'Kaliber'],
    ['benutzer', 'Benutzer'],
    ['einstellungen', 'Einstellungen'],
  ]
  return (
    <>
      <h1>Stammdaten</h1>
      <nav className="navleiste" style={{ position: 'static', borderRadius: 'var(--radius)',
                                          border: '1px solid var(--rand)' }}>
        {teile.map(([t, name]) => (
          <a key={t} href="#" className={teil === t ? 'aktiv' : ''}
             onClick={e => { e.preventDefault(); setTeil(t) }}>{name}</a>
        ))}
      </nav>
      {teil === 'gebinde' && <GebindeTara />}
      {teil === 'paletten' && <PalettenImport />}
      {teil === 'chargen' && <Chargen />}
      {teil === 'kaliber' && <Kaliber />}
      {teil === 'benutzer' && <Benutzer />}
      {teil === 'einstellungen' && <Einstellungen />}
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
function Kaliber() {
  const [zeilen, setZeilen] = useState<SorteKaliber[]>([])
  useEffect(() => { void stammdaten().then(s => setZeilen(s.kaliber)) }, [])
  return (
    <Karte titel="Sorten-Kaliber-Grenzen">
      <p className="leise">
        Gramm, Konvention [untere, obere). Unter der Verlust-Grenze wird weggeworfen,
        ab der Nebenkanal-Grenze geht die Ware in einen anderen Verkaufskanal.
      </p>
      <div className="rollbar">
        <table>
          <thead><tr><th>Sorte</th><th className="zahl">Verlust unter</th>
            <th>Kaliber-Bänder</th><th className="zahl">Nebenkanal ab</th></tr></thead>
          <tbody>
            {zeilen.map(k => (
              <tr key={k.sorte}>
                <td>{k.sorte}</td>
                <td className="zahl">{zahl(k.verlust_unter)} g</td>
                <td>{k.kaliber_baender.map(([a, b]) => `${a}–${b}`).join(' · ')}</td>
                <td className="zahl">{zahl(k.kanal_ab)} g</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="leise" style={{ marginTop: '.75rem' }}>
        Zum Ändern der Grenzen: Supabase → Table Editor → <code>sorte_kaliber</code>.
        Danach <code>select lauf_neu_klassieren(id) from sortier_lauf</code> ausführen,
        damit bereits eingelesene Läufe neu klassiert werden.
      </p>
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
