# Zwei Webseiten: eine für den Betrieb, eine zum Ausprobieren

> **Seit Runde S gibt es dafür einen kürzeren Weg — [docs/DEMO.md](DEMO.md).**
> Dort bleibt es bei *einer* Webseite: Wer sich anmeldet, arbeitet mit den
> echten Daten; wer vorher auf „Demo ansehen" drückt, landet in einer zweiten
> Datenbank mit einer erfundenen Saison. Ein Cloudflare-Projekt statt zwei,
> eine Adresse statt zwei, ein QR-Code statt zwei — und trotzdem dieselbe
> harte Trennung der Daten, denn die zweite Datenbank braucht es so oder so.
>
> Diese Anleitung hier bleibt gültig und beschreibt den anderen Weg: zwei
> vollständig getrennte Webseiten mit eigenen Adressen. Den braucht, wer der
> Beispiel-Seite eine eigene Adresse zum Weitergeben geben will. Wer nur
> zeigen will, was die App kann, nimmt DEMO.md.

Ab jetzt laufen **zwei getrennte Aufbauten** nebeneinander:

| | **Echt** | **Beispiel** |
|---|---|---|
| wofür | die Halle, ab morgen | ausprobieren, zeigen, üben |
| Daten | echte Messungen, werden nie gelöscht | eine erfundene Saison, jederzeit neu ladbar |
| Supabase-Projekt | ein **neues**, leeres | das **bestehende** mit der Demo |
| Cloudflare-Worker | `kurbisverlust` (die Adresse, die du kennst) | `kurbisverlust-beispiel` |
| `einstellung.betriebsmodus` | `echt` | `beispiel` |
| `einstellung.erfassung_scharf` | `true` (du setzt sie in Teil 1) | `false` |
| Demo-Daten laden | die Datenbank weist es ab | geht mit einem Knopf |
| Band oben in der App | keines | „Beispieldaten — nicht der Betrieb" |

**Warum zwei und nicht ein Schalter.** Weil sonst genau der Fehler passiert, den
niemand mehr rückgängig macht: Eine erfundene Palette landet zwischen echten
Messungen, und nachher weiss keiner mehr, welche Zahl gemessen und welche
erfunden war.

**Warum das neue Projekt das echte wird und nicht umgekehrt.** Die echte
Datenbank soll nie eine Demo-Zeile gesehen haben. „Demo-Daten entfernen" räumt
zuverlässig auf — aber ein Projekt, das nie eine Demo hatte, braucht gar nicht
aufzuräumen. Ein Supabase-Projekt kostet in der Gratis-Stufe nichts; die
Vorsicht auch nicht.

**Warum die kurze Adresse die echte bleibt.** Der QR-Code in der Halle zeigt auf
`kurbisverlust…workers.dev`. Wenn diese Adresse die echte bleibt, musst du ihn
nie wieder austauschen — und niemand tippt aus Versehen in die Beispiel-App.

> **Wenn du noch gar nichts veröffentlicht hast:** dann mach einfach beide Teile
> neu — Teil 1 und 3 für die echte Seite, Teil 2 und 4 für die Beispiel-Seite.
> Die Sätze „das bestehende Projekt" liest du dann als „das zweite Projekt".

---

## Bevor du anfängst

Halte bereit:

* Zugang zu **supabase.com** (dein Konto)
* Zugang zu **dash.cloudflare.com** (dein Konto)
* die Datei **`supabase/setup.sql`** aus diesem Projekt — immer der aktuelle
  Stand aus dem Repository. Welchen Stand sie hat, sagt sie selbst: die
  Fertig-Zeile am Ende nennt ihn, und die App meldet sich von allein, wenn
  Datei und Programm auseinanderliegen.

Rechne mit **einer guten halben Stunde**. Die Wartezeiten sind Build-Zeiten,
nichts davon ist knifflig.

**Wie die Teile aufeinander aufbauen:**

