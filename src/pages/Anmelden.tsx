import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import { useSprache } from '../sprache/SprachProvider'
import { Hinweis } from '../components/Bausteine'

const NAME_SCHLUESSEL = 'arbeiter_name'

/**
 * Startseite. Für den Arbeiter genau ein Feld und ein Knopf — mehr nicht.
 * Der Betriebsleiter-Login liegt klein darunter.
 */
export default function Anmelden() {
  const { t } = useSprache()
  return (
    <div className="huelle" style={{ maxWidth: 460, paddingTop: '2.5rem' }}>
      <h1 style={{ fontSize: '1.7rem', textAlign: 'center' }}>🎃 {t('appName')}</h1>
      <ArbeiterStart />
      <BetriebsleiterLogin />
    </div>
  )
}

function ArbeiterStart() {
  const { t } = useSprache()
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
      setFehler(/anonymous|disabled|not enabled/i.test(error.message)
        ? t('zugangGesperrt') : error.message)
    }
  }

  return (
    <section className="karte" style={{ padding: '1.5rem' }}>
      <form onSubmit={los}>
        <div className="feld">
          <label htmlFor="name">{t('deinName')}</label>
          <input id="name" value={name} onChange={e => setName(e.target.value)}
                 autoComplete="off" autoFocus placeholder={t('namePlatzhalter')}
                 style={{ fontSize: '1.2rem' }} />
        </div>
        {fehler && <Hinweis art="warnung">{fehler}</Hinweis>}
        <button className="haupt gross" style={{ width: '100%' }}
                disabled={laeuft || !name.trim()}>
          {laeuft ? t('moment') : t('losGehts')}
        </button>
      </form>
    </section>
  )
}

function BetriebsleiterLogin() {
  const { t } = useSprache()
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
    } finally { setLaeuft(false) }
  }

  if (!offen) {
    return (
      <p style={{ textAlign: 'center', marginTop: '1.5rem' }}>
        <button style={{ background: 'none', border: 'none', color: 'var(--text-leise)',
                         fontWeight: 400, fontSize: '.9rem' }}
                onClick={() => setOffen(true)}>
          {t('leiterLogin')}
        </button>
      </p>
    )
  }

  return (
    <section className="karte">
      <h2 style={{ marginTop: 0 }}>{t('leiterLogin')}</h2>
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
          {laeuft ? '…' : modus === 'anmelden' ? 'Anmelden' : 'Konto anlegen'}
        </button>
        <button type="button" style={{ width: '100%', marginTop: '.5rem', background: 'none', border: 'none' }}
                onClick={() => { setModus(modus === 'anmelden' ? 'registrieren' : 'anmelden'); setFehler(null) }}>
          {modus === 'anmelden' ? 'Neues Betriebsleiter-Konto anlegen' : 'Ich habe schon ein Konto'}
        </button>
      </form>
    </section>
  )
}
