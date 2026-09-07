-- =====================================================================
-- 0051 — Vier Fehler aus der Halle: Fax, Kaliber am Start, Alter ohne
--        FIFO, und die Perigon-Nummer der Charge
--
-- Der Betrieb hat am 7. September vier Dinge klargestellt, die die App
-- bis hierher anders verstanden hatte.
--
-- ---------- 1. Fax ist kein Waschgang -------------------------------------
-- Beim Fax wird nicht gewaschen. Die gewaschene Ware steht in Kisten, bis
-- eine Bestellung kommt; dann werden Etiketten angebracht und dabei wird
-- nochmals Faules aussortiert. Am Ende weiss der Arbeiter zweierlei: wie
-- viele Kisten er gemacht hat („eine Palette mit 32 Kisten, dann noch 10")
-- und wie viel Faules dabei herauskam — gewogen, kistenweise, mit Gebinde
-- („2 Kisten mit 7.5 und 8.5 kg in G2"). Kein Palox, kein zu klein/zu gross.
--
-- Bis 0050 lief Fax als Waschgang (Station waschen, ist_fax). Das war
-- doppelt falsch: Die Fax-Masse zählte als *gewaschen* und schob damit die
-- Charge ein zweites Mal aus dem Lager, und das Faule ging als Punkt in die
-- Verderbskurve — obwohl es nichts mit der Lagerdauer zu tun hat, sondern
-- mit dem Waschen und dem Stehen danach (ABLAUF.md kannte das längst).
--
-- Jetzt: Fax bleibt an der Station waschen (kein neuer Enum-Wert — der wäre
-- in der einen Transaktion von setup.sql nicht verwendbar), aber überall,
-- wo Waschen gerechnet wird, ist Fax ausgenommen. Faules wird als Wägung
-- erfasst (brutto, Kisten, Gebinde, mit/ohne Palette), das Netto rechnet
-- ein Auslöser — dieselbe Regel wie beim Ausschuss (0044). Und Fax bekommt
-- den eigenen Strom, den ABLAUF.md verlangt: „Faul beim Abpacken", ein
-- Koeffizient je Sorte, bezogen auf die verkaufsfähige Masse, nicht auf die
-- Zeit. Er steht in Buch A, mit Bereich, mit Fehlerfortpflanzung.
--
-- ---------- 2. Die Maschine sortiert immer nach Kaliber -------------------
-- Die Frage „Kiste ab x kg oder Kaliber?" gibt es beim Sortieren nicht — die
-- Maschine kennt nur Bänder. Die Frage, die es gibt, ist: *welche* Bänder
-- sind heute eingestellt? Das fragt die App ab jetzt beim Eröffnen, mit der
-- letzten Einstellung als Vorschlag („wie zuletzt — übernehmen / anpassen").
-- Bei Waschen + Sortieren von Hand ebenso: Kiste ab x kg (welches x?) oder
-- Kaliber (welche Bänder?). Was der Vorarbeiter bestätigt, ist die Fassung,
-- nach der die Arbeit läuft; was er ändert, wird eine neue, datierte Fassung
-- (sortierschema_festlegen). Nichts wird überschrieben — ausser die Fassung
-- desselben Tages, denn zweimal am selben Tag ist dieselbe Einstellung.
--
-- ---------- 3. Es gibt kein FIFO ------------------------------------------
-- Der Eingang einer Charge verteilt sich über Wochen, der Ausgang auch, und
-- welche Palette wann drankommt, hängt davon ab, an welche man herankommt.
-- Gespeichert war das schon richtig: jede Palette mit ihrem Eingangsdatum,
-- jede gezählte Palette mit dem Datum vom Zettel. Gerechnet wurde aber mit
-- *einem* Alter je Charge — dem massegewichteten Mittel der übrigen
-- Paletten (0036). Bei einer Kurve, die mit dem Alter steiler wird, ist das
-- Mittel zu wenig: Der Bestand wird jetzt je Eingangstag geführt
-- (v_charge_kohorte: Paletten des Tages minus gezählte Paletten des Tages)
-- und die Kaskade rechnet den Lagerbestand je Kohorte mit ihrem eigenen
-- Alter. Aus „liegt seit 143 Tagen" wird „liegt seit 128–161 Tagen, 4
-- Eingangstage". v_naechste_charge rechnet ebenso je Kohorte.
--
-- ---------- 4. Die sechsstellige Chargennummer ist unsere -----------------
-- Die Planungsdatei des Betriebs führt je Schlag und Sorte beide Nummern:
-- die vierstellige (Bioprodukte) und die sechsstellige aus dem Perigon der
-- anderen Firma (AG). 232 von 236 Kürbiszeilen der AG-Datei seit Juli 2026
-- tragen eine Nummer aus dieser Liste — der Chargenbezug ist also da, er
-- war nur nicht hinterlegt. Ab jetzt steht die Perigon-Nummer an der Charge.
-- Eine Nummer (198976) steht in der Planung an zwei Chargen (1649 Butterkin
-- und 1650 Tiana, beide Rümlang Sauter); dort entscheidet der Artikel.
-- =====================================================================

-- ---------- 4. Perigon-Nummer je Charge ----------------------------------
alter table charge add column if not exists perigon_nr int;
comment on column charge.perigon_nr is
  'Chargennummer derselben Ware im Perigon der Firma AG (sechsstellig). Aus der '
  'Planungsdatei des Betriebs; nicht eindeutig (198976 steht an zwei Chargen).';
create index if not exists charge_perigon on charge (perigon_nr) where perigon_nr is not null;

update charge c set perigon_nr = v.p
  from (values
    (1598, 198876), (1599, 198877), (1601, 198888), (1603, 198915), (1604, 198916),
    (1605, 198917), (1606, 198919), (1607, 198889), (1608, 198920), (1609, 198918),
    (1610, 198921), (1611, 198922), (1612, 198944), (1613, 198923), (1614, 198945),
    (1615, 198946), (1616, 198947), (1617, 198948), (1618, 198949), (1619, 198950),
    (1620, 198951), (1623, 198955), (1624, 198956), (1625, 198957), (1626, 198958),
    (1627, 198959), (1628, 198970), (1630, 198969), (1631, 198968), (1632, 198960),
    (1633, 198961), (1634, 198962), (1635, 198963), (1636, 198966), (1637, 198964),
    (1638, 198965), (1646, 198952), (1647, 198953), (1648, 198974), (1649, 198976),
    (1650, 198976), (1651, 198975)) as v(nr, p)
 where c.nr = v.nr and c.perigon_nr is null;

-- Der Artikelvorschlag des Imports kennt jetzt beide Nummern. Bei der einen
-- doppelten Perigon-Nummer nimmt die Sicht die kleinere Charge — die
-- Entscheidung trifft der Import nach dem Artikel, hier zählt nur der Beleg.
create or replace view v_ausgang_artikel_vorschlag with (security_invoker = true) as
with zeile_charge as (
  select z.id, z.artikel_id, z.artikel, z.datum, z.kg_charge, c.nr as charge_nr, c.sorte
    from ausgang_zeile z
    cross join lateral (
      select nullif(regexp_replace(z.charge_extern, '\D', '', 'g'), '')::bigint as nummer) x
    left join lateral (
      select c.nr, c.sorte from charge c
       where x.nummer is not null and (c.nr = x.nummer or c.perigon_nr = x.nummer)
       order by (c.nr = x.nummer) desc, c.nr limit 1) c on true
), beobachtet as (
  select artikel_id, artikel,
         count(*)::int                                   as zeilen,
         min(datum)                                      as von,
         max(datum)                                      as bis,
         sum(kg_charge)                                  as kg,
         count(*) filter (where charge_nr is not null)::int as zeilen_mit_charge
    from zeile_charge
   group by artikel_id, artikel
), sorte_je_artikel as (
  select distinct on (artikel_id, artikel)
         artikel_id, artikel, sorte, count(*)::int as n
    from zeile_charge where charge_nr is not null
   group by artikel_id, artikel, sorte
   order by artikel_id, artikel, count(*) desc, sorte
)
select b.artikel_id, b.artikel, b.zeilen, b.von, b.bis,
       b.kg::numeric(14,1)                               as kg,
       b.zeilen_mit_charge,
       a.ist_kuerbis                                     as bestaetigt_kuerbis,
       a.sorte                                           as bestaetigte_sorte,
       (a.artikel_id is not null)                        as bestaetigt,
       (lower(b.artikel_id || ' ' || b.artikel) ~ 'k(ü|u|ue)rb'
        and lower(b.artikel_id || ' ' || b.artikel) !~ '(verrechnung|arbeit|lohn|transport|miete)')
                                                         as vorschlag_kuerbis,
       s.sorte                                           as vorschlag_sorte,
       s.n                                               as vorschlag_belege
  from beobachtet b
  left join ausgang_artikel a on a.artikel_id = b.artikel_id and a.artikel = b.artikel
  left join sorte_je_artikel s on s.artikel_id = b.artikel_id and s.artikel = b.artikel;

-- ---------- Eine Palette sind 32 Kisten ----------------------------------
-- Aus der Planungsdatei („Anzahl Paletten à 32 G2"). Der Zähler beim Fax
-- bietet „+ 1 Palette" an und zählt damit diese Zahl Kisten.
insert into einstellung (schluessel, wert)
values ('kisten_pro_palette', '32'::jsonb)
on conflict (schluessel) do nothing;

-- ---------- 1a. Faules wird gewogen: Brutto, Kisten, Gebinde ------------
alter table schimmel_messung add column if not exists brutto_kg   numeric(10,2);
alter table schimmel_messung add column if not exists kisten      int;
alter table schimmel_messung add column if not exists gebindeart  text references gebinde(art);
alter table schimmel_messung add column if not exists mit_palette boolean not null default false;
comment on column schimmel_messung.brutto_kg is
  'Waagenstand einer Kiste (oder mehrerer auf einer Palette) mit Faulem, brutto. '
  'Ist er gesetzt, ist kg das daraus abgeleitete Netto; palox_stand_kg bleibt leer. '
  'Beim Fax die einzige Art, Faules zu erfassen.';
comment on column schimmel_messung.mit_palette is
  'true: die Kisten standen beim Wiegen auf einer Palette, deren Tara mit abgeht. '
  'false: einzelne Kiste auf der Tischwaage.';

create or replace function schimmel_netto_setzen()
returns trigger language plpgsql as $$
declare v_tara_kiste numeric; v_tara_palette numeric;
begin
  if new.brutto_kg is not null then
    if new.palox_stand_kg is not null then
      raise exception 'Eine Messung ist entweder eine Palox-Ablesung oder eine Kistenwägung, nicht beides.';
    end if;
    select g.tara_kg_pro_kiste, coalesce(g.tara_kg_palette, 0)
      into v_tara_kiste, v_tara_palette
      from public.gebinde g where g.art = new.gebindeart;
    new.kg := greatest(round(new.brutto_kg
                - coalesce(new.kisten, 1) * coalesce(v_tara_kiste, 0)
                - case when new.mit_palette then coalesce(v_tara_palette, 0) else 0 end), 0);
    new.gemessen := true;
  end if;
  return new;
end $$;
revoke execute on function schimmel_netto_setzen() from public;
drop trigger if exists schimmel_netto on schimmel_messung;
create trigger schimmel_netto before insert or update on schimmel_messung
  for each row execute function schimmel_netto_setzen();

-- ---------- 1b. Kisten ohne Kaliber: Index −1 -----------------------------
-- Ware von der Hand-Linie („Kiste ab x kg") hat kein Kaliber. Wer sie beim
-- Fax zählt, zählt Kisten nach Sollgewicht — Index −1. Was so eine Kiste
-- wiegt, ist nicht das Soll, sondern die gewogene fertige Palette.
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_kaliber_idx_check;
alter table auftrag_gebinde drop constraint if exists auftrag_gebinde_kaliber_gueltig;
alter table auftrag_gebinde add constraint auftrag_gebinde_kaliber_gueltig
  check (kaliber_idx >= -1);
comment on column auftrag_gebinde.kaliber_idx is
  'Index in kaliber_baender der Fassung der Arbeit. −1 = Kisten nach Sollgewicht '
  '(ohne Kaliber), wie sie von der Hand-Linie kommen.';

alter table auftrag drop constraint if exists auftrag_fax_nur_waschen;
alter table auftrag add constraint auftrag_fax_nur_waschen
  check (not ist_fax or station = 'waschen') not valid;
comment on column auftrag.ist_fax is
  'Fax: Etikettieren und Abpacken nach Bestellung, dabei wird Faules aussortiert. '
  'Kein Waschgang — die Station bleibt nur technisch „waschen"; jede Rechnung, die '
  'Waschen meint, nimmt ist_fax aus (0051).';

create or replace view v_koeff_gebinde with (security_invoker = true) as
with je_arbeit as (
  select a.id as auftrag_id, c.sorte, g.kaliber_idx, g.anzahl,
         (sum(sg.anzahl::bigint * sg.gewicht_g) / 1000.0)::numeric as kg
    from auftrag_gebinde g
    join auftrag a       on a.id = g.auftrag_id and a.abgebrochen_ts is null
    join charge c        on c.nr = a.charge_nr
    join sortier_lauf l  on l.auftrag_id = a.id
    join sortier_gewicht sg on sg.lauf_id = l.id
                           and sg.klasse = 'kaliber'
                           and sg.kaliber_idx = g.kaliber_idx
   where a.station in ('sortieren', 'waschen_sortieren') and g.anzahl > 0
   group by a.id, c.sorte, g.kaliber_idx, g.anzahl
), s as (
  select sorte, kaliber_idx, count(*)::int as n,
         sum(kg) / nullif(sum(anzahl), 0)   as kg_je_gebinde,
         stddev_samp(kg / anzahl)           as sd
    from je_arbeit group by sorte, kaliber_idx
  union all
  -- Kisten nach Sollgewicht: gemessen an den fertigen Paletten der Arbeiten,
  -- die als „Kiste ab x kg" liefen (nur dort gibt es ein Soll).
  select k.sorte, -1, count(*)::int,
         sum(k.netto_kg) / nullif(sum(k.kisten), 0),
         stddev_samp(k.kg_pro_kiste)
    from v_ausgang_kennzahl k
   where k.soll_kg_pro_kiste is not null
   group by k.sorte
)
select sorte, kaliber_idx, n,
       kg_je_gebinde::numeric(10,3)                                     as kg_je_gebinde,
       sd::numeric(10,3)                                                as sd,
       (case when sd is null or n < 2 then kg_je_gebinde
             else greatest(kg_je_gebinde - t_quantil_95(n - 1) * sd / sqrt(n), 0)
        end)::numeric(10,3)                                             as unten,
       (case when sd is null or n < 2 then kg_je_gebinde
             else kg_je_gebinde + t_quantil_95(n - 1) * sd / sqrt(n)
        end)::numeric(10,3)                                             as oben
  from s where kg_je_gebinde is not null;
comment on view v_koeff_gebinde is
  'Wie viel eine Kiste wiegt, je Sorte und Kaliber — gemessen am Sortieren aus '
  'CSV-Masse und gezählten Kisten. Kaliber −1: Kisten nach Sollgewicht, gemessen '
  'an den gewogenen fertigen Paletten. Ohne Messung steht hier keine Zeile.';

-- ---------- 1c. Die Masse je Arbeit kennt Fax ----------------------------
create or replace view v_auftrag_masse with (security_invoker = true) as
select m.auftrag_id, m.charge_nr, m.sorte, m.schlag, m.weg, m.station,
       m.start_ts, m.ende_ts, m.status, m.n_paletten,
       coalesce(m.eingang_netto_kg, gb.kg)::numeric                     as eingang_netto_kg,
       (case when m.masse_quelle <> 'fehlt' then m.masse_quelle
             when gb.kg is not null         then 'gebinde'
             else 'fehlt' end)::text                                    as masse_quelle,
       coalesce(m.lagertage,
         case when m.station = 'waschen'
              then (m.start_ts::date - date '2000-01-01')::numeric
                   - coalesce(se.tage_seit_epoche,
                              (r.eingangsdatum_mittel - date '2000-01-01')::numeric)
              else null end)::numeric(10,1)                             as lagertage,
       a.ist_fax
  from mv_auftrag_masse m
  join auftrag a on a.id = m.auftrag_id
  left join mv_sortier_eingang se on se.charge_nr = m.charge_nr
  left join v_charge_rueckgrat r  on r.charge_nr  = m.charge_nr
  left join (select auftrag_id, sum(kg) as kg from v_auftrag_gebinde_masse group by auftrag_id) gb
         on gb.auftrag_id = m.auftrag_id;
comment on view v_auftrag_masse is
  'Masse je Arbeit aus drei Quellen: gewogene Paletten, eingetippter Durchsatz, '
  'gezählte Kisten mal gemessenem Kistengewicht. ist_fax: die Arbeit ist ein Fax '
  '(Abpacken), kein Waschgang — sie zählt nicht als gewaschen.';

-- Schimmel je Arbeit: Fax-Faules bleibt beobachtbar (Plausibilität), geht aber
-- nicht in die Verderbskurve.
create or replace view v_schimmel_beobachtung with (security_invoker = true) as
select am.auftrag_id, am.charge_nr, am.sorte, am.schlag, am.weg, am.station,
       am.start_ts, am.lagertage, am.masse_quelle,
       s.kg                                                        as schimmel_kg,
       am.eingang_netto_kg                                         as eingang_kg,
       (am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage))::numeric(12,2)
                                                                   as basis_jetzt_kg,
       (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))
                                                                   as anteil,
       anteil_plausibel(
         (s.kg / nullif(am.eingang_netto_kg * power(1 - coalesce(kv.mittel, 0), am.lagertage), 0))::numeric
       )                                                           as plausibel,
       am.ist_fax
  from v_auftrag_masse am
  join v_schimmel_menge s on s.auftrag_id = am.auftrag_id
  left join v_koeff_verdunstung kv on kv.sorte = am.sorte
 where am.eingang_netto_kg is not null
   and am.lagertage is not null;

create or replace view v_schimmel_punkte with (security_invoker = true) as
with sortier_lauf_anteil as materialized (
  select b.charge_nr, b.start_ts, b.schimmel_kg, b.basis_jetzt_kg
    from v_schimmel_beobachtung b
   where b.station = 'sortieren' and b.plausibel and b.anteil is not null
), gemischt as (
  select auftrag_id from v_auftrag_angabe where schluessel = 'eine_charge' and wert = 'false'
)
select b.charge_nr, b.sorte, b.schlag, b.lagertage, b.schimmel_kg,
       b.basis_jetzt_kg, b.anteil, b.plausibel,
       case when g.auftrag_id is not null then 'verarbeitung_gemischt' else 'verarbeitung' end::text as quelle,
       b.auftrag_id
  from v_schimmel_beobachtung b
  left join gemischt g on g.auftrag_id = b.auftrag_id
 where b.station in ('sortieren', 'waschen_sortieren')
union all
select a.charge_nr, a.sorte, a.schlag, a.lagertage,
       s.kg                                                      as schimmel_kg,
       (a.eingang_netto_kg + s.kg)                               as basis_jetzt_kg,
       k.f2                                                      as anteil,
       anteil_plausibel(k.f2)                                    as plausibel,
       case when g.auftrag_id is not null then 'verarbeitung_gemischt' else 'verarbeitung' end,
       a.auftrag_id
  from v_auftrag_masse a
  join v_schimmel_menge s on s.auftrag_id = a.auftrag_id
  left join gemischt g on g.auftrag_id = a.auftrag_id
  left join lateral (
    select sum(sl.schimmel_kg) / nullif(sum(sl.basis_jetzt_kg), 0) as f1
      from sortier_lauf_anteil sl
     where sl.charge_nr = a.charge_nr and sl.start_ts <= a.start_ts
  ) sa on true
  cross join lateral (
    select s.kg / nullif(a.eingang_netto_kg + s.kg, 0)            as g
  ) x
  cross join lateral (
    select 1 - (1 - least(greatest(coalesce(sa.f1, 0), 0), 0.99))
             * (1 - least(greatest(coalesce(x.g, 0), 0), 0.99))   as f2
  ) k
 where a.station = 'waschen' and not a.ist_fax and a.lagertage is not null
   and a.eingang_netto_kg is not null and a.eingang_netto_kg > 0
union all
select w.charge_nr, w.sorte, w.schlag, w.lagertage,
       v.faul_kg, w.netto_jetzt_kg,
       v.faul_kg / nullif(w.netto_jetzt_kg, 0),
       anteil_plausibel(v.faul_kg / nullif(w.netto_jetzt_kg, 0)),
       'lager', null::bigint
  from v_verdunstung_messung w
  join verdunstung_wiegung v on v.id = w.id
 where v.faul_kg is not null and v.gemessen
   and w.netto_jetzt_kg > 0 and w.lagertage > 0;
comment on view v_schimmel_punkte is
  'Die Punkte des Verderbsmodells: aus der Verarbeitung (Palox) und aus '
  'Lagerkontrollen. Fax-Faules fehlt hier absichtlich — es hängt nicht an der '
  'Lagerdauer (v_fax_beobachtung).';

-- ---------- 1d. Der Fax-Strom: je Arbeit beobachtet, je Sorte geschätzt ----
create or replace view v_fax_beobachtung with (security_invoker = true) as
select a.id as auftrag_id, a.charge_nr, c.sorte, c.schlag, a.kaeufer, a.start_ts, a.ende_ts,
       a.status, a.abgebrochen_ts,
       m.eingang_netto_kg                                            as masse_kg,
       m.masse_quelle,
       coalesce(g.kisten, 0)                                         as kisten,
       coalesce(s.kg, 0)::numeric                                    as faul_kg,
       (s.auftrag_id is not null)                                    as faul_erfasst,
       (coalesce(s.kg, 0) / nullif(m.eingang_netto_kg + coalesce(s.kg, 0), 0))::numeric(10,5)
                                                                     as anteil,
       anteil_plausibel((coalesce(s.kg, 0)
                         / nullif(m.eingang_netto_kg + coalesce(s.kg, 0), 0))::numeric)
                                                                     as plausibel
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_auftrag_masse m on m.auftrag_id = a.id
  left join v_schimmel_menge s on s.auftrag_id = a.id
  left join (select auftrag_id, sum(anzahl)::int as kisten from auftrag_gebinde group by auftrag_id) g
         on g.auftrag_id = a.id
 where a.ist_fax and a.abgebrochen_ts is null;
comment on view v_fax_beobachtung is
  'Je Fax-Arbeit: gemachte Kisten, daraus die Masse, das gewogene Faule und sein '
  'Anteil an dem, was durch die Hände ging (Masse + Faules). Grundlage des Stroms '
  '„Faul beim Abpacken".';
grant select on v_fax_beobachtung to authenticated;

-- Der Rohwert läuft durch denselben Schätzer wie zu klein und zu gross
-- (Bündelung je Sorte, Chargen-robuste Varianz) — art = 'fax'.
create or replace view v_koeff_roh_kaliber with (security_invoker = true) as
select 'ausschuss'::text as art, b.sorte, b.charge_nr,
       b.klein_kg / b.basis_kg as anteil, b.basis_kg as gewicht
  from v_ausschuss_beobachtung b
 where b.plausibel and b.basis_kg > 0 and b.klein_kg is not null
union all
select 'nebenkanal', b.sorte, b.charge_nr,
       b.gross_kg / b.basis_kg, b.basis_kg
  from v_ausschuss_beobachtung b
 where b.plausibel and b.basis_kg > 0 and b.gross_kg is not null
union all
select 'fax', f.sorte, f.charge_nr,
       f.anteil::numeric, (f.masse_kg + f.faul_kg)::numeric(12,2)
  from v_fax_beobachtung f
 where f.plausibel and f.masse_kg > 0 and f.faul_erfasst and f.status = 'abgeschlossen';
comment on view v_koeff_roh_kaliber is
  'Koeffizienten-Rohwerte in einheitlicher Form: Anteil, die Masse, die er '
  'vertritt, und die Charge, aus der er stammt. ausschuss, nebenkanal, fax.';

create or replace view v_koeff_fax with (security_invoker = true) as
select sk.sorte,
       k.mittel::numeric                                                    as mittel,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else greatest(k.mittel - k.t * sqrt(k.varianz), 0)
        end)::double precision                                              as unten,
       (case when coalesce(k.varianz, 0) = 0 then k.mittel
             else least(k.mittel + k.t * sqrt(k.varianz), 1)
        end)::double precision                                              as oben,
       coalesce(k.n, 0)                                                     as n,
       case when coalesce(k.n_gesamt, 0) = 0 then 'keine Fax-Arbeit mit gewogenem Faulem'
            when k.b >= 0.67     then 'Fax-Arbeiten dieser Sorte'
            when k.b >= 0.33     then 'eigene Fax-Arbeiten, zum Gesamtwert gezogen'
            else 'alle Sorten (zu wenige eigene Chargen)' end               as basis
  from sorte_kaliber sk
  left join lateral (
    select g.*, t_quantil_95(g.df) as t
      from v_koeff_kaliber_geschaetzt g
     where g.art = 'fax' and g.sorte is not distinct from sk.sorte
  ) k on true;
comment on view v_koeff_fax is
  'Anteil Faules beim Abpacken (Fax), je Sorte — bezogen auf die Masse, die durch '
  'das Fax ging. NULL, solange keine Fax-Arbeit Faules gewogen hat: unbekannt, nicht 0.';
grant select on v_koeff_fax to authenticated;

-- ---------- 3a. Der Bestand je Eingangstag ---------------------------------
create or replace view v_charge_kohorte with (security_invoker = true) as
with gezaehlt as (
  select a.charge_nr,
         coalesce(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum) as eingangsdatum,
         count(*)::int                                                 as n
    from auftrag_palette ap
    join auftrag a on a.id = ap.auftrag_id
    left join palette p on p.id = ap.palette_id
    left join verdunstung_wiegung w on w.id = ap.wiegung_id
   where a.abgebrochen_ts is null
     and a.station in ('sortieren', 'waschen_sortieren')
   group by a.charge_nr, coalesce(p.eingangsdatum, w.eingangsdatum, ap.eingangsdatum)
), je_datum as (
  select p.charge_nr, p.eingangsdatum, count(*)::int as n,
         avg(p.netto_kg) as netto_mittel
    from v_palette p group by p.charge_nr, p.eingangsdatum
), charge_netto as (
  select charge_nr, avg(netto_kg) as netto from v_palette group by charge_nr
)
select d.charge_nr, d.eingangsdatum,
       d.n                                                      as n_paletten,
       coalesce(g.n, 0)                                         as n_verarbeitet,
       greatest(d.n - coalesce(g.n, 0), 0)                      as n_rest,
       coalesce(d.netto_mittel, cn.netto)::numeric(10,2)        as netto_je_palette,
       (greatest(d.n - coalesce(g.n, 0), 0)
        * coalesce(d.netto_mittel, cn.netto))::numeric(12,2)    as rest_kg,
       (current_date - d.eingangsdatum)                         as alter_heute
  from je_datum d
  join charge_netto cn on cn.charge_nr = d.charge_nr
  left join gezaehlt g on g.charge_nr = d.charge_nr and g.eingangsdatum = d.eingangsdatum;
comment on view v_charge_kohorte is
  'Je Charge und Eingangstag: wie viele Paletten kamen, wie viele davon wurden '
  'seither mit diesem Zetteldatum gezählt, wie viele liegen also noch. Kein FIFO — '
  'die gezählten Daten sagen, welche Paletten weg sind.';
grant select on v_charge_kohorte to authenticated;

-- Der Anteil jeder Kohorte am liegenden Bestand. Die Masse selbst kommt aus
-- der Massenrechnung (lager_kg); die Kohorten verteilen sie auf die Alter.
create or replace view v_kohorte_anteil with (security_invoker = true) as
select charge_nr, eingangsdatum, n_rest, rest_kg,
       (rest_kg / sum(rest_kg) over (partition by charge_nr))::numeric(10,6) as anteil
  from v_charge_kohorte
 where rest_kg > 0;
grant select on v_kohorte_anteil to authenticated;

-- ---------- 3b. Die Basis: Fax raus, Alter als Spanne --------------------
create or replace view v_hochrechnung_basis with (security_invoker = true) as
with stichtag as (
  select greatest((select (wert #>> '{}')::date from einstellung
                    where schluessel = 'saison_ende'), current_date) as bis
), je_station as (
  select charge_nr,
         sum(eingang_netto_kg) filter (where station = 'sortieren')          as sortiert_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen' and not ist_fax) as gewaschen_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren')  as hand_kg,
         sum(eingang_netto_kg) filter (where station = 'waschen_sortieren'
                                         and weg = 'hand')                   as kg_hand,
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('waschen', 'waschen_sortieren') and not ist_fax
               and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('waschen', 'waschen_sortieren') and not ist_fax
                 and lagertage is not null), 0)
                                                                             as alter_ende,
         sum(eingang_netto_kg * lagertage) filter (where lagertage is not null and not ist_fax)
           / nullif(sum(eingang_netto_kg) filter (where lagertage is not null and not ist_fax), 0)
                                                                             as alter_irgendwas,
         sum(eingang_netto_kg * lagertage) filter (
             where station in ('sortieren', 'waschen_sortieren') and lagertage is not null)
           / nullif(sum(eingang_netto_kg) filter (
               where station in ('sortieren', 'waschen_sortieren') and lagertage is not null), 0)
                                                                             as alter_band,
         sum(eingang_netto_kg) filter (where station in ('sortieren', 'waschen_sortieren'))
                                                                             as am_band_kg
    from v_auftrag_masse
   where eingang_netto_kg is not null
   group by charge_nr
), anteil as (
  select s.*,
         least(coalesce(s.gewaschen_kg, 0) / nullif(s.sortiert_kg, 0), 1)     as anteil_gewaschen
    from je_station s
), kohorte as (
  select k.charge_nr,
         min(k.eingangsdatum)                                     as eingang_von,
         max(k.eingangsdatum)                                     as eingang_bis,
         count(*)::int                                            as n_eingangstage,
         min(k.eingangsdatum) filter (where k.n_rest > 0)         as rest_von,
         max(k.eingangsdatum) filter (where k.n_rest > 0)         as rest_bis,
         coalesce(sum(k.n_rest), 0)::int                          as n_rest_paletten,
         count(*) filter (where k.n_rest > 0)::int                as n_rest_kohorten,
         sum(k.n_verarbeitet)::int                                as n_gezaehlt_mit_datum,
         -- massegewichtetes Datum der übrigen Paletten
         sum(k.rest_kg * (k.eingangsdatum - date '2000-01-01'))
           / nullif(sum(k.rest_kg), 0)                            as tage_seit_epoche
    from v_charge_kohorte k
   group by k.charge_nr
)
select r.charge_nr, r.schlag, r.sorte,
       r.eingang_netto_kg as eingang_kg,
       r.n_paletten,
       r.eingangsdatum_mittel,
       (coalesce(a.hand_kg, 0)
        + coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0))       as ausgelagert_kg,
       coalesce(a.alter_ende, a.alter_irgendwas)                              as alter_ausgelagert,
       greatest(r.eingang_netto_kg
                - coalesce(a.hand_kg, 0)
                - coalesce(a.sortiert_kg, 0) * coalesce(a.anteil_gewaschen, 0), 0)
                                                                              as lager_kg,
       (s.bis - x.rest_datum)::numeric                                        as alter_lager,
       (current_date - x.rest_datum)::numeric                                 as alter_lager_heute,
       coalesce(a.kg_hand / nullif(coalesce(a.hand_kg, 0)
                                   + coalesce(a.sortiert_kg, 0), 0), 0)       as weg2_anteil,
       s.bis                                                                  as stichtag,
       r.n_paletten_mit_netto,
       greatest(coalesce(a.hand_kg, 0) + coalesce(a.sortiert_kg, 0)
                - r.eingang_netto_kg, 0)                                      as ueberzaehlung_kg,
       coalesce(a.sortiert_kg, 0)                                             as sortiert_kg,
       coalesce(a.gewaschen_kg, 0)                                            as gewaschen_kg,
       (coalesce(a.sortiert_kg, 0) * (1 - coalesce(a.anteil_gewaschen, 0)))    as wartet_kg,
       coalesce(a.anteil_gewaschen, 0)                                        as anteil_gewaschen,
       a.alter_band,
       coalesce(a.am_band_kg, 0)                                              as am_band_kg,
       x.rest_datum                                                           as eingangsdatum_rest,
       (coalesce(k.n_gezaehlt_mit_datum, 0) > 0 and k.tage_seit_epoche is not null)
                                                                              as rest_alter_aus_zaehlung,
       -- neu (0051): die Spanne statt der einen Zahl
       k.eingang_von, k.eingang_bis, k.n_eingangstage,
       k.rest_von, k.rest_bis, k.n_rest_paletten, k.n_rest_kohorten,
       (current_date - k.rest_bis)::int                                       as alter_lager_von,
       (current_date - k.rest_von)::int                                       as alter_lager_bis
  from v_charge_rueckgrat r
  cross join stichtag s
  left join anteil a on a.charge_nr = r.charge_nr
  left join kohorte k on k.charge_nr = r.charge_nr
  cross join lateral (
    select case when k.tage_seit_epoche is not null
                then date '2000-01-01' + round(k.tage_seit_epoche)::int
                else r.eingangsdatum_mittel end as rest_datum
  ) x
 where r.eingang_netto_kg is not null;
