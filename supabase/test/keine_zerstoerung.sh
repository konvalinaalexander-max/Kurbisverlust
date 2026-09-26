#!/usr/bin/env bash
# =====================================================================
# Keine Migration darf eine Messung vernichten
#
# Der Betrieb hat es so gesagt: „mir ist dann wichtig dass die daten der
# arbeiter app von nun an richtig erfasst werden - richtig in der datenbank
# angelegt - und auch genügend geschützt dass dort nicht mehr gross
# rumgepfuscht wird von der KI und falls schon, dann nur so dass nichts
# verloren geht."
#
# Zwei Netze halten das. Das erste ist erfassung_journal (0072): jede
# Änderung an jeder Messtabelle wird festgehalten, bei einem Löschen die
# ganze alte Zeile als jsonb. Das zweite ist dieses Skript: es liest die
# Migrationen und ist rot, sobald eine davon eine Tabelle, eine Spalte
# oder Zeilen wegnimmt.
#
# Das Journal fängt, was trotzdem passiert. Dieses Skript sorgt dafür,
# dass es gar nicht erst passiert.
#
#   ./supabase/test/keine_zerstoerung.sh
#   ./supabase/test/keine_zerstoerung.sh --selbstprobe   (prüft sich selbst)
# =====================================================================
set -euo pipefail
HIER="$(cd "$(dirname "$0")" && pwd)"
MIGRATIONEN="$HIER/../migrations"

# ---------------------------------------------------------------------
# Die Freigabeliste. Jeder Eintrag ist ein Altfall, der geprüft und
# begründet ist. Wer etwas hinzufügt, schreibt den Grund dazu — sonst ist
# die Liste in einem Jahr eine Sammelstelle für alles, was mal nicht
# durchging.
#
# Format: Datei:Zeile
# ---------------------------------------------------------------------
FREIGEGEBEN=(
  # 0048 wirft den Alt-Kanal marge_messung weg. Das ist kein stilles
  # Löschen: die Migration prüft vorher, dass die Tabelle LEER ist, und
  # bricht sonst mit einer Anleitung ab („sichern, dann delete from
  # marge_messung; und setup.sql erneut ausführen"). Der Prüfstand fährt
  # diesen Abbruch in Stufe 3b ausdrücklich nach.
  "0048_ballast.sql:207"
  # 0052 legt drei Hilfstabellen für die Beispieldaten an und räumt sie
  # am Anfang und am Ende wieder weg. Sie enthalten nie eine Messung —
  # sie sind Notizzettel innerhalb einer Funktion.
  "0052_demo_saison.sql:106"
  "0052_demo_saison.sql:756"
  # 0081 schreibt demo_daten_laden() neu und benutzt dieselben drei
  # Notizzettel. Derselbe Grund, dieselbe Sorgfalt: Es sind temporäre
  # Tabellen innerhalb der Funktion, sie leben nur für die Dauer eines
  # Aufrufs, und keine davon trägt je eine Messung des Betriebs.
  "0081_die_demo_zeigt_was_die_app_kann.sql:124"
  "0081_die_demo_zeigt_was_die_app_kann.sql:988"
  # 0093 schreibt demo_daten_laden() noch einmal ganz (die Demo hinterlässt
  # Rückmeldungen) — dieselben drei Notizzettel, am selben Anfang und am
  # selben Ende der Funktion, aus demselben Grund.
  "0093_die_demo_saison_hat_rueckmeldungen.sql:81"
  "0093_die_demo_saison_hat_rueckmeldungen.sql:991"
)

