import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import type { Profil } from '../lib/typen'

interface AuthWert {
  session: Session | null
  profil: Profil | null
  laedt: boolean
  istAdmin: boolean
  istAnonym: boolean
  neuLaden: () => Promise<void>
  abmelden: () => Promise<void>
}

const Kontext = createContext<AuthWert>({
  session: null, profil: null, laedt: true, istAdmin: false, istAnonym: false,
  neuLaden: async () => {}, abmelden: async () => {},
})

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profil, setProfil] = useState<Profil | null>(null)
  const [laedt, setLaedt] = useState(true)

  async function profilLaden(id: string) {
    const { data } = await supabase.from('profil').select('*').eq('id', id).maybeSingle()
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
    session, profil, laedt,
    istAdmin: profil?.rolle === 'admin',
    istAnonym: profil?.anonym ?? session?.user.is_anonymous ?? false,
    neuLaden: async () => { if (session) await profilLaden(session.user.id) },
    abmelden: async () => { await supabase.auth.signOut() },
  }
  return <Kontext.Provider value={wert}>{children}</Kontext.Provider>
}

export const useAuth = () => useContext(Kontext)
