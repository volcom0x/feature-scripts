#!/usr/bin/env bash
# Build curated lists on Kali, push to RT-AX57 without scp/sftp, then apply.
set -euo pipefail

# Router endpoint
ROUTER_USER="${ROUTER_USER:-admin}"
ROUTER_HOST="${ROUTER_HOST:-192.168.50.1}"
ROUTER_PORT="${ROUTER_PORT:-50000}"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ServerAliveInterval=20
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=accept-new
)
SSH=(ssh -p "$ROUTER_PORT" "${SSH_OPTS[@]}" "$ROUTER_USER@$ROUTER_HOST")

# Feeds
URL_SPAMHAUS_DROP="https://www.spamhaus.org/drop/drop.txt"
URL_FEODO_REC="https://feodotracker.abuse.ch/downloads/ipblocklist_recommended.txt"
URL_DSHIELD="https://www.dshield.org/block.txt"

# Cache last-good copies
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/rtax57"
mkdir -p "$CACHE"

curl_fetch() {
  local url="$1" out="$2" tag="$3"
  echo "[*] Fetching $tag..."
  if curl -4fsS --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 10 "$url" -o "${out}.tmp"; then
    mv -f "${out}.tmp" "$out"
  else
    echo "[warn] $tag fetch failed; using cached copy if present"
    rm -f "${out}.tmp" 2>/dev/null || true
  fi
}

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
eg_v4="$tmpdir/eg_v4.cidr"; eg_v6="$tmpdir/eg_v6.cidr"
in_v4="$tmpdir/in_v4.cidr"; in_v6="$tmpdir/in_v6.cidr"
: >"$eg_v4"; : >"$eg_v6"; : >"$in_v4"; : >"$in_v6"

# 1) Spamhaus DROP -> egress + inbound
SPAM="$CACHE/drop.txt"
curl_fetch "$URL_SPAMHAUS_DROP" "$SPAM" "Spamhaus DROP"
if [ -s "$SPAM" ]; then
  awk '!/^;|^$/{print $1}' "$SPAM" | while read -r net; do
    case "$net" in
      *:*)  echo "$net"    >>"$eg_v6"; echo "$net"    >>"$in_v6" ;;
      */*)  echo "$net"    >>"$eg_v4"; echo "$net"    >>"$in_v4" ;;
      *)    echo "$net/32" >>"$eg_v4"; echo "$net/32" >>"$in_v4" ;;
    esac
  done
else
  echo "[warn] no Spamhaus data this run"
fi

# 2) Feodo recommended C2 IPv4 -> egress + inbound
FEODO="$CACHE/feodo_rec.txt"
curl_fetch "$URL_FEODO_REC" "$FEODO" "Feodo recommended C2"
if [ -s "$FEODO" ]; then
  awk '!/^#|^$/{print $1"/32"}' "$FEODO" >>"$eg_v4"
  awk '!/^#|^$/{print $1"/32"}' "$FEODO" >>"$in_v4"
else
  echo "[warn] no Feodo data this run"
fi

# 3) OPTIONAL inbound-only: DShield /24 (set WITH_DSHIELD=0 to skip)
if [ "${WITH_DSHIELD:-1}" = "1" ]; then
  DSHIELD="$CACHE/dshield.txt"
  curl_fetch "$URL_DSHIELD" "$DSHIELD" "DShield block list"
  [ -s "$DSHIELD" ] && awk '!/^#|^$/{print $1"/24"}' "$DSHIELD" >>"$in_v4" || echo "[warn] no DShield data this run"
fi

# Deduplicate
sort -u "$eg_v4" -o "$eg_v4"; sort -u "$in_v4" -o "$in_v4"
sort -u "$eg_v6" -o "$eg_v6"; sort -u "$in_v6" -o "$in_v6"

# Push to router WITHOUT scp/sftp (stdin -> remote file)
"${SSH[@]}" 'mkdir -p /jffs/rtax57/etc'
"${SSH[@]}" "cat > /jffs/rtax57/etc/eg_v4.cidr" < "$eg_v4"
"${SSH[@]}" "cat > /jffs/rtax57/etc/in_v4.cidr" < "$in_v4"
"${SSH[@]}" "cat > /jffs/rtax57/etc/eg_v6.cidr" < "$eg_v6"
"${SSH[@]}" "cat > /jffs/rtax57/etc/in_v6.cidr" < "$in_v6"

# Apply on router
"${SSH[@]}" '/jffs/rtax57/bin/blocklists_apply.sh'

echo "[ok] Blocklists synced/applied"
