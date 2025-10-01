#!/usr/bin/env bash
set -euo pipefail

# Router endpoint
ROUTER_USER=admin
ROUTER_HOST=192.168.50.1
ROUTER_PORT=50000

# Resolve the path to the sync script relative to HOME (provided by systemd unit)
SYNC="${HOME:-/home/matthew}/.glab-repos/poseidon-scripts/feature-scripts/rtax57/ax57_blocklist_sync.sh"
if [[ ! -x "$SYNC" ]]; then
  echo "[err] $SYNC missing or not executable" >&2
  exit 1
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new)
SSH=(ssh -p "$ROUTER_PORT" "${SSH_OPTS[@]}" "$ROUTER_USER@$ROUTER_HOST")

echo "[*] $(date -Is) syncing blocklists (egress: Spamhaus+Feodo; inbound: Spamhaus+Feodo+optional DShield)…"
WITH_DSHIELD=1 "$SYNC"

echo "[*] $(date -Is) enforcing Mullvad-only DoT / DoH guard…"
"${SSH[@]}" '/jffs/rtax57/bin/mullvad_only_dns_strict.sh'

echo "[*] $(date -Is) re-applying LAN DoT-only-to-Mullvad policy (compat-safe)…"
"${SSH[@]}" '/jffs/rtax57/bin/dot_only_policy.sh'

echo "[*] $(date -Is) antispoof / WAN lockdown / forced DNS / scrub vendor NAT…"
"${SSH[@]}" '/jffs/rtax57/bin/lan_antispoof.sh'
"${SSH[@]}" '/jffs/rtax57/bin/fw_lockdown.sh'
"${SSH[@]}" '/jffs/rtax57/bin/force_dns.sh router'
"${SSH[@]}" '/jffs/rtax57/bin/scrub_vendor_redirects.sh'

echo "[*] $(date -Is) PS5 FC25 port forwards (baseline)…"
"${SSH[@]}" '/jffs/rtax57/bin/ps5_fc25_fw.sh baseline'

echo "[ok] $(date -Is) all rules enforced."
