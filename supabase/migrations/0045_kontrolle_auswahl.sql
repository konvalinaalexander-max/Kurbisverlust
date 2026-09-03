-- =====================================================================
-- 0045 — Die Lagerkontrolle hält fest, wie die Palette ausgewählt wurde
--
-- Der Betrieb: Das Lager ist gestapelt, man kommt nicht an jede Palette. „Nimm
-- irgendeine" ist damit nicht durchführbar. Was bleibt, ist das Ehrliche: eine
-- zufällige unter den heute erreichbaren — und die App soll festhalten, dass es
-- so war. Damit ist die Messung nicht frei von Auswahl, aber ihre Auswahl ist
-- wenigstens bekannt und nicht am Zustand der Ware orientiert.
--
-- Die Auswahlart steht als Spalte an der Lagerkontrolle. Die ehrliche Vorgabe
-- ist „zufällig unter den erreichbaren"; „aus der Mitte/unten gegriffen" ist
-- besser (weniger an die Erreichbarkeit gebunden), „gezielt" ist die Warnung,
-- dass nach Aussehen gewählt wurde — solche Kontrollen taugen für die
-- Selektionsprüfung nicht und werden dort später ausgenommen.
-- =====================================================================

alter table verdunstung_wiegung
  add column if not exists auswahl text
  check (auswahl is null or auswahl in ('erreichbar_zufaellig', 'mitte_unten', 'gezielt'));
comment on column verdunstung_wiegung.auswahl is
  'Nur bei der Lagerkontrolle gesetzt: wie die Palette gegriffen wurde — '
  'erreichbar_zufaellig (ehrliche Vorgabe), mitte_unten (besser), gezielt '
  '(nach Aussehen, für die Selektionsprüfung untauglich).';
