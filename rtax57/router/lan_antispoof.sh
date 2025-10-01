#!/bin/sh
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin

LAN_IF="$(nvram get lan_ifname 2>/dev/null || echo br0)"
LAN_IP="$(nvram get lan_ipaddr 2>/dev/null || echo 192.168.50.1)"
LAN_MASK="$(nvram get lan_netmask 2>/dev/null || echo 255.255.255.0)"

# Prefer the kernel-installed directly connected route:
LAN_CIDR="$(ip -4 route show dev "$LAN_IF" 2>/dev/null | awk '/proto kernel/ {print $1; exit}')"
if [ -z "${LAN_CIDR:-}" ]; then
  # Fallback: turn mask into prefix length and use host/prefix (iptables accepts it)
  mask_to_prefix() {
    o1=${1%%.*}; r=${1#*.}
    o2=${r%%.*}; r=${r#*.}
    o3=${r%%.*}; o4=${r#*.}
    for o in $o1 $o2 $o3 $o4; do
      case "$o" in
        255) pref=$((pref+8));;
        254) pref=$((pref+7));;
        252) pref=$((pref+6));;
        248) pref=$((pref+5));;
        240) pref=$((pref+4));;
        224) pref=$((pref+3));;
        192) pref=$((pref+2));;
        128) pref=$((pref+1));;
        0)   pref=$((pref+0));;
        *)   pref=24;;
      esac
    done
    echo "$pref"
  }
  pref=0; pref="$(mask_to_prefix "$LAN_MASK")"
  LAN_CIDR="${LAN_IP}/${pref}"
fi

CHAIN="AX57_ANTISPOOF"
iptables -t filter -nL "$CHAIN" >/dev/null 2>&1 || iptables -t filter -N "$CHAIN"
iptables -t filter -C FORWARD -i "$LAN_IF" -j "$CHAIN" 2>/dev/null || iptables -t filter -I FORWARD 1 -i "$LAN_IF" -j "$CHAIN"
iptables -t filter -F "$CHAIN"

iptables -t filter -A "$CHAIN" ! -s "$LAN_CIDR" -j DROP
iptables -t filter -A "$CHAIN" -j RETURN

echo "[ok] Anti-spoof on $LAN_IF for $LAN_CIDR"
