#!/usr/bin/env bash
# test_validate_home.sh — unit tests for validate_home.py and lib_validate.sh (T1–T12).
# No simulator needed. Synthetic images are created by Pillow in a temp directory.
# Exit 0 if all tests pass, 1 if any fail.
set -uo pipefail

SIM_DIR="$(cd "$(dirname "$0")" && pwd)"

HAVE_PIL=0
python3 -c "import PIL" 2>/dev/null && HAVE_PIL=1
if [ "$HAVE_PIL" != "1" ]; then
  echo "FAIL validator_selftest: Pillow not installed (required for T1-T12)" >&2
  exit 1
fi

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/test_validate.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT

TESTS_PASS=0
TESTS_FAIL=0

pass() { TESTS_PASS=$((TESTS_PASS + 1)); echo "PASS $1"; }
fail() { TESTS_FAIL=$((TESTS_FAIL + 1)); echo "FAIL $1"; }

# Check exit code from previous command substitution.
# Usage: rc=$?; check_rc T1 0 $rc
check_rc() {
  local name=$1 expected=$2 actual=$3
  if [ "$actual" -eq "$expected" ]; then pass "$name rc=$actual"; else fail "$name rc=$actual (want $expected)"; fi
}

# Check that pattern appears in output.
check_line() {
  local name=$1 out=$2 pat=$3
  if echo "$out" | grep -qF "$pat"; then pass "$name contains '$pat'"; else fail "$name: missing '$pat'"; fi
}

# ── Create synthetic test artifacts ──────────────────────────────────────────
python3 - "$TMPD" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
d = Path(sys.argv[1])

def balanced(path):
    """480x800, black separator at y=711, white content at y=690."""
    img = Image.new("L", (480, 800), 255)
    ImageDraw.Draw(img).rectangle([0, 711, 479, 715], fill=0)
    img.save(path)

def standard(path):
    """480x800, no separator (grey)."""
    Image.new("L", (480, 800), 180).save(path)

balanced(d / "balanced.bmp")
standard(d / "standard.bmp")
Image.new("L", (800, 480), 128).save(d / "wrong_size.bmp")
(d / "corrupt.bmp").write_bytes(b"\x00\xff NOT A BMP")
(d / "balanced.log").write_text("[1500] [INF] [HOME] layout=balanced\n")
(d / "standard.log").write_text("[1500] [INF] [HOME] layout=standard\n")
(d / "empty.log").write_text("")
# fake_pil: PIL package that raises ImportError
(d / "fake_pil/PIL").mkdir(parents=True)
(d / "fake_pil/PIL/__init__.py").write_text("raise ImportError('faked Pillow')\n")
PY

T="$TMPD"
PY="python3 $SIM_DIR/validate_home.py"

echo "=== T1: balanced frame + balanced log + different ref ==="
out=$($PY --bmp "$T/balanced.bmp" --log "$T/balanced.log" --ref "$T/standard.bmp"); rc=$?
check_rc T1 0 $rc
check_line T1 "$out" "PASS log:"
check_line T1 "$out" "PASS pixel_sig:"
check_line T1 "$out" "PASS diff:"

echo "=== T2: frame without signature (grey y=711) ==="
out=$($PY --bmp "$T/standard.bmp" --log "$T/balanced.log" --ref "$T/balanced.bmp"); rc=$?
check_rc T2 0 $rc
check_line T2 "$out" "FAIL pixel_sig:"

echo "=== T3: frame identical to ref (diff=0%) ==="
cp "$T/standard.bmp" "$T/std_copy.bmp"
out=$($PY --bmp "$T/standard.bmp" --log "$T/balanced.log" --ref "$T/std_copy.bmp"); rc=$?
check_rc T3 0 $rc
check_line T3 "$out" "FAIL diff:"

echo "=== T4: log without balanced marker ==="
out=$($PY --bmp "$T/balanced.bmp" --log "$T/standard.log" --ref "$T/standard.bmp"); rc=$?
check_rc T4 0 $rc
check_line T4 "$out" "FAIL log:"

echo "=== T5: corrupt BMP ==="
out=$($PY --bmp "$T/corrupt.bmp" --log "$T/balanced.log" --ref "$T/standard.bmp") ; rc=$?
check_rc T5 2 $rc
check_line T5 "$out" "ERROR pixel_sig:"

echo "=== T6: missing log ==="
out=$($PY --bmp "$T/balanced.bmp" --log "$T/no_such.log" --ref "$T/standard.bmp") ; rc=$?
check_rc T6 2 $rc
check_line T6 "$out" "ERROR log:"

echo "=== T7: missing ref ==="
out=$($PY --bmp "$T/balanced.bmp" --log "$T/balanced.log" --ref "$T/no_such.bmp") ; rc=$?
check_rc T7 2 $rc
check_line T7 "$out" "ERROR diff:"

echo "=== T8: wrong-size frame (800x480) ==="
out=$($PY --bmp "$T/wrong_size.bmp" --log "$T/balanced.log" --ref "$T/standard.bmp"); rc=$?
check_rc T8 0 $rc
check_line T8 "$out" "FAIL pixel_sig:"
check_line T8 "$out" "FAIL diff:"

