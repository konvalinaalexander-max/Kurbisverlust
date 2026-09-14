# Zwei Webseiten: eine für den Betrieb, eine zum Ausprobieren

Ab jetzt laufen **zwei getrennte Aufbauten** nebeneinander:

| | **Echt** | **Beispiel** |
|---|---|---|
| wofür | die Halle, ab morgen | ausprobieren, zeigen, üben |
| Daten | echte Messungen, werden nie gelöscht | eine erfundene Saison, jederzeit neu ladbar |
| Supabase-Projekt | ein **neues**, leeres | das **bestehende** mit der Demo |
| Cloudflare-Worker | `kurbisverlust` (die Adresse, die du kennst) | `kurbisverlust-beispiel` |
| `einstellung.betriebsmodus` | `echt` | `beispiel` |
| Demo-Daten laden | die Datenbank weist es ab | geht mit einem Knopf |

**Warum zwei und nicht ein Schalter.** Weil sonst genau der Fehler passiert, den
niemand mehr rückgängig macht: Eine erfundene Palette landet zwischen echten
Messungen, und nachher weiss keiner mehr, welche Zahl gemessen und welche
erfunden war.

**Warum das neue Projekt das echte wird und nicht umgekehrt.** Die echte
Datenbank soll nie eine Demo-Zeile gesehen haben. „Demo-Daten entfernen" räumt
zuverlässig auf — aber ein Projekt, das nie eine Demo hatte, braucht gar nicht
aufzuräumen. Ein Supabase-Projekt kostet nichts; die Vorsicht auch nicht.

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
* die Datei **`supabase/setup.sql`** aus diesem Projekt (der aktuelle Stand,
  Migration 0077)

Rechne mit **einer guten halben Stunde**. Die Wartezeiten sind Build-Zeiten,
nichts davon ist knifflig.

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

**Was du siehst**

Genau **eine** Zeile, keine weiteren Meldungen:

```
Fertig. Die Datenbank steht: 42 Chargen, 11 Sorten, 31 Tabellen,
72 Auswertungen. …
```

Die 42 Chargen sind deine echten Chargen aus der Anbauplanung — die stehen fest
im Programm, das sind keine Demo-Daten.

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

8. Die zwei Zugangswerte abholen (README Schritt 5): **Project URL** und der
   Schlüssel, der mit `sb_publishable_…` anfängt. Beide irgendwo zwischenlegen,
   du brauchst sie in Teil 3.

9. **Die Datenbank als scharf markieren.** Im SQL-Editor:

```sql
update einstellung
   set wert = to_jsonb(true)
 where schluessel = 'erfassung_scharf';
```

   Das ändert an der Erfassung nichts — es ist eine Markierung. Aber von jetzt
   an sagt jedes spätere Einspielen von `setup.sql` in **dieser** Datenbank
   als Erstes: *„ACHTUNG: Auf dieser Datenbank liegen echte Erfassungsdaten"*,
   und die Betriebsseite in der App zeigt den Hinweis zur Sicherung. Wer in
   einem halben Jahr die Datei in das falsche Projekt einfügt, sieht es in der
   ersten Zeile.

---

## Teil 2 — Das bestehende Projekt zur Beispiel-Datenbank machen

Das ist die Datenbank, in der die Demo-Saison schon liegt.

**Was du machst**

1. Im **bestehenden** Supabase-Projekt → **SQL Editor** → **New query**.
2. Erst `supabase/setup.sql` einspielen, damit auch diese Datenbank auf dem
   neuen Stand ist. Deine Daten bleiben dabei erhalten.
3. Dann in einer neuen Abfrage den Modus umstellen:

```sql
update einstellung
   set wert = to_jsonb('beispiel'::text)
 where schluessel = 'betriebsmodus';
```

4. Nachschauen, ob es angekommen ist:

```sql
select wert from einstellung where schluessel = 'betriebsmodus';
```

**Woran du merkst, dass es geklappt hat:** dort steht `"beispiel"`.

`erfassung_scharf` lässt du hier auf `false` — das ist die Datenbank, in der
Aufräumen erlaubt ist.

> Der Wert bleibt so, auch wenn du `setup.sql` später wieder einspielst — die
> Datei setzt ihn nur, wenn er noch gar nicht da ist.

---

## Teil 3 — Die echte Webseite

Hier stellst du die **bestehende** Veröffentlichung auf die **neue** Datenbank
um. Die Adresse bleibt dieselbe.

**Was du machst**

1. Auf https://dash.cloudflare.com → **Workers & Pages** → dein Projekt
   **`kurbisverlust`**.
2. Reiter **Settings** → **Variables and Secrets**.
3. Die zwei Werte auf das **neue** Projekt aus Teil 1 ändern:

   | Variable | neuer Wert |
   |---|---|
   | `VITE_SUPABASE_URL` | die Project URL von `kuerbis-echt` |
   | `VITE_SUPABASE_ANON_KEY` | der `sb_publishable_…`-Schlüssel von `kuerbis-echt` |

   Beim Einfügen darf kein Leerzeichen und kein Zeilenumbruch mitkommen.

4. **Speichern.**
5. **Zwingend:** Reiter **Deployments** → beim obersten Eintrag rechts das Menü
   **⋯** → **Retry deployment**.

> **Warum der zweite Schritt sein muss:** Die zwei Werte kommen beim **Bauen**
> fest in die Seite. Ohne neuen Build zeigt die Adresse weiter auf die alte
> Datenbank — egal was in den Einstellungen steht.

**Woran du merkst, dass es geklappt hat**

