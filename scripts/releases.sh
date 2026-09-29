#!/usr/bin/env bash
# Prints one "REPO TAG" line per published (non-draft) release of
# openvibes-platform, openvibes-agent and openvibes-rules, sorted. The site
# carries it as releases.txt, so the scheduled publish can tell whether
# anything was released since the last deploy. Needs GH_TOKEN.
set -euo pipefail
for repo in openvibes-platform openvibes-agent openvibes-rules; do
    gh release list -R "openvibes-project/$repo" --limit 1000 --json tagName,isDraft \
        --jq ".[] | select(.isDraft | not) | \"$repo \\(.tagName)\""
done | LC_ALL=C sort
