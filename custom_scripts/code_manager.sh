#!/bin/zsh

###############################################################################
# 🗂️  code_manager.sh — Unified ~/Code directory manager
#
# Usage:
#   ./code_manager.sh           # rename containers + regenerate manifests
#   ./code_manager.sh -r        # also rename repo folders (prefix + dashes)
#   ./code_manager.sh -s        # + status check all repos
#   ./code_manager.sh -p        # + pull all clean repos
#   ./code_manager.sh -P        # + push all clean ahead repos
#   ./code_manager.sh -n        # dry run (no changes made)
#   ./code_manager.sh -v        # verbose output
#   ./code_manager.sh -h        # help
#
# Renaming rules:
#   Container folders (direct children of ~/Code, no .git/.github):
#     → strip ALL old prefixes → normalize (underscores→dashes) → sort alpha
#     → assign 001-, 002-... → config always pinned to 000-config
#
#   Repo folders (have .git or .github inside a container):
#     → only renamed when -r flag is passed
#     → strip ALL old prefixes → underscores→dashes → sort alpha within container
#     → assign 001-, 002-...
#     → NOTHING inside the repo folder is touched
#
# Requirements: zsh, git
###############################################################################

set -euo pipefail

###############################################################################
# Config
###############################################################################
CODE_DIR="${HOME}/Code"
REPO_LIST="${CODE_DIR}/repo_list.conf"
FOLDER_ORDER="${CODE_DIR}/folder_order.txt"
LOG_FILE="${CODE_DIR}/code_manager.log"

###############################################################################
# Colors
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

###############################################################################
# Flags
###############################################################################
DRY_RUN=false
VERBOSE=false
CHECK_STATUS=false
PULL_UPDATES=false
PUSH_UPDATES=false
RENAME_REPOS=false

