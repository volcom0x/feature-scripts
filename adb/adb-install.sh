#!/usr/bin/env bash
# android-toolchain-install.sh — Complete ADB/Fastboot/Heimdall toolchain with udev & pairing
# Security & reliability focused: removes conflicts, installs official tools, sets udev, prevents ModemManager grabs,
# adds Pixel OTA payload dumper, and pairs a device. Creates 'adbx' bound to the selected phone for convenience.
#
# Sources:
#  - Platform-Tools (adb+fastboot): https://developer.android.com/tools/releases/platform-tools
#  - ADB docs: https://developer.android.com/tools/adb
#  - Fastboot/bootloader unlock: https://source.android.com/docs/core/architecture/bootloader/locking_unlocking
#  - Pixel factory images/flash guidance: https://developers.google.com/android/images
#  - Heimdall (Samsung Download/Odin mode): https://github.com/Benjamin-Dobell/Heimdall
#  - Payload dumper (payload.bin): https://github.com/ssut/payload-dumper-go
#  - ModemManager ignore tag: https://www.freedesktop.org/software/ModemManager/doc/latest/ModemManager/ModemManager-Common-udev-tags.html
set -Eeuo pipefail
IFS=$' \t\n'

# --------------------------- Tunables -----------------------------------------
INSTALL_ROOT="${HOME}/Android"
PT_DIR="${INSTALL_ROOT}/platform-tools"       # official adb/fastboot location
UDEV_FILE="/etc/udev/rules.d/51-android.rules"

USE_FULL_UDEV_RULES=auto   # auto|on|off (auto if git is present)
STOP_MODEMMANAGER=auto     # auto|on|off (stop if active)
MAKE_ADBX=0                # 1=create ~/.local/bin/adbx bound to selected serial

# extra tools
INSTALL_HEIMDALL=0         # Samsung flashing (Download mode)
INSTALL_PAYLOAD_DUMPER=1   # Pixel OTA extraction
INSTALL_P7ZIP=1            # unpack Odin .tar.md5

# --------------------------- Helpers ------------------------------------------
msg(){ printf '\e[1;32m[*]\e[0m %s\n' "$*"; }
warn(){ printf '\e[1;33m[!]\e[0m %s\n' "$*" >&2; }
err(){ printf '\e[1;31m[ERROR]\e[0m %s\n' "$*" >&2; exit 1; }

need(){ command -v "$1" >/dev/null 2>&1 || err "Missing dependency: $1"; }

as_user_only(){ [[ $EUID -ne 0 ]] || err "Do NOT run as root. The script uses sudo only where needed."; }
sudo_(){ sudo -n true 2>/dev/null || true; sudo "$@"; }

pm_has(){ command -v "$1" >/dev/null 2>&1; }
is_cmd(){ command -v "$1" >/dev/null 2>&1; }

# --------------------------- Preflight ----------------------------------------
as_user_only
need curl
need unzip

# --------------------------- Remove conflicting installs ----------------------
msg "Removing conflicting adb/fastboot from package managers… (safe if absent)"
if pm_has apt-get;  then sudo_ apt-get purge -y adb android-tools-adb android-tools-fastboot android-sdk-platform-tools || true; fi
if pm_has dnf;      then sudo_ dnf remove -y android-tools || true; fi
if pm_has pacman;   then sudo_ pacman -Rns --noconfirm android-tools || true; fi
if pm_has zypper;   then sudo_ zypper -n rm -y android-tools || true; fi
if pm_has brew;     then brew list --versions android-platform-tools >/dev/null 2>&1 && brew uninstall --force android-platform-tools || true; fi
if pm_has snap;     then for s in androidsdk platform-tools android-tools android-studio; do snap list "$s" >/dev/null 2>&1 && sudo_ snap remove "$s" || true; done; fi
if pm_has nix-env;  then nix-env -q | grep -E '^android(-|.*platform-tools)' >/dev/null 2>&1 && nix-env -e android-tools || true; fi

