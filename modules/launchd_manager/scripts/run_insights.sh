#!/bin/bash

# Weekly: run Claude Code's /insights and upload the generated report.
#
# The SSH host, key and remote directory used to be hardcoded here. They were
# internal infrastructure in a PUBLIC repo, and the stale .gitignore pattern that
# was supposed to keep such things out had silently stopped matching (see
# .gitignore). They now come from insights.env, which is gitignored, and the
# script HARD FAILS when it is missing rather than defaulting -- a default would
# quietly ship a usage report somewhere it does not belong.

set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

DATE=$(date +%Y%m%d)
LOG="$HOME/Library/Logs/insight_reporter.log"
CLAUDE="/opt/homebrew/bin/claude"
ENV_FILE="${INSIGHTS_ENV:-$HOME/.hammerspoon/insights.env}"

mkdir -p "$(dirname "$LOG")"
echo "--- Insight started at $(date) ---" >> "$LOG"

notify() {
    osascript -e "display notification \"$1\" with title \"Insight Reporter\""
}

if [ ! -r "$ENV_FILE" ]; then
    echo "ERROR: config not readable: $ENV_FILE (copy insights.env.example)" >> "$LOG"
    notify "config missing, run skipped."
    exit 1
fi
# shellcheck source=/dev/null
. "$ENV_FILE"

for var in INSIGHTS_SSH_HOST INSIGHTS_SSH_KEY INSIGHTS_REMOTE_DIR; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: $var unset in $ENV_FILE" >> "$LOG"
        notify "config incomplete ($var), run skipped."
        exit 1
    fi
done

# Run built-in /insights and extract the report path it printed.
CLAUDE_OUTPUT=$("$CLAUDE" -p "/insights" 2>&1)
echo "$CLAUDE_OUTPUT" >> "$LOG"

REPORT=$(echo "$CLAUDE_OUTPUT" | grep -oE 'file://[^ ]+\.html' | sed 's|^file://||' | head -n 1)

if [ -z "$REPORT" ] || [ ! -s "$REPORT" ]; then
    echo "ERROR: report html not found or empty, aborting upload." >> "$LOG"
    notify "report html missing, upload skipped."
    exit 1
fi

REMOTE_FILE="$INSIGHTS_REMOTE_DIR/${DATE}_report.html"
REMOTE="$INSIGHTS_SSH_HOST:$REMOTE_FILE"

# An array, not a string: the old unquoted $SSH_OPTS relied on word splitting and
# would have broken on any path containing a space.
SSH_OPTS=(
    -i "$INSIGHTS_SSH_KEY"
    -o ConnectTimeout=10
    -o TCPKeepAlive=yes
    -o ServerAliveInterval=10
    -o ServerAliveCountMax=5
    -o StrictHostKeyChecking=accept-new
)
MAX_ATTEMPTS=5
SCP_STATUS=1

# Pre-flight check: verify SSH connectivity before attempting upload
echo "Pre-flight connectivity check at $(date)" >> "$LOG"
if ! ssh "${SSH_OPTS[@]}" "$INSIGHTS_SSH_HOST" "exit 0" >> "$LOG" 2>&1; then
    echo "WARNING: Initial connectivity check failed, waiting 30s before retry..." >> "$LOG"
    sleep 30
fi

# Exponential backoff retry strategy: 15s, 60s, 180s, 300s
BACKOFF_TIMES=(15 60 180 300)

for ATTEMPT in $(seq 1 $MAX_ATTEMPTS); do
    echo "Upload attempt $ATTEMPT/$MAX_ATTEMPTS at $(date)" >> "$LOG"
    scp "${SSH_OPTS[@]}" "$REPORT" "$REMOTE" >> "$LOG" 2>&1
    SCP_STATUS=$?
    if [ $SCP_STATUS -eq 0 ]; then
        break
    fi
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        WAIT_TIME=${BACKOFF_TIMES[$((ATTEMPT - 1))]}
        echo "Attempt $ATTEMPT failed (exit $SCP_STATUS), retrying in ${WAIT_TIME}s..." >> "$LOG"
        sleep "$WAIT_TIME"
    fi
done

if [ $SCP_STATUS -eq 0 ]; then
    # 644, NOT 777. The report is served by a web server that only needs to READ
    # it; 777 let every account on that host rewrite the page (stored XSS on an
    # internal site) for no benefit at all.
    ssh "${SSH_OPTS[@]}" "$INSIGHTS_SSH_HOST" \
        "chmod 644 '$REMOTE_FILE'" >> "$LOG" 2>&1
    echo "Upload success: $REMOTE (after $ATTEMPT attempt(s))" >> "$LOG"
    notify "Report uploaded: ${DATE}"
else
    echo "Upload failed after $MAX_ATTEMPTS attempts: scp exit code $SCP_STATUS" >> "$LOG"
    notify "Upload failed after $MAX_ATTEMPTS attempts (exit $SCP_STATUS)."
fi

echo "--- Finished at $(date) ---" >> "$LOG"
