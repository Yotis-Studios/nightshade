#!/usr/bin/env bash
# =============================================================================
#  ci_imports.sh — NIGHTSHADE's structural gate.            Owned by W2-13.
# =============================================================================
#
#  Six rules, each independently reported, each independently negative-tested
#  by `--selftest`.  Any violation exits 1 and names the rule.
#
#   R1  THE IMPORT WALL          CLAUDE.md §3
#   R2  LEGACY-MODULE BAN        CLAUDE.md §3 (the seven frozen wobbleweed files)
#   R3  THE g_ PREFIX RULE       CLAUDE.md §1 rule 3 / criterion C
#   R4  NO HEX COLOUR OUTSIDE palette.hml            CLAUDE.md §8
#   R5  NO @stdlib/random UNDER src/sim/             CLAUDE.md §7
#   R6  gn.hml IS IMPORTED FROM src/net/ AND NOWHERE ELSE
#
#  Scanned:  $NS_ROOT/src/**/*.hml   (all six rules)
#            $NS_ROOT/tools/*.hml    (R2, R3, R6 — tools are not walled, but a
#                                     tool that reaches for a frozen legacy
#                                     module is still a bug)
#  NOT scanned: tools/bench/**, tools/probes/**, tools/probes-host/** — the
#            frozen recon corpus deliberately imports geom.hml et al. so the
#            benchmarks keep comparing against the old renderer.
#
#  Usage:
#     ./tools/ci_imports.sh              # gate the repo
#     ./tools/ci_imports.sh --selftest   # prove every rule fails on a violation
#     NS_ROOT=/path/to/ns ./tools/ci_imports.sh
#
#  Env: NS_ROOT (default: this script's ../), WW_ROOT (default: $NS_ROOT/../wobbleweed)
#
#  --- Two deliberate, documented relaxations -------------------------------
#  (a) R3 FAILS on a lower/mixed-case top-level variable (`let frame = 0`), and
#      WARNS on an ALL_CAPS one (`export let BTN_FIRE = 1`).  Reason:
#      ARCHITECTURE.md §5 specifies ~40 exported ALL_CAPS constants by name
#      (KIND_*, BTN_*, RNG_*, LAYER_*, ID_PLAYER_BASE, ...) while CLAUDE.md
#      criterion C says every top-level variable is g_-prefixed.  Failing the
#      documented signatures would make this script the bug.  Warnings are
#      counted and printed; set NS_STRICT_G=1 to promote them to failures.
#  (b) R4 accepts a `// ci-hex-ok` trailing comment on a line whose 6-hex-digit
#      literal is a bit mask rather than a colour.  Exemptions are COUNTED and
#      PRINTED, so they cannot hide.
# =============================================================================

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS_ROOT="${NS_ROOT:-$(cd "$SELF_DIR/.." && pwd)}"
WW_ROOT="${WW_ROOT:-$(cd "$NS_ROOT/.." 2>/dev/null && pwd)/wobbleweed}"
STRICT_G="${NS_STRICT_G:-0}"

LEGACY_MODULES="geom.hml framebuffer.hml raster.hml sky.hml postfx.hml scene.hml scene_gpu.hml"

VERBOSE=0
WARNBUF="$(mktemp)"
FAIL=0
WARNS=0
HEX_EXEMPT=0
N_FILES=0
N_IMPORTS=0
declare -A RULE_FAIL=( [R1]=0 [R2]=0 [R3]=0 [R4]=0 [R5]=0 [R6]=0 )

err() { RULE_FAIL[$1]=$(( ${RULE_FAIL[$1]} + 1 )); FAIL=1; printf '  %-3s FAIL  %s\n' "$1" "$2"; }
# Warnings are BUFFERED and summarised per file. 660 identical R3 lines is not
# a report, it is a wall — and a wall is what gets ignored. `-v` lists them all.
warn() { WARNS=$(( WARNS + 1 )); printf '%s\t%s\t%s\n' "$1" "$3" "$2" >> "$WARNBUF"; }