echo "=== T9: Pillow ImportError via fake PYTHONPATH ==="
out=$(PYTHONPATH="$T/fake_pil" $PY --bmp "$T/balanced.bmp" --log "$T/balanced.log" --ref "$T/standard.bmp") ; rc=$?
check_rc T9 2 $rc
check_line T9 "$out" "ERROR"

echo "=== T10: bash wrapper — required_failures on error conditions ==="
# Source lib for wrapper functions.
SUMMARY="$T/summary.txt"; : > "$SUMMARY"
required_failures=0
source "$SIM_DIR/lib_validate.sh"

# T10a: T5 (corrupt bmp) → FAIL, required_failures=1
required_failures=0; : > "$SUMMARY"
run_home_validation "$T/corrupt.bmp" "$T/balanced.log" "$T/standard.bmp" required home_balanced_validate
if [ "$required_failures" -eq 1 ]; then pass "T10a corrupt_bmp required_failures=1"; else fail "T10a required_failures=$required_failures (want 1)"; fi

# T10b: T6 (missing log) → FAIL, required_failures=1
required_failures=0; : > "$SUMMARY"
run_home_validation "$T/balanced.bmp" "$T/no_such.log" "$T/standard.bmp" required home_balanced_validate
if [ "$required_failures" -eq 1 ]; then pass "T10b missing_log required_failures=1"; else fail "T10b required_failures=$required_failures (want 1)"; fi

# T10c: T9 (fake Pillow) → FAIL, required_failures=1
required_failures=0; : > "$SUMMARY"
PYTHONPATH="$T/fake_pil" run_home_validation "$T/balanced.bmp" "$T/balanced.log" "$T/standard.bmp" required home_balanced_validate
if [ "$required_failures" -eq 1 ]; then pass "T10c fake_pillow required_failures=1"; else fail "T10c required_failures=$required_failures (want 1)"; fi

echo "=== T11: self-check ==="
# T11a: balanced frame used as 'standard' (pixel_sig=PASS) → selfcheck FAIL "accepts standard home".
# bmp=balanced.bmp (has sig), log=standard.log (no marker), ref=standard.bmp.
required_failures=0; : > "$SUMMARY"
run_home_selfcheck "$T/balanced.bmp" "$T/standard.log" "$T/standard.bmp" required home_balanced_selfcheck
if [ "$required_failures" -eq 1 ]; then pass "T11a accepts_standard_home FAIL"; else fail "T11a required_failures=$required_failures (want 1)"; fi
if grep -qF "accepts standard home" "$SUMMARY"; then pass "T11a reason includes 'accepts standard home'"; else fail "T11a reason missing"; fi

# T11b: corrupt bmp → selfcheck FAIL "validator error".
required_failures=0; : > "$SUMMARY"
run_home_selfcheck "$T/corrupt.bmp" "$T/balanced.log" "$T/standard.bmp" required home_balanced_selfcheck
if [ "$required_failures" -eq 1 ]; then pass "T11b validator_error FAIL"; else fail "T11b required_failures=$required_failures (want 1)"; fi
if grep -qF "validator error" "$SUMMARY"; then pass "T11b reason includes 'validator error'"; else fail "T11b reason missing"; fi

echo "=== T12: set -euo pipefail safety ==="
# Verify that rc=2 from Python does not trigger set -e in the calling script.
t12_out=$(
  set -euo pipefail
  required_failures=0
  SUMMARY="$T/summary_t12.txt"; : > "$SUMMARY"
  source "$SIM_DIR/lib_validate.sh"
  run_home_validation "$T/corrupt.bmp" "$T/balanced.log" "$T/standard.bmp" required home_balanced_validate
  printf 'T12_REACHED rf=%d\n' "$required_failures"
)
t12_rc=$?
if [ "$t12_rc" -ne 0 ]; then
  fail "T12 subshell exited $t12_rc (set -e triggered by rc=2)"
elif ! echo "$t12_out" | grep -q "T12_REACHED"; then
  fail "T12 never reached end of function"
elif ! echo "$t12_out" | grep -q "rf=1"; then
  fail "T12 required_failures not incremented (got: $t12_out)"
elif ! grep -q "rc=2" "$T/summary_t12.txt" 2>/dev/null; then
  fail "T12 rc=2 not in summary"
else
  pass "T12 set -euo pipefail safe, rc=2 captured"
fi

