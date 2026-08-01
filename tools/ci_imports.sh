#!/usr/bin/env bash
# =============================================================================
#  ci_imports.sh — NIGHTSHADE's structural gate.            Owned by W2-13.
# =============================================================================
#
#  EIGHT rules, each independently reported, each independently negative-tested
#  by `--selftest`.  Any violation exits 1 and names the rule.
#
#   R1  THE IMPORT WALL          CLAUDE.md §3
#   R2  LEGACY-MODULE BAN        CLAUDE.md §3 (the seven frozen wobbleweed files)
#   R3  THE g_ PREFIX RULE       CLAUDE.md §1 rule 3 / criterion C
#   R4  NO HEX COLOUR OUTSIDE palette.hml            CLAUDE.md §8
#   R5  NO @stdlib/random UNDER src/sim/             CLAUDE.md §7
#   R6  gn.hml IS IMPORTED FROM src/net/ AND NOWHERE ELSE
#   R7  NO TOOL CARRIES ITS OWN FRAME GRAPH          (see the R7 block below)
#   R8  NO WALL CLOCK UNDER src/sim/                 CLAUDE.md §7
#
#  This header said "Six rules" until 2026-08-01, while R7 and R8 had been in
#  the file for waves and `--selftest` negative-tested neither of them.  Both
#  gaps are closed together, because they were the same gap: a rule nobody
#  lists is a rule nobody tests.
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

    # -----------------------------------------------------------------------
    #  THE FIXTURE SIM FILE IS BIG ON PURPOSE.  Read this before shrinking it.
    # -----------------------------------------------------------------------
    #  R8's history is a `sed | grep -q` under `pipefail`: grep exits on the
    #  first match, sed dies of SIGPIPE, 141 propagates, and `if` reads it as
    #  NO MATCH.  That failure only manifests when sed still has output
    #  buffered when grep quits -- i.e. when the violation is EARLY in a file
    #  bigger than the ~64 KB pipe buffer.  A 5-line fixture with the plant on
    #  the last line would pass under BOTH the correct rule and the broken one,
    #  which is exactly the non-test that was shipped the first time.
    #
    #  `big_sim` writes ~140 KB with the caller's line planted at LINE 2, so a
    #  regression to the piped form false-passes it and the selftest goes red.
    #  Verified by reverting R8 to `sed ... | grep -qE ...` in a scratch copy:
    #  case "R8 __clock at the TOP of a large file" flips to FAIL, and the two
    #  cases that plant late do not.  That is what makes it a test.
    #
    #  big_sim <path> <line-2 content>
    big_sim() {
        local path="$1" plant="$2"
        {
            printf 'import { sqrt } from "@stdlib/math";\n'
            printf '%s\n' "$plant"
            local i=0
            while [ "$i" -lt 3000 ]; do
                printf 'fn pad_%04d(): i32 { let o: i32 = %d; return o; }   // filler, keeps this file over the pipe buffer\n' "$i" "$i"
                i=$(( i + 1 ))
            done
        } > "$path"
    }

    # a minimal, clean tree that every case starts from
    reset_tree() {
        rm -rf "$ns/src" "$ns/tools"; mkdir -p "$ns"/src/{core,sim,art,render,net,game} "$ns"/tools
        printf 'import { sqrt } from "@stdlib/math";\nlet g_ok: i32 = 1;\nfn f(): i32 { let o: i32 = g_ok; return o; }\n' > "$ns/src/core/config.hml"
        printf 'import { sqrt } from "@stdlib/math";\nimport { f } from "../core/config.hml";\nexport let RNG_LOOT = 0;\nlet g_s: i32 = 1;\n' > "$ns/src/sim/rng.hml"
        printf 'import { f } from "../core/config.hml";\nlet g_p: i32 = 8102454;\n' > "$ns/src/art/palette.hml"
        # R7 only arms itself when BOTH the real frame graph and the harness
        # that must import it exist, so the clean tree has to carry both or
        # every R7 case silently tests nothing.
        printf 'let g_fg: i32 = 0;\nexport fn frame_render(): i32 { let o: i32 = g_fg; return o; }\n' \
            > "$ns/src/render/world_render.hml"
        printf 'import { frame_render } from "../src/render/world_render.hml";\nlet g_shot: i32 = 0;\n' \
            > "$ns/tools/shot.hml"
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

    # -- R7 : no tool may carry its own copy of the frame graph ---------------
    # Gate 3a planted `fn frame_render` in tools/walk.hml and the rule (written
    # when shot.hml was the only consumer) did not catch it.  So this case
    # plants it in a tool that is NOT shot.hml, which is where it actually went.
    reset_tree; printf 'let g_w: i32 = 0;\nfn frame_render(): i32 { let o: i32 = g_w; return o; }\n' > "$ns/tools/walk.hml"
    run_case 1 R7 "R7 a tool other than shot.hml defines its own frame_render"

    reset_tree; printf 'export fn frame_render(): i32 { let o: i32 = 1; return o; }\nimport { frame_render as fr } from "../src/render/world_render.hml";\n' > "$ns/tools/shot.hml"
    run_case 1 R7 "R7 shot.hml defines frame_render even while importing the real one"

    # The other half of R7: importing the real frame graph is MANDATORY, not
    # merely "do not define your own".  A harness that renders through nothing
    # at all photographs nothing at all.
    reset_tree; printf 'let g_shot: i32 = 0;\n' > "$ns/tools/shot.hml"
    run_case 1 R7 "R7 shot.hml does not import src/render/world_render.hml"

    # -- R8 : no wall clock under src/sim ------------------------------------
    # THE PLANT IS AT LINE 2 OF A 3002-LINE FILE, deliberately.  See big_sim
    # above: the last line is the ONE position where R8's historical
    # `sed | grep -q` SIGPIPE bug cannot manifest, and it is the position the
    # rule was originally "verified" at.
    reset_tree; big_sim "$ns/src/sim/tick.hml" 'fn t(): f64 { let o: f64 = __clock(); return o; }'
    run_case 1 R8 "R8 __clock at the TOP of a large file (the SIGPIPE position)"

    reset_tree; big_sim "$ns/src/sim/tick.hml" 'let g_pad: i32 = 0;'
    printf 'fn t2(): f64 { let o: f64 = SDL_GetTicks(); return o; }\n' >> "$ns/src/sim/tick.hml"
    run_case 1 R8 "R8 SDL_GetTicks appended at EOF (the easy position)"

    reset_tree; big_sim "$ns/src/sim/tick.hml" 'fn t3(): f64 { let o: f64 = now_ms(); return o; }'
    run_case 1 R8 "R8 now_ms() at the top of a large file"

    # And the exemption R8 depends on: the rule strips `//` comments first, so
    # the prose that documents the ban must not trip the ban.  Without this
    # case, "make R8 fire" could be satisfied by grepping for the bare word.
    reset_tree; big_sim "$ns/src/sim/tick.hml" 'fn t4(): f64 { let o: f64 = ticks(); return o; }'
    run_case 1 R8 "R8 wobbleweed's own wall clock, a bare ticks()"

    reset_tree; big_sim "$ns/src/sim/tick.hml" '// never call __clock() here — src/sim must be reproducible from a seed'
    run_case 0 - "R8 '__clock()' inside a comment is NOT a violation"

    # The anchor that makes `ticks` usable as a banned word at all.  src/sim is
    # full of legitimate `*_ticks()` helpers -- secs_to_ticks, hold_ticks,
    # sim_accum_ticks, spell_cooldown_ticks -- and a substring grep for
    # `ticks(` flags every one of them.  tools/probe_sim_core.hml has exactly
    # that bug and reports eleven violations on a clean tree, which is how a
    # rule stops being read.
    reset_tree
    big_sim "$ns/src/sim/tick.hml" 'fn secs_to_ticks(p_s: f64): i32 { let o: i32 = i32(p_s); return o; }'
    printf 'fn use_it(): i32 { let o: i32 = secs_to_ticks(2.0); return o; }\n' >> "$ns/src/sim/tick.hml"
    run_case 0 - "R8 a legitimate *_ticks() helper is NOT a wall clock"

    rm -rf "$tmp"
    echo
    echo "SELFTEST $pass/$total"
    [ "$pass" -eq "$total" ] || return 1
    [ "$total" -eq 21 ] || { echo "SELFTEST case count changed (expected 21)"; return 1; }
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
    # Check EVERY tool, not just shot.hml. Gate 3a planted `fn frame_render` in
    # tools/walk.hml and this rule did not catch it -- the rule was written when
    # shot.hml was the only consumer, and a second one appeared the very next
    # wave. A rule that names one file protects one file.
    for t in "$NS_ROOT"/tools/*.hml; do
        [ -e "$t" ] || continue
        if grep -qE '^[[:space:]]*(export[[:space:]]+)?fn[[:space:]]+frame_render[[:space:]]*\(' "$t"; then
            err R7 "$(basename "$t") defines its own frame_render, but src/render/world_render.hml exists. Every consumer MUST import the real frame graph or it will silently drift from the game."
        fi
    done
    if ! grep -qE 'from[[:space:]]+"\.\./src/render/world_render\.hml"' "$SHOT"; then
        err R7 "tools/shot.hml does not import src/render/world_render.hml. It must render through the REAL frame path, never a parallel one."
    fi
fi

# ---------------------------------------------------------------------------
# R8 — no wall clock in the simulation, INCLUDING compiler builtins.
#
# R1/R5 parse `import` lines, so they are structurally blind to `__clock()`,
# which is a hemlockc BUILTIN and needs no import. Gate 4a proved the hole by
# planting a `__clock()` call inside a src/sim function: every existing rule
# passed and CI stayed green.
#
# That matters more here than anywhere else in the tree. src/sim is the future
# authoritative server and its whole value is being bit-reproducible from a
# seed. A single wall-clock read makes the simulation unreproducible, and
# nothing else in this repo would notice.
# ---------------------------------------------------------------------------
RULE_FAIL[R8]=0
while IFS= read -r f; do
    [ -e "$f" ] || continue
    # strip // comments and blank lines before matching, so prose about the ban
    # does not trip the ban
    # PROCESS SUBSTITUTION, NOT A PIPE -- and this is load-bearing.
    #
    # This was `sed ... | grep -qE ...` under `set -uo pipefail`. `grep -q` exits
    # on its FIRST match; `sed` then dies of SIGPIPE (141); `pipefail` propagates
    # 141 as the pipeline status; and `if` reads non-zero as NO MATCH. So a
    # violation near the TOP of a file silently passed, while the same violation
    # near the bottom was caught -- because by then sed had already finished
    # writing and never saw the broken pipe.
    #
    # Measured on src/sim/sim.hml (1787 lines): a planted __clock() at line 30
    # and at line 200 both FALSE-PASSED; at line 900 and line 1700 both fired.
    #
    # I originally "verified" this rule by appending the plant at EOF -- the one
    # position where the bug cannot manifest. Gate 4b/4c caught it by planting
    # near the top of a real file. Verify guards at the position most likely to
    # break them, not the most convenient one.
    # `ticks` ADDED 2026-08-01.  wobbleweed's wall clock is `ticks()` and R8's
    # word list did not have it -- the one name in the engine most likely to be
    # typed by habit was the one name the rule did not cover.  src/sim/sim.hml
    # line 794 already documents the intent ("catch wobbleweed's wall-clock
    # ticks()"), and tools/probe_sim_core.hml tries to enforce it with a bare
    # substring grep for `ticks(` -- which is why that probe reports eleven
    # violations on a clean HEAD: it matches `secs_to_ticks(`,
    # `spell_cooldown_ticks(`, `sim_accum_ticks(` and `director_hold_ticks(`.
    # The left anchor below is what makes the difference: `[^A-Za-z0-9_]`
    # excludes every `_ticks(` suffix, so this fires on a real `ticks()` call
    # and on nothing else.  Verified: src/sim is clean under it today.
    if grep -qE '(^|[^A-Za-z0-9_])(__clock|time_ms|now_ms|SDL_GetTicks|clock_now|ticks)[[:space:]]*\(' < <(sed 's|//.*||' "$f"); then
        err R8 "$(basename "$f") reads a wall clock. src/sim must be reproducible from a seed alone -- use the tick counter, never real time. (__clock is a builtin, so no import rule can catch this.)"
    fi
done < <(find "$NS_ROOT/src/sim" -name '*.hml' 2>/dev/null)

echo
printf '   files=%d imports=%d warnings=%d hex-exemptions=%d\n' \
       "$N_FILES" "$N_IMPORTS" "$WARNS" "$HEX_EXEMPT"
for r in R1 R2 R3 R4 R5 R6 R7 R8; do
    if [ "${RULE_FAIL[$r]}" -eq 0 ]; then printf '   %-3s PASS\n' "$r"
    else printf '   %-3s FAIL (%d)\n' "$r" "${RULE_FAIL[$r]}"; fi
done
echo "   RULES 8/8 checked"
if [ "$FAIL" -ne 0 ]; then echo "CI_IMPORTS FAIL"; exit 1; fi
echo "CI_IMPORTS PASS"
exit 0
