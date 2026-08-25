import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { Profil } from '../lib/typen'

interface AuthWert {
  session: Session | null
  profil: Profil | null
  laedt: boolean
  istAdmin: boolean
  abmelden: () => Promise<void>
}

const Kontext = createContext<AuthWert>({
  session: null, profil: null, laedt: true, istAdmin: false,
  abmelden: async () => {},
})

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profil, setProfil] = useState<Profil | null>(null)
  const [laedt, setLaedt] = useState(true)

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
    supabase.from('profil').select('*').eq('id', session.user.id).maybeSingle()
      .then(({ data }) => {
        if (abgebrochen) return
        setProfil(data as Profil | null)
        setLaedt(false)
      })
    return () => { abgebrochen = true }
  }, [session])

  const wert: AuthWert = {
    session, profil, laedt,
    istAdmin: profil?.rolle === 'admin',
    abmelden: async () => { await supabase.auth.signOut() },
  }
  return <Kontext.Provider value={wert}>{children}</Kontext.Provider>
}

export const useAuth = () => useContext(Kontext)
