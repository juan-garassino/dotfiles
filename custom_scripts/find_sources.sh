#!/usr/bin/env bash
# find_sources.sh — list machines on the local network that accept ssh (candidate migration
# sources). Used by MIGRATE.md step 2: Claude runs it, then asks the user which one to pull from.
#
#   custom_scripts/find_sources.sh            # prints: IP<TAB>NAME<TAB>SSH-BANNER
#
# 1) mDNS: Macs with Remote Login on announce _ssh._tcp (Linux too if avahi publishes ssh).
# 2) Fallback sweep: every host in this machine's /24 (or the subnet's real size, capped) with
#    port 22 open. Read-only: it only opens a TCP connection and reads the ssh banner.
set -u
os="$(uname)"
NAMES="$(mktemp)"   # ip<TAB>name (no associative arrays: macOS bash is 3.2)
tmo() { if command -v timeout >/dev/null 2>&1; then timeout "$@"; else perl -e 'alarm shift; exec @ARGV' "$@"; fi; }
export -f tmo

# --- 1. mDNS / Bonjour ---------------------------------------------------------------------
if command -v avahi-browse >/dev/null 2>&1; then
  while IFS=';' read -r ev _ proto name _ _ host ip _; do
    [ "$ev" = "=" ] && [ "$proto" = IPv4 ] && printf '%s\t%s\n' "$ip" "${host%.local}" >> "$NAMES"
  done < <(tmo 5 avahi-browse -rpt _ssh._tcp 2>/dev/null)
elif [ "$os" = Darwin ]; then
  out="$(mktemp)"; dns-sd -B _ssh._tcp local. > "$out" 2>/dev/null & pid=$!; sleep 3; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  for n in $(awk '/Add/ {for(i=7;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"\n")}' "$out" | tr ' ' '_' | sort -u); do
    h="${n//_/-}.local"; ip="$(dscacheutil -q host -a name "$h" 2>/dev/null | awk '/ip_address/ {print $2; exit}')"
    [ -n "$ip" ] && printf '%s\t%s\n' "$ip" "${n//_/ }" >> "$NAMES"
  done; rm -f "$out"
fi

# --- 2. subnet sweep for port 22 -----------------------------------------------------------
if [ "$os" = Darwin ]; then
  me="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)"
else
  me="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
fi
probe() { # ip → "ip<TAB>banner" if port 22 answers within 1s
  local b; b="$(tmo 1 bash -c "exec 3<>/dev/tcp/$1/22 && head -c 80 <&3" 2>/dev/null | tr -d '\r\n')"
  [ -n "$b" ] && printf '%s\t%s\n' "$1" "$b"
}
export -f probe
if [ -n "${me:-}" ]; then
  base="${me%.*}"
  seq 1 254 | sed "s/^/$base./" | grep -vx "$me" | xargs -P 64 -I{} bash -c 'probe {}' > /tmp/find_sources.$$ 2>/dev/null
else
  : > /tmp/find_sources.$$
fi
cut -f1 "$NAMES" | sort -u | while read -r ip; do grep -q "^$ip	" /tmp/find_sources.$$ || probe "$ip" >> /tmp/find_sources.$$; done

# --- 3. report -----------------------------------------------------------------------------
echo -e "IP\tNAME\tSSH"
sort -t. -k4,4n -u /tmp/find_sources.$$ | while IFS=$'\t' read -r ip banner; do
  n="$(awk -F'\t' -v i="$ip" '$1==i {print $2; exit}' "$NAMES")"
  [ -z "$n" ] && n="$( (getent hosts "$ip" 2>/dev/null || true) | awk '{print $2}')"
  [ -z "$n" ] && command -v avahi-resolve >/dev/null 2>&1 && n="$(tmo 2 avahi-resolve -a "$ip" 2>/dev/null | awk '{print $2}')"
  echo -e "$ip\t${n:--}\t$banner"
done
rm -f /tmp/find_sources.$$ "$NAMES"
echo "(this machine: ${me:-unknown})" >&2
