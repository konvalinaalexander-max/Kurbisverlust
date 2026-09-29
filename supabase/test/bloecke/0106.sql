
-- =====================================================================
-- 0106 — Die Kaskade rechnet mit den Stationswerten
--
-- Geprüft auf der Demo: (a) die Zusammensetzung palox_f über den Weg der
-- Charge, Fall für Fall, und NULL, sobald eine Station auf dem Weg keinen
-- Wert hat; (b) der Weg je Charge — von Hand, über das Band, gewaschen —
-- aus den eigenen Arbeiten, sonst denen der Sorte; (c) jede Zeile der
-- Kaskade ist die Zusammensetzung aus Weg und Stationswerten, für
-- Ausgelagertes die eigene Messung vor der Erwartung; (d) ohne eine
-- einzige Messung ist das Faule unbekannt, nicht 0 — in Kaskade, Charge,
-- Bilanz und Prognose; (e) die Prognose schreibt mit dem Zuwachs je
-- Station fort, und nur, wenn die Kennzahl ihn ausweist; ohne Zuwachs
-- steht der Anteil still, faul_je_tag_kg und die Zwei-Wochen-Zahl sind
-- leer; (f) das Modell ist weg — Sichten, Funktionen, Spalten, Schritte;
-- (g) erg_charge sagt, womit es rechnet und woher; (h) Stand 106.
-- =====================================================================
do $$
declare v_modus jsonb; v_lad text; v_geladen boolean := false; r record; v_n int; v_ab int; v_txt text; v_bis date; v_diff numeric;
  v_u uuid := '00000000-0106-0000-0000-000000000001';