comment on view v_hochrechnung_basis is
  'ausgelagert_kg ist die Masse, die den letzten Verarbeitungsschritt hinter '
  'sich hat — auf Weg 1 also erst nach dem Waschen; Fax zählt nicht als Waschen. '
  'alter_lager ist das massegewichtete Alter der noch liegenden Paletten; '
  'alter_lager_von/bis die Spanne (jüngste bis älteste Kohorte). Die Kaskade '
  'rechnet je Kohorte (v_kohorte_anteil), nicht mit dem Mittel.';

-- ---------- 3c. Die Kaskade je Kohorte, mit Fax-Strom --------------------
drop materialized view if exists mv_kaskade cascade;
drop view if exists v_saisonbilanz;
drop view if exists v_marge_buch;
drop view if exists v_massenbilanz;
drop view if exists v_verlust_ranking;

create materialized view mv_kaskade as
with modell as materialized (
  select * from v_schimmel_modell
),
kurve as materialized (
  select von, anteil_mono, n from v_schimmel_kurve where n > 0
),
kohorten as materialized (
  select charge_nr, eingangsdatum, anteil from v_kohorte_anteil
),
koeff as (
  select b.*,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05) as r,
         (kv.mittel is not null)                          as r_bekannt,
         kv.n as r_n, kv.basis as r_basis,
         least(greatest(coalesce(ka.mittel, 0), 0), 1)    as a_klein,
         (ka.mittel is not null)                          as a_klein_bekannt,
         ka.n as klein_n, ka.basis as klein_basis,
         least(greatest(coalesce(kn.mittel, 0), 0), 1)    as a_gross,
         (kn.mittel is not null)                          as a_gross_bekannt,
         kn.n as gross_n, kn.basis as gross_basis,
         least(greatest(coalesce(kf.mittel, 0), 0), 1)    as a_fax,
         (kf.mittel is not null)                          as a_fax_bekannt,
         kf.n as fax_n, kf.basis as fax_basis
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    left join v_koeff_ausschuss   ka on ka.sorte = b.sorte
    left join v_koeff_nebenkanal  kn on kn.sorte = b.sorte
    left join v_koeff_fax         kf on kf.sorte = b.sorte
),
koeff_norm as (
  select k.*, k.a_klein / n.f as a_klein_n, k.a_gross / n.f as a_gross_n
    from koeff k
    cross join lateral (select greatest(coalesce(k.a_klein, 0) + coalesce(k.a_gross, 0), 1) as f) n
),
teile as (
  select k.*, t.portion, t.m0, t.alter_tage, t.kohorte,
         ln(greatest(t.alter_tage, 1)) - coalesce(m.x_mittel, 0)        as u,
         case when m.brauchbar then
           m.ln_lambda_korrigiert + m.k * ln(greatest(t.alter_tage, 1))
         end                                                            as eta,
         m.brauchbar                                                    as modell_gilt,
         (m.brauchbar and t.alter_tage > m.t_max)                       as f_extrapoliert,
         case when m.brauchbar then m.c_chargen else s.n end            as f_n,
         s.anteil_mono                                                  as f_treppe,
         (m.brauchbar or (select count(*) from kurve) > 0)              as f_bekannt,
         case when m.brauchbar then coalesce(m.sockel, 0) else 0 end    as a0,
         m.brauchbar                                                    as a0_bekannt,
         case when m.brauchbar then coalesce(m.sockel_var, 0) else 0 end as a0_var
    from koeff_norm k
    cross join modell m
    -- Die Portionen: das Verarbeitete mit dem Alter am Tag der Verarbeitung;
    -- der Bestand je Eingangstag mit dem Alter bis zum Stichtag. Ohne
    -- datierte Kohorten (keine Palette mit Datum) bleibt es bei einem Alter.
    cross join lateral (
      select 'ausgelagert'::text as portion, k.ausgelagert_kg as m0,
             coalesce(k.alter_ausgelagert, 0)::numeric as alter_tage, null::date as kohorte
      union all
      select 'lager', k.lager_kg * c.anteil,
             greatest((k.stichtag - c.eingangsdatum)::numeric, 0), c.eingangsdatum
        from kohorten c where c.charge_nr = k.charge_nr and k.lager_kg > 0
      union all
      select 'lager', k.lager_kg, greatest(k.alter_lager, 0), null::date
       where k.lager_kg > 0
         and not exists (select 1 from kohorten c where c.charge_nr = k.charge_nr)
    ) as t
    left join lateral (
        select c.anteil_mono, c.n from kurve c
         where c.von <= t.alter_tage order by c.von desc limit 1
       ) s on true
   where t.m0 > 0
),
mit_f as (
  select t.*,
         case when t.modell_gilt
              then least(greatest(1 - exp(-exp(least(greatest(t.eta, -40), 3))), 0), 1)
              else least(greatest(coalesce(t.f_treppe, 0), 0), 1) end   as f
    from teile t
),
kaskade as (
  select t.*,
         (t.m0 * power(1 - t.r, t.alter_tage))                          as m1,
         (-t.m0 * t.alter_tage * power(1 - t.r, greatest(t.alter_tage - 1, 0))) as d_m1_r,
         case when t.modell_gilt
              then (1 - t.f) * exp(least(greatest(t.eta, -40), 3))
              else 0 end                                                as d_f_eta
    from mit_f t
)
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage, k.eingang_kg,
       k.m0, k.m1, (k.m1 * (1 - k.a0) * (1 - k.f)) as m2,
       k.r, k.f, k.a0, k.a_klein_n, k.a_gross_n, k.a_fax,
       k.u, k.d_m1_r, k.d_f_eta, k.modell_gilt, k.f_extrapoliert,
       k.r_n, k.r_basis, k.klein_n, k.klein_basis, k.gross_n, k.gross_basis, k.f_n,
       k.fax_n, k.fax_basis,
       k.r_bekannt, k.f_bekannt, k.a_klein_bekannt, k.a_gross_bekannt, k.a0_bekannt, k.a0_var,
       k.a_fax_bekannt,
       (k.m0 - k.m1)                                                     as verdunstung_kg,
       (k.m1 * k.a0)                                                     as sockel_kg,
       (k.m1 * (1 - k.a0) * k.f)                                         as schimmel_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * k.a_klein_n)                     as klein_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * k.a_gross_n)                     as nebenkanal_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n) * k.a_fax)
                                                                         as fax_kg,
       (k.m1 * (1 - k.a0) * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n) * (1 - k.a_fax))
                                                                         as verkaufsfaehig_kg,
       k.kohorte
  from kaskade k;

