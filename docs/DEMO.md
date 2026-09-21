# Die Demo einrichten — Schritt für Schritt

**Was am Ende dasteht:** Auf deiner Webseite kommt unten auf der
Anmeldeseite ein Knopf **„Demo ansehen"** dazu. Wer ihn drückt, landet in
einer erfundenen Saison und darf dort alles anfassen. Deine echten Daten
liegen in einer anderen Datenbank und werden dabei nicht berührt.

**Was du brauchst:** einen Browser. Sonst nichts.

**Wie lange:** etwa 20 Minuten, davon 10 Minuten Warten.

**Was es kostet:** nichts.

Es sind 15 Schritte. Mach sie der Reihe nach. Nach jedem Schritt steht, was
du sehen musst — stimmt es nicht, geh nicht weiter, sondern schau unten bei
„Wenn etwas klemmt".

---

## Teil A — Ein zweites Supabase-Projekt anlegen

Du hast schon ein Supabase-Projekt: das mit den echten Daten. Jetzt kommt
ein zweites daneben. Die beiden wissen nichts voneinander — das ist der
ganze Trick.

### Schritt 1 — Bei Supabase anmelden

Geh auf **supabase.com** und melde dich an. Du landest auf einer Übersicht,
in der dein bestehendes Projekt steht.

### Schritt 2 — Neues Projekt anlegen

Klick auf **New project** (grüner Knopf, oben rechts).

Trag ein:

* **Name:** `kurbis-demo`
* **Database Password:** irgendein Passwort. Du brauchst es nie wieder.
  Schreib es trotzdem auf.
* **Region:** `Central EU (Frankfurt)`

Dann unten auf **Create new project**.

> **Du siehst:** eine Seite mit einem kreisenden Symbol und „Setting up
> project". Das dauert zwei bis fünf Minuten. Warte, bis oben links neben
> dem Projektnamen ein **grüner Punkt** steht.

### Schritt 3 — Merken, wo du bist

Oben links steht jetzt `kurbis-demo`. **Alles, was jetzt kommt, passiert in
diesem Projekt.** Wenn du zwischendurch unsicher bist: schau oben links
nach. Steht dort der Name deines echten Projekts, bist du falsch.

---

## Teil B — Die Datenbank einrichten

### Schritt 4 — Die Datei setup.sql holen

Öffne in einem **neuen Browser-Tab** diese Adresse:

```
https://raw.githubusercontent.com/konvalinaalexander-max/Kurbisverlust/claude/new-session-vrnnyo/supabase/setup.sql
```

Du siehst eine sehr lange Textwüste. Das ist richtig so.

Drück **Strg + A** (alles markieren), dann **Strg + C** (kopieren).

> **Auf dem Mac:** Cmd + A, dann Cmd + C.

### Schritt 5 — setup.sql ausführen

Zurück zum Supabase-Tab (`kurbis-demo`).

1. Links in der schmalen Leiste auf **SQL Editor**.
2. Auf **New query** oder das grosse `+`.
3. Klick in das leere weisse Feld und drück **Strg + V** (einfügen).
4. Unten rechts auf **Run** (oder Strg + Enter).

> **Du siehst:** nach etwa 30 Sekunden erscheint unten ein Ergebnis mit
> einer Zeile, die so anfängt: **„Fertig. Die Datenbank steht: 42 Chargen,
> 11 Sorten, …"**
>
> Kommt stattdessen eine rote Fehlermeldung: du hast beim Kopieren nicht
> alles erwischt. Schritt 4 nochmal, diesmal wirklich Strg + A zuerst.

### Schritt 6 — Der Datenbank sagen, dass sie die Demo ist

Das ist die wichtigste Zeile der ganzen Anleitung. Sie sorgt dafür, dass
diese Datenbank Beispieldaten annimmt — und deine echte weiterhin nicht.

1. Im SQL Editor wieder auf **New query**.
2. Das hier hineinkopieren:

```sql
update einstellung set wert = '"beispiel"'::jsonb
 where schluessel = 'betriebsmodus';
```

3. **Run**.

> **Du siehst:** unten links steht **Success. No rows returned**. Das ist
> richtig — die Zeile ändert etwas, sie fragt nichts ab.

### Schritt 7 — Anmelden ohne Konto freischalten

