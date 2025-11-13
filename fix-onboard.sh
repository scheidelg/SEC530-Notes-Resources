#!/usr/bin/env bash
#
# fix-onboard.sh
# Remove old Onboard, install GitHub version into /opt/onboard,
# recreate menu entry, and apply preferred settings.
#
# Created by James Leyte-Vidal 2025.11.13

set -euo pipefail

ONBOARD_DIR="/opt/onboard"
ONBOARD_REPO="https://github.com/onboard-osk/onboard"
ONBOARD_THEME_PATH="$ONBOARD_DIR/themes/Nightshade.theme"

if [[ $EUID -eq 0 ]]; then
  echo "Please run this script as your normal user (without sudo), not as root."
  exit 1
fi

echo "=== Purging old Onboard packages (if present) ==="
for pkg in onboard onboard-common onboard-data mousetweaks; do
  if dpkg -s "$pkg" &>/dev/null; then
    echo "Purging $pkg..."
    sudo apt purge -y "$pkg"
  else
    echo "$pkg not installed, skipping."
  fi
done

echo "=== Installing build dependencies ==="
sudo apt update
sudo apt install -y \
  git build-essential python3-packaging python3-dev \
  dh-python python3-distutils-extra devscripts pkg-config \
  libgtk-3-dev libxtst-dev libxkbfile-dev libdconf-dev libcanberra-dev \
  libhunspell-dev libudev-dev

echo "=== Cloning Onboard into $ONBOARD_DIR ==="
if [[ -d "$ONBOARD_DIR" ]]; then
  echo "Removing existing $ONBOARD_DIR..."
  sudo rm -rf "$ONBOARD_DIR"
fi

sudo git clone "$ONBOARD_REPO" "$ONBOARD_DIR"
sudo chown -R "$USER":"$USER" "$ONBOARD_DIR"

echo "=== Building Onboard from source ==="
cd "$ONBOARD_DIR"
python3 setup.py clean
python3 setup.py build

echo "=== Installing Onboard system-wide ==="
sudo python3 setup.py install

echo "=== Recreating .desktop entry ==="
sudo tee /usr/share/applications/onboard.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=Onboard
GenericName=Onboard onscreen keyboard
Comment=Flexible onscreen keyboard
Exec=onboard
Terminal=false
Type=Application
Categories=Utility;Accessibility;
Keywords=onscreen;keyboard;accessibility;utility;
Icon=onboard
X-Ubuntu-Gettext-Domain=onboard
EOF

sudo chmod 644 /usr/share/applications/onboard.desktop

echo "=== Applying user settings via gsettings ==="

# Show Onboard when unlocking the screen
if gsettings list-schemas | grep -q 'org.mate.screensaver'; then
  echo "Configuring MATE screensaver keyboard..."
  gsettings set org.mate.screensaver embedded-keyboard-enabled true
  gsettings set org.mate.screensaver embedded-keyboard-command 'onboard -e'
elif gsettings list-schemas | grep -q 'org.gnome.desktop.screensaver'; then
  echo "Configuring GNOME screensaver keyboard..."
  gsettings set org.gnome.desktop.screensaver embedded-keyboard-enabled true
  gsettings set org.gnome.desktop.screensaver embedded-keyboard-command 'onboard --xid'
else
  echo "No known screensaver schema found; skipping lock-screen keyboard config."
fi

# Dock to screen edge
echo "Enabling dock-to-screen-edge..."
if gsettings list-schemas | grep -q 'org.onboard.window'; then
  gsettings set org.onboard.window docking-enabled true || true
  gsettings set org.onboard.window docking-edge 'bottom' || true
fi

# Theme: Nightshade from /opt/onboard/themes
if [[ -f "$ONBOARD_THEME_PATH" ]]; then
  echo "Setting theme to Nightshade ($ONBOARD_THEME_PATH)..."
  gsettings set org.onboard theme "$ONBOARD_THEME_PATH" || true
else
  echo "Warning: Nightshade theme not found at $ONBOARD_THEME_PATH; leaving theme unchanged."
fi

echo "=== Done. You may need to log out and back in, or restart Onboard, to see all changes. ==="

