# Kürbis-Verlust-Tracking

Internes Werkzeug für einen landwirtschaftlichen Betrieb: Es findet heraus,
**wo** im Lager und in der Verarbeitung Kürbis-Masse verloren geht und **welche
Ursache dominiert** — aus bewusst lückenhaften, punktuellen Messungen.

Ziel ist das **Rangieren der Ursachen**, keine kg-genaue Bilanz. Jede Zahl im
Dashboard lässt sich aufklappen und zeigt, aus welchen Stichproben, welchem
Koeffizienten und welcher Formel sie entstanden ist.

Kosten: **€0** auf den Gratis-Stufen von Supabase und Cloudflare.

---

# Teil 1 — Einrichtung

Einmalig, danach nie wieder. Rechne mit **30 bis 45 Minuten**, davon sind zehn
reines Warten.

Du brauchst nur einen Browser. Nichts installieren, nichts programmieren.

| Schritt | Worum es geht | Dauer |
|---|---|---|
| 1 | Kurz zur Orientierung (nichts zu tun) | 1 Min |
| 2 | Supabase-Konto und Projekt anlegen | 10 Min (meist Warten) |
| 3 | Datenbank einrichten — **eine Datei, ein Klick** | 3 Min |
| 4 | Bestätigungs-E-Mails abschalten | 2 Min |
| 4b | Direkten QR-Zugang für Arbeiter freischalten | 2 Min |
| 4c | Kleine Zugang-Ergänzung einspielen (nur bei altem Setup) | 2 Min |
| 5 | Die zwei Zugangswerte abholen | 2 Min |
| 6 | App auf Cloudflare veröffentlichen | 10 Min |
| 7 | Erstes Konto anlegen und dich zum Betriebsleiter machen | 5 Min |

