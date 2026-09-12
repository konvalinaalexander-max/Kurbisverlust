/**
 * Die Strichzeichen der App — von Hand als einfache Geometrie, statt eine
 * Icon-Bibliothek mitzuschleppen. Alle einfarbig in Textfarbe, 24er-Raster,
 * runde Enden. Kein Zeichen ohne Text daneben — ausser in einer Leiste, wo
 * der Text als aria-label steht.
 */
import type { ReactNode } from 'react'

function Z({ children, size = 18, strich = 1.75 }: { children: ReactNode; size?: number; strich?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden="true"
         stroke="currentColor" strokeWidth={strich} strokeLinecap="round" strokeLinejoin="round">
      {children}
    </svg>
  )
}
type P = { size?: number }

/* ---------- Navigation ------------------------------------------------------ */
/** Überblick: drei Balken. */
export const ZBalken = ({ size }: P) => <Z size={size}><path d="M5 20V12M12 20V5M19 20V9" /><path d="M3 21h18" /></Z>
/** Ursachen: Lupe. */
export const ZLupe = ({ size }: P) => <Z size={size}><circle cx="10.5" cy="10.5" r="6.5" /><path d="m15.5 15.5 5 5" /></Z>
/** Chargen: Liste. */
export const ZListe = ({ size }: P) => <Z size={size}><path d="M4 7h1.5M9 7h11M4 12h1.5M9 12h11M4 17h1.5M9 17h11" /></Z>
/** Messungen: Regler. */
export const ZRegler = ({ size }: P) => <Z size={size}><path d="M4 8h7M15 8h5M4 16h3M11 16h9" /><circle cx="13" cy="8" r="2.2" /><circle cx="9" cy="16" r="2.2" /></Z>
/** Betrieb: Uhr. */
export const ZUhr = ({ size }: P) => <Z size={size}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></Z>

/* ---------- Marke ------------------------------------------------------------ */
/** Der Kürbis — die Marke. Drei Rippen und ein Stiel. */
export const ZKuerbis = ({ size = 20 }: P) => (
  <Z size={size} strich={1.7}>
    <path d="M12 6.2c-.7-1.2-.4-2.5.6-3.2" />
    <path d="M12 6.4c-2.6 0-4.4 2.1-4.4 5.1S9.2 20 12 20s4.4-2.5 4.4-5.5S14.6 6.4 12 6.4Z" />
    <path d="M12 6.6v13.2" />
    <path d="M9.2 7.4c-1 1.2-1.4 2.9-1.4 4.4 0 1.8.4 3.8 1.4 5.2" />
    <path d="M14.8 7.4c1 1.2 1.4 2.9 1.4 4.4 0 1.8-.4 3.8-1.4 5.2" />
  </Z>
)

/* ---------- Zustände ---------------------------------------------------------- */
export const ZHaken = ({ size }: P) => <Z size={size} strich={2.2}><path d="m5 12.5 4.5 4.5L19 7.5" /></Z>
export const ZKreuz = ({ size }: P) => <Z size={size} strich={2}><path d="M6 6l12 12M18 6 6 18" /></Z>
export const ZWarnung = ({ size }: P) => <Z size={size}><path d="M12 3.5 2.5 20h19L12 3.5Z" /><path d="M12 9.5v5M12 17.2v.3" /></Z>
export const ZInfo = ({ size }: P) => <Z size={size}><circle cx="12" cy="12" r="8.5" /><path d="M12 11v5M12 8v.3" /></Z>
export const ZPunkt = ({ size }: P) => <Z size={size} strich={3}><path d="M12 12v.01" /></Z>

/* ---------- Richtung, Bedienung ---------------------------------------------- */
export const ZPfeilRechts = ({ size }: P) => <Z size={size}><path d="M5 12h14M13 6l6 6-6 6" /></Z>
export const ZChevron = ({ size }: P) => <Z size={size} strich={2}><path d="m9 6 6 6-6 6" /></Z>
export const ZZurueck = ({ size }: P) => <Z size={size} strich={2}><path d="m15 6-6 6 6 6" /></Z>
export const ZPlus = ({ size }: P) => <Z size={size} strich={2.2}><path d="M12 5v14M5 12h14" /></Z>
export const ZMinus = ({ size }: P) => <Z size={size} strich={2.2}><path d="M5 12h14" /></Z>
export const ZRueckgaengig = ({ size }: P) => <Z size={size}><path d="M9 14 4 9l5-5" /><path d="M4 9h9.5a6.5 6.5 0 0 1 0 13H8" /></Z>
export const ZNeu = ({ size }: P) => <Z size={size}><path d="M12 5v14M5 12h14" /><circle cx="12" cy="12" r="9.5" /></Z>
export const ZFilter = ({ size }: P) => <Z size={size}><path d="M4 6h16l-6 7v5l-4 2v-7L4 6Z" /></Z>
export const ZKalender = ({ size }: P) => <Z size={size}><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4" /></Z>
export const ZTabelle = ({ size }: P) => <Z size={size}><rect x="3.5" y="5" width="17" height="14" rx="2" /><path d="M3.5 10h17M3.5 14.5h17M10 10v9" /></Z>
export const ZZoomAus = ({ size }: P) => <Z size={size}><circle cx="10.5" cy="10.5" r="6.5" /><path d="m15.5 15.5 5 5M7.5 10.5h6" /></Z>
export const ZAktualisieren = ({ size }: P) => <Z size={size}><path d="M20 12a8 8 0 1 1-2.4-5.7" /><path d="M20 4v5h-5" /></Z>
export const ZSprache = ({ size }: P) => <Z size={size}><circle cx="12" cy="12" r="8.5" /><path d="M3.5 12h17M12 3.5c2.6 2.5 3.8 5.4 3.8 8.5s-1.2 6-3.8 8.5c-2.6-2.5-3.8-5.4-3.8-8.5s1.2-6 3.8-8.5Z" /></Z>
export const ZAbmelden = ({ size }: P) => <Z size={size}><path d="M10 4H6.5A2.5 2.5 0 0 0 4 6.5v11A2.5 2.5 0 0 0 6.5 20H10" /><path d="M14 8l4 4-4 4M9 12h9" /></Z>
export const ZDrucken = ({ size }: P) => <Z size={size}><path d="M7 9V4h10v5M7 17H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2" /><rect x="7" y="14" width="10" height="6" rx="1" /></Z>
export const ZKopieren = ({ size }: P) => <Z size={size}><rect x="8" y="8" width="12" height="12" rx="2" /><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" /></Z>
export const ZHerunterladen = ({ size }: P) => <Z size={size}><path d="M12 4v11M7 10l5 5 5-5M4 19h16" /></Z>
export const ZStift = ({ size }: P) => <Z size={size}><path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17v3Z" /><path d="m13.5 8.5 3 3" /></Z>