create unique index if not exists mv_kaskade_pk
  on mv_kaskade (charge_nr, portion, coalesce(kohorte, date '1900-01-01'));
create index if not exists mv_kaskade_charge on mv_kaskade (charge_nr);

create or replace view v_kaskade with (security_invoker = true) as
select * from mv_kaskade;
comment on view v_kaskade is
  'Die Massenkaskade je Charge und Portion; der Lagerbestand je Eingangstag '
  '(kohorte). Fax: Faules beim Abpacken, bezogen auf die verkaufsfähige Masse.';

create view v_hochrechnung with (security_invoker = true) as
select k.charge_nr, k.sorte, k.schlag, k.portion, k.alter_tage,
       k.eingang_kg, k.m0::numeric(14,2) as portion_kg, k.f_extrapoliert, k.u,
       s.strom, s.buch,
       (case when s.bekannt then s.kg end)::numeric(14,2)  as kg,
       s.basis_kg::numeric(14,2)    as basis_kg,
       (case when s.bekannt then s.koeffizient end)::numeric(12,6) as koeffizient,
       s.koeff_n, s.koeff_basis, s.formel,
       s.d_r                        as d_r,
       s.d_f * k.d_f_eta            as d_eta,
       s.d_a                        as d_a,
       s.d_a0                       as d_a0,
       s.koeff_art                  as koeff_art,
       s.bekannt                    as koeff_bekannt,
       k.kohorte
  from v_kaskade k
  cross join lateral (values
    ('Verdunstung', 'verlust', k.m0 - k.m1, k.m0, k.r, k.r_n, k.r_basis,
     'Masse × (1 − (1−r)^Lagertage), r = Tagesrate aus den Palettenwägungen',
     -k.d_m1_r, 0::numeric, 0::numeric, 0::numeric, null::text, k.r_bekannt),
    ('Nicht lagerbedingt', 'feld', k.m1 * k.a0, k.m1, k.a0, k.f_n,
     'Grundaussortierung a₀ aus dem Verderbsmodell: was bei Lagerdauer null schon im Palox läge',
     'Masse nach Verdunstung × a₀ — Erde, Hagelnarben, Schnittfehler; kein Lagerverlust',
     k.d_m1_r * k.a0, 0::numeric, 0::numeric, k.m1, null::text, k.a0_bekannt),
    ('Schimmel/Fäulnis', 'verlust', k.m1 * (1 - k.a0) * k.f, k.m1 * (1 - k.a0), k.f, k.f_n,
     'Verderbsmodell F(t) = 1 − exp(−λ·t^k), angepasst an alle Schimmelmessungen',
     'Masse nach Verdunstung und Sockel × Schimmelanteil bei dieser Lagerdauer',
     k.d_m1_r * (1 - k.a0) * k.f, k.m1 * (1 - k.a0), 0::numeric, -k.m1 * k.f, null::text, k.f_bekannt),
    ('Zu klein (Tierfutter)', 'marge', k.m1 * (1 - k.a0) * (1 - k.f) * k.a_klein_n, k.m2,
     k.a_klein_n, k.klein_n, k.klein_basis,
     'Masse nach Schimmel × Massenanteil unter der Sorten-Grenze — geht an die Tiere, kein Verlust',
     k.d_m1_r * (1 - k.a0) * (1 - k.f) * k.a_klein_n, -k.m1 * (1 - k.a0) * k.a_klein_n, k.m2,
     -k.m1 * (1 - k.f) * k.a_klein_n, 'ausschuss', k.a_klein_bekannt),
    ('Nebenkanal zu gross', 'marge', k.m1 * (1 - k.a0) * (1 - k.f) * k.a_gross_n, k.m2,
     k.a_gross_n, k.gross_n, k.gross_basis,
     'Masse nach Schimmel × Massenanteil ab 2000 g — kein Verlust, anderer Kanal',
     k.d_m1_r * (1 - k.a0) * (1 - k.f) * k.a_gross_n, -k.m1 * (1 - k.a0) * k.a_gross_n, k.m2,
     -k.m1 * (1 - k.f) * k.a_gross_n, 'nebenkanal', k.a_gross_bekannt),
    ('Faul beim Abpacken (Fax)', 'verlust',
     k.m1 * (1 - k.a0) * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n) * k.a_fax,
     k.m2 * (1 - k.a_klein_n - k.a_gross_n),
     k.a_fax, k.fax_n, k.fax_basis,
     'Verkaufsfähige Masse × Anteil Faules, das beim Etikettieren aussortiert wird — vom Waschen und Stehen, nicht von der Lagerdauer',
     k.d_m1_r * (1 - k.a0) * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n) * k.a_fax,
     -k.m1 * (1 - k.a0) * (1 - k.a_klein_n - k.a_gross_n) * k.a_fax,
     k.m2 * (1 - k.a_klein_n - k.a_gross_n),
     -k.m1 * (1 - k.f) * (1 - k.a_klein_n - k.a_gross_n) * k.a_fax,
     'fax', k.a_fax_bekannt),
    ('Verkaufsfähig', 'bilanz', k.verkaufsfaehig_kg, k.m2, null::numeric, null::int,
     null::text, 'Rest der Kaskade', 0::numeric, 0::numeric, 0::numeric, 0::numeric, null::text, true)
  ) as s(strom, buch, kg, basis_kg, koeffizient, koeff_n, koeff_basis, formel,
         d_r, d_f, d_a, d_a0, koeff_art, bekannt);