begin
  select wert into v_modus from einstellung where schluessel = 'betriebsmodus';
  update einstellung set wert = '"beispiel"'::jsonb where schluessel = 'betriebsmodus';
  insert into auth.users (id, email, raw_user_meta_data) values (v_u, null, '{"name":"Prüf-0106"}');
  update profil set rolle = 'admin' where id = v_u;
  perform set_config('request.jwt.claim.sub', v_u::text, true);
  if not exists (select 1 from auftrag where station = 'waschen_sortieren' and bemerkung = 'DEMO') then
    select demo_daten_laden() into v_lad; v_geladen := true;
  end if;
  perform auswertung_aktualisieren();

  -- (a) die Zusammensetzung
  assert palox_f(1, 0, 0.05, null, null) = 0.05, '0106 (a1): nur von Hand → f_W+S';
  assert palox_f(0, 0, null, 0.02, null) = 0.02, '0106 (a2): nur Band, ungewaschen → f_S';
  assert abs(palox_f(0, 1, null, 0.02, 0.05) - (0.02 + 0.98 * 0.05)) < 1e-12, '0106 (a3): Band, dann gewaschen → f_S + (1 − f_S)·g_W';
  assert abs(palox_f(0.25, 1, 0.04, 0.02, 0.05) - (0.25 * 0.04 + 0.75 * (0.02 + 0.98 * 0.05))) < 1e-12, '0106 (a4): gemischter Weg';
  assert palox_f(null, 1, 0.04, 0.02, 0.05) is null, '0106 (a5): ohne Weg kein Anteil';
  assert palox_f(0.5, 1, null, 0.02, 0.05) is null, '0106 (a6): Hand auf dem Weg, aber kein Handwert → unbekannt';
  assert palox_f(0, 1, null, 0.02, null) is null, '0106 (a7): gewaschen, aber kein Waschwert → unbekannt';
  assert palox_f(0, 0, null, 0.02, null) is not null, '0106 (a8): ungewaschen braucht keinen Waschwert';
  assert palox_f(1, 0, 1.5, null, null) = 1, '0106 (a9): nie über 1';
  assert abs(palox_f_nach(0, 1, 0.02, 0.02, 0.05, 0.01, 0.01, 0.01, 14) - (0.04 + 0.96 * 0.07)) < 1e-12,
    '0106 (a10): zwei Wochen später ist jede Station um zwei Wochen Zuwachs weiter';
  assert palox_f_nach(0, 1, null, 0.02, 0.05, null, -0.1, null, 70) = palox_f(0, 1, null, 0, 0.05),
    '0106 (a11): ein Zuwachs führt nie unter 0';

  -- (b) der Weg
  assert exists (select 1 from v_charge_weg where p_hand = 1 and weg_quelle = 'eigenen Arbeiten'), '0106 (b1): keine Charge nur von Hand';
  assert exists (select 1 from v_charge_weg where p_hand = 0 and p_wasch = 1 and weg_quelle = 'eigenen Arbeiten'), '0106 (b2): keine Charge über Band und Waschstrasse';
  assert exists (select 1 from v_charge_weg where weg_quelle = 'Arbeiten der Sorte'), '0106 (b3): keine Charge, die den Weg von ihrer Sorte erbt';
  assert not exists (select 1 from v_charge_weg where p_hand < 0 or p_hand > 1 or p_wasch not in (0, 1)), '0106 (b4): Weg ausserhalb 0..1';
  assert not exists (select 1 from v_charge_weg w where w.p_hand = 1 and w.band_kg > 0), '0106 (b5): Bandware, aber Weg ganz von Hand';
  -- (b10) wer den Weg von der Sorte erbt, bekommt genau ihren Anteil von Hand — nachgerechnet aus den Arbeiten
  select count(*), count(*) filter (where abs(w.p_hand - x.p_hand) > 1e-9)
    into v_n, v_ab
    from v_charge_weg w
    join lateral (
      select sum(a.eingang_netto_kg) filter (where a.station = 'waschen_sortieren')
             / nullif(sum(a.eingang_netto_kg) filter (where a.station in ('waschen_sortieren', 'sortieren')), 0) as p_hand
        from v_auftrag_masse a where a.sorte = w.sorte and a.eingang_netto_kg > 0
    ) x on true
   where w.weg_quelle = 'Arbeiten der Sorte';
  assert v_n > 0 and v_ab = 0, format('0106 (b10): bei %s von %s Chargen ist der geerbte Weg nicht der Weg der Sorte', v_ab, v_n);

  -- (b6) die Erwartung ist das massegewichtete Mittel — unabhängig nachgerechnet
  select count(*), count(*) filter (where abs(anteil - nachgerechnet) > 1e-4)
    into v_n, v_ab
    from (select e.anteil,
                 (select sum(p.basis_jetzt_kg * p.anteil_station) / nullif(sum(p.basis_jetzt_kg), 0)
                    from v_schimmel_punkte p
                   where p.plausibel_station and p.anteil_station is not null and p.basis_jetzt_kg > 0
                     and p.station = e.station and p.quelle in ('verarbeitung', 'verarbeitung_gemischt')
                     and (e.ebene like 'alle%' or p.sorte = e.sorte)
                     and (e.ebene like '%saison' or p.messtag > heute() - 28)) as nachgerechnet
            from v_palox_erwartung e) x;
  assert v_n > 0 and v_ab = 0, format('0106 (b6): %s von %s Erwartungen sind nicht das massegewichtete Mittel ihrer Ebene', v_ab, v_n);
  assert palox_mindest_arbeiten() = 3, '0106 (b7): ein Wert der Sorte gilt ab drei Arbeiten';
  assert not exists (select 1 from v_palox_erwartung where ebene like 'sorte%' and n_arbeiten < 3), '0106 (b8): ein Wert der Sorte aus weniger als drei Arbeiten';
  assert not exists (select 1 from v_palox_erwartung where (ebene like 'alle%') <> geliehen), '0106 (b9): geliehen passt nicht zur Ebene';

  -- (c) die Kaskade ist die Zusammensetzung
  with nach as (
    select k.charge_nr, k.portion, k.f, k.f_bekannt, k.schimmel_kg, k.m1,
           palox_f(w.p_hand, w.p_wasch,
                   case when k.portion = 'lager' then ews.anteil else coalesce(pws.anteil, ews.anteil) end,
                   case when k.portion = 'lager' then es.anteil  else coalesce(ps.anteil,  es.anteil)  end,
                   case when k.portion = 'lager' then ew.anteil  else coalesce(pw.anteil,  ew.anteil)  end) as f_nach
      from mv_kaskade k
      join v_charge_weg w on w.charge_nr = k.charge_nr
      left join v_palox_erwartung ews on ews.sorte = k.sorte and ews.station = 'waschen_sortieren'
      left join v_palox_erwartung es  on es.sorte  = k.sorte and es.station  = 'sortieren'
      left join v_palox_erwartung ew  on ew.sorte  = k.sorte and ew.station  = 'waschen'
      left join v_charge_palox pws on pws.charge_nr = k.charge_nr and pws.station = 'waschen_sortieren'
      left join v_charge_palox ps  on ps.charge_nr  = k.charge_nr and ps.station  = 'sortieren'
      left join v_charge_palox pw  on pw.charge_nr  = k.charge_nr and pw.station  = 'waschen'
  )
  select count(*), count(*) filter (where abs(f - coalesce(f_nach, 0)) > 1e-9 or f_bekannt <> (f_nach is not null)
                                       or (portion <> 'entsorgt' and abs(schimmel_kg - m1 * f) > 1e-6))
    into v_n, v_ab from nach;
  assert v_n > 0 and v_ab = 0, format('0106 (c1): %s von %s Kaskadenzeilen sind nicht die Zusammensetzung aus Weg und Stationswerten', v_ab, v_n);
  assert exists (select 1 from mv_kaskade k join v_charge_palox p on p.charge_nr = k.charge_nr
                  where k.portion = 'ausgelagert' and k.f_quelle like '%eigene Messung%'),
    '0106 (c2): keine ausgelagerte Portion rechnet mit der eigenen Messung';
  assert exists (select 1 from mv_kaskade where portion = 'lager' and f_quelle like '%Sorte%'),
    '0106 (c3): keine liegende Portion rechnet mit der Erwartung der Sorte';
  assert not exists (select 1 from mv_kaskade where f_bekannt and f_quelle is null), '0106 (c4): ein bekannter Anteil ohne Quelle';

  -- (d) ohne Messung ist das Faule unbekannt — nicht 0
  create temp table punkte_alle on commit drop as select id from schimmel_messung where gemessen;
  update schimmel_messung set gemessen = false;
  perform auswertung_aktualisieren();
  assert (select count(*) from v_palox_erwartung) = 0, '0106 (d1): ohne Messung gibt es eine Erwartung';
  assert not exists (select 1 from mv_kaskade where f_bekannt), '0106 (d2): ohne Messung gilt ein Anteil als bekannt';
  assert not exists (select 1 from erg_charge where schimmel_heute_kg is not null or verlust_bekannt), '0106 (d3): eine Charge kennt ihr Faules ohne Messung';
  assert (select schimmel_heute_kg is null and not verlust_bekannt from erg_bilanz), '0106 (d4): die Bilanz kennt das Faule ohne Messung';
  assert not exists (select 1 from erg_prognose where f_bekannt or vollstaendig), '0106 (d5): die Prognose kennt das Faule ohne Messung';
  update schimmel_messung set gemessen = true where id in (select id from punkte_alle);
  perform auswertung_aktualisieren();
  assert exists (select 1 from mv_kaskade where f_bekannt), '0106 (d6): nach dem Zurückstellen ist nichts bekannt — die Probe hat Spuren hinterlassen';

  -- (e) die Prognose schreibt mit dem Zuwachs fort
  assert exists (select 1 from erg_prognose where gruppe = 'gesamt' and h = 0 and zuwachs_bekannt),
    '0106 (e0): auf der Demo ist der Zuwachs bekannt — sonst prüft (e) nichts';
  with nach as (
    select k.charge_nr,
           sum(k.m0 * power(1 - k.r, k.alter_tage + 28)
               * coalesce(palox_f_nach(k.p_hand, k.p_wasch, k.f_ws, k.f_s, k.g_w, k.b_ws, k.b_s, k.b_w, 28), k.f)) as faul_28
      from mv_kaskade k
     where k.portion = 'lager' and k.m0 > 0 and k.alter_tage >= 0 and k.zuwachs_bekannt
     group by k.charge_nr
  )
  select count(*), count(*) filter (where abs(p.faul_kg - n.faul_28) > 0.05)
    into v_n, v_ab
    from nach n join erg_prognose p on p.gruppe = 'charge' and p.schluessel = n.charge_nr::text and p.h = 28;
  assert v_n > 0 and v_ab = 0, format('0106 (e1): bei %s von %s Chargen ist das Faule in 28 Tagen nicht der fortgeschriebene Anteil', v_ab, v_n);
  assert (select faul_je_tag_kg is not null from erg_prognose where gruppe = 'gesamt' and h = 0), '0106 (e2): mit Zuwachs keine Rate des Faulen';
  assert not exists (select 1 from erg_prognose where verlust_faeulnis_kg < -0.005), '0106 (e3): Fäulnis-Verlust negativ';
  assert exists (select 1 from v_naechste_charge where schimmel_14_kg is not null and prognose_verlust_14_kg is not null),
    '0106 (e4): mit Zuwachs keine Zwei-Wochen-Zahl';
  -- der Verlauf: das Faule an einem Wochenende in der Prognose ist die Summe
  -- der Portionen mit dem verschobenen Anteil — unabhängig nachgerechnet
  select min(bis) into v_bis from erg_verlauf where bis >= heute() + 28;
  with nach as (
    select sum(k.m0 * power(1 - k.r, t.t) * f.f) as schimmel
      from mv_kaskade k
      cross join lateral (select case when k.portion = 'ausgelagert' then k.kohorte + round(k.alter_tage)::int end as liefertag) l
      cross join lateral (select greatest(least(v_bis, coalesce(l.liefertag, v_bis)) - k.kohorte, 0) as t) t
      cross join lateral (select case when k.zuwachs_bekannt
                                      then coalesce(palox_f_nach(k.p_hand, k.p_wasch, k.f_ws, k.f_s, k.g_w, k.b_ws, k.b_s, k.b_w,
                                                                 (least(v_bis, coalesce(l.liefertag, v_bis)) - coalesce(l.liefertag, heute()))::numeric), k.f)
                                      else k.f end as f) f
     where k.m0 > 0 and k.kohorte is not null and k.kohorte <= v_bis
  )
  select abs((select schimmel_kum_kg from erg_verlauf where gruppe = 'gesamt' and bis = v_bis) - schimmel)
    into v_diff from nach;
  assert v_diff < 1, format('0106 (e5): der Verlauf am %s weicht um %s kg vom fortgeschriebenen Faulen ab', v_bis, round(v_diff, 1));
  -- Ohne Zuwachs (Messungen nur aus den ersten 20 Tagen je Station) steht der Anteil still.
  create temp table punkte_spaet on commit drop as
    select m.id from schimmel_messung m join auftrag a on a.id = m.auftrag_id
     where m.gemessen
       and betriebstag(a.start_ts) > (select min(betriebstag(a2.start_ts)) from auftrag a2 join schimmel_messung m2 on m2.auftrag_id = a2.id
                                        where m2.gemessen and a2.station = a.station) + 20;
  update schimmel_messung set gemessen = false where id in (select id from punkte_spaet);
  perform auswertung_aktualisieren();
  assert not exists (select 1 from v_palox_station where zuwachs_je_woche is not null), '0106 (e6): nach 20 Tagen weist die Kennzahl schon einen Zuwachs aus';
  assert exists (select 1 from mv_kaskade where portion = 'lager' and f_bekannt), '0106 (e7): die Probe hat alle Werte gelöscht — sie trägt nicht';
  assert not exists (select 1 from mv_kaskade where zuwachs_bekannt), '0106 (e8): ohne Zuwachs gilt er als bekannt';
  assert (select faul_je_tag_kg is null from erg_prognose where gruppe = 'gesamt' and h = 0), '0106 (e9): ohne Zuwachs eine Rate des Faulen — erfunden';
  assert (select verlust_faeulnis_kg = 0 and faul_kg > 0 from erg_prognose where gruppe = 'gesamt' and h = 28),
    '0106 (e10): ohne Zuwachs steht der Anteil still — das Faule bleibt, wächst aber nicht';
  assert not exists (select 1 from v_naechste_charge where schimmel_14_kg is not null or prognose_verlust_14_kg is not null),
    '0106 (e11): ohne Zuwachs eine Zwei-Wochen-Zahl — erfunden';
  update schimmel_messung set gemessen = true where id in (select id from punkte_spaet);
  perform auswertung_aktualisieren();

  -- (f) das Modell ist weg
  foreach v_txt in array array['v_schimmel_modell', 'mv_schimmel_modell', 'v_schimmel_modell_rechnen', 'v_schimmel_kurve',
                              'v_schimmel_kurve_anzeige', 'v_selektionsverdacht', 'v_verderb_lage', 'erg_modell', 'erg_kurve',
                              'erg_selektion', 'mv_schimmel_punkte'] loop
    assert to_regclass('public.' || v_txt) is null, format('0106 (f1): %s gibt es noch', v_txt);
  end loop;
  assert to_regprocedure('public.schimmelanteil(numeric, text)') is null and to_regprocedure('public.sockel_anteil()') is null,
    '0106 (f2): schimmelanteil() oder sockel_anteil() gibt es noch';
  assert not exists (select 1 from auswertung_schluessel() where sicht in ('erg_modell', 'erg_kurve', 'erg_selektion', 'mv_schimmel_modell', 'mv_schimmel_punkte')),
    '0106 (f3): der Zeitplan kennt noch Modellsichten';
  assert not exists (select 1 from information_schema.columns
                      where table_name in ('erg_charge', 'erg_bilanz', 'erg_prognose', 'erg_wohin', 'erg_verlauf', 'mv_kaskade', 'mv_hochrechnung')
                        and (column_name like 'sockel%' or column_name in ('a0', 'modell_gilt', 'hochgerechnet', 'f_extrapoliert', 'd_f_eta', 'd_eta', 'd_a0'))),
    '0106 (f4): eine Sockel- oder Modellspalte ist noch da';
  assert not exists (select 1 from v_verlust_ranking where strom = 'Nicht lagerbedingt' or buch = 'feld'), '0106 (f5): der Strom „Nicht lagerbedingt" steht noch';
  assert (select count(*) from jsonb_array_elements(auswertung_diagnose() -> 'langsamste')) >= 0, '0106 (f6): die Diagnose läuft nicht mehr';

  -- (g) erg_charge sagt, womit es rechnet
  assert not exists (select 1 from erg_charge where schimmel_bekannt and lager_kg > 0 and (faul_anteil is null or faul_quelle is null)),
    '0106 (g1): eine Charge mit Faulem, aber ohne Anteil oder Quelle';
  assert not exists (select 1 from erg_charge where faul_anteil < 0 or faul_anteil > 1), '0106 (g2): faul_anteil ausserhalb 0..1';
  assert not exists (select 1 from erg_charge where verlust_bekannt
                        and abs(verlust_heute_kg - (verdunstung_heute_kg + schimmel_heute_kg + fax_heute_kg)) > 0.05),
    '0106 (g3): Verlust bis heute ≠ Verdunstung + Faules + Fax';
  assert (select abs(sum(schimmel_heute_kg) - (select schimmel_heute_kg from erg_bilanz)) < 1 from erg_charge), '0106 (g4): Bilanz und Chargen nennen verschiedenes Faules';

  assert schema_stand() >= 106, format('0106 (h1): schema_stand() = %s', schema_stand());

  if v_geladen then perform demo_daten_entfernen(); end if;
  delete from profil where id = v_u; delete from auth.users where id = v_u;
  update einstellung set wert = v_modus where schluessel = 'betriebsmodus';
  raise notice 'OK  0106 — die Kaskade rechnet mit den Stationswerten: Zusammensetzung über den Weg, eigene Messung vor Erwartung, unbekannt ohne Messung, Prognose mit dem Zuwachs der Kennzahl, das Modell ist weg';
end $$;

select '——— 0106 Kaskade auf Stationswerten geprüft ———' as ergebnis;
