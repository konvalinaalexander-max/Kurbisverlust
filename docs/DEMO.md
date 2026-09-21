# Die Demo: ein Knopf vor dem Login

**Was am Ende dasteht:** Deine Webseite bleibt genau eine Webseite. Wer sich
anmeldet — als Arbeiter mit Namen oder als Betriebsleiter mit E-Mail —
arbeitet mit den echten Daten des Betriebs. Wer vorher unten auf der
Anmeldeseite auf **„Demo ansehen"** drückt, landet in einer erfundenen
Saison: gut 950 Paletten Eingang, rund 370 Arbeiten, Lieferungen,
Lagerkontrollen, ein volles Dashboard. Dort darf er alles anfassen — Arbeiten
eröffnen, wiegen, zählen, abschliessen — und alles wird mitgerechnet.

**Warum eine zweite Datenbank sein muss:** Weil „anfassen dürfen" sonst heisst
„in die echten Zahlen schreiben". Eine Demo, die in dieselbe Datenbank
schreibt, ist keine Demo, sondern genau die Verschmutzung, die der Löschknopf
gerade beseitigt hat. Die zweite Datenbank kostet nichts (Gratis-Stufe wie die
erste) und ist hart getrennt: zwei Projekte, zwei Adressen, zwei Schlüssel.
Die App baut ihre Verbindung beim Laden der Seite auf und redet danach mit
genau einer von beiden.

**Zeit:** rund 20 Minuten, davon zehn Warten.

**Zwei Dinge, die du über die Gratis-Stufe wissen musst:**

* Sie erlaubt **zwei aktive Projekte** pro Organisation. Das echte und das
  Demo-Projekt sind genau zwei. Wenn du früher schon eine eigene
  Beispiel-Webseite nach [ZWEI_WEBSEITEN.md](ZWEI_WEBSEITEN.md) aufgesetzt
  hast, wäre das dritte eines zu viel — dann nimm jenes Projekt als
  Demo-Projekt und überspring Teil 1.
* Ein Projekt, das **sieben Tage** nichts zu tun hatte, wird pausiert. Das
  echte trifft das nie (dort wird gearbeitet); das Demo-Projekt schon. Beim
  ersten Klick nach einer langen Pause kommt dann eine Netzwerk-Fehlermeldung.
  Aufwecken: im Supabase-Dashboard das Projekt öffnen und **Restore**
  drücken, ein bis zwei Minuten warten. Wenn du jemandem etwas zeigen
  willst, weck die Demo lieber am Tag davor auf.

---

## Was du am Ende hast

| | Die echte Seite | Die Demo dahinter |
|---|---|---|
| Adresse | dieselbe | dieselbe |
| Datenbank | dein bisheriges Supabase-Projekt | ein zweites, neues |
| Hinein kommt man | Anmelden (Name oder E-Mail) | Knopf „Demo ansehen" |
| Oben steht | nichts Besonderes | gelbes Band „Demo — erfundene Daten" |
| Daten | die des Betriebs | eine erfundene Saison |
| Wer darf was | Arbeiter sehen die Halle, Betriebsleiter das Büro | jeder sieht beides |
| Zurücksetzen | der Knopf „Alles löschen" in den Stammdaten | der Knopf im gelben Band |

---

## Teil 1 — Das zweite Supabase-Projekt anlegen

