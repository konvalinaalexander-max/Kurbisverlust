import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import { Hinweis } from '../components/Bausteine'

export default function Anmelden() {
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

  return (
    <div className="huelle" style={{ maxWidth: 420, paddingTop: '3rem' }}>
      <h1>🎃 Kürbis-Verlust</h1>
      <p className="leise">Interne Erfassung — bitte mit dem eigenen Konto anmelden.</p>

      <form className="karte" onSubmit={absenden}>
        {modus === 'registrieren' && (
          <div className="feld">
            <label htmlFor="name">Name</label>
            <input id="name" value={name} onChange={e => setName(e.target.value)}
                   required autoComplete="name" />
          </div>
        )}
        <div className="feld">
          <label htmlFor="email">E-Mail</label>
          <input id="email" type="email" value={email} onChange={e => setEmail(e.target.value)}
                 required autoComplete="email" inputMode="email" />
        </div>
        <div className="feld">
          <label htmlFor="pw">Passwort</label>
          <input id="pw" type="password" value={passwort} onChange={e => setPasswort(e.target.value)}
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
          {modus === 'anmelden' ? 'Neues Konto anlegen' : 'Ich habe schon ein Konto'}
        </button>
      </form>
    </div>
  )
}