echo "=== T13: P3-1 diff threshold boundary (480x800=384000 px; changed*100>=total*5) ==="
# Create grey reference and N-pixel-different test images.
python3 - "$T" <<'PY'
import sys
from pathlib import Path
from PIL import Image
d = Path(sys.argv[1])
ref = Image.new("L", (480, 800), 128)
ref.save(d / "grey_ref.bmp")
for n in [19180, 19181, 19199, 19200]:
    img = Image.new("L", (480, 800), 128)
    pix = img.load()
    for i in range(n):
        pix[i % 480, i // 480] = 161  # delta=33 > threshold 32
    img.save(d / f"diff_{n}.bmp")
PY
for n in 19180 19181 19199 19200; do
  out=$($PY --bmp "$T/diff_${n}.bmp" --log "$T/balanced.log" --ref "$T/grey_ref.bmp"); rc=$?
  check_rc "T13a_${n}" 0 $rc
  if [ "$n" -lt 19200 ]; then
    check_line "T13a_${n}" "$out" "FAIL diff:"
  else
    check_line "T13a_${n}" "$out" "PASS diff:"
  fi
done

echo "=== T13b: P3-1 cover_grid_differs boundary (Python changed+total, bash arithmetic) ==="
for n in 19199 19200; do
  diff_out=$(python3 - "$T/diff_${n}.bmp" "$T/grey_ref.bmp" <<'PY'
import sys
from PIL import Image, ImageChops
a, b = (Image.open(p).convert("L") for p in sys.argv[1:3])
if a.size != b.size:
    print(-1)
else:
    d = ImageChops.difference(a, b).point(lambda v: 255 if v > 32 else 0)
    total = a.size[0] * a.size[1]
    changed = d.histogram()[255]
    print(changed, total)
PY
)
  diff_changed=$(echo "$diff_out" | awk '{print $1}')
  diff_total=$(echo "$diff_out" | awk '{print $2}')
  if [ "$((diff_changed * 100))" -ge "$((diff_total * 5))" ]; then result=PASS; else result=FAIL; fi
  if [ "$n" -lt 19200 ] && [ "$result" = "FAIL" ]; then
    pass "T13b cover_grid_differs ${n}px FAIL"
  elif [ "$n" -ge 19200 ] && [ "$result" = "PASS" ]; then
    pass "T13b cover_grid_differs ${n}px PASS"
  else
    fail "T13b cover_grid_differs ${n}px wrong result: $result"
  fi
done

echo "=== T14a: P3-2 layout=balanced marker (validate_home.py) ==="
# Real log format from Logging.cpp:47: "[%lu] [%s] [%s] " + message + "\n"
# So LOG_INF("HOME","layout=%s","balanced") -> "[1500] [INF] [HOME] layout=balanced\n"
python3 - "$T" <<'PY'
import sys
from pathlib import Path
d = Path(sys.argv[1])
(d / "ml_exact.log").write_text("[1500] [INF] [HOME] layout=balanced\n")
(d / "ml_crlf.log").write_text("[1500] [INF] [HOME] layout=balanced\r\n")
(d / "ml_disabled.log").write_text("[1500] [INF] [HOME] layout=balanced_DISABLED\n")
(d / "ml_balancedness.log").write_text("[1500] [INF] [HOME] layout=balancedness\n")
(d / "ml_standard.log").write_text("[1500] [INF] [HOME] layout=standard\n")
(d / "ml_homex.log").write_text("[1500] [INF] [HOMEX] layout=balanced\n")
(d / "ml_rbs.log").write_text("[1500] [INF] [RBS] layout=balanced\n")
(d / "ml_twolines.log").write_text("[1500] [INF] [HOME] other\n[1501] [INF] [RBS] layout=balanced\n")
(d / "ml_empty.log").write_text("")
PY
for case in exact crlf; do
  out=$($PY --bmp "$T/balanced.bmp" --log "$T/ml_${case}.log" --ref "$T/standard.bmp")
  check_line "T14a_${case}" "$out" "PASS log:"
done
for case in disabled balancedness standard homex rbs twolines empty; do
  out=$($PY --bmp "$T/balanced.bmp" --log "$T/ml_${case}.log" --ref "$T/standard.bmp")
  check_line "T14a_${case}" "$out" "FAIL log:"
done
# missing log → ERROR log + exit 2
out=$($PY --bmp "$T/balanced.bmp" --log "$T/no_such_ml.log" --ref "$T/standard.bmp"); rc=$?
check_rc "T14a_missing" 2 $rc
check_line "T14a_missing" "$out" "ERROR log:"

echo "=== T14b: P3-2 layout=balanced marker (check_balanced_marker) ==="
for case in exact crlf; do
  check_balanced_marker "$T/ml_${case}.log"; rc=$?
  [ "$rc" -eq 0 ] && pass "T14b ${case} rc=0" || fail "T14b ${case} rc=$rc (want 0)"
done
for case in disabled balancedness standard homex rbs twolines; do
  check_balanced_marker "$T/ml_${case}.log"; rc=$?
  [ "$rc" -eq 1 ] && pass "T14b ${case} rc=1 (marker absent)" || fail "T14b ${case} rc=$rc (want 1)"
done
check_balanced_marker "$T/ml_empty.log"; rc=$?
[ "$rc" -eq 2 ] && pass "T14b empty rc=2" || fail "T14b empty rc=$rc (want 2)"
check_balanced_marker "$T/no_such_ml.log"; rc=$?
[ "$rc" -eq 2 ] && pass "T14b missing rc=2" || fail "T14b missing rc=$rc (want 2)"

echo "=== T15a: P3-2 exact marker — validate_home.py (line-anchored regex) ==="
# Log format confirmed: Logging.cpp:47 "[%lu] [%s] [%s] " + message + "\n"
# Pattern: fullmatch per line after rstrip('\r') — no unanchored substring match.
python3 - "$T" <<'PY'
import sys
from pathlib import Path
d = Path(sys.argv[1])
(d / "t15_counterexample.log").write_text("[1500] [INF] [RBS] echoed [HOME] layout=balanced\n")
(d / "t15_exact.log").write_text("[1500] [INF] [HOME] layout=balanced\n")
(d / "t15_crlf.log").write_text("[1500] [INF] [HOME] layout=balanced\r\n")
(d / "t15_mixed.log").write_text(
    "[1499] [INF] [HOME] layout=standard\n"
    "[1500] [INF] [HOME] layout=balanced\n"
    "[1501] [INF] [SYS] boot ok\n"
)
(d / "t15_no_ts.log").write_text("[HOME] layout=balanced\n")
(d / "t15_err_level.log").write_text("[1500] [ERR] [HOME] layout=balanced\n")
(d / "t15_leading_space.log").write_text("  [1500] [INF] [HOME] layout=balanced\n")
(d / "t15_leading_x.log").write_text("x[1500] [INF] [HOME] layout=balanced\n")
(d / "t15_extra.log").write_text("[1500] [INF] [HOME] layout=balanced extra\n")
(d / "t15_note.log").write_text("[1500] [INF] [HOME] note layout=balanced\n")
(d / "t15_standard.log").write_text("[1500] [INF] [HOME] layout=standard\n")
# Binary content — control chars that splitlines() would split on but split("\n") won't.
(d / "t15_cr_between.log").write_bytes(
    b"[1500] [INF] [RBS] echoed\r[1500] [INF] [HOME] layout=balanced\n"
)
(d / "t15_double_cr.log").write_bytes(
    b"[1500] [INF] [HOME] layout=balanced\r\r\n"
)
(d / "t15_vt.log").write_bytes(
    b"[1500] [INF] [HOME] layout=balanced\x0b\n"
)
(d / "t15_nel.log").write_bytes(
    b"[1500] [INF] [HOME] layout=balanced\xc2\x85\n"
)
PY
for case in exact crlf mixed; do
  out=$($PY --bmp "$T/balanced.bmp" --log "$T/t15_${case}.log" --ref "$T/standard.bmp")
  check_line "T15a_${case}" "$out" "PASS log:"
done
for case in counterexample no_ts err_level leading_space leading_x extra note standard; do
  out=$($PY --bmp "$T/balanced.bmp" --log "$T/t15_${case}.log" --ref "$T/standard.bmp")
  check_line "T15a_${case}" "$out" "FAIL log:"
done
# priors from T14 (reuse existing files)
for case in disabled balancedness homex rbs twolines; do
  out=$($PY --bmp "$T/balanced.bmp" --log "$T/ml_${case}.log" --ref "$T/standard.bmp")
  check_line "T15a_prior_${case}" "$out" "FAIL log:"
done
# newline="" / split("\n") guards: \r between entries, double \r, VT, NEL
for case in cr_between double_cr vt nel; do
  out=$($PY --bmp "$T/balanced.bmp" --log "$T/t15_${case}.log" --ref "$T/standard.bmp")
  check_line "T15a_${case}" "$out" "FAIL log:"
done
# empty → FAIL (not ERROR — file is readable, just empty string)
out=$($PY --bmp "$T/balanced.bmp" --log "$T/ml_empty.log" --ref "$T/standard.bmp")
check_line "T15a_empty" "$out" "FAIL log:"
# missing → ERROR log + rc 2
out=$($PY --bmp "$T/balanced.bmp" --log "$T/no_such_ml.log" --ref "$T/standard.bmp"); rc=$?
check_rc "T15a_missing" 2 $rc
check_line "T15a_missing" "$out" "ERROR log:"

echo "=== T15b: P3-2 exact marker — check_balanced_marker (Python --marker-only) ==="
# Confirm: rc 1 (not 2 or 141) when marker absent, CRLF passes, counterexample fails.
for case in exact crlf mixed; do
  check_balanced_marker "$T/t15_${case}.log"; rc=$?
  [ "$rc" -eq 0 ] && pass "T15b ${case} rc=0" || fail "T15b ${case} rc=$rc (want 0)"
done
for case in counterexample no_ts err_level leading_space leading_x extra note standard; do
  check_balanced_marker "$T/t15_${case}.log"; rc=$?
  [ "$rc" -eq 1 ] && pass "T15b ${case} rc=1" || fail "T15b ${case} rc=$rc (want 1)"
done
# priors
for case in disabled balancedness homex rbs twolines; do
  check_balanced_marker "$T/ml_${case}.log"; rc=$?
  [ "$rc" -eq 1 ] && pass "T15b prior_${case} rc=1" || fail "T15b prior_${case} rc=$rc (want 1)"
done
check_balanced_marker "$T/ml_empty.log"; rc=$?
[ "$rc" -eq 2 ] && pass "T15b empty rc=2" || fail "T15b empty rc=$rc (want 2)"
check_balanced_marker "$T/no_such_ml.log"; rc=$?
[ "$rc" -eq 2 ] && pass "T15b missing rc=2" || fail "T15b missing rc=$rc (want 2)"
# newline guards (must give rc=1, not rc=0 or 141)
for case in cr_between double_cr vt nel; do
  check_balanced_marker "$T/t15_${case}.log"; rc=$?
  [ "$rc" -eq 1 ] && pass "T15b ${case} rc=1" || fail "T15b ${case} rc=$rc (want 1)"
done

echo "=== T15c: C-4 integration using production c4_check (5 cases) ==="
# NUL-suffix fixture for case 3.
python3 - "$T" <<'PY'
import sys
from pathlib import Path
Path(sys.argv[1]).joinpath("t15c_nul.log").write_bytes(
    b"[1500] [INF] [HOME] layout=balanced\x00\n"
)
PY
# Each sub-test: reset SUMMARY + required_failures, call c4_check, then verify
# check_balanced_marker rc, required_failures, and SUMMARY content independently.

# Case 1: echoed [HOME] (rc 1 → C-4 regression)
_t15c_sum="$T/t15c_1.txt"; : > "$_t15c_sum"; SUMMARY="$_t15c_sum"; required_failures=0
c4_check "$T/t15_counterexample.log"
_crc=0; check_balanced_marker "$T/t15_counterexample.log" || _crc=$?
[ "$_crc" -eq 1 ] && pass "T15c echoed crc=1" || fail "T15c echoed crc=$_crc (want 1)"
[ "$required_failures" -eq 1 ] && pass "T15c echoed rf=1" || fail "T15c echoed rf=$required_failures (want 1)"
grep -qxF "required home_balanced_c4 FAIL layout=balanced absent with orientation=1 (C-4 regression)" "$_t15c_sum" && pass "T15c echoed SUMMARY exact FAIL line" || fail "T15c echoed SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t15c_sum")" -eq 1 ] && pass "T15c echoed SUMMARY: 1 home_balanced_c4 line" || fail "T15c echoed SUMMARY: wrong count"