comment on view v_hochrechnung is
  'Ein Strom je Charge, Portion und (im Lager) Eingangstag. kg ist NULL, wenn '
  'der Koeffizient dahinter nie gemessen wurde — koeff_bekannt sagt es. Der '
  'Fax-Strom ist unbekannt, bis die erste Fax-Arbeit Faules gewogen hat.';

create view v_verlust_ranking with (security_invoker = true) as
select * from verlust_ranking();
comment on view v_verlust_ranking is
  'kg_unten/kg_oben sind ein fortgepflanztes 95-%-Intervall. kg ist NULL, '
  'wenn der Koeffizient hinter dem Strom nie gemessen wurde — dann ist der '
  'Strom unbekannt, nicht null.';

create view v_marge_buch with (security_invoker = true) as
with soll as (
  select coalesce((select (wert #>> '{}')::numeric from public.einstellung
                    where schluessel = 'soll_kg_pro_kiste'), 8) as kg
), kiste_je_sorte as (
  select distinct on (s.sorte) s.sorte, s.soll_kg_pro_kiste as kg
    from sortierschema s
   where s.art = 'kiste' and s.soll_kg_pro_kiste > 0 and s.gilt_ab <= current_date
   order by s.sorte, s.gilt_ab desc, (s.kaeufer is null) desc, s.id desc
), kiste_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (where ss.art = 'kiste'), 0)
           / nullif(sum(am.eingang_netto_kg), 0) as anteil
    from v_auftrag_masse am
    join auftrag a on a.id = am.auftrag_id
    left join sortierschema ss on ss.id = a.sortierschema_id
   where am.weg = 'hand' and am.eingang_netto_kg is not null
   group by am.charge_nr
), kisten as materialized (
  select sum(k.verkaufsfaehig_kg * b.weg2_anteil * coalesce(ka.anteil, 0)
             / coalesce(ks.kg, s.kg))                                as anzahl,
         sum(k.verkaufsfaehig_kg * b.weg2_anteil)                    as weg2_kg,
         sum(k.verkaufsfaehig_kg * b.weg2_anteil * coalesce(ka.anteil, 0)) as kisten_kg
    from v_kaskade k
    join v_hochrechnung_basis b on b.charge_nr = k.charge_nr
    left join kiste_je_sorte ks on ks.sorte = k.sorte
    left join kiste_anteil ka on ka.charge_nr = k.charge_nr
    cross join soll s
)
select r.strom as posten, r.kg, r.kg_unten, r.kg_oben,
       case r.strom
         when 'Nebenkanal zu gross' then 'Ware über 2000 g geht in einen anderen Verkaufskanal'
         when 'Zu klein (Tierfutter)' then 'Ware unter der Sorten-Grenze geht an die Tiere — verlässt den Betrieb, ist aber kein physischer Verlust'
         else '' end::text                                       as erlaeuterung
  from v_verlust_ranking r where r.buch = 'marge'
