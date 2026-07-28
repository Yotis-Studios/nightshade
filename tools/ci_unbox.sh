#!/usr/bin/env bash
# =============================================================================
#  ci_unbox.sh — "did the hot locals actually unbox?"        Owned by W2-13.
# =============================================================================
#
#  CLAUDE.md §2 / §4-A1:  a hot function copies its parameters into typed locals
#  because parameters are NEVER unboxed.  If that copy is untyped, the backend
#  emits `HmlValue acc = hml_convert_to_type(...)` instead of `double acc =
#  hml_to_f64(...)` and you silently lose ~2x on the hottest loop in the game.
#  Nothing in the language warns you.  This script is the warning.
#
#  The check:
#     hemlockc -c <file> --emit-c <tmp.c>
#     scope to the C functions that came from <file>  (hml_fn_<name>)
#     every local named one of the TWELVE
#         mx my mz vx vy vz sx sy w d f acc
#     must be declared `double` / `int32_t` / `int64_t`, never `HmlValue`.
#
#  Scoping matters: `--emit-c` emits the WHOLE transitive import graph (1.5 MB
#  for emit.hml), and boxed `d`s in @stdlib are none of our business.
#
#  Usage:
#     ./tools/ci_unbox.sh                 # the default hot-kernel list
#     ./tools/ci_unbox.sh a.hml b.hml     # explicit targets
#     ./tools/ci_unbox.sh --selftest      # prove it fails on a boxed local
#     ./tools/ci_unbox.sh -v              # print every local it looked at
#
#  Env: NS_ROOT, WW_ROOT, HEMLOCKC (default `hemlockc`)
#
#  A file in the default list that does not exist yet is SKIPPED and printed as
#  skipped — Wave 2 has not written the renderer yet and a gate that quietly
#  checks nothing is worse than no gate.  If the run ends up checking ZERO
#  locals in total, that is a FAILURE, not a pass.
# =============================================================================

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS_ROOT="${NS_ROOT:-$(cd "$SELF_DIR/.." && pwd)}"
WW_ROOT="${WW_ROOT:-$(cd "$NS_ROOT/.." 2>/dev/null && pwd)/wobbleweed}"
HEMLOCKC="${HEMLOCKC:-hemlockc}"

# the twelve names from CLAUDE.md §2 — the documented hot-local vocabulary
HOT_NAMES='mx|my|mz|vx|vy|vz|sx|sy|w|d|f|acc'

VERBOSE=0
FAIL=0
N_TARGETS=0; N_SKIPPED=0; N_CHECKED=0; N_BOXED=0; N_FNS=0; N_WARN=0

default_targets() {
    # the hot kernels, in frame-graph order.  Missing files are skipped.
    cat <<EOF
$WW_ROOT/src/emit.hml
$WW_ROOT/src/clip.hml
$WW_ROOT/src/batch.hml
$WW_ROOT/src/mesh.hml
$WW_ROOT/src/billboard.hml
$WW_ROOT/src/shade.hml
$NS_ROOT/src/render/world_render.hml
$NS_ROOT/src/render/chunkmesh.hml
$NS_ROOT/src/render/terrain_render.hml
$NS_ROOT/src/render/entity_render.hml
$NS_ROOT/src/render/fx.hml
$NS_ROOT/src/sim/movement.hml
$NS_ROOT/src/sim/combat.hml
$NS_ROOT/src/sim/worldgen.hml
$NS_ROOT/src/core/mathx.hml
EOF
}

