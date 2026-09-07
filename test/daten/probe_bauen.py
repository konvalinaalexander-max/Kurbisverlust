"""Baut test/daten/warenausgang-probe.xlsx — die Prüfdatei für den Import.

Erfunden, nicht echt: Die Datei bildet die Form der Perigon-Auswertung nach,
mit genau den Fällen, an denen der Import schon einmal falsch lag. Echte
Kundendaten gehören nicht ins Repository.

    python3 test/daten/probe_bauen.py     (braucht openpyxl)
"""
import openpyxl, datetime, os

KOPF = ['AuftragsErfasser','AuftragsJournal','KundenAuftragsNr','AuftragsReferenz',
        'AuftragsRuestDatum','AuftragsLieferDatum','AuftragsLieferant','AuftragsArtId',
        'AuftragsArtikel','Textlinie1','AuftragsPrsGrpBez','AuftragsGebBez',
        'AuftragsGebindemengeSoll','AuftragsArtikelmengeSoll','AuftragsGebindemenge',
        'AuftragsGebindeinhalt','AuftragsArtikelMenge','AufPosBatchPackageQuantity Charge',
        'AufPosBatchQuantity Charge','AuftragsArtikelEinheit','AuftragsErloesExkl',
        'AuftragsErloesTotExkl','AuftragsChargeManuell','LiefProdAdrName','LiefHerkunft',
        'LiefPrsGrpName','LiefCoopRegion','LiefInitialMenge','LiefVerfügbareMenge',
        'AufPosId','GewichtProArtikel','TotalGewicht']

def zeile(**kw):
    r = [None] * len(KOPF)
    for k, v in kw.items():
        r[KOPF.index(k)] = v
    return r

