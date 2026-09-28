#!/usr/bin/env bash
# Downloads the RPMs of every published (non-draft) release of
# openvibes-platform, openvibes-agent and openvibes-rules into OUT. Needs GH_TOKEN.
set -euo pipefail
[[ $# == 1 ]] || { echo "usage: $0 OUT" >&2; exit 2; }
out=$1
mkdir -p "$out"
for repo in openvibes-platform openvibes-agent openvibes-rules; do
    gh release list -R "openvibes-project/$repo" --limit 1000 --json tagName,isDraft \
        --jq '.[] | select(.isDraft | not) | .tagName' |
        while read -r tag; do
            gh release download "$tag" -R "openvibes-project/$repo" -p '*.rpm' -D "$out" --skip-existing
        done
done
echo "collect: $(find "$out" -maxdepth 1 -name "*.rpm" | wc -l) packages"
