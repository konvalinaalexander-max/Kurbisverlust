-- =====================================================================
-- 0040 — Die Überfüllung rechnet mit dem Kistenmass der Sorte
--
-- Seit 0038 ist das Kistenmass eine Eigenschaft von (Sorte × Käufer) mit
-- Gültigkeitsdatum: Coop will es anders als Migros, und dieselbe Sorte läuft
-- je nach Bestellung mit Kaliberbändern oder mit „Kiste ab x kg". Die
-- Ausgangs-Kennzahl liest das seither so. Die Überfüllung im Marge-Buch nicht:
-- Sie teilte die ganze Weg-2-Masse durch die eine Einstellung
-- soll_kg_pro_kiste, egal um welche Sorte es ging.
--
-- Der Betrieb hat am 3. September gesagt, für welche Sorte die 8-kg-Kiste
-- gilt, lasse sich erst sagen, wenn einmal alles gewaschen und erfasst ist.
-- Das ist eine Antwort, die aus den Daten kommt — also muss die Rechnung sie
-- von dort nehmen können, sobald sie da ist, statt auf eine Zahl in den
-- Einstellungen zu warten.
--
-- Jede Charge bringt ab jetzt ihr eigenes Kistenmass mit, aus der zuletzt
-- gültigen Kisten-Fassung ihrer Sorte. Wo es für eine Sorte keine gibt, gilt
-- weiter die Einstellung — sonst fiele die Überfüllung auf null, sobald jemand
-- die erste Fassung anlegt, und niemand wüsste warum. Der Rechenweg sagt, wie
-- viele Chargen aus einem Schema gerechnet wurden und wie viele aus der
-- Einstellung; solange dort „0 von 14" steht, ist die Zahl so grob wie zuvor.
--
-- Welchem Käufer eine bestimmte Kiste zugutekam, ist im Warenausgang nicht
-- erfasst. Deshalb je Sorte eine Fassung: die zuletzt gültige, Standard vor
-- käuferspezifisch. Sind für eine Sorte mehrere Käufer mit verschiedenen
-- Kistenmassen hinterlegt, ist das eine Näherung — sie steht in ABLAUF.md
-- unter den Annahmen.
-- =====================================================================

drop view if exists v_marge_buch;

create view v_marge_buch with (security_invoker = true) as
with soll as (
  select coalesce((select (wert #>> '{}')::numeric from einstellung
                    where schluessel = 'soll_kg_pro_kiste'), 8) as kg
), kiste_je_sorte as (
  select distinct on (s.sorte) s.sorte, s.soll_kg_pro_kiste as kg
    from sortierschema s
   where s.art = 'kiste' and s.soll_kg_pro_kiste > 0 and s.gilt_ab <= current_date
   order by s.sorte, s.gilt_ab desc, (s.kaeufer is null) desc, s.id desc
), kisten as materialized (
  select sum(k.verkaufsfaehig_kg * b.weg2_anteil / coalesce(ks.kg, s.kg))   as anzahl,
         count(distinct k.charge_nr) filter (where ks.kg is not null)::int  as aus_schema,
         count(distinct k.charge_nr)::int                                   as chargen
    from v_kaskade k
    join v_hochrechnung_basis b on b.charge_nr = k.charge_nr
    left join kiste_je_sorte ks on ks.sorte = k.sorte
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
       format('%s Wägungen, im Schnitt %s kg Überschuss je Kiste, hochgerechnet auf %s Kisten '
              || '(Weg 2). Kistenmass: %s von %s Chargen aus dem Sortierschema der Sorte, '
              || 'der Rest mit %s kg aus den Einstellungen. Annahme: alle Weg-2-Ware geht in '
              || 'solche Kisten',
              u.n, round(u.kg_pro_kiste, 3), round(v.anzahl), v.aus_schema, v.chargen, s.kg)
  from v_koeff_ueberfuellung u cross join kisten v cross join soll s
 where u.n > 0;

comment on view v_marge_buch is
  'Buch B: Ware, die den Betrieb über einen anderen Kanal verlässt, plus die '
  'verschenkte Marge aus überfüllten Kisten. Das Kistenmass kommt je Sorte aus '
  'dem Sortierschema (art = kiste), sonst aus der Einstellung soll_kg_pro_kiste.';

grant select on v_marge_buch to authenticated;
