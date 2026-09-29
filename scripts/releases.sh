#!/usr/bin/env bash
# Prints one "REPO TAG RPMS" line per published (non-draft) release of
# openvibes-platform, openvibes-agent and openvibes-rules, sorted; RPMS is
# the release's RPM asset names. The site carries it as releases.txt, so the
# scheduled publish can tell whether anything changed since the last deploy.
# The asset names matter: a release made in the GitHub UI is published
# before the workflow uploads its RPMs. Needs GH_TOKEN.
set -euo pipefail
for repo in openvibes-platform openvibes-agent openvibes-rules; do
    gh api "repos/openvibes-project/$repo/releases" --paginate \
        --jq ".[] | select(.draft | not) | \"$repo \\(.tag_name) \\([.assets[] | select(.state == \"uploaded\" and (.name | endswith(\".rpm\"))) | .name] | sort | join(\",\"))\""
done | LC_ALL=C sort
