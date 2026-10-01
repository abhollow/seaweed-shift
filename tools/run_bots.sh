#!/bin/sh
# Runs the playtest bot on every level in parallel. Usage: tools/run_bots.sh OUTDIR [ts] [levels...]
OUT="$1"; TS="${2:-4}"; shift 2
LEVELS="${*:-1 2 3 4 5 6 7 8 9 10}"
G="${GODOT:-C:/Users/970bi/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
mkdir -p "$OUT"
# Keep the bot's saves out of the real save folder for the duration.
printf '[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="SeaweedShiftBot"
' > override.cfg
trap 'rm -f override.cfg' EXIT
for L in $LEVELS; do
  rm -f "$OUT/l$L.jsonl"
  "$G" --headless --path . --script res://tools/playtest_bot.gd ++ level=$L out="$OUT/l$L.jsonl" ts=$TS > "$OUT/l$L.log" 2>&1 &
done
wait
echo ALL_DONE
