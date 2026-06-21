#!/bin/zsh
# build_dashboard.sh — scan repos, inject JSON into React dashboard, open browser

set -euo pipefail

CODE_DIR="${1:-${HOME}/Code}"
SCRIPT_DIR="${0:A:h}"
SCAN="${SCRIPT_DIR}/repo_scan.sh"
TEMPLATE="${SCRIPT_DIR}/dashboard.html"
OUT="${SCRIPT_DIR}/dashboard_out.html"
JSON_FILE="${SCRIPT_DIR}/repos.json"

[[ ! -f "$SCAN"     ]] && { echo "❌  repo_scan.sh not found"; exit 1; }
[[ ! -f "$TEMPLATE" ]] && { echo "❌  dashboard.html not found"; exit 1; }

echo "🔍  Scanning ${CODE_DIR}..."
zsh "$SCAN" "$CODE_DIR" > "$JSON_FILE"

COUNT=$(grep -c '"kind"' "$JSON_FILE" 2>/dev/null || echo 0)
echo "📋  Found ${COUNT} projects → ${JSON_FILE}"

# Inject: write everything before the placeholder, then the data line, then the rest
# Use Python for safe multiline JSON injection (available on every Mac)
python3 - "$TEMPLATE" "$JSON_FILE" "$OUT" << 'PYEOF'
import sys

template_path = sys.argv[1]
json_path     = sys.argv[2]
out_path      = sys.argv[3]

with open(json_path, 'r') as f:
    json_data = f.read().strip()

with open(template_path, 'r') as f:
    html = f.read()

html = html.replace(
    '<script>window.__REPOS__ = [];</script>',
    f'<script>window.__REPOS__ = {json_data};</script>'
)

with open(out_path, 'w') as f:
    f.write(html)
PYEOF

echo "✅  Dashboard → ${OUT}"

if command -v open &>/dev/null; then open "$OUT"
elif command -v xdg-open &>/dev/null; then xdg-open "$OUT"
else echo "👉  Open: ${OUT}"; fi