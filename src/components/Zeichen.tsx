/**
 * Eine Handvoll Strichzeichen für die Navigation — bewusst von Hand als
 * einfache Geometrie, statt eine Icon-Bibliothek mitzuschleppen. Emojis in
 * der Navigation sehen nach Bastelei aus; kleine einfarbige Zeichen, die die
 * Textfarbe erben, nach Werkzeug.
 */
import type { ReactNode } from 'react'

function Z({ children }: { children: ReactNode }) {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" fill="none" aria-hidden="true"
         stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      {children}
    </svg>
  )
}

/** Arbeiten: eine Liste mit Haken. */
export const ZListe = () => (
  <Z>{<>
    <path d="M3 4.5h1M6.5 4.5H13" />
    <path d="M3 8h1M6.5 8H13" />
    <path d="M3 11.5h1M6.5 11.5H13" />
  </>}</Z>
)

/** Auswertung: drei Balken. */
export const ZBalken = () => (
  <Z>{<>
    <path d="M3.5 13V9" />
    <path d="M8 13V4" />
    <path d="M12.5 13V6.5" />
    <path d="M2 13.5h12" />
  </>}</Z>
)


/** Warteschlange: Uhr. */
export const ZUhr = () => (
  <Z>{<>
    <circle cx="8" cy="8" r="5.5" />
    <path d="M8 5.2V8l2 1.4" />
  </>}</Z>
)


/** Stammdaten: Schieberegler. */
export const ZRegler = () => (
  <Z>{<>
    <path d="M2.5 4.8h5M10.5 4.8h3" /><circle cx="9" cy="4.8" r="1.5" />
    <path d="M2.5 11.2h2M8.5 11.2h5" /><circle cx="7" cy="11.2" r="1.5" />
  </>}</Z>
)


/** Lagerkontrolle: Lupe. */
export const ZLupe = () => (
  <Z>{<>
    <circle cx="7" cy="7" r="4.5" />
    <path d="m10.5 10.5 3 3" />
  </>}</Z>
)



/* ---------- Runde N: Zeichen statt Emoji ------------------------------------ */

/** Ein grösseres Zeichen für Kacheln (Tätigkeiten, Marke) — 24er-Raster. */
function ZG({ children, size = 26 }: { children: ReactNode; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden="true"
         stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      {children}
    </svg>
  )
}

/** Der Kürbis — die Marke im Kopf, statt 🎃. Drei Rippen und ein Stiel. */
export const ZKuerbis = ({ size = 20 }: { size?: number }) => (
  <ZG size={size}>{<>
    <path d="M12 6.2c-.7-1.2-.4-2.5.6-3.2" />
    <path d="M12 6.4c-2.6 0-4.4 2.1-4.4 5.1S9.2 20 12 20s4.4-2.5 4.4-5.5S14.6 6.4 12 6.4Z" />
    <path d="M12 6.6v13.2" />
    <path d="M9.2 7.4c-1 1.2-1.4 2.9-1.4 4.4 0 1.8.4 3.8 1.4 5.2" />
    <path d="M14.8 7.4c1 1.2 1.4 2.9 1.4 4.4 0 1.8-.4 3.8-1.4 5.2" />
  </>}</ZG>
)

/** Sortieren: Zahnrad (die Maschine). */
const ZZahnrad = () => (
  <ZG>{<>
    <circle cx="12" cy="12" r="3" />
    <path d="M12 4v2M12 18v2M4 12h2M18 12h2M6.3 6.3l1.4 1.4M16.3 16.3l1.4 1.4M17.7 6.3l-1.4 1.4M7.7 16.3l-1.4 1.4" />
  </>}</ZG>
)
/** Waschen: Tropfen. */
const ZWasser = () => (
  <ZG>{<path d="M12 4s5 5.6 5 9.2A5 5 0 0 1 7 13.2C7 9.6 12 4 12 4Z" />}</ZG>
)
/** Waschen + Sortieren von Hand: Korb. */
const ZKorb = () => (
  <ZG>{<>
    <path d="M4 9h16l-1.4 9.2a1 1 0 0 1-1 .8H6.4a1 1 0 0 1-1-.8L4 9Z" />
    <path d="M8 9 10 5M16 9 14 5M8.5 12.5v3M12 12.5v3M15.5 12.5v3" />
  </>}</ZG>
)
/** Fax (Abpacken/Etikettieren): Etikett. */
const ZEtikett = () => (
  <ZG>{<>
    <path d="M4 5h9l7 7-8 8-8-8V5Z" />
    <circle cx="8" cy="9" r="1.3" />
  </>}</ZG>
)

const TAET_ZEICHEN: Record<string, () => ReactNode> = {
  sortieren: ZZahnrad, waschen: ZWasser, waschen_sortieren: ZKorb, fax: ZEtikett,
}

/** Das Zeichen einer Tätigkeit — inline in Textfarbe, statt eines Emoji. */
export function TaetZeichen({ id, className }: { id?: string | null; className?: string }) {
  const Z = id ? TAET_ZEICHEN[id] : undefined
  if (!Z) return null
  return <span className={className} style={{ display: 'inline-flex', verticalAlign: '-.18em' }}>{Z()}</span>
}
