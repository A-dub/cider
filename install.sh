#!/bin/bash
# Cider installer — downloads the latest release from GitHub
# Usage: curl -fsSL https://raw.githubusercontent.com/A-dub/cider/master/install.sh | bash

set -euo pipefail

REPO="A-dub/cider"
INSTALL_DIR="/usr/local/bin"
BINARY="cider"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  arm64)  ASSET="cider-arm64" ;;
  x86_64) ASSET="cider-x86_64" ;;
  *)      ASSET="cider" ;; # universal fallback
esac

# Get latest release tag
echo "Fetching latest release..."
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$TAG" ]; then
  echo "Error: Could not determine latest release." >&2
  exit 1
fi

URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
echo "Downloading cider $TAG ($ASSET)..."

# Download to temp file
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if ! curl -fsSL -o "$TMP" "$URL"; then
  # Fall back to universal binary
  URL="https://github.com/$REPO/releases/download/$TAG/cider"
  echo "Architecture-specific build not found, trying universal binary..."
  curl -fsSL -o "$TMP" "$URL"
fi

chmod +x "$TMP"

# Install
if [ -w "$INSTALL_DIR" ]; then
  mv "$TMP" "$INSTALL_DIR/$BINARY"
else
  echo "Installing to $INSTALL_DIR (requires sudo)..."
  sudo mv "$TMP" "$INSTALL_DIR/$BINARY"
fi

echo "Installed cider $TAG to $INSTALL_DIR/$BINARY"
"$INSTALL_DIR/$BINARY" --version

echo ""
echo "NOTE: cider needs Full Disk Access to read Apple Notes and Reminders."
echo ""
echo "  1. Open System Settings → Privacy & Security → Full Disk Access"
echo "  2. Add your terminal app (Terminal.app, iTerm, Warp, etc.)"
echo "  3. Restart your terminal"
echo ""
echo "Without this, you'll get 'Cannot access the Notes database' errors."