Öffne die Adresse und melde dich als Betriebsleiter an. Du siehst:

* **kein oranges Band** am oberen Rand,
* unter **Betrieb → Stammdaten → Demo-Daten** stehen **keine Knöpfe**, sondern
  der Satz „Diese Datenbank läuft im Echtmodus…",
* der **Überblick** ist leer — das ist richtig so, es ist noch nichts erfasst.

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

4. Bei **Variables and Secrets** die zwei Werte des **bestehenden** (Demo-)
   Projekts eintragen — dieselben, die bisher bei `kurbisverlust` standen:

   | Variable | Wert |
   |---|---|
   | `VITE_SUPABASE_URL` | Project URL der Demo-Datenbank |
   | `VITE_SUPABASE_ANON_KEY` | deren `sb_publishable_…`-Schlüssel |

5. **Deploy**. Ein bis drei Minuten.

**Woran du merkst, dass es geklappt hat**

Du bekommst eine zweite Adresse, etwa
`https://kurbisverlust-beispiel.<etwas>.workers.dev`. Öffne sie:

* oben läuft ein **oranges Band: „Beispieldaten — nicht der Betrieb"**,
* unter **Betrieb → Stammdaten → Demo-Daten** stehen die Knöpfe,
* alle Zahlen sind da wie bisher.

---

## Teil 5 — Die Probe aufs Exempel

Drei Minuten, und du weisst, dass die Trennung wirklich hält.

**1. Das Band.** Echte Seite: kein Band. Beispiel-Seite: oranges Band. Das ist
der Unterschied, den jeder in der Halle auf einen Blick sieht.

**2. Der harte Test.** Im SQL-Editor der **echten** Datenbank:

```sql
select demo_daten_laden();
```

Das **muss** mit dieser Meldung abbrechen:

```
Diese Datenbank läuft im Echtmodus — Beispieldaten werden nicht geladen.
Für die Beispiel-Webseite gibt es eine eigene Datenbank.
```

Wenn stattdessen Daten angelegt werden, steht `betriebsmodus` falsch — zurück
zu Teil 1, Punkt 7.

> Der Schutz sitzt in der **Datenbank**, nicht in der App. Er greift also auch,
> wenn jemand die Zeilen von Hand einfügt oder eine spätere Fassung der App die
> Prüfung vergisst.

**3. Die Adressen auseinanderhalten.** Schreib dir beide auf:

```
echt:     https://kurbisverlust……………………workers.dev     ← QR-Code, Halle
Beispiel: https://kurbisverlust-beispiel………workers.dev     ← zum Zeigen
```

---

## Teil 6 — Bevor die erste echte Palette gezählt wird

In der **echten** App, als Betriebsleiter:

1. **Betrieb → Stammdaten → Gebinde & Tara**: die Leergewichte prüfen. Ohne sie
   hat keine Palette ein Nettogewicht — „leer ist nicht null" heisst dann, dass
   die Masse schlicht fehlt.
2. **Betrieb → Stammdaten → Einstellungen**: `kisten_pro_palette` steht auf 36.
   Wenn bei euch 32 üblicher ist, hier ändern — es ist nur die Vorbelegung der
   Maske, gefragt wird trotzdem je Palette.
3. **Betrieb → Stammdaten → Paletten-Import**: das Erntejournal übernehmen, so
   weit es steht. Die Chargen selbst sind schon da.
4. **Betrieb → Zugang**: den QR-Code der **echten** Adresse ausdrucken und in
   der Halle aufhängen.
5. **Betrieb → Arbeiten**: auf der Karte **Sicherung** einmal „Heute gesichert —
   vermerken" drücken, nachdem du in Supabase unter **Database → Backups**
   nachgesehen hast. Von da an erinnert dich die Karte.

---

## Was danach gilt

* **Die echte Datenbank wird nicht mehr geleert.** Was in der Halle gemessen
  wurde, lässt sich nicht noch einmal messen. Jede Änderung an einer
  Erfassungstabelle steht mit Vorher und Nachher im `erfassung_journal` — auch
  ein Löschen ist damit rückholbar.
* **Neue Programmstände** spielst du in **beide** Datenbanken ein (dieselbe
  `setup.sql`, Daten bleiben) und baust **beide** Cloudflare-Projekte neu. Wenn
  du nur eines machst, laufen die zwei Seiten auseinander; die App sagt es dir
  dann selbst („Die Datenbank steht auf Migration …, die App erwartet …").
* **Vor jedem Einspielen von `setup.sql` in die echte Datenbank**: eine
  Sicherung ziehen. Supabase sichert zwar täglich von selbst, aber ein paar
  Sekunden Vorsicht kosten nichts. Die Datei selbst erinnert dich daran: Auf
  einer scharfen Datenbank beginnt ihre Rückmeldung mit *ACHTUNG* und gibt
  eine Warnung aus — das ist gewollt, kein Fehler.
* **Was `setup.sql` auf einer scharfen Datenbank darf und was nicht**, steht
  in `docs/DATENERHEBUNG.md`, Abschnitt 4: Sichten und Funktionen (das ganze
  Rechenwerk) werden bei jedem Einspielen neu gebaut — das berührt keine
  erfasste Zeile. Tabellen und Spalten kommen nur dazu, nie weg; ein Wächter
  (`supabase/test/keine_zerstoerung.sh`) weist jede Migration ab, die etwas
  löschen würde, und läuft bei jedem Push.
* **Die Beispiel-Seite** darfst du behandeln, wie du willst: Demo neu laden,
  alles kaputtspielen, wieder laden. Dafür ist sie da.
