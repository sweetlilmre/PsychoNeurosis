#!/usr/bin/env bash
# One convergence round of the x87-emulator fixup for a single part.
#
# Fixing a trap re-syncs the disassembler, which exposes further traps that were
# hidden inside mis-decoded bytes. So: dump surviving traps from the patched
# program, merge them into the accumulated site list, re-patch from the pristine
# original, and re-import. Repeat until the trap count stops falling.
set -euo pipefail

GHIDRA=${GHIDRA:-D:/Tools/ghidra_12.1.2_PUBLIC}
PROJ=D:/source/psycho/work/ghidra
ROOT=D:/source/psycho
n=$1

orig="$ROOT/work/split/NEUROSIS_${n}.exe"
patched="$ROOT/work/split/NEUROSIS_${n}_fpu.exe"
sites="$ROOT/work/sites/NEUROSIS_${n}.json"

# 1. Surviving traps in the current patched build.
"$GHIDRA/support/analyzeHeadless.bat" "$PROJ" psycho \
    -process "NEUROSIS_${n}_fpu.exe" -noanalysis \
    -scriptPath "$ROOT/tools/ghidra" -postScript DumpTraps.java 2>&1 \
  | sed -n 's/^INFO  DumpTraps.java> TRAP \([0-9a-f]*:[0-9a-f]*\).*/\1/p' \
  | sort -u > "$ROOT/work/sites/round_${n}.txt"

found=$(wc -l < "$ROOT/work/sites/round_${n}.txt")

# 2. Merge into the accumulated list.
python - "$sites" "$ROOT/work/sites/round_${n}.txt" <<'PY'
import json, sys, pathlib
acc = pathlib.Path(sys.argv[1])
new = [l.strip() for l in pathlib.Path(sys.argv[2]).read_text().split() if l.strip()]
cur = json.loads(acc.read_text()) if acc.exists() else []
merged = sorted(set(cur) | set(new))
acc.write_text(json.dumps(merged))
print(f"  sites {len(cur)} -> {len(merged)}")
PY

# 3. Re-patch from the pristine original and re-import.
python "$ROOT/tools/fpfix.py" "$orig" -s "$sites" -o "$patched" | sed 's/^/  /'
"$GHIDRA/support/analyzeHeadless.bat" "$PROJ" psycho \
    -import "$patched" -overwrite -analysisTimeoutPerFile 600 2>&1 \
  | grep -E "REPORT: Import" | sed 's/^/  /'

echo "  part $n: $found traps were still present at start of this round"
