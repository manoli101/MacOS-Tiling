#!/usr/bin/env bash
# Restart MacOSTiling WITHOUT rebuilding.
# Use this for quick restarts during testing — no build = no binary change = permission stays.
pkill -f MacOSTiling 2>/dev/null || true
sleep 0.3
open /Applications/MacOSTiling.app
echo "✅ MacOSTiling restarted."
