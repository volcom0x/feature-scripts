#!/bin/sh
# EA Sports FC (FIFA) PS5 baseline forwards (idempotent).
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin

PS5_IP="${1:-192.168.50.44}"
WAN_IF="$(nvram get wan0_ifname 2>/dev/null || nvram get wan_ifname 2>/dev/null || echo eth0)"

# Chains
NATC="AX57_PSNAT"
FILC="AX57_PSFWD"
iptables -t nat -nL "$NATC" >/dev/null 2>&1 || iptables -t nat -N "$NATC"
iptables -t filter -nL "$FILC" >/dev/null 2>&1 || iptables -t filter -N "$FILC"

# Hooks (once)
iptables -t nat    -C PREROUTING -j "$NATC" 2>/dev/null || iptables -t nat    -I PREROUTING 1 -j "$NATC"
iptables -t filter -C FORWARD    -j "$FILC" 2>/dev/null || iptables -t filter -I FORWARD    1 -j "$FILC"

# Reset chain contents
iptables -t nat -F "$NATC"
iptables -t filter -F "$FILC"

add_tcp() { iptables -t nat -A "$NATC" -p tcp --dport "$1" -j DNAT --to-destination "$PS5_IP:$1"; iptables -t filter -A "$FILC" -p tcp -d "$PS5_IP" --dport "$1" -m conntrack --ctstate NEW -j ACCEPT; }
add_udp() { iptables -t nat -A "$NATC" -p udp --dport "$1" -j DNAT --to-destination "$PS5_IP:$1"; iptables -t filter -A "$FILC" -p udp -d "$PS5_IP" --dport "$1" -m conntrack --ctstate NEW -j ACCEPT; }

# Sony/EA common (minimal baseline)
add_tcp 3478; add_tcp 3479; add_tcp 3480
add_udp 3478; add_udp 3479; add_udp 3659

# Allow established + return
iptables -t filter -A "$FILC" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t filter -A "$FILC" -j RETURN

echo "[ok] PS5 FC baseline forwards applied to $PS5_IP via $WAN_IF"