# ---------------------------------------------------------------------
# Bewusst löschende Funktionen
#
# Bis 0080 kannte dieses Skript nur einen Fall: eine Anweisung, die beim
# EINSPIELEN läuft. Genau das soll sie nicht dürfen — eine Migration legt
# an und ändert, sie nimmt nichts weg.
#
# Ein „delete from x;" im RUMPF einer Funktion ist etwas anderes. Beim
# Einspielen passiert davon nichts; es passiert erst, wenn ein Mensch die
# Funktion aufruft. Der Zweck dieses Skripts („es soll gar nicht erst
# passieren") ist auf eine solche Zeile nicht anwendbar: Sie ist kein
# Vorgang, sondern ein Werkzeug, das dem Betrieb in die Hand gegeben wird.
#
# Solche Funktionen gibt es. `erfassung_leeren()` macht vor einem Testtag
# Tabula rasa, weil der Betrieb genau das gebraucht hat. Sie steht hier
# mit Namen — und die Freigabe ist keine Ausnahme, sondern eine Zusage,
# die geprüft wird: Der Wächter verlangt, dass jede dieser Funktionen ihre
# Absicherung TRÄGT (unten, ABSICHERUNG). Nimmt jemand später den
# Betriebsleiter oder das Bestätigungswort heraus, ist dieses Skript rot.
#
# Ausserhalb dieser Rümpfe gilt unverändert alles wie vorher. `drop table`
# und `truncate` sind auch INNERHALB nicht erlaubt: Die beiden nimmt kein
# Journal auf, weil mit der Tabelle auch ihr Auslöser verschwindet.
#
# (demo_daten_entfernen() steht hier nicht: Seine Anweisungen tragen alle
# ein `where` und sind nie aufgefallen.)
# ---------------------------------------------------------------------
BEWUSST_LOESCHEND=(
  "erfassung_leeren"
)

# Woran man eine abgesicherte Funktion erkennt. Format: Regex::Klartext.
# Geprüft wird der Rumpf OHNE Kommentare — eine Absicherung, die nur noch
# im Kommentar steht, ist keine.
ABSICHERUNG=(
  'not[[:space:]]+ist_admin\(\)::die Abfrage auf den Betriebsleiter (not ist_admin())'
  'p_bestaetigung[[:space:]]+is[[:space:]]+distinct[[:space:]]+from::den Vergleich mit dem Bestätigungswort (p_bestaetigung is distinct from …)'
  'raise[[:space:]]+exception::den Abbruch (raise exception)'
)

# ---------------------------------------------------------------------
# Wonach gesucht wird
# ---------------------------------------------------------------------
# Bewusst NICHT gesucht wird nach:
#   · drop view / drop materialized view — Sichten sind Rechenwerk, keine
#     Daten. Sie werden in jeder Runde neu gebaut, das ist ihr Zweck.
#   · drop function — dasselbe.
#   · drop constraint — die Migrationen schreiben durchweg
#     „drop constraint if exists X" unmittelbar vor „add constraint X",
#     um die Bedingung neu zu setzen. Dass eine Zusage danach wieder
#     gilt, prüft 0067 gesondert („Zusage … bestätigt").
MUSTER=(
  'drop[[:space:]]+table'
  'drop[[:space:]]+column'
  'truncate'
)

freigegeben() {
  local treffer="$1" f
  for f in "${FREIGEGEBEN[@]}"; do [ "$treffer" = "$f" ] && return 0; done
  return 1
}

# ---------------------------------------------------------------------
# Die Rümpfe der bewusst löschenden Funktionen in einer Datei finden.
#
# Ausgegeben wird je Fund eine Zeile „von:bis:name". Findet sich zu einem
# geöffneten Rumpf kein Ende, kommt stattdessen „OFFEN:von:name" heraus —
# und dann wird NICHTS freigestellt. Im Zweifel gilt die strengere Regel;
# sonst könnte ein vergessenes Dollar-Zeichen den ganzen Rest einer Datei
# aus der Prüfung nehmen.
# ---------------------------------------------------------------------
bereiche() {
  local datei="$1" namen
  [ "${#BEWUSST_LOESCHEND[@]}" -eq 0 ] && return 0
  namen="$(printf '%s|' "${BEWUSST_LOESCHEND[@]}")"; namen="${namen%|}"
  awk -v namen="$namen" '
    # Beginnt in dieser Zeile eine Funktion, die auf der Liste steht?
    # Gibt ihren Namen zurück, sonst die leere Zeichenkette.
    function beginnt(z,   teile, i, n) {
      n = split(namen, teile, "|")
      for (i = 1; i <= n; i++)
        if (z ~ ("create[ \t]+(or[ \t]+replace[ \t]+)?function[ \t]+(public\\.)?" \
                 teile[i] "[ \t]*\\(")) return teile[i]
      return ""
    }
    {
      if (!drin) {
        name = beginnt(tolower($0))
        if (name == "") next
        drin = 1; von = NR; tag = ""
      }
      rest = $0
      # Das erste Dollar-Zeichen öffnet den Rumpf. In dieser Datenbank
      # steht es am Zeilenende („… as $fn$"), gesucht wird es aber
      # überall: Eine einzeilige Funktion („as $$ select 1 $$;") darf den
      # Wächter nicht in die Irre führen.
      if (tag == "") {
        if (!match(rest, /\$[a-zA-Z_]*\$/)) next
        tag = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
      }
      # Dasselbe Dollar-Zeichen schliesst ihn wieder.
      if (index(rest, tag) > 0) { print von ":" NR ":" name; drin = 0 }
    }
    END { if (drin) print "OFFEN:" von ":" name }
  ' "$datei"
}

