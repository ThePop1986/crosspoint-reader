#!/usr/bin/env bash
# lib_validate.sh — sourced by capture_screens.sh and test_validate_home.sh.
# Provides check_balanced_marker, c4_check, run_home_validation, run_home_selfcheck.
#
# Callers must define before sourcing:
#   HAVE_PIL   — "1" if Pillow is available, else "0"
#   SUMMARY    — path to summary.txt (appended by tee)
#   required_failures — integer counter (modified in place)
#
# safe under set -euo pipefail: Python exit code captured via
#   if out=$(python3 ...); then rc=0; else rc=$?; fi
# so a non-zero Python exit never triggers set -e in the calling script.

# SIM_DIR: set from own location so it is correct regardless of caller's CWD.
# Callers that already set SIM_DIR (e.g. capture_screens.sh) keep their value.
SIM_DIR=${SIM_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# check_balanced_marker <log_path>
# Delegates to validate_home.py --marker-only (single Python implementation).
# Returns: 0=found, 1=log readable but marker absent, 2=log missing/empty/error.
# Any exit code other than 0 or 1 from Python (incl. 127=python3 not found) → 2.
check_balanced_marker() {
  local log_path="$1" out rc
  if out=$(python3 "$SIM_DIR/validate_home.py" --marker-only --log "$log_path" 2>/dev/null); then
    rc=0
  else
    rc=$?
    [ "$rc" -ne 1 ] && rc=2
  fi
  return "$rc"
}

# c4_check <log_path>
# Writes required home_balanced_c4 PASS|FAIL to $SUMMARY.
# Increments required_failures when marker absent (rc 1) or not executed (rc 2).
c4_check() {
  local log_path="$1" rc
  rc=0; check_balanced_marker "$log_path" || rc=$?
  case "$rc" in
    0) echo "required home_balanced_c4 PASS layout=balanced confirmed with orientation=1" | tee -a "$SUMMARY" ;;
    1) echo "required home_balanced_c4 FAIL layout=balanced absent with orientation=1 (C-4 regression)" | tee -a "$SUMMARY"
       required_failures=$((required_failures + 1)) ;;
    2) echo "required home_balanced_c4 FAIL C-4 not executed (log absent or empty)" | tee -a "$SUMMARY"
       required_failures=$((required_failures + 1)) ;;
  esac
}

# _parse_validate_out <out>
# Sets _vld_n_checks (bitmask: 1=log 2=pixel_sig 4=diff),
#      _vld_has_fail, _vld_has_error, _vld_log_result, _vld_sig_result, _vld_fail_reason.
_parse_validate_out() {
  local out="$1"
  _vld_n_checks=0 _vld_has_fail=0 _vld_has_error=0
  _vld_log_result="" _vld_sig_result="" _vld_fail_reason=""
  while IFS= read -r line; do
    case "$line" in
      PASS\ log:*)       _vld_n_checks=$((_vld_n_checks | 1)); _vld_log_result=PASS ;;
      FAIL\ log:*)       _vld_n_checks=$((_vld_n_checks | 1)); _vld_log_result=FAIL; _vld_has_fail=1
                         _vld_fail_reason="${_vld_fail_reason:+$_vld_fail_reason; }$line" ;;
      PASS\ pixel_sig:*) _vld_n_checks=$((_vld_n_checks | 2)); _vld_sig_result=PASS ;;
      FAIL\ pixel_sig:*) _vld_n_checks=$((_vld_n_checks | 2)); _vld_sig_result=FAIL; _vld_has_fail=1
                         _vld_fail_reason="${_vld_fail_reason:+$_vld_fail_reason; }$line" ;;
      PASS\ diff:*)      _vld_n_checks=$((_vld_n_checks | 4)) ;;
      FAIL\ diff:*)      _vld_n_checks=$((_vld_n_checks | 4)); _vld_has_fail=1
                         _vld_fail_reason="${_vld_fail_reason:+$_vld_fail_reason; }$line" ;;
      ERROR\ *)          _vld_has_error=1
                         _vld_fail_reason="${_vld_fail_reason:+$_vld_fail_reason; }$line" ;;
    esac
  done <<< "$out"
}