# Remove stray non-distro binaries from PATH (except our target)
strip_dup() { awk '!x[$0]++'; }
mapfile -t ADBS < <(type -a adb 2>/dev/null | awk '{print $NF}' | sed 's/,$//' | strip_dup || true)
mapfile -t FBS  < <(type -a fastboot 2>/dev/null | awk '{print $NF}' | sed 's/,$//' | strip_dup || true)
clean_bin(){
  local bin="$1" path="$2"; [[ -z "$path" ]] && return 0
  [[ "$path" == "$PT_DIR/$bin" ]] && return 0
  # best-effort removal of local duplicates in /usr/local or /opt (not owned by a pkg)
  if [[ -e "$path" && ( "$path" == /usr/local/* || "$path" == /opt/* ) ]]; then
    msg "Removing stray $bin at $path"
    sudo_ rm -f "$path" || true
  fi
}
for p in "${ADBS[@]}"; do clean_bin adb "$p"; done
for p in "${FBS[@]}";  do clean_bin fastboot "$p"; done

# --------------------------- Install official Platform-Tools -------------------
msg "Installing latest Platform-Tools to $PT_DIR …"
mkdir -p "$INSTALL_ROOT"
cd "$INSTALL_ROOT"
curl -fL --retry 3 -o platform-tools-latest-linux.zip \
  "https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
rm -rf "$PT_DIR"
unzip -q platform-tools-latest-linux.zip
rm -f platform-tools-latest-linux.zip

# PATH precedence (bash & zsh)
add_path() { local f="$1"; grep -q 'Android/platform-tools' "$f" 2>/dev/null || echo 'export PATH="$HOME/Android/platform-tools:$PATH"' >> "$f"; }
add_path "$HOME/.bashrc"; [[ -f "$HOME/.zshrc" ]] && add_path "$HOME/.zshrc"
export PATH="$HOME/Android/platform-tools:$PATH"

# --------------------------- udev rules + plugdev + ModemManager --------------
msg "Installing udev rules (Samsung/Google/Motorola) + ModemManager ignore…"
sudo_ install -m 0644 /dev/stdin "$UDEV_FILE" <<'RULES'
# Minimal Android udev rules (secure; prevent ModemManager from grabbing)
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"  # Samsung
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"  # Google
SUBSYSTEM=="usb", ATTR{idVendor}=="22b8", MODE="0666", GROUP="plugdev", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"  # Motorola
RULES
sudo_ chmod 0644 "$UDEV_FILE"

# Optional: full rules (covers most vendors)
if { [[ "$USE_FULL_UDEV_RULES" == "on" ]] || { [[ "$USE_FULL_UDEV_RULES" == "auto" ]] && is_cmd git; }; }; then
  msg "Installing full community android-udev-rules (broad vendor coverage)…"
  tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
  git clone --depth=1 https://github.com/M0Rf30/android-udev-rules.git "$tmpdir" >/dev/null 2>&1 || true
  if [[ -f "$tmpdir/51-android.rules" ]]; then
    sudo_ cp -f "$tmpdir/51-android.rules" "$UDEV_FILE"
    sudo_ chmod 0644 "$UDEV_FILE"
  else
    warn "Full rules fetch failed; keeping minimal rules."
  fi
fi
sudo apt install adb
# plugdev group & reload
getent group plugdev >/dev/null || sudo_ groupadd plugdev
id -nG "$USER" | grep -qw plugdev || { msg "Adding $USER to plugdev (re-login may be required)…"; sudo_ usermod -aG plugdev "$USER"; }
sudo_ udevadm control --reload-rules
sudo_ udevadm trigger

# ModemManager can steal your phone; stop if active
case "$STOP_MODEMMANAGER" in
  on)   sudo_ systemctl stop ModemManager.service 2>/dev/null || true ;;
  auto) systemctl is-active --quiet ModemManager.service 2>/dev/null && { msg "Stopping ModemManager…"; sudo_ systemctl stop ModemManager.service || true; } ;;
  off)  : ;;
esac

# --------------------------- Extra tools --------------------------------------
if [[ "$INSTALL_HEIMDALL" -eq 1 ]]; then
  msg "Installing Heimdall (Samsung Download/Odin mode flasher)…"
  if pm_has apt-get;  then sudo_ apt-get install -y heimdall-flash || true; fi
  if pm_has dnf;      then sudo_ dnf install -y heimdall || true; fi
  if pm_has pacman;   then sudo_ pacman -S --noconfirm heimdall || true; fi
  if pm_has zypper;   then sudo_ zypper -n in -y heimdall || true; fi
fi

if [[ "$INSTALL_P7ZIP" -eq 1 ]]; then
  msg "Installing 7zip/p7zip (unpack Odin tar.md5)…"
  if pm_has apt-get;  then sudo_ apt-get install -y p7zip-full || true; fi
  if pm_has dnf;      then sudo_ dnf install -y p7zip p7zip-plugins || true; fi
  if pm_has pacman;   then sudo_ pacman -S --noconfirm p7zip || true; fi
  if pm_has zypper;   then sudo_ zypper -n in -y p7zip-full || sudo_ zypper -n in -y p7zip || true; fi
fi

if [[ "$INSTALL_PAYLOAD_DUMPER" -eq 1 ]]; then
  msg "Installing payload-dumper-go (extract Pixel OTA payload.bin)…"
  # fetch latest release tag and Linux x86_64 asset
  if is_cmd jq; then :; else
    if pm_has apt-get; then sudo_ apt-get install -y jq || true; elif pm_has dnf; then sudo_ dnf install -y jq || true; elif pm_has pacman; then sudo_ pacman -S --noconfirm jq || true; elif pm_has zypper; then sudo_ zypper -n in -y jq || true; fi
  fi
  API="https://api.github.com/repos/ssut/payload-dumper-go/releases/latest"
  tag="$(curl -fsSL "$API" | jq -r .tag_name 2>/dev/null || echo latest)"
  url="$(curl -fsSL "$API" | jq -r '.assets[] | select(.name|test("linux.*amd64|linux.*x86_64")) | .browser_download_url' | head -n1 || true)"
  if [[ -n "$url" ]]; then
    tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
    curl -fL --retry 3 -o "$tmpd/pdg.tar.gz" "$url"
    mkdir -p "$HOME/.local/bin"
    tar -xzf "$tmpd/pdg.tar.gz" -C "$HOME/.local/bin" || true
    chmod +x "$HOME/.local/bin"/payload-dumper-go* 2>/dev/null || true
    # create stable name
    if ls "$HOME/.local/bin"/payload-dumper-go* >/dev/null 2>&1; then
      ln -sf "$(ls "$HOME/.local/bin"/payload-dumper-go* | head -n1)" "$HOME/.local/bin/payload-dumper-go"
      case ":$PATH:" in *":$HOME/.local/bin:"*) :;; *) echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"; export PATH="$HOME/.local/bin:$PATH";; esac
    fi
  else
    warn "Could not fetch payload-dumper-go release (GitHub API?)."
  fi
fi

# --------------------------- Reset ADB keys & start server --------------------
msg "Resetting ADB host keys (clean RSA pairing)…"
pkill -x adb 2>/dev/null || true
"$PT_DIR/adb" kill-server 2>/dev/null || true
rm -f "$HOME/.android/adbkey" "$HOME/.android/adbkey.pub" 2>/dev/null || true
mkdir -p "$HOME/.android" && chmod 700 "$HOME/.android"

msg "Starting user-owned adb server…"
"$PT_DIR/adb" start-server >/dev/null

# --------------------------- Pair a device & create 'adbx' --------------------
msg "Unlock your phone, enable USB debugging, plug USB (MTP/File Transfer), and ACCEPT the RSA prompt."
SERIAL=""
for _ in {1..25}; do
  line=$("$PT_DIR/adb" devices -l | sed -n '2p' || true)
  if echo "$line" | grep -q "device "; then
    SERIAL="$(echo "$line" | awk '{print $1}')"
    break
  fi
  sleep 1
done
[[ -n "$SERIAL" ]] || { "$PT_DIR/adb" devices -l || true; err "No authorized device detected. Reconnect & re-run."; }

STATE="$("$PT_DIR/adb" -s "$SERIAL" get-state 2>/dev/null || true)"
[[ "$STATE" == "device" ]] || err "Selected device '$SERIAL' not ready (state='$STATE')."

msg "Authorized: $SERIAL (adb get-state: $STATE)"

if [[ "$MAKE_ADBX" -eq 1 ]]; then
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/adbx" <<EOF
#!/usr/bin/env bash
exec "$PT_DIR/adb" -s "$SERIAL" "\$@"
EOF
  chmod +x "$HOME/.local/bin/adbx"
  case ":$PATH:" in *":$HOME/.local/bin:"*) :;; *) echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"; export PATH="$HOME/.local/bin:$PATH";; esac
  msg "Wrapper created: adbx (bound to $SERIAL). Try:  adbx shell"
fi

# --------------------------- Final sanity -------------------------------------
msg "adb: $("$PT_DIR/adb" version | head -n1)"
if is_cmd fastboot; then msg "fastboot: $(fastboot --version | head -n1 2>/dev/null || true)"; else msg "fastboot is in $PT_DIR (PATH updated)."; fi
if is_cmd heimdall; then msg "heimdall: $(heimdall version 2>/dev/null || echo 'installed')"; fi
if is_cmd payload-dumper-go; then msg "payload-dumper-go: $(payload-dumper-go --version 2>/dev/null || echo 'installed')"; fi

echo; msg "All set. Open a NEW terminal (or 'source ~/.bashrc') so PATH/group changes apply."
echo "Tips:"
echo "  - Pixel flashing: fastboot + factory images (flash-all.sh) or Android Flash Tool. (Bootloader unlock wipes data.)"
echo "  - Samsung flashing: use Heimdall in Download mode (Odin equivalent on Linux)."
echo "  - Pixel OTAs: use 'payload-dumper-go' to extract partitions from payload.bin when needed."
exit 0
