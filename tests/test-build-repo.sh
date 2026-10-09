#!/usr/bin/env bash
# Tests scripts/build-repo.sh with a throwaway key: a fully signed set is
# indexed and its metadata signed; one unsigned package, or an installer
# with no key fingerprint, stops the publish; the apt repository's
# InRelease and the pacman database are signed, and an Arch package without
# a valid signature stops it too. Needs rpm-build, rpm-sign, gnupg2,
# createrepo_c, dpkg-dev, pacman, bsdtar, zstd.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GNUPGHOME=$T/gnupg; mkdir -m 0700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase pw --quick-gen-key "test <t@example.invalid>" rsa2048 sign 1d 2>/dev/null
fpr=$(gpg --with-colons --list-secret-keys | awk -F: '$1=="fpr"{print $10; exit}')
gpg --armor --export "$fpr" > "$T/key.pub"
KEY=$(gpg --batch --pinentry-mode loopback --passphrase pw --armor --export-secret-keys "$fpr")
rm -rf "${GNUPGHOME:?}"/*
package() { # NAME DIR
    mkdir -p "$T/build/$1"
    printf 'Name: %s\nVersion: 1\nRelease: 1\nSummary: test\nLicense: MIT\nBuildArch: noarch\n%%description\ntest\n%%files\n' "$1" > "$T/build/$1/$1.spec"
    rpmbuild -bb --define "_topdir $T/build/$1" "$T/build/$1/$1.spec" >/dev/null 2>&1
    mkdir -p "$2"; cp "$T/build/$1"/RPMS/noarch/*.rpm "$2/"
}
deb() { # NAME DIR [unsigned]: a minimal .deb with a detached signature by the test key unless "unsigned"
    local p=$2/${1}_1_amd64.deb
    mkdir -p "$T/deb/$1/DEBIAN" "$2"
    printf 'Package: %s\nVersion: 1\nArchitecture: amd64\nMaintainer: t <t@example.invalid>\nDescription: test\n' "$1" > "$T/deb/$1/DEBIAN/control"
    dpkg-deb --build "$T/deb/$1" "$p" >/dev/null
    [[ ${3:-} == unsigned ]] || gpg --batch --pinentry-mode loopback --passphrase pw --detach-sign --output "$p.sig" "$p"
}
# refused NAME DESC: building site NAME fails because a package is not signed by the key.
refused() {
    local out
    if out=$(cd "$T/src$1" && bash "$ROOT/scripts/build-repo.sh" "$T/site$1" openvibes.gpg 2>&1); then
        echo "FAIL: $2 was published"; exit 1
    fi
    grep -q 'is not signed with the OpenVIBES key' <<<"$out" || { echo "FAIL: $2 refused for another reason: $out"; exit 1; }
}
arch() { # NAME DIR [unsigned [VERSION]]: a minimal Arch package (VERSION-1, default 1), signed with the test key unless "unsigned"
    local v=${4:-1}
    local w=$T/arch/$1-$v p=$2/$1-$v-1-x86_64.pkg.tar.zst
    mkdir -p "$w/usr/share/$1" "$2"
    printf 'pkgname = %s\npkgbase = %s\npkgver = %s-1\npkgdesc = test\narch = x86_64\nsize = 0\n' "$1" "$1" "$v" > "$w/.PKGINFO"
    : > "$w/usr/share/$1/f"
    (cd "$w" && bsdtar -cf - .PKGINFO usr | zstd -q -o "$p")
    [[ ${3:-} == unsigned ]] || gpg --batch --pinentry-mode loopback --passphrase pw --detach-sign --output "$p.sig" "$p"
}
site() { # DIR: a copy of this repository's site sources with the test key
    local dir=$1
    mkdir -p "$dir"
    cp "$ROOT/openvibes.repo" "$ROOT/index.html" "$ROOT/packages.html" "$ROOT/site.css" "$dir/"
    cp -r "$ROOT/assets" "$dir/"
    sed "s/^KEY_FINGERPRINT=.*/KEY_FINGERPRINT=$fpr/" "$ROOT/install.sh" > "$dir/install.sh"
    cp "$T/key.pub" "$dir/openvibes.gpg"
}
export RPM_SIGNING_KEY=$KEY RPM_SIGNING_PASSPHRASE=pw
repo=rpm/fedora/44/x86_64

