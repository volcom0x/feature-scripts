#!/bin/sh
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
WAN_IF="$(nvram get wan0_ifname 2>/dev/null || nvram get wan_ifname 2>/dev/null || echo eth0)"

CHAIN="AX57_LOCKDOWN"
iptables -t filter -nL "$CHAIN" >/dev/null 2>&1 || iptables -t filter -N "$CHAIN"
iptables -t filter -C INPUT -i "$WAN_IF" -j "$CHAIN" 2>/dev/null || iptables -t filter -I INPUT 1 -i "$WAN_IF" -j "$CHAIN"
iptables -t filter -F "$CHAIN"

iptables -t filter -A "$CHAIN" -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
iptables -t filter -A "$CHAIN" -p icmp --icmp-type echo-request -j DROP
iptables -t filter -A "$CHAIN" -p tcp -m multiport --dports 22,23,53,80,443 -j DROP
iptables -t filter -A "$CHAIN" -p udp --dport 53 -j DROP
iptables -t filter -A "$CHAIN" -j RETURN

echo "[ok] WAN lockdown on $WAN_IF; check: iptables -vnL INPUT"
