import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import { AuthProvider } from './auth/AuthProvider'
import { SprachProvider } from './sprache/SprachProvider'
// Die Schrift wird mitgebaut statt von einem CDN geladen: In der Halle ist das
// Netz wackelig, und die App muss auch dann gleich aussehen.
import '@fontsource-variable/inter'
// Erst die Zeichen (Farben, Masse), dann die Struktur, dann die Bewegung.
import './design/tokens.css'
import './index.css'
import './design/bewegung.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <SprachProvider>
        <AuthProvider>
          <App />
        </AuthProvider>
      </SprachProvider>
    </BrowserRouter>
  </React.StrictMode>,
)