union all
select 'Überfüllung der Kisten',
       (u.kg_pro_kiste * v.anzahl)::numeric(14,2),
       (u.unten * v.anzahl)::numeric(14,2),
       (u.oben  * v.anzahl)::numeric(14,2),
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf '
              || '%s Kisten. Gerechnet wird nur über die %s t von %s t Weg-2-Ware, die '
              || 'als „Kiste ab x kg" sortiert wurde — nach Kaliber sortierte Ware hat '
              || 'kein Sollgewicht je Kiste und damit keine Überfüllung.',
              u.n, round(u.kg_pro_kiste, 3), round(coalesce(v.anzahl, 0)),
              round(coalesce(v.kisten_kg, 0) / 1000.0, 1), round(coalesce(v.weg2_kg, 0) / 1000.0, 1))
  from v_koeff_ueberfuellung u cross join kisten v
 where u.n > 0;
comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb über einen anderen Kanal verlässt, plus die '
  'verschenkte Marge aus überfüllten Kisten. Die Aufschlüsselung je Sorte, Charge '
  'und Käufer steht in v_hochrechnung (buch = marge) und v_ueberfuellung_kaeufer.';

create view v_massenbilanz with (security_invoker = true) as
with csv_anteil as materialized (
  select am.charge_nr,
         coalesce(sum(am.eingang_netto_kg) filter (
             where exists (select 1 from sortier_lauf l where l.auftrag_id = am.auftrag_id))
           / nullif(sum(am.eingang_netto_kg), 0), 0) as anteil_mit_csv
    from v_auftrag_masse am
   where am.station in ('sortieren', 'waschen_sortieren')
     and am.eingang_netto_kg is not null
   group by am.charge_nr
), gemessen as materialized (
  select charge_nr, sum(masse_kg) as gemessen_kg from v_sortier_lauf_masse group by charge_nr
), rest as materialized (
  select charge_nr, sum(m2) filter (where portion = 'lager') as restbestand_kg
    from v_kaskade group by charge_nr
), modell as materialized (
  select b.charge_nr,
         b.am_band_kg
         * power(1 - least(greatest(coalesce(kv.mittel, 0), 0), 0.05), coalesce(b.alter_band, 0))
         * (1 - sockel_anteil())
         * (1 - schimmelanteil(coalesce(b.alter_band, 0)))
         * q.anteil_mit_csv                                        as am_band_modell_kg
    from v_hochrechnung_basis b
    left join csv_anteil q on q.charge_nr = b.charge_nr
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
)
select b.charge_nr, b.sorte, b.schlag,
       b.eingang_kg, b.ausgelagert_kg, b.lager_kg, b.n_paletten,
       b.alter_ausgelagert, b.alter_lager, b.stichtag,
       m.am_band_modell_kg::numeric(14,2)                    as modell_am_band_kg,
       c.gemessen_kg                                         as csv_gemessen_kg,
       (c.gemessen_kg - m.am_band_modell_kg)::numeric(14,2)  as abweichung_kg,
       case when m.am_band_modell_kg > 0
            then ((c.gemessen_kg - m.am_band_modell_kg) / m.am_band_modell_kg)::numeric(10,4)
       end                                                   as abweichung_anteil,
       r.restbestand_kg::numeric(14,2)                       as restbestand_kg,
       b.alter_band
  from v_hochrechnung_basis b
  left join modell m     on m.charge_nr = b.charge_nr
  left join gemessen c   on c.charge_nr = b.charge_nr
  left join rest r       on r.charge_nr = b.charge_nr;