1. [supabase.com](https://supabase.com) öffnen, anmelden, **New project**.
2. Name: etwas, das du wiedererkennst — zum Beispiel `kurbis-demo`.
   Region: **Frankfurt (eu-central-1)** wie beim ersten.
   Datenbank-Passwort: irgendeines, du brauchst es nicht wieder. Trotzdem
   aufschreiben.
3. **Create new project** und ein paar Minuten warten, bis oben links der
   grüne Punkt steht.

> Verwechsle die beiden Projekte nicht. Das neue ist die Spielwiese. Im
> alten liegen die echten Zahlen. Wenn du unsicher bist, welches du gerade
> vor dir hast: oben links steht der Projektname.

---

## Teil 2 — Die Datenbank einrichten

Alles in diesem Teil passiert im **neuen** Projekt.

1. Links auf **SQL Editor**, dann **New query**.
2. Aus dem Code die Datei `supabase/setup.sql` öffnen, **alles** markieren,
   kopieren, ins leere Fenster einfügen, **Run**.
   Nach etwa einer halben Minute steht unten eine Zeile, die mit
   *„Fertig. Die Datenbank steht: …"* beginnt und Chargen, Sorten, Tabellen
   und Auswertungen zählt.
3. Ein zweites Query aufmachen und diese zwei Zeilen ausführen:

```sql
update einstellung set wert = '"beispiel"'::jsonb
 where schluessel = 'betriebsmodus';
```

   Damit sagt die Datenbank selbst, dass sie eine Beispieldatenbank ist.
   Daran hängt zweierlei: das gelbe Band oben, und die Erlaubnis, überhaupt
   Beispieldaten zu laden. In der Datenbank des Betriebs steht `echt`, und
   dort werden Beispieldaten nicht nur versteckt, sondern von der Datenbank
   selbst abgewiesen (Migration 0072).

4. Links auf **Authentication → Sign In / Providers**, ganz unten
   **Anonymous sign-ins** einschalten. Ohne das kommt niemand in die Demo
   hinein: sie hat kein Passwort und kein Konto, nur einen Namen.

5. Ebenfalls unter **Authentication → Sign In / Providers → Email**: den
   Haken bei **Confirm email** herausnehmen. (Nur nötig, wenn du dir in der
   Demo später ein E-Mail-Konto anlegen willst. Für den Demo-Knopf nicht.)

---

## Teil 3 — Die zwei Zugangswerte abholen

Im **neuen** Projekt: links **Settings → API** (in neueren Fassungen
**Settings → Data API**).

Du brauchst zwei Dinge:

* **Project URL** — sieht aus wie `https://abcdefgh.supabase.co`
* **Publishable key** (im Reiter *Legacy*: der mit der Beschriftung
  **anon public**) — beginnt mit `sb_publishable_` oder mit `eyJ`

> **Niemals** den Schlüssel mit der Beschriftung *secret* oder
> *service_role*. Der umgeht alle Zugriffsregeln. Die App prüft das beim
> Start und weigert sich mit einer deutlichen Meldung — verlass dich aber
> nicht darauf.

Schreib beide Werte auf. Im nächsten Teil werden sie gebraucht.

---

## Teil 4 — Der Webseite die Demo beibringen

Bei **Cloudflare**, in dem Projekt, das deine Webseite ausliefert:

1. **Settings → Environment variables → Add variable**, zweimal:

   | Name | Wert |
   |---|---|
   | `VITE_DEMO_SUPABASE_URL` | die Project URL aus Teil 3 |
   | `VITE_DEMO_SUPABASE_ANON_KEY` | der Publishable key aus Teil 3 |

   Als Typ **Text** wählen, nicht *Secret*: Der Wert muss beim Bauen in die
   Seite eingesetzt werden, und Secrets stehen dem Bauvorgang nicht zur
   Verfügung. Öffentlich ist er ohnehin — er steckt in jeder ausgelieferten
   Seite und kann nur das, was die Zugriffsregeln erlauben.

2. **Deployments → beim obersten Eintrag das Menü ⋯ → Retry deployment.**
   Ohne diesen Schritt ändert sich nichts: Die Werte kommen beim *Bauen* in
   die Seite, nicht beim Laden.

3. Nach ein bis zwei Minuten die Webseite neu laden (F5). Unten auf der
   Anmeldeseite steht jetzt **„Demo ansehen — erfundene Saison, nichts davon
   ist der Betrieb"**.

Fehlen die beiden Werte oder ist einer leer, erscheint der Knopf nicht. Das
ist Absicht: Ein Knopf, der beim Drücken eine Fehlermeldung zeigt, ist
schlimmer als keiner.

---

## Teil 5 — Die Saison hineinlegen

Jetzt kommt der schönste Teil, weil er ohne SQL geht:

1. Auf der Anmeldeseite **„Demo ansehen"** drücken. Die Seite lädt neu und
   zeigt den Demo-Eingang.
2. Einen Namen eintippen (`Gast` steht schon da) und **Demo starten**.
3. Du bist drin — und zwar als Betriebsleiter. Das macht die Datenbank so,
   weil sie eine Beispieldatenbank ist; in der Datenbank des Betriebs bleibt
   ein anonymer Zugang ein Arbeiter.
4. Das Dashboard ist noch leer und bietet eine Karte **„Erst mal anschauen,
   wie es aussieht"** an. Darin: **Demo-Saison laden**. Das dauert eine
   Sekunde, danach rechnet die App die Auswertung in fünf Schritten durch
   (etwa zehn Sekunden).

Fertig. Ab jetzt zeigt die Demo eine volle Saison.

> **Lieber über den SQL-Editor?** Geht auch — aber erst, nachdem sich
> mindestens einmal jemand angemeldet hat (die Saison braucht einen
> Erfasser):
> ```sql
> select demo_daten_laden();
> select auswertung_aktualisieren();
> ```

---

## Teil 6 — Aufräumen, wenn andere darin gespielt haben

In der Demo darf jeder alles. Nach ein paar Besuchern steht dort Unsinn:
halbe Arbeiten, vertippte Gewichte, drei angefangene Waschgänge.

Oben im gelben Band steht **„Demo zurücksetzen"**. Ein Druck, eine
Rückfrage, und die Saison wird neu aufgebaut — dieselbe wie am ersten Tag.
Sie ist reproduzierbar: gleiche Chargen, gleiche Paletten, gleiche Zahlen.
Nur die Tage wandern mit, damit die Demo nicht altert.

Daneben steht **„Demo verlassen"** — zurück zur Anmeldung des Betriebs.

---

## Wenn du die Demo öffentlich zeigst

Die Chargen im Stammdatenregister tragen die **echten Schlagnamen** deiner
Anbauplanung, und einige davon sind Namen von Produzenten. Für dich intern
ist das richtig so. Wenn du die Demo jemandem zeigst, der das nicht sehen
soll, ersetze sie in der **Demo-Datenbank** (nur dort!) durch neutrale:

```sql
-- Nur im Demo-Projekt ausführen. In der echten Datenbank niemals.
update charge c set schlag = 'Feld ' || t.n
  from (select schlag, row_number() over (order by schlag) as n
          from (select distinct schlag from charge) s) t
 where t.schlag = c.schlag;
```

Die Abnehmer der Demo sind ohnehin erfunden — *Nordmarkt Genossenschaft*,
*Talhof Bio AG*, *Grünwerk Handel*, *Feldfrisch Ost*. Kein Kunde des
Betriebs steht in der Demo.

---

## Was sicher ist, und woran man es sieht

* **Die echte Datenbank kann keine Demo-Daten bekommen.** Sie steht auf
  `betriebsmodus = 'echt'`, und dann weisen die Tabellen selbst jede
  Beispielzeile ab — als Auslöser in der Datenbank, nicht als Prüfung in der
  App (0072). Selbst wer die Funktion von Hand im SQL-Editor aufruft, kommt
  nicht durch.
* **Die Demo kann nicht in die echte Datenbank schreiben.** Sie kennt deren
  Adresse nicht. Im Browser steht ein Merkzettel, welche der beiden gilt; die
  Verbindung wird beim Laden der Seite einmal aufgebaut und danach nicht mehr
  gewechselt.
* **Man sieht immer, wo man ist.** In der Demo steht auf jedem Bildschirm
  oben das gelbe Band. Es lässt sich nicht wegklicken.
* **Der Löschknopf des Betriebs ist woanders.** „Alles löschen" steht in den
  Stammdaten und betrifft immer nur die Datenbank, in der man gerade ist.

---

## Wenn etwas klemmt

**„Demo ansehen" erscheint nicht.**
Die beiden `VITE_DEMO_…`-Werte fehlen, sind leer, oder das Deployment wurde
nach dem Eintragen nicht wiederholt. Cloudflare → Deployments → ⋯ → Retry
deployment.

**„In der Demo-Datenbank ist der Zugang ohne Konto noch nicht freigeschaltet."**
Teil 2, Schritt 4: Anonymous sign-ins im *neuen* Projekt einschalten.

**„Die Datenbank steht auf 0080, die App erwartet 0081."**
Im Demo-Projekt fehlt die aktuelle `setup.sql`. Teil 2, Schritt 2 wiederholen —
sie darf beliebig oft laufen und nimmt nichts weg.

**„Diese Datenbank läuft im Echtmodus …" beim Laden der Demo-Saison.**
Teil 2, Schritt 3 wurde übersprungen oder im falschen Projekt ausgeführt.

**Invalid API key.**
Der Schlüssel gehört zum anderen Projekt, oder beim Kopieren wurde nur ein
Teil erwischt. Neben dem Schlüssel steht in Supabase ein Kopier-Symbol.

**Es kommt eine Netzwerk-Fehlermeldung, sonst nichts.**
Wahrscheinlich ist das Demo-Projekt nach sieben ruhigen Tagen pausiert. Im
Supabase-Dashboard öffnen und **Restore** drücken.

**Die Demo zeigt die Daten des Betriebs.**
Dann zeigen beide `VITE_DEMO_…`-Werte auf das alte Projekt. Teil 3 und 4
nochmals, diesmal im neuen Projekt.
