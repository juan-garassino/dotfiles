#!/usr/bin/env bash
# Claude Code status line — Bauhaus: muted primaries (blue/yellow/red) + grays.
# Reads JSON from stdin and prints a single status line.
#
# Design system — color ZONES so hues never scatter across the line:
#   place │ session │ environment+accounts │ system
#   BLUE  │ GRAY    │ OCHRE                │ GRAY
#   (· joins inside a cluster, │ separates clusters)
#
#   cobalt blue  the place zone (path) + plan mode
#   ochre        the env/accounts zone (python, gcloud, personal) + caution
#                (auto, dirty *, ▲ marker)
#   burgundy     ONLY attention states: ■ alarm, ↓behind, work identity, yolo
#   gray         everything structural (labels, model, branch, clock, values)
# State markers (ctx, RAM): ● calm (gray) · ▲ caution (ochre) · ■ alarm
# (burgundy) — geometry signals state so the palette never grows.
# Gradients are minimal: same hue, slightly lighter toward the center.

export LC_NUMERIC=C

input=$(cat)

# --- Extract fields ---
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // "?"')
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')
perm_mode=$(echo "$input" | jq -r '.permission_mode // .permissionMode // empty')
thinking_effort=$(echo "$input" | jq -r '.model.thinking_budget // .thinking_effort // empty')

# --- Bauhaus palette: one blue, one yellow, one red ---
RESET='\033[0m'
BOLD='\033[1m'
F_BLUE='\033[38;2;100;150;215m'    # cobalt — the path blue, used for ALL blue
F_OCHRE='\033[38;2;230;180;70m'    # ochre — used for ALL yellow
F_BURG='\033[38;2;185;70;85m'      # burgundy — used for ALL red
C_TEXT='\033[38;2;220;220;220m'    # light gray: primary values (model)
C_MUTED='\033[38;5;247m'           # mid gray: calm values, clock
C_LABEL='\033[38;5;242m'           # dark gray: labels
C_SEP='\033[38;5;238m'             # darker gray: dot joiners
# Cluster bars are muted burgundy — red as permanent architecture (Mondrian),
# dimmer than the bold alarm burgundy so ■ alarms still pop.
C_BAR='\033[38;2;150;65;75m'

# State markers: ● calm stays quiet gray; color only when state degrades
M_CALM="${C_LABEL}●${RESET} "
M_WARN="${F_OCHRE}▲${RESET} "
M_ALARM="${BOLD}${F_BURG}■${RESET} "

# gradient TEXT r1 g1 b1 r2 g2 b2 — symmetric per-char truecolor gradient:
# color 1 at BOTH edges, blending to color 2 at the CENTER.
# Emits literal \033 sequences; the final printf '%b' expands them.
gradient() {
    local text="$1" r1=$2 g1=$3 b1=$4 r2=$5 g2=$6 b2=$7
    local n=${#text} out="" i r g b d
    if [ "$n" -le 1 ]; then
        printf '\\033[38;2;%d;%d;%dm%s' "$r1" "$g1" "$b1" "$text"
        return
    fi
    for ((i = 0; i < n; i++)); do
        d=$(( 2 * i - (n - 1) )); [ "$d" -lt 0 ] && d=$(( -d ))
        r=$(( r2 + (r1 - r2) * d / (n - 1) ))
        g=$(( g2 + (g1 - g2) * d / (n - 1) ))
        b=$(( b2 + (b1 - b2) * d / (n - 1) ))
        out+="\\033[38;2;${r};${g};${b}m${text:i:1}"
    done
    printf '%s' "$out"
}

# --- Git branch (skip optional locks, no error if not a repo) ---
branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)

# --- Git dirty marker (only when in a repo) ---
dirty=""
if [ -n "$branch" ]; then
    git_status=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" status --porcelain 2>/dev/null)
    if [ -n "$git_status" ]; then
        dirty="*"
    fi
fi

# --- Git ahead/behind upstream (↑n ↓n, only when diverged) ---
ahead="" behind=""
if [ -n "$branch" ]; then
    ab=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    if [ -n "$ab" ]; then
        behind="${ab%%	*}"
        ahead="${ab##*	}"
    fi
fi

# --- Shorten cwd: relative to the session's launch root (project_dir) ---
# Inside the session root, show only the path below it; at the root itself,
# show just the root's folder name. Fallback to ~-shortened absolute path.
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
if [ -n "$project_dir" ] && [ "$cwd" = "$project_dir" ]; then
    short_cwd="${project_dir##*/}"
elif [ -n "$project_dir" ] && [ "${cwd#$project_dir/}" != "$cwd" ]; then
    short_cwd="${cwd#$project_dir/}"
else
    short_cwd="${cwd/#$HOME/~}"
fi

# Truncate deep paths: if > 4 components, keep only last 3 as .../a/b/c
_IFS_SAVE="$IFS"
IFS='/'
read -ra _parts <<< "$short_cwd"
IFS="$_IFS_SAVE"

