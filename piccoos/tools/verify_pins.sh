#!/usr/bin/env bash
# Independently verify every pinned revision used by PiccoOS (see piccoos/PINS.md).
#
#   piccoos/tools/verify_pins.sh [workflow-file]
#
# Checks (network: GitHub only, read-only):
#   1. each `uses: owner/repo@<40-hex> # vX.Y.Z` resolves: the exact release tag
#      points to the pinned SHA (moving major tags are reported as INFO only);
#   2. the upstream CrossPoint, FreeInk SDK and simulator commits exist in their
#      public repositories (shallow fetch of that exact SHA).
# Exit status = number of failed checks.
set -uo pipefail

WF=${1:-.github/workflows/piccoos-ci.yml}
UPSTREAM_SHA=3a5bfac375c293cb38f7e6e28f7736e7d451ef57
SDK_SHA=6a208c0c46cce99bafa334bc4f171f5e558c5195
SIM_SHA=84c3421da6f707d6ebe919b3fafca7387ff06464
fail=0
ok()  { printf 'OK    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }

[ -f "$WF" ] || { echo "workflow not found: $WF" >&2; exit 2; }

# 1. GitHub Actions pinned by SHA. The comment must name an EXACT release tag
#    (e.g. `# v6.1.0`); that tag must resolve to the pinned SHA (FAIL otherwise).
#    The moving major tag (`v6`) is reported for information only: it is expected
#    to move with new releases and does not change the pinned code.
peeled_tag() { # <repo> <tag> -> commit SHA or empty
  local out
  out=$(git ls-remote "https://github.com/$1.git" "refs/tags/$2^{}" | cut -f1)
  [ -n "$out" ] || out=$(git ls-remote "https://github.com/$1.git" "refs/tags/$2" | cut -f1)
  printf '%s' "$out"
}
info() { printf 'INFO  %s\n' "$*"; }
while read -r repo sha tag; do
  [ -n "$repo" ] || continue
  if ! [[ $tag =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    bad "$repo: comment '$tag' is not an exact release tag (want vX.Y or vX.Y.Z)"; continue
  fi
  exact=$(peeled_tag "$repo" "$tag")
  if [ "$exact" = "$sha" ]; then ok "$repo@$tag = $sha"
  else bad "$repo@$tag: workflow $sha, tag ${exact:-<missing>}"; fi
  major=${tag%%.*}
  moving=$(peeled_tag "$repo" "$major")
  [ "$moving" = "$sha" ] || info "$repo: moving tag $major now at ${moving:-<missing>} (pinned code unchanged)"
done < <(grep -oE 'uses: *[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40} *# *v[0-9.]+' "$WF" \
          | sed -E 's/uses: *([^@]+)@([0-9a-f]{40}) *# *(v[0-9.]+)/\1 \2 \3/' | sort -u)

# 2. Source revisions exist upstream.
check_commit() { # <repo-url> <sha> <label>
  local tmp; tmp=$(mktemp -d)
  if git -C "$tmp" init -q && git -C "$tmp" fetch -q --depth=1 "$1" "$2" 2>/dev/null \
     && [ "$(git -C "$tmp" rev-parse FETCH_HEAD)" = "$2" ]; then ok "$3 $2 exists in $1"
  else bad "$3 $2 not fetchable from $1"; fi
  rm -rf "$tmp"
}
check_commit https://github.com/crosspoint-reader/crosspoint-reader.git "$UPSTREAM_SHA" "upstream"
check_commit https://github.com/Free-Ink/freeink-sdk.git "$SDK_SHA" "freeink-sdk"
check_commit https://github.com/crosspoint-reader/crosspoint-simulator.git "$SIM_SHA" "simulator"

# 3. Local checkout agrees with the pins (when run inside the fork).
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git merge-base --is-ancestor "$UPSTREAM_SHA" HEAD 2>/dev/null; then ok "HEAD descends from $UPSTREAM_SHA"
  else bad "HEAD does not descend from $UPSTREAM_SHA (or history is shallow)"; fi
  if [ -d freeink-sdk ]; then
    actual=$(git -C freeink-sdk rev-parse HEAD 2>/dev/null)
    [ "$actual" = "$SDK_SHA" ] && ok "freeink-sdk checkout = $SDK_SHA" || bad "freeink-sdk checkout = ${actual:-?}"
  fi
  for ini in piccoos/sim/platformio.sim.*.ini; do
    [ -f "$ini" ] || continue
    grep -q "crosspoint-simulator.git#$SIM_SHA" "$ini" && ok "$ini pins simulator" || bad "$ini simulator pin"
  done
fi

echo "failed checks: $fail"
exit "$fail"
