#!/bin/bash
# Check for new Burrow messages since last check.
# Reads daemon.jsonl, outputs only new message lines since last offset.
# Usage: ./check-messages.sh [--reset]

JSONL_FILE="$HOME/.burrow/daemon.jsonl"
OFFSET_FILE="$HOME/.burrow/.daemon-offset"

if [ ! -f "$JSONL_FILE" ]; then
  echo "No daemon log file found. Is burrow daemon running?"
  exit 0
fi

if [ "$1" = "--reset" ]; then
  wc -l < "$JSONL_FILE" > "$OFFSET_FILE"
  echo "Offset reset to $(cat "$OFFSET_FILE")"
  exit 0
fi

# Get last read offset
LAST_OFFSET=0
if [ -f "$OFFSET_FILE" ]; then
  LAST_OFFSET=$(cat "$OFFSET_FILE")
fi

TOTAL_LINES=$(wc -l < "$JSONL_FILE")

if [ "$TOTAL_LINES" -le "$LAST_OFFSET" ]; then
  # No new lines
  exit 0
fi

# Extract new message lines (skip status lines)
tail -n +"$((LAST_OFFSET + 1))" "$JSONL_FILE" | jq -r 'select(.type == "message") | "[\(.groupName)] \(.senderPubkey[0:8])...: \(.content)"'

# Update offset
echo "$TOTAL_LINES" > "$OFFSET_FILE"