# Case 2: CR between entries (rc 1 → C-4 regression)
_t15c_sum="$T/t15c_2.txt"; : > "$_t15c_sum"; SUMMARY="$_t15c_sum"; required_failures=0
c4_check "$T/t15_cr_between.log"
_crc=0; check_balanced_marker "$T/t15_cr_between.log" || _crc=$?
[ "$_crc" -eq 1 ] && pass "T15c cr_between crc=1" || fail "T15c cr_between crc=$_crc (want 1)"
[ "$required_failures" -eq 1 ] && pass "T15c cr_between rf=1" || fail "T15c cr_between rf=$required_failures (want 1)"
grep -qxF "required home_balanced_c4 FAIL layout=balanced absent with orientation=1 (C-4 regression)" "$_t15c_sum" && pass "T15c cr_between SUMMARY exact FAIL line" || fail "T15c cr_between SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t15c_sum")" -eq 1 ] && pass "T15c cr_between SUMMARY: 1 home_balanced_c4 line" || fail "T15c cr_between SUMMARY: wrong count"

# Case 3: NUL after value (rc 1 → C-4 regression)
_t15c_sum="$T/t15c_3.txt"; : > "$_t15c_sum"; SUMMARY="$_t15c_sum"; required_failures=0
c4_check "$T/t15c_nul.log"
_crc=0; check_balanced_marker "$T/t15c_nul.log" || _crc=$?
[ "$_crc" -eq 1 ] && pass "T15c nul_suffix crc=1" || fail "T15c nul_suffix crc=$_crc (want 1)"
[ "$required_failures" -eq 1 ] && pass "T15c nul_suffix rf=1" || fail "T15c nul_suffix rf=$required_failures (want 1)"
grep -qxF "required home_balanced_c4 FAIL layout=balanced absent with orientation=1 (C-4 regression)" "$_t15c_sum" && pass "T15c nul_suffix SUMMARY exact FAIL line" || fail "T15c nul_suffix SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t15c_sum")" -eq 1 ] && pass "T15c nul_suffix SUMMARY: 1 home_balanced_c4 line" || fail "T15c nul_suffix SUMMARY: wrong count"

