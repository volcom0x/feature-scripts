#!/bin/sh
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin

# Remove ASUS vendor NAT (e.g., to :18017/:18018) if present
for d in 18017 18018; do
  while iptables -t nat -S PREROUTING | grep -q "dpt:$d"; do
    iptables -t nat -D PREROUTING $(iptables -t nat -S PREROUTING | nl -ba | grep "dpt:$d" | awk '{print $1}' | head -n1) >/dev/null 2>&1 || break
  done
done
echo "[ok] Any PREROUTING DNATs to :18017 / :18018 removed"
