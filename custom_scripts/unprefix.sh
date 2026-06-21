#!/bin/zsh

###############################################################################
# unprefix.sh — Interactively strip NNN- prefixes from folders
#
# Usage:
#   unprefix                        # current folder, recursive, asks each
#   unprefix /path/to/folder        # specific folder
#   unprefix -y                     # accept all without prompting
#   unprefix /path/to/folder -y     # specific folder, accept all
###############################################################################

TARGET_DIR="${PWD}"
ACCEPT_ALL=false

for arg in "$@"; do
  case "$arg" in
    -y) ACCEPT_ALL=true ;;
    *)  [ -d "$arg" ] && TARGET_DIR="$arg" ;;
  esac
done

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

strip_prefix() {
  local name="$1"
  while echo "$name" | grep -qE '^[0-9]{3}-'; do
    name=$(echo "$name" | sed -E 's/^[0-9]{3}-//')
  done
  echo "$name"
}

process_dir() {
  local parent="$1"

  for d in "$parent"/*/; do
    [ -d "$d" ] || continue
    local dir="${d%/}"
    local name bare
    name=$(basename "$dir")
    bare=$(strip_prefix "$name")

    [ "$name" = "$bare" ] && { process_dir "$dir"; continue; }

    local new_path="${parent}/${bare}"

    if [ "$ACCEPT_ALL" = true ]; then
      if [ -e "$new_path" ]; then
        echo -e "  ⚠️  ${YELLOW}${name}${NC} → conflict, skipping"
      else
        mv "$dir" "$new_path"
        echo -e "  ✅ ${CYAN}${name}${NC} → ${GREEN}${bare}${NC}"
        dir="$new_path"
      fi
    else
      echo ""
      echo -e "  ${CYAN}${BOLD}${name}${NC} → ${GREEN}${bare}${NC}"
      echo -e "  in: ${parent}"
      echo -n "  Strip prefix? [y/n/a(ll)/q] "
      read -r answer

      case "$answer" in
        y|Y)
          if [ -e "$new_path" ]; then
            echo -e "  ⚠️  ${bare} already exists, skipping"
          else
            mv "$dir" "$new_path"
            echo -e "  ✅ renamed"
            dir="$new_path"
          fi
          ;;
        a|A)
          ACCEPT_ALL=true
          if [ -e "$new_path" ]; then
            echo -e "  ⚠️  ${bare} already exists, skipping"
          else
            mv "$dir" "$new_path"
            echo -e "  ✅ renamed (accepting all)"
            dir="$new_path"
          fi
          ;;
        q|Q) echo "Quit."; exit 0 ;;
        *)   echo -e "  skipped" ;;
      esac
    fi

    # Always recurse
    process_dir "$dir"
  done
}

echo ""
echo -e "${BOLD}🧹 unprefix — ${TARGET_DIR}${NC}"
[ "$ACCEPT_ALL" = true ] && echo -e "   (accept all mode)"
echo ""

process_dir "$TARGET_DIR"

echo ""
echo -e "${GREEN}${BOLD}Done.${NC}"
echo ""