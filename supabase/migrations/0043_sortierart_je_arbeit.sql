-- =====================================================================
-- 0043 — Wie sortiert wird, entscheidet die Arbeit, nicht die Stammdaten
--
-- Der Betrieb am 3. September: „manchmal tun wir einfach Kisten mit 8 kg,
-- manchmal ist dort das Kistengewicht egal, stattdessen machen wir von Hand
-- Kaliber." Und dazu, wie es abläuft: Bei „Waschen + Sortieren" geht die Ware
-- durch eine Trommel auf ein Band, und dort sortieren die Arbeiter nach den
-- Regeln, die beim Eröffnen der Arbeit festgelegt werden. Beim Sortieren an
-- der Maschine läuft es nach der hinterlegten Fassung — auch dort soll beim
-- Eröffnen noch einmal bestätigt werden.
--
-- Bisher hing die Art (`kaliber` oder `kiste`) an (Sorte × Käufer × Datum).
-- Ein eindeutiger Index liess für dieselbe Sorte und denselben Käufer nur
-- **eine** Fassung je Stichtag zu — beides gleichzeitig zu hinterlegen war
-- also gar nicht möglich, geschweige denn, es je Arbeit zu wählen.
--
-- Was das kostet, hängt an der Klassierung: Die Sortier-CSV wird nach der
-- Fassung der Arbeit klassiert. Lief eine Arbeit als „Kiste ab x kg", ist aber
-- `kaliber` hinterlegt, wandert alles unterhalb der Kaliber-Untergrenze in den
-- Strom „Zu klein (Tierfutter)" — ein ganzer Balken im Dashboard, aus einer
-- Regel, die an dem Tag nicht galt. Umgekehrt verschwindet er ganz.
--
-- Deshalb:
--   * Der Index umfasst jetzt auch die Art. Eine Sorte darf für denselben
--     Käufer beide Fassungen gleichzeitig führen. Der Betrieb hält es für
--     unwahrscheinlich, dass beides am selben Tag vorkommt — gebaut ist es
--     trotzdem so, damit die Frage nicht wieder aufkommt.
--   * `sortierschema_fuer` bekommt eine Fassung mit Art. Ohne Art bleibt es
--     bei „die zuletzt gültige", damit alles Bestehende weiterläuft.
--   * Je Sorte gibt es ab jetzt auch eine Kisten-Standardfassung. Ihr
--     Sollgewicht kommt aus der Einstellung `soll_kg_pro_kiste` — demselben
--     Wert, mit dem die Auswertung schon bisher gerechnet hat. Das ist keine
--     erfundene Zahl, sondern dieselbe an einem besseren Ort. Ohne diese
--     Fassung könnte der Arbeiter „Kiste" gar nicht erst wählen.
--
-- ---------- Und die Kehrseite: keine Kiste, keine Überfüllung -------------
-- Die Überfüllung ist die verschenkte Marge, wenn in eine Kiste, die als
-- 8-kg-Kiste verkauft wird, 8.3 kg wandern. Wird nach Kaliber sortiert, gibt
-- es kein Sollgewicht je Kiste — und damit auch nichts zu verschenken. Bisher
-- rechnete die Auswertung trotzdem, weil sie ohne Kisten-Fassung auf die
-- globale Einstellung zurückfiel. Ab jetzt zählt für die Überfüllung nur die
-- Masse aus Arbeiten, die wirklich als „Kiste ab x kg" liefen.
-- =====================================================================

-- ---------- 1. Beide Arten dürfen nebeneinander stehen -------------------
drop index if exists sortierschema_eindeutig;
create unique index if not exists sortierschema_eindeutig
  on sortierschema (sorte, coalesce(kaeufer, ''), art, gilt_ab);

-- ---------- 2. Je Sorte auch eine Kisten-Fassung --------------------------
insert into sortierschema (sorte, kaeufer, gilt_ab, art, soll_kg_pro_kiste, bemerkung)
select sk.sorte, null, date '2000-01-01', 'kiste',
       coalesce((select (wert #>> '{}')::numeric from public.einstellung
                  where schluessel = 'soll_kg_pro_kiste'), 8),
       'Beim Einrichten aus der Einstellung soll_kg_pro_kiste übernommen — '
       'derselbe Wert, mit dem die Auswertung schon vorher gerechnet hat. '
       'Sobald der Betrieb das echte Sollgewicht je Sorte kennt, gehört eine '
       'neue Fassung angelegt, nicht diese geändert.'
  from sorte_kaliber sk
 where not exists (select 1 from sortierschema s
                    where s.sorte = sk.sorte and s.kaeufer is null and s.art = 'kiste');

-- ---------- 3. Die Fassung zu einer Art ----------------------------------
create or replace function sortierschema_fuer(p_sorte text, p_kaeufer text,
                                              p_datum date, p_art text)
returns bigint language sql stable as $$
  select coalesce(
    -- die Fassung dieses Käufers in dieser Art, die am Stichtag galt
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is not distinct from p_kaeufer
        and art = p_art and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst die Standard-Fassung dieser Art
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is null and art = p_art and gilt_ab <= p_datum
      order by gilt_ab desc limit 1),
    -- sonst irgendeine Standard-Fassung dieser Art
    (select id from public.sortierschema
      where sorte = p_sorte and kaeufer is null and art = p_art
      order by gilt_ab limit 1));
