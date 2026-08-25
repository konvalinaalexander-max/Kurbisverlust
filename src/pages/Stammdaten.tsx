import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { fehlerText, stammdaten } from '../lib/db'
import { datum, kg, zahl } from '../lib/format'
import { Hinweis, Karte, Lade, Marke } from '../components/Bausteine'
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
interface ImportZeile {
  charge_nr: number; eingangsdatum: string; brutto_kg: number
  kisten: number | null; gebindeart: string | null; extern_id: string
}

const SPALTEN: Record<string, string[]> = {
  charge_nr: ['charge', 'chargennummer', 'charge_nr', 'chargennr'],
  eingangsdatum: ['datum', 'eingangsdatum', 'eingang'],
  brutto_kg: ['brutto', 'bruttogewicht', 'brutto_kg', 'gewicht'],
  kisten: ['kisten', 'kistenzahl', 'anzahl kisten'],
  gebindeart: ['gebinde', 'gebindeart', 'art'],
}

function PalettenImport() {
  const [text, setText] = useState('')
  const [zeilen, setZeilen] = useState<ImportZeile[]>([])
  const [probleme, setProbleme] = useState<string[]>([])
  const [meldung, setMeldung] = useState<string | null>(null)
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  async function pruefen() {
    setFehler(null); setMeldung(null)
    try {
      const { chargen } = await stammdaten()
      const bekannt = new Set(chargen.map(c => c.nr))
      const rohZeilen = text.trim().split(/\r?\n/).filter(z => z.trim() !== '')
      if (rohZeilen.length < 2) { setFehler('Bitte Kopfzeile und mindestens eine Datenzeile einfügen.'); return }

      const trenner = rohZeilen[0].includes('\t') ? '\t' : ';'
      const kopf = rohZeilen[0].split(trenner).map(s => s.trim().toLowerCase())
      const spalte = (feld: string) => kopf.findIndex(k => SPALTEN[feld].some(n => k === n || k.includes(n)))

      const idx = Object.fromEntries(Object.keys(SPALTEN).map(f => [f, spalte(f)]))
      const fehlend = ['charge_nr', 'eingangsdatum', 'brutto_kg'].filter(f => idx[f] === -1)
      if (fehlend.length) {
        setFehler(`Diese Spalten fehlen: ${fehlend.join(', ')}. Gefunden: ${kopf.join(', ')}`)
        return
      }

      const neu: ImportZeile[] = []
      const meldungen: string[] = []
      const gesehen = new Map<string, number>()

      rohZeilen.slice(1).forEach((zeile, n) => {
        const f = zeile.split(trenner).map(s => s.trim())
        const nr = Number(f[idx.charge_nr])
        if (!bekannt.has(nr)) { meldungen.push(`Zeile ${n + 2}: Charge ${f[idx.charge_nr]} unbekannt`); return }
        const d = datumLesen(f[idx.eingangsdatum])
        if (!d) { meldungen.push(`Zeile ${n + 2}: Datum „${f[idx.eingangsdatum]}" nicht lesbar`); return }
        const brutto = Number(f[idx.brutto_kg].replace(',', '.'))
        if (!Number.isFinite(brutto) || brutto <= 0) {
          meldungen.push(`Zeile ${n + 2}: Bruttogewicht „${f[idx.brutto_kg]}" nicht lesbar`); return
        }
        const kisten = idx.kisten >= 0 && f[idx.kisten] ? Number(f[idx.kisten]) : null
        const gebinde = idx.gebindeart >= 0 && f[idx.gebindeart] ? f[idx.gebindeart] : null

        // Stabiler Schlüssel aus dem Zeileninhalt: derselbe Import zweimal
        // laufen zu lassen legt keine Dubletten an. Zwei wirklich gleiche
        // Paletten unterscheidet der Zähler am Ende.
        const kern = [nr, d, brutto, kisten ?? '', gebinde ?? ''].join('|')
        const lauf = (gesehen.get(kern) ?? 0) + 1
        gesehen.set(kern, lauf)

        neu.push({ charge_nr: nr, eingangsdatum: d, brutto_kg: brutto,
                   kisten, gebindeart: gebinde, extern_id: `${kern}#${lauf}` })
      })

      setZeilen(neu)
      setProbleme(meldungen)
    } catch (f) { setFehler(fehlerText(f)) }
  }

  async function importieren() {
    setLaeuft(true); setFehler(null)
    try {
      // Gebindearten anlegen, damit der Fremdschlüssel greift. Die Tara bleibt
      // bewusst leer — geraten wird sie nicht.
      const arten = [...new Set(zeilen.map(z => z.gebindeart).filter(Boolean))] as string[]
      if (arten.length) {
        const { error } = await supabase.from('gebinde')
          .upsert(arten.map(art => ({ art })), { onConflict: 'art', ignoreDuplicates: true })
        if (error) throw error
      }
      for (let i = 0; i < zeilen.length; i += 500) {
        const { error } = await supabase.from('palette')
          .upsert(zeilen.slice(i, i + 500), { onConflict: 'extern_id' })
        if (error) throw error
      }
      setMeldung(`${zeilen.length} Paletten übernommen.`)
      setZeilen([]); setText('')
      void stammdaten(true)
    } catch (f) { setFehler(fehlerText(f)) } finally { setLaeuft(false) }
  }

  const ohneGebinde = zeilen.filter(z => !z.gebindeart).length

  return (
    <Karte titel="Paletten aus dem Erntejournal">
      <Hinweis>
        Im Google Sheet den Bereich samt Kopfzeile markieren, kopieren und hier
        einfügen. Erkannt werden Spalten wie <em>Charge, Datum, Brutto, Kisten,
        Gebinde</em>. Derselbe Import mehrfach ausgeführt legt keine Dubletten an.
      </Hinweis>

      <div className="feld">
        <label htmlFor="einfuegen">Eingefügte Zeilen</label>
        <textarea id="einfuegen" rows={8} value={text} onChange={e => setText(e.target.value)}
                  placeholder={'Charge\tDatum\tBrutto\tKisten\tGebinde\n1613\t01.09.2026\t950\t40\tHolzkiste'} />
      </div>
      <button onClick={pruefen} disabled={!text.trim()}>Prüfen</button>

      {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
      {meldung && <Hinweis art="gut">{meldung}</Hinweis>}

      {probleme.length > 0 && (
        <Hinweis art="warnung">
          <strong>{probleme.length} Zeilen übersprungen</strong>
          <ul style={{ margin: '.4rem 0 0', paddingLeft: '1.2rem' }}>
            {probleme.slice(0, 10).map((p, i) => <li key={i}>{p}</li>)}
          </ul>
        </Hinweis>
      )}

      {zeilen.length > 0 && (
        <>
          <p style={{ marginTop: '1rem' }}>
            <strong>{zeilen.length} Paletten bereit</strong> ·
            {' '}{kg(zeilen.reduce((s, z) => s + z.brutto_kg, 0), 0)} brutto
            {ohneGebinde > 0 && ` · ${ohneGebinde} ohne Gebindeart`}
          </p>
          <div className="rollbar">
            <table>
              <thead><tr><th>Charge</th><th>Datum</th><th className="zahl">Brutto</th>
                <th className="zahl">Kisten</th><th>Gebinde</th></tr></thead>
              <tbody>
                {zeilen.slice(0, 10).map((z, i) => (
                  <tr key={i}>
                    <td>{z.charge_nr}</td><td>{datum(z.eingangsdatum)}</td>
                    <td className="zahl">{kg(z.brutto_kg, 1)}</td>
                    <td className="zahl">{z.kisten ?? '—'}</td><td>{z.gebindeart ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button className="haupt" style={{ width: '100%', marginTop: '.75rem' }}
                  onClick={importieren} disabled={laeuft}>
            {laeuft ? 'Läuft …' : `${zeilen.length} Paletten übernehmen`}
          </button>
        </>
      )}
    </Karte>
  )
}

/** Akzeptiert 01.09.2026, 2026-09-01 und 1.9.26. */
function datumLesen(roh: string): string | null {
  const t = roh.trim()
  if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t
  const m = t.match(/^(\d{1,2})[.\/](\d{1,2})[.\/](\d{2,4})$/)
  if (!m) return null
  const jahr = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])
  const p = (n: string) => n.padStart(2, '0')
  return `${jahr}-${p(m[2])}-${p(m[1])}`
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
  return (
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