```
Teil 0  die zwei Werte der bestehenden Datenbank abschreiben
Teil 1  neue, leere Datenbank anlegen            → zwei neue Werte
Teil 2  bestehende Datenbank auf Beispiel stellen
Teil 3  bestehende Webseite auf die neue Datenbank umhängen   (Werte aus Teil 1)
Teil 4  zweite Webseite für die Beispiel-Datenbank            (Werte aus Teil 0)
Teil 5  die Probe aufs Exempel
Teil 6  bevor die erste echte Palette gezählt wird
```

---

## Teil 0 — Zuerst abschreiben, was du gleich überschreibst

Zwei Minuten, die dir später einen Umweg sparen: In Teil 3 ersetzt du bei
Cloudflare die zwei Werte, die auf die **bestehende** (Demo-)Datenbank zeigen —
und in Teil 4 brauchst du genau diese zwei wieder.

1. https://dash.cloudflare.com → **Workers & Pages** → Projekt `kurbisverlust`
   → **Settings** → **Variables and Secrets**.
2. Die zwei Werte irgendwo hinschreiben:

   ```
   Demo-Datenbank
   VITE_SUPABASE_URL      = https://……………………….supabase.co
   VITE_SUPABASE_ANON_KEY = sb_publishable_……………………
   ```

Falls du sie nicht mehr findest: Im Supabase-Dashboard des bestehenden
Projekts stehen sie auf **zwei verschiedenen Seiten** — der Schlüssel unter
*Project Settings → API Keys* (Abschnitt **Publishable key**, beginnt mit
`sb_publishable_`), die Project URL unter *Project Settings → Data API*. Der
genaue Weg mit allen Fallstricken steht im README, **Schritt 5**.

---

## Teil 1 — Die echte Datenbank anlegen (neu und leer)

**Was du machst**

1. Auf https://supabase.com anmelden → **New project**.
2. Name: `kuerbis-echt`. Region: **Frankfurt** oder **Zürich** (was näher ist).
   Datenbank-Passwort vergeben und **aufschreiben** — du brauchst es später bei
   Sicherungen und bekommst es nicht wieder angezeigt.
3. **Create new project**. Das Anlegen dauert ein bis zwei Minuten.
4. Linke Symbolleiste → **SQL Editor** → **New query**.
5. Den **ganzen** Inhalt von `supabase/setup.sql` einfügen und **Run** drücken.

   > **Fragt Supabase „Potentially destructive operation"** oder „Are you sure
   > you want to run this query?" — das ist normal. Die Datei legt
   > Sicherheitsregeln neu an, und Supabase warnt bei jedem Skript, das solche
   > Befehle enthält. **Run this query** beziehungsweise **I understand, run
   > this query** klicken; ein Kästchen zum Ankreuzen ankreuzen. In einem frisch
   > angelegten Projekt gibt es nichts, was kaputtgehen könnte.

**Was du siehst**

Unten eine Tabelle mit einer Spalte `ergebnis` und einer Zeile darin:

```
Fertig. Die Datenbank steht: 42 Chargen, 11 Sorten, 31 Tabellen,
75 Auswertungen. Auswertung berechnet. Weiter im README bei Schritt 4.
```

Die Zahlen für **Tabellen** und **Auswertungen** wachsen mit dem Programm und
sind kein Prüfmerkmal — wichtig sind die Wörter **„Fertig."** und
**„Auswertung berechnet."**. Die 42 Chargen und 11 Sorten stehen dagegen fest:
Das sind deine echten Chargen aus der Anbauplanung, keine Demo-Daten.

