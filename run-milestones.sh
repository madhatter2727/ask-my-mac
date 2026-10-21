#!/bin/bash
cd "$(dirname "$0")"
for m in "$@"; do
  echo "=== $m start $(date +%T)" >> milestones.log
  timeout -k 30 2700 /home/box/.local/bin/grok -m grok-4.7 --effort xhigh --permission-mode bypassPermissions --always-approve --max-turns 40 --output-format streaming-messages-json --include-partial-messages --prompt-file $m.md > $m.jsonl 2>&1 < /dev/null
  echo "=== $m end $? $(date +%T)" >> milestones.log
done
