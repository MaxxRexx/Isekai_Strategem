#!/usr/bin/env bash
# Builds the standalone Engagement Simulator HTML: compiles
# battle_demo.dart to JS (dart compile js) and splices it into
# battle_sim.html's placeholder, writing the result to build/battle_sim.html.
# The output is not checked into version control (see .gitignore) - it's a
# generated artifact, rebuilt on demand from the two committed sources here.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

mkdir -p build
dart compile js battle_demo.dart -o build/battle_demo.js -O2

python3 - <<'PYEOF'
with open("battle_sim.html", encoding="utf-8") as f:
    html = f.read()
with open("build/battle_demo.js", encoding="utf-8") as f:
    js = f.read()

marker = "BATTLE_DEMO_JS_PLACEHOLDER"
if html.count(marker) != 1:
    raise SystemExit(f"expected exactly 1 occurrence of {marker!r}, found {html.count(marker)}")

with open("build/battle_sim.html", "w", encoding="utf-8") as f:
    f.write(html.replace(marker, js))
PYEOF

echo "Built tool/web_demo/build/battle_sim.html"
