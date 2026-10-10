#!/usr/bin/env bash
# install.sh's [openvibes] section in pacman.conf: added when absent; an
# existing one must be exactly the installer's (its Server and SigLevel),
# so a section that turns signature checks off is refused, not trusted.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
site=https://openvibes-project.github.io
conf() { printf '[options]\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n%s' "$1" > "$d/pacman.conf"; }
run() { sh "$ROOT/install.sh" --pacman-section "$d/pacman.conf"; }

conf ''
run >/dev/null || fail "no section: refused"
[[ $(grep -c '^\[openvibes\]' "$d/pacman.conf") == 1 ]] || fail "no section: not added once"
grep -qx 'SigLevel = Required DatabaseRequired' "$d/pacman.conf" || fail "no section: no SigLevel"
run >/dev/null || fail "the installer's own section refused on a second run"
[[ $(grep -c '^\[openvibes\]' "$d/pacman.conf") == 1 ]] || fail "second run added another section"
echo "ok section added once, accepted on a second run"

conf $'\n[openvibes]\nSigLevel = Never\nServer = '"$site"$'/arch/$arch\n'
if out=$(run 2>&1); then fail "a section with SigLevel = Never accepted"; fi
grep -q "differs from this installer's" <<<"$out" || fail "SigLevel = Never refused for another reason: $out"
echo "ok a section without signature checks refused"

conf $'\n[openvibes]\nSigLevel = Required DatabaseRequired\nServer = https://elsewhere.example/arch/$arch\n[extra]\nServer = '"$site"$'/arch/$arch\n'
if out=$(run 2>&1); then fail "a section with another server accepted (our Server line in another section)"; fi
echo "ok our Server line in another section does not count"
echo "test-install-pacman: all checks passed"