# Die Bereiche je Datei nur einmal rechnen (die Treffer kommen nach Datei
# sortiert herein). Bash 3.2 kennt keine assoziativen Felder — ein Paar
# aus Pfad und Ergebnis reicht.
B_DATEI=""
B_WERTE=""
bereiche_gepuffert() {
  if [ "$1" != "$B_DATEI" ]; then
    B_DATEI="$1"
    B_WERTE="$(bereiche "$1")"
  fi
  printf '%s\n' "$B_WERTE"
}

# Steht diese Zeile im Rumpf einer bewusst löschenden Funktion?
im_rumpf() {                       # datei_pfad zeilennummer
  local datei="$1" nr="$2" b von bis
  for b in $(bereiche_gepuffert "$datei"); do
    case "$b" in OFFEN:*) continue ;; esac
    von="${b%%:*}"; bis="${b#*:}"; bis="${bis%%:*}"
    [ "$nr" -ge "$von" ] && [ "$nr" -le "$bis" ] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------
# Der Durchgang über ein Verzeichnis. Jede Beanstandung ist eine Zeile
# „  ✗ …" auf der Standardausgabe; gezählt wird beim Aufrufer. (Ein
# Rückgabewert taugt dafür nicht: Bei 256 Beanstandungen wäre er 0.)
# ---------------------------------------------------------------------
durchgang() {
  local verzeichnis="$1" muster zeile pfad datei rest nr text
  local name b von bis rumpf eintrag regex klartext treffer frei

  for muster in "${MUSTER[@]}"; do
    while IFS= read -r zeile; do
      [ -z "$zeile" ] && continue
      datei="$(basename "${zeile%%:*}")"
      rest="${zeile#*:}"; nr="${rest%%:*}"
      text="$(echo "${rest#*:}" | sed 's/^[[:space:]]*//' | cut -c1-90)"
      if freigegeben "$datei:$nr"; then continue; fi
      echo "  ✗ $datei:$nr  $text"
    done < <(grep -rnHiE "$muster" "$verzeichnis"/*.sql || true)
  done

  # „delete from <tabelle>" ohne where — trifft alle Zeilen auf einmal.
  #
  # Und seit 0080 ebenso „… where true" (oder „where 1=1"). Der Grund ist
  # nicht Pedanterie: Supabase lässt die API-Verbindung mit der Sicherung
  # „safeupdate" laufen, die ein DELETE ohne WHERE abweist. Wer wirklich
  # alles löschen will, MUSS also ein where hinschreiben — und genau damit
  # wäre er hier unsichtbar geworden. Ein Wächter, den man mit drei Wörtern
  # aushebelt, ist keiner. Beide Formen sagen dasselbe („alle Zeilen"),
  # also behandelt er sie gleich.
  #
  # Übersprungen wird nur, was gar keine Anweisung ist: eine Kommentar-
  # zeile oder eine Zeile, die im Fliesstext einer Zeichenkette steht
  # (dort kommt sie als Anleitung für den Betriebsleiter vor). Geprüft
  # wird der ANFANG der Zeile — ein Apostroph irgendwo weiter hinten darf
  # eine echte Anweisung nicht unsichtbar machen.
  frei=0
  while IFS= read -r zeile; do
    [ -z "$zeile" ] && continue
    pfad="${zeile%%:*}"; datei="$(basename "$pfad")"
    rest="${zeile#*:}"; nr="${rest%%:*}"
    text="$(echo "${rest#*:}" | sed 's/^[[:space:]]*//')"
    case "$text" in
      --*|"'"*) continue ;;        # Kommentar oder Fliesstext
    esac
    if freigegeben "$datei:$nr"; then continue; fi
    if im_rumpf "$pfad" "$nr"; then frei=$((frei + 1)); continue; fi
    echo "  ✗ $datei:$nr  $(echo "$text" | cut -c1-90)"
  done < <(grep -rnHiE "^[[:space:]]*delete[[:space:]]+from[[:space:]]+[a-z_]+[[:space:]]*(;|where[[:space:]]+(true|1[[:space:]]*=[[:space:]]*1)[[:space:]]*;)" \
             "$verzeichnis"/*.sql || true)

  # Jede freigestellte Funktion muss ihre Absicherung tragen. Ohne diese
  # Prüfung wäre die Liste oben ein Freibrief: Man nähme die Abfrage auf
  # den Betriebsleiter heraus, und niemandem fiele es auf.
  for name in "${BEWUSST_LOESCHEND[@]}"; do
    treffer=0
    for datei in "$verzeichnis"/*.sql; do
      [ -e "$datei" ] || continue
      for b in $(bereiche "$datei"); do
        case "$b" in
          OFFEN:*)
            von="${b#OFFEN:}"; von="${von%%:*}"
            [ "${b##*:}" = "$name" ] || continue
            echo "  ✗ $(basename "$datei"):$von  $name() — der Rumpf wird nie geschlossen; nichts freigestellt"
            treffer=$((treffer + 1))
            continue ;;
        esac
        [ "${b##*:}" = "$name" ] || continue
        von="${b%%:*}"; bis="${b#*:}"; bis="${bis%%:*}"
        treffer=$((treffer + 1))
        # Rumpf ohne Kommentare: was nur noch im Kommentar steht, zählt nicht.
        rumpf="$(sed -n "${von},${bis}p" "$datei" | sed 's/--.*$//')"
        for eintrag in "${ABSICHERUNG[@]}"; do
          regex="${eintrag%%::*}"; klartext="${eintrag##*::}"
          if ! printf '%s\n' "$rumpf" | grep -qiE "$regex"; then
            echo "  ✗ $(basename "$datei"):$von  $name() hat $klartext verloren"
          fi
        done
      done
    done
    if [ "$treffer" -eq 0 ]; then
      echo "  ✗ $name() steht in BEWUSST_LOESCHEND, ist aber in keiner Migration zu finden"
    fi
  done

  # Keine Beanstandung, aber eine Zahl, die auffällt, wenn sie springt.
  echo "  # freigestellt: $frei"
}

# Zählt die „✗"-Zeilen einer Ausgabe.
beanstandungen() {
  printf '%s\n' "$1" | grep -c '✗' || true
}

# ---------------------------------------------------------------------
# Selbstprobe: Ein Wächter, der nie anschlägt, ist kein Wächter.
#
# Jeder Fall prüft nicht nur ROT oder GRÜN, sondern die BEGRÜNDUNG. Sonst
# beweist ein roter Fall nichts: Er könnte aus einem ganz anderen Grund
# rot sein als aus dem, den er zu prüfen vorgibt.
# ---------------------------------------------------------------------
if [ "${1:-}" = "--selbstprobe" ]; then
  echo "── Selbstprobe des Wächters ───────────────────────────────────"
  PROBE="$(mktemp -d)"
  trap 'rm -rf "$PROBE"' EXIT
  FEHLER=0
  # Gezählt statt hingeschrieben: Eine Zahl im Schlusssatz, die man beim
  # Hinzufügen eines Falls von Hand nachziehen muss, steht irgendwann falsch da.
  FAELLE=0

  # Die abgesicherte Funktion, so wie 0080 sie schreibt. Das
  # Bestätigungswort steht hier als chr()-Ausdruck, damit in dieser Datei
  # kein zweites „ALLES LOESCHEN" steht, das jemand für echt hält.
  GESICHERT='create or replace function erfassung_leeren(p_bestaetigung text)
returns text language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is not null and not ist_admin() then
    raise exception (chr(65));
  end if;
  if p_bestaetigung is distinct from (chr(66)) then
    raise exception (chr(67));
  end if;
  delete from palette;
  delete from auftrag;
  return (chr(68));
end $fn$;'

  probe() {        # name  rot|gruen  marker  inhalt  [ohne_grundlage]
    local name="$1" erwartung="$2" marker="$3" inhalt="$4" ohne="${5:-}"
    local ausgabe anzahl
    FAELLE=$((FAELLE + 1))
    rm -f "$PROBE"/*.sql
    # Ohne Gegengewicht wäre jeder Fall schon deshalb rot, weil die
    # gelistete Funktion im Verzeichnis fehlt. Die Grundlage sorgt dafür,
    # dass ein roter Fall wirklich am Fall liegt.
    [ -n "$ohne" ] || printf '%s\n' "$GESICHERT" > "$PROBE/0001_grundlage.sql"
    printf '%s\n' "$inhalt" > "$PROBE/9999_probe.sql"
    ausgabe="$(durchgang "$PROBE" 2>&1)"
    anzahl="$(beanstandungen "$ausgabe")"
    if [ "$erwartung" = "gruen" ]; then
      if [ "$anzahl" -eq 0 ]; then echo "  ✓ $name"; return 0; fi
      echo "  ✗ $name — sollte grün sein, ist aber rot:"
      printf '%s\n' "$ausgabe" | grep '✗' | sed 's/^/      /'
      FEHLER=$((FEHLER + 1)); return 0
    fi
    if [ "$anzahl" -eq 0 ]; then
      echo "  ✗ $name — bleibt grün; der Wächter ist an dieser Stelle stumpf"
      FEHLER=$((FEHLER + 1)); return 0
    fi
    if ! printf '%s\n' "$ausgabe" | grep -q "$marker"; then
      echo "  ✗ $name — rot, aber aus dem falschen Grund (kein „$marker\"):"
      printf '%s\n' "$ausgabe" | grep '✗' | sed 's/^/      /'
      FEHLER=$((FEHLER + 1)); return 0
    fi
    echo "  ✓ $name"
  }

  probe "nacktes delete ausserhalb jeder Funktion ist rot" \
        rot "9999_probe.sql:1" \
        'delete from palette;'

  # Seit 0080: „where true" ist die Form, die safeupdate verlangt — und
  # genau deshalb die Form, mit der man sonst an dieser Wache vorbeikäme.
  probe "delete … where true ausserhalb jeder Funktion ist rot" \
        rot "9999_probe.sql:1" \
        'delete from palette where true;'

  probe "delete … where 1=1 ausserhalb jeder Funktion ist rot" \
        rot "9999_probe.sql:1" \
        'delete from palette where 1 = 1;'

  probe "ein echtes where bleibt erlaubt" \
        gruen "" \
        "delete from palette where extern_id like 'demo-%';"

  probe "delete im Rumpf einer NICHT gelisteten Funktion ist rot" \
        rot "9999_probe.sql:10" \
        "$(printf '%s\n' "$GESICHERT" | sed 's/erfassung_leeren/etwas_anderes/')"

  probe "delete im Rumpf der gelisteten, abgesicherten Funktion ist grün" \
        gruen "" \
        "$GESICHERT"

  probe "gelistete Funktion ohne ist_admin ist rot" \
        rot "Betriebsleiter" \
        "$(printf '%s\n' "$GESICHERT" | sed 's/not ist_admin()/true/')" ohne_grundlage

  probe "gelistete Funktion ohne Bestätigungswort ist rot" \
        rot "Bestätigungswort" \
        "$(printf '%s\n' "$GESICHERT" | sed 's/p_bestaetigung is distinct from (chr(66))/false/')" ohne_grundlage

  probe "Absicherung nur noch im Kommentar ist rot" \
        rot "Betriebsleiter" \
        "$(printf '%s\n' "$GESICHERT" | sed 's|not ist_admin()|true then null; end if; -- not ist_admin()|')" ohne_grundlage

  # Fängt den Fall, an dem die erste Fassung scheiterte: `grep -r` über ein
  # Verzeichnis mit nur EINER Datei verschweigt den Dateinamen, und dann
  # rutscht die Zeilennummer an die Stelle der Datei. Ein Fund, der seine
  # Datei nicht nennen kann, ist kein Fund.
  probe "eine einzelne Datei wird beim Namen genannt" \
        rot "9999_probe.sql:1" \
        'delete from palette;' ohne_grundlage

  probe "gelisteter Name, den es nirgends gibt, ist rot" \
        rot "in keiner Migration zu finden" \
        'select 1;' ohne_grundlage

  probe "drop table bleibt rot, auch im Rumpf der gelisteten Funktion" \
        rot "9999_probe.sql" \
        "$(printf '%s\n' "$GESICHERT" | sed 's/delete from palette;/drop table palette;/')"

  probe "truncate bleibt rot, auch im Rumpf der gelisteten Funktion" \
        rot "9999_probe.sql" \
        "$(printf '%s\n' "$GESICHERT" | sed 's/delete from palette;/truncate palette;/')"

  probe "unbeendeter Rumpf stellt den Rest der Datei nicht frei" \
        rot "delete from charge" \
        "$(printf '%s\n' "$GESICHERT" | sed 's/^end \$fn\$;$/end;/')
delete from charge;" ohne_grundlage

  echo "───────────────────────────────────────────────────────────────"
  if [ "$FEHLER" -gt 0 ]; then
    echo "  $FEHLER Fall/Fälle der Selbstprobe sind nicht eingetreten."
    echo "  Der Wächter misst nicht, was er zu messen behauptet."
    echo "───────────────────────────────────────────────────────────────"
    exit 1
  fi
  echo "  OK  $FAELLE gebaute Fälle, jeder schlägt an — und aus dem richtigen Grund."
  echo "───────────────────────────────────────────────────────────────"
  exit 0
fi

# ---------------------------------------------------------------------
# Der eigentliche Lauf
# ---------------------------------------------------------------------
echo "── Keine Zerstörung ───────────────────────────────────────────"

AUSGABE="$(durchgang "$MIGRATIONEN")"
GEFUNDEN="$(beanstandungen "$AUSGABE")"
FREIGESTELLT="$(printf '%s\n' "$AUSGABE" | sed -n 's/^  # freigestellt: //p')"
printf '%s\n' "$AUSGABE" | grep '✗' || true

if [ "$GEFUNDEN" -gt 0 ]; then
  echo
  echo "  $GEFUNDEN Anweisung(en), die Daten wegnehmen."
  echo "  Eine Migration legt an und ändert — sie nimmt nichts weg. Was nicht"
  echo "  mehr gebraucht wird, verschwindet aus der Oberfläche und bekommt im"
  echo "  Schema einen Kommentar. Ist der Fall wirklich unvermeidlich, gehört"
  echo "  er mit Begründung in die Freigabeliste oben in diesem Skript."
  echo
  echo "  Löscht die Anweisung erst auf Knopfdruck eines Menschen, gehört ihre"
  echo "  Funktion mit Namen in BEWUSST_LOESCHEND — und muss dann den"
  echo "  Betriebsleiter und das Bestätigungswort abfragen."
  echo "───────────────────────────────────────────────────────────────"
  exit 1
fi

ANZ_DATEIEN="$(ls "$MIGRATIONEN"/*.sql | wc -l | tr -d ' ')"
echo "  OK  $ANZ_DATEIEN Migrationen, keine nimmt beim Einspielen Daten weg"
echo "      (${#FREIGEGEBEN[@]} geprüfte Altfälle in der Freigabeliste;"
echo "       ${#BEWUSST_LOESCHEND[@]} bewusst löschende Funktion(en) mit geprüfter"
echo "       Absicherung, $FREIGESTELLT Anweisung(en) in ihren Rümpfen)"
echo "───────────────────────────────────────────────────────────────"