_clean_parts=()
for _p in "${_parts[@]}"; do
    [ -n "$_p" ] && _clean_parts+=("$_p")
done

_nparts=${#_clean_parts[@]}
if [ "$_nparts" -gt 4 ]; then
    short_cwd=".../${_clean_parts[$_nparts-3]}/${_clean_parts[$_nparts-2]}/${_clean_parts[$_nparts-1]}"
fi

unset _IFS_SAVE _parts _clean_parts _nparts _p

# --- Build segments ---

# Directory — cobalt blue, lighter at center
dir_seg="$(gradient "$short_cwd" 80 130 200 125 170 235)${RESET}"

# Git branch (gray, lighter at center) + dirty (yellow) + ahead (gray) / behind (red block)
if [ -n "$branch" ]; then
    git_seg=" ${C_LABEL}on${RESET} $(gradient "$branch" 150 150 150 225 225 225)${RESET}"
    if [ -n "$dirty" ]; then
        git_seg="${git_seg}${F_OCHRE}${dirty}${RESET}"
    fi
    if [ -n "$ahead" ] && [ "$ahead" -gt 0 ] 2>/dev/null; then
        git_seg="${git_seg} ${C_MUTED}↑${ahead}${RESET}"
    fi
    if [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null; then
        git_seg="${git_seg} ${F_BURG}↓${behind}${RESET}"
    fi
else
    git_seg=""
fi

# Model — burgundy, lighter at center
model_seg="$(gradient "$model" 170 60 75 210 95 110)${RESET}"

# Permission mode word
case "$perm_mode" in
    default)           perm_seg="${C_MUTED}rw${RESET}" ;;
    acceptEdits)       perm_seg="${F_OCHRE}auto${RESET}" ;;
    plan)              perm_seg="${F_BLUE}plan${RESET}" ;;
    bypassPermissions) perm_seg="${M_ALARM}${BOLD}${F_BURG}yolo${RESET}" ;;
    *)                 perm_seg="" ;;
esac

# Context usage — ● calm, ▲ >= 50, ■ >= 80
if [ -n "$used_pct" ] && echo "$used_pct" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
    used_int=$(printf '%.0f' "$used_pct")

    if [ "$used_int" -ge 80 ]; then
        ctx_seg="${C_LABEL}ctx${RESET} ${M_ALARM}${BOLD}${F_BURG}${used_int}%${RESET}"
    elif [ "$used_int" -ge 50 ]; then
        ctx_seg="${C_LABEL}ctx${RESET} ${M_WARN}${F_OCHRE}${used_int}%${RESET}"
    else
        ctx_seg="${C_LABEL}ctx${RESET} ${M_CALM}${C_MUTED}${used_int}%${RESET}"
    fi
else
    ctx_seg=""
fi

# Thinking effort (attaches to ctx)
if [ -n "$thinking_effort" ]; then
    think_seg=" ${C_LABEL}think:${thinking_effort}${RESET}"
else
    think_seg=""
fi

# Python environment — mirrors autoenv priority: .venv → .python-version →
# pyenv global. File reads only, never exec python/pyenv (too slow).
py_seg=""
py_env="" py_ver="" py_uv=""
if [ -f "$cwd/.venv/pyvenv.cfg" ]; then
    _pycfg="$cwd/.venv/pyvenv.cfg"
    # `version` (stdlib venv) or `version_info` (uv) both match /^version/
    py_ver=$(awk '/^version/ {print $3; exit}' "$_pycfg" 2>/dev/null)
    # uv-created venvs carry a `uv = <version>` line
    grep -q '^uv = ' "$_pycfg" 2>/dev/null && py_uv="uv"
    py_env=".venv"
    unset _pycfg
elif [ -f "$cwd/.python-version" ]; then
    py_env=$(head -1 "$cwd/.python-version" 2>/dev/null | tr -d '[:space:]')
elif [ -f "$HOME/.pyenv/version" ]; then
    py_env=$(head -1 "$HOME/.pyenv/version" 2>/dev/null | tr -d '[:space:]')
fi
if [ -n "$py_env" ]; then
    # ochre, lighter at center
    py_seg="🐍 $(gradient "$py_env" 225 170 55 245 205 110)${RESET}"
    # show major.minor only (3.12.9 → 3.12)
    if [ -n "$py_ver" ]; then
        py_seg="${py_seg} ${C_MUTED}${py_ver%.*}${RESET}"
    fi
    if [ -n "$py_uv" ]; then
        py_seg="${py_seg} ${C_LABEL}uv${RESET}"
    fi
fi

# gcloud active project — file reads only, never exec gcloud (too slow)
gcloud_seg=""
_gc_dir="$HOME/.config/gcloud"
if [ -d "$_gc_dir" ]; then
    _gc_cfg=$(cat "$_gc_dir/active_config" 2>/dev/null)
    _gc_proj=$(awk -F' = ' '/^project/ {print $2; exit}' "$_gc_dir/configurations/config_${_gc_cfg:-default}" 2>/dev/null)
    if [ -n "$_gc_proj" ]; then
        # ochre — same hue as the rest of the env/accounts zone
        gcloud_seg="☁️ $(gradient "$_gc_proj" 225 170 55 245 205 110)${RESET}"
    fi