# Case 4: missing log (rc 2 → not executed)
_t15c_sum="$T/t15c_4.txt"; : > "$_t15c_sum"; SUMMARY="$_t15c_sum"; required_failures=0
c4_check "$T/no_such_t15c.log"
_crc=0; check_balanced_marker "$T/no_such_t15c.log" || _crc=$?
[ "$_crc" -eq 2 ] && pass "T15c missing crc=2" || fail "T15c missing crc=$_crc (want 2)"
[ "$required_failures" -eq 1 ] && pass "T15c missing rf=1" || fail "T15c missing rf=$required_failures (want 1)"
grep -qxF "required home_balanced_c4 FAIL C-4 not executed (log absent or empty)" "$_t15c_sum" && pass "T15c missing SUMMARY exact FAIL line" || fail "T15c missing SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t15c_sum")" -eq 1 ] && pass "T15c missing SUMMARY: 1 home_balanced_c4 line" || fail "T15c missing SUMMARY: wrong count"

# Case 5: correct log (rc 0 → PASS)
_t15c_sum="$T/t15c_5.txt"; : > "$_t15c_sum"; SUMMARY="$_t15c_sum"; required_failures=0
c4_check "$T/t15_exact.log"
_crc=0; check_balanced_marker "$T/t15_exact.log" || _crc=$?
[ "$_crc" -eq 0 ] && pass "T15c exact crc=0" || fail "T15c exact crc=$_crc (want 0)"
[ "$required_failures" -eq 0 ] && pass "T15c exact rf=0" || fail "T15c exact rf=$required_failures (want 0)"
grep -qxF "required home_balanced_c4 PASS layout=balanced confirmed with orientation=1" "$_t15c_sum" && pass "T15c exact SUMMARY exact PASS line" || fail "T15c exact SUMMARY wrong PASS line"
[ "$(grep -c "home_balanced_c4" "$_t15c_sum")" -eq 1 ] && pass "T15c exact SUMMARY: 1 home_balanced_c4 line" || fail "T15c exact SUMMARY: wrong count"

