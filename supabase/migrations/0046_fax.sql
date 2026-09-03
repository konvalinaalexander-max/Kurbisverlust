-- =====================================================================
-- 0046 — Fax ist ein eigener Arbeitsgang
--
-- Der Betrieb (2. September): „Fax" ist immer ein eigener Arbeitsgang nach
-- Bestellung; tagsüber wird provisorisch vorgewaschen. Diese Arbeiten sind
-- fachlich ein Waschgang, gehören aber getrennt gezählt — sonst verschwinden
-- sie in den regulären Wascharbeiten oder werden gar nicht erfasst.
--
-- Deshalb eine Markierung an der Arbeit, nicht eine neue Station: fachlich
-- bleibt es ein Waschgang (Station waschen), damit die ganze Massenkaskade
-- unverändert rechnet. `ist_fax` trennt die Fax-Arbeiten für die Erfassung
-- und spätere Auswertung, ohne das Modell anzufassen.
-- =====================================================================

alter table auftrag add column if not exists ist_fax boolean not null default false;
comment on column auftrag.ist_fax is
  'Fax-Arbeit: eigener Waschgang nach Bestellung. Fachlich ein Waschgang '
  '(Station waschen), nur für die Erfassung getrennt gehalten.';
