import { useEffect, useRef } from 'react'

/**
 * Eine Liste frisch halten, ohne dass jemand sie anfassen muss (Q22).
 *
 * In der Halle liegt das Handy zwischen zwei Griffen auf der Palette. Die
 * Startseite lud ihre Liste genau einmal — beim Öffnen. Wer um vier Uhr die
 * Schicht übernahm, sah dann den Stand von halb zwei: Arbeiten, die längst
 * abgeschlossen sind, stehen noch als „läuft" da, und die Arbeit, die der
 * Kollege vor zehn Minuten eröffnet hat, fehlt. Beides ist beim
 * Schichtwechsel genau das, was man braucht.
 *
 * Also: neu laden, wenn der Bildschirm wieder da ist (`visibilitychange`),
 * wenn das Fenster den Fokus bekommt — und solange man hinschaut, alle paar
 * Sekunden. Ist der Bildschirm aus, läuft nichts; das schont den Akku und
 * die Datenbank.
 *
 * Bewusst kein Echtzeitkanal: dafür bräuchte es eine offene Verbindung durch
 * das Hallen-WLAN, und die Startseite ist keine Messung, sondern eine Liste.
 */
export function useFrischhalten(laden: () => void | Promise<void>, sekunden = 20) {
  const merker = useRef(laden)
  merker.current = laden
  useEffect(() => {
    const sichtbar = () => typeof document === 'undefined' || document.visibilityState === 'visible'
    const jetzt = () => { if (sichtbar()) void merker.current() }
    const uhr = window.setInterval(jetzt, sekunden * 1000)
    document.addEventListener('visibilitychange', jetzt)
    window.addEventListener('focus', jetzt)
    return () => {
      window.clearInterval(uhr)
      document.removeEventListener('visibilitychange', jetzt)
      window.removeEventListener('focus', jetzt)
    }
  }, [sekunden])
}