echo "=== T16: NUL and encoding — --marker-only, check_balanced_marker, full log check ==="
python3 - "$T" <<'PY'
import sys
from pathlib import Path
d = Path(sys.argv[1])
(d / "t16_nul_suffix.log").write_bytes(b"[1500] [INF] [HOME] layout=balanced\x00\n")
(d / "t16_nul_junk.log").write_bytes(b"[1500] [INF] [HOME] layout=balanced\x00junk\n")
(d / "t16_nul_prefix.log").write_bytes(b"\x00[1500] [INF] [HOME] layout=balanced\n")
(d / "t16_nul_then_good.log").write_bytes(
    b"[1500] [INF] [RBS] data\x00\n"
    b"[1500] [INF] [HOME] layout=balanced\n"
)
(d / "t16_good_bad_utf8.log").write_bytes(
    b"[1500] [INF] [HOME] layout=balanced\n"
    b"[1500] [INF] [SYS] \xff\xfe junk\n"
)
(d / "t16_bad_utf8_marker.log").write_bytes(b"[1500] [INF] [HOME] layout=bal\xffanced\n")
(d / "t16_utf8_nel.log").write_bytes(b"[1500] [INF] [HOME] layout=balanced\xc2\x85\n")
(d / "t16_nel_between.log").write_bytes(
    b"[1500] [INF] [RBS] text\xc2\x85[1500] [INF] [HOME] layout=balanced\n"
)
PY

echo "--- T16a: --marker-only ---"
for _case in nul_suffix nul_junk nul_prefix bad_utf8_marker utf8_nel nel_between; do
  _mo_rc=0; python3 "$SIM_DIR/validate_home.py" --marker-only --log "$T/t16_${_case}.log" > /dev/null || _mo_rc=$?
  [ "$_mo_rc" -eq 1 ] && pass "T16a ${_case} --marker-only rc=1" || fail "T16a ${_case} --marker-only rc=$_mo_rc (want 1)"
done
for _case in nul_then_good good_bad_utf8; do
  _mo_rc=0; python3 "$SIM_DIR/validate_home.py" --marker-only --log "$T/t16_${_case}.log" > /dev/null || _mo_rc=$?
  [ "$_mo_rc" -eq 0 ] && pass "T16a ${_case} --marker-only rc=0" || fail "T16a ${_case} --marker-only rc=$_mo_rc (want 0)"
done

echo "--- T16b: check_balanced_marker ---"
for _case in nul_suffix nul_junk nul_prefix bad_utf8_marker utf8_nel nel_between; do
  _crc=0; check_balanced_marker "$T/t16_${_case}.log" || _crc=$?
  [ "$_crc" -eq 1 ] && pass "T16b ${_case} check_balanced_marker rc=1" || fail "T16b ${_case} check_balanced_marker rc=$_crc (want 1)"
done
for _case in nul_then_good good_bad_utf8; do
  _crc=0; check_balanced_marker "$T/t16_${_case}.log" || _crc=$?
  [ "$_crc" -eq 0 ] && pass "T16b ${_case} check_balanced_marker rc=0" || fail "T16b ${_case} check_balanced_marker rc=$_crc (want 0)"
done

echo "--- T16c: full-mode log check ---"
for _case in nul_suffix nul_junk nul_prefix bad_utf8_marker utf8_nel nel_between; do
  out=$($PY --bmp "$T/balanced.bmp" --log "$T/t16_${_case}.log" --ref "$T/standard.bmp")
  check_line "T16c_${_case}" "$out" "FAIL log:"
done
for _case in nul_then_good good_bad_utf8; do
  out=$($PY --bmp "$T/balanced.bmp" --log "$T/t16_${_case}.log" --ref "$T/standard.bmp")
  check_line "T16c_${_case}" "$out" "PASS log:"
done

echo "--- T16d: python3 exit 127 (code-normalization: maps rc 127 to 2) ---"
_t16d_bin="$T/t16_no_py_bin"; mkdir -p "$_t16d_bin"
printf '#!/bin/sh\nexit 127\n' > "$_t16d_bin/python3"; chmod +x "$_t16d_bin/python3"
_saved_path="$PATH"; PATH="$_t16d_bin:$PATH"
_crc=0; check_balanced_marker "$T/t15_exact.log" || _crc=$?
PATH="$_saved_path"
[ "$_crc" -eq 2 ] && pass "T16d no_python check_balanced_marker rc=2" || fail "T16d no_python check_balanced_marker rc=$_crc (want 2)"

