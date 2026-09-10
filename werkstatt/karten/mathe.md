# Mathematik-Karte — Werkstatt A, Runde M

**Stand:** Schema 0066, `supabase/setup.sql` (10 625 Zeilen).
**Gemessen auf:** eigener Kopie `karte_mathe` (`create database karte_mathe template demo`).
Verbindung: `export PGHOST=/tmp/pgsock PGPORT=55432 PGUSER=postgres`.
**Nichts verändert** — weder eine Datei noch `demo`.
Jede Zahl unten trägt den Befehl, mit dem sie gemessen wurde. Wo ich schätze
statt messe, steht „(geschätzt)“ daneben.

---

## 0. Wo die Mathematik wohnt

Alles Rechnen steckt im SQL. Das Frontend rechnet **nichts** Statistisches:
`grep -rn "1\.96|sqrt|lambda|smearing" src/` findet in `src/` nur
Achsenskalierung in `src/components/Diagramm.tsx` und Typdeklarationen in
`src/auswertung/daten.ts` — keine einzige Schätzformel. Das ist eine Stärke.

| Objekt | setup.sql | Rolle | Laufzeit |
|---|---|---|---|
| `v_koeff_roh_verdunstung` | 5990 | Rohpunkte r | — |
| `v_koeff_verdunstung_geschaetzt` | 6001 | Shrinkage-Schätzer r | — |
| `v_koeff_verdunstung` | 6104 | Anzeigefassung r | — |
| `v_koeff_roh_kaliber` | 6883 | Rohpunkte a_klein / a_gross / a_fax | — |
| `v_koeff_kaliber_geschaetzt` | 6909 | Shrinkage-Schätzer der drei | — |
| `v_koeff_ausschuss` / `_nebenkanal` / `_fax` | 7021 / 7042 / 7063 | Anzeigefassungen | — |
| `v_koeff_unsicherheit` | 7014 | Varianzbausteine für die Fortpflanzung | — |
| `v_schimmel_punkte` → `mv_schimmel_punkte` | 6380 ff. | 142 Schimmelmessungen | — |
| `v_schimmel_modell_rechnen` → `mv_schimmel_modell` | 6457–6757 | Verderbsmodell + Sockel | **525 ms** |
| `v_schimmel_kurve` | 6434 | Treppe (Rückfall) | — |
| `schimmelanteil(t, szenario)` | Funktion | Anzeigekurve mit Band | — |
| `mv_kaskade` | 7228 | die Kaskade, 171 Zeilen | — |
| `mv_hochrechnung` | — | Zerlegung in 7 Ströme, 1 197 Zeilen | — |
| `v_verlust_je_gruppe` → `erg_verlust` | 8530 | Aggregation + Bänder, 366 Zeilen | **240 ms** |
| `v_hochrechnung_basis` → `erg_charge` | 7850 | je Charge | — |
| `v_saisonbilanz` | 8864 | Saisonzahl + Bilanzrest | — |
| `v_massenbilanz` | 8167 | der **einzige** unabhängige Abgleich | — |
| `t_quantil_95(df)` | 1347 | t-Quantil, Tabelle | — |
| `zahl(x, stellen, grenze)` | 4161 / 4178 | Rundung + Plausibilitätsdeckel | — |
| `anteil_plausibel(x)` | 1168 | `x >= 0 and x <= 0.5` | — |

Messbefehl Laufzeit:
`psql -d karte_mathe -c "\timing on" -c "select count(*) from v_schimmel_modell_rechnen" -c "select count(*) from v_verlust_je_gruppe"`

**Korrektur zur Auftragsannahme:** *nicht* jede Zwischengrösse ist `numeric(14,2)`.
`mv_kaskade` speichert alle 48 Spalten als unbeschränktes `numeric`
(`psql -d karte_mathe -c "select attname, format_type(atttypid,atttypmod) from pg_attribute where attrelid='mv_kaskade'::regclass and attnum>0"`).
Gerundet wird erst an der Oberkante: `mv_hochrechnung.kg`, `v_verlust_je_gruppe.kg`,
`v_hochrechnung_basis.*`, `v_saisonbilanz.*`. Siehe Abschnitt 8.

---

## 1. Das Gerüst: die Kaskade in Formeln

Je Charge × Kohorte (Eingangstag) × Portion (`ausgelagert` / `entsorgt` / `lager`)
eine Zeile. 171 Zeilen in der Demo (85 ausgelagert, 86 lager, 0 entsorgt).

Sei t = Lagertage, r = Tagesrate Verdunstung, a₀ = Sockel, f = Verderbsanteil,
ã_k / ã_g = normierte Ausschuss-/Nebenkanalanteile, a_fax = Fax-Anteil.

**Verkaufsfähiger Anteil** (setup.sql:7528)

    A = max( (1−r)^t · (1−a₀) · (1−f) · (1−ã_k−ã_g) · (1−a_fax) , 0.25 )

**Verdunstungs-Anteil** (setup.sql:7533), nur für entsorgte Ware

    A_v = max( (1−r)^t , 0.25 )

**Rückrechnung auf die Eingangsmasse** (setup.sql:7541–7542)

    m₀ = geliefert / A                (ausgelagert)
    m₀ = geliefert / A_v              (entsorgt)
    m₀ = max( Eingang_Kohorte − Σ m₀_ausgelagert+entsorgt , 0 )   (lager)
    Überzählung = max( Σ m₀ − Eingang_Kohorte , 0 )

**Vorwärts durch die Stufen**

    m₁ = m₀ · (1−r)^t
    m₂ = m₁ · (1−a₀) · (1−f)                       [0 bei entsorgt]

    Verdunstung  = m₀ − m₁
    Sockel       = m₁ · a₀                          [0 bei entsorgt]
    Schimmel     = m₁ · (1−a₀) · f                  [= m₁ bei entsorgt]
    Klein        = m₂ · ã_k
    Nebenkanal   = m₂ · ã_g
    Fax          = m₂ · (1−ã_k−ã_g) · a_fax
    Verkaufsfähig= m₂ · (1−ã_k−ã_g) · (1−a_fax)

**Normierung** (setup.sql, CTE `koeff_norm`)

    ã_k = a_k / max(a_k + a_g, 1) ,  ã_g = a_g / max(a_k + a_g, 1)

**Ableitungen, die die Kaskade selbst mitführt**

    ∂m₁/∂r  = d_m1_r = −m₀ · t · (1−r)^(t−1)
    ∂f/∂η   = d_f_eta = (1−f) · exp(clamp(η, −40, 3))
    u       = ln(max(t,1)) − x̄        (zentrierte Log-Zeit)

**Der Hebel.** Gemessen über die 85 ausgelagerten Zeilen:
1/A im Mittel 1.1931, Spanne 1.1311 … 1.3832; in der Summe
m₀ = 138 950.2 kg gegen geliefert 115 836.3 kg — **23 113.9 kg (19.95 %)
Aufschlag**, den die Kaskade allein aus geschätzten Koeffizienten erzeugt.
Messbefehl:
`select round(avg(1/verkaufsfaehig_anteil),4), round(sum(m0)-sum(geliefert_kg),1) from mv_kaskade where portion='ausgelagert'`

---

## 2. Katalog: jede geschätzte Grösse

| # | Name | Formel | Einheit | Wertebereich (Bau) | Schätzertyp | Stichprobe Demo |
|---|---|---|---|---|---|---|
| 1 | `r` (Verdunstungsrate je Sorte) | siehe 3.1 | 1/Tag | erzwungen [0, 0.05] | massegewichteter Verhältnisschätzer + James-Stein-Shrinkage zum Gesamtwert | **41 Wiegungen aus 15 Chargen**, 11 Sorten bedient |
| 2 | `a_klein` (Ausschuss) | siehe 3.1 | Anteil | erzwungen [0, 1] | dito, art='ausschuss' | **48 Beobachtungen aus 33 Chargen** |
| 3 | `a_gross` (Nebenkanal) | siehe 3.1 | Anteil | erzwungen [0, 1] | dito, art='nebenkanal' | **39 Beobachtungen aus 25 Chargen** |
| 4 | `a_fax` (Faul beim Abpacken) | siehe 3.1 | Anteil | erzwungen [0, 1] | dito, art='fax' | **160 Beobachtungen aus 33 Chargen** |
| 5 | `k` (Weibull-Formparameter) | siehe 3.2 | dimensionslos | keine Klammer; `brauchbar` verlangt k > 0 | gewichtete Kleinste-Quadrate im Log-Log-Raum | 140 Punkte / **33 Chargen** |
| 6 | `ln λ` (Achsenabschnitt) | siehe 3.2 | ln(1/Tag^k) | keine Klammer | dito | dito |
| 7 | `smearing` s | siehe 3.2 | dimensionslos | Boden 0.01 | Duan-Smearing, massegewichtet | dito |
| 8 | `a₀` (Sockel) | siehe 3.3 | Anteil | Gitter [0, 0.10], Schritt 0.0025 | Gittersuche über SSE + F-artiger Nachweistest | dito |
| 9 | `f(t)` (Verderbsanteil) | 1 − exp(−exp(η)) | Anteil | erzwungen [0, 1], η geklammert [−40, 3] | Rücktransformation aus 5–7 | dito |
| 10 | Treppe `anteil_mono` | siehe 3.4 | Anteil | erzwungen [0, 1], kumulatives Maximum | Verhältnis der Summen je Altersklasse | 138 von 140 Punkten (2 fallen durch, s. u.) |
| 11 | `selektions_versatz` | siehe 3.5 | ln-Einheiten | Boden 0 | Differenz zweier gewichteter Residuen-Mittel minus 1.96·se | **NULL** — 0 Lagerkontrollen |
| 12 | Überfüllung kg/Kiste | siehe 3.6 | kg | Boden 0 | Verhältnis der Summen, Band mit fixem 1.96 | n = 32 |
| 13 | Gebinde kg/Gebinde | siehe 3.6 | kg | Boden 0 | Verhältnis der Summen je Sorte×Kaliber, Band mit t(n−1) | 26 Zeilen, n = 1 … 9 |
| 14 | Palette netto | `avg(netto_kg)` | kg | — | einfacher Mittelwert | 21 Zeilen |
| 15 | Kohortenanteil | Eingang_Tag / Σ Eingang | Anteil | auf 6 Stellen gerundet | Anteil | 36 Chargen |