fi
unset _gc_dir _gc_cfg _gc_proj

# Kubernetes context — current cluster from ~/.kube/config (file read only,
# never exec kubectl). Ochre like its zone siblings; any kubectl command
# would hit this cluster. Omitted entirely when no kube config exists.
kube_seg=""
if [ -f "$HOME/.kube/config" ]; then
    kube_ctx=$(awk '/^current-context:/ {print $2; exit}' "$HOME/.kube/config" 2>/dev/null)
    if [ -n "$kube_ctx" ]; then
        kube_seg="☸️ $(gradient "$kube_ctx" 225 170 55 245 205 110)${RESET}"
    fi
fi

# GitHub CLI identity — work vs personal, from hosts.yml (file read only).
# Auto-switched by the zshrc cd-hook when crossing the 002-engenious boundary.
# personal = ochre (quiet, zone hue); work = burgundy (attention state).
gh_seg=""
gh_user=$(awk '$1 == "user:" {print $2; exit}' "$HOME/.config/gh/hosts.yml" 2>/dev/null)
if [ -n "$gh_user" ]; then
    case "$gh_user" in
        j-garassino-engenious) gh_seg="🐙 ${BOLD}$(gradient "work" 170 60 75 210 95 110)${RESET}" ;;
        juan-garassino)        gh_seg="🐙 $(gradient "personal" 225 170 55 245 205 110)${RESET}" ;;
        *)                     gh_seg="🐙 ${C_MUTED}${gh_user}${RESET}" ;;
    esac
fi

# Clock — burgundy: the system cluster is the red zone
clock_seg="🕐 ${F_BURG}$(date +%H:%M)${RESET}"

# Free RAM — calm gray when plenty, yellow under 4G, red BLOCK under 2G.
# macOS: free+inactive pages × page size; Linux: MemAvailable from /proc/meminfo.
if [ -r /proc/meminfo ]; then
    ram_gb=$(awk '/^MemAvailable:/ { printf "%.1f", $2/1024/1024 }' /proc/meminfo)
else
    ram_gb=$(vm_stat 2>/dev/null | awk '
        /page size/  { gsub(/[^0-9]/,"",$8); ps=$8 }
        /Pages free/ { gsub(/\./,"",$3); f=$3 }
        /Pages inactive/ { gsub(/\./,"",$3); i=$3 }
        END { if (ps) printf "%.1f", (f+i)*ps/1024/1024/1024 }
    ')
fi
if [ -n "$ram_gb" ]; then
    ram_level=$(echo "$ram_gb" | awk '{if ($1 < 2) print "err"; else if ($1 < 4) print "warn"; else print "ok"}')
    case "$ram_level" in
        err)  ram_seg="${C_LABEL}RAM${RESET} ${M_ALARM}${BOLD}${F_BURG}${ram_gb}G${RESET}" ;;
        warn) ram_seg="${C_LABEL}RAM${RESET} ${M_WARN}${F_OCHRE}${ram_gb}G${RESET}" ;;
        *)    ram_seg="${C_LABEL}RAM${RESET} ${M_CALM}${F_BURG}${ram_gb}G${RESET}" ;;
    esac
else
    ram_seg=""
fi

# --- Compose: · joins inside a cluster, │ separates clusters ---
sep=" ${C_BAR}│${RESET} "
dot=" ${C_SEP}·${RESET} "

# join_dot OUT_VAR seg1 seg2 ... — concatenate non-empty segments with ·
join_dot() {
    local _out="" _s _var="$1"; shift
    for _s in "$@"; do
        [ -z "$_s" ] && continue
        if [ -z "$_out" ]; then _out="$_s"; else _out="${_out}${dot}${_s}"; fi
    done
    printf -v "$_var" '%s' "$_out"
}

join_dot cl_place "${dir_seg}${git_seg}"
join_dot cl_session "$model_seg" "$perm_seg" "${ctx_seg}${think_seg}"
join_dot cl_env "$py_seg" "$gcloud_seg" "$kube_seg" "$gh_seg"
join_dot cl_system "$clock_seg" "$ram_seg"

line=""
for g in "$cl_place" "$cl_session" "$cl_env" "$cl_system"; do
    [ -z "$g" ] && continue
    if [ -z "$line" ]; then line="$g"; else line="${line}${sep}${g}"; fi
done

# Session name only when the line is short enough to afford it
# (Claude Code already shows the name elsewhere, so it's a nice-to-have)
if [ -n "$session_name" ]; then
    plain=$(printf '%b' "$line" | sed $'s/\x1b\[[0-9;]*m//g')
    if [ $(( ${#plain} + ${#session_name} + 5 )) -le 110 ]; then
        line="${line}${sep}${C_LABEL}\"${session_name}\"${RESET}"
    fi
fi

printf '%b\n' "$line"