echo "--- T16d-real: PATH with real symlinks, no python3 ---"
_t16d_real_bin="$T/t16d_real_no_py"; mkdir -p "$_t16d_real_bin"
ln -sf "$(command -v tee)" "$_t16d_real_bin/tee"
_pychk=$(PATH="$_t16d_real_bin" command -v python3 2>/dev/null)
[ -z "$_pychk" ] && pass "T16d-real python3 not in restricted PATH" || fail "T16d-real python3 found: $_pychk"
_saved_path="$PATH"; PATH="$_t16d_real_bin"
_crc=0; check_balanced_marker "$T/t15_exact.log" || _crc=$?
PATH="$_saved_path"
[ "$_crc" -eq 2 ] && pass "T16d-real check_balanced_marker rc=2" || fail "T16d-real check_balanced_marker rc=$_crc (want 2)"

echo "=== T17: robustness under set -euo pipefail ==="
# Fake python3 for T17c (exits 127 = python not found).
_t17_no_py_dir="$T/t17_no_py_bin"; mkdir -p "$_t17_no_py_dir"
printf '#!/bin/sh\nexit 127\n' > "$_t17_no_py_dir/python3"; chmod +x "$_t17_no_py_dir/python3"
# Bad SIM_DIR (no validate_home.py) for T17e.
_t17_bad_sim="$T/t17_bad_sim"; mkdir -p "$_t17_bad_sim"

echo "--- T17a: marker absent (rc 1) ---"
_t17_sum="$T/t17a_sum.txt"; : > "$_t17_sum"
_t17_out=$(bash -c "
  set -euo pipefail
  SIM_DIR='${SIM_DIR}'
  source '${SIM_DIR}/lib_validate.sh'
  SUMMARY='${_t17_sum}'
  required_failures=0
  HAVE_PIL=1
  c4_check '${T}/ml_standard.log'
  printf 'REACHED_END rf=%d\n' \"\$required_failures\"
"); _t17_rc=$?
[ "$_t17_rc" -eq 0 ] && pass "T17a rc=0 (script continued)" || fail "T17a rc=$_t17_rc (want 0)"
echo "$_t17_out" | grep -q "REACHED_END" && pass "T17a REACHED_END" || fail "T17a missing REACHED_END (got: $_t17_out)"
echo "$_t17_out" | grep -q "rf=1" && pass "T17a required_failures=1" || fail "T17a rf mismatch (got: $_t17_out)"
grep -qxF "required home_balanced_c4 FAIL layout=balanced absent with orientation=1 (C-4 regression)" "$_t17_sum" && pass "T17a SUMMARY exact FAIL line" || fail "T17a SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t17_sum")" -eq 1 ] && pass "T17a SUMMARY: 1 home_balanced_c4 line" || fail "T17a SUMMARY: wrong count"

echo "--- T17b: missing log (rc 2) ---"
_t17_sum="$T/t17b_sum.txt"; : > "$_t17_sum"
_t17_out=$(bash -c "
  set -euo pipefail
  SIM_DIR='${SIM_DIR}'
  source '${SIM_DIR}/lib_validate.sh'
  SUMMARY='${_t17_sum}'
  required_failures=0
  HAVE_PIL=1
  c4_check '${T}/no_such_t17b.log'
  printf 'REACHED_END rf=%d\n' \"\$required_failures\"
"); _t17_rc=$?
[ "$_t17_rc" -eq 0 ] && pass "T17b rc=0 (script continued)" || fail "T17b rc=$_t17_rc (want 0)"
echo "$_t17_out" | grep -q "REACHED_END" && pass "T17b REACHED_END" || fail "T17b missing REACHED_END (got: $_t17_out)"
echo "$_t17_out" | grep -q "rf=1" && pass "T17b required_failures=1" || fail "T17b rf mismatch"
grep -qxF "required home_balanced_c4 FAIL C-4 not executed (log absent or empty)" "$_t17_sum" && pass "T17b SUMMARY exact FAIL line" || fail "T17b SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t17_sum")" -eq 1 ] && pass "T17b SUMMARY: 1 home_balanced_c4 line" || fail "T17b SUMMARY: wrong count"

echo "--- T17c: PATH without python3 - exit 127 (code-normalization) ---"
_t17_sum="$T/t17c_sum.txt"; : > "$_t17_sum"
_t17_out=$(bash -c "
  set -euo pipefail
  export PATH='${_t17_no_py_dir}:${PATH}'
  SIM_DIR='${SIM_DIR}'
  source '${SIM_DIR}/lib_validate.sh'
  SUMMARY='${_t17_sum}'
  required_failures=0
  HAVE_PIL=1
  c4_check '${T}/t15_exact.log'
  printf 'REACHED_END rf=%d\n' \"\$required_failures\"
"); _t17_rc=$?
[ "$_t17_rc" -eq 0 ] && pass "T17c rc=0 (script continued)" || fail "T17c rc=$_t17_rc (want 0)"
echo "$_t17_out" | grep -q "REACHED_END" && pass "T17c REACHED_END" || fail "T17c missing REACHED_END (got: $_t17_out)"
echo "$_t17_out" | grep -q "rf=1" && pass "T17c required_failures=1" || fail "T17c rf mismatch"
grep -qxF "required home_balanced_c4 FAIL C-4 not executed (log absent or empty)" "$_t17_sum" && pass "T17c SUMMARY exact FAIL line" || fail "T17c SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t17_sum")" -eq 1 ] && pass "T17c SUMMARY: 1 home_balanced_c4 line" || fail "T17c SUMMARY: wrong count"

