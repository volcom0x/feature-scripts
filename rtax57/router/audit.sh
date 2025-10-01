#!/bin/sh
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
LAN_IF="$(nvram get lan_ifname 2>/dev/null || echo br0)"
WAN_IF="$(nvram get wan0_ifname 2>/dev/null || nvram get wan_ifname 2>/dev/null || echo eth0)"

echo "=== BASIC ==="
echo "LAN: $LAN_IF  WAN: $WAN_IF"
echo

echo "=== DNS (nvram) ==="
echo "wan0_dnsenable_x=$(nvram get wan0_dnsenable_x 2>/dev/null || echo)"
echo "wan0_dns=$(nvram get wan0_dns 2>/dev/null || echo)"
echo

echo "=== CHAINS (v4) ==="
for c in AX57_DOTONLY AX57_DOT_ENFORCE AX57_BAD_EGRESS4 AX57_BAD_INGRESS4 AX57_PSFWD AX57_LOCKDOWN AX57_ANTISPOOF; do
  iptables -vnL "$c" 2>/dev/null | sed -n '1,10p' || true
  echo
done

if [ -s /proc/net/if_inet6 ] && command -v ip6tables >/dev/null 2>&1; then
  echo "=== CHAINS (v6) ==="
  for c in AX57_DOTONLY6 AX57_DOT_ENFORCE6 AX57_BAD_EGRESS6 AX57_BAD_INGRESS6; do
    ip6tables -vnL "$c" 2>/dev/null | sed -n '1,10p' || true
    echo
  done
fi

echo "=== DoT sessions (tcp/853) ==="
netstat -tn 2>/dev/null | awk '($4 ~ /:853$/ || $5 ~ /:853$/) {print}'
echo "[ok] audit complete"
