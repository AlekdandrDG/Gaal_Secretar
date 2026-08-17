#!/bin/bash
# Send a one-line alert to the admin Telegram chat. Standalone (only needs
# curl + .env), so it works as a systemd OnFailure handler even when the bot
# is down. Usage: notify.sh "message"
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
# Last-resort alert handler: a malformed .env line must not abort us before
# curl. Drop errexit around the load.
if [ -f "$ENV_FILE" ]; then
    set +e
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE" 2>/dev/null
    set +a
    set -e
fi

MSG="${1:-Gaal alert}"
CHAT_ID="${ALLOWED_USER_IDS//[\[\] ]/}"  # strip brackets/spaces
CHAT_ID="${CHAT_ID%%,*}"                  # first id only

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "$CHAT_ID" ]; then
    echo "notify: missing token or chat id" >&2
    exit 0
fi

# Debounce identical alerts: a crash-loop must not spam Telegram. Keyed by
# message text so distinct faults still alert independently.
RUNTIME_DIR="${DBRAIN_RUNTIME_DIR:-$PROJECT_DIR/.runtime}"
COOLDOWN="${DBRAIN_NOTIFY_COOLDOWN:-1800}"  # seconds (30 min)
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
STAMP="$RUNTIME_DIR/notify.$(printf '%s' "$MSG" | cksum | cut -d' ' -f1).stamp"
NOW=$(date +%s)
LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
case "$LAST" in *[!0-9]*) LAST=0 ;; esac
if [ "$((NOW - LAST))" -lt "$COOLDOWN" ]; then
    exit 0  # within cooldown — stay silent
fi
echo "$NOW" >"$STAMP" 2>/dev/null || true

curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID" -d "text=$MSG" >/dev/null || true
