#!/bin/bash
set -e

# PATH for systemd (claude, uv, npx, node)
export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | tail -1)/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Paths — auto-detect from script location
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_DIR="$PROJECT_DIR/vault"
ENV_FILE="$PROJECT_DIR/.env"

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# Check token
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo "ERROR: TELEGRAM_BOT_TOKEN not set"
    exit 1
fi

# Timezone (configure in .env: TZ=Your/Timezone)
export TZ="${TZ:-UTC}"

# Date and chat_id
# $1 can be: a date "YYYY-MM-DD", literal "yesterday", or empty (= today).
# Used by catchup service to re-process yesterday's daily for late entries.
if [ "$1" = "yesterday" ]; then
    TODAY=$(date -d yesterday +%Y-%m-%d)
elif [ -n "$1" ]; then
    TODAY="$1"
else
    TODAY=$(date +%Y-%m-%d)
fi
CHAT_ID="${ALLOWED_USER_IDS//[\[\]]/}"  # remove brackets from [123456]

echo "=== Gaal processing for $TODAY ==="

# ── ORIENT PHASE: pre-flight checks ──
DAILY_FILE="$VAULT_DIR/daily/$TODAY.md"
HANDOFF_FILE="$VAULT_DIR/.session/handoff.md"
GRAPH_FILE="$VAULT_DIR/.graph/vault-graph.json"

# Check daily file exists and has content
if [ ! -f "$DAILY_FILE" ]; then
    echo "ORIENT: daily/$TODAY.md not found — creating empty file"
    echo "# $TODAY" > "$DAILY_FILE"
fi

DAILY_SIZE=$(wc -c < "$DAILY_FILE" 2>/dev/null || echo "0")
if [ "$DAILY_SIZE" -lt 50 ]; then
    echo "ORIENT: daily/$TODAY.md is empty ($DAILY_SIZE bytes) — skipping Claude processing"
    echo "ORIENT: Running graph rebuild only"

    # Still rebuild graph and commit
    cd "$VAULT_DIR"
    uv run .claude/skills/graph-builder/scripts/analyze.py || echo "Graph rebuild failed (non-critical)"
    cd "$PROJECT_DIR"

    git add -A
    git commit -m "chore: process daily $TODAY" || true
    git push || true
    echo "=== Done (empty daily, graph-only) ==="
    exit 0
fi

# Check handoff exists
if [ ! -f "$HANDOFF_FILE" ]; then
    echo "ORIENT: handoff.md not found — creating stub"
    mkdir -p "$VAULT_DIR/.session"
    echo -e "---\nupdated: $(date -Iseconds)\n---\n\n## Last Session\n(none)\n\n## Observations" > "$HANDOFF_FILE"
fi

# Check graph freshness (warn if >7 days old)
if [ -f "$GRAPH_FILE" ]; then
    GRAPH_AGE=$(( ($(date +%s) - $(stat -c %Y "$GRAPH_FILE" 2>/dev/null || stat -f %m "$GRAPH_FILE" 2>/dev/null || echo 0)) / 86400 ))
    if [ "$GRAPH_AGE" -gt 7 ]; then
        echo "ORIENT: vault-graph.json is $GRAPH_AGE days old (>7)"
    fi
fi

echo "ORIENT: daily=$DAILY_SIZE bytes, handoff=OK, graph=OK"
# ── END ORIENT PHASE ──

# MCP timeout for stdio server (default 5 sec is too short)
export MCP_TIMEOUT=30000
export MAX_MCP_OUTPUT_TOKENS=50000

# ── 3-PHASE PIPELINE ──
# Phase 1: CAPTURE (classify entries → JSON)
# Phase 2: EXECUTE (create tasks, save thoughts → JSON)
# Phase 3: REFLECT (generate HTML report, update MEMORY)
# Each phase = fresh Claude context for better quality.

SESSION_DIR="$VAULT_DIR/.session"
mkdir -p "$SESSION_DIR"
CAPTURE_FILE="$SESSION_DIR/capture.json"
EXECUTE_FILE="$SESSION_DIR/execute.json"

# Find yearly goals file (auto-detect year)
YEARLY_GOALS=$(ls "$VAULT_DIR/goals/1-yearly-"*.md 2>/dev/null | tail -1)
YEARLY_GOALS_NAME=$(basename "$YEARLY_GOALS" 2>/dev/null || echo "1-yearly.md")

# MCP config (needed for Phase 2)
MCP_PROMPT="CRITICAL: MCP loads in 10-30 seconds. You are NOT in subprocess.
Algorithm: 1) Call. 2) Error? Wait 10 sec. 3) Call again. 4) Wait 20 sec. 5) Call — GUARANTEED to work.
DO NOT say MCP unavailable. It is available. Just wait and call."