Messbefehl Stichproben:
```
select count(*) wiegungen, count(*) filter (where verwendbar) verwendbar,
       count(distinct charge_nr) chargen from v_verdunstung_messung;
select art, coalesce(sorte,'(gesamt)'), n, c_chargen, round(mittel,5), round(b,3)
  from v_koeff_kaliber_geschaetzt order by art, sorte nulls first;
select quelle, count(*), count(*) filter (where plausibel),
       count(distinct charge_nr) from mv_schimmel_punkte group by quelle;
```

---

## 3. Die Schätzer im Einzelnen

### 3.1 Die vier Sorten-Koeffizienten (r, a_klein, a_gross, a_fax)

Identische Bauart, zwei Ansichten (`v_koeff_verdunstung_geschaetzt` 6001,
`v_koeff_kaliber_geschaetzt` 6909) — Wort für Wort dieselben 90 Zeilen SQL, nur
mit anderer Rohquelle. **Das ist eine echte Dublette von rund 90 Zeilen je Kopie.**

Ablauf, je Art × Sorte:

1. **Je Charge bündeln.** Sw_c = Σ w, Swa_c = Σ a·w mit w = Masse.
2. **Ebene bilden** über `grouping sets ((art, sorte), (art))` — Sorten-Ebene
   und Gesamt-Ebene in einem Durchgang.
3. **Punktschätzer** = Verhältnis der Summen:
   `mittel = Σ_c Swa_c / Σ_c Sw_c` — ein *massegewichteter* Mittelwert, nicht
   der Mittelwert der Einzelanteile.
4. **Varianz, chargen-robust (Sandwich):**

       V = Σ_c (Swa_c − mittel·Sw_c)² / (Σ Sw_c)² · C/(C−1),   nur wenn C > 1

   Das ist die korrekte Cluster-Varianz auf Chargen-Ebene — genau das, was
   `docs/STATISTIK_BEFUND.md` §3 als Reparatur beschreibt. **Geprüft und in Ordnung.**
5. **τ² zwischen den Sorten:**

       τ² = max( Σ_s Sw_s·(mittel_s − mittel_ges)² / Σ_s Sw_s − avg_s(V_s) , 0 )

6. **Shrinkage-Gewicht** (setup.sql:6100 / 7008):

       b = τ² / (τ² + V_eigen)     ;  b = 0 falls V_eigen oder mittel fehlt
       b = 1 für die Gesamt-Zeile

7. **Zusammengezogener Wert:**  `mittel = b·mittel_eigen + (1−b)·mittel_ges`
8. **Zwei verschiedene Varianzen** (!):

       varianz        = b·V_eigen + (1−b)²·V_ges       ← Anzeige (v_koeff_*)
       varianz_eigen  = b²·V_eigen                      ← Kaskadenband
       gewicht_gesamt = 1 − b ; varianz_gesamt = V_ges

9. **Freiheitsgrade** (setup.sql:6082):

       df = max( round(b·C_eigen + (1−b)·C_gesamt) − 1 , 1 )

**Gemessen, Demosaison:**

| art | eigene Sorten mit b ≥ 0.67 | mit b = 0 (rein gepoolt) | τ² | V_gesamt | df-Spanne |
|---|---|---|---|---|---|
| verdunstung | 3 (Butterkin, Mieluna, Tiana) | 8 | 1.096e-8 | 5.604e-10 | **1 … 14** |
| ausschuss | 8 | 3 | — | 8.348e-6 | **1 … 32** |
| nebenkanal | 6 | 5 | — | 2.200e-5 | **1 … 24** |
| fax | 8 | 3 | — | 1.352e-6 | **1 … 32** |

`select art, min(df), max(df), count(*) from v_koeff_unsicherheit group by art;`

**Massenanteil, der auf gepoolte Werte läuft:** 93 923.9 kg von 327 447.9 kg
Kaskadenmasse = **28.7 %** beziehen ihr r aus „Wiegungen aller Sorten“.
`select r_basis, count(*), round(sum(m0),1), round(100*sum(m0)/sum(sum(m0)) over(),1) from mv_kaskade group by 1;`

**Beide Varianzen im Vergleich** (Faktor sd_anzeige / sd_kaskade):

| art | Sorte | b | sd Anzeige | sd Kaskade | Faktor |
|---|---|---|---|---|---|
| nebenkanal | Amoro | 0.3787 | 0.016121 | 0.010184 | **1.583** |
| fax | Orangita | 0.4117 | 0.003581 | 0.002357 | **1.519** |
| fax | Amoro | 0.5857 | 0.002989 | 0.002308 | 1.295 |
| ausschuss | Mieluna | 0.8626 | 0.004608 | 0.004282 | 1.076 |

Dieselbe Zahl trägt also zwei Streuungen, die um bis zu **58 %** auseinanderliegen.
Gegenrede: `b·V` ist die Posteriorvarianz des Shrinkage-Schätzers, `b²·V` der
Eigenanteil für die Fehlerfortpflanzung — beides ist einzeln begründbar. Aber
der Betrieb sieht auf einem Bildschirm ein Band, das im Gesamtband nicht steckt.

### 3.2 Das Verderbsmodell — die Log-Kette exakt

Quelle: `mv_schimmel_punkte`, gefiltert auf
`plausibel and anteil > 0 and anteil < 1 and lagertage > 0 and quelle in ('verarbeitung','lager')`.
**Gemessen: 140 Punkte aus 33 Chargen, Lagerdauer 8.0 … 195.5 Tage.**
Von 142 Rohpunkten fallen 2 raus (`anteil` 1.55 und 1.65 — Tippfehler, die
`v_plausibilitaet` als „Schimmel“ meldet, Auftrag 112 und 304).

Die Kette, Schritt für Schritt (setup.sql:6457–6757):

    (1)  Rohpunkt:   (t_i, f_i, w_i)      w_i = basis_jetzt_kg
    (2)  Sockelabzug: fs_i = (f_i − a₀)/(1 − a₀)   falls quelle='verarbeitung'
                      fs_i = f_i                    falls quelle='lager'
    (3)  Doppelter Logarithmus:
                      x_i = ln t_i
                      y_i = ln( −ln(1 − fs_i) )
    (4)  Gewichtete Kleinste Quadrate (Gewichte w_i):
                      k    = (Sw·Swxy − Swx·Swy) / (Sw·Swxx − Swx²)
                      lnλ  = (Swy − k·Swx) / Sw
    (5)  Duan-Smearing, massegewichtet:
                      s    = Σ w_i·exp( y_i − (lnλ + k·x_i) ) / Σ w_i
    (6)  Korrigierter Achsenabschnitt (setup.sql:6710):
                      lnλ_korr = lnλ + ln( max(s, 0.01) )
    (7)  Rücktransformation (mv_kaskade, CTE teile/mit_f):
                      η(t) = lnλ_korr + k·ln( max(t, 1) )
                      f(t) = min( max( 1 − exp(−exp( clamp(η, −40, 3) )), 0 ), 1 )

**Gemessen (`select * from v_schimmel_modell;`):**

| Grösse | Wert |
|---|---|
| n | 140 |
| c_chargen | 33 |
| t_min / t_max | 8.0 / 195.5 Tage |
| k | 1.220865 |
| ln λ | −8.557510 |
| λ | 1.920970e-4 |
| x̄ (`x_mittel`) | 4.168321 |
| Sxx | 137 336.63 |
| **smearing s** | **1.048335** |
| **ln λ_korr** | **−8.510307** |
| σ² (`sigma2`) | 0.067255 |
| var_achse | 1.108097e-3 |
| var_k | 1.643351e-3 |
| kov_achse_k | 1.616059e-4 |
| t_faktor = t(c−1) = t(32) | 1.960 |
| brauchbar | true |
| selektions_versatz | **NULL** |

