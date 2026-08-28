import { NavLink, Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './auth/AuthProvider'
import { SprachAuswahl, useSprache } from './sprache/SprachProvider'
import { istKonfiguriert, konfigurationsProblem } from './lib/supabase'
import { SPRACHEN } from './lib/i18n'
import { Hinweis, Lade } from './components/Bausteine'
import Anmelden from './pages/Anmelden'
import Auftraege from './pages/Auftraege'
import AuftragDetail from './pages/AuftragDetail'
import CsvUpload from './pages/CsvUpload'
import Warteschlange from './pages/Warteschlange'
import Dashboard from './pages/Dashboard'
import Kontrolle from './pages/Kontrolle'
import Lieferungen from './pages/Lieferungen'
import Stammdaten from './pages/Stammdaten'
import Zugang from './pages/Zugang'

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

  return (
    <>
      <header className="kopf kein-druck">
        <span className="marke">🎃 {t('appName')}</span>
        <span className="wer">{profil?.name ?? ''}</span>
        <button className="flagge-knopf" onClick={abfrageOeffnen} aria-label="Sprache">
          {aktuelleFlagge}
        </button>
        <button onClick={abmelden} style={{ minHeight: 34, padding: '.3rem .7rem' }}>
          {t('abmelden')}
        </button>
      </header>

      {istAdmin && (
        <nav className="navleiste kein-druck">
          <NavLink to="/auftraege" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Arbeiten</NavLink>
          <NavLink to="/dashboard" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Auswertung</NavLink>
          <NavLink to="/csv" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Sortier-CSV</NavLink>
          <NavLink to="/warteschlange" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Warteschlange</NavLink>
          <NavLink to="/lieferungen" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Warenausgang</NavLink>
          <NavLink to="/stammdaten" className={({ isActive }) => (isActive ? 'aktiv' : '')}>Stammdaten</NavLink>
          <NavLink to="/zugang" className={({ isActive }) => (isActive ? 'aktiv' : '')}>QR-Zugang</NavLink>
        </nav>
      )}

      <main className="huelle">
        <Routes>
          <Route path="/" element={<Navigate to="/auftraege" replace />} />
          <Route path="/auftraege" element={<Auftraege />} />
          <Route path="/auftraege/:id" element={<AuftragDetail />} />
          <Route path="/kontrolle" element={<Kontrolle />} />
          <Route path="/dashboard" element={istAdmin ? <Dashboard /> : <NurAdmin />} />
          <Route path="/csv" element={istAdmin ? <CsvUpload /> : <NurAdmin />} />
          <Route path="/warteschlange" element={istAdmin ? <Warteschlange /> : <NurAdmin />} />
          <Route path="/lieferungen" element={istAdmin ? <Lieferungen /> : <NurAdmin />} />
          <Route path="/stammdaten" element={istAdmin ? <Stammdaten /> : <NurAdmin />} />
          <Route path="/zugang" element={istAdmin ? <Zugang /> : <NurAdmin />} />
          <Route path="*" element={<Navigate to="/auftraege" replace />} />
        </Routes>
      </main>
    </>
  )
}

function NurAdmin() {
  const { t } = useSprache()
  return <Hinweis art="warnung">{t('keineBerechtigung')}</Hinweis>
}
