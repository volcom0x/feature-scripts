#!/bin/sh
# Strict Mullvad-only DoT enforcement, LAN clients + router OUTPUT. Idempotent.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin

LAN_IF="$(nvram get lan_ifname 2>/dev/null || echo br0)"

ALLOW_V4="194.242.2.4 194.242.2.5"
ALLOW_V6="2a07:e340::4 2a07:e340::5"
V4_FILE="/jffs/rtax57/etc/mullvad_dot_v4.list"
V6_FILE="/jffs/rtax57/etc/mullvad_dot_v6.list"
[ -s "$V4_FILE" ] && ALLOW_V4="$(awk '!/^($|#)/{printf "%s ",$0}' "$V4_FILE")"
[ -s "$V6_FILE" ] && ALLOW_V6="$(awk '!/^($|#)/{printf "%s ",$0}' "$V6_FILE")"

CHAIN_V4="AX57_DOT_ENFORCE"
iptables -t filter -nL "$CHAIN_V4" >/dev/null 2>&1 || iptables -t filter -N "$CHAIN_V4"
iptables -t filter -C FORWARD -i "$LAN_IF" -p tcp --dport 853 -j "$CHAIN_V4" 2>/dev/null || \
  iptables -t filter -I FORWARD 1 -i "$LAN_IF" -p tcp --dport 853 -j "$CHAIN_V4"
iptables  -C OUTPUT  -p tcp --dport 853 -j "$CHAIN_V4" 2>/dev/null || \
  iptables  -I OUTPUT 1 -p tcp --dport 853 -j "$CHAIN_V4"
iptables -t filter -F "$CHAIN_V4"
for ip in $ALLOW_V4; do iptables -t filter -A "$CHAIN_V4" -d "$ip" -j ACCEPT; done
iptables -t filter -A "$CHAIN_V4" -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null || \
iptables -t filter -A "$CHAIN_V4" -p tcp -j REJECT

if [ -s /proc/net/if_inet6 ] && command -v ip6tables >/dev/null 2>&1; then
  CHAIN_V6="AX57_DOT_ENFORCE6"
  ip6tables -t filter -nL "$CHAIN_V6" >/dev/null 2>&1 || ip6tables -t filter -N "$CHAIN_V6"
  ip6tables -t filter -C FORWARD -i "$LAN_IF" -p tcp --dport 853 -j "$CHAIN_V6" 2>/dev/null || \
    ip6tables -t filter -I FORWARD 1 -i "$LAN_IF" -p tcp --dport 853 -j "$CHAIN_V6"
  ip6tables -C OUTPUT  -p tcp --dport 853 -j "$CHAIN_V6" 2>/dev/null || \
    ip6tables -I OUTPUT 1 -p tcp --dport 853 -j "$CHAIN_V6"
  ip6tables -t filter -F "$CHAIN_V6"
  for ip in $ALLOW_V6; do ip6tables -t filter -A "$CHAIN_V6" -d "$ip" -j ACCEPT; done
  ip6tables -t filter -A "$CHAIN_V6" -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null || \
  ip6tables -t filter -A "$CHAIN_V6" -p tcp -j REJECT
else
  echo "[warn] IPv6 not available: skipping AX57_DOT_ENFORCE6" >&2 || true
fi

echo "[ok] Strict Mullvad-only encrypted DNS enforcement is active (LAN+router)."
