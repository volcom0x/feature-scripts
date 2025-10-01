#!/bin/sh
# Fetch SPKI (pin-sha256 base64) for DoT endpoints.
# Usage: dot_spki_fetch.sh [host ...]; defaults to Mullvad base+extended.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
HOSTS="${*:-base.dns.mullvad.net extended.dns.mullvad.net}"
outdir="/jffs/rtax57/dnspriv"
mkdir -p "$outdir"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; exit 1; }; }
need openssl

for h in $HOSTS; do
  echo "== $h =="
  pin="$(echo | openssl s_client -connect "${h}:853" -servername "$h" 2>/dev/null \
        | openssl x509 -pubkey -noout \
        | openssl pkey -pubin -outform der \
        | openssl dgst -sha256 -binary \
        | openssl enc -base64 -A)"
  [ -n "$pin" ] || { echo "Failed to derive SPKI for $h"; exit 2; }
  echo "$pin" > "${outdir}/${h}.spki"
  printf "SPKI (base64): %s\n" "$pin"
done

# Emit a ready-to-paste summary for ASUS DoT entries
printf "\n--- ASUS DoT entries ---\n"
for h in $HOSTS; do
  case "$h" in
    base.dns.mullvad.net) ip4=194.242.2.4; ip6=2a07:e340::4;;
    extended.dns.mullvad.net) ip4=194.242.2.5; ip6=2a07:e340::5;;
    *) ip4=""; ip6="";;
  esac
  pin="$(cat "${outdir}/${h}.spki")"
  [ -n "$ip4" ] && printf "IPv4: %s  | TLS Hostname: %s | Port: 853 | SPKI: %s\n" "$ip4" "$h" "$pin"
  [ -n "$ip6" ] && printf "IPv6: %s  | TLS Hostname: %s | Port: 853 | SPKI: %s\n" "$ip6" "$h" "$pin"
done
