#!/usr/bin/env bash
# Tests tests/check-site.sh: the good fixture passes, and each kind of
# problem fails on its own with its own message (a site with several
# problems at once would hide a broken check).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=$ROOT/tests/check-site.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
# site NAME HTML: a site with one page, index.html.
site() { mkdir -p "$T/$1"; printf '%s\n' "$2" > "$T/$1/index.html"; }
# expect NAME MESSAGE: the check fails on that site and says MESSAGE.
expect() {
    local out
    if out=$(bash "$CHECK" "$T/$1"); then fail "$1: passed"; fi
    grep -qF -- "$2" <<<"$out" || fail "$1: no '$2' in: $out"
    echo "ok $1"
}

bash "$CHECK" "$ROOT/tests/fixtures/site-ok" >/dev/null || fail "the good fixture failed"
echo "ok good fixture"

site missing '<link rel="stylesheet" href="missing.css">'
expect missing "index.html: missing.css does not exist"

site anchor '<a href="#nowhere">x</a><p data-id="nowhere"></p>'
expect anchor "index.html: no id for #nowhere"

# A link to another page's anchor: the target page must have the id.
site cross '<p id="here"></p>'
printf '%s\n' '<a href="./#gone">x</a><a href="index.html#here">y</a>' > "$T/cross/other.html"
expect cross "other.html: no id for ./#gone"

site big '<p></p>'
mkdir -p "$T/big/assets"; truncate -s 1100K "$T/big/assets/huge.webp"
expect big "over 1 MB"

# Files the publish step writes are not looked for.
site generated '<a href="releases.txt">r</a><a href="rpm/fedora/44/x86_64/">p</a>'
bash "$CHECK" "$T/generated" >/dev/null || fail "generated files were looked for"
echo "ok generated"
echo "test-check-site: all checks passed"
