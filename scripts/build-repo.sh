#!/usr/bin/env bash
# Builds the site in SITE from the released packages already collected
# (scripts/collect.sh): RPMs in SITE/rpm/fedora/44/x86_64, .debs in
# SITE/deb, Arch packages in SITE/arch/x86_64, each .deb and Arch package
# with its detached .sig. Every package must be signed by PUBKEY (RPMs inside,
# the others by their .sig); each repository's metadata is
# indexed and signed (dnf repomd.xml.asc, apt InRelease, pacman
# openvibes.db.sig), and the installer, key, repository file and pages are
# added. Run from this
# repository's root. Env: RPM_SIGNING_KEY, RPM_SIGNING_PASSPHRASE.
# Any failure stops the build, so the live site keeps its previous state.
set -euo pipefail
[[ $# == 2 ]] || { echo "usage: $0 SITE PUBKEY" >&2; exit 2; }
site=$1 pubkey=$2
repo=$site/rpm/fedora/44/x86_64
here=$(cd "$(dirname "$0")" && pwd)
if grep -q '^KEY_FINGERPRINT=unset$' install.sh; then
    echo "build-repo: install.sh has no package key fingerprint" >&2; exit 1
fi
mkdir -p "$repo"
shopt -s nullglob; rpms=("$repo"/*.rpm); shopt -u nullglob
if ((${#rpms[@]})); then
    bash "$here/sign-rpms.sh" --check-only "$repo" "$pubkey"
fi
createrepo_c --quiet "$repo"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GNUPGHOME=$T/gnupg; mkdir -m 0700 "$GNUPGHOME"
printf '%s' "$RPM_SIGNING_KEY" | gpg --batch --quiet --import
printf '%s' "$RPM_SIGNING_PASSPHRASE" > "$T/pass"; chmod 0600 "$T/pass"
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$T/pass" \
    --detach-sign --armor --output "$repo/repodata/repomd.xml.asc" "$repo/repodata/repomd.xml"
# signed_by_key FILE: FILE.sig is one detached signature over FILE (class 00,
# a binary document) by PUBKEY's primary key. A plain gpg --verify would also
# accept other signature forms; the status lines leave no doubt.
mkdir -m 0700 "$T/verify"
GNUPGHOME=$T/verify gpg --batch --quiet --import "$pubkey"
key=$(GNUPGHOME=$T/verify gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')
signed_by_key() {
    local status
    [[ -f $1.sig ]] || return 1
    status=$(GNUPGHOME=$T/verify gpg --batch --status-fd 1 --verify "$1.sig" "$1" 2>/dev/null) || return 1
    [[ $(grep -c '^\[GNUPG:\] NEWSIG' <<<"$status") == 1 ]] || return 1
    awk -v key="$key" '$2 == "VALIDSIG" && $11 == "00" && $NF == key { ok = 1 } END { exit !ok }' <<<"$status"
}
# apt: a flat repository ("deb URL ./"), its Release hashing the index and
# clear-signed as InRelease. A .deb has no signature inside: its .sig is
# checked here, and InRelease carries the trust to apt.
deb=$site/deb
if compgen -G "$deb/*.deb" >/dev/null; then
    for p in "$deb"/*.deb; do
        signed_by_key "$p" || { echo "build-repo: $p is not signed with the OpenVIBES key" >&2; exit 1; }
    done
    (cd "$deb" && dpkg-scanpackages --multiversion . /dev/null > Packages 2>/dev/null && gzip -9kf Packages)
    {
        echo "Origin: OpenVIBES"
        echo "Label: OpenVIBES"
        echo "Architectures: amd64"
        echo "Date: $(LC_ALL=C date -Ru)"
        echo "SHA256:"
        for f in Packages Packages.gz; do
            printf ' %s %s %s\n' "$(sha256sum "$deb/$f" | cut -d' ' -f1)" "$(stat -c %s "$deb/$f")" "$f"
        done
    } > "$deb/Release"
    gpg --batch --yes --pinentry-mode loopback --passphrase-file "$T/pass" \
        --clearsign --output "$deb/InRelease" "$deb/Release"
fi
# pacman: every package signed by PUBKEY, then the database built, made
# plain files (Pages may not keep symlinks) and signed.
arch=$site/arch/x86_64
if compgen -G "$arch/*.pkg.tar.zst" >/dev/null; then
    for p in "$arch"/*.pkg.tar.zst; do
        signed_by_key "$p" || { echo "build-repo: $p is not signed with the OpenVIBES key" >&2; exit 1; }
    done
    # -p: never replace an entry with an older version. The glob is in string
    # order (0.2.10 before 0.2.9), and repo-add otherwise keeps the last one.
    (cd "$arch" && rm -f openvibes.db* openvibes.files* && repo-add -q -p openvibes.db.tar.gz ./*.pkg.tar.zst)
    for f in openvibes.db openvibes.files; do cp --remove-destination "$arch/$f.tar.gz" "$arch/$f"; done
    gpg --batch --yes --pinentry-mode loopback --passphrase-file "$T/pass" \
        --detach-sign --output "$arch/openvibes.db.sig" "$arch/openvibes.db"
fi
cp install.sh "$pubkey" openvibes.repo index.html packages.html site.css "$site/"
cp -r assets "$site/"
[[ $pubkey == openvibes.gpg ]] || cp "$pubkey" "$site/openvibes.gpg"
echo "build-repo: ${#rpms[@]} packages in $repo"
