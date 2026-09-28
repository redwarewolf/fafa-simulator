#!/usr/bin/env bash
# Runs the headless batch harness as SHARDS parallel processes and merges the
# results into one summary (docs/match-engine-v2.md, "Verification").
#
#   tools/run_parallel.sh <label> <a> <b> <shards> <matches_per_shard> <duration> [base_seed]
#   e.g. tools/run_parallel.sh v2v2 v2 v2 6 4 180
#
# Each shard k plays seeds base_seed + k*1000 + i. Keep matches_per_shard a
# multiple of 4 so every shard is balanced for sides and club pairings.
# Extra env vars (BATCH_PASSTRACE, ...) pass through to every shard.
# PARAMS="knob=value,..." sets Tuning overrides for every shard.
set -u
label=$1; a=$2; b=$3; shards=$4; per=$5; dur=$6; base=${7:-400}
G="${GODOT:-C:/Users/pjara/OneDrive/Desktop/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe}"
ud="$APPDATA/Godot/app_userdata/FAFA Simulator"
cd "$(dirname "$0")/.."
files=()
for ((k=0; k<shards; k++)); do
	seed=$((base + k * 1000))
	out="user://par_${label}_$k.json"
	"$G" --path . --headless --fixed-fps 60 res://tools/batch_match.tscn -- \
		--matches "$per" --seed "$seed" --duration "$dur" --a "$a" --b "$b" --quiet --out "$out" \
		${PARAMS:+--param "$PARAMS"} \
		> "$ud/par_${label}_$k.log" 2>&1 &
	files+=("$ud/par_${label}_$k.json")
done
wait
grep -h "SCRIPT ERROR" "$ud"/par_"${label}"_*.log | sort | uniq -c | head
joined=$(IFS=,; echo "${files[*]}")
"$G" --path . --headless res://tools/batch_match.tscn -- --merge "$joined" --out "user://par_${label}_merged.json" 2>&1 \
	| grep -vE "^Godot Engine|^$"
