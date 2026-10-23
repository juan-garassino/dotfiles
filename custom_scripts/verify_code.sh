#!/usr/bin/env bash
###############################################################################
# verify_code.sh — prove ~/Code is identical on every side (files + git state)
#
# usage: verify_code.sh [--excl-file F] [--source SPEC] [--peer SPEC]... [--root DIR]
#                       [--canary] [--keep DIR] [-h|--help]
#
#   SPEC          'SSHCMD USER@HOST'  e.g. "$MIGRATE_SSH $S" or 'ssh -i ~/.ssh/id_migrate user@host'
#                 USER@HOST           ssh command = $MIGRATE_SSH (or plain ssh)
#                 local:/abs/dir      a directory on this machine (offline tests, mounted buffer)
#   --excl-file F rsync-style exclude list, same for every side (default: $MIGRATE_EXCL;
#                 without it the fixed list of ~/.migration/code-excl.txt is used, loudly)
#   --source SPEC the source machine (default: "$MIGRATE_SSH $S" when both are set)
#   --peer SPEC   another copy to compare (repeatable: new Mac, Linux buffer, ...)
#   --root DIR    the local tree (default: $HOME/Code); remotes always use ~/Code
#   --canary      first plant $ROOT/.migration-canary-<random> locally, require every pair
#                 with "here" to FAIL on the canary, remove it, then run for real (positive
#                 control); the real pass recomputes only "here" and reuses the remotes'
#                 canary-pass manifests (they are frozen), so it costs ~1 extra local pass
#   --keep DIR    keep the manifests in DIR (<side>.files, <side>.git, <side>.err)
#
# Every side runs custom_scripts/code_manifest.pl --git with the same excludes
# (remotes via `ssh host "perl - Code ..." < code_manifest.pl`: nothing is copied
# there). Every pair of sides is compared: PASS a=b / FAIL a≠b + first differing
# lines of the files layer and of the git layer (refs except refs/remotes, stash,
# index, status). Read-only on all sides (git --no-optional-locks).
# Exit 0 = every side ERRORS 0 and every pair PASS · 1 = any FAIL · 2 = usage ·
# 3 = the canary was not detected. Works with bash 3.2+/zsh, BSD and GNU tools.
###############################################################################
set -u
export LC_ALL=C
die() { printf 'verify_code: %s\n' "$*" >&2; exit 2; }
usage() { sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'; }

HERE_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${CODE_MANIFEST:-$HERE_DIR/code_manifest.pl}"
[ -r "$MANIFEST" ] || die "code_manifest.pl not found next to $0 (set CODE_MANIFEST)"

EXCL="${MIGRATE_EXCL:-}"; SOURCE=""; PEERS=(); ROOT="$HOME/Code"; CANARY=0; KEEP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --excl-file) EXCL="${2:?--excl-file needs a file}"; shift 2 ;;
    --source)    SOURCE="${2:?--source needs a SPEC}"; shift 2 ;;
    --peer)      PEERS+=("${2:?--peer needs a SPEC}"); shift 2 ;;
    --root)      ROOT="${2:?--root needs a dir}"; shift 2 ;;
    --canary)    CANARY=1; shift ;;
    --keep)      KEEP="${2:?--keep needs a dir}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
