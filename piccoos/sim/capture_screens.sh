#!/usr/bin/env bash
# Capture PiccoOS simulator screenshots for review and CI artifacts.
#
# Usage:
#   piccoos/sim/capture_screens.sh <simulator-program> <corpus-dir> <out-dir>
#
#   <simulator-program>  e.g. .pio/build/simulator_picco/program (relative or absolute)
#   <corpus-dir>         output of make_corpus.py (contains books/)
#   <out-dir>            screenshots (*.bmp, *.png), logs and summary.txt land here
#
# Input-script timing (crosspoint-simulator README, "Automated QA"; HalGPIO.cpp):
#   `<ms>:<ACTION>` times are ABSOLUTE within a segment, not delays from the previous
#   step. Every WAIT starts a new segment whose clock starts when the WAIT matches.
#   Events in a segment are sorted by time, so a later-listed step with a smaller time
#   runs first. v3 used delays (`1500:SHOT;500:QUIT`), so QUIT fired before SHOT.
#   lint_script() below rejects non-increasing times and anything after QUIT.
#
# Scenarios
#   REQUIRED (failure fails the run):
#     home_lyra        default theme, Home screen
#     home_cover_grid  upstream COVER_GRID (uiTheme=4), reference for D-017
#     home_balanced    PiccoOS Balanced 3.0 (homeLayout=1), D-034
#   EXPERIMENTAL (reported, never fails the run):
#     library                   Home -> DOWN (NavNext) -> ENTER -> Library (button path)
#     library_tap               Home -> TAP Library row (0.50, 0.5225) -> Library (touch path)
#     home_balanced_reading     Balanced + 4 recent books injected; cover+Cyrillic wrapping test
#     home_balanced_empty       Balanced with empty SD; tests empty-state render path
#     home_balanced_reader_landscape_setting   Balanced + orientation=1; C-4 accepted (D-036)
#
# A required scenario passes only if ALL hold:
#   - the simulator exits with status 0 within the per-scenario timeout,
#   - its log shows the expected activity ("Entering activity: Home"),
#   - the log contains "[SIM] Saved screenshot: <path>" for every expected frame,
#   - every expected screenshot exists, is non-empty, is 480x800 (Picco portrait)
#     and is not a blank frame (size/blank checks need Pillow).
# Expected screenshots are deleted before their scenario, so a stale file from a
# previous run can never pass. home_cover_grid must also differ visibly from
# home_lyra (proves the theme setting took effect; still review it by eye).
#
# Env:
#   HEADLESS=1 (default) uses SDL's dummy video driver; HEADLESS=0 shows the window.
#   SCENARIO_TIMEOUT_S (default 120)  hard limit per scenario (process is killed).
#   RUN_TIMEOUT_S (default 600)       budget for the scenarios: each one gets
#                                     min(SCENARIO_TIMEOUT_S, time left); when nothing is left
#                                     the rest are SKIPPED (required = fail). Setup, image checks
#                                     and PNG conversion are outside this budget; the CI step's
#                                     timeout-minutes is the hard outer limit.
#
# SIM results only (Decision Log D-014). This script never touches a device.
set -uo pipefail

