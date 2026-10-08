#!/usr/bin/env bash
# Tests scripts/build-repo.sh with a throwaway key: a fully signed set is
# indexed and its metadata signed; one unsigned package, or an installer
# with no key fingerprint, stops the publish. Needs rpm-build, rpm-sign,
# gnupg2, createrepo_c.
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

# A signed set: indexed, metadata signed and verifiable.
site "$T/src1"; package one "$T/site1/$repo"; package two "$T/site1/$repo"
bash "$ROOT/scripts/sign-rpms.sh" "$T/site1/$repo" "$T/key.pub"
(cd "$T/src1" && bash "$ROOT/scripts/build-repo.sh" "$T/site1" openvibes.gpg) || { echo "FAIL: a signed set was refused"; exit 1; }
test -s "$T/site1/$repo/repodata/repomd.xml.asc" || { echo "FAIL: no repomd.xml.asc"; exit 1; }
gpg --batch --import "$T/key.pub" 2>/dev/null
gpg --batch --verify "$T/site1/$repo/repodata/repomd.xml.asc" "$T/site1/$repo/repodata/repomd.xml" 2>/dev/null ||
    { echo "FAIL: repomd.xml signature does not verify"; exit 1; }
for f in install.sh openvibes.gpg openvibes.repo index.html packages.html site.css assets/wordmark-dark.svg; do [[ -s $T/site1/$f ]] || { echo "FAIL: $f missing"; exit 1; }; done

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
