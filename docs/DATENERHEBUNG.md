# Vor dem Scharfschalten — Datenerhebung, Trennung, Lager

Grundlage: die Ansage vom 14.09. — *„Fokus auf der Datenerhebung, so dass wir
heute mit dem Aufnehmen beginnen können. Die App muss genau mit den
Betriebsabläufen zusammenhängen, die Datenbank muss dann korrekt sein, und
anschliessend wird nichts mehr daran geändert."*

Nichts programmiert. Alles unten ist am Code und an der Datenbank nachgemessen.

---

## 1. Wo die Daten heute liegen

Die gute Nachricht zuerst: **die Trennung zwischen Struktur und Beobachtung
gibt es schon.** `setup.sql` enthält keine einzige Messung.

| Was | Wo | Umfang |
|---|---|---|
| **Struktur** — 28 Tabellen, 67 Sichten, 43 gespeicherte Ansichten, 44 Funktionen, Rechte, Auslöser | `supabase/setup.sql` | 635 KB |
| **Stammdaten** — Gebinde, 11 Sorten, **42 Chargen**, Sortierschemata, Ausgangsziele, Einstellungen | ebenfalls `setup.sql`, als `insert` | 14 Anweisungen |
| **Beobachtungen** — Paletten, Arbeiten, Palox, Wägungen, Lieferungen | **nirgends in einer Datei.** Sie entstehen durch Erfassung | — |
| **Demo-Saison** | die Funktion `demo_daten_laden()`, aufgerufen aus `supabase/demo_daten.sql` (2 KB) | erzeugt ~320 t |

Die Demo ist also **kein Datenbestand, sondern ein Knopf**. Sie markiert alles,
was sie anlegt (`bemerkung = 'DEMO'`, `extern_id like 'demo-%'`,
`datei_name like 'DEMO-%'`), und `demo_daten_entfernen()` räumt genau das
wieder weg — echte Daten bleiben unberührt.

> **Offener Punkt:** Die **42 Chargen** in `setup.sql` (Nr. 1598–1651,
> 14 Schläge, Saison 2026, mit Perigon-Nummern) sind Stammdaten, keine Demo.
> Sind das die echten Chargen dieser Saison? Wenn ja, bleiben sie; wenn nein,
> müssen sie vor dem Scharfschalten ersetzt werden.

---

## 2. Die Trennung: was ich empfehle

**Zwei Supabase-Projekte, zwei Cloudflare-Auslieferungen, *eine* `setup.sql`.**

```
              ein Repository, eine setup.sql
                          |
        +-----------------+-----------------+
        v                                   v
  kurbisverlust                    kurbisverlust-demo
  Cloudflare-Projekt               Cloudflare-Projekt
  VITE_SUPABASE_URL = A            VITE_SUPABASE_URL = B
        |                                   |
        v                                   v
  Supabase-Projekt A                 Supabase-Projekt B
  ECHTE DATEN                        Demo-Saison
  demo_daten_laden() gesperrt        jederzeit neu ladbar
```

**Warum so und nicht anders**

| Variante | Urteil |
|---|---|
| Zwei Supabase-Projekte | **Empfohlen.** Beide auf der Gratis-Stufe. Physisch getrennt — ein Fehlklick kann die echten Daten nicht erreichen. Dieselbe `setup.sql` läuft in beiden. |
| Ein Projekt, zwei Schemas | Abzuraten. Das ganze Rechenwerk, alle Rechte und alle Suchpfade stehen auf `public`. Das wäre ein Umbau mit vielen stillen Fallen. |
| Ein Projekt, Demo markiert (heute) | Funktioniert, aber: Ein versehentliches „Demo laden" verdoppelt die Saison in der Auswertung. Und man kann nichts Riskantes ausprobieren. |

