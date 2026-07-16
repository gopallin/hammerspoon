#!/bin/bash

# Repairs the macOS charge-limit wedge (must run as root).
#
# Why: after the Friday "Charge Mac To 100" shortcut runs, the temporary
# override expires next morning at 06:00. If the Mac is asleep at that
# moment, PowerUIAgent's restore path can fail and leave MCLFeatureState=0
# in root's com.apple.smartcharging.topoffprotection domain. From then on
# System Settings can only change the target value (mclLimitValue) but can
# never re-enable the feature flag, so the 80% charge limit silently stops
# working. The only fix (verified 2026-07-16) is rewriting the flag and
# restarting PowerUIAgent. The saved target value survives, so nothing else
# needs to be restored.
#
# Install (root LaunchDaemon — NOT managed by the Hammerspoon launchd_manager,
# which only handles user LaunchAgents):
#   sudo cp restore_charge_limit.sh /usr/local/bin/
#   sudo chown root:wheel /usr/local/bin/restore_charge_limit.sh
#   sudo cp com.user.restore-charge-limit.plist /Library/LaunchDaemons/
#   sudo chown root:wheel /Library/LaunchDaemons/com.user.restore-charge-limit.plist
#   sudo launchctl load /Library/LaunchDaemons/com.user.restore-charge-limit.plist

DOMAIN="com.apple.smartcharging.topoffprotection"

STATE=$(defaults read "$DOMAIN" MCLFeatureState 2>/dev/null || echo "missing")

if [ "$STATE" = "1" ]; then
    echo "MCLFeatureState=1, charge limit healthy, nothing to do at $(date)"
    exit 0
fi

echo "MCLFeatureState=$STATE, restoring to 1 at $(date)"
defaults write "$DOMAIN" MCLFeatureState -int 1

PID=$(pgrep -x PowerUIAgent)
if [ -n "$PID" ]; then
    kill -9 "$PID"
    echo "killed PowerUIAgent (pid $PID), launchd respawns it on demand"
else
    echo "PowerUIAgent not running, new state picked up on next spawn"
fi