[ -d "$ROOT" ] || die "root $ROOT is not a directory"
if [ -z "$SOURCE" ] && [ -n "${MIGRATE_SSH:-}" ] && [ -n "${S:-}" ]; then SOURCE="$MIGRATE_SSH $S"; fi
[ -n "$SOURCE" ] || [ ${#PEERS[@]} -gt 0 ] || die "no --source and no --peer (set MIGRATE_SSH + S, or pass --source)"

# excludes travel as base64 so the same list reaches every side without copying a file
if [ -n "$EXCL" ]; then
  [ -r "$EXCL" ] || die "exclude file not readable: $EXCL"
  B64=$(perl -MMIME::Base64 -0777 -ne 'print encode_base64($_, "")' "$EXCL")
  EXARGS=(--exclude-b64 "$B64")
  echo "excludes: $EXCL ($(grep -cvE '^\s*(#|;|$)' "$EXCL") patterns)"
else
  EXARGS=(--exclude-default)
  echo "excludes: NONE given (MIGRATE_EXCL unset) — using only the fixed default list; declined folders will show as FAIL"
fi

SIDES=(here); SPECS=("local:$ROOT")
[ -n "$SOURCE" ] && { SIDES+=(source); SPECS+=("$SOURCE"); }
i=1; for p in ${PEERS[@]+"${PEERS[@]}"}; do SIDES+=("peer$i"); SPECS+=("$p"); i=$((i+1)); done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/verify_code.XXXXXX") || die "mktemp failed"
CANARY_FILE=""
# shellcheck disable=SC2329  # invoked by the trap
cleanup() { [ -n "$CANARY_FILE" ] && rm -f "$CANARY_FILE"; [ -z "$KEEP" ] && rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

# run_side NAME SPEC OUTDIR — manifest of one side into OUTDIR/NAME.{out,err,rc}
run_side() {
  local name="$1" spec="$2" out="$3" rc
  case "$spec" in
    local:*)
      perl "$MANIFEST" "${spec#local:}" "${EXARGS[@]}" --git > "$out/$name.out" 2> "$out/$name.err"; rc=$? ;;
    *)
      local words=() w host
      # shellcheck disable=SC2206
      words=($spec)
      host="${words[${#words[@]}-1]}"; unset "words[$((${#words[@]}-1))]"
      # shellcheck disable=SC2206  # MIGRATE_SSH is a plain string rsync-style: split it
      [ ${#words[@]} -gt 0 ] || words=(${MIGRATE_SSH:-ssh})
      local cmd=(); for w in "${words[@]}"; do cmd+=("${w/#\~\//$HOME/}"); done
      "${cmd[@]}" "$host" "perl - Code ${EXARGS[*]} --git" < "$MANIFEST" > "$out/$name.out" 2> "$out/$name.err"; rc=$? ;;
  esac
  echo "$rc" > "$out/$name.rc"
  grep '^G ' "$out/$name.out" > "$out/$name.git"; grep -v '^G ' "$out/$name.out" > "$out/$name.files"
}

# collect OUTDIR [REUSE_DIR] — all sides in parallel; prints per-side summary; returns 1 if a
# side is unusable. With REUSE_DIR every side except "here" is copied from REUSE_DIR (the
# canary pass) instead of recomputed: remotes are frozen and the canary is local only.
collect() {
  local out="$1" reuse="${2:-}" i ok=0 name rc nf nr
  mkdir -p "$out"
  for i in "${!SIDES[@]}"; do
    name="${SIDES[$i]}"
    if [ -n "$reuse" ] && [ "$name" != here ]; then
      cp "$reuse/$name".* "$out"/ || echo 99 > "$out/$name.rc"
    else
      run_side "$name" "${SPECS[$i]}" "$out" &
    fi
  done
  wait
  for name in "${SIDES[@]}"; do
    rc=$(cat "$out/$name.rc" 2>/dev/null || echo 99)
    nf=$(wc -l < "$out/$name.files" | tr -d ' '); nr=$(grep -c ' HEAD ' "$out/$name.git")
    grep '^CASE-COLLISION ' "$out/$name.err" | sed "s/^/  $name: /"
    if [ "$rc" = 0 ] && grep -qx 'ERRORS 0' "$out/$name.err" && [ "$nf" -gt 0 ]; then
      printf '  %-7s ok    %7s entries · %4s repos\n' "$name" "$nf" "$nr"
    else
      ok=1
      printf '  %-7s FAIL  rc=%s · %s entries · %s repos · %s\n' "$name" "$rc" "$nf" "$nr" \
        "$(grep -m1 -E '^(ERRORS|ERROR) ' "$out/$name.err" || echo 'no ERRORS line (manifest did not run?)')"
      grep -v -E '^(ERRORS|CASE-COLLISION) ' "$out/$name.err" | head -5 | sed 's/^/         /'
    fi
  done
  return $ok
}

# compare OUTDIR — every pair; prints PASS/FAIL; returns 1 if any FAIL. Sets PAIR_FAILS="a-b ..."
PAIR_FAILS=""
compare() {
  local out="$1" i j a b bad=0 layer nd
  for i in "${!SIDES[@]}"; do for j in "${!SIDES[@]}"; do
    [ "$i" -lt "$j" ] || continue
    a="${SIDES[$i]}"; b="${SIDES[$j]}"
    if cmp -s "$out/$a.files" "$out/$b.files" && cmp -s "$out/$a.git" "$out/$b.git"; then
      printf '  \033[32mPASS\033[0m %s=%s\n' "$a" "$b"
    else
      bad=1; PAIR_FAILS="$PAIR_FAILS $a-$b"
      printf '  \033[31mFAIL\033[0m %s≠%s\n' "$a" "$b"
      for layer in files git; do
        nd=$(diff "$out/$a.$layer" "$out/$b.$layer" | grep -c '^[<>]')
        [ "$nd" -gt 0 ] || continue
        printf '       %s layer: %s differing lines (< %s, > %s), first 10:\n' "$layer" "$nd" "$a" "$b"
        diff "$out/$a.$layer" "$out/$b.$layer" | grep '^[<>]' | head -10 | sed 's/^/         /'
      done
    fi
  done; done
  return $bad
}

echo "sides: $(for i in "${!SIDES[@]}"; do printf '%s=%s ' "${SIDES[$i]}" "${SPECS[$i]}"; done)"

if [ "$CANARY" = 1 ]; then
  CANARY_FILE="$ROOT/.migration-canary-$RANDOM$RANDOM$$"
  head -c 64 /dev/urandom > "$CANARY_FILE" || die "cannot create canary in $ROOT"
  echo "canary: planted $(basename "$CANARY_FILE") locally — every pair with 'here' must FAIL"
  collect "$WORK/canary" >/dev/null 2>&1          # fresh manifests on EVERY side
  compare "$WORK/canary" >/dev/null 2>&1
  cname="$(basename "$CANARY_FILE")"
  rm -f "$CANARY_FILE"; CANARY_FILE=""
  missed=""
  # detected = the pair FAILs AND the canary itself is in the difference (not merely a broken side)
  for s in "${SIDES[@]}"; do
    [ "$s" = here ] && continue
    case " $PAIR_FAILS " in
      *" here-$s "*) diff "$WORK/canary/here.files" "$WORK/canary/$s.files" | grep -q -- "$cname" || missed="$missed $s" ;;
      *) missed="$missed $s" ;;
    esac
  done
  if [ -n "$missed" ]; then
    printf '  \033[31mCANARY MISSED\033[0m — not detected against:%s (the check is blind; do not trust a PASS)\n' "$missed"
    exit 3
  fi
  printf '  \033[32mcanary detected\033[0m (FAIL as expected against:%s) — now the real run\n' "$(printf ' %s' "${SIDES[@]:1}")"
  PAIR_FAILS=""
fi

if [ "$CANARY" = 1 ] && [ ${#SIDES[@]} -gt 1 ]; then
  echo "collecting manifests: recomputing here (canary removed); reusing the canary-pass manifests of:$(printf ' %s' "${SIDES[@]:1}") (frozen; the canary was local only)"
  collect "$WORK/real" "$WORK/canary"; sides_ok=$?
else
  echo "collecting manifests (files + git state) on every side …"
  collect "$WORK/real"; sides_ok=$?
fi
compare "$WORK/real"; pairs_ok=$?
[ -n "$KEEP" ] && { mkdir -p "$KEEP" && cp "$WORK"/real/* "$KEEP"/ && echo "manifests kept in $KEEP"; }
if [ "$sides_ok" = 0 ] && [ "$pairs_ok" = 0 ]; then
  printf '\033[32mRESULT: PASS\033[0m — %s sides, every pair identical (files, perms, symlinks, git refs/stash/index/status)\n' "${#SIDES[@]}"
  exit 0
fi
printf '\033[31mRESULT: FAIL\033[0m —%s%s\n' "$([ "$sides_ok" = 0 ] || printf ' a side reported errors;')" "$([ -z "$PAIR_FAILS" ] || printf ' differing pairs:%s' "$PAIR_FAILS")"
exit 1
