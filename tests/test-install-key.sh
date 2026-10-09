#!/usr/bin/env bash
# install.sh trusts the package key file only if it holds exactly one key,
# the pinned one, and hands rpm, apt, pacman and dnf gpg's own export of
# that key, never the downloaded file: they parse key files themselves and
# trust every key they find.
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
check() { GNUPGHOME=$d/empty sh "$d/install.sh" --pinned-key "$1" "$d/out.asc"; }
mkdir -m 0700 "$d/empty"
check "$d/real.gpg" >/dev/null || fail "the pinned key refused"
[[ $(gpg --batch --show-keys --with-colons "$d/out.asc" 2>/dev/null | awk -F: '$1 == "pub" { n++ } $1 == "fpr" && !f { f = $10 } END { print n, f }') == "1 $(fpr real)" ]] ||
    fail "the export is not exactly the pinned key"
echo "ok the pinned key alone accepted, exported alone"
# Text around the armour (a comment, a second armour block of the same key)
# never reaches the output: it is gpg's export, not the input.
{ echo "junk before"; cat "$d/real.gpg"; echo "junk after"; } > "$d/noisy.gpg"
check "$d/noisy.gpg" >/dev/null || fail "the pinned key with text around it refused"
! grep -q junk "$d/out.asc" || fail "text from the input reached the export"
echo "ok only gpg's export is written"
if out=$(check "$d/both.gpg" 2>&1); then fail "a second key next to the pinned one accepted"; fi
grep -q "holds 2 keys" <<<"$out" || fail "two keys refused for another reason: $out"
echo "ok a second key refused"
if out=$(check "$d/evil.gpg" 2>&1); then fail "another key accepted"; fi
grep -q "the package key's fingerprint is" <<<"$out" || fail "another key refused for another reason: $out"
echo "ok another key refused"
echo "test-install-key: all checks passed"