**Ein technisches Detail, das man kennen muss:** `VITE_SUPABASE_URL` und
`VITE_SUPABASE_ANON_KEY` werden **beim Bauen** in das Bündel geschrieben, nicht
zur Laufzeit gelesen. Zwei Auslieferungen heissen darum zwei Builds mit je
eigenen Umgebungsvariablen — in Cloudflare zwei Projekte aus demselben
Repository, jedes mit seinen zwei Variablen. Am Code ändert sich dafür nichts.
(Der Anon-Key ist ohnehin öffentlich; er steckt im Browser-Bündel. Geschützt
wird über die Zeilenregeln, nicht über Geheimhaltung.)

**Zwei kleine Ergänzungen, die viel Sicherheit bringen** (additiv, ungefährlich):

1. Eine Einstellung `instanz = 'echt' | 'demo'` **in der Datenbank**. Die App
   liest sie und zeigt auf der Demo ein farbiges Band „DEMO-SYSTEM". Damit
   kann niemand die beiden verwechseln — und es steht in der Datenbank, nicht
   im Build, also ist es fälschungssicher.
2. Auf `instanz = 'echt'` verschwindet der Knopf „Demo-Daten laden", und
   `demo_daten_laden()` verweigert die Ausführung.

---

## 3. Das grösste Risiko heisst nicht Struktur, sondern Sicherung

Ab morgen sind die Daten unersetzlich — eine Palette, die im Oktober nicht
gewogen wurde, lässt sich im März nicht nachholen. Das ist ein
<em>grösseres</em> Risiko als jede Schemafrage.

**Was geklärt sein muss, bevor echte Daten hineingehen:**

- Welche Sicherung bietet die Supabase-Stufe, die du hast, und über wie viele
  Tage reicht sie zurück?
- Wer merkt es, wenn eine Woche lang nichts mehr geschrieben wurde?
- Gibt es eine Ausfuhr, die der Betrieb selbst auslösen kann — ohne
  Kommandozeile, nur mit dem Browser?

Ein Export-Knopf „Alles sichern" (alle Beobachtungstabellen als Dateien) wäre
wenig Arbeit und der billigste Versicherungsschutz, den es gibt. **Das ist
meine dringendste Empfehlung vor dem Scharfschalten.**

### 3.1 Was seit Runde Q gebaut ist

Zwei Netze, und sie fangen Verschiedenes.

**Das Journal** (`erfassung_journal`, Migration 0072) hängt als Auslöser an
siebzehn Tabellen. Jede Änderung wird festgehalten; bei einem Löschen steht
die **ganze alte Zeile als JSON** darin, mit Zeitpunkt und Urheber. Niemand
kann das Journal ändern oder löschen — auch der Betriebsleiter nicht. Ein
Protokoll, das sich bearbeiten lässt, ist keines.

Damit gilt: **eine gelöschte Messung ist wiederherstellbar**, solange die
Datenbank selbst existiert.

```sql
-- Was wurde in den letzten sieben Tagen gelöscht?
select wann, tabelle, zeile_id, alt
  from erfassung_journal
 where vorgang = 'delete' and wann > now() - interval '7 days'
 order by wann desc;
```

**Der Wächter** (`supabase/test/keine_zerstoerung.sh`) liest die Migrationen
und ist rot, sobald eine davon `drop table`, `drop column`, `truncate` oder
ein `delete from` ohne `where` enthält. Er läuft als Erstes in
`supabase/test/run.sh` — noch vor jeder Datenbankverbindung. Drei geprüfte
Altfälle stehen mit Begründung in einer Freigabeliste im Skript selbst.

Das Journal fängt, was trotzdem passiert. Der Wächter sorgt dafür, dass es
gar nicht erst passiert.

### 3.2 Was das Journal NICHT ersetzt

Beides hilft nichts, wenn die Datenbank als Ganzes verschwindet. Dafür
braucht es eine Sicherung, und die zieht der Betrieb selbst.

**Weg 1 — über das Supabase-Dashboard (kein Werkzeug nötig):**