D = datetime.datetime
ZEILEN = [
    # 1) Eine Position, über zwei eigene Chargen aufgeteilt: 100 + 60 Stk à 1.5 kg
    zeile(AuftragsJournal='A', KundenAuftragsNr=900001, AuftragsLieferDatum=D(2026,9,1),
          AuftragsLieferant='Grosshandel Zürich', AuftragsArtId='kürbbu',
          AuftragsArtikel='Bio Kürbis Butternut', AuftragsGebBez='G2',
          AuftragsGebindemenge=20, AuftragsGebindeinhalt=8, AuftragsArtikelMenge=160,
          **{'AufPosBatchPackageQuantity Charge': 12, 'AufPosBatchQuantity Charge': 100},
          AuftragsArtikelEinheit='Stk.', AuftragsErloesTotExkl=800,
          AuftragsChargeManuell=1613, LiefProdAdrName='Imhof', AufPosId=5001,
          GewichtProArtikel=1.5, TotalGewicht=240),
    zeile(AuftragsJournal='A', KundenAuftragsNr=900001, AuftragsLieferDatum=D(2026,9,1),
          AuftragsLieferant='Grosshandel Zürich', AuftragsArtId='kürbbu',
          AuftragsArtikel='Bio Kürbis Butternut', AuftragsGebBez='G2',
          AuftragsGebindemenge=20, AuftragsGebindeinhalt=8, AuftragsArtikelMenge=160,
          **{'AufPosBatchPackageQuantity Charge': 8, 'AufPosBatchQuantity Charge': 60},
          AuftragsArtikelEinheit='Stk.', AuftragsErloesTotExkl=800,
          AuftragsChargeManuell=1626, LiefProdAdrName='Imhof', AufPosId=5001,
          GewichtProArtikel=1.5, TotalGewicht=240),
    # 2) Position mit einer Kandidatenzeile ohne Menge (0) — darf nichts beitragen
    zeile(AuftragsJournal='A', KundenAuftragsNr=900002, AuftragsLieferDatum=D(2026,9,2),
          AuftragsLieferant='Migros Zürich', AuftragsArtId='Kürbol',
          AuftragsArtikel='Bio Kürbis oranger Knirps lose', AuftragsGebBez='U-Gebinde',
          AuftragsGebindemenge=10, AuftragsGebindeinhalt=8, AuftragsArtikelMenge=80,
          **{'AufPosBatchPackageQuantity Charge': 10, 'AufPosBatchQuantity Charge': 80},
          AuftragsArtikelEinheit='kg', AuftragsChargeManuell=1615,
          LiefProdAdrName='Imhof', AufPosId=5002, GewichtProArtikel=1, TotalGewicht=80),
    zeile(AuftragsJournal='A', KundenAuftragsNr=900002, AuftragsLieferDatum=D(2026,9,2),
          AuftragsLieferant='Migros Zürich', AuftragsArtId='Kürbol',
          AuftragsArtikel='Bio Kürbis oranger Knirps lose', AuftragsGebBez='U-Gebinde',
          AuftragsGebindemenge=10, AuftragsGebindeinhalt=8, AuftragsArtikelMenge=80,
          **{'AufPosBatchPackageQuantity Charge': 0, 'AufPosBatchQuantity Charge': 0},
          AuftragsArtikelEinheit='kg', AuftragsChargeManuell=199001,
          LiefProdAdrName='Peter Rüegg', AufPosId=5002, GewichtProArtikel=1, TotalGewicht=80),
    # 3) Position ganz ohne Chargenbezug — zählt in die Bilanz, nicht auf eine Charge
    zeile(AuftragsJournal='A', KundenAuftragsNr=900003, AuftragsLieferDatum=D(2026,9,3),
          AuftragsLieferant='Rathgeb BioLog AG', AuftragsArtId='knid',
          AuftragsArtikel='Bio-Kürbis roter Knirps Demeter', AuftragsGebBez='IFCO 6416',
          AuftragsGebindemenge=5, AuftragsGebindeinhalt=10, AuftragsArtikelMenge=200,
          AuftragsArtikelEinheit='kg', AufPosId=5003, GewichtProArtikel=1, TotalGewicht=200),
    # 4) Zweimal dieselbe Zeile (kommt im Original vor) — zwei Läufe, kein Verlust
    zeile(AuftragsJournal='A', KundenAuftragsNr=900004, AuftragsLieferDatum=D(2026,9,4),
          AuftragsLieferant='Coop Castione', AuftragsArtId='kürbkak',
          AuftragsArtikel='Bio Kürbis Kabocha klein', AuftragsGebBez='IFCO 6416',
          AuftragsGebindemenge=1, AuftragsGebindeinhalt=10, AuftragsArtikelMenge=10,
          **{'AufPosBatchPackageQuantity Charge': 1, 'AufPosBatchQuantity Charge': 10},
          AuftragsArtikelEinheit='Stk.', AuftragsChargeManuell=1614,
          LiefProdAdrName='Imhof', AufPosId=5004, GewichtProArtikel=0.95, TotalGewicht=9.5),
    zeile(AuftragsJournal='A', KundenAuftragsNr=900004, AuftragsLieferDatum=D(2026,9,4),
          AuftragsLieferant='Coop Castione', AuftragsArtId='kürbkak',
          AuftragsArtikel='Bio Kürbis Kabocha klein', AuftragsGebBez='IFCO 6416',
          AuftragsGebindemenge=1, AuftragsGebindeinhalt=10, AuftragsArtikelMenge=10,
          **{'AufPosBatchPackageQuantity Charge': 1, 'AufPosBatchQuantity Charge': 10},
          AuftragsArtikelEinheit='Stk.', AuftragsChargeManuell=1614,
          LiefProdAdrName='Imhof', AufPosId=5004, GewichtProArtikel=0.95, TotalGewicht=9.5),
    # 5) Rücknahme: negative Menge (Gutschrift)
    zeile(AuftragsJournal='A', KundenAuftragsNr=900005, AuftragsLieferDatum=D(2026,9,5),
          AuftragsLieferant='Fahrmaadhof AG', AuftragsArtId='knik',
          AuftragsArtikel='Bio-Kürbis roter Knirps Knospe', AuftragsArtikelMenge=-300,
          AuftragsArtikelEinheit='kg', AufPosId=5005, GewichtProArtikel=1, TotalGewicht=-300),
    # 6) Kein Kürbis — darf nicht mitzählen
    zeile(AuftragsJournal='A', KundenAuftragsNr=900006, AuftragsLieferDatum=D(2026,9,5),
          AuftragsLieferant='Bio Partner Schweiz SA', AuftragsArtId='karod',
          AuftragsArtikel='Bio-Karotten Demeter', AuftragsArtikelMenge=500,
          AuftragsArtikelEinheit='kg', AufPosId=5006, GewichtProArtikel=1, TotalGewicht=500),
    # 7) Buchung mit „Kürbis" im Namen — Ware ist das keine
    zeile(AuftragsJournal='G', KundenAuftragsNr=900007, AuftragsLieferDatum=D(2026,9,5),
          AuftragsLieferant='Alfred Meister', AuftragsArtId='kürbver',
          AuftragsArtikel='Kürbisverrechnung 2026', AuftragsArtikelMenge=1,
          AuftragsArtikelEinheit='Stk.', AufPosId=5007, GewichtProArtikel=0, TotalGewicht=0),
    # 8) Ware ohne Lieferdatum, nur mit Rüstdatum
    zeile(AuftragsJournal='A', KundenAuftragsNr=900008, AuftragsRuestDatum=D(2026,9,6),
          AuftragsLieferant='Hofladen', AuftragsArtId='kürbmad',
          AuftragsArtikel='Bio Kürbis Mandarin Dem', AuftragsArtikelMenge=40,
          **{'AufPosBatchQuantity Charge': 40}, AuftragsArtikelEinheit='Stk.',
          AuftragsChargeManuell=1617, AufPosId=5008, GewichtProArtikel=0.55, TotalGewicht=22),
    # 9) Zeile ohne Positions-Id — Müll, wird gezählt und übersprungen
    zeile(AuftragsJournal='A', AuftragsLieferant='ohne Position'),
]

wb = openpyxl.Workbook()
ws = wb.active
ws.title = 'Tabelle S. 1'
ws.append(KOPF)
for r in ZEILEN:
    ws.append(r)
for zelle in ws['E'] + ws['F']:
    if zelle.row > 1:
        zelle.number_format = 'DD.MM.YYYY'
ziel = os.path.join(os.path.dirname(__file__), 'warenausgang-probe.xlsx')
wb.save(ziel)
print(f'{ziel}: {len(ZEILEN)} Zeilen')
