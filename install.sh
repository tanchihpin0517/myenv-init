#!/usr/bin/env bash
#
# install.sh - Installer for the 'myenv' CLI.
#
# Tasks:
# 1. Prompts for or loads a saved GitHub personal access token (~/.myenv-rs/config/token).
# 2. Detects host OS (Linux, macOS) and architecture (x86_64, arm64).
# 3. Fetches the latest 'myenv-rs' release details via the GitHub API.
# 4. Downloads the matching platform archive (.tar.gz) using its asset ID.
# 5. Extracts and installs the 'myenv' binary to ~/.myenv-rs/bin/.
# 6. Downloads the assets bundle (registry.toml + formulas/) and extracts to ~/.myenv-rs/.
# 7. Symlinks the binary to ~/.local/bin/.
# 8. Stores the GitHub token with read-only permissions.
#
# File structure:
#   ~/.myenv-rs/
#   ├── bin/
#   │   └── myenv           # Installed CLI binary
#   ├── config/
#   │   └── token           # GitHub access token (read-only)
#   ├── registry.toml       # Formula dependency graph
#   └── formulas/           # Per-formula Lua scripts
#
# Usage:
#   ./install.sh
#

set -euo pipefail

OWNER="tanchihpin0517"
REPO="myenv-rs"
BIN_NAME="myenv"
INSTALL_ROOT="${HOME}/.myenv-rs"
BIN_DIR="${INSTALL_ROOT}/bin"
LOCAL_BIN="${HOME}/.local/bin"
CONFIG_DIR="${INSTALL_ROOT}/config"
TOKEN_FILE="${CONFIG_DIR}/token"

TMP_DIR=""

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

TOKEN_LOADED=false

load_token() {
    if [ -f "$TOKEN_FILE" ] && [ -r "$TOKEN_FILE" ]; then
        IFS= read -r GITHUB_TOKEN < "$TOKEN_FILE" || true
        GITHUB_TOKEN="${GITHUB_TOKEN//$'\r'/}"
        GITHUB_TOKEN="${GITHUB_TOKEN//$'\n'/}"
        if [ -n "$GITHUB_TOKEN" ]; then
            TOKEN_LOADED=true
            echo "Using saved token from $TOKEN_FILE"
            return
        fi
    fi

    if [ ! -e /dev/tty ]; then
        echo "Error: no saved token found and no terminal available." >&2
        exit 1
    fi

    printf "GitHub token (Releases read-only for %s/%s): " "$OWNER" "$REPO" >/dev/tty
    stty -echo </dev/tty
    IFS= read -r GITHUB_TOKEN </dev/tty
    stty echo </dev/tty
    printf "\n" >/dev/tty

    if [ -z "$GITHUB_TOKEN" ]; then
        echo "Error: token cannot be empty." >&2
        exit 1
    fi
}

load_token

download_release_asset() {
    local file_name="$1"
    local dest_path="$2"
    local asset_id

    asset_id="$(echo "$RELEASE_JSON" | \
      grep -B 2 "\"name\": \"$file_name\"" | \
      grep '"id":' | \
      sed -E 's/.*"id": ([0-9]+),.*/\1/')"

    if [ -z "$asset_id" ]; then
        echo "Error: could not find asset ID for $file_name." >&2
        return 1
    fi

    echo "Downloading $file_name ..."
    curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
         -H "Accept: application/octet-stream" \
         "https://api.github.com/repos/$OWNER/$REPO/releases/assets/$asset_id" \
         -o "$dest_path"
}

echo "=== Installing $BIN_NAME ==="

# Detect OS and architecture (target triple)
OS="$(uname -s)"
ARCH="$(uname -m)"

if [ "$OS" = "Linux" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        TARGET="x86_64-unknown-linux-gnu"
    else
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
    fi
    EXT="tar.gz"
elif [ "$OS" = "Darwin" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        TARGET="x86_64-apple-darwin"
    elif [ "$ARCH" = "arm64" ]; then
        TARGET="aarch64-apple-darwin"
    else
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
    fi
    EXT="tar.gz"
else
    echo "This script supports Linux and macOS only. On Windows, download the release zip directly." >&2
    exit 1
fi

# Fetch latest release info from GitHub API
echo "Fetching latest release info from GitHub..."
RELEASE_JSON="$(curl -fsS -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/releases/latest")"

LATEST_VERSION="$(echo "$RELEASE_JSON" | \
  grep '"tag_name":' | head -1 | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')"

if [ -z "$LATEST_VERSION" ]; then
    echo "Could not fetch latest version. Check your token and repository name." >&2
    exit 1
fi

echo "Latest version: $LATEST_VERSION"

# Resolve platform-specific archive and download via asset ID
STAGING_DIR="${BIN_NAME}-${LATEST_VERSION}-${TARGET}"
FILE_NAME="${STAGING_DIR}.${EXT}"
ASSETS_FILE_NAME="myenv-assets-${LATEST_VERSION}.tar.gz"
BINARY_PATH=""

TMP_DIR="$(mktemp -d)"

download_release_asset "$FILE_NAME" "$TMP_DIR/$FILE_NAME"

echo "Extracting and installing to $BIN_DIR ..."
tar -xzf "$TMP_DIR/$FILE_NAME" -C "$TMP_DIR"

if [ -f "$TMP_DIR/$STAGING_DIR/$BIN_NAME" ]; then
    BINARY_PATH="$TMP_DIR/$STAGING_DIR/$BIN_NAME"
elif [ -f "$TMP_DIR/$BIN_NAME" ]; then
    BINARY_PATH="$TMP_DIR/$BIN_NAME"
else
    echo "Could not find $BIN_NAME in the downloaded archive." >&2
    exit 1
fi

mkdir -p "$BIN_DIR" "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

install -m 755 "$BINARY_PATH" "$BIN_DIR/$BIN_NAME"

echo "Installing formula bundle to $INSTALL_ROOT ..."
download_release_asset "$ASSETS_FILE_NAME" "$TMP_DIR/$ASSETS_FILE_NAME"
rm -rf "$INSTALL_ROOT/formulas"
tar -xzf "$TMP_DIR/$ASSETS_FILE_NAME" -C "$INSTALL_ROOT" --strip-components=1

mkdir -p "$LOCAL_BIN"
rm -f "$LOCAL_BIN/$BIN_NAME"
ln -s "$BIN_DIR/$BIN_NAME" "$LOCAL_BIN/$BIN_NAME"

if [ "$TOKEN_LOADED" = true ]; then
    chmod 600 "$TOKEN_FILE"
else
    printf '%s\n' "$GITHUB_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
fi

echo "=== Installation complete! ==="
echo "Binary:   $BIN_DIR/$BIN_NAME"
echo "Registry: $INSTALL_ROOT/registry.toml"
echo "Formulas: $INSTALL_ROOT/formulas/"
echo "Link:     $LOCAL_BIN/$BIN_NAME"
echo "Token:    $TOKEN_FILE"
if [[ ":${PATH}:" == *":${LOCAL_BIN}:"* ]]; then
    echo "Run: $BIN_NAME --version"
else
    echo "Add to PATH: export PATH=\"$LOCAL_BIN:\$PATH\""
    echo "Run: $BIN_NAME --version"
fi