# ---------------------------------------------------------------------------
#  check_one <file.hml>
# ---------------------------------------------------------------------------
check_one() {
    local f="$1" cfile names out rc
    cfile="$(mktemp --suffix=.c)"

    if ! out="$("$HEMLOCKC" -c "$f" --emit-c "$cfile" 2>&1)"; then
        printf '  %-46s BUILD FAIL\n' "$(basename "$f")"
        printf '%s\n' "$out" | sed 's/^/        | /' | head -12
        FAIL=1; rm -f "$cfile"; return
    fi

    # every function this file defines
    names="$(grep -oE '^[[:space:]]*(export[[:space:]]+)?fn[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$f" \
             | sed -E 's/.*fn[[:space:]]+//' | sort -u | tr '\n' ' ')"
    if [ -z "$names" ]; then
        printf '  %-46s no functions\n' "$(basename "$f")"
        rm -f "$cfile"; return
    fi

    # ---- source-side map:  fn|local|annotation  --------------------------
    # A name from the twelve is only a HOT SCALAR when the source declares it
    # as one.  `let d: array<f64> = b.depth;` and `let w: object = p_w;` are
    # reference handles and are CORRECTLY HmlValue — flagging those would make
    # this script a liar (batch.hml alone has five).
    local map; map="$(mktemp)"
    awk '
        function scanlets(line, fn,   seg, nm, ann) {
            while (match(line, /(^|[^A-Za-z0-9_])let[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
                seg = substr(line, RSTART, RLENGTH)
                line = substr(line, RSTART + RLENGTH)
                nm = seg; sub(/^.*let[ \t]+/, "", nm)
                ann = ""
                if (match(line, /^[ \t]*:[ \t]*[A-Za-z_][A-Za-z0-9_]*(<[^>]*>)?/)) {
                    ann = substr(line, RSTART, RLENGTH); sub(/^[ \t]*:[ \t]*/, "", ann)
                }
                print fn "|" nm "|" ann
            }
        }
        { line = $0; sub(/\/\/.*$/, "", line) }
        cur == "" && line ~ /^[ \t]*(export[ \t]+)?fn[ \t]+[A-Za-z_]/ {
            cur = line; sub(/^.*fn[ \t]+/, "", cur); sub(/[ \t]*\(.*$/, "", cur)
            depth = 0; opened = 0
        }
        cur != "" {
            scanlets(line, cur)
            n = gsub(/\{/, "{", line); m = gsub(/\}/, "}", line)
            depth += n - m
            if (n > 0) opened = 1
            # a multi-line signature keeps depth at 0 until the body opens —
            # do not close the function before it has started.
            if (opened && depth <= 0) { depth = 0; opened = 0; cur = "" }
        }
    ' "$f" | sort -u > "$map"

    local res
    res="$(awk -v names="$names" -v hot="$HOT_NAMES" -v mapf="$map" '
        BEGIN { n=split(names, a, " "); for (i=1;i<=n;i++) if (a[i]!="") want[a[i]]=1;
                while ((getline ml < mapf) > 0) { split(ml, q, "|"); ann[q[1] "|" q[2]] = q[3] "?" }
                fnre = "^[A-Za-z_][A-Za-z0-9_ *]* hml_fn_[A-Za-z0-9_]+\\(.*\\) \\{$";
                decre = "^[ \t]+(HmlValue|double|int32_t|int64_t|int|float)[ \t]+(" hot ")[ \t]*[=;]";
                scalre = "^(f64|f32|i8|i16|i32|i64|u8|u16|u32|u64|bool)$" }
        $0 ~ fnre {
            fn=$0; sub(/^.* hml_fn_/, "", fn); sub(/\(.*$/, "", fn);
            base=fn; sub(/_[0-9]+$/, "", base);
            if (fn in want)      { cur=fn;   nfn++ }
            else if (base in want) { cur=base; nfn++ }
            else cur="";
            next
        }
        /^\}$/ { cur=""; next }
        cur != "" && $0 ~ decre {
            line=$0; sub(/^[ \t]+/, "", line);
            split(line, p, /[ \t]+/); type=p[1]; nm=p[2]; sub(/[=;].*$/, "", nm);
            key = cur "|" nm
            annv = (key in ann) ? ann[key] : "??"
            sub(/\?$/, "", annv)
            if (type != "HmlValue")            { printf "OK %s %s %s\n", cur, type, nm; next }
            if (annv == "")                    { printf "BOX %s untyped %s\n", cur, nm; next }
            if (annv ~ scalre)                 { printf "WARN %s %s %s\n", cur, annv, nm; next }
            if (annv == "?")                   { printf "WARN %s unknown %s\n", cur, nm; next }
            printf "REF %s %s %s\n", cur, annv, nm       # array/object/ptr/buffer — correct as HmlValue
        }
        END { printf "FNS %d\n", nfn }
    ' "$cfile")"
    rm -f "$map"

    local nfns nok nbox nwarn nref
    nfns="$(printf '%s\n' "$res" | awk '/^FNS/{print $2}')"
    nok="$(printf '%s\n' "$res"   | grep -c '^OK '   || true)"
    nbox="$(printf '%s\n' "$res"  | grep -c '^BOX '  || true)"
    nwarn="$(printf '%s\n' "$res" | grep -c '^WARN ' || true)"
    nref="$(printf '%s\n' "$res"  | grep -c '^REF '  || true)"
    N_FNS=$(( N_FNS + nfns )); N_CHECKED=$(( N_CHECKED + nok + nbox + nwarn ))
    N_BOXED=$(( N_BOXED + nbox )); N_WARN=$(( N_WARN + nwarn ))

    if [ "$nbox" -gt 0 ]; then
        printf '  %-46s BOXED %d / %d scalars in %s fns\n' "$(basename "$f")" "$nbox" "$(( nok + nbox + nwarn ))" "$nfns"
        FAIL=1
    elif [ "$nwarn" -gt 0 ]; then
        printf '  %-46s ok(%d warn) %d unboxed in %s fns\n' "$(basename "$f")" "$nwarn" "$nok" "$nfns"
    else
        printf '  %-46s ok    %d scalars unboxed in %s fns (%d refs)\n' "$(basename "$f")" "$nok" "$nfns" "$nref"
    fi
    printf '%s\n' "$res" | grep '^BOX ' | while read -r _ fn _ nm; do
        printf '        FAIL HmlValue %-4s in %s() — UNTYPED `let %s = ...`; write `let %s: f64 = ...` (CLAUDE.md A1, 2x)\n' "$nm" "$fn" "$nm" "$nm"
    done
    printf '%s\n' "$res" | grep '^WARN ' | while read -r _ fn ty nm; do
        printf '        warn HmlValue %-4s in %s() — source says `: %s` but the backend kept it boxed\n' "$nm" "$fn" "$ty"
    done
    if [ "$VERBOSE" = 1 ]; then printf '%s\n' "$res" | grep -E '^(OK|REF) ' | sed 's/^/        /'; fi
    rm -f "$cfile"
}

# ---------------------------------------------------------------------------
#  --selftest
# ---------------------------------------------------------------------------
selftest() {
    local tmp; tmp="$(mktemp -d)"; local pass=0 total=0
    run_case() {                       # run_case <want-exit> <file> <label>
        local want="$1" file="$2" label="$3" out rc
        total=$(( total + 1 ))
        out="$(bash "${BASH_SOURCE[0]}" "$file" 2>&1)"; rc=$?
        if [ "$rc" -eq "$want" ]; then pass=$(( pass + 1 )); printf '  ok   %-46s exit=%d\n' "$label" "$rc"
        else printf '  FAIL %-46s exit=%d (wanted %d)\n' "$label" "$rc" "$want"; printf '%s\n' "$out" | sed 's/^/         | /'; fi
    }

    echo "== ci_unbox.sh SELFTEST (fixture: $tmp) =="

    # GOOD — the hot skeleton of CLAUDE.md §4, verbatim
    cat > "$tmp/good.hml" <<'EOF'
export fn project(p_x: f64, p_y: f64, p_n: i32): f64 {
    let mx: f64 = p_x;
    let my: f64 = p_y;
    let acc: f64 = 0.0;
    let d: f64 = 0.0;
    let n: i32 = p_n;
    for (let i = 0; i < n; i++) { d = mx * my; acc = acc + d; }
    let out: f64 = acc;
    return out;
}
EOF
    run_case 0 "$tmp/good.hml" "typed hot locals -> unboxed, passes"

    # BAD — same function, untyped copies.  This is the mistake being hunted.
    cat > "$tmp/bad.hml" <<'EOF'
export fn project(p_x, p_y, p_n) {
    let mx = p_x;
    let my = p_y;
    let acc = 0.0;
    let d = 0.0;
    let n = p_n;
    for (let i = 0; i < n; i++) { d = mx * my; acc = acc + d; }
    let out = acc;
    return out;
}
EOF
    run_case 1 "$tmp/bad.hml" "untyped hot locals -> BOXED, fails"

    # VACUOUS — no hot local at all: must NOT be reported as a pass
    printf 'export fn q(p_a: i32): i32 { let z: i32 = p_a; return z; }\n' > "$tmp/none.hml"
    run_case 1 "$tmp/none.hml" "zero locals checked -> fails (no vacuous green)"

    # BUILD FAIL must be a failure, not a skip
    printf 'export fn broken(: { }\n' > "$tmp/broken.hml"
    run_case 1 "$tmp/broken.hml" "file that will not compile -> fails"

    rm -rf "$tmp"
    echo
    echo "SELFTEST $pass/$total"
    [ "$pass" -eq "$total" ] || return 1
    [ "$total" -eq 4 ] || { echo "SELFTEST case count changed (expected 4)"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
TARGETS=()
for a in "$@"; do
    case "$a" in
        --selftest) selftest; exit $? ;;
        --help|-h) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
        -v|--verbose) VERBOSE=1 ;;
        *) TARGETS+=("$a") ;;
    esac
done
if [ "${#TARGETS[@]}" -eq 0 ]; then
    while IFS= read -r t; do TARGETS+=("$t"); done < <(default_targets)
fi

echo "== ci_unbox.sh =="
echo "   hot locals: $HOT_NAMES"
for t in "${TARGETS[@]}"; do
    if [ ! -f "$t" ]; then
        N_SKIPPED=$(( N_SKIPPED + 1 ))
        printf '  %-46s SKIP (not written yet)\n' "$(basename "$t")"
        continue
    fi
    N_TARGETS=$(( N_TARGETS + 1 ))
    check_one "$t"
done

echo
printf '   targets=%d skipped=%d functions=%d scalars=%d boxed=%d warn=%d\n' \
       "$N_TARGETS" "$N_SKIPPED" "$N_FNS" "$N_CHECKED" "$N_BOXED" "$N_WARN"
if [ "$N_CHECKED" -eq 0 ]; then
    echo "   checked ZERO hot locals — this run proves nothing."
    echo "CI_UNBOX FAIL"; exit 1
fi
if [ "$FAIL" -ne 0 ]; then echo "CI_UNBOX FAIL"; exit 1; fi
echo "CI_UNBOX PASS"
exit 0
