# Kürbis-Verlust-Tracking — Projekt-Spezifikation (Seed)

> Diese Datei ist die vollständige Übergabe an ein **neues Projekt / eine neue Claude-Cowork-Session**.
> Sie beschreibt Zweck, Fachlogik, Daten, Reinigungsregeln, Statistik-Ansatz, App-Aufbau und Technik.
> Sie ist bewusst selbstständig lesbar — mit allen Stammdaten eingebettet.
> Stand: 2026-08. Alles hier ist ein durchdachter Entwurf und darf angepasst werden.

## 0. Kontext & Beziehung zur bestehenden App

Es existiert bereits eine **Wareneingang-App** („Kürbis-Erntejournal", Next.js + Google Sheets),
die beim Wareneingang **pro Palette** Datum, Person, Schlag, Sorte, Bruttogewicht, Kistenzahl,
Gebindeart erfasst und in ein Google Sheet schreibt. Dieses neue Projekt ist **eigenständig**
(eigenes Repo, eigene Datenbank) und hängt mit der Journal-App **nur über die Chargennummer**
zusammen. Der einzige Eingriff in die bestehende App: die **Chargennummer** wird pro Palette
ergänzt (Spalte im Sheet), damit die Eingangsdaten hier importierbar sind.

**Ziel des Projekts:** Herausfinden, **wo** im Lager/der Verarbeitung Kürbis-Masse verloren geht
und **welche Ursache dominiert** — aus bewusst **lückenhaften, punktuellen** Messungen ein
**Gesamtbild** hochrechnen. Es geht ums **Rangieren der Ursachen**, nicht um kg-genaue Bilanz.
Größenordnung: hunderte Tonnen Kürbis pro Saison. **Internes Werkzeug für einen einzelnen
landwirtschaftlichen Betrieb** (nur interne Nutzer) — professionell & korrekt, aber **kostenbewusst**:
wo möglich Gratis-Stufen nutzen, keine unnötigen Hosting-Kosten.

## 1. Fachbegriffe

- **Schlag** = die benannte Herkunft, meist Ort und Bewirtschafter („Illnau Bruno“,
  „Slowgrow Uster“). **Nicht** einfach „Feld“ — vom Betrieb ausdrücklich richtiggestellt.
- **Sorte** = Kürbissorte (z. B. Kaori Kuri, Tiana).
- **Charge** = Kombination **Schlag × Sorte**, eindeutig identifiziert durch eine **Chargennummer**.
  Eine Charge wird **gestaffelt** über Tage/Wochen geerntet und eingelagert.
- **Palette** = Erfassungseinheit beim Wareneingang; **eine Palette = genau eine Charge**;
  jede Palette hat ihr **eigenes Eingangsdatum** und ihren Zettel (Charge, Datum, Bruttogewicht, Kistenzahl).
- **Auftrag** = ein Verarbeitungslauf einer Charge an einer Station (mit Server-Zeitstempel).
- **Lager** = eine einzige große Halle, gleiche Bedingungen für alle Paletten.

## 2. Die fünf Ströme (drei Verluste, zwei keine)

| Strom | Art | Bedeutung |
|---|---|---|
| **Verdunstung** | Verlust (Masse) | Kürbis verliert Wasser über Zeit; Ware bleibt verkäuflich, nur leichter |
| **Schimmel/Fäulnis** | Verlust (total) | Ganze Kürbisse verderben |
| **Ausschuss zu klein** | Verlust (total) | Unter Sorten-Grenze → weggeworfen |
| **Zu gross (Nebenkanal)** | **kein Verlust** | Über oberer Grenze → anderer Verkaufskanal; separat ausweisen |
| **Überfüllung** | **kein Verlust, Marge** | 8-kg-Kisten real 8.1–8.5 kg → verschenkte Ware |

**Zwei getrennte Bücher führen:** (A) **physischer Verlust** = Verdunstung + Schimmel + Ausschuss-klein
+ Restware am Saisonende; (B) **verschenkte Marge** = Nebenkanal-Überschuss (Weg 1) + Überfüllung (Weg 2).
Niemals vermischen.

## 3. Die zwei Verarbeitungswege

**Weg 1 — Maschinen-Weg:** Lager → **Sortieren** → Lager → **Waschen** → Warenausgang.
- Preis: **pro Stück innerhalb eines Kalibers** (Gewicht egal). Optimierung: engeres Band liefern.
- Sortiermaschine wiegt **jeden Kürbis einzeln** → **CSV** (siehe §5). Fäulnis wird vor dem Band aussortiert
  (CSV enthält nur gesunde Kürbisse). Zu klein/gross kommen in eigene Kisten.
- Kürbisse landen danach in **Kaliber-Kisten** (Original-Palette löst sich auf). Charge bleibt bekannt,
  **Gewicht ab hier aus der CSV** (nicht mehr vom Zettel). Aus der CSV lässt sich **kein Palettengewicht** ableiten.
- Beim späteren Waschen (Wochen/Monate später) nochmals Fäulnis aussortiert → **Schimmel #2, zeitaufgelöst**.

**Weg 2 — Hand-Weg:** Lager → **Waschen + Sortieren** in einem → Warenausgang.
- Preis: **Fixpreis pro Kiste ≥ 8 kg** (real 8.1–8.5). Optimierung: Überfüllung messen.
- **Bester Verdunstungs-Messpunkt:** beim Herausholen aus dem Lager (vor dem Wasserbecken) Palette wiegen —
  große Vielfalt an Lagerdauern. Gross/klein nach Auge (locker), Fäulnis aussortiert.

Beide Wege können **gleichzeitig** laufen; die Waschstation ist zwischen Weg-1-Waschen und Weg-2 geteilt.
Eine Charge kann teils Weg 1, teils Weg 2 gehen.

## 4. Reinigungsregeln für die Sortier-CSV (MÜSSEN in der App laufen)

Die CSV = **eine Zahl (Gewicht in Gramm) pro Zeile**, keine Kopfzeile, keine Charge/Datum im Inhalt.
Alle Werte **gerade** (2-g-Auflösung). **Rohdatei immer unverändert speichern**; Reinigung ist eine
eigene, umstellbare, **transparent angezeigte** Schicht:

1. **Overflow ≥ 60000** → 16-Bit-Unterlauf; als negativ interpretieren (−2…−130 g) = Leerband-Rauschen → **verwerfen**.
2. **< 100 g** → kein Kürbis (Bruchstück/Rauschen) → **verwerfen**.
3. **Direkte Dubletten** (aufeinanderfolgende gleiche Werte) → **Maschinen-Doppel-Trigger**, zusammenfassen.
   Begründung: Nachbar-Gleichheit 12–28 %, Zufall wäre < 0.2 %; keine Größenkorrelation; nur Paare/Dreier.
   (Optional später mit einer gezählten Palette verifizieren.)
4. Danach **klassieren** (§6). Anzeigen: „X gelesen → −Overflow → −<100 g → −Dubletten → **N Kürbisse**".

Beispiel real (Datei 1613/Tiana): 11 370 → −5 → −11 → −3 204 → **8 161 Kürbisse**.

## 5. CSV-Dateiname & Zuordnung zum Auftrag

- Die Maschine erzeugt bei **jedem Chargenwechsel** eine neue Datei. Dateiname-Format (an der Maschine getippt):
  **`Charge-TT-MM-HH-MM`**, z. B. `1614-25-08-11-10` (Jahr = laufende Saison). Dadurch ist **jeder Lauf eindeutig**,
  auch wenn dieselbe Charge Mo–Fr wieder läuft — kein Überschreiben.
- Die App muss den Namen **tolerant** parsen: Chargennummer = 4-stellige Zahl gegen die bekannte Charge-Liste;
  Trenner können `-`, `_`, `/`, Leerzeichen sein; Datum/Zeit fuzzy. Notnagel: Datei-`lastModified` beim Upload.
- **Zuordnung:** über Charge + nächstliegende Zeit an den passenden **Auftrag** (verlässliche Server-Zeit).
  Eindeutig → automatisch; mehrdeutig/kein Treffer → **Admin-Warteschlange** „nicht zugeordnete CSVs".

## 6. Sorten-Kaliber-Grenzen (Gramm; Konvention [untere, obere))

Klassifikation pro Kürbisgewicht: **< Verlust-Grenze = VERLUST** (weggeworfen);
**in einem Band = HAUPTKANAL**; **≥ 2000 = NEBENKANAL** (kein Verlust, separat).
Kaliberzahl variiert je Sorte (2–4) — nicht als fix behandeln. Join über **Sortenname** (kanonisch unten).

| Sorte | Verlust < | Kaliber-Bänder | Nebenkanal ≥ |
|---|--:|---|--:|
| Orangita | 300 | 300–800 · 800–2000 | 2000 |
| Kaori Kuri | 600 | 600–1100 · 1100–1600 · 1600–2000 | 2000 |
| Mieluna | 500 | 500–800 · 800–1300 · 1300–1800 · 1800–2000 | 2000 |
| Amoro | 600 | 600–1100 · 1100–1600 · 1600–2000 | 2000 |
| Butterkin | 500 | 500–600 · 600–1200 · 1200–1800 · 1800–2000 | 2000 |
| Bolp 5110 | 600 | 600–1100 · 1100–1600 · 1600–2000 | 2000 |
| Orange Summer | 600 | 600–1100 · 1100–1600 · 1600–2000 | 2000 |
| Lekor | 700 | 700–1200 · 1200–1700 · 1700–2000 | 2000 |
| Fictor | 600 | 600–1100 · 1100–1600 · 1600–2000 | 2000 |
| Tiana | 500 | 500–800 · 800–1300 · 1300–1800 · 1800–2000 | 2000 |
| Ker Madec | 600 | 600–1100 · 1100–1600 · 1600–2000 | 2000 |

Kanonische Schreibweise = obige (im Grenzen-Sheet stand fälschlich „Lektor" statt „Lekor").

## 7. Charge-Registry (Schlag × Sorte → Chargennummer)

Join-Schlüssel überall = **Chargennummer** (immun gegen Schreibweisen/Leerzeichen). Nicht fortlaufend; als
undurchsichtige ID behandeln. Aktuelle Saison:

| Nr | Schlag | Sorte |
|--:|---|---|
| 1598 | Illnau Bruno | Kaori Kuri |
| 1599 | Illnau Bruno | Orangita |
| 1601 | Illnau Bruno | Mieluna |
| 1603 | Illnau Gross | Bolp 5110 |
| 1604 | Illnau Gross | Orangita |
| 1605 | Illnau Gross | Orange Summer |
| 1606 | Illnau Gross | Lekor |
| 1607 | Illnau Gross | Amoro |
| 1608 | Illnau Gross | Butterkin |
| 1609 | Illnau Gross | Kaori Kuri |
| 1610 | Illnau Gross | Fictor |
| 1611 | Negi Thalheim | Tiana |
| 1612 | Slowgrow Uster | Butterkin |
| 1613 | Slowgrow Uster | Tiana |
| 1614 | Slowgrow Uster | Kaori Kuri |
| 1615 | Slowgrow Uster | Ker Madec |
| 1616 | Slowgrow Uster | Lekor |
| 1617 | Slowgrow Uster | Orangita |
| 1618 | Slowgrow Uster | Orange Summer |
| 1619 | Gossau Eberhard | Kaori Kuri |
| 1620 | Gossau Eberhard | Orangita |
| 1623 | Agasul Rüegg | Mieluna |
| 1624 | Agasul Rüegg | Butterkin |
| 1625 | Agasul Rüegg | Amoro |
| 1626 | Agasul Rüegg | Tiana |
| 1627 | Agasul Rüegg | Fictor |
| 1628 | Agasul Baumann | Kaori Kuri |
| 1630 | Rümlang Keller | Kaori Kuri |
| 1631 | Rümlang Keller | Mieluna |
| 1632 | Andi Ball | Tiana |
| 1633 | Daniel Böhler | Tiana |
| 1634 | Daniel Böhler | Amoro |
| 1635 | Daniel Böhler | Kaori Kuri |
| 1636 | Klaus Böhler | Tiana |
| 1637 | Klaus Böhler | Amoro |
| 1638 | Klaus Böhler | Kaori Kuri |
| 1646 | Gossau Eberhard | Butterkin |
| 1647 | Bonomo | Tiana |
| 1648 | Russikon BundB | Orange Summer |
| 1649 | Rümlang Sauter | Butterkin |
| 1650 | Rümlang Sauter | Tiana |
| 1651 | Rümlang Sauter | Kaori Kuri |

## 8. Datenmodell (Vorschlag, Postgres)

- **charge**(nr PK, schlag, sorte)
- **sorte_kaliber**(sorte PK, verlust_unter, kaliber_baender jsonb, kanal_ab)
- **palette**(id, charge_nr FK, eingangsdatum, brutto_kg, kisten, gebindeart) — Import aus Journal-App
- **auftrag**(id, weg, station, charge_nr FK, start_ts, geplante_paletten, status)
- **auftrag_palette**(auftrag_id, palette_id?, eingangsdatum?) — Zähl-/Beitritts-Erfassung
- **sortier_lauf**(id, charge_nr, datei_name, roh_datei_ref, gelesen_ts, auftrag_id? , n_roh, n_overflow, n_klein, n_dubletten, n_gueltig)
- **sortier_kuerbis**(lauf_id FK, gewicht_g, klasse) — pro Kürbis (bereinigt); Roh separat referenziert
- **schimmel_messung**(auftrag_id, kg, ts, erfasser)
- **verdunstung_wiegung**(palette/charge, eingangsdatum, brutto_damals, brutto_jetzt, kisten, wiege_ts, sichtbar_schimmel bool)
- **marge_messung**(auftrag_id, art [nebenkanal|ueberfuellung], wert, ts)

Jede Messzeile: `gemessen bool`, `erfasser`, `ts`. **Leer ≠ 0.** Rohdaten immutable; Reinigung/Klassierung reproduzierbar.

## 9. Statistik-Ansatz (wie ein Data-Scientist)

- **Trennung:** *Rückgrat* (für jede Charge bekannt: Eingangsgewicht, Daten, Charge, Schlag, Sorte,
  Palettenzahl, CSV) vs. *Koeffizienten* (nur Stichprobe: Verdunstung %/Tag, Schimmelanteil je Lagerdauer,
  Ausschussanteil Weg 2).
- **Hochrechnung:** `Verlust = Koeffizient × bekannte Größe` (z. B. Verdunstung = Rate × Lagerdauer × Eingangsgewicht),
  **stratifiziert** nach Sorte/Schlag/Lagerdauer, Ergebnis als **Bereich** (Unsicherheit mitführen).
- **Mitten in der Saison auswertbar:** was noch im Lager liegt, ist **rechts-zensiert** →
  Überlebens-/Hazard-Analyse für Schimmel; Ausgabe „bisher beobachtet" + „projiziert",
  Bereiche werden enger mit mehr Daten. **Massenbilanz** Eingang vs. Verkauf + Verlust + Restbestand als Check.
- **Ziel = Ursachen rangieren**, nicht kg-genau. Stichproben so legen, dass sie die Kandidaten trennen.
  Wenige **komplett dokumentierte „Gold-Chargen"** als Eichanker.
- **Kleine Ströme direkt messen** (Schimmel-Palox wiegen), nie als Differenz zweier großer Zahlen.

## 10. App, Rollen, Auftrags-Flow

- **Zwei Rollen:** Betriebsleiter (Admin) + Arbeiter. Private Handys, Einzel-Login. Netz vorhanden (online-fähig).
- **Auftrag ist die zentrale Einheit.** Erster eröffnet ihn (Weg + Chargennummer → Server-Zeit),
  andere **treten bei** (Schichtwechsel möglich). Unter-Reiter je Funktion; jeder zeigt den laufenden Stand.
  Abschluss: „Auftrag abschließen?" → „Sicher?"; Box voll → Teilgewicht, später weiter.
- **Arbeiter erfassen minimal:** Paletten zählen (+, optional Eingangsdatum vom Zettel), Faule (kg, Palox am Ende),
  (Weg 2) zu gross/klein, optional Palette wiegen (Verdunstung). **Palettenzahl Pflicht, Wiegen optional.**
- **Betriebsleiter:** sagt wann gemessen wird; lädt Sortier-CSVs hoch; ordnet offene CSVs zu; Kontrolle; Dashboard.
- **Mengen:** Faule/Schimmel in **kg (ganzzahlig)**; Ausschuss klein aus CSV; Gross-Vergleich getrennt.

## 11. Dashboard (transparent, keine Blackbox)

- **Ebene 1:** Hauptursache + Bereiche (Ursachen rangiert, mit Unsicherheit).
- **Ebene 2:** Aufschlüsselung je Verlustart, filterbar nach Sorte/Schlag/Lagerdauer; zwei Bücher (Verlust vs. Marge).
- **Ebene 3:** Rohdaten + **aufklappbarer Rechenweg** je Zahl (welche Stichproben, welcher Koeffizient,
  welche Formel, welche Unsicherheit), Export. Massenbilanz sichtbar.
- Betriebsleiter darf zusätzlich per Tabellen-UI/SQL direkt in die Rohdaten.

## 12. Technik & Aufbau (kostenfrei, wo möglich)

Grundsatz: interner Betrieb, ein Hof — professionell & korrekt, aber **Hosting-Kosten vermeiden**.
Alle Bausteine haben Gratis-Stufen, GUI-Bedienung (laientauglich) und sind vom Assistenten baubar.

- **Frontend:** React + Vite als **reine Browser-App (SPA)**, gehostet **gratis auf Cloudflare Pages**
  (kommerziell erlaubt, private Repos, globales CDN). Kein Vercel/kein bezahltes Hosting nötig.
- **Backend:** **Supabase (Gratis-Stufe)** — Postgres-DB, Auth/Rollen (Row-Level-Security),
  Storage für Roh-CSVs, optional Edge Functions. Region **EU (Frankfurt)** — Daten in Europa.
- **CSV-Verarbeitung im Browser:** Parsen/Reinigen läuft clientseitig (Dateien ~60 KB) und schreibt
  direkt in Supabase — **kein eigener Server**.
- **Auswertung/Hochrechnung** als **SQL-Views/-Funktionen in Postgres** (schnell, transparent — der
  Betriebsleiter kann die Formeln direkt lesen); die SPA zeigt sie nur an.
- **Kosten: €0** auf den Gratis-Stufen. Einziger Kompromiss: Supabase-Gratisprojekte **pausieren nach
  7 Tagen ohne Nutzung** → 1-Klick-Reaktivierung. Während der Saison hält die wöchentliche Nutzung es
  wach; off-season pausiert es kostenlos. (Falls je störend: Supabase Pro ~25 $/Monat, nicht nötig.)
- **Transparenz:** Der Betriebsleiter nutzt zusätzlich die **Supabase-Tabellen-/SQL-Oberfläche** für
  vollen Rohdaten-Einblick.

**Aufbau-Reihenfolge:** (1) Supabase-Projekt anlegen [Nutzer, geführt, gratis] · (2) Schema +
Reinigungs-/Klassier-Logik + Stammdaten + Auswerte-Views [Assistent] · (3) SPA: Auftrags-Flow,
CSV-Upload+Pipeline (Browser), Matching, Rollen [Assistent] · (4) Cloudflare-Pages-Deploy [Nutzer
klickt, gratis] · (5) Dashboard [Assistent] · (6) Test mit echtem Auftrag + eine Palette zählen.

## 13. Offene Kleinigkeiten

- Eingangsdaten-Import: Chargennummer-Spalte in der Journal-App/dem Sheet ergänzen; Bruttogewicht + Kistenzahl liefern das Netto (Tara bekannt).
- Preise (pro Stück je Kaliber / pro Kiste) später fürs Marge-Buch.
- Ground-Truth Dubletten bei Gelegenheit bestätigen.