echo "--- T17c-real: real PATH without python3 ---"
_t17c_real_bin="$T/t17c_real_no_py"; mkdir -p "$_t17c_real_bin"
ln -sf "$(command -v tee)" "$_t17c_real_bin/tee"
_pychk=$(PATH="$_t17c_real_bin" command -v python3 2>/dev/null)
[ -z "$_pychk" ] && pass "T17c-real python3 not in restricted PATH" || fail "T17c-real python3 found: $_pychk"
_t17_sum="$T/t17c_real_sum.txt"; : > "$_t17_sum"
_t17_out=$(bash -c "
  set -euo pipefail
  export PATH='${_t17c_real_bin}'
  SIM_DIR='${SIM_DIR}'
  source '${SIM_DIR}/lib_validate.sh'
  SUMMARY='${_t17_sum}'
  required_failures=0
  HAVE_PIL=1
  c4_check '${T}/t15_exact.log'
  printf 'REACHED_END rf=%d\n' \"\$required_failures\"
"); _t17_rc=$?
[ "$_t17_rc" -eq 0 ] && pass "T17c-real rc=0 (script continued)" || fail "T17c-real rc=$_t17_rc (want 0)"
echo "$_t17_out" | grep -q "REACHED_END" && pass "T17c-real REACHED_END" || fail "T17c-real missing REACHED_END (got: $_t17_out)"
echo "$_t17_out" | grep -q "rf=1" && pass "T17c-real required_failures=1" || fail "T17c-real rf mismatch"
grep -qxF "required home_balanced_c4 FAIL C-4 not executed (log absent or empty)" "$_t17_sum" && pass "T17c-real SUMMARY exact FAIL line" || fail "T17c-real SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t17_sum")" -eq 1 ] && pass "T17c-real SUMMARY: 1 home_balanced_c4 line" || fail "T17c-real SUMMARY: wrong count"

echo "--- T17d: SIM_DIR not set, cd / → SIM_DIR self-computed from BASH_SOURCE ---"
_t17_sum="$T/t17d_sum.txt"; : > "$_t17_sum"
_t17_out=$(bash -c "
  set -euo pipefail
  cd /
  unset SIM_DIR 2>/dev/null || true
  source '${SIM_DIR}/lib_validate.sh'
  SUMMARY='${_t17_sum}'
  required_failures=0
  HAVE_PIL=1
  c4_check '${T}/t15_exact.log'
  printf 'REACHED_END rf=%d\n' \"\$required_failures\"
"); _t17_rc=$?
[ "$_t17_rc" -eq 0 ] && pass "T17d rc=0 (SIM_DIR self-computed)" || fail "T17d rc=$_t17_rc (want 0)"
echo "$_t17_out" | grep -q "REACHED_END" && pass "T17d REACHED_END" || fail "T17d missing REACHED_END (got: $_t17_out)"
echo "$_t17_out" | grep -q "rf=0" && pass "T17d required_failures=0" || fail "T17d rf mismatch (got: $_t17_out)"
grep -qxF "required home_balanced_c4 PASS layout=balanced confirmed with orientation=1" "$_t17_sum" && pass "T17d SUMMARY exact PASS line" || fail "T17d SUMMARY wrong PASS line"
[ "$(grep -c "home_balanced_c4" "$_t17_sum")" -eq 1 ] && pass "T17d SUMMARY: 1 home_balanced_c4 line" || fail "T17d SUMMARY: wrong count"

echo "--- T17e: SIM_DIR points to dir without validate_home.py (rc 2) ---"
_t17_sum="$T/t17e_sum.txt"; : > "$_t17_sum"
_t17_out=$(bash -c "
  set -euo pipefail
  SIM_DIR='${_t17_bad_sim}'
  source '${SIM_DIR}/lib_validate.sh'
  SUMMARY='${_t17_sum}'
  required_failures=0
  HAVE_PIL=1
  c4_check '${T}/t15_exact.log'
  printf 'REACHED_END rf=%d\n' \"\$required_failures\"
"); _t17_rc=$?
[ "$_t17_rc" -eq 0 ] && pass "T17e rc=0 (script continued)" || fail "T17e rc=$_t17_rc (want 0)"
echo "$_t17_out" | grep -q "REACHED_END" && pass "T17e REACHED_END" || fail "T17e missing REACHED_END (got: $_t17_out)"
echo "$_t17_out" | grep -q "rf=1" && pass "T17e required_failures=1" || fail "T17e rf mismatch"
grep -qxF "required home_balanced_c4 FAIL C-4 not executed (log absent or empty)" "$_t17_sum" && pass "T17e SUMMARY exact FAIL line" || fail "T17e SUMMARY wrong FAIL line"
[ "$(grep -c "home_balanced_c4" "$_t17_sum")" -eq 1 ] && pass "T17e SUMMARY: 1 home_balanced_c4 line" || fail "T17e SUMMARY: wrong count"

echo ""
echo "Results: $TESTS_PASS passed, $TESTS_FAIL failed"
[ "$TESTS_FAIL" -eq 0 ]