# Signing test packages (Arch) needs the key in this shell's keyring.
printf '%s' "$KEY" | gpg --batch --quiet --pinentry-mode loopback --passphrase pw --import 2>/dev/null

# A signed set: indexed, metadata signed and verifiable.
site "$T/src1"; package one "$T/site1/$repo"; package two "$T/site1/$repo"
deb one "$T/site1/deb"; arch one "$T/site1/arch/x86_64"
arch multi "$T/site1/arch/x86_64" signed 9; arch multi "$T/site1/arch/x86_64" signed 10
bash "$ROOT/scripts/sign-rpms.sh" "$T/site1/$repo" "$T/key.pub"
(cd "$T/src1" && bash "$ROOT/scripts/build-repo.sh" "$T/site1" openvibes.gpg) || { echo "FAIL: a signed set was refused"; exit 1; }
test -s "$T/site1/$repo/repodata/repomd.xml.asc" || { echo "FAIL: no repomd.xml.asc"; exit 1; }
gpg --batch --import "$T/key.pub" 2>/dev/null
gpg --batch --verify "$T/site1/$repo/repodata/repomd.xml.asc" "$T/site1/$repo/repodata/repomd.xml" 2>/dev/null ||
    { echo "FAIL: repomd.xml signature does not verify"; exit 1; }
for f in install.sh openvibes.gpg openvibes.repo index.html packages.html site.css assets/wordmark-dark.svg; do [[ -s $T/site1/$f ]] || { echo "FAIL: $f missing"; exit 1; }; done
# apt: a flat repository whose Release hashes Packages and is clear-signed.
gpg --batch --verify "$T/site1/deb/InRelease" 2>/dev/null || { echo "FAIL: InRelease does not verify"; exit 1; }
grep -q '^Package: one$' "$T/site1/deb/Packages" || { echo "FAIL: the .deb is not indexed"; exit 1; }
sha=$(sha256sum "$T/site1/deb/Packages" | cut -d' ' -f1)
grep -qE "^ $sha [0-9]+ Packages\$" "$T/site1/deb/Release" || { echo "FAIL: Release does not hash Packages"; exit 1; }
# Valid-Until: a stale signed index can't be replayed for long (publish.yml
# rebuilds weekly, well inside it).
until=$(sed -n 's/^Valid-Until: //p' "$T/site1/deb/Release")
[[ -n $until ]] || { echo "FAIL: Release has no Valid-Until"; exit 1; }
left=$(( $(date -d "$until" +%s) - $(date +%s) ))
(( left > 20 * 86400 && left <= 31 * 86400 )) || { echo "FAIL: Valid-Until $until is not about 30 days ahead"; exit 1; }
# pacman: the database lists the package, is a plain file, and is signed.
gpg --batch --verify "$T/site1/arch/x86_64/openvibes.db.sig" "$T/site1/arch/x86_64/openvibes.db" 2>/dev/null ||
    { echo "FAIL: openvibes.db.sig does not verify"; exit 1; }
[[ -f $T/site1/arch/x86_64/openvibes.db && ! -L $T/site1/arch/x86_64/openvibes.db ]] || { echo "FAIL: openvibes.db is missing or a symlink"; exit 1; }
bsdtar -tf "$T/site1/arch/x86_64/openvibes.db" | grep -q '^one-1-1/' || { echo "FAIL: the Arch package is not in openvibes.db"; exit 1; }
# Two versions of one package: the database lists the newer one, though its
# file name sorts first as a string (0.2.10 before 0.2.9).
bsdtar -tf "$T/site1/arch/x86_64/openvibes.db" | grep -q '^multi-10-1/' ||
    { echo "FAIL: openvibes.db lists $(bsdtar -tf "$T/site1/arch/x86_64/openvibes.db" | grep -o '^multi-[^/]*' | sort -u), not multi-10-1"; exit 1; }

