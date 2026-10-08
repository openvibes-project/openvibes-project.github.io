#!/usr/bin/env bash
# Checks the site's pages: every local link and asset exists, every
# in-page anchor has its target, and the images stay under 1 MB (the site
# is already over GitHub Pages' size soft limit; website spec §5).
# Looks at href/src (either quote, any case), every srcset candidate, and
# url() in the stylesheets.
# Usage: tests/check-site.sh [DIR]   (default: the repository root)
set -euo pipefail
DIR=${1:-$(cd "$(dirname "$0")/.." && pwd)}
# Written into the site at publish time (scripts/releases.sh, build-repo.sh),
# not in the repository: links to them are not checked here.
SITE_GENERATED="releases.txt rpm"
bad=0
fail() { echo "FAIL: $*"; bad=1; }
# has_id FILE ID: FILE has an element with exactly that id (not data-id=).
has_id() {
    local file=$1 id=$2
    grep -qE "[[:space:]]id=\"$id\"" "$file"
}
# refs FILE: the local references in FILE, one per line.
refs() {
    local file=$1
    case $file in
        *.css)
            { grep -oE 'url\([^)]*\)' "$file" || true; } | sed -E "s/^url\\([\"']?//; s/[\"']?\\)\$//" | { grep -v '^data:' || true; } ;;
        *)
            { grep -oiE "(href|src)[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*')" "$file" || true; } |
                sed -E "s/^[^=]*=[[:space:]]*[\"']//; s/[\"']\$//"
            { grep -oiE "srcset[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*')" "$file" || true; } |
                sed -E "s/^[^=]*=[[:space:]]*[\"']//; s/[\"']\$//" | tr ',' '\n' | awk 'NF {print $1}' ;;
    esac
}
for file in "$DIR"/*.html "$DIR"/*.css; do
    [[ -e $file ]] || continue
    name=$(basename "$file")
    while read -r ref; do
        case $ref in
            http://* | https://* | mailto:*) ;;
            '#'*) has_id "$file" "${ref#\#}" || fail "$name: no id for $ref" ;;
            *)
                case " $SITE_GENERATED " in *" ${ref%%/*} "*) continue ;; esac
                path=${ref%%#*}
                [[ -e $DIR/$path ]] || { fail "$name: $ref does not exist"; continue; }
                # Another page's anchor: that page must have the id.
                if [[ $ref == *'#'* ]]; then
                    [[ -z $path || $path == ./ || $path == */ ]] && path=${path}index.html
                    has_id "$DIR/$path" "${ref#*#}" || fail "$name: no id for $ref"
                fi ;;
        esac
    done < <(refs "$file")
done
size=0
if [[ -d $DIR/assets ]]; then
    size=$(find "$DIR/assets" -type f \( -name '*.webp' -o -name '*.png' -o -name '*.jpg' -o -name '*.svg' \) -printf '%s\n' | awk '{s += $1} END {print s + 0}')
fi
(( size <= 1048576 )) || fail "images are $size bytes, over 1 MB"
(( bad == 0 )) && echo "check-site: ok ($size bytes of images)"
exit "$bad"
