#!/bin/sh
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin

LAN_IF="$(nvram get lan_ifname 2>/dev/null || echo br0)"
WAN_IF="$(nvram get wan0_ifname 2>/dev/null || nvram get wan_ifname 2>/dev/null || echo eth0)"

EG4=/jffs/rtax57/etc/eg_v4.cidr
EG6=/jffs/rtax57/etc/eg_v6.cidr
IN4=/jffs/rtax57/etc/in_v4.cidr
IN6=/jffs/rtax57/etc/in_v6.cidr

EGRESS4=AX57_BAD_EGRESS4
INGRESS4=AX57_BAD_INGRESS4

iptables -t filter -nL $EGRESS4 >/dev/null 2>&1 || iptables -t filter -N $EGRESS4
iptables -t filter -nL $INGRESS4 >/dev/null 2>&1 || iptables -t filter -N $INGRESS4

iptables -t filter -C FORWARD -i "$LAN_IF" -j $EGRESS4 2>/dev/null || iptables -t filter -I FORWARD 1 -i "$LAN_IF" -j $EGRESS4
iptables -t filter -C INPUT   -i "$WAN_IF" -j $INGRESS4 2>/dev/null || iptables -t filter -I INPUT   1 -i "$WAN_IF" -j $INGRESS4
iptables -t filter -C FORWARD -i "$WAN_IF" -j $INGRESS4 2>/dev/null || iptables -t filter -I FORWARD 1 -i "$WAN_IF" -j $INGRESS4

iptables -t filter -F $EGRESS4
iptables -t filter -F $INGRESS4

if [ -s "$EG4" ]; then
  while read -r net; do case "$net" in ''|\#*) continue;; esac
    iptables -t filter -A $EGRESS4 -d "$net" -j REJECT
  done < "$EG4"
fi
iptables -t filter -A $EGRESS4 -j RETURN

if [ -s "$IN4" ]; then
  while read -r net; do case "$net" in ''|\#*) continue;; esac
    iptables -t filter -A $INGRESS4 -s "$net" -j DROP
  done < "$IN4"
fi
iptables -t filter -A $INGRESS4 -j RETURN

if [ -s /proc/net/if_inet6 ] && command -v ip6tables >/dev/null 2>&1; then
  EGRESS6=AX57_BAD_EGRESS6
  INGRESS6=AX57_BAD_INGRESS6
  ip6tables -t filter -nL $EGRESS6 >/dev/null 2>&1 || ip6tables -t filter -N $EGRESS6
  ip6tables -t filter -nL $INGRESS6 >/dev/null 2>&1 || ip6tables -t filter -N $INGRESS6
  ip6tables -t filter -C FORWARD -i "$LAN_IF" -j $EGRESS6 2>/dev/null || ip6tables -t filter -I FORWARD 1 -i "$LAN_IF" -j $EGRESS6
  ip6tables -t filter -C INPUT   -i "$WAN_IF" -j $INGRESS6 2>/dev/null || ip6tables -t filter -I INPUT   1 -i "$WAN_IF" -j $INGRESS6
  ip6tables -t filter -C FORWARD -i "$WAN_IF" -j $INGRESS6 2>/dev/null || ip6tables -t filter -I FORWARD 1 -i "$WAN_IF" -j $INGRESS6
  ip6tables -t filter -F $EGRESS6
  ip6tables -t filter -F $INGRESS6

  if [ -s "$EG6" ]; then
    while read -r net; do case "$net" in ''|\#*) continue;; esac
      ip6tables -t filter -A $EGRESS6 -d "$net" -j REJECT
    done < "$EG6"
  fi
  ip6tables -t filter -A $EGRESS6 -j RETURN

  if [ -s "$IN6" ]; then
    while read -r net; do case "$net" in ''|\#*) continue;; esac
      ip6tables -t filter -A $INGRESS6 -s "$net" -j DROP
    done < "$IN6"
  fi
  ip6tables -t filter -A $INGRESS6 -j RETURN
fi

n_eg4=0; [ -s "$EG4" ] && n_eg4=$(wc -l < "$EG4")
n_in4=0; [ -s "$IN4" ] && n_in4=$(wc -l < "$IN4")
n_eg6=0; [ -s "$EG6" ] && n_eg6=$(wc -l < "$EG6")
n_in6=0; [ -s "$IN6" ] && n_in6=$(wc -l < "$IN6")
echo "[ok] Blocklists applied: eg4=$n_eg4 in4=$n_in4 eg6=$n_eg6 in6=$n_in6"
