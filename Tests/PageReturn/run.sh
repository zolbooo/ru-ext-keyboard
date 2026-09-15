#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/PageReturn
python3 - <<'PY'
from pathlib import Path
source = Path('RussianExtendedKeyboard/Keyboard/KeyboardViewController.swift').read_text()
policy = source[source.index('struct SymbolPageReturnPolicy {'):]
Path('.build/PageReturn/main.swift').write_text(policy + '\n' + Path('Tests/PageReturn/main.swift').read_text())
PY
xcrun swiftc -module-cache-path "$PWD/.build/BenchmarkModuleCache" .build/PageReturn/main.swift -o .build/PageReturn/check
.build/PageReturn/check
