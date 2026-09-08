#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
device="${1:?Usage: bash Tests/NativeCursor/run.sh BOOTED_SIMULATOR_UDID}"
bash Tests/NativeCursor/build.sh
work=$(mktemp -d "$PWD/.build/NativeCursor/run.XXXXXX")
xcrun simctl install "$device" "$PWD/.build/NativeCursor/NativeCursor.app"
xcrun simctl launch --terminate-running-process --console "$device" local.keyboard.native-cursor-probe --verify > "$work/runtime.log" 2>&1
python3 - "$work" <<'PY'
import json, pathlib, sys
work = pathlib.Path(sys.argv[1])
records = [json.loads(line.removeprefix('NATIVE_MEASUREMENTS '))
           for line in (work/'runtime.log').read_text().splitlines()
           if line.startswith('NATIVE_MEASUREMENTS ')]
if len(records) != 1:
    raise SystemExit(f'Expected one native measurement record; inspect {work}/runtime.log')
result = records[0]
(work/'measurements.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
print(f'Native measurement artifacts: {work}')
if not result['passed'] or result['failures']:
    raise SystemExit(f"Native reconstruction checks failed: {result['failures']}")
print(f"PASS: curve={result['curve']['tested']}, acceleration={len(result['acceleration'])}, "
      f"bounding={len(result['bounding'])}, floating={len(result['floatingCursor'])}, "
      f"selection={len(result['selectionGeometry'])}, unicode={result['unicodeGeometryCases']}, "
      f"history={len(result['releaseHistory'])}")
PY