Die Demo hat kein Passwort. Jemand tippt einen Namen ein und ist drin. Damit
das geht, muss ein Schalter um.

1. Links auf **Authentication**.
2. Im Menü links auf **Sign In / Providers**.
3. Runterscrollen bis **Anonymous sign-ins**.
4. Den Schalter **einschalten** (er wird grün). Falls eine Rückfrage kommt:
   bestätigen.

> **Du siehst:** der Schalter steht auf grün / „Enabled".
>
> Ohne diesen Schritt kommt später niemand in die Demo hinein, und die App
> sagt „Zugang ohne Konto noch nicht freigeschaltet".

---

## Teil C — Die zwei Zugangswerte abholen

Die Webseite muss zwei Dinge über die neue Datenbank wissen: **wo** sie
steht und **womit** sie sich melden darf. Beides holst du jetzt.

Nimm dir einen leeren Notizzettel (oder ein Textfeld). Da kommen zwei Werte
hinein.

### Schritt 8 — Wert 1: die Adresse

Du brauchst eine Adresse in genau dieser Form:

```
https://EINEZWANZIGSTELLIGEBUCHSTABENFOLGE.supabase.co
```

Die Buchstabenfolge steht **in der Adresszeile deines Browsers**, genau
jetzt, während du im Projekt `kurbis-demo` bist. Dort steht etwas wie:

```
https://supabase.com/dashboard/project/qmhxkfyowwvsumcwssxe/auth/providers
                                       └──── das brauchst du ────┘
```

Nimm das Stück zwischen `/project/` und dem nächsten Schrägstrich und bau
daraus:

```
https://qmhxkfyowwvsumcwssxe.supabase.co
```

Das schreibst du auf den Notizzettel als **Wert 1**.

> **Wichtig, zwei Fallen:**
>
> * **Nicht** `https://supabase.com/dashboard/…` nehmen. Das ist die
>   Verwaltungsoberfläche, nicht die Datenbank.
> * Findest du woanders eine Adresse, die auf **`/rest/v1/`** endet, ist das
>   dieselbe Adresse mit einem Pfad dran. Lösch den Pfad weg:
>
>   ```
>   https://qmhxkfyowwvsumcwssxe.supabase.co/rest/v1/   ← so steht es da
>   https://qmhxkfyowwvsumcwssxe.supabase.co            ← so gehört es hin
>   ```
>
>   Alles bis `.supabase.co`, kein Schrägstrich am Ende.

### Schritt 9 — Wert 2: der Schlüssel

1. Ganz unten links auf das **Zahnrad** (*Project Settings*).
2. Im Menü links unter *CONFIGURATION* auf **API Keys**.
3. Jetzt gibt es zwei Möglichkeiten, und **beide sind richtig**:

   **Fall A — du siehst einen Abschnitt „Publishable key".**
   Darin eine Zeile `default` mit einem Schlüssel, der mit
   `sb_publishable_` anfängt. Rechts davon ein Kopier-Symbol (zwei
   übereinanderliegende Rechtecke). Draufklicken.

   **Fall B — du siehst keinen.** Völlig normal bei älteren Projekten.
   Klick oben auf den Reiter **`Legacy anon, service_role API keys`** (oder,
   falls die Seite bei dir schlicht **API** heisst, schau in der Liste
   `Project API keys` nach). Nimm dort die Zeile mit der Beschriftung
   **`anon`** **`public`**. Der Schlüssel ist sehr lang und fängt mit `eyJ`
   an. Kopier-Symbol daneben, draufklicken.

Das ist **Wert 2** für deinen Notizzettel.

> **Die App nimmt beide Sorten.** Sie prüft nur, dass es nicht der geheime
> ist.
>
> **Finger weg** von allem, wo **`secret`** oder **`service_role`** steht.
> Solche Schlüssel umgehen sämtliche Schutzregeln und gehören nie in eine
> Webseite. Erkennungszeichen für die richtigen: Supabase schreibt daneben
> „can be safely shared publicly".

### Schritt 10 — Kurz gegenprüfen

Schau auf deinen Notizzettel. Wert 1 muss die Kennung des **neuen**
Projekts enthalten. Wenn du gleich bei Cloudflare bist, siehst du dort den
Wert `VITE_SUPABASE_URL` stehen — das ist dein **echtes** Projekt. Die
beiden Kennungen müssen **verschieden** sein.

