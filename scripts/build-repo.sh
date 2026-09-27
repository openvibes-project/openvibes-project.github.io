#!/usr/bin/env bash
# Builds the site in SITE from the released RPMs already collected into
# SITE/rpm/fedora/44/x86_64 (scripts/collect.sh): every package must be
# signed by PUBKEY, the metadata is indexed and signed, and the installer,
# key, repository file and landing page are added. Run from this
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
cp install.sh "$pubkey" openvibes.repo index.html "$site/"
[[ $pubkey == openvibes.gpg ]] || cp "$pubkey" "$site/openvibes.gpg"
echo "build-repo: ${#rpms[@]} packages in $repo"
