import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { Profil } from '../lib/typen'
import { fehlerText } from '../lib/db'

interface AuthWert {
  session: Session | null
  profil: Profil | null
  laedt: boolean
  istAdmin: boolean
  istAnonym: boolean
  /** Runde AG: Das Profil liess sich nicht laden (Datenbank antwortet nicht) — der Text dazu, statt eines Skeletts. */
  verbindung: string | null
  neuLaden: () => Promise<void>
  abmelden: () => Promise<void>
}

const Kontext = createContext<AuthWert>({
  session: null, profil: null, laedt: true, istAdmin: false, istAnonym: false, verbindung: null,
  neuLaden: async () => {}, abmelden: async () => {},
})

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profil, setProfil] = useState<Profil | null>(null)
  const [laedt, setLaedt] = useState(true)
  const [verbindung, setVerbindung] = useState<string | null>(null)

  async function profilLaden(id: string) {
    setVerbindung(null)
    const { data, error } = await supabase.from('profil').select('*').eq('id', id).maybeSingle()
    if (error) setVerbindung(fehlerText(error))
    setProfil(data as Profil | null)
  }

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      if (!data.session) setLaedt(false)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      setSession(s)
      if (!s) { setProfil(null); setLaedt(false) }
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) return
    let abgebrochen = false
    profilLaden(session.user.id).finally(() => { if (!abgebrochen) setLaedt(false) })
    return () => { abgebrochen = true }
  }, [session])

  const wert: AuthWert = {
    session, profil, laedt, verbindung,
    istAdmin: profil?.rolle === 'admin',
    istAnonym: profil?.anonym ?? session?.user.is_anonymous ?? false,
    neuLaden: async () => { if (session) await profilLaden(session.user.id) },
    abmelden: async () => { await supabase.auth.signOut() },
  }
  return <Kontext.Provider value={wert}>{children}</Kontext.Provider>
}

export const useAuth = () => useContext(Kontext)