usage() { echo "usage: $0 <simulator-program> <corpus-dir> <out-dir>" >&2; exit 2; }
[ $# -eq 3 ] || usage

abspath() { # portable (macOS has no `realpath -m` by default)
  local p=$1
  if [ -d "$p" ]; then (cd "$p" && pwd); else (cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd)" "$(basename "$p")"); fi
}

PROGRAM=$(abspath "$1") || { echo "bad program path: $1" >&2; exit 2; }
CORPUS=$(abspath "$2") || { echo "bad corpus path: $2" >&2; exit 2; }
mkdir -p "$3" || exit 2
OUT=$(abspath "$3")
SIM_DIR="$(abspath "$(dirname "$0")")"

[ -f "$PROGRAM" ] && [ -x "$PROGRAM" ] || { echo "not an executable file: $PROGRAM" >&2; exit 2; }
ls "$CORPUS"/books/*.epub >/dev/null 2>&1 || { echo "no EPUBs in $CORPUS/books" >&2; exit 2; }

SCENARIO_TIMEOUT_S=${SCENARIO_TIMEOUT_S:-120}
RUN_TIMEOUT_S=${RUN_TIMEOUT_S:-600}
RUN_START=$(date +%s)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/piccoos-sim.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

if [ "${HEADLESS:-1}" = "1" ]; then export SDL_VIDEODRIVER=dummy; fi
# The dummy video driver has no accelerated renderer; HalDisplay::begin() asks for
# SDL_RENDERER_ACCELERATED, gets NULL, and presentIfNeeded() then silently skips SHOT.
# Naming the software renderer bypasses the flag check (verified, SDL 2.32.10).
if [ "${HEADLESS:-1}" = "1" ]; then export SDL_RENDER_DRIVER=software; fi
# WAIT steps inside the simulator time out on their own (exit 1); each scenario
# sets that below its hard limit (see run_scenario).
export CROSSPOINT_SIM_SCREEN_TEXT=1

HAVE_PIL=0
python3 -c "import PIL" 2>/dev/null && HAVE_PIL=1

SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"
required_failures=0

# shellcheck source=lib_validate.sh
source "$SIM_DIR/lib_validate.sh"

# run_with_timeout <seconds> <log> <cmd...> — portable (no GNU `timeout` on macOS).
run_with_timeout() {
  local secs=$1 log=$2; shift 2
  "$@" > "$log" 2>&1 &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      echo "[capture_screens] killed after ${secs}s" >> "$log"
      return 124
    fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid"
}

# check_image <path> -> 0 ok, 1 missing/empty, 3 blank
check_image() {
  local img=$1
  [ -s "$img" ] || return 1
  [ "$HAVE_PIL" = "1" ] || return 0
  python3 - "$img" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
if im.size != (480, 800):
    print(f"size {im.size[0]}x{im.size[1]}")
    sys.exit(4)
lo, hi = im.convert("L").getextrema()
sys.exit(3 if hi - lo < 16 else 0)  # a single-tone frame means nothing was drawn
PY
}

# lint_script <script> <timeline-file> -> 0 ok; prints the problem otherwise.
# Always writes the parsed timeline (segment, time, action) for diagnosis.
lint_script() {
  python3 - "$1" "$2" <<'PY'
import sys
seg_last, quit_seen, seg = -1, False, 0
lines = ["# segment  at_ms  step   (at_ms is absolute within the segment; WAIT starts the next one)"]
for n, step in enumerate(sys.argv[1].split(";"), 1):
    lines.append(f"{seg:>9}  {step.partition(':')[0]:>5}  {step.partition(':')[2]}")
    open(sys.argv[2], "w").write("\n".join(lines) + "\n")
    t, _, rest = step.partition(":")
    action = rest.split(":", 1)[0].upper()
    if quit_seen:
        sys.exit(print(f"step {n} after QUIT: {step}") or 1)
    if not t.isdigit():
        sys.exit(print(f"step {n} has no time: {step}") or 1)
    if int(t) < seg_last:
        sys.exit(print(f"step {n} time {t} < previous {seg_last} in the same segment: {step}") or 1)
    seg_last = int(t)
    if action == "WAIT":
        seg_last = -1          # next step starts a new segment (clock restarts at match)
        seg += 1
    quit_seen = action == "QUIT"
if not quit_seen:
    sys.exit(print("script does not end with QUIT") or 1)
PY
}

# validator_selftest: run T1-T12 unit tests before any simulator scenarios.
# Failures are required; scenarios still run for diagnostics.
selftest_rc=0
"$SIM_DIR/test_validate_home.sh" > "$OUT/validator_selftest.log" 2>&1 || selftest_rc=$?
if [ "$selftest_rc" -ne 0 ]; then
  echo "required validator_selftest FAIL (exit $selftest_rc; see validator_selftest.log)" | tee -a "$SUMMARY"
  required_failures=$((required_failures + 1))
else
  echo "required validator_selftest PASS" | tee -a "$SUMMARY"
fi

# run_scenario <required|experimental> <name> <settings-json-or-empty> <script> <expected-images...>
run_scenario() {
  local kind=$1 name=$2 settings=$3 script=$4; shift 4
  local img
  rm -f "$OUT/$name.log" "$OUT/$name.timeline.txt"  # F3: stale artifacts from prior runs
  for img in "$@"; do rm -f "$OUT/$img" "$OUT/${img%.bmp}.png"; done
  local lint_msg
  if ! lint_msg=$(lint_script "$script" "$OUT/$name.timeline.txt"); then
    echo "$kind $name FAIL bad input script: $lint_msg" | tee -a "$SUMMARY"
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
    return 0
  fi
  local remaining=$(( RUN_TIMEOUT_S - ($(date +%s) - RUN_START) ))
  if [ "$remaining" -lt 5 ]; then
    echo "$kind $name SKIPPED run timeout (${RUN_TIMEOUT_S}s) reached" | tee -a "$SUMMARY"
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
    return 0
  fi
  local limit=$SCENARIO_TIMEOUT_S
  [ "$remaining" -lt "$limit" ] && limit=$remaining
  local sd="$WORK/$name"
  mkdir -p "$sd/books" "$sd/.crosspoint" || {
    echo "$kind $name FAIL setup: mkdir failed" | tee -a "$SUMMARY"
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
    return 0
  }
  cp "$CORPUS"/books/*.epub "$sd/books/" || {
    echo "$kind $name FAIL setup: cp books failed" | tee -a "$SUMMARY"
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
    return 0
  }
  # Assumption (verify on first run): keys missing from settings.json keep defaults.
  if [ -n "$settings" ]; then
    printf '%s\n' "$settings" > "$sd/.crosspoint/settings.json" || {
      echo "$kind $name FAIL setup: write settings.json failed" | tee -a "$SUMMARY"
      [ "$kind" = required ] && required_failures=$((required_failures + 1))
      return 0
    }
  fi
  # PiccoOS: optional extra SD setup (set _EXTRA_SD_SETUP=fn_name before calling).
  if [ -n "${_EXTRA_SD_SETUP:-}" ]; then
    local setup_fn="${_EXTRA_SD_SETUP}"
    _EXTRA_SD_SETUP=
    "${setup_fn}" "$sd" "$CORPUS" || {
      echo "$kind $name FAIL setup: '${setup_fn}' failed" | tee -a "$SUMMARY"
      [ "$kind" = required ] && required_failures=$((required_failures + 1))
      return 0
    }
  fi

  local log="$OUT/$name.log" start rc status="PASS" reason=""
  start=$(date +%s)
  ( cd "$sd" || exit 2
    export CROSSPOINT_SIM_SD="$sd" CROSSPOINT_SIM_INPUT_SCRIPT="$script"
    export CROSSPOINT_SIM_WAIT_TIMEOUT_MS=$(( (limit > 15 ? limit - 10 : 5) * 1000 ))
    run_with_timeout "$limit" "$log" "$PROGRAM" )
  rc=$?
  local secs=$(( $(date +%s) - start ))

  if [ $rc -eq 124 ]; then status=FAIL; reason="timeout ${limit}s"
  elif [ $rc -ne 0 ]; then status=FAIL; reason="exit $rc"
  elif ! grep -q "Entering activity: Home" "$log"; then status=FAIL; reason="Home activity not in log"
  fi
  for img in "$@"; do
    if ! grep -qF "[SIM] Saved screenshot: $OUT/$img" "$log"; then
      status=FAIL; reason="${reason:+$reason; }SHOT not executed for $img"
      continue
    fi
    local size_msg
    size_msg=$(check_image "$OUT/$img"); case $? in
      0) ;;
      3) status=FAIL; reason="${reason:+$reason; }blank $img" ;;
      4) status=FAIL; reason="${reason:+$reason; }$img $size_msg (want 480x800)" ;;
      *) status=FAIL; reason="${reason:+$reason; }missing $img" ;;
    esac
  done
  echo "$kind $name $status ${secs}s ${reason}" | tee -a "$SUMMARY"
  if [ "$status" = FAIL ]; then
    tail -n 15 "$log" >&2
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
  fi
  return 0
}

run_scenario required home_lyra "" \
  "0:WAIT:Entering activity: Home;1500:SHOT:$OUT/home_lyra.bmp;3000:QUIT" \
  home_lyra.bmp

run_scenario required home_cover_grid '{"uiTheme":4}' \
  "0:WAIT:Entering activity: Home;5000:SHOT:$OUT/home_cover_grid.bmp;6500:QUIT" \
  home_cover_grid.bmp

# PiccoOS: Balanced 3.0 Home screen (D-034)
run_scenario required home_balanced '{"uiTheme":1,"homeLayout":1}' \
  "0:WAIT:Entering activity: Home;5000:SHOT:$OUT/home_balanced.bmp;6500:QUIT" \
  home_balanced.bmp

# F-4: home_balanced validation via lib_validate.sh (fail-closed, R3, F2).
run_home_validation \
  "$OUT/home_balanced.bmp" "$OUT/home_balanced.log" "$OUT/home_lyra.bmp" \
  required home_balanced_validate
# Self-check: bmp=home_lyra (standard), log=home_lyra.log, ref=home_balanced (different layout).
# PASS only if validator rejects home_lyra (log=FAIL, pixel_sig=FAIL); validator error → FAIL.
run_home_selfcheck \
  "$OUT/home_lyra.bmp" "$OUT/home_lyra.log" "$OUT/home_balanced.bmp" \
  required home_balanced_selfcheck

# home_cover_grid must not look like home_lyra (otherwise uiTheme=4 was ignored).
if [ "$HAVE_PIL" = "1" ] && [ -s "$OUT/home_lyra.bmp" ] && [ -s "$OUT/home_cover_grid.bmp" ]; then
  diff_out=$(python3 - "$OUT/home_lyra.bmp" "$OUT/home_cover_grid.bmp" <<'PY'
import sys
from PIL import Image, ImageChops
a, b = (Image.open(p).convert("L") for p in sys.argv[1:3])
if a.size != b.size:
    print(-1)  # size mismatch is reported by the per-image check, not as "different"
else:
    d = ImageChops.difference(a, b).point(lambda v: 255 if v > 32 else 0)
    total = a.size[0] * a.size[1]
    changed = d.histogram()[255]
    print(changed, total)
PY
)
  diff_changed=$(echo "$diff_out" | awk '{print $1}')
  diff_total=$(echo "$diff_out" | awk '{print $2}')
  if [ "$diff_changed" = "-1" ]; then
    echo "required cover_grid_differs SKIP frame sizes differ (see per-image check)" | tee -a "$SUMMARY"
  elif [ "$((diff_changed * 100))" -ge "$((diff_total * 5))" ]; then
    diff_pct=$(awk "BEGIN{printf \"%.2f\", 100.0*$diff_changed/$diff_total}")
    echo "required cover_grid_differs PASS ${diff_pct}% pixels differ from home_lyra" | tee -a "$SUMMARY"
  else
    diff_pct=$(awk "BEGIN{printf \"%.2f\", 100.0*$diff_changed/$diff_total}")
    echo "required cover_grid_differs FAIL only ${diff_pct}% pixels differ (theme setting not applied?)" | tee -a "$SUMMARY"
    required_failures=$((required_failures + 1))
  fi
fi

# Fresh SD, no open book: Home selector starts on "Browse Files"; DOWN -> "Library".
run_scenario experimental library "" \
  "0:WAIT:Entering activity: Home;1000:DOWN;1600:ENTER;1700:WAIT:Entering activity: Library;4000:SHOT:$OUT/library_p1.bmp;4500:DOWN;6500:SHOT:$OUT/library_p2.bmp;8000:QUIT" \
  library_p1.bmp library_p2.bmp

# Touch path (coordinate from the parallel ChatGPT Work patch). y=0.5225*800=418 px
# is the centre of the Lyra "Library" row: menuTop 56+242+16=314, row step 64+8,
# row 1 = 386..450 (LyraTheme.h metrics, assuming they are not scaled on Picco).
run_scenario experimental library_tap "" \
  "0:WAIT:Entering activity: Home;1500:TAP:0.50,0.5225;1600:WAIT:Entering activity: Library;4000:SHOT:$OUT/library_tap.bmp;5500:QUIT" \
  library_tap.bmp

# -------------------------------------------------------------------------
# PiccoOS: Balanced 3.0 extended scenarios (experimental — never fail CI)
# -------------------------------------------------------------------------

# inject_recent_books <sd-dir> <corpus-dir>
# Pre-populates /.crosspoint/recent.json with 4 entries pointing to corpus EPUBs.
# Titles are long Cyrillic strings to exercise wrappedText on Hero/Recent slots.
# Hardened: checks Python exit code, verifies 4 entries written, errors → FAIL.
inject_recent_books() {
  local sd=$1 corpus=$2
  local out
  out=$(python3 - "$sd" "$corpus" <<'PY'
import json, pathlib, sys
sd = pathlib.Path(sys.argv[1])
epubs = sorted((sd / "books").glob("*.epub"))
if not epubs:
    print("inject_recent_books: no EPUBs in", sd / "books", file=sys.stderr)
    sys.exit(1)
if len(epubs) < 4:
    print(f"inject_recent_books: need at least 4 EPUBs in corpus, found {len(epubs)}", file=sys.stderr)
    sys.exit(1)
titles = [
    "Достопримечательности: записки наблюдателя по дороге домой",
    "Человеконенавистничество и другие истории",
    "Высокопревосходительство: в двух частях о котором никто не помнил",
]
authors = ["Анна Соколова", "Пётр Белов", "Мария Кузнецова"]
entries = [{"path": f"/books/{epubs[i].name}", "title": titles[i % len(titles)],
            "author": authors[i % len(authors)], "coverBmpPath": ""} for i in range(4)]
dest = sd / ".crosspoint" / "recent.json"
dest.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")
# Verify round-trip: read back and confirm exactly 4 entries.
loaded = json.loads(dest.read_text(encoding="utf-8"))
if len(loaded) != 4:
    print(f"inject_recent_books: wrote 4 entries but read back {len(loaded)}", file=sys.stderr)
    sys.exit(1)
print("inject_recent_books: 4 entries OK")
PY
  ) || { echo "inject_recent_books FAILED (python exit $?): $out" >&2; return 1; }
  echo "$out"
  # Confirm exactly 4 entries written.
  echo "$out" | grep -qE "^inject_recent_books: 4 entries OK$" || {
    echo "inject_recent_books: unexpected output: $out" >&2; return 1
  }
}

# run_empty_scenario: variant of run_scenario that creates an SD card with no
# EPUBs. Used to test the empty-state Home screen render path.
run_empty_scenario() {
  local kind=$1 name=$2 settings=$3 script=$4; shift 4
  rm -f "$OUT/$name.log" "$OUT/$name.timeline.txt"  # F3: stale artifacts from prior runs
  for img in "$@"; do rm -f "$OUT/$img" "$OUT/${img%.bmp}.png"; done
  local lint_msg
  if ! lint_msg=$(lint_script "$script" "$OUT/$name.timeline.txt"); then
    echo "$kind $name FAIL bad input script: $lint_msg" | tee -a "$SUMMARY"; return 0
  fi
  local remaining=$(( RUN_TIMEOUT_S - ($(date +%s) - RUN_START) ))
  if [ "$remaining" -lt 5 ]; then
    echo "$kind $name SKIPPED run timeout reached" | tee -a "$SUMMARY"; return 0
  fi
  local limit=$SCENARIO_TIMEOUT_S
  [ "$remaining" -lt "$limit" ] && limit=$remaining
  local sd="$WORK/$name"
  mkdir -p "$sd/books" "$sd/.crosspoint" || {
    echo "$kind $name FAIL setup: mkdir failed" | tee -a "$SUMMARY"
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
    return 0
  }
  # No EPUBs copied — empty SD card tests the no-books render path.
  if [ -n "$settings" ]; then
    printf '%s\n' "$settings" > "$sd/.crosspoint/settings.json" || {
      echo "$kind $name FAIL setup: write settings.json failed" | tee -a "$SUMMARY"
      [ "$kind" = required ] && required_failures=$((required_failures + 1))
      return 0
    }
  fi
  local log="$OUT/$name.log" start rc status="PASS" reason=""
  start=$(date +%s)
  ( cd "$sd" || exit 2
    export CROSSPOINT_SIM_SD="$sd" CROSSPOINT_SIM_INPUT_SCRIPT="$script"
    export CROSSPOINT_SIM_WAIT_TIMEOUT_MS=$(( (limit > 15 ? limit - 10 : 5) * 1000 ))
    run_with_timeout "$limit" "$log" "$PROGRAM" )
  rc=$?
  local secs=$(( $(date +%s) - start ))
  if [ $rc -eq 124 ]; then status=FAIL; reason="timeout ${limit}s"
  elif [ $rc -ne 0 ]; then status=FAIL; reason="exit $rc"
  elif ! grep -q "Entering activity: Home" "$log"; then status=FAIL; reason="Home activity not in log"
  fi
  for img in "$@"; do
    if ! grep -qF "[SIM] Saved screenshot: $OUT/$img" "$log"; then
      status=FAIL; reason="${reason:+$reason; }SHOT not executed for $img"; continue
    fi
    local size_msg
    size_msg=$(check_image "$OUT/$img"); case $? in
      0) ;;
      3) status=FAIL; reason="${reason:+$reason; }blank $img" ;;
      4) status=FAIL; reason="${reason:+$reason; }$img $size_msg (want 480x800)" ;;
      *) status=FAIL; reason="${reason:+$reason; }missing $img" ;;
    esac
  done
  echo "$kind $name $status ${secs}s ${reason}" | tee -a "$SUMMARY"
  [ "$status" = FAIL ] && tail -n 15 "$log" >&2
  return 0
}

# B: Balanced home with 4 recent books injected (long Cyrillic titles).
# Tests: hero cover display (D-029 300px thumb), Noto Sans Cyrillic wrapping (D-031),
# recent covers (192px thumbs), progress bar (0% because no progress recorded).
# Allow 15 s for cover generation (4 EPUBs × EPUB parse + BMP write on first render).
# EXPERIMENTAL until first successful CI run with cover+text verified by eye.
_EXTRA_SD_SETUP=inject_recent_books
run_scenario experimental home_balanced_reading '{"uiTheme":1,"homeLayout":1}' \
  "0:WAIT:Entering activity: Home;15000:SHOT:$OUT/home_balanced_reading.bmp;17000:QUIT" \
  home_balanced_reading.bmp
# R2: confirm RecentBooksStore loaded the injected history (LOG_LEVEL=2 → DBG visible).
if [ -f "$OUT/home_balanced_reading.log" ]; then
  if grep -q "RBS.*Recent books loaded from file" "$OUT/home_balanced_reading.log"; then
    echo "experimental home_balanced_reading_history PASS recent books loaded from file" | tee -a "$SUMMARY"
  else
    echo "experimental home_balanced_reading_history WARN recent books not in log (check LOG_LEVEL)" | tee -a "$SUMMARY"
  fi
fi

# C: Balanced home with empty SD card — tests empty-state render path.
# Expected: status bar + empty-state placeholder text + bottom panel; no crash.
run_empty_scenario experimental home_balanced_empty '{"uiTheme":1,"homeLayout":1}' \
  "0:WAIT:Entering activity: Home;4000:SHOT:$OUT/home_balanced_empty.bmp;5500:QUIT" \
  home_balanced_empty.bmp

# D: Balanced home + landscape reader orientation setting (D-036 / C-4 accepted, required).
# Verifies that SETTINGS.orientation (reader-only, SettingsList.cpp:116) does not suppress Balanced.
# Roundtrip Library → Reader → Home not tested here (A-08 scope).
run_scenario required home_balanced_reader_landscape_setting '{"uiTheme":1,"homeLayout":1,"orientation":1}' \
  "0:WAIT:Entering activity: Home;5000:SHOT:$OUT/home_balanced_reader_landscape_setting.bmp;6500:QUIT" \
  home_balanced_reader_landscape_setting.bmp
# C-4 log check: layout=balanced must appear; log absent/empty → not executed; marker absent → regression.
c4_check "$OUT/home_balanced_reader_landscape_setting.log"

if [ "$HAVE_PIL" = "1" ]; then
  python3 - "$OUT" <<'PY'
import sys, pathlib
from PIL import Image
for bmp in pathlib.Path(sys.argv[1]).glob("*.bmp"):
    Image.open(bmp).save(bmp.with_suffix(".png"))
PY
fi

echo "required failures: $required_failures" | tee -a "$SUMMARY"
exit "$required_failures"