# An Arch package without a signature: refused.
site "$T/src4"; package six "$T/site4/$repo"
bash "$ROOT/scripts/sign-rpms.sh" "$T/site4/$repo" "$T/key.pub"
arch seven "$T/site4/arch/x86_64" unsigned
refused 4 "an unsigned Arch package"
# One signed by another key: refused.
site "$T/src5"; package eight "$T/site5/$repo"
bash "$ROOT/scripts/sign-rpms.sh" "$T/site5/$repo" "$T/key.pub"
gpg --batch --pinentry-mode loopback --passphrase pw --quick-gen-key "other <o@example.invalid>" rsa2048 sign 1d 2>/dev/null
arch nine "$T/site5/arch/x86_64" unsigned
gpg --batch --pinentry-mode loopback --passphrase pw --local-user "other <o@example.invalid>" --detach-sign \
    --output "$T/site5/arch/x86_64/nine-1-1-x86_64.pkg.tar.zst.sig" "$T/site5/arch/x86_64/nine-1-1-x86_64.pkg.tar.zst"
refused 5 "an Arch package signed by another key"
# A .deb without a signature: refused.
site "$T/src6"; package ten "$T/site6/$repo"
bash "$ROOT/scripts/sign-rpms.sh" "$T/site6/$repo" "$T/key.pub"
deb eleven "$T/site6/deb" unsigned
refused 6 "an unsigned .deb"
# A signed message by the right key in place of a detached signature (the
# site publishes one: InRelease): refused.
site "$T/src7"; package twelve "$T/site7/$repo"
bash "$ROOT/scripts/sign-rpms.sh" "$T/site7/$repo" "$T/key.pub"
arch thirteen "$T/site7/arch/x86_64" unsigned
cp "$T/site1/deb/InRelease" "$T/site7/arch/x86_64/thirteen-1-1-x86_64.pkg.tar.zst.sig"
refused 7 "an Arch package whose .sig is a signed message"
# A detached signature by the right key over other data: refused.
site "$T/src8"; package fourteen "$T/site8/$repo"
bash "$ROOT/scripts/sign-rpms.sh" "$T/site8/$repo" "$T/key.pub"
deb fifteen "$T/site8/deb" unsigned
cp "$T/site1/deb/one_1_amd64.deb.sig" "$T/site8/deb/fifteen_1_amd64.deb.sig"
refused 8 "a .deb with another package's signature"

# One unsigned package: refused.
site "$T/src2"; package three "$T/site2/$repo"
bash "$ROOT/scripts/sign-rpms.sh" "$T/site2/$repo" "$T/key.pub"
package four "$T/site2/$repo"
if (cd "$T/src2" && bash "$ROOT/scripts/build-repo.sh" "$T/site2" openvibes.gpg) 2>/dev/null; then
    echo "FAIL: an unsigned package was published"; exit 1
fi

# An installer without a key fingerprint: refused.
site "$T/src3"; package five "$T/site3/$repo"
bash "$ROOT/scripts/sign-rpms.sh" "$T/site3/$repo" "$T/key.pub"
sed -i "s/^KEY_FINGERPRINT=.*/KEY_FINGERPRINT=unset/" "$T/src3/install.sh"
if (cd "$T/src3" && bash "$ROOT/scripts/build-repo.sh" "$T/site3" openvibes.gpg) 2>/dev/null; then
    echo "FAIL: an installer without a key fingerprint was published"; exit 1
fi
echo "test-build-repo: all checks passed"
