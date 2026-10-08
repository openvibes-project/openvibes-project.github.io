#!/usr/bin/env bash
# Checks the site's pages: every local link and asset exists, every
# in-page anchor has its target, and the images stay under 1 MB (the site
# is already over GitHub Pages' size soft limit; website spec §5).
# Usage: tests/check-site.sh [DIR]   (default: the repository root)
set -euo pipefail
DIR=${1:-$(cd "$(dirname "$0")/.." && pwd)}
bad=0
fail() { echo "FAIL: $*"; bad=1; }
for page in "$DIR"/*.html; do
    name=$(basename "$page")
    while read -r ref; do
        case $ref in
            http://* | https://* | mailto:*) ;;
            '#'*) grep -q "id=\"${ref#\#}\"" "$page" || fail "$name: no id for $ref" ;;
            *) [[ -e $DIR/${ref%%#*} ]] || fail "$name: $ref does not exist" ;;
        esac
    done < <(grep -oE '(href|src)="[^"]*"' "$page" | sed -E 's/^(href|src)="(.*)"$/\2/')
done
size=0
if [[ -d $DIR/assets ]]; then
    size=$(find "$DIR/assets" -type f \( -name '*.webp' -o -name '*.png' -o -name '*.jpg' -o -name '*.svg' \) -printf '%s\n' | awk '{s += $1} END {print s + 0}')
fi
(( size <= 1048576 )) || fail "images are $size bytes, over 1 MB"
(( bad == 0 )) && echo "check-site: ok ($size bytes of images)"
exit "$bad"
