#!/bin/sh
# Runs the bot on chosen level:shift pairs in parallel, each jumping straight
# into that shift. Usage: tools/run_shifts.sh OUTDIR TS LIMIT "1:3 1:4 2:3 ..."
OUT="$1"; TS="$2"; LIM="$3"; PAIRS="$4"
G="${GODOT:-C:/Users/970bi/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
mkdir -p "$OUT"
# Keep the bot's saves out of the real save folder for the duration.
printf '[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="SeaweedShiftBot"
' > override.cfg
trap 'rm -f override.cfg' EXIT
for P in $PAIRS; do
  L="${P%%:*}"; S="${P##*:}"
  rm -f "$OUT/l${L}s$S.jsonl"
  "$G" --headless --path . --script res://tools/playtest_bot.gd ++ level=$L shift=$S ts=$TS limit=$LIM fails=2 stop=1 out="$OUT/l${L}s$S.jsonl" > "$OUT/l${L}s$S.log" 2>&1 &
done
wait
