#!/usr/bin/env bash
set -euo pipefail

# === config ===
ROUTER_USER="${ROUTER_USER:-admin}"
ROUTER_HOST="${ROUTER_HOST:-192.168.50.1}"
ROUTER_PORT="${ROUTER_PORT:-50000}"
REMOTE_DIR="/jffs/rtax57/bin"
DEST="${DEST:-$HOME/.glab-repos/poseidon-scripts/feature-scripts/rtax57/router}"
mkdir -p "$DEST"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new)
SSH=(ssh -p "$ROUTER_PORT" "${SSH_OPTS[@]}" "$ROUTER_USER@$ROUTER_HOST")

say(){ printf '%s\n' "$*"; }

# --- probe remote capabilities ---
has_tar="$("${SSH[@]}" 'command -v tar >/dev/null 2>&1 && echo yes || (busybox | grep -qw tar && echo busybox) || echo no' || true)"
has_b64="$("${SSH[@]}" 'command -v base64 >/dev/null 2>&1 && echo yes || (busybox base64 --help >/dev/null 2>&1 && echo busybox) || echo no' || true)"

say "[*] remote tar:   $has_tar"
say "[*] remote base64: $has_b64"
say "[*] pulling files from $ROUTER_HOST:$REMOTE_DIR -> $DEST"

# --- method 1: tar over SSH (preferred) ---
if [[ "$has_tar" != "no" ]]; then
  remote_tar="tar"
  [[ "$has_tar" == "busybox" ]] && remote_tar="busybox tar"
  say "[*] using $remote_tar over SSH…"
  # pack on router -> stream -> extract locally
  if "${SSH[@]}" "$remote_tar -C '$REMOTE_DIR' -cf - . " | tar -C "$DEST" -xvf -; then
    chmod 700 "$DEST"/*.sh 2>/dev/null || true
    say "[ok] pulled via tar-over-ssh"
    exit 0
  else
    say "[warn] tar-over-ssh failed, falling back…"
  fi
fi

# --- method 2: per-file base64 over SSH (binary-safe) ---
if [[ "$has_b64" != "no" ]]; then
  say "[*] using base64 per-file copy…"
  mapfile -t files < <("${SSH[@]}" "ls -1 $REMOTE_DIR/*.sh 2>/dev/null" || true)
  if ((${#files[@]}==0)); then
    say "[err] no *.sh files found in $REMOTE_DIR"; exit 2
  fi
  for f in "${files[@]}"; do
    bn="${f##*/}"
    say "    - $bn"
    # encode remotely, decode locally
    "${SSH[@]}" "base64 '$f' 2>/dev/null || busybox base64 '$f'" | base64 -d > "$DEST/$bn"
    chmod 700 "$DEST/$bn"
  done
  say "[ok] pulled via base64"
  exit 0
fi

# --- method 3: per-file raw cat (text-safe; your payloads are .sh) ---
say "[*] using raw cat per-file (text)…"
mapfile -t files < <("${SSH[@]}" "ls -1 $REMOTE_DIR/*.sh 2>/dev/null" || true)
if ((${#files[@]}==0)); then
  say "[err] no *.sh files found in $REMOTE_DIR"; exit 2
fi
for f in "${files[@]}"; do
  bn="${f##*/}"
  say "    - $bn"
  "${SSH[@]}" "cat '$f'" > "$DEST/$bn"
  chmod 700 "$DEST/$bn"
done
say "[ok] pulled via raw cat"
