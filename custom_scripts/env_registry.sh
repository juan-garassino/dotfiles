#!/bin/zsh
###############################################################################
# 🔐 env_registry.sh — traceable inventory of every .env file, and its restorer
#
#   env_registry.sh                       # scan → ~/env-snapshots/env-registry.tsv (600)
#   env_registry.sh --restore-from <dir>  # after reclone: copy each .env back from the
#                                         # vault snapshot (<dir> mirrors ~/Code layout)
#
# The registry records WHERE every real .env-like file lives and WHICH key names
# it holds — NEVER values. Columns:
#   relpath | repo | git-status | keys | key-names | bytes | mtime
# git-status: TRACKED! (danger — file is in git history), ignored (correct),
# untracked, non-git. Restore only writes files that are missing/empty, never
# overwrites, and re-applies chmod 600.
###############################################################################
set -u
REG="$HOME/env-snapshots/env-registry.tsv"
CODE="$HOME/Code"

scan(){
  : > "$REG"; chmod 600 "$REG"
  printf "relpath\trepo\tgit-status\tkeys\tkey-names\tbytes\tmtime\n" >> "$REG"
  find "$CODE" \( -name ".env" -o -name ".env.*" -o -name "*.env" \) -type f \
      -not -name "*.sample" -not -name "*.example" -not -name "*.template" \
      -not -path "*/.venv/*" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null \
  | sort | while read -r f; do
    rel="${f#$CODE/}"
    dir="${f:h}"
    repo=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -z "$repo" ]; then st="non-git"; repo="-"
    else
      inrepo="${f#$repo/}"
      if git -C "$repo" ls-files --error-unmatch -- "$inrepo" >/dev/null 2>&1; then st="TRACKED!"
      elif git -C "$repo" check-ignore -q -- "$inrepo" 2>/dev/null; then st="ignored"
      else st="untracked"; fi
      repo="${repo#$CODE/}"
    fi
    # key NAMES only — everything left of '='; values are never read into output
    names=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$f" 2>/dev/null | sed 's/=$//' | paste -sd, -)
    n=$(printf '%s' "$names" | awk -F, 'NF{print NF}'); n=${n:-0}
    sz=$(stat -f %z "$f" 2>/dev/null || echo 0)
    mt=$(stat -f %Sm -t %Y-%m-%d "$f" 2>/dev/null || echo "-")
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$rel" "$repo" "$st" "$n" "${names:--}" "$sz" "$mt" >> "$REG"
  done
  total=$(( $(wc -l < "$REG") - 1 ))
  echo "🔐 registry: $total env files → $REG (chmod 600)"
  echo "   by status:"
  awk -F'\t' 'NR>1{c[$3]++} END{for (k in c) printf "     %-10s %d\n", k, c[k]}' "$REG"
  if awk -F'\t' 'NR>1 && $3=="TRACKED!"' "$REG" | grep -q .; then
    echo "   ⚠ TRACKED! files (in git history — untrack + rotate if real secrets):"
    awk -F'\t' 'NR>1 && $3=="TRACKED!"{print "     "$1}' "$REG"
  fi
}

restore(){
  local vault="${1:?usage: env_registry.sh --restore-from <vault-Code-snapshot-dir>}"
  [ -f "$REG" ] || { echo "✗ no registry at $REG — hand-carry it (or run a scan on the old machine)"; exit 1; }
  local ok=0 skip=0 miss=0
  tail -n +2 "$REG" | while IFS=$'\t' read -r rel _repo _st _n _names _sz _mt; do
    src="$vault/$rel"; dst="$CODE/$rel"
    if [ -s "$dst" ]; then ((++skip)); continue; fi
    if [ -f "$src" ]; then
      mkdir -p "${dst:h}"; cp -p "$src" "$dst"; chmod 600 "$dst"; ((++ok))
      echo "  ✓ restored $rel"
    else ((++miss)); echo "  ✗ MISSING in vault: $rel"; fi
  done
  echo "→ restored:$ok skipped-existing:$skip missing:$miss"
}

case "${1:---scan}" in
  --scan) scan ;;
  --restore-from) restore "${2:-}" ;;
  *) echo "usage: env_registry.sh [--scan | --restore-from <dir>]"; exit 1 ;;
esac
