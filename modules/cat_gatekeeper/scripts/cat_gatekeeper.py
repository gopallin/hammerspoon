#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime
from subprocess import run, PIPE

DATA_FILE = os.path.expanduser("~/.hammerspoon/modules/cat_gatekeeper/data/usage.json")
DAILY_LIMIT = 40 * 60  # 40 minutes

def get_active_app_bundle_id():
    """Get the Bundle ID of the currently active application."""
    try:
        result = run(
            ["osascript", "-e", "tell application \"System Events\" to get bundle identifier of (first application process whose frontmost is true)"],
            stdout=PIPE,
            stderr=PIPE,
            text=True,
            timeout=1
        )
        bundle_id = result.stdout.strip()
        return bundle_id if bundle_id else None
    except Exception as e:
        print(f"Error getting active app: {e}", file=sys.stderr)
        return None

def get_app_name(bundle_id):
    """Get app name from bundle ID."""
    try:
        result = run(
            ["mdls", "-name", "kMDItemDisplayName", "-r", f"/Applications/*/{bundle_id}"],
            stdout=PIPE,
            stderr=PIPE,
            text=True,
            timeout=1
        )
        app_name = result.stdout.strip()
        return app_name if app_name else bundle_id
    except Exception:
        return bundle_id

def load_usage_data():
    """Load usage data from JSON file."""
    if not os.path.exists(DATA_FILE):
        return {}

    try:
        with open(DATA_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading usage data: {e}", file=sys.stderr)
        return {}

def save_usage_data(data):
    """Save usage data to JSON file."""
    os.makedirs(os.path.dirname(DATA_FILE), exist_ok=True)
    try:
        with open(DATA_FILE, 'w') as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        print(f"Error saving usage data: {e}", file=sys.stderr)

def get_today_key():
    """Get today's date as key (YYYY-MM-DD)."""
    return datetime.now().strftime("%Y-%m-%d")

def update_usage(bundle_id, duration):
    """Update usage for an app."""
    data = load_usage_data()
    today = get_today_key()

    if today not in data:
        data[today] = {}

    if bundle_id not in data[today]:
        data[today][bundle_id] = {"duration": 0, "name": get_app_name(bundle_id)}

    data[today][bundle_id]["duration"] += duration
    save_usage_data(data)

def get_daily_total():
    """Get total usage for today."""
    data = load_usage_data()
    today = get_today_key()

    if today not in data:
        return 0

    total = sum(app["duration"] for app in data[today].values() if isinstance(app, dict))
    return total

def is_limit_exceeded():
    """Check if daily limit is exceeded."""
    return get_daily_total() >= DAILY_LIMIT

def get_status():
    """Get current status."""
    total = get_daily_total()
    exceeded = total >= DAILY_LIMIT

    return {
        "total_seconds": total,
        "limit_seconds": DAILY_LIMIT,
        "exceeded": exceeded,
        "today": get_today_key()
    }

def main():
    if len(sys.argv) < 2:
        print(json.dumps(get_status()))
        return

    command = sys.argv[1]

    if command == "status":
        print(json.dumps(get_status()))
    elif command == "track" and len(sys.argv) >= 4:
        bundle_id = sys.argv[2]
        duration = int(sys.argv[3])
        update_usage(bundle_id, duration)
        print(json.dumps(get_status()))
    else:
        print("Usage: cat_gatekeeper.py [status|track BUNDLE_ID DURATION]", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