comment on view v_massenbilanz is
  'Modell gegen Sortier-CSV, beide zum selben Zeitpunkt: dem Tag am Band. '
  'restbestand_kg ist die Masse, die nach Verdunstung und Verderb noch im '
  'Haus liegt — über alle Eingangstage summiert.';

create view v_saisonbilanz with (security_invoker = true) as
with eingang as (
  select sum(eingang_kg) as kg, sum(lager_kg) as im_lager_kg, sum(wartet_kg) as wartet_kg
    from v_hochrechnung_basis
), verlust as (
  select sum(kg) as kg, sum(kg_unten) as kg_unten, sum(kg_oben) as kg_oben,
         sum(kg) filter (where buch = 'verlust') as lager_kg,
         sum(kg) filter (where buch = 'feld')    as feld_kg,
         bool_and(kg is not null) filter (where buch = 'verlust') as bekannt
    from v_verlust_ranking where buch in ('verlust', 'feld')
), rest as (
  select sum(m2) as kg from v_kaskade where portion = 'lager'
), vorlauf as (
  select coalesce(sum(ausgang_vor_app_kg), 0) as kg from charge_vorlauf
), ausgang as (
  select coalesce(sum(masse_kg), 0)                                as kg,
         coalesce(sum(masse_kg) filter (where buch = 'verkauf'), 0) as verkauf_kg,
         coalesce(sum(masse_kg) filter (where buch = 'marge'), 0)   as marge_kg,
         coalesce(sum(masse_kg) filter (where buch = 'verlust'), 0) as entsorgt_kg,
         coalesce(sum(masse_fehler_kg), 0)                          as fehler_kg,
         count(*)::int                                             as n_lieferungen
    from v_lieferung_masse
), fax as (
  -- Der dritte Lagerabschnitt (0051): gewaschen, in Kisten, wartet auf eine
  -- Bestellung. Was durchs Fax ging, hat die Halle als Palette mit Etikett
  -- verlassen; was verkaufsfähig gewaschen, aber noch nicht abgepackt ist,
  -- liegt noch da — die Bilanz sah es bisher als Lücke. Nur rechenbar, wenn
  -- der Betrieb das Fax überhaupt erfasst; sonst bleibt es NULL.
  select coalesce(sum(masse_kg), 0) as kg, count(*)::int as n
    from v_fax_beobachtung where status = 'abgeschlossen' and masse_kg is not null
), gewaschen as (
  select coalesce(sum(verkaufsfaehig_kg), 0) as kg from v_kaskade where portion = 'ausgelagert'
), offen as (
  select case when f.n > 0 then greatest(g.kg - f.kg, 0) end as kg, f.kg as fax_kg, f.n as fax_n
    from fax f cross join gewaschen g
)
select e.kg::numeric(14,2)                                 as eingang_kg,
       v.kg::numeric(14,2)                                 as verlust_modell_kg,
       v.kg_unten::numeric(14,2)                           as verlust_unten_kg,
       v.kg_oben::numeric(14,2)                            as verlust_oben_kg,
       (a.kg + vl.kg)::numeric(14,2)                       as ausgang_kg,
       a.verkauf_kg::numeric(14,2) as verkauf_kg, a.marge_kg::numeric(14,2) as marge_kg,
       a.entsorgt_kg::numeric(14,2) as entsorgt_kg,
       a.fehler_kg::numeric(14,2)                          as ausgang_fehler_kg,
       a.n_lieferungen,
       vl.kg::numeric(14,2)                                as vorlauf_kg,
       r.kg::numeric(14,2)                                 as restbestand_modell_kg,
       e.im_lager_kg::numeric(14,2) as im_lager_kg, e.wartet_kg::numeric(14,2) as wartet_kg,
       (e.kg - v.kg - a.kg - vl.kg - r.kg - coalesce(o.kg, 0))::numeric(14,2)  as luecke_kg,
       (case when e.kg > 0 then (e.kg - v.kg - a.kg - vl.kg - r.kg - coalesce(o.kg, 0)) / e.kg end)::numeric(10,4)
                                                           as luecke_anteil,
       (case when e.kg > 0 then (a.kg + vl.kg) / e.kg end)::numeric(10,4) as ausgang_deckung,
       case
         -- Ein unbekannter Strom (0051: Fax, bis die erste Fax-Arbeit Faules
         -- gewogen hat) und ein fehlender Ausgang können zusammen vorkommen —
         -- dann gehören beide in den Satz.
         when not coalesce(v.bekannt, false)
           then 'Ein Verluststrom ist noch nicht gemessen — die Bilanz kann erst '
                || 'schliessen, wenn jeder Koeffizient mindestens eine Messung hat.'
                || case when a.n_lieferungen = 0 and vl.kg = 0
                        then ' Kein Warenausgang erfasst — der Restbestand ist eine '
                             || 'Hochrechnung, kein Inventar.'
                        else '' end
         when a.n_lieferungen = 0 and vl.kg = 0
           then 'Kein Warenausgang erfasst — die Bilanz kann nichts prüfen. '
                || 'Der Restbestand ist eine Hochrechnung, kein Inventar.'
         when (a.kg + vl.kg) / nullif(e.kg, 0) < 0.2
           then 'Erst ein Bruchteil des Ausgangs ist erfasst — die Lücke sagt '
                || 'bislang mehr über die Erfassung als über das Modell.'
         when abs(e.kg - v.kg - a.kg - vl.kg - r.kg - coalesce(o.kg, 0)) / nullif(e.kg, 0) < 0.05
           then 'Die Bilanz geht auf: Eingang, Verlust, Ausgang und Bestand '
                || 'passen auf wenige Prozent zusammen.'
         when (e.kg - v.kg - a.kg - vl.kg - r.kg - coalesce(o.kg, 0)) > 0
           then 'Es fehlt Masse: mehr eingelagert, als sich durch Verlust, '
                || 'Ausgang und Bestand erklären lässt. Entweder ist ein '
                || 'Abgang nicht erfasst, oder ein Verlust wird unterschätzt.'
                || case when o.kg is null then ' Gewaschene Ware, die noch auf eine Bestellung wartet, '
                        || 'sieht die Bilanz erst, wenn das Fax erfasst wird.' else '' end
         else 'Es ist zu viel Masse da: mehr ausgeliefert und übrig, als je '
              || 'eingelagert wurde. Meist doppelt gezählte Paletten oder '
              || 'fehlende Tara im Wareneingang.'
       end                                                 as befund,
       v.lager_kg::numeric(14,2)                           as lagerverlust_kg,
       v.feld_kg::numeric(14,2)                            as feld_kg,
       -- neu (0051): der dritte Lagerabschnitt
       o.fax_kg::numeric(14,2)                             as fax_kg,
       o.fax_n                                             as n_fax,
       o.kg::numeric(14,2)                                 as gewaschen_offen_kg
  from eingang e cross join verlust v cross join rest r
       cross join ausgang a cross join vorlauf vl cross join offen o;
comment on view v_saisonbilanz is
  'Die Gegenprobe aus Spec §9: Eingang = Verlust + Ausgang + Restbestand + gewaschene '
  'Ware, die noch auf eine Bestellung wartet (gewaschen_offen_kg, nur wenn das Fax '
  'erfasst wird). Der Verlust enthält das Faule beim Abpacken (Fax).';