# ---------------------------------------------------------------------------
# zone_of <repo-relative path>  ->  core|sim|art|render|net|game|data|tools|src
# ---------------------------------------------------------------------------
zone_of() {
    case "$1" in
        src/core/*)   echo core   ;;
        src/sim/*)    echo sim    ;;
        src/art/*)    echo art    ;;
        src/render/*) echo render ;;
        src/net/*)    echo net    ;;
        src/game/*)   echo game   ;;
        src/data/*)   echo data   ;;
        tools/*)      echo tools  ;;
        *)            echo src    ;;
    esac
}

# ---------------------------------------------------------------------------
# classify <importing file> <import spec>  ->  a class token
#   stdlib:<name> | ns:<zone> | ww | ww:legacy | gn | ffi | unknown
# ---------------------------------------------------------------------------
classify() {
    local f="$1" spec="$2" abs base
    case "$spec" in
        @stdlib/*) echo "stdlib:${spec#@stdlib/}"; return ;;
    esac
    case "$spec" in
        *.hml) : ;;
        *) echo ffi; return ;;          # import "libSDL2-2.0.so.0";
    esac
    base="$(basename "$spec")"
    if [ "$base" = "gn.hml" ]; then echo gn; return; fi
    abs="$(realpath -m "$(dirname "$f")/$spec")"
    case "$abs" in
        "$NS_ROOT"/src/*)
            echo "ns:$(zone_of "src/${abs#"$NS_ROOT"/src/}")" ;;
        "$NS_ROOT"/tools/*) echo "ns:tools" ;;
        "$WW_ROOT"/src/*)
            for L in $LEGACY_MODULES; do
                if [ "$base" = "$L" ]; then echo "ww:legacy"; return; fi
            done
            echo ww ;;
        *) echo unknown ;;
    esac
}

# ---------------------------------------------------------------------------
# wall_allows <zone> <class>   -> 0 allowed, 1 denied
#  CLAUDE.md §3.  Sibling imports inside a zone are always allowed (the wall
#  table says so for src/sim and src/render; it is implied for the rest).
# ---------------------------------------------------------------------------
wall_allows() {
    local z="$1" c="$2"
    [ "$c" = "ns:$z" ] && return 0                 # siblings, every zone
    case "$z" in
      tools|game) return 0 ;;                      # game may import everything
      core)
        case "$c" in stdlib:*) return 0 ;; *) return 1 ;; esac ;;
      sim)
        case "$c" in
          stdlib:math) return 0 ;;
          ns:core)     return 0 ;;
          *)           return 1 ;;
        esac ;;
      art)
        case "$c" in stdlib:*|ns:core|ww) return 0 ;; *) return 1 ;; esac ;;
      render)
        case "$c" in stdlib:*|ns:core|ns:sim|ww) return 0 ;; *) return 1 ;; esac ;;
      net)
        case "$c" in stdlib:*|ns:sim|gn) return 0 ;; *) return 1 ;; esac ;;
      data)
        case "$c" in stdlib:*|ns:core) return 0 ;; *) return 1 ;; esac ;;
      *) return 1 ;;
    esac
}

wall_rule_text() {
    case "$1" in
      core)   echo '@stdlib/* only' ;;
      sim)    echo '@stdlib/math, src/sim/**, src/core/** — NO SDL, NO wobbleweed, NO gn.hml, NO @stdlib/random' ;;
      art)    echo 'wobbleweed, src/core/**, @stdlib/*' ;;
      render) echo 'wobbleweed, src/render/**, src/core/**, src/sim/**, @stdlib/* — NOT src/net/**' ;;
      net)    echo 'src/sim/**, gn.hml, @stdlib/*' ;;
      data)   echo 'src/core/**, @stdlib/*' ;;
      *)      echo 'everything' ;;
    esac
}

# ---------------------------------------------------------------------------
#  the scan
# ---------------------------------------------------------------------------
scan() {
    local files=() f rel zone
    while IFS= read -r f; do files+=("$f"); done < <(
        { [ -d "$NS_ROOT/src" ] && find "$NS_ROOT/src" -type f -name '*.hml';
          [ -d "$NS_ROOT/tools" ] && find "$NS_ROOT/tools" -maxdepth 1 -type f -name '*.hml'; } 2>/dev/null | LC_ALL=C sort)

    N_FILES=${#files[@]}
    if [ "$N_FILES" -eq 0 ]; then
        echo "  WARN  scanned 0 .hml files under $NS_ROOT/src and $NS_ROOT/tools —"
        echo "        this run proves NOTHING.  (Expected before Wave 2 lands files.)"
        return
    fi

    for f in "${files[@]}"; do
        rel="${f#"$NS_ROOT"/}"
        zone="$(zone_of "$rel")"

        # ---- comment-stripped body, used by every text rule ----------------
        local body; body="$(sed 's://.*::' "$f")"

        # ---- R1 / R2 / R5 / R6 : imports ----------------------------------
        local specs spec class
        specs="$(printf '%s\n' "$body" \
                 | grep -oE '(from[[:space:]]*"[^"]+"|^[[:space:]]*import[[:space:]]+"[^"]+")' \
                 | grep -oE '"[^"]+"' | tr -d '"')"
        for spec in $specs; do
            [ -z "$spec" ] && continue
            N_IMPORTS=$(( N_IMPORTS + 1 ))
            class="$(classify "$f" "$spec")"

            # R2 — legacy ban (src/** and tools/*.hml alike)
            if [ "$class" = "ww:legacy" ]; then
                err R2 "$rel imports FROZEN LEGACY module '$spec' (CLAUDE.md §3)"
                continue
            fi

            # R5 — @stdlib/random under src/sim
            if [ "$zone" = "sim" ] && [ "$class" = "stdlib:random" ]; then
                err R5 "$rel imports @stdlib/random — the sim must be seed-reproducible (CLAUDE.md §7)"
                continue
            fi

            # R6 — gn.hml only from src/net/**
            if [ "$class" = "gn" ] && [ "$zone" != "net" ]; then
                err R6 "$rel imports gn.hml — only src/net/** may (CLAUDE.md §3)"
                continue
            fi

            # R1 — the wall itself (tools are not walled)
            if [ "$zone" != "tools" ]; then
                if ! wall_allows "$zone" "$class"; then
                    err R1 "$rel (zone '$zone') imports '$spec' [$class]; may import: $(wall_rule_text "$zone")"
                fi
            fi
        done

        # ---- R3 : the g_ prefix rule --------------------------------------
        local name
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            case "$name" in
                g_*) : ;;
                *)
                    if printf '%s' "$name" | grep -qE '^[A-Z][A-Z0-9_]*$'; then
                        if [ "$STRICT_G" = "1" ]; then
                            err R3 "$rel top-level '$name' is not g_-prefixed (NS_STRICT_G=1)"
                        else
                            warn R3 "top-level ALL_CAPS constant '$name' is not g_-prefixed (ARCHITECTURE.md §5 names it; CLAUDE.md §1 rule 3 wants g_)" "$rel"
                        fi
                    else
                        err R3 "$rel top-level variable '$name' is not g_-prefixed (CLAUDE.md §1 rule 3 — 423 vs 222 ms/50M, silent)"
                    fi ;;
            esac
        done < <(printf '%s\n' "$body" \
                 | grep -E '^(export[[:space:]]+)?(let|const|var)[[:space:]]' \
                 | grep -oE '\b(let|const|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
                 | sed -E 's/^(let|const|var)[[:space:]]+//')

        # ---- R4 : no hex colour outside src/art/palette.hml ---------------
        if [ "$zone" != "tools" ] && [ "$rel" != "src/art/palette.hml" ]; then
            local hitline
            while IFS= read -r hitline; do
                [ -z "$hitline" ] && continue
                local ln="${hitline%%:*}"
                if sed -n "${ln}p" "$f" | grep -q 'ci-hex-ok'; then
                    HEX_EXEMPT=$(( HEX_EXEMPT + 1 ))
                else
                    err R4 "$rel:$ln hex colour literal outside src/art/palette.hml (CLAUDE.md §8) -> ${hitline#*:}"
                fi
            done < <(printf '%s\n' "$body" | grep -noP '0x[0-9A-Fa-f]{6}(?![0-9A-Fa-f])')
        fi
    done
}

# ---------------------------------------------------------------------------
#  --selftest : one deliberate violation per rule, plus a clean control.
#  Each case must make a FRESH run of this very script exit non-zero and print
#  the rule tag.  A rule that cannot fail is not a rule.
# ---------------------------------------------------------------------------
selftest() {
    local tmp; tmp="$(mktemp -d)"
    local ns="$tmp/nightshade"
    local pass=0 total=0
    mkdir -p "$ns"/src/{core,sim,art,render,net,game,data} "$ns"/tools "$tmp"/wobbleweed/src

    # a minimal, clean tree that every case starts from
    reset_tree() {
        rm -rf "$ns/src" "$ns/tools"; mkdir -p "$ns"/src/{core,sim,art,render,net,game} "$ns"/tools
        printf 'import { sqrt } from "@stdlib/math";\nlet g_ok: i32 = 1;\nfn f(): i32 { let o: i32 = g_ok; return o; }\n' > "$ns/src/core/config.hml"
        printf 'import { sqrt } from "@stdlib/math";\nimport { f } from "../core/config.hml";\nexport let RNG_LOOT = 0;\nlet g_s: i32 = 1;\n' > "$ns/src/sim/rng.hml"
        printf 'import { f } from "../core/config.hml";\nlet g_p: i32 = 8102454;\n' > "$ns/src/art/palette.hml"
    }

    # run <expect-exit> <expect-tag|-> <label>
    run_case() {
        local want_exit="$1" want_tag="$2" label="$3" out rc
        total=$(( total + 1 ))
        out="$(NS_ROOT="$ns" WW_ROOT="$tmp/wobbleweed" bash "${BASH_SOURCE[0]}" 2>&1)"; rc=$?
        local ok=1
        [ "$rc" -eq "$want_exit" ] || ok=0
        if [ "$want_tag" != "-" ]; then printf '%s' "$out" | grep -q "$want_tag  *FAIL" || ok=0; fi
        if [ "$ok" = 1 ]; then
            pass=$(( pass + 1 )); printf '  ok   %-52s exit=%d\n' "$label" "$rc"
        else
            printf '  FAIL %-52s exit=%d (wanted %d/%s)\n' "$label" "$rc" "$want_exit" "$want_tag"
            printf '%s\n' "$out" | sed 's/^/         | /'
        fi
    }

    echo "== ci_imports.sh SELFTEST (fixture: $ns) =="

    reset_tree; run_case 0 - "control: clean tree passes"

    reset_tree; printf 'import { window_open } from "../../../wobbleweed/src/sdl.hml";\n' > "$ns/src/sim/bad.hml"
    run_case 1 R1 "R1 sim -> wobbleweed/sdl.hml"

    reset_tree; printf 'import { proto_write_input } from "../net/protocol.hml";\n' > "$ns/src/render/bad.hml"
    run_case 1 R1 "R1 render -> src/net"

    reset_tree; printf 'import { rng_next } from "../sim/rng.hml";\n' > "$ns/src/core/bad.hml"
    run_case 1 R1 "R1 core -> src/sim"

    reset_tree; printf 'import { crc32 } from "@stdlib/hash";\n' > "$ns/src/sim/bad.hml"
    run_case 1 R1 "R1 sim -> @stdlib/hash (only @stdlib/math)"

    reset_tree; printf 'import { batch_new } from "../../../wobbleweed/src/geom.hml";\n' > "$ns/src/art/bad.hml"
    run_case 1 R2 "R2 art -> frozen legacy geom.hml"

    reset_tree; printf 'let frame: i32 = 0;\n' > "$ns/src/game/bad.hml"
    run_case 1 R3 "R3 top-level 'frame' without g_"

    reset_tree; printf 'let g_grass: i32 = 0x7A9636;\n' > "$ns/src/art/bad.hml"
    run_case 1 R4 "R4 hex colour outside palette.hml"

    reset_tree; printf 'let g_grass: i32 = 0x7A9636;  // ci-hex-ok\n' > "$ns/src/art/bad.hml"
    run_case 0 - "R4 '// ci-hex-ok' exemption is honoured"

    reset_tree; printf 'import { rand } from "@stdlib/random";\n' > "$ns/src/sim/bad.hml"
    run_case 1 R5 "R5 @stdlib/random under src/sim"

    reset_tree; printf 'import { net_send } from "../../../gn.hml";\n' > "$ns/src/game/bad.hml"
    run_case 1 R6 "R6 gn.hml imported outside src/net"

    reset_tree; printf 'import { batch_new } from "../../wobbleweed/src/scene_gpu.hml";\n' > "$ns/tools/bad.hml"
    run_case 1 R2 "R2 tools/*.hml -> frozen legacy scene_gpu.hml"

    rm -rf "$tmp"
    echo
    echo "SELFTEST $pass/$total"
    [ "$pass" -eq "$total" ] || return 1
    [ "$total" -eq 12 ] || { echo "SELFTEST case count changed (expected 12)"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
case "${1:-}" in
    --selftest) selftest; rc=$?; rm -f "$WARNBUF"; exit $rc ;;
    -v|--verbose) VERBOSE=1 ;;
    --help|-h) sed -n '2,50p' "${BASH_SOURCE[0]}"; rm -f "$WARNBUF"; exit 0 ;;
esac

echo "== ci_imports.sh =="
echo "   NS_ROOT=$NS_ROOT"
echo "   WW_ROOT=$WW_ROOT"
scan
# ---- warning summary ------------------------------------------------------
if [ "$WARNS" -gt 0 ]; then
    echo
    if [ "$VERBOSE" = 1 ]; then
        awk -F'\t' '{ printf "  %-3s warn  %s %s\n", $1, $2, $3 }' "$WARNBUF"
    else
        echo "  warnings (use -v to list every one):"
        awk -F'\t' '{ k = $1 " " $2; c[k]++; if (!(k in ex)) ex[k]=$3 }
             END { for (k in c) printf "  %-6s %-34s %3d x  e.g. %s\n", "warn", k, c[k], substr(ex[k],1,64) }' \
            "$WARNBUF" | LC_ALL=C sort
    fi
fi
rm -f "$WARNBUF"

# ---------------------------------------------------------------------------
# R7 — the harness must never carry its own copy of the frame graph.
#
# tools/shot.hml currently defines a private `frame_render` because it was built
# in Wave 2, before src/render/world_render.hml existed. W3-7 re-owns shot.hml
# and rewires it to the real one. This rule makes forgetting that impossible.
#
# Why it is worth a CI rule: Wave 2 shipped a visual harness carrying ~650 lines
# of STAND-IN ART, so every committed screenshot depicted art the game did not
# use, and every probe passed. A harness holding a private copy of the thing it
# is meant to photograph is the same defect one layer up — and a second frame
# graph would drift from the real one silently, exactly as the art did.
# ---------------------------------------------------------------------------
RULE_FAIL[R7]=0
REAL_FG="$NS_ROOT/src/render/world_render.hml"
SHOT="$NS_ROOT/tools/shot.hml"
if [ -f "$REAL_FG" ] && [ -f "$SHOT" ]; then
    if grep -qE '^[[:space:]]*(export[[:space:]]+)?fn[[:space:]]+frame_render[[:space:]]*\(' "$SHOT"; then
        err R7 "tools/shot.hml defines its own frame_render, but src/render/world_render.hml exists. The harness MUST import the real frame graph (W3-7) or it will silently drift from the game."
    fi
    if ! grep -qE 'from[[:space:]]+"\.\./src/render/world_render\.hml"' "$SHOT"; then
        err R7 "tools/shot.hml does not import src/render/world_render.hml. It must render through the REAL frame path, never a parallel one."
    fi
fi

echo
printf '   files=%d imports=%d warnings=%d hex-exemptions=%d\n' \
       "$N_FILES" "$N_IMPORTS" "$WARNS" "$HEX_EXEMPT"
for r in R1 R2 R3 R4 R5 R6 R7; do
    if [ "${RULE_FAIL[$r]}" -eq 0 ]; then printf '   %-3s PASS\n' "$r"
    else printf '   %-3s FAIL (%d)\n' "$r" "${RULE_FAIL[$r]}"; fi
done
echo "   RULES 7/7 checked"
if [ "$FAIL" -ne 0 ]; then echo "CI_IMPORTS FAIL"; exit 1; fi
echo "CI_IMPORTS PASS"
exit 0
