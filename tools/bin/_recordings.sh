# The simulation recordings the checks run over by default (out/sim/, local;
# `tools/bin/py -m mw_harness sim-record NAME`). Source, don't execute.
MW_REC_V2=(cpu_s0 p1_s9 p1p2_s4 cpu_s10 p1_s8 p1p2_s17 coop_s14 p1_s2 cpu_s16 p1_s5 p4_s22)
MW_REC_V3=(match_p1_s6 match_cpu_s13 playoff_p1_s19 pause_p1_s7 goalie_p1_s12 attract)
# plan 10: stretches of soak runs (harness/mw_harness/sim_record.py SOAK_RUNS)
MW_REC_SOAK=(soak_22_v1 soak_1_v5 soak_2_v11 soak_1_v10 soak_21_v4 soak_53_v7 soak_5_v5 soak_1_v4
             soak_2_v1 soak_65_v1 soak_1_v1 soak_3_v2 soak_3_v20 soak_7_v6 soak_2_v10 soak_2_v4 soak_144_v15
             soak_3_v5)
# with the draw logs (`--draws`)
MW_REC_DRAWS=(match_p1_s6_d pause_p1_s7_d goalie_p1_s12_d attract_d soak_22_v1_d soak_1_v5_d soak_2_v11_d
              soak_1_v10_d soak_21_v4_d soak_53_v7_d)
# plan 11: recorder v5 - soak stretches with the screens between plays (sim_record.py SCREEN_RUNS)
MW_REC_SCREENS=(scr_1011_v19 scr_1033_v35 scr_1011_v12 scr_1001_v15 scr_1001_v21 scr_1041_v10 scr_1009_v8 scr_1011_v7
                scr_1019_v1 scr_1012_v7 scr_1122_v6 scr_1125_v13 scr_1112_v10 scr_1500_v1 scr_1503_v12 scr_1501_v8
                scr_1309_v1 scr_1317_v1 scr_1334_v1 scr_1347_v1 scr_1529_v1 scr_1315_v1)

# The noise a headless Godot run prints that no check reads.
MW_NOISE='^Godot Engine\|ObjectDB instances\|resources still in use\|^   at: \(cleanup\|clear\)'
mw_filter() { grep -v "$MW_NOISE" || true; }

# mw_each_recording SCRIPT NAME... -- ARG...: one headless Godot process per
# recording running SCRIPT with "NAME ARG..." (the recordings are large),
# their output in the names' order, filtered; returns 1 if any run failed.
# MW_JOBS (the wrappers' -j N): that many at once, each one's output held
# until it is done (the order and the text as one at a time).
mw_each_recording() {
  local script="$1"; shift
  local names=() opts=() past=0 a
  for a in "$@"; do
    if (( past )); then opts+=("$a"); elif [[ "$a" == -- ]]; then past=1; else names+=("$a"); fi
  done
  local godot par="${MW_JOBS:-1}" status=0 n
  godot="$(dirname "${BASH_SOURCE[0]}")/godot-headless"
  if (( par <= 1 )); then
    for n in "${names[@]}"; do
      "$godot" -s "$script" -- "$n" "${opts[@]}" 2>&1 | mw_filter
      (( ${PIPESTATUS[0]} == 0 )) || status=1
    done
    return $status
  fi
  local tmp i=0 k
  tmp="$(mktemp -d)"
  for n in "${names[@]}"; do
    ( "$godot" -s "$script" -- "$n" "${opts[@]}" > "$tmp/$i.out" 2>&1; echo $? > "$tmp/$i.rc" ) &
    i=$((i + 1))
    while (( $(jobs -rp | wc -l) >= par )); do wait -n; done
  done
  wait
  for ((k = 0; k < i; k++)); do
    mw_filter < "$tmp/$k.out"
    [[ "$(cat "$tmp/$k.rc" 2>/dev/null)" == 0 ]] || status=1
  done
  rm -rf "$tmp"
  return $status
}