**Was die Rückverwandlung wirklich liefert.** Die Smearing-Korrektur macht
E[z] erwartungstreu, mit z = −ln(1−f). Sie macht **nicht** E[f] erwartungstreu:
f = 1 − e^(−z) ist konkav in z, also E[f] < 1 − e^(−E[z]). Es bleibt also nach
der Korrektur eine *nach oben* gerichtete Restverzerrung.
Grössenordnung, mit z̄ ∈ [0.031, 0.128] (gemessen) und σ² = 0.0673:

    Bias(f) ≈ −½ · e^(−z̄) · z̄² · (e^(σ²) − 1)
            ≈ −½ · 0.88 · 0.0128 · 0.0696  ≈ −3.9e-4  bei z̄ = 0.128

relativ zu f = 0.120 sind das **−0.33 %** — die Smearing-Korrektur selbst hebt λ
dagegen um **+4.83 %** (ln 1.048335). Die Restverzerrung ist also rund
**1/15 der Korrektur**; sie zählt hier nicht. (Analytisch gerechnet, nicht simuliert.)

**Abstand zum Smearing-Boden:** s = 1.0483 gegen Boden 0.01 → Faktor **104.8**.
Würde der Boden greifen, spränge λ um den Faktor 0.01/s.

**Die Varianz-Parametrisierung ist konsistent** — geprüft:
`var_achse = Saa/Sw² · C/(C−1)` ist die Cluster-Varianz von ȳ_w, also des Werts
*bei x = x̄*; `var_k = Skk/Sxx² · C/(C−1)`; `kov = Sak/(Sw·Sxx) · C/(C−1)`.
In `v_verlust_je_gruppe` wird mit `g_achse = Σ d_eta` und
`g_steigung = Σ d_eta·u`, u = ln t − x̄ gerechnet — genau die zentrierte
Parametrisierung. Passt zusammen.

**Was berechnet, aber nirgends benutzt wird:** `sigma2` (0 Treffer in `src/`,
nur Spaltendurchreichung in setup.sql), `t_faktor` (0 Treffer in `src/`,
`v_verlust_je_gruppe` rechnet sein t selbst), `sockel_unten` (0 Treffer in `src/`).
`grep -rl "sigma2|t_faktor|sockel_unten" src/` → leer.

### 3.3 Der Sockel a₀ — Gittersuche mit Nachweistest

**Gitter** (setup.sql:6469): `generate_series(0,40) * 0.0025` → 41 Kandidaten,
0 bis 0.10, **Auflösung 0.0025 = 0.25 Prozentpunkte**.

**Gütemass** (CTE `guete`): SSE **im Originalraum**, gewichtet —

    SSE(a₀) = Σ w_i · ( f_i − [ a₀·1{verarb} + (1 − a₀·1{verarb})·(1 − exp(−exp(clamp(lnλ + ln max(s,0.01) + k·x_i)))) ] )²

Gefiltert auf `k is not null and k > 0 and n >= 3`.

**Nachweisschwelle** (setup.sql:6561):

    Faktor = 1 + t(max(C−3, 1))² / max(C−3, 1)

mit C = Zahl distinkter Chargen in den Rohdaten. Gemessen: C = 33,
C−3 = 30 → t(30) = 1.960 → Faktor = 1 + 3.8416/30 = **1.128** (`sockel_schwelle`).

**Wahlregel** (CTE `wahl`): das kleinste a₀ mit
`SSE(a₀) ≤ 1.01·min(SSE)` **und** `SSE(0) > Faktor · min(SSE)`.
Fällt die zweite Bedingung, ist `wahl` leer und **a₀ = 0**.

**Gemessen:** `sockel_nachweis = SSE(0)/min(SSE) = 1.000`, `sockel_schwelle = 1.128`
→ **kein Nachweis, a₀ = 0**. `sockel_unten = 0.0000`, `sockel_oben = 0.0025`.

**Varianz des Sockels** (setup.sql:6754):

    sockel_var = ( (a₀_oben − a₀_unten) / 2 / t(C−1) )²
               = ( 0.0025 / 2 / 1.960 )² = 4.067316e-7

Das ist eine **Gitterquantisierung**, keine Datenaussage: die Halbbreite kann
nie feiner als 0.00125 sein, weil das Gitter nicht feiner ist.
sd(a₀) = 6.378e-4.

**Die SSE-Kurve über das Gitter — und das grosse Problem dabei.**
Punkte mit fs ≤ 0 fallen aus dem Fit; da min(f) = 0.0036, verliert das Gitter
ab a₀ = 0.005 Punkte:

| a₀ | Punkte im Fit | Chargen | k | ln λ | smearing | SSE | SSE/min |
|---|---|---|---|---|---|---|---|
| 0.0000 | **140** | 33 | 1.2209 | −8.5575 | 1.0483 | 127.70 | 1.0000 |
| 0.0025 | 140 | 33 | 1.4771 | −9.7728 | 1.0511 | 133.12 | 1.0424 |
| 0.0050 | 137 | 32 | 1.7925 | −11.2719 | 1.0706 | 156.77 | 1.2277 |
| 0.0100 | 130 | 32 | 2.6859 | −15.5282 | 1.2419 | 444.60 | 3.4816 |
| 0.0250 | 100 | 29 | 3.0838 | −17.9710 | 1.3359 | 276.75 | 2.1672 |
| 0.0500 | 56 | 21 | 3.5091 | −21.2414 | 2.8202 | 381.10 | 2.9844 |
| 0.1000 | **9** | 7 | — | — | — | — | — |

Messbefehl: die vollständige Nachrechnung des Gitters steht im Anhang A.

**Zwei Befunde daraus:**

1. **Die SSE-Werte sind über das Gitter nicht vergleichbar**, weil die
   Summe über verschiedene Punktmengen läuft (140 bis 9). Eine Summe über
   weniger Terme ist mechanisch kleiner. In der Demo rettet es das Ergebnis
   (der Anstieg der Residuen dominiert), aber die Regel selbst trägt nicht.
2. **k reagiert extrem auf a₀.** Ein einziger Gitterschritt (0.0025) hebt
   k von 1.2209 auf 1.4771 — **+21.0 %**, also **6.3-mal die berichtete
   sd(k) = sqrt(0.0016434) = 0.0405**. In der Fehlerrechnung gehen a₀ und k
   trotzdem als **unabhängig** ein.

**Wie viel Masse das kostet — direkt gemessen:**

| a₀ | k | Sockel kg | Schimmel kg | Summe kg | Δ zu a₀=0 |
|---|---|---|---|---|---|
| 0 | 1.2209 | 0.0 | 26 170.3 | 26 170.3 | — |
| 0.0025 | 1.4771 | **759.8** | **28 170.7** | **28 930.4** | **+2 760.2 kg (+10.5 %)** |
| 0.0050 | 1.7925 | 1 519.6 | 31 318.9 | 32 838.5 | +6 668.2 kg |
| 0.0075 | 2.0064 | 2 279.4 | 32 840.4 | 35 119.8 | +8 949.5 kg |

Messbefehl: Anhang B.

a₀ = 0.0025 liegt **innerhalb** des ausgewiesenen Bereichs (`sockel_oben = 0.0025`).
Der direkte Anteil (759.8 kg) ist genau das, was die Delta-Methode einfängt
(g_a0 · 0.0025 = 193.83/6.378e-4 · 0.0025 = 759.6 kg — Übereinstimmung auf 0.03 %).
Der **indirekte** Anteil über neu geschätztes k und λ ist 2 000.4 kg,
also **2.63-mal so gross wie der direkte** — und er fehlt in der Varianz vollständig.

### 3.4 Die Treppe (Rückfall, wenn `brauchbar` falsch ist)

`v_schimmel_kurve` (setup.sql:6434), sieben feste Klassen:
(0,14), (15,30), (31,60), (61,90), (91,120), (121,180), (181,100000).

    anteil_k    = Σ schimmel_kg / Σ basis_jetzt_kg     (Verhältnis der Summen)
    sd_k        = stddev_samp(anteil_i)                (ungewichtete Streuung der Einzelanteile)
    anteil_mono = min( max( laufendes Maximum(anteil) , 0 ), 1 )
    unten/oben  = anteil ∓ 1.96·sd/sqrt(n)             nur bei n ≥ 2

**Gemessen:**

