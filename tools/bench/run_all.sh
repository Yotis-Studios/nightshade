#!/usr/bin/env bash
# run_all.sh — compile every bench with hemlockc -O3 and run it.
# Usage: ./run_all.sh [outdir]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-/tmp/nightshade-bench}"
mkdir -p "$OUT"

for f in "$HERE"/bench_*.hml; do
    name="$(basename "$f" .hml)"
    echo "=============================================================="
    echo "== $name"
    echo "=============================================================="
    hemlockc -O3 "$f" -o "$OUT/$name" 2>&1 | grep -v "always_inline\|^ *[0-9]* |\|^ *|" || true
    if [ -x "$OUT/$name" ]; then
        timeout 900 "$OUT/$name"
        echo "(exit $?)"
    else
        echo "COMPILE FAILED"
    fi
    echo
done

echo "=============================================================="
echo "== bench_interp_vs_compiled.hml under the INTERPRETER"
echo "=============================================================="
timeout 900 hemlock "$HERE/bench_interp_vs_compiled.hml"
