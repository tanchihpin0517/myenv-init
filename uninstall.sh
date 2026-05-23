#!/usr/bin/env bash
#
# uninstall.sh - Uninstaller for the 'myenv' CLI.
#
# Tasks:
# 1. Confirms removal of the 'myenv' CLI from the system.
# 2. Prompts whether to keep the saved GitHub token (~/.myenv-rs/config/token).
# 3. Removes the symlink from ~/.local/bin/ if it points to the managed binary.
# 4. Removes the installed binary and directories (or the entire ~/.myenv-rs folder if requested).
#
# File structure (after uninstall):
#   If keeping token:
#     ~/.myenv-rs/
#     └── config/
#         └── token      # Retained GitHub access token
#   If removing token:
#     (none - ~/.myenv-rs/ is completely removed)
#
# Usage:
#   ./uninstall.sh
#

set -euo pipefail

BIN_NAME="myenv"
INSTALL_ROOT="${HOME}/.myenv-rs"
BIN_DIR="${INSTALL_ROOT}/bin"
CONFIG_DIR="${INSTALL_ROOT}/config"
TOKEN_FILE="${CONFIG_DIR}/token"
LOCAL_BIN="${HOME}/.local/bin"
LINK_PATH="${LOCAL_BIN}/${BIN_NAME}"
BINARY_PATH="${BIN_DIR}/${BIN_NAME}"

KEEP_TOKEN=true

confirm_uninstall() {
    if [ ! -e /dev/tty ]; then
        return 0
    fi

    printf "Remove %s from this system? [Y/n] " "$BIN_NAME" >/dev/tty
    IFS= read -r answer </dev/tty
    case "$answer" in
        [nN]|[nN][oO])
            echo "Cancelled."
            exit 0
            ;;
        *) ;;
    esac
}

ask_keep_token() {
    if [ ! -f "$TOKEN_FILE" ]; then
        KEEP_TOKEN=false
        return
    fi

    if [ ! -e /dev/tty ]; then
        KEEP_TOKEN=true
        return
    fi

    printf "Keep saved GitHub token for future reinstalls? [Y/n] " >/dev/tty
    IFS= read -r answer </dev/tty
    case "$answer" in
        [nN]|[nN][oO]) KEEP_TOKEN=false ;;
        *) KEEP_TOKEN=true ;;
    esac
}

remove_path() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        rm -rf "$path"
        echo "Removed: $path"
    fi
}

echo "=== Uninstalling $BIN_NAME ==="

if [ ! -e "$INSTALL_ROOT" ] && [ ! -e "$LINK_PATH" ]; then
    echo "Nothing to uninstall."
    exit 0
fi

confirm_uninstall
ask_keep_token

if [ -L "$LINK_PATH" ]; then
    link_target="$(readlink "$LINK_PATH")"
    if [ "$link_target" = "$BINARY_PATH" ]; then
        rm -f "$LINK_PATH"
        echo "Removed: $LINK_PATH"
    else
        echo "Skipped: $LINK_PATH (not managed by this installer)"
    fi
elif [ -e "$LINK_PATH" ]; then
    echo "Skipped: $LINK_PATH (exists but is not a symlink)"
fi

if [ "$KEEP_TOKEN" = true ]; then
    remove_path "$BIN_DIR"
    if [ -f "$TOKEN_FILE" ]; then
        echo "Kept: $TOKEN_FILE"
    fi
else
    remove_path "$INSTALL_ROOT"
fi

echo "=== Uninstall complete ==="