| von–bis | n | anteil | anteil_mono | Halbband mit 1.96 | Halbband mit t(n−1) | Faktor |
|---|---|---|---|---|---|---|
| 0–14 | 4 | 0.00459 | 0.00459 | 0.00144 | 0.00234 | **1.623** |
| 15–30 | 6 | 0.00766 | 0.00766 | 0.00114 | 0.00150 | 1.312 |
| 31–60 | 36 | 0.01770 | 0.01770 | 0.00243 | 0.00243 | 1.000 |
| 61–90 | 41 | 0.03585 | 0.03585 | 0.01137 | 0.01137 | 1.000 |
| 91–120 | 22 | 0.03304 | 0.03585 | 0.00352 | 0.00373 | 1.061 |
| 121–180 | 25 | 0.07234 | 0.07234 | 0.00878 | 0.00925 | 1.053 |
| 181+ | **4** | 0.03027 | 0.07234 | 0.00798 | 0.01296 | **1.623** |

**Drei Befunde:**

1. **Lücken zwischen den Klassen.** `lagertage` ist `numeric`, die Klassen sind
   ganzzahlig und lassen 14→15, 30→31, 60→61, 90→91, 120→121, 180→181 offen.
   Gemessen: **80 von 140 Punkten haben eine gebrochene Lagerdauer**, und
   **2 Punkte fallen tatsächlich durch** (t = 30.5 und t = 90.7).
   Messbefehl im Anhang C.
2. **1.96 statt t(n−1).** In den beiden Klassen mit n = 4 — darunter die
   *älteste*, die für die Prognose die wichtigste ist — ist das Band um
   **62 % zu schmal**.
3. **Punktschätzer massegewichtet, Streuung ungewichtet.** Genau der Fehler,
   den `docs/STATISTIK_BEFUND.md` als „Punkt 10“ für die Koeffizienten behoben
   hat — in der Treppe steht er noch.

### 3.5 Selektionsversatz und Zuschlag

Formel (setup.sql:6731, sinngemäss):

    versatz = max( | ē_lager − ē_verarb | − 1.96·sd(e_lager)/sqrt(n_lager) , 0 )
              nur wenn n_lager ≥ 5, sonst NULL

    zuschlag = kg_projiziert · | exp(versatz) − 1 |     (nur Strom „Schimmel/Fäulnis“)

und wird in `v_verlust_je_gruppe` **symmetrisch** auf beide Seiten gelegt:
`kg_unten = kg − t·streuung − zuschlag`, `kg_oben = kg + t·streuung + zuschlag`.

**Gemessen:** `mv_schimmel_punkte` enthält **0 Punkte mit quelle='lager'** —
alle 140 kommen aus 'verarbeitung'. Also `selektions_versatz = NULL`,
`zuschlag = 0` in jeder Zeile. `v_selektionsverdacht` sagt genau das:
„keine Lagerkontrollen — Selektion nicht prüfbar“, n_lager = NULL.

Zwei Konsequenzen:

- Der Sockel a₀ ist damit **schwach identifiziert**: die Trennung „Sockel vs.
  Verderb“ lebt davon, dass es Punkte *ohne* Sockel gibt. Ohne Lagerpunkte
  hängt sie allein an der Krümmung der Kurve — und die reagiert, wie in 3.3
  gemessen, auf einen Gitterschritt mit +21 % in k.
- Der Zuschlag verbreitert **beidseitig**, obwohl die Richtung der
  Selektionsverzerrung bekannt ist. `docs/STATISTIK_BEFUND.md` Zeile 604 sagt
  „rund 10 % **zu hoch**“; Zeile 276 derselben Datei sagt „systematisch **zu
  niedrig**“ — die erste Tabelle wurde nie nachgeführt. Eine bekannte,
  gerichtete Verzerrung gehört als Verschiebung des Punktes behandelt, nicht
  als symmetrische Verbreiterung. 10 % von 26 170.3 kg = **2 617 kg**.
- Formel selbst: `stddev_samp(e)` über **Punkte** und `sqrt(count(*))` über
  **Punkte** — der Clusterfehler, der überall sonst behoben wurde,
  steckt hier noch drin.

### 3.6 Überfüllung und Gebinde

    v_koeff_ueberfuellung:  kg/Kiste = Σ ueberfuellung_kg / Σ kisten
                            Band     = ∓ 1.96 · sd(je_kiste) / sqrt(n)
    v_koeff_gebinde:        kg/Gebinde = Σ kg / Σ anzahl
                            Band       = ∓ t(n−1) · sd / sqrt(n)

**Gemessen:** Überfüllung n = 32, 0.467 kg/Kiste, Band 0.417 … 0.516.
Bei n = 32 ist 1.96 zufällig richtig; bei n = 3 wäre es 39 % zu schmal.
Gebinde: 26 Zeilen, n von 1 bis 9. **Bei n = 1 (Fictor) ist das Band null breit**
(`sd is null` → `unten = oben = mittel`). Dasselbe Muster in
`v_koeff_ueberfuellung` bei n < 2. Eine einzige Beobachtung erzeugt so ein
Band der Breite 0 — Sicherheit aus dem Nichts.

Zwei Geschwisteransichten, zwei verschiedene Quantile — ohne erkennbaren Grund.

---

## 4. Die Unsicherheitskette: von der Varianz zum Band

`v_verlust_je_gruppe` (setup.sql:8530). Je (Gruppe, Schlüssel, Strom, Buch):

**Gradienten sammeln**

    je Sorte:      g_r = Σ d_r ,  g_a = Σ d_a
    je Strom:      g_achse = Σ d_eta , g_steigung = Σ d_eta·u , g_a0 = Σ d_a0
    (jeweils ohne die Zeilen mit `erwartet` = Fax auf Lagerware)

**Drei Varianzblöcke**

    Var_r = Σ_s g_r,s²·V_eigen,s  +  ( Σ_s g_r,s·(1−b_s) )² · V_gesamt
    Var_a = analog mit der zum Strom passenden Art
    Var_f = g_achse²·var_achse + 2·g_achse·g_steigung·kov + g_steigung²·var_k
            + g_a0²·sockel_var

**Zusammenzählen und Quantil** (setup.sql:8754)

    streuung = sqrt( max( Var_r + Var_a + Var_f , 0 ) )
    df       = LEAST( coalesce(df_r, 999), coalesce(df_a, 999), coalesce(df_f, 999) )
    mit  df_r = df_a = min_s( coalesce(df_s, 1) )        (setup.sql:8654/8664)
         df_f = c_chargen − 1
    kg_unten = max( kg − t(df)·streuung − zuschlag , 0 )
    kg_oben  =      kg + t(df)·streuung + zuschlag

**Rekonstruktion geprüft:** ich habe die Varianzblöcke ausserhalb der Ansicht
nachgerechnet (Anhang D) und treffe jede Streuung exakt:
56.51 / 227.32 / 193.83 / 1279.15 / 364.50 / 190.77 kg. Die Formel steht also
so da, wie ich sie hier aufschreibe.

**Gemessen, Gruppe „gesamt“:**

| Strom | Buch | kg | unten | oben | streuung | df | t | Breite / kg |
|---|---|---|---|---|---|---|---|---|
| Schimmel/Fäulnis | verlust | 26 170.29 | 9 917.41 | 42 423.17 | 1 279.15 | **1** | 12.706 | **124.2 %** |
| Verdunstung | verlust | 23 530.25 | 18 898.88 | 28 161.62 | 364.50 | **1** | 12.706 | 39.4 % |
| Zu klein | marge | 7 349.52 | 4 925.59 | 9 773.45 | 190.77 | **1** | 12.706 | 66.0 % |
| Nebenkanal | marge | 4 790.06 | 1 901.78 | 7 678.34 | 227.32 | **1** | 12.706 | 120.6 % |
| Fax | verlust | 2 418.88 | 1 700.84 | 3 136.92 | 56.51 | **1** | 12.706 | 59.4 % |
| Nicht lagerbedingt | feld | **0.00** | 0.00 | **2 462.74** | 193.83 | **1** | 12.706 | — |

**Der Freiheitsgrad ist überall 1.** Ursache: `min(coalesce(u.df, 1))` läuft
über **alle Sorten der Gruppe**, unabhängig davon, wie viel Varianz eine Sorte
beisteuert. Gemessen für den Strom Verdunstung:

| Sorte | g_r | df | Beitrag zur Eigenvarianz |
|---|---|---|---|
| Tiana | 22 902 653 | 6 | 36 563.38 |
| Butterkin | 6 989 870 | 2 | 16 648.36 |
| **Mieluna** | 3 429 306 | **1** | **1.27** |
| alle übrigen | — | 14 | 0.00 |

**Mieluna steuert 1.27 von 53 213 Einheiten Eigenvarianz bei — 0.0024 % — und
setzt t für die ganze Saison von 1.960 auf 12.706.**

**Was das kostet.** Mit einem Welch-Satterthwaite-df aus denselben Bausteinen:

| Strom | df ist | df Satterthwaite | Breite ist | Breite S-W | Differenz |
|---|---|---|---|---|---|
| Schimmel/Fäulnis | 1 | **32.1** | 32 505.8 kg | 5 014.3 kg | −27 491.5 kg |
| Verdunstung | 1 | **21.7** | 9 262.7 kg | 1 516.3 kg | −7 746.4 kg |
| Nebenkanal | 1 | **33.5** | 5 776.7 kg | 891.1 kg | −4 885.6 kg |
| Nicht lagerbedingt | 1 | **32.0** | 4 925.6 kg | 759.8 kg | −4 165.8 kg |
| Zu klein | 1 | **14.9** | 4 847.8 kg | 818.4 kg | −4 029.4 kg |
| Fax | 1 | **38.9** | 1 436.0 kg | 221.5 kg | −1 214.5 kg |

Gesamtverlust (verlust + feld):

    ist:            52 119.4 kg   [ 30 517.2 … 76 184.5 ]   Breite 45 667.3 kg = 14.13 % des Eingangs
    Satterthwaite:  52 119.4 kg   [ 48 743.4 … 55 875.4 ]   Breite  7 132.0 kg =  2.21 % des Eingangs
    Differenz:                                              38 535.3 kg = 11.9 Prozentpunkte

**Gegenprobe an derselben Grösse an anderer Stelle.** Die Anzeigekurve
`schimmelanteil(t, 'unten'/'oben')` benutzt für dasselbe f das Modell-eigene
`t_faktor = t(c_chargen−1) = 1.960` und **ohne** den Sockelterm:

| t (Tage) | mittel | unten | oben | Breite |
|---|---|---|---|---|
| 30 | 0.01272 | 0.01171 | 0.01383 | 16.7 % |
| 90 | 0.04779 | 0.04449 | 0.05132 | 14.3 % |
| 195 | 0.11825 | 0.10607 | 0.13173 | **21.7 %** |
| 300 | 0.19179 | 0.16822 | 0.21822 | 26.1 % |

Der Strom Schimmel/Fäulnis bekommt im selben System **124.2 %**. Rechnet man
das Kaskadenband mit t = 1.960, kommt man auf ±9.6 % — praktisch dasselbe wie
die Kurve. **Die gesamte Diskrepanz ist der df.**

**Dieselbe Doppelung beim Sockel:** `v_hochrechnung_basis.sockel_oben_kg`
(setup.sql:7951) rechnet `lager_kg · 1.96 · sqrt(a0_var)`, Summe **235.6 kg**.
`v_verlust_je_gruppe` gibt für denselben Sockel **2 462.74 kg** — Faktor **10.5**
(6.48 aus t, der Rest aus der anderen Bezugsmasse).

---

## 5. Wo geklammert wird — und wie weit die Demosaison davon weg ist

| # | Klammer | Belegstelle | Wert Demo (min/max) | Abstand |
|---|---|---|---|---|
| 1 | `r = least(greatest(coalesce(r,0),0), 0.05)` | mv_kaskade CTE `koeff` | 0.000461 … 0.000617 /Tag | **Faktor 81 … 108** unter dem Deckel |
| 2 | `a_klein = least(greatest(·,0),1)` | dito | 0.0042 … 0.0360 | Faktor 28 … 240 |
| 3 | `a_gross = least(greatest(·,0),1)` | dito | 0.0032 … 0.1164 | Faktor 8.6 … 316 |
| 4 | `a_fax = least(greatest(·,0),1)` | dito | 0.0128 … 0.0247 | Faktor 40 … 78 |
| 5 | `greatest(a_k + a_g, 1)` (Normierung) | CTE `koeff_norm` | Rohsumme max **0.1342** | **Faktor 7.45**; nie aktiv |
| 6 | `greatest(A, 0.25)` (verkaufsfähiger Anteil) | setup.sql:7528 | 0.6708 … 0.8841, Mittel 0.8005, sd 0.0473 | **+0.4208 absolut**, min = **2.68×** Boden; 0 Zeilen am Boden |
| 7 | `greatest((1−r)^t, 0.25)` (Verdunstungsanteil) | setup.sql:7533 | min 0.8849 | 3.54× Boden; nur für entsorgte Ware, in Demo unbenutzt |
| 8 | `clamp(η, −40, 3)` | mv_kaskade CTE `mit_f` | η ∈ [−3.4647, −2.0540] | **5.05 in ln-Einheiten** zum Deckel = Faktor 194 in λt^k |
| 9 | `least(greatest(f,0),1)` | dito | 0.0308 … 0.1203 | 8.3× vom Deckel |
| 10 | `greatest(smearing, 0.01)` | setup.sql:6710 | 1.048335 | **Faktor 104.8** |
| 11 | `greatest(m0_lager − Σ ausgelagert, 0)` | CTE `lager` | 4 179.88 kg als Überzählung abgeschnitten | **1.29 %** des Eingangs; Warnschwelle 5 % → 3.71 pp Abstand |
| 12 | `greatest(kg − t·s − zuschlag, 0)` | setup.sql | „Nicht lagerbedingt“ liegt auf 0 | **greift aktiv**, 1 von 6 Strömen |
| 13 | `anteil_plausibel: 0 ≤ x ≤ 0.5` | setup.sql:1168 | 2 von 142 Punkten (1.4 %) verworfen | greift aktiv |
| 14 | Gitter a₀ ∈ [0, 0.10], Schritt 0.0025 | setup.sql:6469 | a₀ = 0 (untere Kante) | **greift an der Kante** |
| 15 | `greatest(C−3, 1)` in der Schwelle | setup.sql:6561 | C−3 = 30 | weit weg |
| 16 | `greatest(df, 1)` im Koeffizienten-df | setup.sql:6082 | df = 1 für 4 Sorten | **greift aktiv** |
| 17 | `least(greatest(f1/f2, 0), 0.99)` (Waschen-Kombination) | setup.sql:6410 ff. | — | nicht gemessen |
| 18 | `zahl(x, stellen, grenze)` | 4161 | siehe 8 | Faktor > 10⁶ |

Messbefehl für 1–9:
```
select round(min(verkaufsfaehig_anteil),4), round(max(verkaufsfaehig_anteil),4),
       round(avg(verkaufsfaehig_anteil),4), round(stddev_samp(verkaufsfaehig_anteil),4),
       count(*) filter (where verkaufsfaehig_anteil<=0.25),
       round(min(r),6), round(max(r),6), round(min(f),4), round(max(f),4),
       round(min(a_klein_n+a_gross_n),4), round(max(a_klein_n+a_gross_n),4),
       round(min(a_fax),4), round(max(a_fax),4)
  from mv_kaskade;
```

**Wichtig für Werkstatt A2:** Klammern 6, 7, 9 und 10 sind in der Demo weit weg —
aber die Demo hat auch **keine schlechte Charge**. Bei r = 0.005/Tag (10× der
gemessenen Rate, in der Literatur für warme Lagerung nicht abwegig) und
t = 200 Tagen ist (1−r)^t = 0.367, und A fiele mit den übrigen Faktoren auf
rund 0.29 — **dann ist der Boden 0.25 nur noch 16 % entfernt**, und er ist
einseitig: er kann m₀ nur nach unten begrenzen, also den Verlust **unter**schätzen.
(Rechnung, nicht gemessen — die Demodaten enthalten keinen solchen Fall.)

---

## 6. Die harten Fragen aus dem Auftrag

### 6.1 „m₀ = geliefert ÷ verkaufsfähiger Anteil — wo genau, und wie streut der Nenner?“

**Wo:** `supabase/setup.sql:7541–7542`, CTE `ausgelagert` in `mv_kaskade`:

```sql
CASE WHEN a.portion = 'entsorgt' THEN (a.geliefert_kg / a.verdunstungs_anteil)
     ELSE (a.geliefert_kg / a.verkaufsfaehig_anteil) END AS m0
```

Der Nenner entsteht 13 Zeilen darüber (7528) und ist ein Produkt aus **fünf**
geschätzten Grössen (r, a₀, f, ã_k+ã_g, a_fax).

**Streuung, zwei verschiedene Dinge — beide gemessen:**

| | Wert |
|---|---|
| **Querschnitts-Streuung** über die 171 Zeilen (echte Variation, kein Fehler) | Mittel 0.8005, sd **0.0473**, Spanne 0.6708 … 0.8841, VK = **5.91 %** |
| **Schätz-Unsicherheit** des Nenners (Delta-Methode aus den Varianzbausteinen) | sd im Mittel **0.00404** (ausgelagert) / 0.00632 (lager), VK **0.48 %** im Mittel, **1.21 %** maximal |

**Verzerrung des Verhältnisses.** Für E[X/Ŷ] ≈ (X/Y)(1 + Var(Ŷ)/Y²) ist die
relative Verzerrung gleich VK(Â)². Gemessen: **0.0029 % im Mittel**, in Kilo
über alle ausgelagerten Zeilen **+4.6 kg** auf 138 950.2 kg m₀.

**Urteil: sie zählt hier nicht.** Sie zählte ab VK(Â) ≈ 10 % (1 % Verzerrung),
also **ab dem 20-Fachen der heutigen Koeffizientenunsicherheit**. Bei der in
6.5 gemessenen a₀-Kopplung kommt man dem näher, aber immer noch nicht hin.
Belegbefehl: Anhang E.