$$;
comment on function sortierschema_fuer(text, text, date, text) is
  'Die Fassung einer bestimmten Art (kaliber oder kiste), die für Sorte und '
  'Käufer an einem Tag galt. Die Art wählt der Arbeiter beim Eröffnen.';
revoke execute on function sortierschema_fuer(text, text, date, text) from public;
grant execute on function sortierschema_fuer(text, text, date, text) to authenticated;

-- ---------- 4. Die Art der Arbeit festhalten ------------------------------
-- Sie steckt bereits in der gewählten Fassung; als eigene Spalte wäre sie
-- eine zweite Wahrheit. Diese Ansicht macht sie lesbar, ohne sie zu doppeln.
create or replace view v_auftrag_sortierart with (security_invoker = true) as
select a.id as auftrag_id, a.charge_nr, a.weg, a.station,
       s.id as sortierschema_id, s.art, s.soll_kg_pro_kiste, s.kaliber_baender,
       s.verlust_unter, s.kanal_ab, s.gilt_ab, s.kaeufer
  from auftrag a
  left join sortierschema s on s.id = a.sortierschema_id
 where a.abgebrochen_ts is null;
comment on view v_auftrag_sortierart is
  'Nach welchen Regeln eine Arbeit lief — die Fassung, die beim Eröffnen '
  'gewählt wurde. Nicht die heute gültige.';
grant select on v_auftrag_sortierart to authenticated;

-- ---------- 5. Keine Kiste, keine Überfüllung -----------------------------
create or replace view v_ausgang_kennzahl with (security_invoker = true) as
select w.id, w.auftrag_id, w.charge_nr, c.sorte, c.schlag, w.ts,
       w.brutto_kg, w.kisten, w.gebindeart, w.kuerbisse_pro_kiste,
       n.netto_kg,
       (n.netto_kg / w.kisten)::numeric(10,3)                       as kg_pro_kiste,
       (n.netto_kg / nullif(w.kisten * w.kuerbisse_pro_kiste, 0))::numeric(10,3)
                                                                    as kg_pro_kuerbis,
       s.soll                                                       as soll_kg_pro_kiste,
       -- Ohne Sollgewicht gibt es keine Überfüllung: Wird nach Kaliber
       -- sortiert, ist die Kiste kein Mass, sondern nur ein Behälter.
       (case when s.soll is not null
             then (n.netto_kg / w.kisten - s.soll) end)::numeric(10,3)
                                                                    as ueberfuellung_je_kiste,
       (case when s.soll is not null
             then (n.netto_kg - w.kisten * s.soll) end)::numeric(10,2)
                                                                    as ueberfuellung_kg
  from ausgang_wiegung w
  join auftrag a on a.id = w.auftrag_id
  join charge c on c.nr = w.charge_nr
  left join gebinde g on g.art = w.gebindeart
  left join sortierschema ss on ss.id = a.sortierschema_id
  cross join lateral (
    select (w.brutto_kg - w.kisten * g.tara_kg_pro_kiste
            - coalesce(g.tara_kg_palette, 0))::numeric(10,2) as netto_kg) n
  cross join lateral (
    select case when ss.art = 'kiste' then ss.soll_kg_pro_kiste end as soll) s
 where w.gemessen and a.abgebrochen_ts is null and n.netto_kg > 0;

comment on view v_ausgang_kennzahl is
  'Je fertiger Palette: tatsächliche Kilo je Kiste und der Überschuss über das '
  'Sollgewicht. Der Überschuss ist NULL, wenn die Arbeit nach Kaliber lief — '
  'dann gibt es kein Sollgewicht und nichts zu verschenken.';

