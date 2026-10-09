#!/usr/bin/env bash
# install.sh trusts the package key file only if it holds exactly one key,
# the pinned one: rpm --import and apt's signed-by trust every key in the
# file, so a second key next to the real one would be trusted too.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
export GNUPGHOME=$d/g; mkdir -m 0700 "$GNUPGHOME"
fail() { echo "FAIL: $*"; exit 1; }
for k in real evil; do
    gpg --batch --passphrase '' --quick-gen-key "$k <$k@example.invalid>" ed25519 sign 1d 2>/dev/null
done
fpr() { gpg --with-colons --list-keys "$1@example.invalid" | awk -F: '$1 == "fpr" { print $10; exit }'; }
gpg --armor --export "$(fpr real)" > "$d/real.gpg"
gpg --armor --export "$(fpr real)" "$(fpr evil)" > "$d/both.gpg"
gpg --armor --export "$(fpr evil)" > "$d/evil.gpg"
sed "s/^KEY_FINGERPRINT=.*/KEY_FINGERPRINT=$(fpr real)/" "$ROOT/install.sh" > "$d/install.sh"
check() { GNUPGHOME=$d/empty sh "$d/install.sh" --check-key "$1"; }
mkdir -m 0700 "$d/empty"
check "$d/real.gpg" >/dev/null || fail "the pinned key refused"
echo "ok the pinned key alone accepted"
if out=$(check "$d/both.gpg" 2>&1); then fail "a second key next to the pinned one accepted"; fi
grep -q "holds 2 keys" <<<"$out" || fail "two keys refused for another reason: $out"
echo "ok a second key refused"
if out=$(check "$d/evil.gpg" 2>&1); then fail "another key accepted"; fi
grep -q "the package key's fingerprint is" <<<"$out" || fail "another key refused for another reason: $out"
echo "ok another key refused"
echo "test-install-key: all checks passed"