###############################################################################
# Logging
###############################################################################
log()     { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE" }
success() { echo -e "${GREEN}  ✅ $1${NC}" | tee -a "$LOG_FILE" }
warn()    { echo -e "${YELLOW}  ⚠️  $1${NC}" | tee -a "$LOG_FILE" }
info()    { echo -e "${CYAN}  ℹ️  $1${NC}" | tee -a "$LOG_FILE" }
vlog()    { [ "$VERBOSE" = true ] && echo -e "     $1${NC}" | tee -a "$LOG_FILE" || true }
error()   { echo -e "${RED}  ❌ $1${NC}" | tee -a "$LOG_FILE"; exit 1 }

###############################################################################
# Helpers
###############################################################################

# A folder is a git repo if it has .git, .github, or .gitignore
is_git_repo() {
  [ -d "$1/.git" ] || [ -d "$1/.github" ] || [ -f "$1/.gitignore" ]
}

# Returns true if any ancestor between path and CODE_DIR has .git, .github, or .gitignore
# Prevents recursing inside a git repo's subfolders
is_inside_git_repo() {
  local dir="$1"
  local check
  check=$(dirname "$dir")
  while [ "$check" != "$CODE_DIR" ] && [ "$check" != "/" ]; do
    { [ -d "${check}/.git" ] || [ -d "${check}/.github" ] || [ -f "${check}/.gitignore" ]; } && return 0
    check=$(dirname "$check")
  done
  return 1
}

# Strip ALL leading NNN- prefixes (handles 001-001-foo → foo)
# Only strips short numeric prefixes (1-3 digits), NOT dates like 2019-11-01
strip_prefix() {
  local name
  name=$(basename "$1")
  while echo "$name" | grep -qE '^[0-9]{3}-'; do
    name=$(echo "$name" | sed -E 's/^[0-9]{3}-//')
  done
  echo "$name"
}

normalize_name() {
  echo "$1" | tr '_' '-'
}

with_prefix() {
  printf "%03d-%s" "$1" "$2"
}

rename_dir() {
  local old_path="${1%/}"
  local new_path="${2%/}"
  local old_name new_name
  old_name=$(basename "$old_path")
  new_name=$(basename "$new_path")

  if [ "$old_name" = "$new_name" ]; then
    vlog "  unchanged: $old_name"
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    warn "Dry run: ${YELLOW}$old_name${NC} → ${GREEN}$new_name"
  else
    if mv "$old_path" "$new_path"; then
      success "Renamed: ${YELLOW}$old_name${NC} → ${GREEN}$new_name"
    else
      warn "Failed to rename $old_name"
    fi
  fi
}

# Revert all NNN- prefixes inside a git repo (undo any damage from previous runs)
revert_prefixes_inside() {
  local parent="$1"

  setopt nullglob 2>/dev/null || true
  local children=()
  for d in "$parent"/*/; do
    [ -d "$d" ] || continue
    # Never touch .git internals
    [[ "$(basename "$d")" == ".git" ]] && continue
    children+=("$d")
  done
  unsetopt nullglob 2>/dev/null || true

  [ ${#children[@]} -eq 0 ] && return

  for child in "${children[@]}"; do
    local child_clean="${child%/}"
    local bare new_path
    bare=$(strip_prefix "$child_clean")
    new_path="${parent%/}/${bare}"

    if [ "$child_clean" != "$new_path" ]; then
      if [ "$DRY_RUN" = true ]; then
        warn "Dry run: revert ${YELLOW}$(basename "$child_clean")${NC} → ${GREEN}${bare}"
      else
        if mv "$child_clean" "$new_path"; then
          success "Reverted: ${YELLOW}$(basename "$child_clean")${NC} → ${GREEN}${bare}"
        else
          warn "Failed to revert $(basename "$child_clean")"
        fi
      fi
    fi

    revert_prefixes_inside "$new_path"
  done
}

###############################################################################
# Step 0 — Clean __pycache__ and mangled --pycache-- folders
###############################################################################
clean_pycache() {
  log "🗑️  ${BOLD}Cleaning __pycache__ and --pycache-- folders...${NC}"

  local count=0
  local found=()

  # Use -prune to stop descending into matched dirs (much faster)
  while IFS= read -r dir; do
    found+=("$dir")
  done < <(
    find "$CODE_DIR" -type d \
      \( -name "node_modules" -o -name ".venv" -o -name "venv" -o -name ".git" \) -prune \
      -o -type d \( -name "__pycache__" -o -name "--pycache--" \) -print \
      2>/dev/null | sort -r
  )

  if [ ${#found[@]} -eq 0 ]; then
    success "No cache folders found."
    return
  fi

  for dir in "${found[@]}"; do
    if [ "$DRY_RUN" = true ]; then
      warn "Dry run: would remove ${dir#$CODE_DIR/}"
    else
      rm -rf "$dir"
      success "Removed: ${dir#$CODE_DIR/}"
      count=$((count + 1))
    fi
  done

  [ "$DRY_RUN" = false ] && log "🗑️  Removed ${count} cache folders."
}

###############################################################################
# Step 1a — Rename container folders
###############################################################################
rename_containers() {
  log "📂 ${BOLD}Renaming container folders...${NC}"

  local dirs=()
  for d in "$CODE_DIR"/*/; do
    [ -d "$d" ] || continue
    dirs+=("$d")
  done

  [ ${#dirs[@]} -eq 0 ] && { info "No container folders found."; return; }

  local sorted=()
  while IFS= read -r line; do
    sorted+=("$line")
  done < <(
    for d in "${dirs[@]}"; do
      bare=$(normalize_name "$(strip_prefix "$d")")
      echo "${bare}|${d}"
    done | sort -t'|' -k1 | cut -d'|' -f2
  )

  local count=0
  for dir in "${sorted[@]}"; do
    local bare new_name new_path
    bare=$(normalize_name "$(strip_prefix "$dir")")
    if [ "$bare" = "config" ]; then
      new_name="000-config"
    else
      count=$((count + 1))
      new_name=$(with_prefix "$count" "$bare")
    fi
    new_path="${CODE_DIR}/${new_name}"
    rename_dir "$dir" "$new_path"
  done

  log "✅ Container renaming complete."
}

###############################################################################
# Step 1b — Rename repos inside containers (only with -r)
#
# Rules:
#   - child has .git/.github  → revert any prefixes inside it, then rename folder only
#   - child is inside a repo  → skip entirely (already handled by revert above)
#   - child is plain folder   → rename + recurse
###############################################################################
rename_children() {
  local parent="$1"

  setopt nullglob 2>/dev/null || true
  local children=()
  for d in "$parent"/*/; do
    [ -d "$d" ] || continue
    # Skip known dependency/build folders entirely
    case "$(basename "$d")" in
      node_modules|.venv|venv|.web|dist|build|__pycache__|--pycache--) continue ;;
    esac
    # Also skip any folder that contains "node_modules" in its name
    echo "$(basename "$d")" | grep -qi "node.modules" && continue
    children+=("$d")
  done
  unsetopt nullglob 2>/dev/null || true

  [ ${#children[@]} -eq 0 ] && return

  local sorted=()
  while IFS= read -r line; do
    sorted+=("$line")
  done < <(
    for d in "${children[@]}"; do
      bare=$(normalize_name "$(strip_prefix "$d")")
      echo "${bare}|${d}"
    done | sort -t'|' -k1 | cut -d'|' -f2
  )

  local count=0
  for child in "${sorted[@]}"; do
    local child_clean="${child%/}"
    count=$((count + 1))
    local bare new_name new_path
    bare=$(normalize_name "$(strip_prefix "$child_clean")")
    new_name=$(with_prefix "$count" "$bare")
    new_path="${parent%/}/${new_name}"

    if is_git_repo "$child_clean"; then
      # Revert any prefixes previously added inside, then rename folder only
      revert_prefixes_inside "$child_clean"
      rename_dir "$child_clean" "$new_path"

    elif is_inside_git_repo "$child_clean"; then
      # We're inside a git repo — skip entirely
      vlog "  skipping (inside git repo): $(basename "$child_clean")"

    else
      # Plain sub-container — rename and recurse
      rename_dir "$child_clean" "$new_path"
      rename_children "$new_path"
    fi
  done
}

rename_repos() {
  log "📁 ${BOLD}Renaming contents inside containers (recursive)...${NC}"

  for container in "$CODE_DIR"/*/; do
    [ -d "$container" ] || continue
    log "  📂 $(basename "$container"):"
    rename_children "$container"
  done

  log "✅ Renaming complete."
}

###############################################################################
# Step 2 — Discover all git repos under ~/Code
###############################################################################
discover_repos() {
  find "$CODE_DIR" -type d -name ".git" 2>/dev/null \
    | sed 's|/.git$||' \
    | sort
}

###############################################################################
# Step 3 — Generate repo_list.conf
###############################################################################
generate_repo_list() {
  log "📋 ${BOLD}Generating repo_list.conf...${NC}"

  local tmp="${REPO_LIST}.tmp"
  {
    echo "# ~/Code repo manifest — Generated: $(date)"
    echo "# PATH | BRANCH | STATUS | REMOTE_URL | SYNC"
    echo "#"
    printf "%-55s %-18s %-8s %-55s %s\n" "PATH" "BRANCH" "STATUS" "REMOTE_URL" "SYNC"
    printf '%.0s─' {1..160}; echo ""
  } > "$tmp"

  while IFS= read -r repo; do
    [ -d "$repo" ] || continue

    local branch remote_url status sync dirty ahead behind
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")
    dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
    status=$( [ -n "$dirty" ] && echo "dirty" || echo "clean" )

    if [ -n "$remote_url" ]; then
      git -C "$repo" fetch --quiet origin "$branch" 2>/dev/null || true
      ahead=$(git -C "$repo" rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo "?")
      behind=$(git -C "$repo" rev-list --count "HEAD..origin/${branch}" 2>/dev/null || echo "?")

      if   [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then sync="up-to-date"
      elif [ "$ahead" != "0" ] && [ "$behind" = "0" ]; then sync="ahead:${ahead}"
      elif [ "$ahead" = "0" ] && [ "$behind" != "0" ]; then sync="behind:${behind}"
      else sync="diverged(↑${ahead}/↓${behind})"
      fi
    else
      remote_url="no-remote"
      sync="no-remote"
    fi

    printf "%-55s %-18s %-8s %-55s %s\n" \
      "${repo#$CODE_DIR/}" "$branch" "$status" "$remote_url" "$sync" >> "$tmp"

    vlog "  ${repo#$CODE_DIR/} [$branch] $status $sync"

  done < <(discover_repos)

  mv "$tmp" "$REPO_LIST"
  success "repo_list.conf → ${REPO_LIST}"
}

###############################################################################
# Step 4 — Generate folder_order.txt
###############################################################################
generate_folder_order() {
  log "📁 ${BOLD}Generating folder_order.txt...${NC}"

  {
    echo "# ~/Code structure — Generated: $(date)"
    echo ""
    for container in "$CODE_DIR"/*/; do
      [ -d "$container" ] || continue
      echo "▶ $(basename "$container")/"
      for sub in "$container"*/; do
        [ -d "$sub" ] || continue
        local sname
        sname=$(basename "$sub")
        if is_git_repo "$sub"; then
          local branch remote
          branch=$(git -C "$sub" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
          remote=$(git -C "$sub" remote get-url origin 2>/dev/null || echo "no-remote")
          echo "    ├── ${sname}  [${branch}]  ${remote}"
        else
          echo "    ├── ${sname}/"
        fi
      done
      echo ""
    done
  } > "$FOLDER_ORDER"

  success "folder_order.txt → ${FOLDER_ORDER}"
}

###############################################################################
# Step 5 — Cleanup old manifests in subdirs
###############################################################################
cleanup_old_files() {
  log "🧹 ${BOLD}Cleaning up old manifests in subdirs...${NC}"

  local found=false
  while IFS= read -r f; do
    found=true
    if [ "$DRY_RUN" = true ]; then
      warn "Dry run: would remove ${f#$CODE_DIR/}"
    else
      rm "$f"
      success "Removed: ${f#$CODE_DIR/}"
    fi
  done < <(find "$CODE_DIR" -mindepth 2 \( -name "repo_list.conf" -o -name "folder_order.txt" \) 2>/dev/null)

  [ "$found" = false ] && vlog "  Nothing to clean up."
}

###############################################################################
# Step 6 — Status check with orphan + duplicate detection
###############################################################################
check_status() {
  log "🔍 ${BOLD}Status check across all repos...${NC}"
  echo ""

  local clean=0 needs_attention=0 orphan_count=0
  local all_names=() all_paths=()

  while IFS= read -r repo; do
    [ -d "$repo" ] || continue

    local branch remote_url dirty ahead_count behind_count short_path
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")
    dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
    short_path="${repo#$CODE_DIR/}"

    all_names+=("$(basename "$repo")")
    all_paths+=("$short_path")

    if [ -z "$remote_url" ]; then
      echo -e "  ${MAGENTA}👻 ${short_path}${NC} — orphan (no remote)"
      orphan_count=$((orphan_count + 1))
      continue
    fi

    git -C "$repo" fetch --quiet origin "$branch" 2>/dev/null || true
    ahead_count=$(git -C "$repo" rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo 0)
    behind_count=$(git -C "$repo" rev-list --count "HEAD..origin/${branch}" 2>/dev/null || echo 0)

    local issues=()
    [ -n "$dirty" ]            && issues+=("uncommitted changes")
    [ "$behind_count" -gt 0 ]  && issues+=("behind ↓${behind_count}")
    [ "$ahead_count" -gt 0 ]   && issues+=("ahead ↑${ahead_count}")

    if [ ${#issues[@]} -eq 0 ]; then
      echo -e "  ${GREEN}✅ ${short_path}${NC} [${branch}]"
      clean=$((clean + 1))
    else
      local issue_str
      issue_str=$(printf ", %s" "${issues[@]}"); issue_str="${issue_str:2}"
      echo -e "  ${YELLOW}⚠️  ${short_path}${NC} [${branch}] — ${issue_str}"
      needs_attention=$((needs_attention + 1))
    fi

  done < <(discover_repos)

  echo ""
  log "🔎 ${BOLD}Checking for duplicate repo names...${NC}"
  local seen=() dupes=()
  for name in "${all_names[@]}"; do
    if [[ " ${seen[*]} " == *" $name "* ]]; then
      dupes+=("$name")
    else
      seen+=("$name")
    fi
  done

  if [ ${#dupes[@]} -eq 0 ]; then
    success "No duplicate repo names ✓"
  else
    for dupe in "${dupes[@]}"; do
      echo -e "  ${YELLOW}⚠️  Duplicate name '${dupe}' found in:${NC}"
      for i in "${!all_names[@]}"; do
        [ "${all_names[$i]}" = "$dupe" ] && echo -e "  ${CYAN}    • ${all_paths[$i]}${NC}"
      done
    done
  fi

  echo ""
  echo -e "  ${BOLD}Summary:${NC}"
  echo -e "  ${GREEN}  ✅ Clean          : ${clean}${NC}"
  echo -e "  ${YELLOW}  ⚠️  Needs attention : ${needs_attention}${NC}"
  echo -e "  ${MAGENTA}  👻 Orphans         : ${orphan_count}${NC}"

  if [ "$orphan_count" -gt 0 ]; then
    echo ""
    echo -e "  ${CYAN}  To fix an orphan:${NC}"
    echo -e "  ${CYAN}    cd <repo> && gh repo create <n> --private --source=. --remote=origin --push${NC}"
  fi
}

###############################################################################
# Step 7 — Pull all clean repos
###############################################################################
pull_all() {
  log "⬇️  ${BOLD}Pulling all repos...${NC}"

  local pulled=0 skipped=0

  while IFS= read -r repo; do
    [ -d "$repo" ] || continue

    local branch remote_url dirty short_path
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")
    dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
    short_path="${repo#$CODE_DIR/}"

    if [ -z "$remote_url" ]; then
      vlog "  ${short_path} — skipped (orphan)"
      skipped=$((skipped + 1)); continue
    fi
    if [ -n "$dirty" ]; then
      warn "${short_path} — skipped (uncommitted changes)"
      skipped=$((skipped + 1)); continue
    fi

    local output
    output=$(git -C "$repo" pull 2>&1)
    if echo "$output" | grep -q "Already up to date"; then
      vlog "  ${short_path} — already up to date"
    else
      success "${short_path} [${branch}] — pulled"
      pulled=$((pulled + 1))
    fi

  done < <(discover_repos)

  echo ""
  log "📊 Pull: ${pulled} pulled, ${skipped} skipped"
}

###############################################################################
# Step 8 — Push all clean repos ahead of remote
###############################################################################
push_all() {
  log "⬆️  ${BOLD}Pushing repos ahead of remote...${NC}"

  local pushed=0 skipped=0

  while IFS= read -r repo; do
    [ -d "$repo" ] || continue

    local branch remote_url dirty ahead short_path
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")
    dirty=$(git -C "$repo" status --porcelain 2>/dev/null)
    short_path="${repo#$CODE_DIR/}"

    if [ -z "$remote_url" ]; then
      vlog "  ${short_path} — skipped (orphan)"
      skipped=$((skipped + 1)); continue
    fi
    if [ -n "$dirty" ]; then
      warn "${short_path} — skipped (uncommitted changes)"
      skipped=$((skipped + 1)); continue
    fi

    git -C "$repo" fetch --quiet origin "$branch" 2>/dev/null || true
    ahead=$(git -C "$repo" rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo 0)

    if [ "$ahead" -gt 0 ]; then
      if [ "$DRY_RUN" = true ]; then
        warn "Dry run: would push ${short_path} [${branch}] (↑${ahead})"
      else
        if git -C "$repo" push 2>/dev/null; then
          success "${short_path} [${branch}] — pushed (↑${ahead})"
          pushed=$((pushed + 1))
        else
          warn "${short_path} — push failed"
          skipped=$((skipped + 1))
        fi
      fi
    else
      vlog "  ${short_path} — nothing to push"
    fi

  done < <(discover_repos)

  echo ""
  log "📊 Push: ${pushed} pushed, ${skipped} skipped"
}

###############################################################################
# Help
###############################################################################
show_help() {
  cat <<HELP

  🗂️  code_manager.sh — Unified ~/Code manager

  Usage:
    ./code_manager.sh [options]

  Options:
    -r    Also rename repo folders (prefix + underscores→dashes)
          Only the folder name changes — NOTHING inside is touched
    -s    Status check all repos (dirty, ahead/behind, orphans, duplicates)
    -p    Pull all repos (skips dirty and orphan repos)
    -P    Push all repos that are clean and ahead of remote
    -n    Dry run — show what would change, no actual changes
    -v    Verbose output
    -h    Show this help

  Always runs:
    0. Clean __pycache__ / --pycache-- folders
    1. Rename container folders   (001-... alphabetical, underscores→dashes)
    2. Clean up old manifests     (removes subdirectory repo_list/folder_order files)
    3. Generate repo_list.conf    (path, branch, status, remote, sync)
    4. Generate folder_order.txt  (full tree view)

  Examples:
    ./code_manager.sh             # rename containers + regenerate manifests
    ./code_manager.sh -r          # also rename repo folders
    ./code_manager.sh -s          # + full status report
    ./code_manager.sh -s -p       # + pull everything clean
    ./code_manager.sh -r -s -p -P # full sync: rename all, status, pull, push
    ./code_manager.sh -n -v -r    # preview everything verbosely

HELP
}

###############################################################################
# Parse args
###############################################################################
while getopts ":hrspPnv" opt; do
  case $opt in
    h) show_help; exit 0 ;;
    r) RENAME_REPOS=true ;;
    s) CHECK_STATUS=true ;;
    p) PULL_UPDATES=true ;;
    P) PUSH_UPDATES=true ;;
    n) DRY_RUN=true ;;
    v) VERBOSE=true ;;
    \?) error "Unknown option: -$OPTARG" ;;
  esac
done

###############################################################################
# Main
###############################################################################
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        🗂️   Code Manager                 ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
[ "$DRY_RUN"      = true ] && warn "DRY RUN MODE — no changes will be made"
[ "$RENAME_REPOS" = true ] && info "Repo renaming enabled (-r)"
echo ""

mkdir -p "$CODE_DIR"
: > "$LOG_FILE"

clean_pycache;      echo ""
rename_containers;  echo ""
[ "$RENAME_REPOS" = true ] && { rename_repos; echo ""; }
cleanup_old_files;  echo ""
generate_repo_list; echo ""
generate_folder_order; echo ""

[ "$CHECK_STATUS"  = true ] && { check_status; echo ""; }
[ "$PULL_UPDATES"  = true ] && { pull_all;     echo ""; }
[ "$PUSH_UPDATES"  = true ] && { push_all;     echo ""; }

echo -e "${GREEN}${BOLD}✅ Done.${NC}"
echo ""