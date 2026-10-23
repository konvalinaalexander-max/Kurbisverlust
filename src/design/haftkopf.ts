import { useEffect } from 'react'

/**
 * Spaltentitel, die je Block kleben (Runde AS).
 *
 * Der Betrieb: „wenn ich runter scrolle … die Spaltentitel verschwinden dann
 * oberhalb … schau, dass die wie kleben bleiben. Also dass immer innerhalb
 * vom Block kleben bleiben … wenn ich so weit scrolle, dass ich den ganzen
 * Block nicht mehr sehe, dann sollen die auch wieder verschwinden."
 *
 * position: sticky reicht dafür nicht: die Tabellen liegen in einem seitlich
 * rollbaren Rahmen (.rollbar), und der ist für sticky der Bezug — der Kopf
 * klebte am Rahmen, der sich nicht rollt, also nie. Darum rückt hier der Kopf
 * selbst nach: liegt der Tabellenanfang über der Unterkante der klebenden
 * Leisten (Kopfzeile, Reiter, Filter), wird der Kopf um genau so viel nach
 * unten verschoben — höchstens bis ans Ende der Tabelle, dann geht er mit
 * ihr hinaus. Eine Tabelle in einer aufgeklappten Zeile klebt unter dem Kopf
 * der äusseren. Seitlich rollt der Kopf mit seiner Tabelle, weil er in ihr
 * bleibt. In Fenstern (.dialog) rollt das Fenster, nicht die Seite — dort
 * nichts.
 *
 * 22. Oktober: Verschoben werden die Kopfzellen, nicht der thead. Der Betrieb
 * schickte ein Bild aus Safari: der klebende Kopf lag *unter* der aufgeklappten
 * Zeile, ihr Text stand mitten in den Spaltentiteln. WebKit gibt einem thead
 * keine eigene Ebene (z-index wirkt dort nicht) — die Zeilen danach malen
 * darüber. Einer Zelle mit position: relative gibt jeder Browser eine. Der
 * Versatz steht darum als --kopf-versatz am thead, und index.css schiebt jede
 * Zelle (thead.klebt th).
 */
export function useHaftendeKoepfe(an: boolean) {
  useEffect(() => {
    if (!an) return
    let raf = 0
    const rechnen = () => {
      raf = 0
      const oben = leistenUnterkante()
      const unterkante = new Map<Element, number>()
      for (const kopf of document.querySelectorAll<HTMLElement>('table > thead')) {
        const tabelle = kopf.parentElement as HTMLElement
        // Runde AT: eine Liste, die in sich selbst rollt (.innen-rollt), hält ihren Kopf mit CSS.
        // 0122: eine Tabelle mit zwei, drei Zeilen (table.ohne-haftkopf) braucht keinen klebenden Kopf.
        if (tabelle.closest('.dialog, .innen-rollt') || tabelle.classList.contains('ohne-haftkopf')) continue
        let grenze = oben
        for (let e = tabelle.parentElement; e; e = e.parentElement) {
          const u = unterkante.get(e)
          if (u != null) { grenze = Math.max(grenze, u); break }
        }
        const r = tabelle.getBoundingClientRect()
        const h = kopf.offsetHeight
        const versatz = Math.max(0, Math.min(grenze - r.top, r.height - h * 2))
        if (versatz > 0.5) {
          kopf.style.setProperty('--kopf-versatz', `${versatz}px`)
          kopf.classList.add('klebt')
          unterkante.set(tabelle, grenze + h)
        } else if (kopf.classList.contains('klebt')) {
          kopf.style.removeProperty('--kopf-versatz')
          kopf.classList.remove('klebt')
        }
      }
    }
    const planen = () => { if (!raf) raf = requestAnimationFrame(rechnen) }
    window.addEventListener('scroll', planen, { passive: true })
    window.addEventListener('resize', planen)
    // Eine Zeile geht auf, eine Tabelle lädt nach: die Lage ändert sich ohne Rollen.
    const beobachter = new MutationObserver(planen)
    beobachter.observe(document.body, { childList: true, subtree: true })
    planen()
    return () => {
      window.removeEventListener('scroll', planen)
      window.removeEventListener('resize', planen)
      beobachter.disconnect()
      if (raf) cancelAnimationFrame(raf)
      for (const kopf of document.querySelectorAll<HTMLElement>('thead.klebt')) { kopf.style.removeProperty('--kopf-versatz'); kopf.classList.remove('klebt') }
    }
  }, [an])
}

/** Unterkante der Leisten, die gerade oben kleben (Band, Kopfzeile, Reiter, Filter) — 0, wenn keine. */
function leistenUnterkante(): number {
  let unten = 0
  for (const e of document.querySelectorAll<HTMLElement>('.beispiel-band, .app > .kopf, .seitenleiste, .filterleiste.haftend')) {
    const s = getComputedStyle(e)
    if (s.position !== 'sticky' && s.position !== 'fixed') continue
    const r = e.getBoundingClientRect()
    // Die Seitenleiste am breiten Bildschirm ist so hoch wie das Fenster — sie liegt neben, nicht über der Tabelle.
    if (r.height > window.innerHeight / 2 || r.bottom <= 0) continue
    const klebOben = parseFloat(s.top) || 0
    if (r.top <= klebOben + 1) unten = Math.max(unten, r.bottom)
  }
  return unten
}
