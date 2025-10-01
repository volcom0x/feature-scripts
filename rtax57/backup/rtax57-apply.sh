#!/usr/bin/env bash
set -euo pipefail

# === Router endpoint ===
ROUTER_USER=admin
ROUTER_HOST=192.168.50.1
ROUTER_PORT=50000
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new)
#                                                  ^ only auto-accept the first time; won’t connect if a known key changes. :contentReference[oaicite:1]{index=1}
SSH=(ssh -p "$ROUTER_PORT" "${SSH_OPTS[@]}" "$ROUTER_USER@$ROUTER_HOST")

echo "[*] $(date -Is) syncing blocklists (egress: Spamhaus+Feodo; inbound: Spamhaus+Feodo+optional DShield)…"
WITH_DSHIELD=1 "$HOME/ax57_blocklist_sync.sh"

echo "[*] $(date -Is) enforcing Mullvad-only DoT / DoH guard…"
"${SSH[@]}" '/jffs/rtax57/bin/mullvad_only_dns_strict.sh'

echo "[*] $(date -Is) re-applying LAN DoT-only-to-Mullvad policy (compat-safe)…"
"${SSH[@]}" '/jffs/rtax57/bin/dot_only_policy.sh'

echo "[*] $(date -Is) antispoof / WAN lockdown / forced DNS / scrub vendor NAT…"
"${SSH[@]}" '/jffs/rtax57/bin/lan_antispoof.sh'
"${SSH[@]}" '/jffs/rtax57/bin/fw_lockdown.sh'
# Force LAN clients to use router DNS (port 53 -> router)
"${SSH[@]}" '/jffs/rtax57/bin/force_dns.sh router'
# Remove ASUS vendor NAT redirects if they reappear
"${SSH[@]}" '/jffs/rtax57/bin/scrub_vendor_redirects.sh'

echo "[*] $(date -Is) PS5 FC25 port forwards (baseline)…"
"${SSH[@]}" '/jffs/rtax57/bin/ps5_fc25_fw.sh baseline'

echo "[ok] $(date -Is) all rules enforced."
