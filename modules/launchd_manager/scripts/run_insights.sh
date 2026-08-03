#!/bin/bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

DATE=$(date +%Y%m%d)
REPORT="$HOME/.claude/usage-data/report.html"
LOG="$HOME/Library/Logs/insight_reporter.log"
CLAUDE="/opt/homebrew/bin/claude"

# Create log directory if not exists
mkdir -p "$(dirname "$LOG")"

echo "--- Insight started at $(date) ---" >> "$LOG"

# Run built-in /insights command and capture output to extract the actual report filename
CLAUDE_OUTPUT=$("$CLAUDE" -p "/insights" 2>&1)
echo "$CLAUDE_OUTPUT" >> "$LOG"

REPORT=$(echo "$CLAUDE_OUTPUT" | grep -oE 'file://[^ ]+\.html' | sed 's|^file://||' | head -n 1)

if [ -z "$REPORT" ] || [ ! -s "$REPORT" ]; then
    echo "ERROR: report html not found or empty, aborting upload." >> "$LOG"
    osascript -e "display notification \"report html missing, upload skipped.\" with title \"Insight Reporter\""
    exit 1
fi

# Upload report (retry up to 3 times with exponential backoff)
REMOTE="user@REDACTED-HOST:/var/www/REDACTED/${DATE}_report.html"
SSH_OPTS="-i $HOME/.ssh/REDACTED-KEY -o ConnectTimeout=10 -o TCPKeepAlive=yes -o ServerAliveInterval=10 -o ServerAliveCountMax=5 -o StrictHostKeyChecking=accept-new"
MAX_ATTEMPTS=5
SCP_STATUS=1

# Pre-flight check: verify SSH connectivity before attempting upload
echo "Pre-flight connectivity check at $(date)" >> "$LOG"
ssh $SSH_OPTS user@REDACTED-HOST "exit 0" >> "$LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "WARNING: Initial connectivity check failed, waiting 30s before retry..." >> "$LOG"
    sleep 30
fi

# Exponential backoff retry strategy: 15s, 60s, 180s, 300s
BACKOFF_TIMES=(15 60 180 300)

for ATTEMPT in $(seq 1 $MAX_ATTEMPTS); do
    echo "Upload attempt $ATTEMPT/$MAX_ATTEMPTS at $(date)" >> "$LOG"
    scp $SSH_OPTS "$REPORT" "$REMOTE" >> "$LOG" 2>&1
    SCP_STATUS=$?
    if [ $SCP_STATUS -eq 0 ]; then
        break
    fi
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        WAIT_TIME=${BACKOFF_TIMES[$((ATTEMPT - 1))]}
        echo "Attempt $ATTEMPT failed (exit $SCP_STATUS), retrying in ${WAIT_TIME}s..." >> "$LOG"
        sleep $WAIT_TIME
    fi
done

if [ $SCP_STATUS -eq 0 ]; then
    ssh $SSH_OPTS user@REDACTED-HOST "chmod 777 /var/www/REDACTED/${DATE}_report.html" >> "$LOG" 2>&1
    echo "Upload success: $REMOTE (after $ATTEMPT attempt(s))" >> "$LOG"
    osascript -e "display notification \"Report uploaded: ${DATE}\" with title \"Insight Reporter\""
else
    echo "Upload failed after $MAX_ATTEMPTS attempts: scp exit code $SCP_STATUS" >> "$LOG"
    osascript -e "display notification \"Upload failed after $MAX_ATTEMPTS attempts (exit $SCP_STATUS).\" with title \"Insight Reporter\""
fi

echo "--- Finished at $(date) ---" >> "$LOG"