Sind sie gleich, warst du im falschen Projekt. Dann Schritt 3 nochmal.

---

## Teil D — Der Webseite die Demo beibringen

### Schritt 11 — Die zwei Werte bei Cloudflare eintragen

1. Geh auf **dash.cloudflare.com** und öffne das Projekt, unter dem deine
   Webseite läuft (`kurbisverlust`).
2. **Settings** → **Environment variables** (oder *Variables and Secrets*).
3. **Add variable**, und zwar zweimal:

   | Variable name | Value |
   |---|---|
   | `VITE_DEMO_SUPABASE_URL` | Wert 1 vom Notizzettel |
   | `VITE_DEMO_SUPABASE_ANON_KEY` | Wert 2 vom Notizzettel |

4. Als Typ **Text** wählen, **nicht** *Secret*. (Grund: der Wert muss beim
   Bauen der Seite eingesetzt werden, und an Secrets kommt der Bauvorgang
   nicht heran. Geheim ist er ohnehin nicht.)
5. **Save**.

> **Die Namen müssen exakt stimmen**, mit `DEMO` in der Mitte. Schreib sie
> ab, tipp sie nicht frei.

### Schritt 12 — Neu veröffentlichen

Das Eintragen allein bewirkt nichts. Die Werte kommen beim **Bauen** in die
Seite.

1. Links auf **Deployments**.
2. Beim **obersten** Eintrag rechts auf das Menü **⋯**.
3. **Retry deployment**.
4. Ein bis zwei Minuten warten, bis der Eintrag auf **Success** steht.

### Schritt 13 — Nachschauen

Öffne deine Webseite und drück **F5** (Seite neu laden).

> **Du siehst:** unten auf der Anmeldeseite, unter dem Betriebsleiter-Login,
> steht jetzt in kleiner Schrift:
> **„Demo ansehen — erfundene Saison, nichts davon ist der Betrieb"**.
>
> Steht da nichts, siehe unten „Wenn etwas klemmt".

---

## Teil E — Die Demo-Saison hineinlegen

Dieser Teil geht ohne SQL. Einfach klicken.

### Schritt 14 — In die Demo gehen

1. **„Demo ansehen"** drücken. Die Seite lädt neu.
2. Jetzt siehst du oben ein **gelbes Band** und darunter „Kürbis-Verlust ·
   Demo".
3. Ein Name steht schon da (`Gast`). Drück **Demo starten**.

> **Du siehst:** die App, wie du sie kennst — aber leer, und mit dem gelben
> Band oben. Du bist als Betriebsleiter drin.

### Schritt 15 — Die Saison laden

Auf dem leeren Lagermanagement steht eine Karte **„Erst mal anschauen, wie
es aussieht"**. Darin ein Knopf **„Demo-Saison laden"**. Drück ihn.

> **Du siehst:** nach ein, zwei Sekunden eine Meldung „Demo-Saison steht:
> 951 Paletten in 42 Chargen, 377 Arbeiten …". Danach rechnet die App etwa
> zehn Sekunden.

**Fertig.** Lade die Seite einmal neu — jetzt ist jeder Bildschirm gefüllt:
362 Tonnen Eingang, das Lager nach Kaliber, die Verlustursachen, die
Lagerkontrollen, die Arbeiter-Masken.

---

## Teil F — Was du damit jetzt tun kannst

**Herumklicken und ausprobieren.** Alles ist erfunden. Eröffne Arbeiten,
wiege, zähle, schliess ab. Es wird mitgerechnet wie im Echtbetrieb.

**Beide Seiten anschauen.** Oben links auf den Kürbis → du bist in der
Halle (Arbeiter). Über die Reiter links → du bist im Büro
(Betriebsleiter). In der Demo darfst du beides.

**Jemandem zeigen.** Schick ihm einfach deine normale Adresse. Er drückt
„Demo ansehen" und ist drin — ohne Konto, ohne Passwort.

**Aufräumen, wenn jemand Unsinn hineingetippt hat.** Oben im gelben Band:
**„Demo zurücksetzen"** → Rückfrage → die Saison wird neu aufgebaut,
identisch zum ersten Tag.

**Wieder raus.** Oben im gelben Band: **„Demo verlassen"**.

---

## Wenn etwas klemmt

