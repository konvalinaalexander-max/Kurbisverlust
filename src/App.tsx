import type { ReactNode } from 'react'
import { NavLink, Navigate, Route, Routes, useParams } from 'react-router-dom'
import { ZBalken, ZListe, ZLupe, ZRegler, ZUhr } from './components/Zeichen'
import { useAuth } from './auth/AuthProvider'
import { SprachAuswahl, useSprache } from './sprache/SprachProvider'
import { istKonfiguriert, konfigurationsProblem } from './lib/supabase'
import { SPRACHEN } from './lib/i18n'
import { Hinweis, Lade } from './components/Bausteine'
import Anmelden from './pages/Anmelden'
import Start from './pages/Start'
import NeueArbeit from './pages/NeueArbeit'
import Arbeit from './pages/Arbeit'
import Kontrolle from './pages/Kontrolle'
import Ueberblick from './pages/Ueberblick'
import Ursachen from './pages/Ursachen'
import Chargen from './pages/Chargen'
import Messungen from './pages/Messungen'
import Betrieb from './pages/Betrieb'

export default function App() {
  const { session, profil, laedt, istAdmin, abmelden } = useAuth()
  const { t, sprache, abfrageOffen, abfrageOeffnen } = useSprache()

  if (konfigurationsProblem) {
    return (
      <div className="huelle" style={{ paddingTop: '2rem' }}>
        <h1>Kürbis-Verlust</h1>
        <Hinweis art="warnung">
          <p><strong>Die Zugangsdaten stimmen nicht.</strong></p>
          <p style={{ marginBottom: 0 }}>{konfigurationsProblem}</p>
        </Hinweis>
        <p className="leise">
          Zu ändern bei Cloudflare unter Settings → Environment variables.
          Danach unter Deployments beim obersten Eintrag über das Menü ⋯ auf
          „Retry deployment" — ohne neuen Build ändert sich nichts.
        </p>
      </div>
    )
  }

  if (!istKonfiguriert) {
    return (
      <div className="huelle" style={{ paddingTop: '2rem' }}>
        <h1>Kürbis-Verlust</h1>
        <Hinweis art="warnung">
          <p><strong>Noch nicht mit Supabase verbunden.</strong></p>
          <p style={{ marginBottom: 0 }}>
            <code>VITE_SUPABASE_URL</code> und <code>VITE_SUPABASE_ANON_KEY</code> fehlen —
            lokal in <code>.env.local</code>, bei Cloudflare unter Environment variables.
          </p>
        </Hinweis>
      </div>
    )
  }

  // Die Sprachfrage steht vor allem anderen: Wer die App nicht lesen kann,
  // kommt auch am Anmeldebildschirm nicht weiter.
  if (abfrageOffen) return <SprachAuswahl />

  if (laedt) return <Lade />
  if (!session) return <Anmelden />

  const aktuelleFlagge = SPRACHEN.find(s => s.code === sprache)?.flagge ?? '🌐'

  // Fünf Reiter, je mit einem Satz, was er beantwortet (docs/UI-KONZEPT.md).
  const reiter: [string, string, () => ReactNode][] = [
    ['/dashboard', 'Überblick', ZBalken],
    ['/ursachen', 'Ursachen', ZLupe],
    ['/chargen', 'Chargen', ZListe],
    ['/messungen', 'Messungen', ZRegler],
    ['/betrieb', 'Betrieb', ZUhr],
  ]

  return (
    <>
      <header className="kopf kein-druck">
        <NavLink to="/" className="marke" style={{ textDecoration: 'none', color: 'inherit' }}>
          <span className="zeichen" aria-hidden="true">🎃</span>
          <span className="name">{t('appName')}</span>
        </NavLink>
        <span className="wer">{profil?.name ?? ''}</span>
        <button onClick={abfrageOeffnen} aria-label="Sprache">{aktuelleFlagge}</button>
        <button onClick={abmelden}>{t('abmelden')}</button>
      </header>

      {istAdmin && (
        <nav className="navleiste kein-druck">
          {reiter.map(([pfad, name, Zeichen]) => (
            <NavLink key={pfad} to={pfad}
                     className={({ isActive }) => (isActive ? 'aktiv' : '')}>
              <Zeichen />{name}
            </NavLink>
          ))}
        </nav>
      )}

      <main className={istAdmin ? 'huelle' : 'huelle eng'}>
        <Routes>
          <Route path="/" element={<Start />} />
          <Route path="/start" element={<Start />} />
          <Route path="/neu" element={<NeueArbeit />} />
          <Route path="/arbeit/:id" element={<Arbeit />} />
          {/* Alte Adressen (QR-Codes, Lesezeichen) laufen weiter */}
          <Route path="/auftraege" element={<Navigate to="/" replace />} />
          <Route path="/auftraege/:id" element={<AlteArbeit />} />
          <Route path="/kontrolle" element={<Kontrolle />} />
          <Route path="/dashboard" element={istAdmin ? <Ueberblick /> : <NurAdmin />} />
          <Route path="/ursachen" element={istAdmin ? <Ursachen /> : <NurAdmin />} />
          <Route path="/chargen" element={istAdmin ? <Chargen /> : <NurAdmin />} />
          <Route path="/messungen" element={istAdmin ? <Messungen /> : <NurAdmin />} />
          <Route path="/betrieb/:teil?" element={istAdmin ? <Betrieb /> : <NurAdmin />} />
          {/* Alte Adressen laufen weiter */}
          <Route path="/csv" element={<Navigate to="/betrieb/csv" replace />} />
          <Route path="/warteschlange" element={<Navigate to="/betrieb/warteschlange" replace />} />
          <Route path="/lieferungen" element={<Navigate to="/betrieb/lieferungen" replace />} />
          <Route path="/stammdaten" element={<Navigate to="/betrieb/stammdaten" replace />} />
          <Route path="/zugang" element={<Navigate to="/betrieb/zugang" replace />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </>
  )
}

function AlteArbeit() {
  const { id } = useParams()
  return <Navigate to={`/arbeit/${id}`} replace />
}

function NurAdmin() {
  const { t } = useSprache()
  return <Hinweis art="warnung">{t('keineBerechtigung')}</Hinweis>
}
