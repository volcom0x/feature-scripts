#!/bin/sh
# Force LAN IPv4 DNS to router:53 using NAT redirection (idempotent).
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin

LAN_IF="$(nvram get lan_ifname 2>/dev/null || echo br0)"
LAN_IP="$(nvram get lan_ipaddr 2>/dev/null || echo 192.168.50.1)"

# Create/clean AX57_DNS chain in nat PREROUTING
CHAIN="AX57_DNS"
iptables -t nat -nL "$CHAIN" >/dev/null 2>&1 || iptables -t nat -N "$CHAIN"
iptables -t nat -C PREROUTING -i "$LAN_IF" -j "$CHAIN" 2>/dev/null || iptables -t nat -I PREROUTING 1 -i "$LAN_IF" -j "$CHAIN"
iptables -t nat -F "$CHAIN"

# Redirect all LAN DNS (TCP+UDP 53) to router
iptables -t nat -A "$CHAIN" -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A "$CHAIN" -p tcp --dport 53 -j REDIRECT --to-ports 53

echo "[ok] Forced DNS on $LAN_IF -> router:53; check: iptables -t nat -vnL PREROUTING"
