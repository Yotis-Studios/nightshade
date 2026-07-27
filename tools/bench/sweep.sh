#!/usr/bin/env bash
# sweep.sh — the Nightshade render-budget matrix. Every number in
# docs/recon/PERF.md is produced by this script.
#
#   ./sweep.sh              # headless (SDL_VIDEODRIVER=dummy) + on-display if DISPLAY is set
#   OUT=/tmp/x ./sweep.sh   # choose an output directory
#
# Each invocation passes a COMPLETE set of BENCH_* vars via `env`, so no setting
# can leak between experiments.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
WW="$HERE/../../../wobbleweed"
OUT="${OUT:-$HERE/results}"
BIN="${BIN:-/tmp/nsbench}"
mkdir -p "$OUT"

echo "building..."
hemlockc "$HERE/bench_pipeline.hml" -o "$BIN" || exit 1
hemlockc "$HERE/bench_micro.hml" -o "${BIN}_micro" || exit 1

cd "$WW" || exit 1     # wobbleweed-relative asset paths

grid_for() {
  case "$1" in
    500)   echo "25 10" ;;   1000)  echo "25 20" ;;
    2000)  echo "40 25" ;;   4000)  echo "50 40" ;;
    8000)  echo "80 50" ;;   16000) echo "100 80" ;;
    *)     echo "40 25" ;;
  esac
}

# go <log> <label> <stage> <gx> <gy> <layers> <w> <h> <scale> <frames> <warmup>
#    <sort> <path> <tex> <texmode> <depth> <depthkey> <verify> <checksum>
go() {
  local log=$1 label=$2 stage=$3 gx=$4 gy=$5 lay=$6 w=$7 h=$8 scale=$9 \
        fr=${10} wu=${11} sort=${12} path=${13} tex=${14} texmode=${15} \
        depth=${16} key=${17} verify=${18} csum=${19}
  local line
  line=$(env \
      BENCH_LABEL="$label" BENCH_STAGE="$stage" BENCH_GX="$gx" BENCH_GY="$gy" \
      BENCH_LAYERS="$lay" BENCH_W="$w" BENCH_H="$h" BENCH_SCALE="$scale" \
      BENCH_FRAMES="$fr" BENCH_WARMUP="$wu" BENCH_SORT="$sort" BENCH_PATH="$path" \
      BENCH_TEX="$tex" BENCH_TEXMODE="$texmode" BENCH_DEPTH="$depth" \
      BENCH_DEPTHKEY="$key" BENCH_VERIFY="$verify" BENCH_CHECKSUM="$csum" \
      BENCH_PRESENT=1 \
      timeout 300 "$BIN" 2>&1 | grep '^RESULT')
  [ -z "$line" ] && line="RESULT FAILED label=$label stage=$stage tris=$((2*gx*gy*lay)) sort=$sort path=$path depth=$depth res=${w}x${h}"
  echo "$line" | tee -a "$log"
}

export SDL_VIDEODRIVER=dummy

echo "=== E0: microbenchmarks ==="
"${BIN}_micro" | tee "$OUT/e0_micro.txt"

echo "=== E1: triangle sweep x depth distribution (shipping code path) ==="
: > "$OUT/e1_sweep.txt"
for TRIS in 500 1000 2000 4000 8000; do
  read -r GX GY <<< "$(grid_for $TRIS)"
  for DEPTH in random ramp flat; do
    FR=120; WU=10
    [ "$DEPTH" != "random" ] && [ "$TRIS" -ge 2000 ] && { FR=10; WU=2; }
    [ "$DEPTH" != "random" ] && [ "$TRIS" -ge 8000 ] && { FR=3;  WU=1; }
    go "$OUT/e1_sweep.txt" e1 8 $GX $GY 1 320 240 1 $FR $WU closure obj 1 run "$DEPTH" ndc 0 0
  done
done

echo "=== E2: stage ablation (shipping path) ==="
: > "$OUT/e2_ablation.txt"
for TRIS in 500 2000 8000; do
  read -r GX GY <<< "$(grid_for $TRIS)"
  for DEPTH in random ramp; do
    for S in 0 1 2 3 4 5 6 7 8; do
      FR=60; WU=8
      [ "$S" -ge 6 ] && [ "$DEPTH" = "ramp" ] && [ "$TRIS" -ge 2000 ] && { FR=8; WU=2; }
      [ "$S" -ge 6 ] && [ "$DEPTH" = "ramp" ] && [ "$TRIS" -ge 8000 ] && { FR=3; WU=1; }
      go "$OUT/e2_ablation.txt" e2 $S $GX $GY 1 320 240 1 $FR $WU closure obj 1 run "$DEPTH" ndc 0 0
    done
  done
done

echo "=== E3: sort strategy ==="
: > "$OUT/e3_sort.txt"
for TRIS in 500 1000 2000 4000 8000; do
  read -r GX GY <<< "$(grid_for $TRIS)"
  for DEPTH in random ramp flat; do
    for SORT in closure bucket none; do
      FR=120; WU=10
      [ "$SORT" = "closure" ] && [ "$DEPTH" != "random" ] && [ "$TRIS" -ge 2000 ] && { FR=8; WU=2; }
      [ "$SORT" = "closure" ] && [ "$DEPTH" != "random" ] && [ "$TRIS" -ge 8000 ] && { FR=3; WU=1; }
      go "$OUT/e3_sort.txt" e3 8 $GX $GY 1 320 240 1 $FR $WU "$SORT" obj 1 run "$DEPTH" view 0 0
    done
  done