Je nachdem, was das Projekt kann, steht dazwischen noch ein Satz über `pg_cron`
(„Ohne pg_cron rechnet die App selbst nach, wenn etwas veraltet ist.") — auch
das ist in Ordnung. Und daneben können Hinweise des Servers stehen oder auch
nicht; das hängt am Editor. Solange die Zeile mit „Fertig." da ist, hat es
geklappt.

6. Noch zwei Schalter in Supabase, beide pro Projekt (wie in README Schritt 4
   und 4b beschrieben):
   * **Authentication → Sign In / Providers → Confirm email** auf **aus**
   * **Authentication → Sign In / Providers → Anonymous sign-ins** auf **an**
     (sonst kommen die Arbeiter nicht per QR-Code herein)

7. Kontrolle im SQL-Editor:

```sql
select wert from einstellung where schluessel = 'betriebsmodus';
```

**Woran du merkst, dass es geklappt hat:** dort steht `"echt"`. Das ist die
Vorgabe — du musst nichts setzen. Wenn jemand den Schritt vergisst, ist die
Datenbank im sicheren Zustand und nicht im unsicheren.

8. Die zwei Zugangswerte abholen — sie stehen auf **zwei verschiedenen
   Seiten** (README, Schritt 5, beschreibt beide Wege im Einzelnen):

   * der Schlüssel unter *Project Settings → API Keys*, Abschnitt
     **Publishable key**, beginnt mit `sb_publishable_`. **Nicht** der
     „Secret key" darunter — der gehört nie in eine Webseite;
   * die Project URL unter *Project Settings → Data API*, ganz oben.

   Beide aufschreiben, du brauchst sie in Teil 3:

   ```
   Echte Datenbank
   VITE_SUPABASE_URL      = https://……………………….supabase.co
   VITE_SUPABASE_ANON_KEY = sb_publishable_……………………
   ```

9. **Die Datenbank als scharf markieren.** Im SQL-Editor — die zweite Zeile
   zeigt dir gleich, ob es angekommen ist, deshalb beides zusammen einfügen:

```sql
update einstellung
   set wert = to_jsonb(true)
 where schluessel = 'erfassung_scharf';

select schluessel, wert from einstellung where schluessel = 'erfassung_scharf';
```

   **Woran du merkst, dass es geklappt hat:** die zweite Abfrage liefert eine
   Zeile, und dort steht `true`. Kommt **keine** Zeile, hat das `update` nichts
   getroffen — dann ist `setup.sql` in dieser Datenbank nicht (vollständig)
   gelaufen; zurück zu Punkt 5.

   Das ändert an der Erfassung nichts — es ist eine Markierung. Aber von jetzt
   an sagt jedes spätere Einspielen von `setup.sql` in **dieser** Datenbank
   als Erstes: *„ACHTUNG: Auf dieser Datenbank liegen echte Erfassungsdaten"*,
   und die Betriebsseite in der App zeigt den Hinweis zur Sicherung. Wer in
   einem halben Jahr die Datei in das falsche Projekt einfügt, sieht es in der
   ersten Zeile. Genau darum ist die Kontrollabfrage hier wichtig: Eine
   Markierung, die stillschweigend nicht gesetzt wurde, warnt auch nicht.

---

## Teil 2 — Das bestehende Projekt zur Beispiel-Datenbank machen

Das ist die Datenbank, in der die Demo-Saison schon liegt.

**Was du machst**

1. Im **bestehenden** Supabase-Projekt → **SQL Editor** → **New query**.
2. Erst `supabase/setup.sql` einspielen, damit auch diese Datenbank auf dem
   neuen Stand ist. Deine Daten bleiben dabei erhalten. Die Rückfrage
   „Potentially destructive operation" kommt hier genauso — bestätigen.
3. Dann in einer neuen Abfrage den Modus umstellen und gleich nachsehen:

```sql
update einstellung
   set wert = to_jsonb('beispiel'::text)
 where schluessel = 'betriebsmodus';

select wert from einstellung where schluessel = 'betriebsmodus';
```

**Woran du merkst, dass es geklappt hat:** dort steht `"beispiel"`.

`erfassung_scharf` lässt du hier auf `false` — das ist die Datenbank, in der
Aufräumen erlaubt ist.

> Der Modus bleibt so, auch wenn du `setup.sql` später wieder einspielst — die
> Datei legt die Einstellung nur an, wenn es sie noch gar nicht gibt, und rührt
> einen vorhandenen Wert nicht an.

---

## Teil 3 — Die echte Webseite

Hier stellst du die **bestehende** Veröffentlichung auf die **neue** Datenbank
um. Die Adresse bleibt dieselbe.

**Was du machst**

1. Auf https://dash.cloudflare.com → **Workers & Pages** → dein Projekt
   **`kurbisverlust`**.
2. Reiter **Settings** → **Variables and Secrets**.
3. Die zwei Werte auf das **neue** Projekt aus Teil 1 ändern:

   | Variable | neuer Wert | Typ |
   |---|---|---|
   | `VITE_SUPABASE_URL` | die Project URL von `kuerbis-echt` | **Text** |
   | `VITE_SUPABASE_ANON_KEY` | der `sb_publishable_…`-Schlüssel von `kuerbis-echt` | **Text** |

   Beim Einfügen darf kein Leerzeichen und kein Zeilenumbruch mitkommen.

   > **Beide Werte immer aus demselben Supabase-Tab holen.** Sie stehen auf
   > zwei Seiten, und ab jetzt gibt es zwei Projekte — eine URL aus dem einen
   > und ein Schlüssel aus dem anderen fällt nicht auf: Die Seite startet ganz
   > normal, und erst beim Anmelden kommt „Invalid API key". Wenn du diese
   > Meldung siehst, gehören die zwei Werte zu verschiedenen Projekten.

   > **Typ „Text", nicht „Secret".** Cloudflare bietet „Secret" an, und bei
   > etwas, das „Key" heisst, greift man leicht danach. Ein Secret steht beim
   > **Bauen** aber nicht zur Verfügung — und genau beim Bauen werden die zwei
   > Werte in die Seite eingesetzt. Die Seite startete dann mit „Noch nicht mit
   > Supabase verbunden". Der Schlüssel ist ohnehin der öffentliche; er ist
   > dafür gemacht, im Browser zu stehen, und ohne Anmeldung kommt damit
   > niemand an Daten.

4. **Speichern.**
5. **Zwingend:** Reiter **Deployments** → beim obersten Eintrag rechts das Menü
   **⋯** → **Retry deployment**.

> **Warum der zweite Schritt sein muss:** Die zwei Werte kommen beim **Bauen**
> fest in die Seite. Ohne neuen Build zeigt die Adresse weiter auf die alte
> Datenbank — egal was in den Einstellungen steht.

6. **Dein Betriebsleiter-Konto in der neuen Datenbank anlegen.** Die neue
   Datenbank ist leer — sie kennt auch dich noch nicht. Ohne diesen Schritt
   kommst du auf der echten Adresse nur als Arbeiter herein, siehst keine
   Reiter und kannst nichts aus Teil 6 erledigen.

   Das ist README **Schritt 7**, noch einmal, für **dieses** Projekt:

   1. Auf der Adresse unten auf **Betriebsleiter-Login** → **Neues
      Betriebsleiter-Konto anlegen**, Namen, E-Mail und ein Passwort
      (mindestens 6 Zeichen) eintragen.
   2. Im SQL-Editor der **neuen** Datenbank (nicht der Demo!):

      ```sql
      update profil set rolle = 'admin'
       where id = (select id from auth.users where email = 'deine@adresse.ch');

      select name, rolle from profil;
      ```

      Die E-Mail-Adresse durch deine ersetzen. Die zweite Zeile zeigt dir
      gleich das Ergebnis: In deiner Zeile muss unter `rolle` jetzt **admin**
      stehen.
   3. Im App-Tab **F5**.

**Woran du merkst, dass es geklappt hat**

Nach dem Anmelden steht zuerst die **Startseite der Halle** da („Hallo …",
„Gerade läuft keine Arbeit.") — das ist richtig so und kein Fehler. Die
Auswertung liegt hinter den Reitern:

* am Computer **links** in einer Seitenleiste, mit fünf Reitern
  (**Lagermanagement**, **Ursachen**, **Chargen**, **Messungen**, **Betrieb**),
  ganz unten darin dein Name mit dem Zusatz *Betriebsleiter*;
* auf dem Handy als **Zeile unter der Kopfzeile**.

Sind die Reiter nicht da, ist Punkt 6 noch offen. Sind sie da, prüfe drei Dinge:

* **kein Band** am oberen Rand — die Beispiel-Seite trägt dort einen gelben
  Streifen mit dem Satz „Beispieldaten — nicht der Betrieb"; hier gibt es ihn
  nicht;
* unter **Betrieb → Stammdaten → Demo-Daten** stehen **keine Knöpfe**, sondern
  der Satz „Diese Datenbank läuft im Echtmodus …";
* **Lagermanagement** meldet „Noch keine auswertbaren Daten. Dafür braucht es
  mindestens Eingangspaletten mit hinterlegter Tara — siehe Betrieb →
  Stammdaten." Das ist richtig so, es ist noch nichts erfasst.

---

## Teil 4 — Die Beispiel-Webseite

Ein **zweites** Cloudflare-Projekt aus demselben Code.

**Was du machst**

1. Auf https://dash.cloudflare.com → **Workers & Pages** → **Create
   application** → **Import a repository**.
2. Wieder `konvalinaalexander-max/Kurbisverlust` auswählen.
3. Auf der Seite **Set up your application**:

   | Feld | Wert |
   |---|---|
   | Project name | `kurbisverlust-beispiel` |
   | Build command | `npm run build` |
   | **Deploy command** | **`npx wrangler deploy --env beispiel`** |

   > **Der Deploy-Befehl ist der wichtige Teil.** Ohne das `--env beispiel`
   > würde diese zweite Seite auf denselben Worker deployen wie die erste — und
   > deine Halle zeigte plötzlich Beispieldaten. Mit dem Zusatz bekommt sie
   > einen eigenen Worker namens `kurbisverlust-beispiel`; das steht in
   > `wrangler.toml` und ist Teil des Programms, du musst nichts einrichten.
   >
   > Wrangler warnt zwar, wenn der Zusatz fehlt („Multiple environments are
   > defined in the Wrangler configuration file…"), aber es hält ihn nicht auf.
   > Deshalb steht unten die Abnahme in Punkt 6.

4. Bei **Variables and Secrets** die zwei Werte des **bestehenden** (Demo-)
   Projekts eintragen — die aus Teil 0, wieder beide vom Typ **Text**:

   | Variable | Wert | Typ |
   |---|---|---|
   | `VITE_SUPABASE_URL` | Project URL der Demo-Datenbank | **Text** |
   | `VITE_SUPABASE_ANON_KEY` | deren `sb_publishable_…`-Schlüssel | **Text** |

   Auch hier: beide aus demselben Supabase-Tab. „Invalid API key" beim Anmelden
   heisst, dass sie aus verschiedenen Projekten stammen.

5. **Deploy**. Ein bis drei Minuten.

6. **Abnahme, gleich danach:** In **Workers & Pages** stehen jetzt **zwei**
   Einträge:

   * `kurbisverlust` — Zeitpunkt der letzten Veröffentlichung unverändert
     (der von deinem *Retry deployment* aus Teil 3),
   * `kurbisverlust-beispiel` — gerade eben veröffentlicht.

   Steht dort nur **ein** Eintrag und `kurbisverlust` wurde gerade neu
   veröffentlicht, hat der Deploy-Befehl das `--env beispiel` nicht gehabt:
   Im neuen Projekt unter **Settings → Build** den Deploy command korrigieren,
   dann dort **Retry deployment** — und danach **Teil 3 Punkt 5 noch einmal**,
   damit die echte Seite wieder auf die echte Datenbank zeigt.

**Woran du merkst, dass es geklappt hat**

Du bekommst eine zweite Adresse, etwa
`https://kurbisverlust-beispiel.<etwas>.workers.dev`. Öffne sie und melde dich
an:

* oben läuft ein Band mit dem Satz **„Beispieldaten — nicht der Betrieb"**
  (gelb auf hellem Grund, im Dunkelmodus heller — der **Satz** ist das
  Merkmal, nicht die Farbe),
* unter **Betrieb → Stammdaten → Demo-Daten** stehen die Knöpfe,
* alle Zahlen sind da wie bisher.

---

## Teil 5 — Die Probe aufs Exempel

Drei Minuten, und du weisst, dass die Trennung wirklich hält.

**1. Das Band.** Echte Seite: kein Band. Beispiel-Seite: das Band mit
„Beispieldaten — nicht der Betrieb".

> **Das Band erscheint erst nach dem Anmelden.** Auf dem Anmeldebildschirm
> sehen beide Seiten gleich aus. Deshalb hängt in der Halle nur **ein**
> QR-Code, und deshalb steht in Teil 6 die Kontrolle der Adresszeile auf dem
> Ausdruck.

**2. Der harte Test.** Im SQL-Editor der **echten** Datenbank:

```sql
select demo_daten_laden();
```

Das **muss** abbrechen. Es gibt drei mögliche Ausgänge:

| Meldung | Bedeutung |
|---|---|
| „Diese Datenbank läuft im Echtmodus — Beispieldaten werden nicht geladen. Für die Beispiel-Webseite gibt es eine eigene Datenbank. Soll es hier doch eine sein: einstellung betriebsmodus auf \"beispiel\" setzen." | **So soll es sein.** Der Schutz greift. |
| „Es gibt noch kein Benutzerkonto. Lege zuerst dein Betriebsleiter-Konto an (README, Schritt 7) …" | Es ist **noch gar kein Konto** in dieser Datenbank — Teil 3 Punkt 6 ist offen. Am Schutz ändert das nichts; hol den Punkt nach und wiederhole den Test. |
| Es werden Daten angelegt | `betriebsmodus` steht falsch. Zurück zu Teil 1, Punkt 7. |

> Der Schutz sitzt in der **Datenbank**, nicht in der App: als Auslöser an den
> Tabellen. Er greift also auch, wenn jemand die Zeilen von Hand einfügt oder
> eine spätere Fassung der App die Prüfung vergisst.

**3. Die Adressen auseinanderhalten.** Schreib dir beide auf:

```
echt:     https://kurbisverlust……………………workers.dev     ← QR-Code, Halle
Beispiel: https://kurbisverlust-beispiel………workers.dev     ← zum Zeigen
```

---

## Teil 6 — Bevor die erste echte Palette gezählt wird

In der **echten** App, als Betriebsleiter:

1. **Betrieb → Stammdaten → Paletten-Import**: das Erntejournal übernehmen, so
   weit es steht. Die Chargen selbst sind schon da.

2. **Betrieb → Stammdaten → Gebinde & Tara**: nachsehen, ob der Import eine
   Gebindeart mitgebracht hat, die es noch nicht gab. Die vier bekannten stehen
   schon drin (G2 1,500 kg; IFCO 6410 1,360 kg; IFCO 6416 1,680 kg; IFCO 6424
   2,000 kg, Palette je 25 kg). Eine neue Art steht mit **„Tara fehlt"** da und
   braucht ihr Leergewicht — sonst hat jede Palette in diesem Gebinde kein
   Nettogewicht. „Leer ist nicht null": Die Masse fehlt dann schlicht, sie wird
   nicht als 0 gerechnet.

3. **Betrieb → Stammdaten → Einstellungen**: `kisten_pro_palette` steht auf 36.
   Wenn bei euch 32 üblicher ist, hier ändern — es ist nur die Vorbelegung der
   Maske, gefragt wird trotzdem je Palette. Der geänderte Wert bleibt auch dann
   stehen, wenn du `setup.sql` später wieder einspielst.

4. **Betrieb → Zugang**: den QR-Code der **echten** Adresse ausdrucken und in
   der Halle aufhängen.

   > **Vor dem Aufhängen die Adresszeile auf dem Blatt lesen** und gegen die in
   > Teil 5 notierte echte Adresse halten. Das Band der Beispiel-Seite wird
   > **nicht** mitgedruckt; ein auf der Beispiel-Seite gedrucktes Blatt trägt
   > dafür einen eigenen Streifen „BEISPIEL — nicht der Betrieb. Dieses Blatt
   > gehört nicht in die Halle." Ist der Streifen da oder passt die Adresse
   > nicht, gehört das Blatt in den Papierkorb.

5. **Betrieb → Arbeiten**, Karte **Sicherung**: Sieh zuerst in Supabase unter
   **Database → Backups** nach, **was deine Stufe wirklich sichert** — auf der
   Gratis-Stufe sind das wenige Tage, und das reicht für einen Unfall, nicht
   für eine Saison. Wenn du eine eigene Kopie willst, steht der Weg in
   `docs/DATENERHEBUNG.md`, Abschnitt „Sicherung" (`pg_dump` mit der
   Verbindungszeichenfolge aus *Project Settings → Database*). Erst danach auf
   der Karte „Heute gesichert — vermerken" drücken; von da an erinnert sie
   dich.

---

## Was danach gilt

* **Die echte Datenbank wird nicht mehr geleert.** Was in der Halle gemessen
  wurde, lässt sich nicht noch einmal messen. Jede Änderung an einer
  Erfassungstabelle steht mit Vorher und Nachher im `erfassung_journal` — auch
  ein Löschen ist damit rückholbar.

* **Neue Programmstände in dieser Reihenfolge:** **erst** `setup.sql` in
  **beide** Datenbanken, **dann** **beide** Cloudflare-Projekte neu bauen.
  In dieser Richtung entsteht keine Lücke: Eine Datenbank, die neuer ist als
  die App, stört nicht. Andersherum schon — dann misst die Halle gegen eine
  Datenbank, die die neue App nicht kennt, und die Meldung „Die Datenbank steht
  auf Migration …, die App erwartet …" siehst du erst, wenn du selbst ins
  Dashboard gehst.

* **Vor jedem Einspielen von `setup.sql` in die echte Datenbank**: eine
  Sicherung ziehen. Die Datei erinnert dich daran: Auf einer scharfen Datenbank
  beginnt ihre Rückmeldung mit *ACHTUNG* — das ist gewollt, kein Fehler.

* **Was `setup.sql` auf einer scharfen Datenbank darf und was nicht**, steht
  in `docs/DATENERHEBUNG.md`, Abschnitt 4: Sichten und Funktionen (das ganze
  Rechenwerk) werden bei jedem Einspielen neu gebaut — das berührt keine
  erfasste Zeile. Tabellen und Spalten kommen nur dazu, nie weg; ein Wächter
  (`supabase/test/keine_zerstoerung.sh`) weist jede Migration ab, die etwas
  löschen würde, und läuft bei jedem Push.

* **Die Beispiel-Seite** darfst du behandeln, wie du willst: Demo neu laden,
  alles kaputtspielen, wieder laden. Dafür ist sie da — mit **einer**
  Ausnahme:

  > **Keine echten Warenausgangs-Dateien auf der Beispiel-Seite.** Die
  > Perigon-Auswertung enthält Kundennamen und Erlöse. Wird sie dort
  > hochgeladen, bleibt sie: „Demo-Daten entfernen" erkennt die Demo an
  > `quelle = 'DEMO'` und fasst importierte Zeilen einer echten Datei nicht an.
  > Zum Üben gibt es `test/daten/warenausgang-probe.xlsx` — erfunden, genau für
  > diesen Zweck gebaut. Echte Dateien gehören in die echte Datenbank.
