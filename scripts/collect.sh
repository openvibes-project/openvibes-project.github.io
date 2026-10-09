#!/usr/bin/env bash
# Downloads the packages of every published (non-draft) release of
# openvibes-platform, openvibes-agent and openvibes-rules into SITE's
# repositories: RPMs to rpm/fedora/44/x86_64, .debs and their signatures to deb, Arch packages
# and their signatures to arch/x86_64. Only the kinds a release has are
# fetched (gh release download -p fails when nothing matches). Needs GH_TOKEN.
set -euo pipefail
[[ $# == 1 ]] || { echo "usage: $0 SITE" >&2; exit 2; }
site=$1
rpm=$site/rpm/fedora/44/x86_64 deb=$site/deb arch=$site/arch/x86_64
mkdir -p "$rpm" "$deb" "$arch"
for repo in openvibes-platform openvibes-agent openvibes-rules; do
    gh release list -R "openvibes-project/$repo" --limit 1000 --json tagName,isDraft \
        --jq '.[] | select(.isDraft | not) | .tagName' |
        while read -r tag; do
            gh release view "$tag" -R "openvibes-project/$repo" --json assets --jq '.assets[].name' |
                while read -r a; do
                    case $a in
                        # The model's gigabytes come from its publisher (decisions.md 2026-10-09).
                        *-llm-model-part*) continue ;;
                        *.rpm) d=$rpm ;;
                        *.deb | *.deb.sig) d=$deb ;;
                        *.pkg.tar.zst | *.pkg.tar.zst.sig) d=$arch ;;
                        *) continue ;;
                    esac
                    [[ -f $d/$a ]] || gh release download "$tag" -R "openvibes-project/$repo" -p "$a" -D "$d"
                done
        done
done
echo "collect: $(find "$rpm" -name '*.rpm' | wc -l) RPMs, $(find "$deb" -name '*.deb' | wc -l) .debs, $(find "$arch" -name '*.pkg.tar.zst' | wc -l) Arch packages"
