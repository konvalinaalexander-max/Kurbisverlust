import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import { AuthProvider } from './auth/AuthProvider'
import { SprachProvider } from './sprache/SprachProvider'
// Die Schrift wird mitgebaut statt von einem CDN geladen: In der Halle ist das
// Netz wackelig, und die App muss auch dann gleich aussehen.
import '@fontsource-variable/inter'
import './index.css'

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
