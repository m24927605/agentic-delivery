#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Doctor on a clean checkout
agentic doctor || true   # may fail if validators are strict — informational

# Init a planning run
RUN_ID=cli-smoke agentic init "smoke test" --goal-file cli/tests/smoke/fixtures/goal.md || \
  scripts/init-agentic-run.sh --goal-file cli/tests/smoke/fixtures/goal.md
agentic --run-id cli-smoke status > /tmp/agentic-status.txt
cat /tmp/agentic-status.txt
grep -q cli-smoke /tmp/agentic-status.txt

# JSON envelope
agentic --json --run-id cli-smoke status | python -c '
import json, sys
p = json.load(sys.stdin)
assert p["_schema"] == "agentic.cli/v1", p
assert p["run"]["id"] == "cli-smoke", p
print("ok")
'

# raw escape hatch
agentic raw validate-agentic-system.sh || true

echo "smoke ok"