1. Supabase öffnen → das Projekt wählen
2. Links **Database** → **Backups**
3. Dort steht, welche Sicherungen es gibt und bis wann sie zurückreichen.
   Auf der Gratis-Stufe sind das wenige Tage — das reicht für einen Unfall,
   nicht für eine Saison.

**Weg 2 — eine eigene Kopie, die dem Betrieb gehört:**

```bash
# Die Verbindungszeichenfolge steht in Supabase unter
# Project Settings → Database → Connection string → URI
pg_dump "postgresql://postgres:PASSWORT@db.xxxx.supabase.co:5432/postgres"   --no-owner --no-acl --format=custom   --file="kuerbis-$(date +%Y-%m-%d).dump"
```

Die Datei gehört auf einen anderen Rechner als den, der sie erzeugt hat.

**Die Regel, die jede andere überwiegt:**

> **Vor jedem Einspielen von `setup.sql` eine Sicherung.**

`setup.sql` ersetzt das ganze Rechenwerk (Teil B) und legt Fehlendes an
(Teil A). Sie nimmt keine Daten weg — der Prüfstand belegt das bei jedem
Lauf. Aber „belegt" ist nicht „unmöglich", und eine Sicherung kostet zwei
Minuten.

### 3.3 Die Erinnerung in der App

`einstellung('letzte_sicherung')` hält fest, wann zuletzt gesichert wurde.
Der Betriebsleiter trägt das von Hand ein — es gibt keinen automatischen
Mechanismus, und es soll auch keiner vorgetäuscht werden. Auf der Seite
**Betrieb** steht die Zeile „Letzte vermerkte Sicherung: …", ab dreissig
Tagen in Warnfarbe.

Steht `einstellung('erfassung_scharf')` auf `true`, gibt `setup.sql` beim
Einspielen zusätzlich einen deutlichen Hinweis aus, dass auf dieser Datenbank
echte Erfassungsdaten liegen.

---

## 4. Was „eingefroren" wirklich heisst — und was nicht

Hier ist die Lage besser, als sie klingt. `setup.sql` ist in zwei Teile gebaut,
und die verhalten sich völlig verschieden:

| | **Teil A** | **Teil B** |
|---|---|---|
| Inhalt | Tabellen, Spalten, Bedingungen, Stammdaten | Sichten, gespeicherte Ansichten, rechnende Funktionen |
| Charakter | **eine Geschichte** — jeder Schritt zählt | **ein Zustand** — nur die letzte Fassung |
| Beim Aktualisieren | wird fortgeschrieben | wird **vollständig ersetzt** |

**Daraus folgt: Das Dashboard darf sich beliebig weiterentwickeln.** Jede neue
Kennzahl, jede neue Sicht, jede geänderte Formel lebt in Teil B und wird bei
jedem `setup.sql` sauber neu gebaut. Das berührt keine einzige erfasste Zeile.

**Was nach dem Scharfschalten gefährlich ist:**

| Gefährlich | Ungefährlich |
|---|---|
| eine Spalte löschen oder umbenennen | eine **neue** Spalte anlegen (leer erlaubt) |
| die Bedeutung einer Spalte ändern | eine **neue** Tabelle anlegen |
| Zeilen löschen | jede Sicht, jede Funktion, jede Auswertung ändern |
| eine Pflichtbedingung nachträglich verschärfen | eine Auffälligkeit ergänzen |

**Und daraus folgt der eigentliche Auftrag für heute:**

> Was heute nicht **erfasst** wird, kann kein Dashboard der Welt später
> erfinden. Die Frage ist nicht „was wollen wir anzeigen", sondern
> **„was wollen wir je auswerten können"**. Im Zweifel erheben.

---

## 5. Was heute noch entschieden werden muss

Jede Zeile hier verändert entweder die Arbeiter-App oder die Tabellen — also
genau das, was danach stehen soll.