-- ---------- 6. Die Überfüllung nur über die Kisten-Masse -----------------
-- Bisher rechnete das Marge-Buch die ganze Weg-2-Masse auf Kisten um, mit der
-- ausdrücklichen Annahme „alle Weg-2-Ware geht in solche Kisten". Jetzt ist
-- bekannt, welche Arbeit als Kiste lief und welche nach Kaliber — die Annahme
-- wird durch eine Messung ersetzt.
drop view if exists v_marge_buch;

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
  -- Wie viel der Weg-2-Masse einer Charge lief als „Kiste ab x kg"?
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
  'verschenkte Marge aus überfüllten Kisten. Die Überfüllung zählt nur die '
  'Masse aus Arbeiten, die als „Kiste ab x kg" liefen.';
grant select on v_marge_buch to authenticated;

-- ---------- 7. Ein Koeffizient zählt nur, was gemessen wurde --------------
-- v_koeff_ueberfuellung zählte bisher jede Wägung mit, auch die, aus der sich
-- gar kein Überschuss ergibt. Seit Punkt 5 ist das nicht mehr theoretisch: Bei
-- einer Arbeit nach Kaliber ist der Überschuss NULL. Der Zähler stand dann auf
-- 420 Wägungen, während der Wert daneben leer blieb — dieselbe Verwechslung
-- von „leer" und „null" wie in 0036, nur an einer neuen Stelle.
create or replace view v_koeff_ueberfuellung with (security_invoker = true) as
with roh as (
  select m.wert, m.n_kisten, m.wert / nullif(m.n_kisten, 0)::numeric as je_kiste
    from marge_messung m
    join auftrag a on a.id = m.auftrag_id
   where m.art = 'ueberfuellung' and m.gemessen and m.n_kisten > 0
     and a.abgebrochen_ts is null and m.wert is not null
  union all
  select k.ueberfuellung_kg, k.kisten, k.ueberfuellung_je_kiste
    from v_ausgang_kennzahl k
   where k.ueberfuellung_je_kiste is not null
), s as (
  select count(*)::int as n,
         sum(wert) / nullif(sum(n_kisten), 0)::numeric as kg_pro_kiste,
         stddev_samp(je_kiste) as sd
    from roh
)
select n,
       kg_pro_kiste::numeric(10,3)                                  as kg_pro_kiste,
       sd::numeric(10,3)                                            as sd,
       (case when sd is null or n < 2 then kg_pro_kiste
             else greatest(kg_pro_kiste - 1.96 * sd / sqrt(n), 0) end)::numeric(10,3) as unten,
       (case when sd is null or n < 2 then kg_pro_kiste
             else kg_pro_kiste + 1.96 * sd / sqrt(n) end)::numeric(10,3)              as oben
  from s;

comment on view v_koeff_ueberfuellung is
  'Überschuss je Kiste über dem Sollgewicht. Gezählt werden nur Wägungen, aus '
  'denen sich überhaupt ein Überschuss ergibt — Arbeiten nach Kaliber haben '
  'kein Sollgewicht und zählen nicht mit.';
grant select on v_koeff_ueberfuellung to authenticated;

-- ---------- 8. Der alte Drei-Argument-Aufruf wird eindeutig --------------
-- sortierschema_fuer(sorte, kaeufer, datum) ohne Art gibt es weiter — die
-- Klassierung und der Auslöser fallen darauf zurück, wenn die App keine
-- Fassung nennt. Mit zwei Arten je Sorte war „die zuletzt gültige" aber nicht
-- mehr eindeutig. Historisch gab es nur Kaliber; genau das bleibt die
-- Vorgabe, damit keine bestehende Arbeit still die Art wechselt.
create or replace function sortierschema_fuer(p_sorte text, p_kaeufer text, p_datum date)
returns bigint language sql stable as $$
  select public.sortierschema_fuer(p_sorte, p_kaeufer, p_datum, 'kaliber');
$$;

-- Und der Auslöser reicht die Art durch, wenn die App eine nennt (über die
-- Fassung, die sie schickt). Nennt sie keine, bleibt es bei Kaliber.
create or replace function auftrag_schema_setzen()
returns trigger language plpgsql as $$
begin
  if new.sortierschema_id is null and new.station = 'waschen' then
    select l.sortierschema_id into new.sortierschema_id
      from public.sortier_lauf l
      join public.auftrag a on a.id = l.auftrag_id
     where l.charge_nr = new.charge_nr and l.sortierschema_id is not null
     order by coalesce(l.datei_zeit, l.gelesen_ts) desc limit 1;
  end if;
  if new.sortierschema_id is null then
    select public.sortierschema_fuer(c.sorte, new.kaeufer, new.start_ts::date, 'kaliber')
      into new.sortierschema_id
      from public.charge c where c.nr = new.charge_nr;
  end if;
  return new;
end $$;
revoke execute on function auftrag_schema_setzen() from public;