-- ---------- 3d. Welche Charge zuerst — je Kohorte gerechnet --------------
create or replace view v_naechste_charge with (security_invoker = true) as
with modell as materialized (
  select * from v_schimmel_modell
),
kohorten as materialized (
  select charge_nr, eingangsdatum, anteil from v_kohorte_anteil
),
bestand as (
  select b.charge_nr, b.sorte, b.schlag, b.lager_kg,
         least(greatest(coalesce(kv.mittel, 0), 0), 0.05)      as r,
         t.m0, t.alter_tage
    from v_hochrechnung_basis b
    left join v_koeff_verdunstung kv on kv.sorte = b.sorte
    cross join lateral (
      select b.lager_kg * c.anteil as m0,
             greatest((current_date - c.eingangsdatum)::numeric, 0) as alter_tage
        from kohorten c where c.charge_nr = b.charge_nr
      union all
      select b.lager_kg, greatest(b.alter_lager_heute, 0)
       where not exists (select 1 from kohorten c where c.charge_nr = b.charge_nr)
    ) t
   where b.lager_kg > 0
),
mit_f as (
  select b.*,
         b.m0 * power(1 - b.r, b.alter_tage)                    as masse_jetzt_kg,
         case when m.brauchbar then least(greatest(
           1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage, 1))
           , -40), 3))), 0), 0.99) end                          as f_jetzt,
         case when m.brauchbar then least(greatest(
           1 - exp(-exp(least(greatest(
             m.ln_lambda_korrigiert + m.k * ln(greatest(b.alter_tage + 14, 1))
           , -40), 3))), 0), 0.99) end                          as f_dann,
         (m.brauchbar and b.alter_tage > m.t_max)               as hochgerechnet,
         m.brauchbar                                            as modell_gilt
    from bestand b cross join modell m
),
je_charge as (
  select charge_nr, sorte, schlag, lager_kg, modell_gilt,
         bool_or(hochgerechnet)                                                 as hochgerechnet,
         sum(masse_jetzt_kg)                                                    as masse_jetzt_kg,
         sum(masse_jetzt_kg * alter_tage) / nullif(sum(masse_jetzt_kg), 0)     as alter_tage,
         min(alter_tage)                                                        as alter_von,
         max(alter_tage)                                                        as alter_bis,
         count(*)::int                                                          as n_kohorten,
         sum(masse_jetzt_kg * (1 - power(1 - r, 14)))                           as verdunstung_14_kg,
         case when modell_gilt
              then sum(masse_jetzt_kg * (f_dann - f_jetzt) / nullif(1 - f_jetzt, 0)) end
                                                                                as schimmel_14_kg
    from mit_f
   group by charge_nr, sorte, schlag, lager_kg, modell_gilt
)
select charge_nr, sorte, schlag,
       lager_kg::numeric(14,2),
       round(alter_tage)::int                                   as alter_tage,
       masse_jetzt_kg::numeric(14,2),
       verdunstung_14_kg::numeric(12,1)                         as verdunstung_14_kg,
       schimmel_14_kg::numeric(12,1)                            as schimmel_14_kg,
       (verdunstung_14_kg + coalesce(schimmel_14_kg, 0))::numeric(12,1) as verlust_14_kg,
       hochgerechnet, modell_gilt,
       round(alter_von)::int                                    as alter_von,
       round(alter_bis)::int                                    as alter_bis,
       n_kohorten
  from je_charge
 order by verlust_14_kg desc nulls last;
comment on view v_naechste_charge is
  'Was kostet es, jede Charge zwei weitere Wochen liegen zu lassen? Je Eingangstag '
  'gerechnet und je Charge summiert. alter_tage ist das massegewichtete Mittel, '
  'alter_von/bis die Spanne der liegenden Kohorten.';

-- ---------- 2. Eine Fassung festlegen, beim Eröffnen -----------------------
create or replace function sortierschema_festlegen(
  p_sorte text, p_kaeufer text, p_art text,
  p_baender jsonb default null, p_soll numeric default null, p_bemerkung text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_alt  sortierschema%rowtype;
  v_id   bigint;
  v_von  int; v_bis int; v_prev int; v_i int;
  v_gleich boolean;
begin
  if not (ist_aktiv() or ist_admin()) then
    raise exception 'Nur angemeldete Arbeiter dürfen eine Fassung festlegen.';
  end if;
  if p_art not in ('kaliber', 'kiste') then
    raise exception 'Unbekannte Sortierart „%".', p_art;
  end if;
  if not exists (select 1 from sorte_kaliber where sorte = p_sorte) then
    raise exception 'Unbekannte Sorte „%".', p_sorte;
  end if;

  if p_art = 'kaliber' then
    if p_baender is null or jsonb_typeof(p_baender) <> 'array' or jsonb_array_length(p_baender) = 0 then
      raise exception 'Kaliberbänder fehlen.';
    end if;
    v_prev := null;
    for v_i in 0 .. jsonb_array_length(p_baender) - 1 loop
      v_von := (p_baender -> v_i ->> 0)::int;
      v_bis := (p_baender -> v_i ->> 1)::int;
      if v_von is null or v_bis is null or v_von < 0 or v_bis <= v_von then
        raise exception 'Band % ist nicht aufsteigend (%–% g).', v_i + 1, v_von, v_bis;
      end if;
      if v_prev is not null and v_von <> v_prev then
        raise exception 'Band % beginnt bei % g, Band % endet aber bei % g — die Bänder müssen lückenlos anschliessen.',
          v_i + 1, v_von, v_i, v_prev;
      end if;
      v_prev := v_bis;
    end loop;
    v_von := (p_baender -> 0 ->> 0)::int;
    v_bis := v_prev;
  else
    if p_soll is null or p_soll <= 0 then
      raise exception 'Sollgewicht je Kiste fehlt.';
    end if;
  end if;

  -- Gilt heute schon genau das? Dann ist es dieselbe Fassung — auch wenn es
  -- die Standardfassung ohne Käufer ist.
  select * into v_alt from sortierschema
   where id = sortierschema_fuer(p_sorte, p_kaeufer, current_date, p_art);
  if found then
    v_gleich := case when p_art = 'kaliber'
                     then v_alt.kaliber_baender = p_baender
                     else v_alt.soll_kg_pro_kiste = p_soll end;
    if v_gleich then return v_alt.id; end if;
  end if;

  -- Sonst die Fassung von heute für diese Sorte, diesen Käufer, diese Art:
  -- gibt es sie schon, wird sie ersetzt (zweimal am selben Tag ist dieselbe
  -- Einstellung); sonst entsteht sie neu. Ältere Fassungen bleiben unberührt.
  select id into v_id from sortierschema
   where sorte = p_sorte and kaeufer is not distinct from p_kaeufer
     and art = p_art and gilt_ab = current_date;
  if v_id is not null then
    update sortierschema
       set verlust_unter = case when p_art = 'kaliber' then v_von end,
           kaliber_baender = case when p_art = 'kaliber' then p_baender end,
           kanal_ab = case when p_art = 'kaliber' then v_bis end,
           soll_kg_pro_kiste = case when p_art = 'kiste' then p_soll end,
           bemerkung = coalesce(p_bemerkung, bemerkung),
           erfasser = coalesce(auth.uid(), erfasser), ts = now()
     where id = v_id;
  else
    insert into sortierschema (sorte, kaeufer, gilt_ab, art, verlust_unter, kaliber_baender,
                               kanal_ab, soll_kg_pro_kiste, bemerkung, erfasser)
    values (p_sorte, p_kaeufer, current_date, p_art,
            case when p_art = 'kaliber' then v_von end,
            case when p_art = 'kaliber' then p_baender end,
            case when p_art = 'kaliber' then v_bis end,
            case when p_art = 'kiste' then p_soll end,
            coalesce(p_bemerkung, 'Beim Eröffnen einer Arbeit festgelegt'),
            auth.uid())
    returning id into v_id;
  end if;
  return v_id;
end $$;
comment on function sortierschema_festlegen is
  'Die Fassung, nach der eine Arbeit läuft: Gilt heute schon dasselbe, kommt deren '
  'id zurück; sonst entsteht eine neue Fassung ab heute (oder die von heute wird '
  'ersetzt). Kaliber: Bänder lückenlos aufsteigend, zu klein = erstes von, zu gross '
  '= letztes bis. Kiste: Sollgewicht.';
revoke execute on function sortierschema_festlegen(text, text, text, jsonb, numeric, text) from public;
grant execute on function sortierschema_festlegen(text, text, text, jsonb, numeric, text) to authenticated;

-- ---------- Datenqualität: Fax zählt für sich ------------------------------
create or replace view v_datenqualitaet with (security_invoker = true) as
with arbeiten as (select a.* from auftrag a where a.abgebrochen_ts is null),
     fertig as (select * from arbeiten where status = 'abgeschlossen')
select
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id)::int as paletten_gezaehlt,
  (select count(*) from auftrag_palette ap join arbeiten a on a.id = ap.auftrag_id
    where ap.eingangsdatum is not null)::int                                             as paletten_mit_datum,
  (select count(*) from fertig where not ist_fax)::int                                    as arbeiten_fertig,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null))::int                     as arbeiten_mit_ablesung,
  (select count(*) from fertig f where not f.ist_fax and (select count(*) from schimmel_messung s
    where s.auftrag_id = f.id and s.palox_stand_kg is not null) >= 2)::int                as arbeiten_mit_zwei_ablesungen,
  (select count(*) from fertig f where not f.ist_fax and exists (select 1 from auftrag_angabe g
    where g.auftrag_id = f.id and g.schluessel = 'eine_charge'))::int                     as arbeiten_mit_antwort,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen)::int                                                                as ausschuss_messungen,
  (select count(*) from ausschuss_messung m join arbeiten a on a.id = m.auftrag_id
    where m.gemessen and m.brutto_kg is not null)::int                                    as ausschuss_gewogen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.faul_kg is not null and w.gemessen)::int             as lagerkontrollen,
  (select count(*) from verdunstung_wiegung w
    where w.auftrag_id is null and w.faul_kg is not null and w.gemessen
      and w.auswahl = 'erreichbar_zufaellig')::int                                        as lagerkontrollen_zufaellig,
  (select count(*) from sortier_lauf)::int                                                as sortierlaeufe,
  (select count(*) from sortier_lauf where auftrag_id is not null)::int                   as sortierlaeufe_zugeordnet,
  (select count(*) from fertig f where f.station = 'sortieren')::int                      as sortier_arbeiten,
  (select count(*) from fertig f where f.station = 'sortieren' and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as sortier_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax)::int      as wasch_arbeiten,
  (select count(*) from fertig f where f.station = 'waschen' and not f.ist_fax
    and f.kaliber_idx is not null
    and exists (select 1 from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int
                                                                                          as wasch_arbeiten_mit_kisten,
  -- neu (0051): Fax
  (select count(*) from fertig f where f.ist_fax)::int                                    as fax_arbeiten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from auftrag_gebinde g where g.auftrag_id = f.id and g.anzahl > 0))::int              as fax_arbeiten_mit_kisten,
  (select count(*) from fertig f where f.ist_fax and exists (select 1
    from schimmel_messung s where s.auftrag_id = f.id and s.gemessen))::int               as fax_arbeiten_mit_faulem;
comment on view v_datenqualitaet is
  'Zähler zur Vollständigkeit der Erfassung. Fax-Arbeiten zählen getrennt: Kisten '
  'gezählt, Faules gewogen (auch „nichts Faules" ist eine Messung).';