cd "$VAULT_DIR"

# ── Phase 1: CAPTURE ──
echo "=== Phase 1: CAPTURE ==="
CAPTURE=$(timeout 1200 claude --print --dangerously-skip-permissions --output-format json \
    -p "Today is $TODAY. Read .claude/skills/dbrain-processor/phases/capture.md and execute Phase 1.
Read daily/$TODAY.md, goals/3-weekly.md, goals/2-monthly.md, goals/$YEARLY_GOALS_NAME.
Classify each entry. Return ONLY JSON." \
    | python3 "$PROJECT_DIR/scripts/log_usage.py" capture) || true

# Extract JSON from output (устойчив к многострочному JSON и code fences)
echo "$CAPTURE" | python3 "$PROJECT_DIR/scripts/extract_json.py" > "$CAPTURE_FILE" 2>/dev/null \
    || echo '{"error": "failed to parse capture output"}' > "$CAPTURE_FILE"

echo "Capture saved: $(wc -c < "$CAPTURE_FILE") bytes"

# Check if capture produced valid entries
if grep -q '"error"' "$CAPTURE_FILE"; then
    echo "WARN: Capture phase had issues, falling back to monolith mode"
    # Fallback to monolith processing
    REPORT=$(timeout 1200 claude --print --dangerously-skip-permissions --output-format json \
        --mcp-config "$PROJECT_DIR/mcp-config.json" \
        -p "Today is $TODAY. Execute daily processing according to dbrain-processor skill.
$MCP_PROMPT" \
        | python3 "$PROJECT_DIR/scripts/log_usage.py" monolith) || true
else
    # ── Phase 2: EXECUTE ──
    echo "=== Phase 2: EXECUTE ==="
    EXECUTE=$(timeout 1200 claude --print --dangerously-skip-permissions --output-format json \
        --mcp-config "$PROJECT_DIR/mcp-config.json" \
        -p "Today is $TODAY. Read .claude/skills/dbrain-processor/phases/execute.md and execute Phase 2.
Read .session/capture.json for input data.
Read business/_index.md and projects/_index.md for context.
Create tasks in Todoist, save thoughts, update CRM. Return ONLY JSON.
$MCP_PROMPT" \
        | python3 "$PROJECT_DIR/scripts/log_usage.py" execute) || true

    echo "$EXECUTE" | python3 "$PROJECT_DIR/scripts/extract_json.py" > "$EXECUTE_FILE" 2>/dev/null \
        || echo '{"error": "failed to parse execute output"}' > "$EXECUTE_FILE"

    echo "Execute saved: $(wc -c < "$EXECUTE_FILE") bytes"

    # ── Phase 3: REFLECT ──
    echo "=== Phase 3: REFLECT ==="
    REPORT=$(timeout 1200 claude --print --dangerously-skip-permissions --output-format json \
        -p "Today is $TODAY. Read .claude/skills/dbrain-processor/phases/reflect.md and execute Phase 3.
Read .session/capture.json and .session/execute.json for input data.
Read MEMORY.md, .session/handoff.md, .graph/health-history.json.
Generate HTML report, update MEMORY, record observations.
Return ONLY RAW HTML (for Telegram)." \
        | python3 "$PROJECT_DIR/scripts/log_usage.py" reflect) || true
fi

cd "$PROJECT_DIR"

echo "=== Claude output ==="
echo "$REPORT"
echo "===================="

# Remove HTML comments (break Telegram HTML parser)
REPORT_CLEAN=$(echo "$REPORT" | sed '/<!--/,/-->/d')

# Rebuild vault graph (keeps structure up to date)
echo "=== Rebuilding vault graph ==="
cd "$VAULT_DIR"
uv run .claude/skills/graph-builder/scripts/analyze.py || echo "Graph rebuild failed (non-critical)"

# Memory decay (update relevance scores and tiers)
echo "=== Memory decay ==="
uv run .claude/skills/agent-memory/scripts/memory-engine.py decay . || echo "Memory decay failed (non-critical)"
cd "$PROJECT_DIR"

# Git commit
git add -A
git commit -m "chore: process daily $TODAY" || true
git push || true

# Send to Telegram
if [ -n "$REPORT_CLEAN" ] && [ -n "$CHAT_ID" ]; then
    echo "=== Sending to Telegram ==="
    RESULT=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$CHAT_ID" \
        -d "text=$REPORT_CLEAN" \
        -d "parse_mode=HTML")

    # If HTML failed, send without formatting
    if echo "$RESULT" | grep -q '"ok":false'; then
        echo "HTML failed: $RESULT"
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "chat_id=$CHAT_ID" \
            -d "text=$REPORT_CLEAN"
    fi
fi

echo "=== Done ==="
