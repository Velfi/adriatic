#!/bin/sh

set -eu

manifest=${1:-tools/module_size_manifest.txt}
maximum=${2:-699}
failed=0

while IFS= read -r path || [ -n "$path" ]; do
    case "$path" in
        ""|'#'*) continue ;;
    esac

    if [ ! -f "$path" ]; then
        echo "module-size-check: missing $path" >&2
        failed=1
        continue
    fi

    lines=$(wc -l < "$path" | tr -d ' ')
    if [ "$lines" -gt "$maximum" ]; then
        echo "module-size-check: $path has $lines lines (maximum $maximum)" >&2
        failed=1
    fi
done < "$manifest"

exit "$failed"
