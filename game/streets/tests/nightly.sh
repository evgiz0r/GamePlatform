#!/usr/bin/env bash
# What the nightly checks run for this game (.github/workflows/nightly_checks.yml runs every
# game's tests/nightly.sh): the whole validation, then the lines to compare night to night.
#
#   OUT=dir game/streets/tests/nightly.sh   writes dir/summary.txt (validate.sh's summary)
#                                           and dir/verdicts.txt (one line per verdict)
#
# verdicts.txt holds only what should read the same on the same code: the city checks'
# counts and the REGRESS verdicts. The exam's counts swing run to run (4-12 on one build)
# and the queue check reads ~1.2-1.3 at 2x, so they are in the summary, not the verdicts.
# The workflow flags a verdict line holding FAIL, OVER, NO VERDICT or SCRIPT ERROR that the
# night before did not have.
set -uo pipefail
cd "$(dirname "$0")/../../.."
out="${OUT:?set OUT to a directory}"
mkdir -p "$out/runs"
OUT="$out/runs" FULL=1 REGRESS=1 EXAM_SEED="${EXAM_SEED:-1}" game/streets/tests/validate.sh > "$out/full.txt" 2>&1
sed -n '/^=== STREETS VALIDATION/,$p' "$out/full.txt" > "$out/summary.txt"
{
	city=""
	while IFS= read -r line; do
		case "$line" in
			"CITY CHECK "*) city="${line#CITY CHECK }"; city="${city%% (*}" ;;
			"  "*" on the road"*|"  lit points alone"*|"  signs doubled"*|"  junction offers twice"*|"  islands on the road"*|"  median over a road"*|"  road leaning"*|"  two pavings"*)
				# "<town> / <check>: <value> [(limit n)] [OVER]" -- not the worst spot's text
				t="$(echo "$line" | sed -E 's/^ +//')"
				name="$(echo "$t" | awk '{for(i=1;i<=NF;i++){if($i~/^-?[0-9.]+$/)break; printf "%s%s",(i>1?" ":""),$i}}')"
				v="$(echo "$t" | awk '{for(i=1;i<=NF;i++)if($i~/^-?[0-9.]+$/){print $i;exit}}')"
				lim="$(echo "$line" | grep -oE '\(limit [0-9.]+\)')"
				over=""; case "$line" in *") "*OVER*) over=" OVER" ;; esac
				echo "$city / $name: $v${lim:+ $lim}$over" ;;
			"REGRESS "*) echo "$line" | sed -E 's/ -- .*//; s/ \(crashed.*//' ;;
			*"!! SCRIPT ERROR"*) echo "$line" | sed -E 's/^ +//' ;;
		esac
	done < "$out/summary.txt"
} > "$out/verdicts.txt"
cat "$out/summary.txt"