### 6.2 „Die Bänder addieren Varianzen — wo genau, und welche Unabhängigkeit?“

**Wo:** `setup.sql:8754`, CTE `g0`:

```sql
sqrt(GREATEST(COALESCE(vr.varianz,0) + COALESCE(va.varianz,0) + COALESCE(vf.varianz,0), 0)) AS streuung
```

Drei Blöcke werden **ohne Kovarianzterm** addiert. Vorausgesetzt wird:

1. **r ⟂ a** (Verdunstung unabhängig von Ausschuss/Nebenkanal/Fax).
   Beide werden aus derselben Charge, teils demselben Auftrag gebildet
   (`v_verdunstung_messung` und `v_ausschuss_beobachtung` teilen `charge_nr`).
   Nicht geprüft — es gibt keine Ansicht, die diese Kovarianz misst.
2. **r ⟂ f, a ⟂ f.** Die Schimmelpunkte kommen aus `v_auftrag_masse` /
   `sortier_lauf`, dieselben Aufträge, aus denen `a_klein`/`a_gross`/`a_fax`
   kommen. `mv_schimmel_punkte` hat 33 Chargen, `v_koeff_kaliber_geschaetzt`
   art='ausschuss' ebenfalls **33 Chargen**. Es sind dieselben.
3. **a₀ ⟂ (lnλ, k)** — innerhalb von Var_f wird der Sockelterm
   `g_a0²·sockel_var` einfach addiert, während die drei Modellparameter
   untereinander korrekt mit Kovarianz gerechnet werden. **Das ist der
   nachweisbar falsche Teil:** aus 3.3 ist gemessen, dass ein Gitterschritt in
   a₀ k um +21 % verschiebt, und dass 2 000.4 kg der 2 760.2 kg Wirkung
   *indirekt* über k und λ laufen — also genau der Term, der fehlt. Die
   Varianz ist damit für den Sockel-Kanal um den Faktor
   (2 760.2/759.8)² ≈ **13.2** zu klein.
4. **Innerhalb Var_r/Var_a** ist die Kovarianz über den gemeinsamen
   Gesamtwert korrekt behandelt (`( Σ g·(1−b) )²·V_ges` statt Σ g²(1−b)²V_ges) —
   das ist sauber gebaut und der Kommentar bei setup.sql:6086 sagt es auch.

### 6.3 „Die Log-Kette exakt“

Siehe 3.2, Schritte (1)–(7). Kurzform:

    y = ln(−ln(1−fs))  ──WLS──►  (k, lnλ)  ──smearing──►  lnλ_korr = lnλ + ln(max(s,0.01))
    ──►  η(t) = lnλ_korr + k·ln(max(t,1))  ──►  f(t) = 1 − exp(−exp(clamp(η,−40,3)))

Gemessen: s = 1.048335 (+4.83 % auf λ), σ² = 0.067255, Restverzerrung durch
die Konkavität von f(z) ≈ **−0.33 %** (analytisch). Duan-Smearing ist bei
n = 140 / 33 Chargen der richtige Schätzer; er ist massegewichtet passend zur
WLS. **Die Unsicherheit von s selbst geht nirgends in die Bänder ein** —
`var_achse` wird aus den Residuen *vor* der Smearing-Korrektur gebildet.

### 6.4 „Die Freiheitsgrade in t_quantil_95 — woher kommt die Zahl?“

`t_quantil_95(p_df)` (setup.sql:1347) ist eine 29-Elemente-Tabelle:
df < 1 oder NULL → 12.706; df ≥ 30 → 1.960; sonst Tabellenwert.
Die Werte sind korrekt (zweiseitiges 95-%-t-Quantil).
15 Aufrufstellen in setup.sql, 4 Stellen benutzen weiterhin fest 1.96.

Woher df kommt, je Stelle:

| Stelle | df | gemessen | Urteil |
|---|---|---|---|
| `v_schimmel_modell.t_faktor` | `c_chargen − 1` = 32 | 1.960 | **richtig** — Chargen sind die unabhängigen Einheiten |
| `schimmelanteil()` | dasselbe | 1.960 | richtig |
| Koeffizient je Sorte (setup.sql:6082) | `round(b·C_eigen + (1−b)·C_gesamt) − 1`, Boden 1 | 1 … 32 | plausibel konstruiert |
| `v_verlust_je_gruppe`, Var_f | `c_chargen − 1` = 32 | — | richtig |
| `v_verlust_je_gruppe`, Var_r / Var_a | **`min` über alle Sorten der Gruppe** (8654/8664) | **1** | **falsch** — siehe 4 |
| `v_verlust_je_gruppe`, gesamt | `LEAST(df_r, df_a, df_f)` (8754) | **1** | **falsch** |
| `sockel_schwelle` (6561) | `max(C−3, 1)` = 30 | 1.960 | siehe 6.5 |
| `sockel_var` (6754) | `c_chargen − 1` = 32 | 1.960 | Gitterartefakt, siehe 3.3 |
| `v_koeff_gebinde` | `n − 1` mit n = Zahl der **Arbeiten** | 0 … 8 | Arbeiten, nicht Chargen — Cluster nicht berücksichtigt |
| `v_koeff_ueberfuellung`, `v_schimmel_kurve`, `selektions_versatz`, `sockel_oben_kg` | **fest 1.96** | — | inkonsistent |

Die entscheidende Zahl ist **1** — und sie kommt nicht aus der Statistik,
sondern aus einer `min()`-Aggregation über Sorten ohne Gewichtung.

### 6.5 „Der Sockel a₀ mit seinem Nachweis-Test“

- **Schwelle:** `1 + t(max(C−3,1))² / max(C−3,1)`, C = distinkte Chargen der
  Rohpunkte = 33 → **1.128**.
- **Test:** `SSE(a₀=0) > Schwelle · min(SSE)`. Das ist die Extra-Sum-of-Squares-Form
  eines F-Tests für **einen** Zusatzparameter mit F_{0.95,1,df} = t(df)².
- **Was passiert bei Nichtnachweis:** `wahl` liefert keine Zeile, `gewaehlt.a0`
  fällt per `coalesce` auf **0**, `sockel = 0`. Das Modell rechnet dann weiter
  mit dem Fit bei a₀ = 0. **`a0_bekannt` bleibt trotzdem `true`** (es ist
  identisch mit `brauchbar`, mv_kaskade CTE `teile`), und
  `v_hochrechnung_basis` nennt die Spalte `sockel_nachgewiesen` — sie ist
  `bool_and(a0_bekannt)`, also **true, obwohl nichts nachgewiesen wurde**.
- **Gemessen:** `sockel_nachweis = 1.000` gegen `sockel_schwelle = 1.128`.
  Der Nachweis scheitert deutlich; das Minimum liegt bei a₀ = 0.

**Drei Probleme mit dem Test, jedes belegt:**

1. **df-Wahl.** Der Nenner der F-Statistik ist SSE über **140 gewichtete
   Punkte**, die df aber `C − 3 = 30` Chargen. Ein Cluster-Korrektiv ist
   sinnvoll, aber dann müsste auch der Zähler cluster-robust sein. Mit
   n − 3 = 137 wäre die Schwelle 1 + 3.8416/137 = 1.028 statt 1.128 —
   **der Test wäre 3.6-mal schärfer**.
2. **Kriterienmischung.** a₀ wird über SSE im **Originalraum** gewählt,
   k und lnλ über WLS im **Log-Log-Raum**. Zwei Zielfunktionen im selben Fit.
3. **Wechselnde Stichprobe.** Siehe 3.3: 140 Punkte bei a₀ = 0, 9 bei a₀ = 0.10.
   SSE-Werte über das Gitter sind schlicht nicht dieselbe Grösse.

### 6.6 „Wo werden Koeffizienten über Sorten gepoolt, und wonach gewichtet?“

Nur an einer Stelle, aber zweimal kopiert:
`v_koeff_verdunstung_geschaetzt` (6001) und `v_koeff_kaliber_geschaetzt` (6909).

- **Gewichtung innerhalb einer Sorte:** nach Masse (w = `basis_kg` /
  `netto_jetzt_kg` / `masse_kg + faul_kg`) — Verhältnis der Summen.
- **Gewichtung zwischen Sorten:** James-Stein/Empirical-Bayes,
  `b = τ²/(τ² + V_eigen)`, wobei
  `τ² = Σ Sw_s(mittel_s − mittel_ges)²/Σ Sw_s − avg_s(V_s)`.

**Zwei Ungereimtheiten in τ², gemessen:**

- Der **erste** Summand ist massegewichtet, der **zweite** (`avg(v.varianz)`)
  ist ein *ungewichteter* Mittelwert und läuft nur über Sorten mit
  C_eigen > 1. Für Verdunstung sind das **3 von 11 Sorten** (Butterkin,
  Mieluna, Tiana); die Sorten mit genau einer Charge (Kaori Kuri, Lekor,
  Orangita) gehen in den ersten Summanden ein, in den zweiten nicht.
  **Folge: τ² ist nach oben verzerrt**, b wird zu gross, es wird zu wenig
  gepoolt. Gemessen: τ² = 1.0963e-8 gegen V_gesamt = 5.604e-10 — Faktor 19.6.
  Die Shrinkage schrumpft praktisch nicht: b = 0.9679 / 1.0000 / 0.9936 für
  die drei Sorten mit eigenen Daten.