**„Demo ansehen" steht nicht auf der Anmeldeseite.**
Entweder fehlt einer der beiden Werte bei Cloudflare, oder einer ist leer,
oder Schritt 12 (Retry deployment) wurde vergessen. Prüf die Schreibweise
der Namen — `VITE_DEMO_SUPABASE_URL` und `VITE_DEMO_SUPABASE_ANON_KEY`.

**„In der Demo-Datenbank ist der Zugang ohne Konto noch nicht freigeschaltet."**
Schritt 7 fehlt oder wurde im falschen Projekt gemacht.

**„Die Datenbank steht auf 0080, die App erwartet 0081."**
Im Demo-Projekt fehlt die aktuelle `setup.sql`. Schritt 4 und 5 wiederholen.
Die Datei darf beliebig oft laufen und nimmt nichts weg.

**„Diese Datenbank läuft im Echtmodus …" beim Laden der Demo-Saison.**
Schritt 6 fehlt oder wurde im falschen Projekt gemacht.

**„Invalid API key" oder „Die Zugangsdaten stimmen nicht."**
Der Schlüssel gehört zum anderen Projekt, oder beim Kopieren wurde nur ein
Teil erwischt. Nimm das Kopier-Symbol, nicht die Maus.

**„Die Project URL sieht nicht richtig aus."**
Bei Wert 1 hängt ein Pfad dran (`/rest/v1/`) oder es ist die
`supabase.com/dashboard/…`-Adresse. Siehe Schritt 8.

**Es kommt nur eine Netzwerk-Fehlermeldung.**
Das Demo-Projekt wurde nach sieben ruhigen Tagen pausiert — das macht
Supabase auf der Gratis-Stufe automatisch. Projekt im Supabase-Dashboard
öffnen, **Restore** drücken, ein bis zwei Minuten warten. Wenn du jemandem
etwas zeigen willst: weck die Demo am Tag davor auf.

**Die Demo zeigt die echten Daten des Betriebs.**
Beide Werte zeigen auf das alte Projekt. Schritt 8 bis 12 nochmal, diesmal
im Projekt `kurbis-demo`.

**Supabase lässt kein drittes Projekt zu.**
Die Gratis-Stufe erlaubt zwei aktive Projekte. Hast du früher schon eine
eigene Beispiel-Webseite aufgesetzt, nimm jenes Projekt als Demo-Projekt
und überspring Teil A.

---

## Zum Schluss: wenn du die Demo öffentlich zeigst

Die Chargen tragen die **echten Schlagnamen** deiner Anbauplanung, und
einige davon sind Namen von Produzenten. Für dich intern ist das richtig
so; für ein Publikum vielleicht nicht.

Wenn du sie neutral haben willst, führ **im Demo-Projekt** (nur dort!) im
SQL Editor das hier aus:

```sql
-- Nur im Demo-Projekt ausführen. In der echten Datenbank niemals.
update charge c set schlag = 'Feld ' || t.n
  from (select schlag, row_number() over (order by schlag) as n
          from (select distinct schlag from charge) s) t
 where t.schlag = c.schlag;
```

Aus „Illnau Gross" wird dann „Feld 7". Die Abnehmer der Demo sind ohnehin
erfunden — *Nordmarkt Genossenschaft*, *Talhof Bio AG*, *Grünwerk Handel*,
*Feldfrisch Ost*. Kein Kunde des Betriebs steht in der Demo.

---

## Warum das sicher ist

* **Die echte Datenbank kann keine Demo-Daten bekommen.** Sie steht auf
  `betriebsmodus = 'echt'`, und dann weisen die Tabellen selbst jede
  Beispielzeile ab — als Regel in der Datenbank, nicht als Prüfung in der
  App. Selbst wer die Funktion von Hand im SQL-Editor aufruft, kommt nicht
  durch.
* **Die Demo kann nicht in die echte Datenbank schreiben.** Sie kennt deren
  Adresse nicht. Die Verbindung wird beim Laden der Seite einmal gewählt und
  danach nicht mehr gewechselt.
* **Man sieht immer, wo man ist.** In der Demo steht auf jedem Bildschirm
  oben das gelbe Band. Es lässt sich nicht wegklicken.
* **Der Löschknopf des Betriebs ist woanders.** „Alles löschen" steht in den
  Stammdaten und betrifft immer nur die Datenbank, in der man gerade ist.