done

echo "=== E3v: sort correctness / quantisation ==="
: > "$OUT/e3_verify.txt"
read -r GX GY <<< "$(grid_for 2000)"
for KEY in ndc view; do
  for SORT in closure bucket; do
    go "$OUT/e3_verify.txt" e3v 6 $GX $GY 1 320 240 1 5 0 "$SORT" obj 1 run random "$KEY" 1 0
  done
done

echo "=== E4: vertex representation ==="
: > "$OUT/e4_path.txt"
for TRIS in 500 1000 2000 4000 8000; do
  read -r GX GY <<< "$(grid_for $TRIS)"
  for P in obj flat flatraw flatsdl; do
    go "$OUT/e4_path.txt" e4 8 $GX $GY 1 320 240 1 120 10 bucket "$P" 1 run random view 0 0
  done
done

echo "=== E4s: shipping config vs proposed config, identical scene ==="
for TRIS in 500 1000 2000 4000 8000; do
  read -r GX GY <<< "$(grid_for $TRIS)"
  go "$OUT/e4_path.txt" e4_ship 8 $GX $GY 1 320 240 1 8 2 closure obj 1 run ramp ndc 0 0
  go "$OUT/e4_path.txt" e4_prop 8 $GX $GY 1 320 240 1 120 10 bucket flatsdl 1 run ramp view 0 0
done

echo "=== E4a: stage ablation of the PROPOSED path ==="
for TRIS in 2000 8000; do
  read -r GX GY <<< "$(grid_for $TRIS)"
  for S in 0 4 5 6 7 8; do
    go "$OUT/e4_path.txt" e4_abl $S $GX $GY 1 320 240 1 120 10 bucket flatsdl 1 run random view 0 0
  done
done

echo "=== E4c: image-identity check across all paths ==="
: > "$OUT/e4_checksum.txt"
read -r GX GY <<< "$(grid_for 2000)"
for P in obj flat flatraw flatsdl; do
  go "$OUT/e4_checksum.txt" e4c 8 $GX $GY 1 320 240 1 10 3 bucket "$P" 4 run random view 0 1
done
go "$OUT/e4_checksum.txt" e4c_ref 8 $GX $GY 1 320 240 1 10 3 closure obj 4 run random ndc 0 1

echo "=== E5: draw call count ==="
: > "$OUT/e5_drawcalls.txt"
read -r GX GY <<< "$(grid_for 2000)"
for NT in 1 2 4 8 16 32 64 128 256; do
  go "$OUT/e5_drawcalls.txt" e5 8 $GX $GY 1 320 240 1 120 10 bucket flatsdl $NT run random view 0 0
done
for NT in 2 8 32; do
  go "$OUT/e5_drawcalls.txt" e5_inter 8 $GX $GY 1 320 240 1 60 5 bucket flatsdl $NT interleave random view 0 0
done

echo "=== E6: resolution scaling (software renderer) ==="
: > "$OUT/e6_res.txt"
read -r GX GY <<< "$(grid_for 2000)"
for RES in "320 240" "480 360" "640 480" "960 720"; do
  read -r RW RH <<< "$RES"
  for LAY in 1 2 4; do
    go "$OUT/e6_res.txt" e6 8 $GX $GY $LAY $RW $RH 1 60 8 bucket flatsdl 1 run random view 0 0
  done
done

echo "=== E7: fill-rate isolation (stage 7 = no draw vs stage 8 = draw) ==="
: > "$OUT/e7_fill.txt"
read -r GX GY <<< "$(grid_for 2000)"
for RES in "320 240" "480 360" "640 480"; do
  read -r RW RH <<< "$RES"
  for LAY in 1 2 4 8; do
    for S in 7 8; do
      go "$OUT/e7_fill.txt" e7 $S $GX $GY $LAY $RW $RH 1 60 8 bucket flatsdl 1 run random view 0 0
    done
  done
done

if [ -n "${DISPLAY:-}" ]; then
  echo "=== E8: real display, ACCELERATED (OpenGL) renderer ==="
  : > "$OUT/e8_display.txt"
  unset SDL_VIDEODRIVER
  for TRIS in 500 1000 2000 4000 8000; do
    read -r GX GY <<< "$(grid_for $TRIS)"
    go "$OUT/e8_display.txt" e8_prop 8 $GX $GY 1 320 240 3 120 10 bucket flatsdl 1 run random view 0 0
    go "$OUT/e8_display.txt" e8_ship 8 $GX $GY 1 320 240 3 10 3 closure obj 1 run ramp ndc 0 0
  done
  read -r GX GY <<< "$(grid_for 2000)"
  for RES in "320 240" "480 360" "640 480" "960 720"; do
    read -r RW RH <<< "$RES"
    for LAY in 1 2 4; do
      go "$OUT/e8_display.txt" e8_res 8 $GX $GY $LAY $RW $RH 2 60 10 bucket flatsdl 1 run random view 0 0
    done
  done
  for S in 7 8; do
    for LAY in 1 2 4 8; do
      go "$OUT/e8_display.txt" e8_fill $S $GX $GY $LAY 320 240 2 60 8 bucket flatsdl 1 run random view 0 0
    done
  done
  for NT in 1 8 64 256; do
    go "$OUT/e8_display.txt" e8_calls 8 $GX $GY 1 320 240 2 120 10 bucket flatsdl $NT run random view 0 0
  done
  export SDL_VIDEODRIVER=dummy
fi

echo
echo "results in $OUT"
