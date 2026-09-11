# Drehbücher — die Wirklichkeit, Schritt für Schritt durchgespielt

Ein Drehbuch ist ein Tag auf dem Betrieb, aufgeschrieben wie er passiert, und
daneben, was die App dabei speichern und was sie hinterher zeigen muss. Kein
Drehbuch prüft eine Formel. Es prüft, ob die App **die Praxis abbilden kann**
— ob es für das, was der Vorarbeiter tut, einen Knopf gibt, ob das
Gespeicherte das Beobachtete ist, und ob der Betriebsleiter am Ende die Zahl
sieht, die aus diesem Tag folgt.

## Warum nicht einfach Tests

Die Tests des Projekts beweisen Zusagen: *diese* Sicht rechnet *so*. Sie
setzen voraus, dass die Daten schon in der Datenbank liegen. Wie sie
dorthin kommen — durch welche Maske, mit welchen Fragen, in welcher
Reihenfolge, mit welchen Lücken — prüft nichts. Genau dort sind aber die
Fehler, die der Betrieb meldet: *„Ich kann die Palette nicht wiegen, weil
die App das Eingangsgewicht will, und das gibt es nach dem Sortieren nicht
mehr."*

## Aufbau einer Datei

```
# NN Titel

**Wer:** Vorarbeiter Tomasz, Zähler Ildikó, Betriebsleiter
**Wann:** Tag 45 nach dem Eingang der Charge 1613
**Ausgangslage:** … (welche Daten liegen schon in der Datenbank — als SQL oder als Verweis auf die Demo)

## Szenen

### S1 Titel der Szene
**Wirklichkeit.** Ein Absatz Prosa: was in der Halle passiert.
**In der App.** Maske, Knopf, Eingabe — als nummerierte Schritte.
**Gespeichert.** Welche Zeile in welcher Tabelle mit welchen Werten (Beobachtung, nichts Abgeleitetes).
**Sichtbar.** Was der Betriebsleiter nach `auswertung_aktualisieren()` sieht — Reiter, Karte, Zahl.
**Prüfung.** SQL oder Orakel-Aufruf, der das Erwartete belegt. Rot, bevor die Reparatur da ist, wenn es eine braucht.

### S2 …
```

Jede Szene endet mit einem von drei Urteilen, das die ausführende Runde einträgt:

| Urteil | Bedeutung |
|---|---|
| **geht** | Die App kann es, das Gespeicherte ist das Beobachtete, die Zahl stimmt. |
| **geht, aber** | Es geht über einen Umweg oder mit einer Lüge (ein erfundenes Datum, ein Gewicht „0"). Das ist ein Befund. |
| **geht nicht** | Es gibt keinen Weg. Befund, und die Frage, ob die App ihn braucht oder der Ablauf sich ändern muss. |

## Der Spieler

`spieler.mjs` führt ein Drehbuch **gegen die Datenbank** aus — nicht gegen
den Browser. Er nimmt dieselben Schreibwege wie die App: `insert` in die
Tabellen, die die Masken beschreiben, und die RPC-Funktionen
(`auftrag_abbrechen`, `auswertung_aktualisieren`, …). Für die Maske selbst
(gibt es den Knopf? fragt sie das Richtige?) ist die Runde auf den
Bildschirm-Prüfstand und ihre eigenen Augen angewiesen; der Spieler prüft,
dass die Datenbank den Tag **tragen** kann.

Die Szenen stehen im Drehbuch auch als Codeblock ` ```sql szene S1 ` und
` ```sql pruefung S1 ` — der Spieler liest genau diese Blöcke, führt „szene"
aus und erwartet von „pruefung" eine Zeile `ok = true`. So bleibt das
Drehbuch **eine** Datei, lesbar für den Betriebsleiter und ausführbar für die
Maschine.

```
node gegenprobe/drehbuecher/spieler.mjs 01                # Drehbuch 01 auf einer frischen Kopie der Demo
node gegenprobe/drehbuecher/spieler.mjs 01 --db meine_db  # auf einer bestehenden Datenbank (wird verändert!)
```
