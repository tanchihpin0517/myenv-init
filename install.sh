#!/usr/bin/env bash
#
# install.sh - Bootstrap installer for 'myenv' CLI tool.
#
# Tasks:
# 1. Prompts for or loads a saved GitHub access token.
# 2. Detects host OS and architecture.
# 3. Fetches the release information via the GitHub API.
# 4. Saves the GitHub access token (~/.myenv/config/token).
# 5. Downloads the platform binary archive (.tar.gz) using its asset ID.
# 6. Extracts and installs 'myenv' CLI binary to ~/.myenv/bin/.
# 7. Dispatches the remaining tasks to the binary via `self install`.
#
# Bootstrapped File structure before running `self install`:
#   ~/.myenv/
#   ├── bin/
#   │   └── myenv           # 'myenv' CLI binary
#   └── config/
#       └── token           # Saved GitHub access token (read-only 600)
#

set -euo pipefail

OWNER="tanchihpin0517"
REPO="myenv"
BIN_NAME="myenv"
INSTALL_ROOT="${HOME}/.myenv"
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

get_asset_digest() {
    local file_name="$1"
    echo "$RELEASE_JSON" | \
      grep -C 30 "\"name\": \"$file_name\"" | \
      grep '"digest":' | \
      sed -E 's/.*"digest": "([^"]+)".*/\1/' | head -n 1
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
    if [ "$ARCH" = "arm64" ]; then
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

# Save token after successfully verifying that it works
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
if [ "$TOKEN_LOADED" = false ]; then
    printf '%s\n' "$GITHUB_TOKEN" > "$TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"

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

mkdir -p "$BIN_DIR"

install -m 755 "$BINARY_PATH" "$BIN_DIR/$BIN_NAME"

if [ -z "${DEBUG:-}" ]; then
    echo "Bootstrapping complete myenv installation using 'self install'..."
    "$BIN_DIR/$BIN_NAME" self install
else
    echo "Debug mode: skipping 'self install' execution."
fi