Wenn irgendwo etwas anders aussieht als hier beschrieben: die Anbieter ändern
ihre Oberflächen ständig. Am Ende steht [**Wenn etwas klemmt**](#wenn-etwas-klemmt)
mit den Fehlermeldungen, die wirklich vorkommen.

---

## Schritt 1 — Kurz zur Orientierung (nichts zu tun)

Der fertige Code liegt bereits bei GitHub, auf **einem** Branch namens
`claude/new-session-vrnnyo`. Dieser Branch ist zugleich der **Standard-Branch**
des Projekts — das heißt: GitHub und Cloudflare nehmen ihn von selbst. Du musst
**nichts** zusammenführen, nichts umbenennen, keinen zweiten Branch anlegen.

Merke dir nur den Namen `claude/new-session-vrnnyo`. Er taucht später ein paarmal
auf, und dann weißt du: Das ist einfach „mein Projekt".

> Falls du in einer früheren Fassung dieser Anleitung schon versucht hast, etwas
> nach `main` zu bringen, und daran gescheitert bist: Das war mein Fehler in der
> Anleitung, nicht deiner. Es gibt kein `main` und es braucht auch keins. Alles
> liegt auf dem einen Branch. Weiter mit Schritt 2.

---

## Schritt 2 — Supabase-Projekt anlegen## Schritt 2 — Supabase-Projekt anlegen

Supabase ist die Datenbank. Das Gratis-Konto reicht vollkommen.

**Was du machst**

1. Gehe auf https://supabase.com und klicke oben rechts auf
   **Start your project**.
2. Melde dich mit **GitHub** an (dasselbe Konto wie eben) und bestätige die
   Zugriffsfrage mit **Authorize**.
3. Falls Supabase nach einer **Organization** fragt:
   - *Name*: irgendetwas, zum Beispiel `Hof`
   - *Type*: `Personal`
   - *Plan*: **Free**
   - → **Create organization**
4. Jetzt kommt **Create a new project**. Trage ein:

   | Feld | Was hinein gehört |
   |---|---|
   | Project name | `kuerbis-verlust` |
   | Database Password | Auf **Generate a password** klicken |
   | Region | **Central EU (Frankfurt)** — damit die Daten in Europa liegen |
   | Pricing Plan | **Free** |

5. **Das Datenbank-Passwort jetzt kopieren und irgendwo sichern.** Supabase
   zeigt es kein zweites Mal. Für den Alltag brauchst du es nicht, aber wenn du
   es je brauchst, brauchst du es wirklich.
6. **Create new project** klicken.

**Was du siehst**

Ein Wartebildschirm mit „Setting up project…" und kreisenden Punkten. Das
dauert **ein bis drei Minuten**. Lass den Tab offen.

**Woran du merkst, dass es geklappt hat**

Der Wartebildschirm verschwindet und du landest auf der Projekt-Übersicht.
Links am Rand ist eine schmale Leiste mit Symbolen.

---

## Schritt 3 — Datenbank einrichten

**Das ist der Schritt, um den es geht: eine einzige Datei, einmal einfügen,
einmal auf Run.** Nicht acht Dateien. Nichts hochladen. Keine Reihenfolge, die
man falsch machen kann.

### 3a — Die Datei kopieren

1. Öffne im Browser:
   **https://github.com/konvalinaalexander-max/Kurbisverlust/blob/claude/new-session-vrnnyo/supabase/setup.sql**

   *(Am einfachsten ist der Weg über die Knöpfe unten — dann musst du diese
   lange Adresse gar nicht abtippen.)*

2. Über dem grauen Textblock ist rechts eine Reihe kleiner Symbole. Klicke auf
   das Symbol **Copy raw file** — zwei übereinanderliegende Rechtecke. Wenn du
   mit der Maus darüber fährst, erscheint der Text „Copy raw file".

   Kurz blitzt ein Häkchen auf. Damit liegen jetzt rund 1 400 Zeilen SQL in der
   Zwischenablage — der ganze Inhalt, nicht nur der sichtbare Ausschnitt.

   *Symbol nicht gefunden?* Klicke stattdessen auf den Knopf **Raw**. Es öffnet
   sich eine reine Textseite. Dort **Strg+A** (alles markieren), dann **Strg+C**
   (kopieren). Auf dem Mac ⌘+A und ⌘+C.

### 3b — Im SQL-Editor einfügen und ausführen

3. Zurück zum Supabase-Tab.
4. Klicke in der linken Symbolleiste auf **SQL Editor**. Das Symbol sieht aus
   wie ein Blatt Papier mit `>_` darauf und liegt im oberen Drittel. Wenn du mit
   der Maus über die Symbole fährst, erscheinen die Namen.
5. Du siehst eine große, fast leere Fläche mit einem blinkenden Cursor —
   darüber steht meist „New query". Klicke einmal hinein.
6. **Strg+V** (Mac: ⌘+V). Die Fläche füllt sich mit sehr viel Text, der mit
   `-- =====` beginnt. Das ist richtig so.
7. Klicke unten rechts auf den grünen Knopf **Run**. (Oder **Strg+Enter**.)

### 3c — Die Rückfrage bestätigen

**Wahrscheinlich erscheint jetzt ein Fenster** mit „Potentially destructive
operation" oder „Are you sure you want to run this query?".

Das ist normal und harmlos: Das Skript legt Sicherheitsregeln neu an, und
Supabase warnt bei jedem Skript, das solche Befehle enthält. In einem frisch
angelegten Projekt gibt es nichts, was kaputtgehen könnte.

→ Klicke auf **Run this query** beziehungsweise **I understand, run this query**.
Falls ein Kästchen zum Ankreuzen dabei ist, kreuze es an.

**Woran du merkst, dass es geklappt hat**

Unten im Ergebnisfenster erscheint eine Tabelle mit einer Spalte `ergebnis` und
genau dieser Zeile:

```
Fertig. 42 Chargen und 11 Sorten angelegt, 15 Tabellen und 23 Auswertungen
erstellt. Weiter im README bei Schritt 4.
```

Wenn du das siehst, ist die komplette Datenbank fertig: Tabellen, Zugriffsrechte,
alle 42 Chargen der Saison, alle Kaliber-Grenzen und die gesamte Auswertung.

Es dauert ein paar Sekunden. Es kommt **keine** Erfolgsmeldung als Popup — nur
diese Zeile unten.

> **Zweimal geklickt?** Kein Problem. Dann steht dort in Rot „Das Setup wurde
> bereits eingespielt — es ist nichts zu tun." Es ist wirklich nichts passiert:
> Das ganze Skript läuft als ein Block, und der bricht ab, bevor irgendetwas
> geändert wird. Einfach weitermachen.

---

## Schritt 4 — Bestätigungs-E-Mails abschalten

Ohne diesen Schritt verlangt Supabase bei jeder Anmeldung eine Bestätigungsmail.
Die kommt bei Gratis-Projekten oft gar nicht oder landet im Spam — und dann
kommt niemand in die App. Für ein internes Werkzeug mit einer Handvoll bekannter
Leute schaltest du das besser ab.

**Was du machst**

1. Linke Symbolleiste → **Authentication** (Symbol: eine Person).
2. Es öffnet sich ein zweites Menü. Klicke dort auf **Sign In / Providers**.
   *Bei älteren Versionen heißt der Punkt einfach **Providers**.*
3. In der Liste steht ganz oben **Email**. Klicke darauf, damit sich der Bereich
   aufklappt.
4. Suche den Schalter **Confirm email** und stelle ihn auf **aus** (der Schalter
   wird grau statt grün).
5. Klicke auf **Save**.

**Woran du merkst, dass es geklappt hat**

Der Schalter bleibt nach dem Neuladen der Seite grau.

> Lieber mit Bestätigungsmail? Dann lass den Schalter an. Rechne aber damit,
> dass die Mail bei Gratis-Projekten stark verzögert oder gar nicht ankommt —
> Supabase begrenzt das auf wenige Mails pro Stunde.

---

## Schritt 4b — Direkten Zugang für Arbeiter freischalten

Damit die Arbeiter **ohne Konto** per QR-Code hereinkommen (nur Name eintippen,
kein Passwort), muss in Supabase ein Schalter an.

**Was du machst**

1. Linke Symbolleiste → **Authentication**.
2. **Sign In / Providers** (bei älteren Versionen **Providers**).
3. Etwas weiter unten steht **Anonymous sign-ins** (oder „Allow anonymous
   sign-ins"). Auf **an** stellen (Schalter wird grün).
4. **Save**, falls ein Speichern-Knopf erscheint.

**Woran du merkst, dass es geklappt hat**

Der Schalter bleibt nach dem Neuladen grün. (Vergessen ist kein Drama — falls
ein Arbeiter später „Der direkte Zugang ist noch nicht freigeschaltet" sieht,
holst du genau diesen Schalter nach.)

> **Kurz zur Sicherheit:** Anonymer Zugang heißt, wer die Adresse deiner App
> kennt, kann Daten eintragen. Die Adresse ist nicht geheim, aber auch nicht zu
> erraten. Für ein internes Hof-Werkzeug ist das der richtige Kompromiss —
> lieber ein Arbeiter zu viel als eine Messung, die aus Bequemlichkeit gar nicht
> gemacht wird. Ans Dashboard, an den CSV-Upload und an die Stammdaten kommt
> weiterhin nur der Betriebsleiter mit seinem Login.

---

## Schritt 4c — Die Ergänzung für den direkten Zugang einspielen

Diese eine kleine Ergänzung sorgt dafür, dass ein Arbeiter ohne Mail sauber
angelegt wird. (Nur nötig, wenn du das Setup aus Schritt 3 vor dieser Version
eingespielt hast. Bei einem frischen Setup ist sie schon enthalten — dann
meldet sich der SQL-Editor mit „column already exists" o. Ä., das ist harmlos.)

**Was du machst** — genau wie Schritt 3, nur mit einer anderen, viel kürzeren
Datei:

1. Öffne
   **https://github.com/konvalinaalexander-max/Kurbisverlust/blob/claude/new-session-vrnnyo/supabase/migrations/0009_anonyme_arbeiter.sql**
2. Über dem Text rechts auf **Copy raw file** (oder **Raw** → Strg+A → Strg+C).
3. Supabase → **SQL Editor** → das alte Skript mit Strg+A, Entf löschen →
   einfügen → **Run**.
4. Kommt eine Rückfrage „Potentially destructive operation": **Run this query**.

**Woran du merkst, dass es geklappt hat**

Unten steht „Success. No rows returned" — das genügt hier. Fertig.

---

## Schritt 5 — Die zwei Zugangswerte abholen

Die App muss zwei Dinge wissen: **wo** deine Datenbank steht und **womit** sie
sich melden darf. Die beiden Werte stehen leider auf **zwei verschiedenen
Seiten** — das ist die Stelle, an der man sucht.

### 5a — Der Schlüssel

1. Ganz unten links in der Symbolleiste auf das **Zahnrad** klicken
   (*Project Settings*).
2. Im Menü links unter *CONFIGURATION* auf **API Keys**.
3. Du siehst die Überschrift **API Keys** und darunter zwei Reiter:
   `Publishable and secret API keys` und `Legacy anon, service_role API keys`.
   Bleib auf dem ersten (er ist bereits ausgewählt).
4. Etwas weiter unten steht der Abschnitt **Publishable key** mit einer Zeile
   namens `default`. Rechts vom Schlüssel — er beginnt mit `sb_publishable_` —
   ist ein kleines **Kopier-Symbol** (zwei übereinanderliegende Rechtecke).
   Klick darauf und sichere den Wert in deinem Notizzettel.

   Das ist `VITE_SUPABASE_ANON_KEY`.

> **Finger weg vom Abschnitt darunter.** „Secret keys" (beginnt mit
> `sb_secret_`) umgeht sämtliche Zugriffsregeln und gehört niemals in eine
> Webseite. Die App erkennt das inzwischen und verweigert den Start mit einer
> deutlichen Meldung — verlass dich aber lieber nicht darauf.
>
> Direkt darunter steht in Supabase übrigens „Publishable keys can be safely
> shared publicly" — genau deshalb ist der richtige Schlüssel unbedenklich.

*Zeigt deine Seite gar keine Reiter, sondern eine Liste „Project API keys"?*
Dann hat dein Projekt die ältere Oberfläche. Nimm dort die Zeile mit der
Beschriftung `anon` `public`. Sie funktioniert genauso.

### 5b — Die Project URL

Auf der Seite mit den API Keys steht sie **nicht**. Zwei Wege:

**Der schnelle Weg — aus der Adresszeile deines Browsers.**
Dort steht gerade etwas wie:

```
supabase.com/dashboard/project/qaryvviqdjnxrukpgdn/settings/api-keys
                               └────── das ist deine Projekt-Kennung ──────┘
```

Nimm das Stück zwischen `/project/` und dem nächsten `/` und baue daraus:

```
https://DEINE-KENNUNG.supabase.co
```

Für die Kennung oben wäre das `https://qaryvviqdjnxrukpgdn.supabase.co`.

**Der offizielle Weg.** Im selben Menü links, weiter unten unter *INTEGRATIONS*,
auf **Data API** klicken. Dort steht ganz oben **Project URL** mit einem
Kopier-Symbol daneben.

Das ist `VITE_SUPABASE_URL`.

> **Nicht die Adresszeile als Ganzes kopieren.** `https://supabase.com/dashboard/…`
> ist die Adresse der *Verwaltungsseite*, nicht deiner Datenbank. Auch das
> erkennt die App inzwischen und sagt es dir.

### Am Ende hast du

```
VITE_SUPABASE_URL       https://qaryvviqdjnxrukpgdn.supabase.co
VITE_SUPABASE_ANON_KEY  sb_publishable_Fj_FAZG…            (viel länger)
```

Beide brauchst du gleich in Schritt 6.

## Schritt 6 — App veröffentlichen

Cloudflare macht aus dem Code eine Webseite, die auf jedem Handy läuft. Gratis.

> **Warum sieht mein Bildschirm anders aus als in älteren Anleitungen?**
> Cloudflare hat „Pages" und „Workers" zusammengelegt. Es gibt keine getrennte
> „Pages"-Seite mehr — alles läuft jetzt über **Workers**. Das Projekt ist
> darauf eingestellt (die Datei `wrangler.toml` sagt Cloudflare, was zu tun
> ist), du musst also nichts suchen. Folge einfach den Feldern unten.

**Was du machst**

1. Gehe auf https://dash.cloudflare.com und lege ein Konto an oder melde dich an.
2. In der linken Leiste auf **Workers & Pages** klicken (manchmal nur
   **Compute** oder **Workers**).
3. **Create application** → **Import a repository** (oder **Connect to Git**).
4. Falls GitHub noch nicht verbunden ist: **Connect GitHub**, mit **Authorize**
   bestätigen, bei der Repository-Frage `Kurbisverlust` freigeben.
5. In der Liste `konvalinaalexander-max/Kurbisverlust` auswählen.

6. Jetzt kommt die Seite **Set up your application**. Genau die auf deinem
   Screenshot. Trage ein bzw. lass stehen:

   | Feld | Wert | |
   |---|---|---|
   | Project name | `kurbisverlust` | so lassen — muss genau so heißen |
   | Build command | `npm run build` | eintragen (steht als „Optional", wird aber gebraucht) |
   | Deploy command | `npx wrangler deploy` | **so lassen**, nichts ändern |
   | Builds for non-production branches | angehakt lassen | gibt Vorschau-Builds |

   Kein „Framework preset", kein „Build output directory", kein
   „Production branch" — die gibt es auf dieser Seite nicht mehr. Alles, was
   dort früher stand, erledigt jetzt `wrangler.toml`.

7. **Die zwei Werte aus Schritt 5 eintragen — sonst startet die App nicht.**

   Suche auf derselben Seite den Abschnitt **Variables and Secrets** (oder
   **Build variables**). Er kann etwas weiter unten stehen — nach unten scrollen.
   Lege mit **Add** zwei Einträge an, beide vom Typ **Text** (nicht „Secret"):

   | Variable name | Value |
   |---|---|
   | `VITE_SUPABASE_URL` | die Project URL aus Schritt 5 |
   | `VITE_SUPABASE_ANON_KEY` | der `sb_publishable_…`-Schlüssel aus Schritt 5 |

   Die Namen exakt so — Großbuchstaben und Unterstriche. Beim Einfügen des
   Schlüssels darf kein Leerzeichen und kein Zeilenumbruch mitkommen.

   > **Findest du den Abschnitt hier nicht?** Kein Problem, dann kommen die zwei
   > Werte gleich nach dem ersten Deploy dazu — siehe den Kasten „Falls die
   > Variablen erst nachträglich gehen" unter dieser Anleitung.

8. Unten rechts auf **Deploy** klicken.

**Was du siehst**

Eine schwarze Konsole, durch die Text läuft: `Cloning repository…`,
`Installing dependencies…`, `Building…`, am Ende `Uploaded` und `Deployed`.
Das dauert **ein bis drei Minuten**.

**Woran du merkst, dass es geklappt hat**

Es erscheint eine Erfolgsmeldung mit einer Adresse wie
`https://kurbisverlust.<etwas>.workers.dev`. Öffne sie.

Du siehst den Anmeldebildschirm mit dem Kürbis und den Feldern für E-Mail und
Passwort.

- Steht dort **„Noch nicht mit Supabase verbunden"**, fehlen die zwei Werte aus
  Punkt 7.
- Steht dort **„Die Zugangsdaten stimmen nicht"**, ist einer der beiden Werte
  vertippt oder verwechselt — die Meldung sagt, welcher.

In beiden Fällen hilft der Kasten direkt hier drunter.

> **Falls die Variablen erst nachträglich gehen**
>
> Wenn du die zwei Werte in Schritt 7 nicht eintragen konntest, oder die App
> „Noch nicht mit Supabase verbunden" zeigt:
>
> 1. Im Cloudflare-Dashboard links auf **Workers & Pages** → dein Projekt
>    `kurbisverlust` anklicken.
> 2. Reiter **Settings** → **Variables and Secrets** (oder **Build**).
> 3. Die zwei Variablen aus Punkt 7 als **Text** anlegen und speichern.
> 4. **Jetzt zwingend neu bauen:** Reiter **Deployments** → beim obersten
>    Eintrag rechts das Menü **⋯** → **Retry deployment**. Ohne neuen Build
>    ändert sich nichts, weil die Werte beim Bauen fest in die Seite kommen.

## Schritt 7 — Dein Konto und die Betriebsleiter-Rolle

Du legst dir als Betriebsleiter ein richtiges Konto an (die Arbeiter brauchen
keins). Dieses erste Konto muss einmal von Hand zum Betriebsleiter ernannt
werden — danach vergibst du alle weiteren Rollen bequem in der App.

**Was du machst**

1. Auf der Adresse aus Schritt 6 unten auf **Betriebsleiter-Login** klicken,
   dann auf **Neues Betriebsleiter-Konto anlegen**.
2. Namen, deine E-Mail-Adresse und ein Passwort eintragen (mindestens 6 Zeichen)
   → **Konto anlegen**.
3. Du bist angemeldet und siehst die Auftragsliste. Oben rechts steht dein Name.
   Noch **ohne** den Zusatz „Betriebsleiter" — das ändern wir jetzt.
4. Zurück zum Supabase-Tab → linke Symbolleiste → **SQL Editor**.
5. Falls noch das alte Skript im Feld steht: **Strg+A**, dann **Entf** — es ist
   längst ausgeführt und wird nicht mehr gebraucht.
6. Folgendes einfügen, **die E-Mail-Adresse durch deine ersetzen**, dann **Run**:

   ```sql
   update profil set rolle = 'admin'
    where id = (select id from auth.users where email = 'deine@adresse.ch');

   select name, rolle from profil;
   ```

   Die zweite Zeile zeigt dir gleich das Ergebnis — deshalb beides zusammen
   einfügen.

7. Im Ergebnisfenster erscheint eine Tabelle mit allen Konten. In deiner Zeile
   muss unter `rolle` jetzt **admin** stehen.

   Steht dort noch `arbeiter`, stimmt die E-Mail-Adresse nicht mit der überein,
   mit der du dich registriert hast — die Tabelle zeigt dir die Namen, mit denen
   die Konten angelegt wurden. Adresse korrigieren und nochmal **Run**.

**Woran du merkst, dass es geklappt hat**

Zurück im App-Tab die Seite neu laden (**F5**). Oben rechts steht jetzt dein
Name **· Betriebsleiter**, und in der Menüleiste sind drei Punkte dazugekommen:
**Sortier-CSV**, **Warteschlange** und **Stammdaten**.

**Damit ist die Einrichtung fertig.** Alles Weitere geht in der App.

---

# Teil 2 — Die ersten echten Daten

Die App ist jetzt leer. Drei Dinge in dieser Reihenfolge, dann rechnet sie.

## 0. Den QR-Zugang für die Arbeiter aufhängen

*Als Betriebsleiter anmelden → Menü **QR-Zugang***

Dort ist ein QR-Code. **QR-Code drucken** und in der Halle aufhängen. Die
Arbeiter scannen ihn mit der normalen Handy-Kamera, tippen einmal ihren Namen —
und sind sofort drin, ohne Konto und ohne Passwort. Jedes Handy merkt sich das,
beim nächsten Mal geht es direkt weiter.

Der eingetippte Name steht bei jeder Erfassung dabei, damit nachvollziehbar
bleibt, wer was gemessen hat. Arbeiter sehen nur die Aufträge; Dashboard,
CSV-Upload und Stammdaten bleiben dir vorbehalten.

## 1. Paletten aus dem Erntejournal übernehmen

*Stammdaten → Paletten-Import*

Zwei Wege — der erste ist der bequeme:

**A) Direkt aus dem Google Sheet (empfohlen).** Einmalig im Erntejournal-Sheet:
*Datei → Freigeben → Im Web veröffentlichen*, dort den Tab **Ertragsjournal** und
das Format **CSV** wählen und die entstehende Adresse (endet auf `output=csv`)
kopieren. Diese Adresse in der App unter *Stammdaten → Paletten-Import* einfügen.
Ab dann genügt **Jetzt vom Sheet holen** — die App liest den aktuellen Stand,
zeigt eine Vorschau und übernimmt ihn. Die Adresse wird gemerkt.

**B) Von Hand einfügen.** Im Sheet den Bereich samt Kopfzeile markieren, kopieren,
in das Feld einfügen, **Prüfen**, **übernehmen**. Für den Fall, dass du das Sheet
nicht veröffentlichen willst.

Beide Wege verstehen das Erntejournal so, wie es ist: Die **Charge ergibt sich
aus Schlag + Sorte** (eine eigene Chargennummer-Spalte im Sheet ist nicht nötig).
Datum, Brutto, Kisten und Gebindeart werden automatisch erkannt; eine leere
Gebindeart gilt als „G2". Zeilen, deren Schlag/Sorte nicht zur Chargen-Liste
passt, werden einzeln aufgelistet statt stillschweigend verschluckt — das ist
derselbe Hinweis wie der Kontrollwert im Sheet. Denselben Import mehrfach
auszuführen legt keine doppelten Paletten an (die App nutzt die Paletten-ID aus
dem Sheet).

Wie viel Ernte bisher zusammengekommen ist, zeigt danach *Stammdaten → Chargen*
ganz oben als Gesamtzahl.

> **Kurz zur Veröffentlichung:** „Im Web veröffentlichen" macht genau diesen einen
> Tab über eine nicht erratbare Adresse lesbar — nicht dein ganzes Google-Konto,
> nicht das Bearbeiten. Für interne Erntedaten ist das der einfachste Weg. Wer es
> ganz privat will, nimmt Weg B oder sagt mir Bescheid, dann binde ich es über
> deinen bestehenden Google-Zugang der Erntejournal-App an.

## 2. Leergewichte prüfen (meist nichts zu tun)

*Stammdaten → Gebinde & Tara*

Die Leergewichte sind bereits eingetragen — genau die Werte aus der
Erntejournal-App: Palette 25 kg, Kiste G2 1,5 kg, die IFCO-Kisten 1,36 / 1,68 /
2,0 kg. Daraus rechnet die App das Netto:

```
Netto = Brutto − 25 (Palette) − Kisten × Tara(Gebindeart)
```

Du musst hier nur dann etwas tun, wenn eine **neue, unbekannte Gebindeart** aus
dem Journal auftaucht — dann steht sie ohne Tara da und ist mit „Tara fehlt"
markiert. Solange irgendwo Tara fehlt, warnt das Dashboard sichtbar, weil die
betroffenen Paletten sonst aus der Auswertung fielen.

## 3. Einen echten Auftrag mitlaufen lassen## 3. Einen echten Auftrag mitlaufen lassen

*Aufträge → Neuen Auftrag eröffnen*

Weg und Charge wählen — die Startzeit setzt der Server, nicht das Handy. Wer
sonst noch mitarbeitet, öffnet denselben Auftrag und klickt **Beitreten**.

Dann während der Arbeit:

- **Paletten** — jede Palette einmal antippen. Das ist die einzige Pflichtangabe.
  Das Eingangsdatum vom Zettel ist freiwillig, macht die Lagerdauer aber genau.
- **Faule** — am Ende den vollen Palox wiegen, Kilo eintragen. Ist die Box
  zwischendurch voll: Teilgewicht erfassen und weitermachen.
- **Palette wiegen** — freiwillig, aber die wertvollste Messung überhaupt.
  Eine Palette beim Herausholen aus dem Lager wiegen, vor dem Wasserbecken.
- Auf Weg 2 zusätzlich **Gross / klein** und **Überfüllung**.

Am Schluss *Abschluss* → **Auftrag abschließen?** → **Sicher?**

Sortier-CSVs lädt der Betriebsleiter unter *Sortier-CSV* hoch. Vor dem Einlesen
siehst du den Reinigungs-Trichter — „11 370 gelesen → −5 Overflow → −10 unter
100 g → −2 183 Dubletten → 9 172 Kürbisse". Läuft die Datei nicht eindeutig auf
einen Auftrag, landet sie in der **Warteschlange** statt geraten zu werden.

---

## Vorher ausprobieren: eine erfundene Saison

Bevor die erste echte Palette gezählt ist, zeigt die Auswertung nichts — man
kann also nicht beurteilen, was am Ende herauskommt. Dafür gibt es Demo-Daten:
eine vollständige, erfundene Saison zum Durchklicken.

**Voraussetzung:** Dein Betriebsleiter-Konto muss existieren (Schritt 7).

1. [`supabase/demo_daten.sql`](supabase/demo_daten.sql) öffnen → **Copy raw file**
   → Supabase → **SQL Editor** → einfügen → **Run**.
2. In der App unter **Auswertung** durchklicken.

Du bekommst rund 460 t Eingang, 535 Paletten in 10 Chargen, 22 Arbeiten und
drei Sortierläufe — dazu absichtlich eine abgebrochene Arbeit und einen
Zahlendreher, damit auch die Sonderfälle einmal sichtbar sind.

**Wenn die echten Daten kommen:**
[`supabase/demo_daten_entfernen.sql`](supabase/demo_daten_entfernen.sql) genauso
einspielen. Es verschwindet restlos alles Erfundene, echte Daten bleiben
unberührt.

Was jede Ansicht bedeutet, steht in [`docs/DATENFLUSS.md`](docs/DATENFLUSS.md).

---

# Wenn etwas klemmt

| Was du siehst | Was los ist | Was hilft |
|---|---|---|
| Demo: „Es gibt noch kein Benutzerkonto" | Die Demo-Daten brauchen jemanden als Erfasser | Erst Schritt 7 (Betriebsleiter-Konto anlegen), dann nochmal |
| „Das Setup wurde bereits eingespielt" | Du hast Schritt 3 zweimal ausgeführt | Nichts. Es ist nichts passiert. Weiter mit Schritt 4. |
| „Potentially destructive operation" | Supabase warnt bei Skripten mit `drop`/`alter` | **Run this query** klicken. In einem neuen Projekt ist nichts zu zerstören. |
| Nach **Run** passiert nichts | Skript läuft noch | 10–20 Sekunden warten. Der Knopf zeigt solange einen Ladekreis. |
| `syntax error at or near ""` | Beim Kopieren wurde nur ein Teil erwischt | Schritt 3a wiederholen, diesmal über **Raw** + Strg+A + Strg+C. |
| App zeigt „Die Zugangsdaten stimmen nicht" | Die App prüft die zwei Werte beim Start und sagt im Text, welcher davon nicht passt | Meldung lesen, Schritt 5 wiederholen, bei Cloudflare korrigieren — **und danach neu bauen** (siehe Zeile unten) |
| App zeigt „Noch nicht mit Supabase verbunden" | Die zwei Werte aus Schritt 5 fehlen bei Cloudflare oder sind vertippt | Cloudflare → dein Projekt → *Settings* → *Environment variables* prüfen. **Danach zwingend neu bauen:** Reiter *Deployments* → beim obersten Eintrag rechts das Menü **⋯** → **Retry deployment**. Ohne neuen Build ändert sich nichts. |
| Anmeldung: „Email not confirmed" | Schritt 4 fehlt | Schritt 4 nachholen, dann erneut anmelden. |
| Anmeldung: „Invalid login credentials" | Falsches Passwort — oder das Konto gibt es noch nicht | Unten auf **Neues Konto anlegen** wechseln. |
| Arbeiter sieht „Der direkte Zugang ist noch nicht freigeschaltet" | Schritt 4b fehlt | In Supabase Authentication → Sign In / Providers → Anonymous sign-ins einschalten |
| „Dafür fehlt die Berechtigung" | Du bist noch Arbeiter, nicht Betriebsleiter | Schritt 7 nachholen, dann F5. |
| Menü zeigt kein „Stammdaten" | Dasselbe | Schritt 7 nachholen, dann F5. |
| Dashboard: „Noch keine auswertbaren Daten" | Keine Paletten importiert oder überall Tara fehlend | Teil 2, Punkte 1 und 2. |
| Dashboard warnt „Fehlende Tara" | Für manche Gebinde fehlt das Leergewicht | *Stammdaten → Gebinde & Tara* ausfüllen. |
| Supabase: „Project is paused" | Gratis-Projekte pausieren nach 7 Tagen ohne Nutzung | Grüner Knopf **Restore project**, ein bis zwei Minuten warten. Während der Saison passiert das durch die normale Nutzung nicht. |
| Cloudflare-Build schlägt fehl | Meist das Build command falsch oder leer | In der Konsole nach der ersten roten Zeile suchen. Build command muss `npm run build`, Deploy command `npx wrangler deploy` sein. |

Kommst du nicht weiter: Fehlermeldung wörtlich notieren, dazu welcher Schritt.
Das genügt fast immer zur Klärung.

---

# Teil 3 — Für die Technik

## Was gebaut ist

| Teil | Ort | Zustand |
|---|---|---|
| Datenbankschema, Rollen, Stammdaten | `supabase/migrations/0001`–`0003` | gegen Postgres 16 getestet |
| Reinigung, Klassierung, CSV-Zuordnung | `supabase/migrations/0004`, `src/lib/csv.ts` | mit Tests |
| Auswertung und Hochrechnung | `supabase/migrations/0005`–`0007` | Massenbilanz schließt im Test auf 0.1 % |
| App | `src/` | fertig |

`supabase/setup.sql` ist die Zusammenfassung aller Migrationen zu einer Datei —
das, was in Schritt 3 eingefügt wird. Sie wird von `supabase/setup_bauen.sh`
erzeugt; nach jeder Änderung an `supabase/migrations/` neu bauen. Der Testlauf
schlägt fehl, wenn beides auseinanderdriftet.

## Lokal entwickeln

```bash
npm install
cp .env.example .env.local     # die zwei Werte aus Schritt 5 eintragen
npm run dev
```

## Tests

```bash
npm test                    # Reinigung und Dateinamen-Parser, ohne Datenbank
./supabase/test/run.sh      # Schema, Logik, Views und Zugriffsrechte
```

`run.sh` prüft vier Dinge: dass die Migrationen einzeln durchlaufen und die
Fachlogik stimmt; dass `setup.sql` als ein einziger Query durchgeht, so wie der
Supabase-Editor ihn sendet; dass ein zweiter Durchlauf sauber abbricht, ohne
Daten anzufassen; und dass `setup.sql` zu den Migrationen passt.

Ohne Argument erwartet es einen lokalen Cluster auf Port 55432, sonst eine
Verbindungs-URL. `supabase/test/stub_supabase.sql` bildet dafür die Teile von
Supabase nach, die es lokal nicht gibt (`auth.users`, `auth.uid()`, `storage`) —
in das echte Projekt wird diese Datei **nicht** eingespielt.

## Wie gerechnet wird

Jede Charge wird in zwei Portionen zerlegt:

- **ausgelagert** — schon verarbeitet, die Lagerdauer ist beobachtet
- **im Lager** — rechts-zensiert, bis zum Stichtag projiziert

Auf beide läuft dieselbe Massenkaskade, jeder Anteil bezogen auf die Masse, die
in seinen Schritt hineingeht:

```
Eingang ──Verdunstung──> M1 ──Schimmel──> M2 ──Ausschuss/Nebenkanal──> verkaufsfähig
```

- **Verdunstung** multiplikativ: `netto_jetzt = netto_damals · (1−r)^Lagertage`.
  So kann die Hochrechnung auch über Monate nie mehr verbrauchen, als da ist.
- **Schimmel** als kumulative Kurve über die Lagerdauer, isoton geglättet —
  was verdorben ist, wird nicht wieder gesund.
- **Ausschuss und Nebenkanal** als Massenanteile aus der Sortier-CSV
  beziehungsweise den Handmessungen auf Weg 2.

Koeffizienten kommen je Sorte, solange die eigene Stichprobe trägt (n ≥ 3),
sonst aus allen Sorten zusammen. Welcher Fall gilt, steht an jeder Zahl.

**Zwei Bücher, nie vermischt:** Buch A ist der physische Verlust
(Verdunstung + Schimmel + Ausschuss zu klein), Buch B die verschenkte Marge
(Nebenkanal-Überschuss + Überfüllung der 8-kg-Kisten).

Die Probe aufs Exempel ist die **Massenbilanz**: Das Modell sagt voraus, wie
viel Masse am Sortierband ankommen müsste, die CSV hat sie gewogen. Liegen beide
nah beieinander, stimmen die Koeffizienten.

Fachliche Spezifikation: [`docs/SPEC.md`](docs/SPEC.md).
Begründung der Modellentscheidungen: [`docs/ENTSCHEIDUNGEN.md`](docs/ENTSCHEIDUNGEN.md).

## Was noch offen ist

- **Warenausgang wird nicht erfasst.** Die Massenbilanz vergleicht deshalb
  Modell gegen Sortier-CSV, nicht Eingang gegen Verkauf.
- **Preise fehlen** (pro Stück je Kaliber, pro Kiste). Buch B rechnet in
  Kilogramm, nicht in Franken.
- **Ground-Truth für die Dubletten-Regel** steht aus: einmal eine Palette von
  Hand zählen und mit `n_gueltig` vergleichen. Die Regel lässt sich beim Upload
  abschalten, der Unterschied ist damit direkt sichtbar.
- **Weg 1, Waschen:** Dort sind die Original-Paletten in Kaliber-Kisten
  aufgelöst, es gibt keine Palettenzahl mehr. Damit der dort ausgelesene
  Schimmel einen Nenner hat, muss beim Abschluss die verarbeitete Menge in kg
  eingetragen werden.
