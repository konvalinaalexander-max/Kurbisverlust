# Entwürfe Runde P — gegen die Demo gerechnet, noch nicht angewendet

Zwei Sichten, an denen Runde P hängt (`docs/PLAN_RUNDE_P.md` §3). Beide sind
am 13. September als temporäre Sichten gegen die Demo-Datenbank (Schema 70,
Stand 11.09.) gelaufen. Sie gehören **wörtlich** in Migration 0071; was der
Plan darüber hinaus verlangt (Band, Rate je Tag, Primärschlüssel), kommt
dazu.

| Datei | Was | Ergebnis auf der Demo |
|---|---|---|
| `v_prognose.sql` | Die Kaskade (`mv_kaskade`, Portion „lager") bei heute + h ausgewertet, h ∈ {0, 7, 14, 28, 56, 84}, je Gruppe (gesamt, sorte, schlag, charge) | h = 0 gesamt: lager 187 775.36 kg, verkaufsfähig 144 073.82, gute Ware 153 567.92, Kanal 7 143.76, Fax erwartet 2 350.34, verdunstet 15 887.46, faul 18 319.98 — identisch mit `erg_bilanz` / `erg_verlust` (kg_projiziert) bis auf 2 Rappen Rundung je Charge. Anteil verkaufsfähig: 76.7 → 76.0 → 75.4 → 74.0 → 71.4 → 68.8 %. Charge 1632 bei h = 0: 29 310.33 / 22 586.49 = `erg_charge`. |
| `v_wohin.sql` | Der Eingang je Gruppe aufgeteilt: ausgeliefert, anderer Kanal, verdunstet/faul an der ausgelieferten Ware, Fax, im Lager (davon verkaufsfähig, Kanal, Fax erwartet, faul, verdunstet) | 61 Gruppenzeilen; `rest_kg` und `lager_rest_kg` beide ≤ 0.03 kg. Gesamt: 323 268 + 4 179 = 116 404 + 4 979 + 7 808 + 8 054 + 2 426 + 187 775. |

So wurde geprüft (in einer Transaktion, danach zurückgerollt):

```
U="postgresql://postgres@/demo?host=/tmp/pgsock&port=55432"
psql "$U" -v ON_ERROR_STOP=1 -c "begin;
  $(sed 's/create or replace view v_prognose with (security_invoker = true) as/create temp view p_entwurf as/' docs/entwurf_runde_p/v_prognose.sql);
  select * from p_entwurf where gruppe = 'gesamt' order by h;
  select lager_kg, verkaufsfaehig_heute_kg, im_haus_heute_kg, kanal_im_haus_kg, fax_erwartet_kg from erg_bilanz;
  rollback;"
```

Wer eine Formel darin ändert, rechnet diese Zahlen neu und schreibt sie hier hin.