| | Entscheidung | Warum heute |
|---|---|---|
| **A** | **Palox F1–F3** reparieren (gefallener Stand zeigt nichts; `palox_geleert` unerreichbar; 0 kg statt „unbekannt") | Betrifft jede Arbeit ab dem ersten Tag. Braucht nur Frage 1 und 2. |
| **B** | **Die Massenbrücke nach dem Sortieren** (Frage 5). Ohne sie haben 201 von 305 Arbeiten keine Masse. | Wenn wir die Kaliber-Palette wiegen wollen, braucht es eine neue Maske und eine neue Tabelle — danach nicht mehr. |
| **C** | **Palox beim Waschen**: freiwillig lassen oder Pflicht? | Er misst das höchste Alter und ist der wertvollste Punkt der ganzen Verderbskurve. |
| **D** | **Lagerkontrolle**: soll die App aktiv daran erinnern (z. B. wöchentlich)? | Die einzige Messung ohne Auswahlverzerrung. Heute: null davon. |
| **E** | **Fax nach Waschen+Sortieren** (F8): der Vorschlag findet die Wascharbeit nicht. | Einzeiler, aber Arbeiter-App. |
| **F** | **Sortierschemata je Sorte** (Frage 14): heute gilt für 8 von 11 Sorten „Kiste ab 8 kg", nicht Kaliber. | Bestimmt, ob die Sortier-CSV überhaupt klassiert. |
| **G** | **Gebinde-Taras**: jeder IFCO-Typ mit seinem Leergewicht. | Ohne sie gibt es kein Netto — und Netto ist der Nenner von allem. |
| **H** | **Erntejournal**: welches Blatt, welche Spalten, wer lädt es wann? | Der Eingang ist die Bezugsmasse. |

**Checkliste zum Scharfschalten** (wenn A–H entschieden sind):
Supabase-Projekt anlegen · `setup.sql` ausführen · echte Chargen prüfen ·
Gebinde-Taras eintragen · `palox_tara_kg` · `kisten_pro_palette` ·
`erfassungsbeginn` auf heute · `saison_ende` · Sortierschemata je Sorte ·
anonyme Anmeldung freischalten · ersten Betriebsleiter ernennen · QR drucken ·
**Sicherung geklärt** · Erntejournal verbunden.

---

## 6. Lager-Management als Kern — was die Daten hergeben

Gefragt ist: *wie viel liegt, von welcher Sorte, von welcher Charge, wie viel
davon faul, wie viel verkaufsfähig, und wie viel leichter als beim Eingang.*
Alles davon ist heute schon gerechnet; es steht nur an fünf verschiedenen
Stellen. Beispiel Charge 1632, wie es zusammengehört:

```
  Charge 1632 · Tiana · Andi Ball · Eingang 18.–24.03. · 93 Paletten

  Eingang                                        36 946 kg
  davon ausgeliefert                              6 394 kg
  ---------------------------------------------------------
  IM LAGER (Eingangsware)                        29 300 kg     liegt 174–180 d
      davon Wasser verloren                     − 2 308 kg     ( 7.9 % )
      davon faul geworden                       − 2 852 kg     ( 9.7 % )
  ---------------------------------------------------------
  GUTE WARE, heute tatsächlich vorhanden         24 140 kg
      davon zu klein / zu gross                 − 1 267 kg
      davon beim Abpacken erwartet              −   298 kg
  ---------------------------------------------------------
  VERKAUFSFÄHIG                                  22 576 kg     ( 77.1 % )
                                        Hülle    21 941 … 23 132 kg
```

Die Zeile **„davon Wasser verloren − 2 308 kg"** ist die, die du meinst mit
*„es ist eben nicht wenig"*: Das sind 7.9 % der liegenden Masse, allein aus
Verdunstung, an einer einzigen Charge. Sie steht heute nirgends so da.

---

## 7. Neu und wichtig: die Kaliberwanderung

Deine Frage — *„von dem Kaliber ist noch so viel da, aber gewisse fallen in
eine andere Kalibergrösse"* — habe ich nachgerechnet. Sie ist berechtigt, und
der Effekt ist grösser, als ich erwartet hätte.

Die Sortier-CSV enthält **jeden Kürbis einzeln in Gramm**. Man kann also das
ganze Histogramm um die Verdunstung verschieben und neu klassieren. Mit der
gemessenen Rate (0.052 %/Tag), über 91 101 gewogene Kürbisse der Demo:

| Nach | rutscht unter die unterste Kalibergrenze | Masse verloren |
|---|---|---|
| 60 Tagen | 573 Stück · 0.63 % | 3 213 kg |
| 120 Tagen | 1 181 Stück · 1.30 % | 6 327 kg |
| **180 Tagen** | **1 806 Stück · 1.98 %** | 9 346 kg |
| 240 Tagen | 2 544 Stück · 2.79 % | 12 272 kg |

**Erste Folgerung:** *„Zu klein wächst nicht mit der Lagerdauer"* stimmt so
nicht ganz. Es wächst — um rund zwei Prozentpunkte über eine Saison. Klein
gegen die 4.5 % vom Feld, aber nicht null, und es ist bisher nirgends
abgebildet.

**Zweite Folgerung, und die ist die eigentliche:** Bei schon sortierter Ware
steht auf der Kiste das Kaliber **vom Sortiertag**. Der Inhalt ist heute
leichter. Was in der Kiste ist, im Vergleich zum Etikett:

| Sorte | Etikett | bei Sortierung | nach 60 d | nach 120 d | Lage im Band |
|---|---|---|---|---|---|
| Amoro | 1600–2000 g | 1 757 g | 1 703 g | 1 650 g | 39 % → 13 % |
| Kaori Kuri | 1100–1600 g | 1 288 g | 1 248 g | 1 210 g | 38 % → 22 % |
| **Kaori Kuri** | **1600–2000 g** | **1 644 g** | **1 593 g** | **1 544 g** | **11 % → −14 %** |
| Butterkin | 1200–1800 g | 1 423 g | 1 380 g | 1 337 g | 37 % → 23 % |

Die markierte Zeile: Kaori Kuri im obersten Band liegt schon bei der Sortierung
nur 11 % über der Unterkante. **Nach 60 Tagen ist der Durchschnitt unter
1 600 g — also unter der Grenze, die auf der Kiste steht.** Nach 120 Tagen
deutlich darunter.

Das ist eine Aussage, die der Betrieb heute nirgends bekommt, und sie hat zwei
praktische Seiten: Sie sagt, **welches Kaliber zuerst raus muss** (nicht das
älteste, sondern das, dessen Ware am nächsten an der Unterkante liegt), und sie
sagt etwas über das **Sortierschema** (ein Band, das bei 11 % startet, ist zu
knapp geschnitten).

> Für die Erhebung heisst das: **nichts Neues zu erfassen.** Alles steckt schon
> in der Sortier-CSV und in der Verdunstungsrate. Es ist reine Auswertung —
> also Teil B, also jederzeit nachrüstbar. Gut so.

---

## 8. Was ich daraus für die Reihenfolge schliesse

1. **Heute:** A–H entscheiden, Arbeiter-App und Tabellen fertigmachen,
   Sicherung klären.
2. **Dann scharfschalten:** echtes Supabase-Projekt, Demo auf ein zweites.
3. **Danach:** Dashboard, so lange und so oft es nötig ist — es berührt nur
   Teil B und kann keine erfasste Zeile beschädigen.

Der Lagerrechner und die Kaliberwanderung sind beide reine Auswertung. Sie
können also getrost warten, bis Daten da sind — sie brauchen keine einzige
zusätzliche Frage in der Halle.