-- ---------- Plausibilität: Zetteldatum, Fax, Kaliber −1 ------------------
create or replace view v_plausibilitaet with (security_invoker = true) as
select 'Schimmel'::text as art, b.auftrag_id, b.charge_nr, b.sorte, b.start_ts,
       format('%s kg Schimmel auf %s kg Ware — das wären %s %%',
              round(b.schimmel_kg), round(b.basis_jetzt_kg), round(b.anteil * 100)) as befund,
       'Sehr wahrscheinlich ein Tippfehler bei den Kilogramm. Zahl im Auftrag korrigieren.'::text as rat
  from v_schimmel_beobachtung b
 where b.anteil is not null and not b.plausibel and not b.ist_fax
union all
select 'Fax', f.auftrag_id, f.charge_nr, f.sorte, f.start_ts,
       format('%s kg Faules bei %s Kisten (%s kg) — das wären %s %%',
              round(f.faul_kg), f.kisten, round(f.masse_kg), round(f.anteil * 100)),
       'Entweder die Kistenzahl oder eine Wägung ist vertippt. Im Auftrag prüfen.'
  from v_fax_beobachtung f
 where f.anteil is not null and not f.plausibel
union all
select 'Ausschuss', a.auftrag_id, a.charge_nr, a.sorte, null::timestamptz,
       format('%s kg zu klein / %s kg zu gross bei %s kg Bezugsmasse',
              round(coalesce(a.klein_kg, 0)), round(coalesce(a.gross_kg, 0)), round(a.basis_kg)),
       'Entweder die Kilogramm oder die Palettenzahl im Auftrag stimmt nicht.'
  from v_ausschuss_beobachtung a
 where a.weg = 'hand' and not a.plausibel
union all
select 'Ohne Nenner', a.id, a.charge_nr, c.sorte, a.start_ts,
       format('%s erfasst, aber %s — die Messung hat keinen Nenner und fliesst nirgends ein',
              concat_ws(' und ',
                case when coalesce(s.kg, 0) > 0 then round(s.kg) || ' kg Faules' end,
                case when coalesce(x.kg, 0) > 0 then round(x.kg) || ' kg zu klein/gross' end),
              case when a.ist_fax then 'keine Kiste gezählt oder das Kistengewicht ist unbekannt'
                   when a.station = 'waschen' then 'keine Kiste gezählt und keine Menge eingetragen'
                   else 'keine Palette gezählt' end),
       case when a.ist_fax
            then 'Die gemachten Kisten je Kaliber am Auftrag zählen. Fehlt das Kistengewicht, '
                 || 'beim Sortieren mitzählen oder eine fertige Palette wiegen.'
            when a.station = 'waschen'
            then 'Die geleerten Kisten am Auftrag zählen (dann rechnet die Masse sich '
                 || 'selbst) oder die verarbeitete Menge in kg nachtragen.'
            else 'Die gezählten Paletten am Auftrag nachtragen.' end
  from auftrag a
  join charge c on c.nr = a.charge_nr
  left join v_schimmel_menge s on s.auftrag_id = a.id
  left join (select auftrag_id, sum(kg)::numeric as kg from ausschuss_messung
              where gemessen group by auftrag_id) x on x.auftrag_id = a.id
  left join v_auftrag_masse m on m.auftrag_id = a.id
 where a.abgebrochen_ts is null
   and (coalesce(s.kg, 0) > 0 or coalesce(x.kg, 0) > 0)
   and coalesce(m.eingang_netto_kg, 0) <= 0
union all
select 'Palox', s.auftrag_id, a.charge_nr, c.sorte, s.ts,
       format('Waagenstand %s kg liegt unter dem Leergewicht des Palox (%s kg)',
              s.palox_stand_kg, palox_tara_kg()),
       'Zeigt die Waage netto, gehört palox_tara_kg in den Einstellungen auf 0. '
       || 'Sonst ist der Stand vertippt.'
  from schimmel_messung s
  join auftrag a on a.id = s.auftrag_id
  join charge c on c.nr = a.charge_nr
 where s.gemessen and a.abgebrochen_ts is null
   and s.palox_stand_kg is not null and s.palox_stand_kg < palox_tara_kg()
union all
select 'Wägung', w.auftrag_id, w.charge_nr, w.sorte, w.wiege_ts,
       'Palette gewogen, aber '
       || case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
                 then 'für die Gebindeart fehlt die Tara'
               when w.lagertage <= 0
                 then 'das Wiegedatum liegt nicht nach dem Eingangsdatum'
               when w.netto_damals_kg <= 0 or w.netto_jetzt_kg <= 0
                 then 'das Netto ist null oder negativ'
               else 'sie ist nicht verwertbar' end
       || ' — sie zählt nicht in die Verdunstungsrate',
       case when w.netto_damals_kg is null or w.netto_jetzt_kg is null
              then 'Unter Stammdaten → Gebinde die Tara nachtragen.'
            else 'Eingangsdatum und Gewichte der Wägung prüfen.' end
  from v_verdunstung_messung w
  left join auftrag a on a.id = w.auftrag_id
 where not w.verwendbar and not w.sichtbar_schimmel
   and (a.id is null or a.abgebrochen_ts is null)
   and exists (select 1 from verdunstung_wiegung v where v.id = w.id and v.gemessen)
union all
select 'Kistengewicht', g.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       case when g.kaliber_idx = -1
            then format('%s Kisten nach Sollgewicht gezählt, aber für diese Sorte wurde noch '
                        || 'nie eine fertige Palette gewogen — das Kistengewicht ist unbekannt', g.anzahl)
            else format('%s Kisten Kaliber %s gezählt, aber für dieses Kaliber wurde beim '
                        || 'Sortieren noch nie mitgezählt — das Kistengewicht ist unbekannt',
                        g.anzahl, g.kaliber_idx + 1) end,
       case when g.kaliber_idx = -1
            then 'Bei der nächsten Arbeit „Kiste ab x kg" eine fertige Palette wiegen. Das '
                 || 'Kistengewicht gilt dann für alle Fax-Arbeiten dieser Sorte.'
            else 'Beim nächsten Sortierlauf die gefüllten Kisten je Kaliber zählen. Das '
                 || 'Kistengewicht gilt dann rückwirkend für alle Waschgänge dieser Sorte.' end
  from v_auftrag_gebinde_masse g
  join auftrag a on a.id = g.auftrag_id
  join charge c on c.nr = a.charge_nr
 where g.kg is null and g.anzahl > 0
union all
select 'Kaliber fehlt', a.id, a.charge_nr, c.sorte, a.start_ts,
       'Waschgang ohne Kaliber eröffnet — die gezählten Kisten lassen sich keiner Masse zuordnen',
       'Das Kaliber am Auftrag nachtragen; welche Bänder es gibt, steht unter '
       || 'Stammdaten → Sortierschemata.'
  from auftrag a
  join charge c on c.nr = a.charge_nr
 where a.station = 'waschen' and not a.ist_fax and a.kaliber_idx is null and a.abgebrochen_ts is null
   and exists (select 1 from auftrag_gebinde g where g.auftrag_id = a.id and g.anzahl > 0)
union all
select 'Ausschuss-Tara', m.auftrag_id, a.charge_nr, c.sorte, m.ts,
       format('%s kg %s gespeichert — aus Brutto %s kg und heutiger Tara wären es %s kg',
              m.kg, case m.art when 'zu_klein' then 'zu klein' else 'zu gross' end,
              m.brutto_kg,
              greatest(round(m.brutto_kg - coalesce(m.kisten, 0) * coalesce(g.tara_kg_pro_kiste, 0)
                             - coalesce(g.tara_kg_palette, 0)), 0)),
       'Die Gebinde-Tara wurde nach dem Wiegen geändert. Stimmt die neue Tara, den '
       || 'Eintrag im Auftrag löschen und mit demselben Brutto neu eintragen.'
  from ausschuss_messung m
  join auftrag a on a.id = m.auftrag_id
  join charge c on c.nr = a.charge_nr
  left join gebinde g on g.art = m.gebindeart
 where m.brutto_kg is not null and a.abgebrochen_ts is null
   and m.kg <> greatest(round(m.brutto_kg - coalesce(m.kisten, 0) * coalesce(g.tara_kg_pro_kiste, 0)
                              - coalesce(g.tara_kg_palette, 0)), 0)
union all
-- Ein Zetteldatum, zu dem die Charge keine Palette hat: vertippt, oder die
-- Palette fehlt im Wareneingang. So oder so stimmt eine Kohorte nicht.
select 'Zetteldatum', ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts,
       format('%s Palette(n) mit Zetteldatum %s gezählt, aber an dem Tag kam keine Palette dieser Charge',
              count(*), to_char(ap.eingangsdatum, 'DD.MM.YYYY')),
       'Datum an der Zählung prüfen (Zahlendreher?) — oder die Palette fehlt im Wareneingang.'
  from auftrag_palette ap
  join auftrag a on a.id = ap.auftrag_id
  join charge c on c.nr = a.charge_nr
 where ap.eingangsdatum is not null and ap.palette_id is null and ap.wiegung_id is null
   and a.abgebrochen_ts is null
   and not exists (select 1 from palette p where p.charge_nr = a.charge_nr and p.eingangsdatum = ap.eingangsdatum)
 group by ap.auftrag_id, a.charge_nr, c.sorte, a.start_ts, ap.eingangsdatum;
comment on view v_plausibilitaet is
  'Messungen, die die Auswertung bewusst nicht verwendet — und Messungen, die '
  'sie nicht verwenden kann, weil ihnen der Nenner fehlt. Neu (0051): Fax-Anteile, '
  'Zetteldaten ohne Palette, Kisten nach Sollgewicht ohne gewogene Palette.';

grant select on v_kaskade, v_hochrechnung, v_verlust_ranking, v_marge_buch,
               v_massenbilanz, v_saisonbilanz, v_plausibilitaet, v_datenqualitaet,
               v_hochrechnung_basis, v_naechste_charge, v_koeff_gebinde,
               v_auftrag_masse, v_schimmel_beobachtung, v_schimmel_punkte,
               v_koeff_roh_kaliber, v_ausgang_artikel_vorschlag to authenticated;
grant execute on function verlust_ranking(text, text, numeric) to authenticated;