# run_home_validation <bmp> <log> <ref> <kind> <name>
# PASS — rc=0, all 3 checks present, no ERROR, all 3 PASS.
# FAIL — anything else; increments required_failures when kind=required.
run_home_validation() {
  local bmp="$1" log="$2" ref="$3" kind="$4" name="$5"
  if [ "$HAVE_PIL" != "1" ]; then
    echo "$kind $name FAIL Pillow not available" | tee -a "$SUMMARY"
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
    return 0
  fi
  local out rc
  if out=$(python3 "$SIM_DIR/validate_home.py" --bmp "$bmp" --log "$log" --ref "$ref"); then rc=0; else rc=$?; fi
  _parse_validate_out "$out"
  local status reason
  if [ "$rc" -ne 0 ]; then
    status=FAIL; reason="rc=$rc ${_vld_fail_reason}"
  elif [ "$_vld_has_error" -eq 1 ]; then
    status=FAIL; reason="$_vld_fail_reason"
  elif [ "$_vld_n_checks" -ne 7 ]; then
    status=FAIL; reason="missing check(s) n_checks=$_vld_n_checks"
  elif [ "$_vld_has_fail" -eq 1 ]; then
    status=FAIL; reason="$_vld_fail_reason"
  else
    status=PASS; reason="$out"
  fi
  echo "$kind $name $status $reason" | tee -a "$SUMMARY"
  if [ "$status" = FAIL ] && [ "$kind" = required ]; then
    required_failures=$((required_failures + 1))
  fi
}

# run_home_selfcheck <bmp> <log> <ref> <kind> <name>
# Runs validator with bmp=standard_home, log=standard_log, ref=balanced_home.
# PASS — rc=0, all 3 present, no ERROR, log=FAIL, pixel_sig=FAIL.
# FAIL — validator error, or validator accepts standard home; increments required_failures.
run_home_selfcheck() {
  local bmp="$1" log="$2" ref="$3" kind="$4" name="$5"
  if ! [ -s "$bmp" ] || ! [ -s "$ref" ]; then
    echo "$kind $name FAIL selfcheck artifacts missing" | tee -a "$SUMMARY"
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
    return 0
  fi
  if [ "$HAVE_PIL" != "1" ]; then
    echo "$kind $name FAIL Pillow not available" | tee -a "$SUMMARY"
    [ "$kind" = required ] && required_failures=$((required_failures + 1))
    return 0
  fi
  local out rc
  if out=$(python3 "$SIM_DIR/validate_home.py" --bmp "$bmp" --log "$log" --ref "$ref"); then rc=0; else rc=$?; fi
  _parse_validate_out "$out"
  local status reason
  if [ "$rc" -ne 0 ] || [ "$_vld_has_error" -eq 1 ]; then
    status=FAIL; reason="validator error, rejection not proven (rc=$rc ${_vld_fail_reason})"
  elif [ "$_vld_n_checks" -ne 7 ]; then
    status=FAIL; reason="validator error, rejection not proven (missing checks n_checks=$_vld_n_checks)"
  elif [ "$_vld_log_result" = PASS ] || [ "$_vld_sig_result" = PASS ]; then
    status=FAIL; reason="validator accepts standard home (log=$_vld_log_result sig=$_vld_sig_result)"
  else
    status=PASS; reason="validator correctly rejects standard home (log=$_vld_log_result sig=$_vld_sig_result)"
  fi
  echo "$kind $name $status $reason" | tee -a "$SUMMARY"
  if [ "$status" = FAIL ] && [ "$kind" = required ]; then
    required_failures=$((required_failures + 1))
  fi
}
