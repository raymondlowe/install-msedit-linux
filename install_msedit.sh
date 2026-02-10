#!/bin/sh
set -e

# GitHub repo info
REPO="microsoft/edit"

# Directory to install the binary
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)
        ARCH_KEY="x86_64" ;;
    aarch64|arm64)
        ARCH_KEY="aarch64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Get latest release info from GitHub API
RELEASE_JSON=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
LATEST_TAG=$(echo "$RELEASE_JSON" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)

if [ -z "$LATEST_TAG" ]; then
  echo "Failed to fetch the latest release version."
  exit 1
fi

echo "Latest version detected: $LATEST_TAG"

# Robustly find the correct asset download URL for this architecture and OS
# This works even if asset names change format, as long as arch and linux are present somewhere

# Try to find the correct asset as before
ASSET_URL=""
ASSET_NAME=""
echo "$RELEASE_JSON" | awk -v arch="$ARCH_KEY" '
  BEGIN { in_assets=0; name=""; url=""; found=0; }
  /"assets": \[/ { in_assets=1; next }
  in_assets && /"name":/ {
    # Extract name using gsub - more portable than match with array
    name = $0;
    gsub(/.*"name": "/, "", name);
    gsub(/".*/, "", name);
  }
  in_assets && /"browser_download_url":/ {
    # Extract URL using gsub - more portable than match with array
    url = $0;
    gsub(/.*"browser_download_url": "/, "", url);
    gsub(/".*/, "", url);
    if (name ~ arch && name ~ /linux/ && name ~ /(xz|gz|tar.gz|AppImage|zip|bz2|tar|tar.zst)$/) {
      print url;
      found=1;
      exit;
    }
  }
  in_assets && /\]/ { in_assets=0 }
' > .asset_url.tmp
ASSET_URL=$(cat .asset_url.tmp)
rm -f .asset_url.tmp
if [ -n "$ASSET_URL" ]; then
  ASSET_NAME=$(basename "$ASSET_URL")
else
  echo "Could not find a suitable download for architecture $ARCH_KEY."
  exit 1
fi

echo "Downloading $ASSET_NAME from $ASSET_URL..."

# Check if edit is already installed and up-to-date
if command -v "$INSTALL_DIR/edit" >/dev/null 2>&1; then
  INSTALLED_VERSION=`"$INSTALL_DIR/edit" --version 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9.]*\).*/\1/p' | head -n 1`
  LATEST_VERSION=`echo "$LATEST_TAG" | sed 's/^v//'`
  if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
    echo "edit $INSTALLED_VERSION is already installed and up-to-date."
    exit 0
  else
    echo "edit $INSTALLED_VERSION is installed, but $LATEST_VERSION is available. Updating..."
  fi
fi

# Download the asset
TMP_FILE=`mktemp`
HTTP_STATUS=`curl -w "%{http_code}" -L -o "$TMP_FILE" "$ASSET_URL"`
if [ "$HTTP_STATUS" != "200" ]; then
  echo "Failed to download $ASSET_NAME (HTTP status $HTTP_STATUS)."
  rm -f "$TMP_FILE"
  exit 1
fi

# Check file size (should be more than a few KB)
FILESIZE=`ls -l "$TMP_FILE" | awk '{print $5}'`
if [ ! -s "$TMP_FILE" ] || [ "$FILESIZE" -lt 10000 ]; then
  echo "Downloaded file is too small or empty. Download may have failed."
  rm -f "$TMP_FILE"
  exit 1
fi

# Extract or move to install directory

# Handle .tar.zst and other archive types
EXT="${ASSET_NAME##*.}"
EXTRACTED_FILE=`mktemp`
if [ "$ASSET_NAME" != "" ] && echo "$ASSET_NAME" | grep -q "tar.zst$"; then
  # .tar.zst: decompress and extract the binary file from the archive
  if command -v unzstd >/dev/null 2>&1; then
    BIN_PATH=$(tar --use-compress-program=unzstd -tf "$TMP_FILE" | grep '/edit$' | head -n1)
    if [ -z "$BIN_PATH" ]; then
      BIN_PATH=$(tar --use-compress-program=unzstd -tf "$TMP_FILE" | grep '^edit$' | head -n1)
    fi
    if [ -n "$BIN_PATH" ]; then
      tar --use-compress-program=unzstd -xOf "$TMP_FILE" "$BIN_PATH" > "$EXTRACTED_FILE"
    else
      echo "Could not find a suitable 'edit' binary in tar.zst archive." >&2
      rm -f "$TMP_FILE" "$EXTRACTED_FILE"
      exit 1
    fi
  elif command -v zstd >/dev/null 2>&1; then
    BIN_PATH=$(zstd -d < "$TMP_FILE" | tar -tf - | grep '/edit$' | head -n1)
    if [ -z "$BIN_PATH" ]; then
      BIN_PATH=$(zstd -d < "$TMP_FILE" | tar -tf - | grep '^edit$' | head -n1)
    fi
    if [ -n "$BIN_PATH" ]; then
      zstd -d < "$TMP_FILE" | tar -xOf - "$BIN_PATH" > "$EXTRACTED_FILE"
    else
      echo "Could not find a suitable 'edit' binary in tar.zst archive (zstd fallback)." >&2
      rm -f "$TMP_FILE" "$EXTRACTED_FILE"
      exit 1
    fi
  else
    echo "Neither unzstd nor zstd found for extracting .tar.zst archives." >&2
    echo "Please install zstd (e.g., 'sudo apt install zstd' or 'sudo dnf install zstd') and try again." >&2
    rm -f "$TMP_FILE" "$EXTRACTED_FILE"
    exit 1
  fi
elif [ "$EXT" = "xz" ]; then
  if unxz -c "$TMP_FILE" > "$EXTRACTED_FILE"; then
    :
  else
    echo "Failed to extract the binary. The downloaded file may be corrupt."
    rm -f "$TMP_FILE" "$EXTRACTED_FILE"
    exit 1
  fi
elif [ "$EXT" = "gz" ] || [ "$EXT" = "tgz" ]; then
  if tar -xOzf "$TMP_FILE" 2>/dev/null | head -c 1 | grep . >/dev/null; then
    tar -xOzf "$TMP_FILE" > "$EXTRACTED_FILE"
  else
    echo "Failed to extract the binary from tar.gz archive."
    rm -f "$TMP_FILE" "$EXTRACTED_FILE"
    exit 1
  fi
elif [ "$EXT" = "AppImage" ] || [ "$EXT" = "zip" ] || [ "$EXT" = "bz2" ] || [ "$EXT" = "tar" ]; then
  mv "$TMP_FILE" "$EXTRACTED_FILE"
else
  mv "$TMP_FILE" "$EXTRACTED_FILE"
fi

if [ ! -s "$EXTRACTED_FILE" ]; then
  echo "Extraction produced an empty file. The downloaded file may be corrupt."
  rm -f "$EXTRACTED_FILE"
  exit 1
fi
mv "$EXTRACTED_FILE" "$INSTALL_DIR/edit"
chmod +x "$INSTALL_DIR/edit"

# Clean up
rm -f "$TMP_FILE"

# Add install dir to PATH if not already present
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
  echo "Adding $INSTALL_DIR to PATH in ~/.profile"
  echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> ~/.profile
  echo "Please reload your shell or run: source ~/.profile"
fi

# Optionally set as default 'edit' command
if [ "$1" = "--set-default" ]; then
  mkdir -p "$HOME/bin"
  ln -sf "$INSTALL_DIR/edit" "$HOME/bin/edit"
  echo "Microsoft 'edit' is now set as your default 'edit' command via symlink at ~/bin/edit."
  echo "Make sure ~/bin is in your PATH (add 'export PATH=\"$HOME/bin:$PATH\"' to your ~/.profile if needed)."
  echo "To undo and restore your previous default 'edit', run: rm ~/bin/edit"
else
  echo "Installation complete. Microsoft 'edit' is installed at $INSTALL_DIR/edit."
  echo "Note: This may not be the default 'edit' if another 'edit' is earlier in your PATH (e.g., /usr/bin/edit)."
  echo "To make Microsoft 'edit' the default, run:"
  echo "  sh install_msedit.sh --set-default"
  echo "To undo and restore your previous default 'edit', run: rm ~/bin/edit"
fi

# Detect if running from a pipe (not a file)
if [ -p /dev/stdin ]; then
  INSTALL_CMD="curl -sSL https://github.com/microsoft/edit/raw/main/install_msedit.sh | sh -s -- --set-default"
  echo "To make Microsoft 'edit' the default, run:"
  echo "  $INSTALL_CMD"
  echo "To undo and restore your previous default 'edit', run: rm ~/bin/edit"
fi

echo "Run 'edit --version' to verify."

# After install, check for glibc compatibility if possible
if command -v "$INSTALL_DIR/edit" >/dev/null 2>&1; then
  GLIBC_ERR_MSG=$("$INSTALL_DIR/edit" --version 2>&1 | grep 'GLIBC_' || true)
  if [ -n "$GLIBC_ERR_MSG" ]; then
    echo "\nERROR: The Microsoft 'edit' binary requires a newer version of glibc than is available on your system." >&2
    echo "You may need to upgrade your Linux distribution to use this binary." >&2
    echo "Details:" >&2
    echo "$GLIBC_ERR_MSG" >&2
  fi
fi

