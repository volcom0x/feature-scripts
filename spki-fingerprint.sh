#!/bin/bash

# Function to get SPKI fingerprint
get_spki() {
    local host=$1
    local ip=$2
    local port=${3:-853}

    echo "Getting SPKI for $host ($ip)..." >&2

    # Use timeout to prevent hanging, connect via IP but use host for TLS verification
    fingerprint=$(timeout 20 openssl s_client -connect "[$ip]:$port" -servername "$host" -verify_hostname "$host" 2>/dev/null | openssl x509 -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 -binary | openssl enc -base64 2>/dev/null)

    if [ -z "$fingerprint" ]; then
        echo "Failed"
    else
        echo "$fingerprint"
    fi
}

# Server data
declare -A servers
servers["dns.mullvad.net"]="194.242.2.2 2a07:e340::2"
servers["adblock.dns.mullvad.net"]="194.242.2.3 2a07:e340::3"
servers["base.dns.mullvad.net"]="194.242.2.4 2a07:e340::4"
servers["extended.dns.mullvad.net"]="194.242.2.5 2a07:e340::5"
servers["family.dns.mullvad.net"]="194.242.2.6 2a07:e340::6"
servers["all.dns.mullvad.net"]="194.242.2.9 2a07:e340::9"

echo "Mullvad DNS Server SPKI Fingerprints"
echo "====================================="
echo ""

for host in "${!servers[@]}"; do
    echo "Hostname: $host"

    # Split IPv4 and IPv6
    ips=(${servers[$host]})
    ipv4="${ips[0]}"
    ipv6="${ips[1]}"

    echo "IPv4: $ipv4"
    echo "IPv6: $ipv6"

    # Try IPv4 first
    spki=$(get_spki "$host" "$ipv4")
    echo "SPKI Fingerprint: $spki"

    echo ""
done