/* ---------- Die Halle ----------------------------------------------------------- */
export const ZWaage = ({ size }: P) => <Z size={size}><path d="M12 4v3M5 7h14l-2 12H7L5 7Z" /><path d="M9 13a3 3 0 0 0 6 0" /></Z>
export const ZPalette = ({ size }: P) => <Z size={size}><rect x="4" y="5" width="16" height="9" rx="1.5" /><path d="M3 18h18M7 14v4M17 14v4M12 14v4" /></Z>
export const ZKiste = ({ size }: P) => <Z size={size}><path d="M4 9.5 12 5l8 4.5v7L12 21l-8-4.5v-7Z" /><path d="M4 9.5 12 14l8-4.5M12 14v7" /></Z>
export const ZPersonen = ({ size }: P) => <Z size={size}><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20a6.5 6.5 0 0 1 13 0" /><path d="M16 5a3.5 3.5 0 0 1 0 7M21.5 20a6.5 6.5 0 0 0-4.5-6.2" /></Z>

/* ---------- Tätigkeiten ---------------------------------------------------------- */
/** Sortieren: Zahnrad (die Maschine). */
const ZZahnrad = ({ size }: P) => (
  <Z size={size}><circle cx="12" cy="12" r="3" />
    <path d="M12 3.5v2.5M12 18v2.5M3.5 12H6M18 12h2.5M6 6l1.8 1.8M16.2 16.2 18 18M18 6l-1.8 1.8M7.8 16.2 6 18" /></Z>
)
/** Waschen: Tropfen. */
const ZWasser = ({ size }: P) => <Z size={size}><path d="M12 3.5s5.5 6 5.5 10a5.5 5.5 0 0 1-11 0c0-4 5.5-10 5.5-10Z" /></Z>
/** Waschen + Sortieren von Hand: Korb. */
const ZKorb = ({ size }: P) => (
  <Z size={size}><path d="M3.5 9h17l-1.5 9.5a1.2 1.2 0 0 1-1.2 1H6.2a1.2 1.2 0 0 1-1.2-1L3.5 9Z" />
    <path d="M8 9 10.5 4.5M16 9l-2.5-4.5M8.5 12.5v3.5M12 12.5v3.5M15.5 12.5v3.5" /></Z>
)
/** Fax (Abpacken, Etikettieren): Etikett. */
const ZEtikett = ({ size }: P) => <Z size={size}><path d="M3.5 4.5h9.5l7.5 7.5-8.5 8.5-8.5-8.5v-7.5Z" /><circle cx="8" cy="9" r="1.4" /></Z>

const TAET_ZEICHEN: Record<string, (p: P) => ReactNode> = {
  sortieren: ZZahnrad, waschen: ZWasser, waschen_sortieren: ZKorb, fax: ZEtikett,
}

/** Das Zeichen einer Tätigkeit — inline in Textfarbe. */
export function TaetZeichen({ id, className, size = 18 }: { id?: string | null; className?: string; size?: number }) {
  const T = id ? TAET_ZEICHEN[id] : undefined
  if (!T) return null
  return <span className={`zeichen-inline${className ? ` ${className}` : ''}`}>{T({ size })}</span>
}

/** Die Kachel einer Tätigkeit — ein Quadrat mit Fläche, für Karten und Wahl. */
export function TaetKachel({ id, size = 40 }: { id?: string | null; size?: number }) {
  const T = id ? TAET_ZEICHEN[id] : undefined
  return (
    <span className="kachel" aria-hidden="true" style={{ width: size, height: size }}>
      {T ? T({ size: Math.round(size * .55) }) : <ZKuerbis size={Math.round(size * .55)} />}
    </span>
  )
}