- **`b = 0` heisst nicht „keine Daten“.** Kaori Kuri hat n = 1 Wiegung
  (C = 1 → V_eigen = NULL → b = 0), bekommt den Gesamtwert — aber
  `v_koeff_verdunstung.n` zeigt **1**, und `basis` sagt „Wiegungen aller
  Sorten“. In `v_verlust_je_gruppe` wird daraus `koeff_n_min = 0` für
  Verdunstung, obwohl der Wert auf 41 Wiegungen ruht.

**Und die schärfste Folge des Poolens:** `r_bekannt = (kv.mittel is not null)`.
Da `mittel` durch den Gesamtwert nie NULL ist, ist **`r_bekannt` für jede
Sorte true, sobald irgendwo in der Saison eine einzige Wiegung existiert.**
Dasselbe für `a_klein_bekannt`, `a_gross_bekannt`, `a_fax_bekannt` —
und damit für `verlust_bekannt` in `v_hochrechnung_basis` und
`v_saisonbilanz.verlust_bekannt`, das Tor, hinter dem die Saisonzahl
überhaupt erst erscheint. Gemessen: 6 von 11 Sorten haben 0 eigene
Verdunstungswiegungen, alle 6 gelten als „bekannt“.

---

## 7. Der einzige unabhängige Abgleich — und was er sagt

`v_saisonbilanz.bilanz_rest_kg` ist **kein** Test. Gemessen: **−0.01 kg** auf
323 268 kg. Ich habe nachgerechnet, dass das eine Identität ist:

- Zeilenweise gilt exakt (Restsumme = 0, auf alle Nachkommastellen):
  `m₀ = Verdunstung + Sockel + Schimmel + Klein + Nebenkanal + Fax + Verkaufsfähig`
  und für ausgelagerte Zeilen `Verkaufsfähig = geliefert_kg`.
- Gegenprobe: rechnet man die ganze Bilanz mit **verdoppelter** Rate r durch
  (Verdunstung springt von 23 530 kg auf **45 268 kg**, +92 %), bleibt der
  Bilanzrest **0.0000 kg** (Anhang F).

**`bilanz_rest_kg` kann einen Koeffizientenfehler beliebiger Grösse nicht
entdecken.** Es entdeckt nur Rundung.

Der einzige echte Aussenabgleich ist `v_massenbilanz` (setup.sql:8167): das
Modell sagt die Masse am Sortierband voraus,

    modell_am_band_kg = am_band_kg · (1−r)^alter_band · (1−a₀) · (1−f(alter_band)) · anteil_mit_csv

und vergleicht sie mit der aus den Sortier-CSV summierten Masse.

**Gemessen über 36 Chargen, davon 25 vergleichbar:**

| | Wert |
|---|---|
| Mittlere Abweichung `abweichung_anteil` | **+0.1103** (+11.03 %) |
| Streuung | 0.2157 |
| Spanne | −0.0512 … **+0.4924** |
| Summe gemessen | 108 383.3 kg |
| Summe Modell | 99 066.6 kg |
| **Summe Abweichung** | **+9 316.7 kg (+9.40 %)** |

`select count(*), count(abweichung_anteil), round(avg(abweichung_anteil),4), round(stddev_samp(abweichung_anteil),4), round(min(abweichung_anteil),4), round(max(abweichung_anteil),4), round(sum(abweichung_kg),1), round(sum(csv_gemessen_kg),1), round(sum(modell_am_band_kg),1) from v_massenbilanz;`

9 316.7 kg sind **2.9 % des Saisoneingangs** und **17.9 % des ausgewiesenen
Gesamtverlusts von 52 119.4 kg**. Nichts im System erhebt das zum Befund:
`v_plausibilitaet` liefert 22 Zeilen, keine davon betrifft die Massenbilanz
(`select art, count(*) from v_plausibilitaet group by 1` → Schimmel 2,
Ohne Nenner 1, Palox geleert 4, Kistengewicht 3, Zetteldatum 1,
Lieferung in der Zukunft 1, Überzählung 10).

Gegenrede, ernst gemeint: die beiden Seiten sind nicht sauber deckungsgleich
(`anteil_mit_csv` skaliert auf CSV-Abdeckung, `alter_band` ist ein
massegewichtetes Mittel, die CSV wiegen auch Ausschuss mit). Die +11 % können
also Definition statt Modell sein. **Aber genau das ist der Punkt: es ist die
einzige Aussenprüfung, und niemand hat entschieden, was ihr Wert bedeutet.**

---

## 8. Numerik und Rundung

**Wo überhaupt gerundet wird.** `mv_kaskade` ist durchgehend unbeschränktes
`numeric` (48 Spalten geprüft). Gerundet wird an fünf Stellen:

| Stelle | Rundung | Wirkung gemessen |
|---|---|---|
| `mv_hochrechnung.kg` | `zahl(x)` → `numeric(14,2)`, 1 197 Zeilen | Summe 66 622.4700 kg, Drift < 0.01 kg |
| `mv_hochrechnung.koeffizient` | `numeric(12,6)` | **nur Anzeige** — die Gradienten `d_r`, `d_eta`, `d_a`, `d_a0` sind ungerundet. Kein Rechenweg betroffen. Aber r ≈ 0.000518 auf 6 Stellen heisst 0.1 % Auflösung |
| `v_lieferung_kohorte.alter_tage` | `numeric(8,1)` | 0.05 Tage je Kohorte |
| `v_kohorte_anteil.anteil` | `numeric(10,6)` | **gemessen:** 2 von 36 Chargen summieren auf 0.999999 bzw. 1.000001 statt 1 — max. Abweichung **1e-6**, in Kilo bei der grössten Charge unter 0.02 kg |
| `v_saisonbilanz`, `v_hochrechnung_basis` | `numeric(14,2)` | Bilanzrest −0.01 kg über 36 Chargen |

**Auslöschung.** `bilanz_rest_kg = 323 268 + 4 179.88 − 115 836.33 − 52 119.38
− 4 946.81 − 154 545.37 = −0.01`. Sieben Stellen Auslöschung — aber in
`numeric` (Dezimal-Arithmetik beliebiger Genauigkeit), also **kein**
Gleitkommaproblem. Die einzigen `double precision`-Stellen im Rechenweg sind
`v_koeff_*.unten/oben` und `v_koeff_ueberfuellung` (Casts nach
`double precision` für `sqrt`) — dort ist die Genauigkeit ~1e-16 relativ,
belanglos.

**Überlaufgrenze von `zahl(x, stellen, grenze)`.** Die Funktion gibt
`round(x, stellen)` zurück, wenn `abs(x) < grenze`. Bei den 15 Aufrufen mit
`grenze = 1e12` und Ziel `numeric(14,2)` ist die Grenze **exakt** die
Typgrenze, also um eine halbe letzte Stelle zu gross. Nachgewiesen:

```
select zahl(999999999999.996::numeric, 2, 1e12)::numeric(14,2);
ERROR:  numeric field overflow
```

Erreichbar wäre das bei einer Saison von **1e12 kg = 1 Milliarde Tonnen**.
Beziffert und verworfen. Die Aufrufe mit `grenze = 1e5` auf `numeric(8,1)`
(Typgrenze 9 999 999.9) und der Standard `1e11` auf `numeric(14,2)` haben
Luft von Faktor 100 bzw. 10 — dort ist `zahl()` ein **Plausibilitätsdeckel**,
kein Überlaufschutz. Das ist zwei verschiedene Aufgaben in einer Funktion.

**Nicht gemessen:** die dreifache Saison. Dafür fehlt mir ein Generator, der
`demo_daten_laden()` skaliert; `demo_daten_laden()` (setup.sql:3214, 715 Zeilen)
ist auf feste Werte geschrieben.

---

## 9. Namen, die etwas anderes meinen

Für Werkstatt D wichtig, weil der Betriebsleiter genau diese Wörter liest:

| Spalte / Text | Was dasteht | Was es misst | Beleg |
|---|---|---|---|
| `sockel_nachgewiesen` | „der Sockel ist nachgewiesen“ | `bool_and(a0_bekannt)` = `brauchbar` — **unabhängig vom Nachweistest**; ist in der Demo `true` bei a₀ = 0 und `sockel_nachweis` 1.000 < 1.128 | v_hochrechnung_basis |
| `verlust_bekannt` | „alle Koeffizienten gemessen“ | „irgendwo in der Saison existiert je Art mindestens eine Messung“ | 6.6 |
| `koeff_n_min` | Zahl der Messungen hinter dem Koeffizienten | eigene Messungen der schwächsten Sorte, **0** für Verdunstung, obwohl 41 Wiegungen dahinterstehen | v_verlust_je_gruppe |
| `bilanz_rest_kg` | „Bilanz geht auf“ | eine Identität; unabhängig von jedem Koeffizientenwert | 7 |
| `kg_unten` / `kg_oben` | 95-%-Bereich | ± **12.706** σ, nicht 1.96 σ; der df kommt aus einer Sorte mit 0.0024 % Varianzanteil | 4 |
| `sd` in `v_schimmel_kurve` | Streuung des Klassenanteils | ungewichtete Streuung der Einzelanteile bei massegewichtetem Punktschätzer | 3.4 |
| „Verzerrung Schimmel“ in STATISTIK_BEFUND | Zeile 276: „systematisch zu niedrig“; Zeile 604: „rund 10 % zu hoch“ | widersprüchlich; Zeile 276 nie nachgeführt | docs |

---

## 10. Was Werkstatt A als Nächstes messen müsste (Reihenfolge nach Hebel)

1. **df-Regel.** Ein Werkzeug, das für die sechs Ströme sowohl
   `min(df)` als auch Welch-Satterthwaite rechnet und die Überdeckung gegen
   simulierte Wahrheiten misst. Erwarteter Hebel: **38 535 kg Bandbreite**.
2. **a₀-Kopplung.** Profil-Likelihood über das a₀-Gitter mit jeweils neu
   geschätztem (k, lnλ), Band aus dem Profil statt aus `sockel_var`.
   Erwarteter Hebel: Varianzterm ×13.
3. **a₀-Gitter mit fester Punktmenge.** SSE nur über die Punkte, die bei
   *jedem* a₀ überleben, oder Straffunktion für verlorene Punkte.
4. **Klammertest.** Wahrheit r ∈ {0.0005 … 0.01}, t bis 250 Tage, messen ab
   wann `greatest(A, 0.25)` greift und wie gross die Verzerrung dann ist.
5. **Massenbilanz-Diskrepanz.** Definitionsabgleich zwischen
   `modell_am_band_kg` und `csv_gemessen_kg`; 9 317 kg müssen erklärt sein,
   bevor die Saisonzahl belastbar heisst.
6. **Treppenlücken und 1.96.** Vier Zeilen SQL, aber nur mit Selbstprobe.

---

## Anhang: die Messbefehle im Wortlaut

**A — SSE-Kurve über das a₀-Gitter nachgerechnet** (bestätigt die Modellwerte
bei a₀ = 0 auf 4 Stellen):

```sql
with roh as (select b.charge_nr, b.lagertage t, b.anteil f, b.basis_jetzt_kg w,
       b.quelle='verarbeitung' mit_sockel
  from mv_schimmel_punkte b
 where b.plausibel and b.anteil>0 and b.anteil<1 and b.lagertage>0
   and b.quelle in ('verarbeitung','lager')),
gitter as (select i*0.0025 a0 from generate_series(0,40) i),
kand as (select g.a0, r.charge_nr, r.t, r.f, r.w, r.mit_sockel, ln(r.t) x,
   case when r.mit_sockel then (r.f-g.a0)/(1-g.a0) else r.f end fs
   from gitter g cross join roh r),
fit as (select q.a0, count(*)::int n, count(distinct q.charge_nr)::int c_chargen,
   sum(q.w) sw, sum(q.w*q.x) swx, sum(q.w*q.y) swy,
   sum(q.w*q.x*q.x) swxx, sum(q.w*q.x*q.y) swxy
  from (select a0,charge_nr,w,x, ln(-ln(1-fs)) y from kand where fs>0 and fs<1) q
 group by q.a0),
param2 as (select f.*, k, case when k is not null then (f.swy-k*f.swx)/f.sw end ln_lambda
  from fit f cross join lateral (select case when (f.sw*f.swxx-f.swx*f.swx)<>0
       then (f.sw*f.swxy-f.swx*f.swy)/(f.sw*f.swxx-f.swx*f.swx) end k) kk),
smear as (select p.a0, sum(k.w*exp(ln(-ln(1-k.fs))-(p.ln_lambda+p.k*k.x)))/nullif(sum(k.w),0) s
  from param2 p join kand k on k.a0=p.a0
 where k.fs>0 and k.fs<1 and p.k is not null group by p.a0)
select p.a0, p.n, p.c_chargen, round(p.k,4), round(p.ln_lambda,4), round(s.s,4),
  round(sum(k.w*power(k.f-(case when k.mit_sockel then p.a0 else 0 end
    + (1-case when k.mit_sockel then p.a0 else 0 end)
      *(1-exp(-exp(least(greatest(p.ln_lambda+ln(greatest(s.s,0.01))+p.k*k.x,-40),3))))),2)),2) sse
 from param2 p join smear s on s.a0=p.a0 join kand k on k.a0=p.a0
where p.k is not null and p.k>0 and p.n>=3
group by p.a0,p.n,p.c_chargen,p.k,p.ln_lambda,s.s order by p.a0;
```

**B — Sensitivität von Sockel + Schimmel gegenüber einem a₀-Gitterschritt:**

```sql
with p as (select 0::numeric a0, 1.2208654423025489::numeric k, -8.510307342232018::numeric lnl
     union all select 0.0025, 1.4771, -9.7230
     union all select 0.0050, 1.7925, -11.2719+ln(1.0706)
     union all select 0.0075, 2.0064, -12.3286+ln(1.0982))
select p.a0, round(p.k,4) k, round(sum(k2.m1*p.a0),1) sockel_kg,
  round(sum(k2.m1*(1-p.a0)*(1-exp(-exp(least(greatest(p.lnl+p.k*ln(greatest(k2.alter_tage,1)),-40),3))))),1) schimmel_kg
 from p cross join mv_kaskade k2 where k2.portion<>'entsorgt'
group by p.a0,p.k,p.lnl order by p.a0;
```

**C — Punkte, die durch die Treppenlücken fallen:**

```sql
select lagertage, anteil, quelle from mv_schimmel_punkte b
 where b.anteil is not null and b.plausibel and b.quelle in ('verarbeitung','lager')
   and not exists (select 1 from (values (0,14),(15,30),(31,60),(61,90),(91,120),
                                        (121,180),(181,100000)) k(von,bis)
                    where b.lagertage>=k.von and b.lagertage<=k.bis);
-- → 90.7 / 30.5, beide quelle='verarbeitung'
select count(*) filter (where lagertage <> trunc(lagertage)), count(*)
  from mv_schimmel_punkte where plausibel;   -- → 80 von 140
```

**D — Varianzblöcke ausserhalb der Ansicht nachgebaut** (trifft jede Streuung
exakt; liefert zugleich Welch-Satterthwaite) — der vollständige Befehl steht in
Abschnitt 4; Kern:

```sql
select strom, round(sqrt(sum(v)),2) sd, min(df) df_ist,
       round(power(sum(v),2)/nullif(sum(power(v,2)/greatest(df,1)),0),1) df_satterthwaite
  from alle where v>0 group by strom;
-- Fax 56.51 / 1 / 38.9 · Nebenkanal 227.32 / 1 / 33.5 · Sockel 193.83 / 32 / 32.0
-- Schimmel 1279.15 / 1 / 32.1 · Verdunstung 364.50 / 1 / 21.7 · Klein 190.77 / 1 / 14.9
```

**E — Verhältnis-Verzerrung nach der Delta-Methode:** vollständige Abfrage
über `mv_kaskade × v_koeff_unsicherheit × v_schimmel_modell` mit
Var(A) = Σ (∂A/∂θ)²Var(θ) und ∂A/∂r = −A·t/(1−r) usw.
Ergebnis: sd(A) 0.00404 / VK 0.48 % / Verzerrung 0.0029 % / **+4.6 kg**.

**F — Bilanzrest bei verdoppeltem r:**

```sql
with x as (select k.*, 2*k.r r2 from mv_kaskade k),
y as (select portion, m0, alter_tage, a0, f, a_klein_n, a_gross_n, a_fax, geliefert_kg,
        m0*power(1-r2,alter_tage) m1n from x)
select round(sum(m0-m1n),2) verdunstung_neu,
  round(sum(m0) - sum(m0-m1n) - sum(m1n*a0) - sum(m1n*(1-a0)*f)
        - sum(case when portion='ausgelagert' then m1n*(1-a0)*(1-f)*(a_klein_n+a_gross_n) else 0 end)
        - sum(case when portion='ausgelagert' then m1n*(1-a0)*(1-f)*(1-a_klein_n-a_gross_n)*a_fax else 0 end)
        - sum(case when portion='lager' then m1n*(1-a0)*(1-f) else 0 end)
        - sum(case when portion='ausgelagert' then m1n*(1-a0)*(1-f)*(1-a_klein_n-a_gross_n)*(1-a_fax) else 0 end),4)
  from y;
-- → 45267.73 kg Verdunstung, Bilanzrest 0.0000
```
