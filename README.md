# Kürbis-Verlust-Tracking

Internes Werkzeug für einen landwirtschaftlichen Betrieb: Es findet heraus,
**wo** im Lager und in der Verarbeitung Kürbis-Masse verloren geht und **welche
Ursache dominiert** — aus bewusst lückenhaften, punktuellen Messungen.

Das Ziel ist das **Rangieren der Ursachen**, nicht eine kg-genaue Bilanz. Jede
Zahl im Dashboard lässt sich aufklappen und zeigt, aus welchen Stichproben,
welchem Koeffizienten und welcher Formel sie entstanden ist.

Die vollständige fachliche Spezifikation liegt in [`docs/SPEC.md`](docs/SPEC.md),
die Begründung der Modellentscheidungen in [`docs/ENTSCHEIDUNGEN.md`](docs/ENTSCHEIDUNGEN.md).

## Was gebaut ist

| Teil | Ort | Zustand |
|---|---|---|
| Datenbankschema, Rollen, Stammdaten | `supabase/migrations/0001`–`0003` | fertig, gegen Postgres 16 getestet |
| Reinigung, Klassierung, CSV-Zuordnung | `supabase/migrations/0004`, `src/lib/csv.ts` | fertig, mit Tests |
| Auswertung und Hochrechnung | `supabase/migrations/0005`–`0007` | fertig, Massenbilanz schließt im Test auf 0.1 % |
| App: Auftrags-Flow, CSV-Upload, Warteschlange, Dashboard | `src/` | fertig |
| Supabase-Projekt anlegen · Cloudflare-Pages-Deploy | — | **macht der Nutzer**, siehe unten |

Kosten: **€0** auf den Gratis-Stufen von Supabase und Cloudflare Pages.

## Einrichtung

### 1. Supabase-Projekt anlegen (einmalig, gratis)

1. Auf [supabase.com](https://supabase.com) ein Konto anlegen und ein neues
   Projekt erstellen.
2. Als Region **Central EU (Frankfurt)** wählen — dann liegen die Daten in Europa.
3. Das Datenbank-Passwort notieren.

> Gratis-Projekte pausieren nach 7 Tagen ohne Nutzung und werden mit einem Klick
> wieder geweckt. Während der Saison hält die wöchentliche Nutzung sie wach.

### 2. Schema einspielen

Im Supabase-Dashboard unter **SQL Editor** die Dateien aus `supabase/migrations/`
**der Reihe nach** einfügen und ausführen — `0001`, dann `0002`, und so weiter
bis `0008`. Jede Datei ist für sich vollständig.

Danach steht das Schema samt Charge-Registry und Kaliber-Grenzen der Saison.

### 3. Den ersten Betriebsleiter ernennen

Zuerst in der App ein Konto anlegen (Schritt 4). Neue Konten sind immer
*Arbeiter*. Dann im **SQL Editor**:

```sql
update profil set rolle = 'admin' where id = (
  select id from auth.users where email = 'chef@example.com'
);
```

Alle weiteren Rollen vergibt der Betriebsleiter danach in der App unter
*Stammdaten → Benutzer*.

### 4. App lokal starten

```bash
npm install
cp .env.example .env.local     # URL und anon key aus Project Settings → API
npm run dev
```

### 5. Auf Cloudflare Pages veröffentlichen (gratis)

1. [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages** →
   *Create* → *Pages* → *Connect to Git* → dieses Repository wählen.
2. Build-Einstellungen:
   - Framework preset: **Vite**
   - Build command: `npm run build`
   - Build output directory: `dist`
3. Unter *Settings → Environment variables* dieselben zwei Werte eintragen:
   `VITE_SUPABASE_URL` und `VITE_SUPABASE_ANON_KEY`.
4. *Save and Deploy*.

Der `anon key` darf öffentlich sein — was ein Angemeldeter sehen und ändern
darf, entscheidet ausschließlich die Row-Level-Security in der Datenbank.

### 6. Erster echter Durchlauf

1. *Stammdaten → Paletten-Import*: den Bereich aus dem Erntejournal-Sheet
   kopieren und einfügen. **Voraussetzung:** das Sheet braucht eine Spalte mit
   der Chargennummer — das ist der einzige Eingriff in die bestehende App.
2. *Stammdaten → Gebinde*: die Leergewichte eintragen. **Ohne Tara kein Netto**,
   und ohne Netto rechnet die Auswertung diese Paletten gar nicht mit.
3. Einen echten Auftrag eröffnen, Paletten zählen, einen Palox Faule wiegen.
4. Eine Sortier-CSV hochladen und prüfen, ob sie automatisch am richtigen
   Auftrag landet.

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
sonst aus allen Sorten zusammen. Welcher Fall gilt, steht in jeder Zahl.

**Zwei Bücher, nie vermischt:** Buch A ist der physische Verlust
(Verdunstung + Schimmel + Ausschuss zu klein), Buch B die verschenkte Marge
(Nebenkanal-Überschuss + Überfüllung der 8-kg-Kisten).

Die Probe aufs Exempel ist die **Massenbilanz**: Das Modell sagt voraus, wie
viel Masse am Sortierband ankommen müsste, die CSV hat sie gewogen. Liegen
beide nah beieinander, stimmen die Koeffizienten.

## Tests

```bash
npm test                    # Reinigung und Dateinamen-Parser (Node, keine DB nötig)
./supabase/test/run.sh      # Schema, Logik, Views und RLS gegen ein echtes Postgres
```

`run.sh` legt Schema und Stammdaten in einer Testdatenbank an, füttert sie mit
einem stimmigen Mini-Datensatz und prüft unter anderem, dass die Massenbilanz
sich schließt und dass ein Arbeiter messen, aber nicht verwalten darf. Ohne
Argument erwartet es einen lokalen Cluster auf Port 55432; sonst eine
Verbindungs-URL übergeben.

`supabase/test/stub_supabase.sql` bildet nur für diesen lokalen Test die Teile
von Supabase nach (`auth.users`, `auth.uid()`, `storage`). In das echte Projekt
wird diese Datei **nicht** eingespielt.

## Was noch offen ist

- **Warenausgang wird nicht erfasst.** Die Massenbilanz vergleicht deshalb
  Modell gegen Sortier-CSV, nicht Eingang gegen Verkauf. Für die volle Bilanz
  aus Spec §9 fehlen die Verkaufsmengen.
- **Preise fehlen** (pro Stück je Kaliber, pro Kiste). Buch B rechnet in
  Kilogramm, nicht in Franken.
- **Ground-Truth für die Dubletten-Regel** steht aus: einmal eine Palette
  von Hand zählen und mit `n_gueltig` vergleichen. Die Regel lässt sich beim
  Upload abschalten, der Unterschied ist damit direkt sichtbar.
- **Weg 1, Waschen:** dort sind die Original-Paletten in Kaliber-Kisten
  aufgelöst, es gibt keine Palettenzahl mehr. Damit der dort ausgelesene
  Schimmel einen Nenner hat, muss beim Abschluss die verarbeitete Menge in kg
  eingetragen werden.
