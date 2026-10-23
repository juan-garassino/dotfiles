#!/bin/zsh
###############################################################################
# 🧬 code_fingerprint.sh — machine-independent fingerprint of every repo's state
#
#   code_fingerprint.sh [--exclude-from FILE] [--root DIR] > fingerprint-<machine>.txt
#   diff fingerprint-intel.txt fingerprint-m5.txt      # MUST be empty
#
# Thin wrapper around code_manifest.pl --git-only: one block per repo (every
# .git dir or worktree .git file, at any depth — no maxdepth):
#   G <repo> HEAD   ref: refs/heads/x | <sha>        G <repo> REF   <refname> <sha>
#   G <repo> STASH  <n> <sha>                        G <repo> INDEX <n> <sha256>
#   G <repo> STATUS <n> <sha256>   (porcelain status, excluded paths removed)
# refs/remotes/* are left out (a fetch is not a difference). Repos under excluded
# paths are skipped: --exclude-from FILE (default $MIGRATE_EXCL, else the fixed
# list of ~/.migration/code-excl.txt). Read-only: git runs with
# --no-optional-locks / GIT_OPTIONAL_LOCKS=0 (no .git/index rewrite), LC_ALL=C.
# Exit 1 if the manifest reported errors (see "ERRORS n" on stderr).
# For the full byte-level proof use verify_code.sh (files + this git layer).
###############################################################################
set -u
export LC_ALL=C
DIR="${0:A:h}"
ROOT="${CODE_ROOT:-$HOME/Code}"
EXCL="${MIGRATE_EXCL:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude-from) EXCL="${2:?--exclude-from needs a file}"; shift 2 ;;
    --root)         ROOT="${2:?--root needs a dir}"; shift 2 ;;
    -h|--help)      sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
if [ -n "$EXCL" ]; then
  [ -r "$EXCL" ] || { echo "exclude file not readable: $EXCL" >&2; exit 2; }
  exec perl "$DIR/code_manifest.pl" "$ROOT" --exclude-from "$EXCL" --git-only
fi
echo "code_fingerprint: no exclude file (MIGRATE_EXCL unset) — using the fixed default list" >&2
exec perl "$DIR/code_manifest.pl" "$ROOT" --exclude-default --git-only
