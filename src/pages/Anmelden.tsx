import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import { Hinweis } from '../components/Bausteine'

const NAME_SCHLUESSEL = 'arbeiter_name'

/**
 * Startseite ohne Anmeldung. Zwei Wege, bewusst unterschiedlich gewichtet:
 *
 *  - Arbeiter (der Normalfall): Name eintippen, „Los geht's" — fertig. Dahinter
 *    steckt eine anonyme Supabase-Anmeldung, die niemand als solche bemerkt.
 *    Kein Konto, keine Mail, kein Passwort. Genau das, was per QR-Code aufgehängt
 *    wird.
 *  - Betriebsleiter: kleiner Link unten, echtes Login mit Mail und Passwort.
 */
export default function Anmelden() {
  return (
    <div className="huelle" style={{ maxWidth: 460, paddingTop: '2.5rem' }}>
      <h1 style={{ fontSize: '1.8rem' }}>🎃 Kürbis-Verlust</h1>
      <ArbeiterStart />
      <BetriebsleiterLogin />
    </div>
  )
}

function ArbeiterStart() {
  const [name, setName] = useState(() => {
    try { return localStorage.getItem(NAME_SCHLUESSEL) ?? '' } catch { return '' }
  })
  const [fehler, setFehler] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  async function los(e: FormEvent) {
    e.preventDefault()
    const sauber = name.trim()
    if (!sauber) return
    setLaeuft(true); setFehler(null)
    try { localStorage.setItem(NAME_SCHLUESSEL, sauber) } catch { /* privater Modus */ }

    const { error } = await supabase.auth.signInAnonymously({ options: { data: { name: sauber } } })
    if (error) {
      setLaeuft(false)
      // Der häufigste Fall: der Betriebsleiter hat die anonyme Anmeldung in
      // Supabase noch nicht freigeschaltet. Das ist eine Einrichtungssache,
      // kein Fehler des Arbeiters — entsprechend formulieren.
      if (/anonymous|disabled|not enabled/i.test(error.message)) {
        setFehler('Der direkte Zugang ist noch nicht freigeschaltet. Bitte dem '
          + 'Betriebsleiter Bescheid geben: In Supabase unter Authentication → '
          + 'Sign In / Providers muss „Anonymous sign-ins" eingeschaltet werden '
          + '(siehe README).')
      } else {
        setFehler(error.message)
      }
    }
    // Erfolg: der AuthProvider bemerkt die neue Sitzung und zeigt die App.
  }

  return (
    <section className="karte" style={{ padding: '1.5rem' }}>
      <h2 style={{ marginTop: 0 }}>Ich arbeite mit</h2>
      <p className="leise">Nur deinen Namen eintippen — kein Passwort nötig.</p>
      <form onSubmit={los}>
        <div className="feld">
          <label htmlFor="name">Dein Name</label>
          <input id="name" value={name} onChange={e => setName(e.target.value)}
                 autoComplete="off" autoFocus placeholder="z. B. Hans"
                 style={{ fontSize: '1.15rem' }} />
        </div>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <button className="haupt gross" style={{ width: '100%' }}
                disabled={laeuft || !name.trim()}>
          {laeuft ? 'Einen Moment …' : "Los geht's"}
        </button>
      </form>
    </section>
  )
}

function BetriebsleiterLogin() {
  const [offen, setOffen] = useState(false)
  const [modus, setModus] = useState<'anmelden' | 'registrieren'>('anmelden')
  const [email, setEmail] = useState('')
  const [passwort, setPasswort] = useState('')
  const [name, setName] = useState('')
  const [fehler, setFehler] = useState<string | null>(null)
  const [meldung, setMeldung] = useState<string | null>(null)
  const [laeuft, setLaeuft] = useState(false)

  async function absenden(e: FormEvent) {
    e.preventDefault()
    setFehler(null); setMeldung(null); setLaeuft(true)
    try {
      if (modus === 'anmelden') {
        const { error } = await supabase.auth.signInWithPassword({ email, password: passwort })
        if (error) throw error
      } else {
        const { error } = await supabase.auth.signUp({
          email, password: passwort, options: { data: { name } },
        })
        if (error) throw error
        setMeldung('Konto angelegt. Falls Supabase eine Bestätigungsmail verlangt, '
          + 'zuerst den Link in der Mail öffnen.')
      }
    } catch (f) {
      setFehler((f as Error).message)
    } finally {
      setLaeuft(false)
    }
  }

  if (!offen) {
    return (
      <p style={{ textAlign: 'center', marginTop: '1.5rem' }}>
        <button style={{ background: 'none', border: 'none', color: 'var(--blau)' }}
                onClick={() => setOffen(true)}>
          Betriebsleiter-Login
        </button>
      </p>
    )
  }

  return (
    <section className="karte">
      <h2 style={{ marginTop: 0 }}>Betriebsleiter</h2>
      <form onSubmit={absenden}>
        {modus === 'registrieren' && (
          <div className="feld">
            <label htmlFor="bl-name">Name</label>
            <input id="bl-name" value={name} onChange={e => setName(e.target.value)}
                   required autoComplete="name" />
          </div>
        )}
        <div className="feld">
          <label htmlFor="bl-email">E-Mail</label>
          <input id="bl-email" type="email" value={email} onChange={e => setEmail(e.target.value)}
                 required autoComplete="email" inputMode="email" />
        </div>
        <div className="feld">
          <label htmlFor="bl-pw">Passwort</label>
          <input id="bl-pw" type="password" value={passwort} onChange={e => setPasswort(e.target.value)}
                 required minLength={6}
                 autoComplete={modus === 'anmelden' ? 'current-password' : 'new-password'} />
        </div>

        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        {meldung && <Hinweis art="gut">{meldung}</Hinweis>}

        <button className="haupt" style={{ width: '100%', marginTop: '.5rem' }} disabled={laeuft}>
          {laeuft ? 'Einen Moment …' : modus === 'anmelden' ? 'Anmelden' : 'Konto anlegen'}
        </button>
        <button type="button" style={{ width: '100%', marginTop: '.5rem', background: 'none', border: 'none' }}
                onClick={() => { setModus(modus === 'anmelden' ? 'registrieren' : 'anmelden'); setFehler(null) }}>
          {modus === 'anmelden' ? 'Neues Betriebsleiter-Konto anlegen' : 'Ich habe schon ein Konto'}
        </button>
      </form>
    </section>
  )
}
